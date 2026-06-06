local json = require("libs/dkjson")

NPCBehaviorSystem = {}

-- =============================================================================
-- CONFIG
-- =============================================================================

NPCBehaviorSystem.apiURL = "http://localhost:8001/generate"

-- =============================================================================
-- STATE
-- =============================================================================

NPCBehaviorSystem.thread         = nil
NPCBehaviorSystem.jobsChannel    = nil
NPCBehaviorSystem.resultsChannel = nil
NPCBehaviorSystem.pendingJobs    = {}
NPCBehaviorSystem.nextJobID      = 1

-- generated schedules per npc, keyed by npcID
-- stores { goal = "...", steps = { "MOVE(sarah, ...)", ... } }
NPCBehaviorSystem.schedules = {}

-- queue of NPC IDs waiting to be generated; processed FIFO, one at a time
NPCBehaviorSystem.queue = {}

-- pending re-queue requests with cooldowns
NPCBehaviorSystem.pendingRequeues = {}

-- cooldown durations (seconds)
NPCBehaviorSystem.requeueCooldownComplete = 8
NPCBehaviorSystem.requeueCooldownFailed   = 12

-- =============================================================================
-- THREAD LIFECYCLE
-- =============================================================================

function NPCBehaviorSystem:StartWorker()
  if self.thread ~= nil then return end
  print("NPCBehaviorSystem: starting worker...")
  self.pendingJobs    = self.pendingJobs or {}
  self.nextJobID      = self.nextJobID or 1
  self.queue          = self.queue or {}
  self.jobsChannel    = love.thread.getChannel("npc_jobs")
  self.resultsChannel = love.thread.getChannel("npc_results")
  print("NPCBehaviorSystem: channels acquired")
  self.thread = love.thread.newThread("NPCBehaviorWorker.lua")
  print("NPCBehaviorSystem: thread object created")
  self.thread:start()
  print("NPCBehaviorSystem: thread:start() called")
end

function NPCBehaviorSystem:StopWorker()
  if self.thread == nil then return end
  self.jobsChannel:push("shutdown")
  self.thread:wait()
  self.thread         = nil
  self.jobsChannel    = nil
  self.resultsChannel = nil
  print("NPCBehaviorSystem: worker thread stopped")
end

function NPCBehaviorSystem:Load()
  self:StartWorker()
  -- when any NPC's schedule ends, queue them up for a fresh one
  NPCScheduler:OnScheduleEnd(function(npcID, finalState)
    -- skip if game is over
    if EndGame then return end
    local cooldown = (finalState == "failed")
      and self.requeueCooldownFailed
      or  self.requeueCooldownComplete
    print("NPCBehaviorSystem: " .. npcID .. " schedule "
      .. finalState .. ", scheduling regen in " .. cooldown .. "s")
    self:EnqueueDelayed(npcID, cooldown)
  end)
end

-- =============================================================================
-- CHARACTER LOOKUP
-- =============================================================================

-- find character description in QuestSystem's loaded characters list
function NPCBehaviorSystem:GetCharacterDescription(npcID)
  if QuestSystem == nil or QuestSystem.characters == nil then
    print("NPCBehaviorSystem: QuestSystem.characters not loaded")
    return nil
  end
  for _, char in ipairs(QuestSystem.characters) do
    if char.id == npcID then
      return char
    end
  end
  return nil
end

-- =============================================================================
-- WORLD STATE
-- =============================================================================

function NPCBehaviorSystem:GetLiveWorldState()
  local fullJSON = WorldState:ToJSON()
  local decoded, _, err = json.decode(fullJSON)
  if err or decoded == nil then
    print("NPCBehaviorSystem: failed to decode live world state: " .. tostring(err))
    return nil
  end
  return decoded.world_state
end

-- =============================================================================
-- QUEUE API
-- =============================================================================

