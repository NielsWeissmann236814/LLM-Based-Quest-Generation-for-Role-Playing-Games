local json   = require("libs/dkjson")
local http   = require("socket.http")
local ltn12  = require("ltn12")

QuestSystem = {}

-- =============================================================================
-- CONFIG
-- =============================================================================

QuestSystem.apiURL    = "http://localhost:8000/generate"
QuestSystem.dataPath  = "data/"   -- relative to LÖVE save/source dir

-- =============================================================================
-- STATE
-- =============================================================================

QuestSystem.chapters       = {}
QuestSystem.characters     = nil
QuestSystem.actionLibrary  = nil
QuestSystem.worldRules     = nil
QuestSystem.currentChapter = nil

QuestSystem.thread         = nil
QuestSystem.jobsChannel    = nil
QuestSystem.resultsChannel = nil
QuestSystem.pendingJobs    = {}
QuestSystem.nextJobID      = 1

-- =============================================================================
-- FILE LOADING
-- =============================================================================

local function readJSONFile(path)
  local contents, sizeOrErr = love.filesystem.read(path)
  if contents == nil then
    print("QuestSystem: failed to read " .. path .. " (" .. tostring(sizeOrErr) .. ")")
    return nil
  end
  local data, _, err = json.decode(contents)
  if err then
    print("QuestSystem: failed to parse JSON in " .. path .. ": " .. err)
    return nil
  end
  return data
end

function QuestSystem:LoadChapters()
  self.chapters = {}
  local data = readJSONFile(self.dataPath .. "chapters.json")
  if data == nil then
    print("QuestSystem: failed to load chapters")
    return
  end
  for _, chapter in ipairs(data) do
    if chapter.id then
      self.chapters[chapter.id] = chapter
      print("QuestSystem: loaded chapter " .. chapter.id)
    else
      print("QuestSystem: skipping chapter entry without id")
    end
  end
  print("QuestSystem: total chapters loaded: " .. self:CountChapters())
end