-- Enqueue a single NPC for generation. The schedule will be generated and
-- started automatically when its turn comes up. If the NPC is already in
-- the queue or has a pending request, the call is a no-op.
function NPCBehaviorSystem:Enqueue(npcID)
  -- skip if already pending
  for _, p in pairs(self.pendingJobs) do
    if p.npcID == npcID then
      print("NPCBehaviorSystem: " .. npcID .. " already in flight, skipping")
      return
    end
  end
  -- skip if already queued
  for _, q in ipairs(self.queue) do
    if q == npcID then
      print("NPCBehaviorSystem: " .. npcID .. " already queued, skipping")
      return
    end
  end
  table.insert(self.queue, npcID)
  print("NPCBehaviorSystem: enqueued " .. npcID
    .. " (queue length: " .. #self.queue .. ")")
end

-- Enqueue every NPC the system knows about. Called once at game start.
function NPCBehaviorSystem:QueueAll()
  if NPCManager == nil or NPCManager.npcs == nil then
    print("NPCBehaviorSystem: NPCManager not loaded, cannot queue")
    return
  end
  local count = 0
  for _, npc in ipairs(NPCManager.npcs) do
    -- only queue NPCs that have a character description; otherwise the LLM
    -- has nothing to plan around
    if self:GetCharacterDescription(npc.npcID) ~= nil then
      self:Enqueue(npc.npcID)
      count = count + 1
    else
      print("NPCBehaviorSystem: skipping " .. npc.npcID
        .. " (no character description)")
    end
  end
  print("NPCBehaviorSystem: QueueAll done, " .. count .. " NPCs queued")
end

function NPCBehaviorSystem:GetQueueLength()
  return #self.queue
end

function NPCBehaviorSystem:HasInFlight()
  for _ in pairs(self.pendingJobs) do return true end
  return false
end

-- Schedule an NPC to be re-queued after a delay. Used by the regeneration
-- listener so an NPC whose schedule just ended doesn't immediately get a
-- new plan based on stale world state.
function NPCBehaviorSystem:EnqueueDelayed(npcID, delay)
  -- replace any existing pending re-queue for this NPC
  for i, p in ipairs(self.pendingRequeues) do
    if p.npcID == npcID then
      table.remove(self.pendingRequeues, i)
      break
    end
  end
  table.insert(self.pendingRequeues, {
    npcID = npcID,
    timer = delay or 5
  })
  print("NPCBehaviorSystem: " .. npcID
    .. " will be re-queued in " .. (delay or 5) .. "s")
end

-- =============================================================================
-- DISPATCH (internal)
-- =============================================================================

-- Dispatches a single NPC's generation request to the worker.
-- Internal: called by Update when the queue moves forward.
-- Returns true if dispatched, false on any setup failure.
function NPCBehaviorSystem:Dispatch(npcID, callback)
  local character = self:GetCharacterDescription(npcID)
  if character == nil then
    print("NPCBehaviorSystem: unknown npc id: " .. tostring(npcID))
    if callback then callback(nil, "unknown npc id: " .. tostring(npcID)) end
    return false
  end

  if QuestSystem == nil
     or QuestSystem.actionLibrary == nil
     or QuestSystem.worldRules    == nil then
    print("NPCBehaviorSystem: action_library or world_rules not loaded")
    if callback then
      callback(nil, "action_library or world_rules not loaded")
    end
    return false
  end

  if self.thread == nil then
    print("NPCBehaviorSystem: worker not running")
    if callback then callback(nil, "worker not running") end
    return false
  end

  local worldState = self:GetLiveWorldState()
  if worldState == nil then
    if callback then callback(nil, "failed to extract world state") end
    return false
  end

  local body = json.encode({
    npc_name              = npcID,
    character_description = character,
    world_state           = worldState,
    world_rules           = QuestSystem:GetWorldRulesFor("npc"),
    action_library        = QuestSystem:GetActionLibraryFor("npc")
  })

  local jobID = self.nextJobID
  self.nextJobID = jobID + 1

  self.pendingJobs[jobID] = {
    npcID     = npcID,
    callback  = callback,
    startTime = love.timer.getTime()
  }

  self.jobsChannel:push({
    jobID = jobID,
    url   = self.apiURL,
    body  = body
  })

  print("NPCBehaviorSystem: dispatched job " .. jobID
    .. " for npc " .. npcID
    .. " (" .. #body .. " bytes)")
  return true
end

-- =============================================================================
-- PUBLIC GENERATION API
-- =============================================================================

-- One-off generation that bypasses the queue. Used by the manual test key
-- and for any direct call. Goes ahead of any queued requests.
function NPCBehaviorSystem:GenerateSchedule(npcID, callback)
  return self:Dispatch(npcID, callback)
end

function NPCBehaviorSystem:Update(dt)
  -- drain pending re-queues
  if self.pendingRequeues and #self.pendingRequeues > 0 then
    local readyToEnqueue = {}
    for i, p in ipairs(self.pendingRequeues) do
      p.timer = p.timer - dt
      if p.timer <= 0 then
        table.insert(readyToEnqueue, i)
      end
    end
    -- iterate in reverse so removals don't shift indices
    for i = #readyToEnqueue, 1, -1 do
      local idx = readyToEnqueue[i]
      local p   = self.pendingRequeues[idx]
      table.remove(self.pendingRequeues, idx)
      self:Enqueue(p.npcID)
    end
  end

  if self.thread == nil then return end

  -- check if the worker thread died
  local threadErr = self.thread:getError()
  if threadErr ~= nil then
    print("NPCBehaviorSystem: WORKER THREAD CRASHED")
    print(threadErr)
    for jobID, pending in pairs(self.pendingJobs) do
      if pending.callback then
        pending.callback(nil, "worker thread crashed: " .. threadErr)
      end
    end
    self.pendingJobs = {}
    self.queue       = {}
    self.thread = nil
    return
  end

  if self.resultsChannel == nil then return end

  while true do
    local result = self.resultsChannel:pop()
    if result == nil then break end

    local pending = self.pendingJobs[result.jobID]
    if pending == nil then
      print("NPCBehaviorSystem: received result for unknown job "
        .. tostring(result.jobID))
    else
      local elapsed = love.timer.getTime() - pending.startTime
      print(string.format("NPCBehaviorSystem: job %d (%s) returned in %.2fs",
        result.jobID, pending.npcID, elapsed))

      if result.ok then
        local schedule = result.data and result.data.schedule
        if schedule then
          self.schedules[pending.npcID] = schedule
        end
        if pending.callback then pending.callback(schedule, nil) end
      else
        print("NPCBehaviorSystem: job " .. result.jobID .. " failed: "
          .. tostring(result.error))
        if result.response then
          print("Response: " .. tostring(result.response))
        end
        if pending.callback then pending.callback(nil, result.error) end
      end

      self.pendingJobs[result.jobID] = nil
    end
  end

  -- pump the queue: if nothing is in flight and we have queued NPCs,
  -- dispatch the next one
  if not self:HasInFlight() and #self.queue > 0 then
    local nextID = table.remove(self.queue, 1)
    print("NPCBehaviorSystem: dequeuing " .. nextID
      .. " (" .. #self.queue .. " remaining)")
    self:Dispatch(nextID, function(schedule, err)
      if err then
        print("NPCBehaviorSystem: queued generation failed for "
          .. nextID .. ": " .. err)
        return
      end
      if schedule == nil then
        print("NPCBehaviorSystem: queued generation for " .. nextID
          .. " returned no schedule")
        return
      end
      print("NPCBehaviorSystem: auto-starting schedule for " .. nextID)
      NPCScheduler:Start(nextID, schedule)
    end)
  end
end

function NPCBehaviorSystem:IsGenerating()
  if self.pendingJobs == nil then return false end
  for _ in pairs(self.pendingJobs) do return true end
  return false
end

function NPCBehaviorSystem:GetSchedule(npcID)
  return self.schedules[npcID]
end

function NPCBehaviorSystem:DumpSchedule(npcID)
  local s = self.schedules[npcID]
  if s == nil then
    print("NPCBehaviorSystem: no schedule for " .. tostring(npcID))
    return
  end
  print("=== Schedule for " .. npcID .. " ===")
  print("Goal: " .. tostring(s.goal))
  print("Steps:")
  for i, step in ipairs(s.steps or {}) do
    print(string.format("  %d. %s", i, step))
  end
  print("===")
end