function QuestSystem:LoadCharacters()
  self.characters = readJSONFile(self.dataPath .. "characters.json")
  if self.characters then
    print("QuestSystem: loaded " .. #self.characters .. " characters")
  end
end

function QuestSystem:LoadSystemFiles()
  self.actionLibrary = readJSONFile(self.dataPath .. "action_library.json")
  if self.actionLibrary then
    print("QuestSystem: loaded action_library")
  end
  self.worldRules = readJSONFile(self.dataPath .. "world_rules.json")
  if self.worldRules then
    print("QuestSystem: loaded world_rules")
  end
end

function QuestSystem:Load()
  self:LoadChapters()
  self:LoadCharacters()
  self:LoadSystemFiles()
end

function QuestSystem:CountChapters()
  local n = 0
  for _ in pairs(self.chapters) do n = n + 1 end
  return n
end

-- =============================================================================
-- THREAD LIFECYCLE
-- =============================================================================

function QuestSystem:StartWorker()
  if self.thread ~= nil then return end
  print("QuestSystem: starting worker...")
  self.pendingJobs    = self.pendingJobs or {}    -- <<< add this
  self.nextJobID      = self.nextJobID or 1       -- <<< add this
  self.jobsChannel    = love.thread.getChannel("quest_jobs")
  self.resultsChannel = love.thread.getChannel("quest_results")
  print("QuestSystem: channels acquired")
  self.thread = love.thread.newThread("QuestWorker.lua")
  print("QuestSystem: thread object created")
  self.thread:start()
  print("QuestSystem: thread:start() called")
end

function QuestSystem:StopWorker()
  if self.thread == nil then return end
  self.jobsChannel:push("shutdown")
  self.thread:wait()
  self.thread        = nil
  self.jobsChannel   = nil
  self.resultsChannel = nil
  print("QuestSystem: worker thread stopped")
end

function QuestSystem:Load()
  self:LoadChapters()
  self:LoadCharacters()
  self:LoadSystemFiles()
  self:StartWorker()
end

-- =============================================================================
-- WORLD STATE
-- =============================================================================

function QuestSystem:GetLiveWorldState()
  local fullJSON = WorldState:ToJSON()
  local decoded, _, err = json.decode(fullJSON)
  if err or decoded == nil then
    print("QuestSystem: failed to decode live world state: " .. tostring(err))
    return nil
  end
  return decoded.world_state
end

-- =============================================================================
-- ASYNC GENERATION
-- =============================================================================

-- callback signature: function(chapterData, errorString)
-- on success: chapterData is the API response, errorString is nil
-- on failure: chapterData is nil, errorString is set
function QuestSystem:GenerateChapter(chapterID, callback)
  local chapter = self.chapters[chapterID]
  if chapter == nil then
    print("QuestSystem: unknown chapter id: " .. tostring(chapterID))
    if callback then callback(nil, "unknown chapter id") end
    return
  end
  if self.characters == nil or self.actionLibrary == nil or self.worldRules == nil then
    print("QuestSystem: required data not loaded")
    if callback then callback(nil, "required data not loaded") end
    return
  end
  if self.thread == nil then
    print("QuestSystem: worker not running")
    if callback then callback(nil, "worker not running") end
    return
  end

  local worldState = self:GetLiveWorldState()
  if worldState == nil then
    if callback then callback(nil, "failed to extract world state") end
    return
  end

  local body = json.encode({
    chapter           = chapter,
    characters        = self.characters,
    world_state       = worldState,
    action_library    = self:GetActionLibraryFor("player"),
    world_rules       = self:GetWorldRulesFor("player")
  })

  local jobID = self.nextJobID
  self.nextJobID = jobID + 1

  self.pendingJobs[jobID] = {
    chapterID = chapterID,
    callback  = callback,
    startTime = love.timer.getTime()
  }

  self.jobsChannel:push({
    jobID = jobID,
    url   = self.apiURL,
    body  = body
  })

  print("QuestSystem: dispatched job " .. jobID .. " for chapter " .. chapterID
    .. " (" .. #body .. " bytes)")
end

function QuestSystem:Update(dt)
  if self.thread == nil then return end

  -- check if the worker thread died
  local threadErr = self.thread:getError()
  if threadErr ~= nil then
    print("QuestSystem: WORKER THREAD CRASHED")
    print(threadErr)
    -- fail all pending jobs so callers know
    for jobID, pending in pairs(self.pendingJobs) do
      if pending.callback then
        pending.callback(nil, "worker thread crashed: " .. threadErr)
      end
    end
    self.pendingJobs = {}
    self.thread = nil   -- prevent repeat reporting
    return
  end

  if self.resultsChannel == nil then return end

  -- drain all completed jobs this frame
  while true do
    local result = self.resultsChannel:pop()
    if result == nil then break end

    local pending = self.pendingJobs[result.jobID]
    if pending == nil then
      print("QuestSystem: received result for unknown job " .. tostring(result.jobID))
    else
      local elapsed = love.timer.getTime() - pending.startTime
      print(string.format("QuestSystem: job %d returned in %.2fs",
        result.jobID, elapsed))

      if result.ok then
        self.currentChapter = result.data
        print("QuestSystem: chapter generated: "
          .. tostring(result.data.chapter_title))
        print("QuestSystem: quests: "
          .. (result.data.quests and #result.data.quests or 0))
        if result.data.dialogue_warnings
            and #result.data.dialogue_warnings > 0 then
          print("QuestSystem: dialogue warnings:")
          for _, w in ipairs(result.data.dialogue_warnings) do
            print("  - " .. w)
          end
        end
        if pending.callback then pending.callback(result.data, nil) end
      else
        print("QuestSystem: job " .. result.jobID .. " failed: "
          .. tostring(result.error))
        if result.response then
          print("Response: " .. tostring(result.response))
        end
        if pending.callback then pending.callback(nil, result.error) end
      end

      self.pendingJobs[result.jobID] = nil
    end
  end
end

function QuestSystem:IsGenerating()
  if self.pendingJobs == nil then return false end
  for _ in pairs(self.pendingJobs) do return true end
  return false
end

function QuestSystem:GetCurrentChapter()
  return self.currentChapter
end

function QuestSystem:DumpCurrentChapter()
  if self.currentChapter == nil then
    print("QuestSystem: no chapter generated yet")
    return
  end
  print(json.encode(self.currentChapter, { indent = true }))
end

function QuestSystem:GetActionLibraryFor(actorType)
  if self.actionLibrary == nil then return nil end
  local filtered = {}
  for _, action in ipairs(self.actionLibrary.action_library) do
    if action.actors then
      for _, a in ipairs(action.actors) do
        if a == actorType then
          table.insert(filtered, action)
          break
        end
      end
    end
  end
  return { action_library = filtered }
end

function QuestSystem:GetWorldRulesFor(actorType)
  if self.worldRules == nil then return nil end
  local filtered = {}
  for _, rule in ipairs(self.worldRules.world_rules) do
    if rule.actors then
      for _, a in ipairs(rule.actors) do
        if a == actorType then
          table.insert(filtered, rule)
          break
        end
      end
    end
  end
  return { world_rules = filtered }
end