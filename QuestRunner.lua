QuestRunner = {}

QuestRunner.chapter        = nil
QuestRunner.goals          = {}    -- collapsed goals derived from chapter steps
QuestRunner.currentGoalIdx = 0     -- 0 = not started; 1..#goals = active
QuestRunner.completed      = false
QuestRunner.talkFlags      = {}    -- talkFlags[stepNum] = true when player completed a TALK
QuestRunner.checkTimer     = 0     -- throttle world-state checks
QuestRunner.panelVisible = true

-- ordered list of chapter IDs. when the current chapter completes,
-- the next one in this list is generated. nil means no more chapters.
QuestRunner.chapterSequence = { "C1", "C2", "C3", "C4", "C5" }
QuestRunner.currentChapterID = nil

-- =============================================================================
-- GOAL CONSTRUCTION
-- =============================================================================

-- collapse runs of consecutive MOVE steps into a single goal whose destination
-- is the final MOVE's "to". non-MOVE steps each become their own goal.
function QuestRunner:BuildGoals(chapter)
  local goals = {}
  local i = 1
  local allSteps = {}

  -- flatten all quest steps in order
  for _, quest in ipairs(chapter.quests or {}) do
    for _, step in ipairs(quest.steps or {}) do
      step._questID    = quest.quest_id
      step._questTitle = quest.quest_title
      table.insert(allSteps, step)
    end
  end

  while i <= #allSteps do
    local step = allSteps[i]

    if step.action == "MOVE" then
      -- collect run of consecutive MOVEs
      local runStart = i
      local runEnd   = i
      while runEnd + 1 <= #allSteps and allSteps[runEnd + 1].action == "MOVE" do
        runEnd = runEnd + 1
      end

      local lastMove = allSteps[runEnd]
      local dest     = (lastMove.parameters and lastMove.parameters.to)
                    or lastMove.place
                    or "unknown"
      table.insert(goals, {
        kind        = "MOVE",
        description = "Go to the " .. self:PlaceName(dest),
        destination = dest,
        coveredSteps = { from = allSteps[runStart].step, to = lastMove.step },
        questTitle  = step._questTitle
      })
      i = runEnd + 1

    else
      table.insert(goals, self:DescribeStep(step))
      i = i + 1
    end
  end

  return goals
end

-- builds a goal entry for a non-MOVE step
function QuestRunner:DescribeStep(step)
  local action = step.action
  local goal = {
    kind        = action,
    step        = step,
    coveredSteps = { from = step.step, to = step.step },
    questTitle  = step._questTitle
  }

  if action == "TALK" then
    local target = step.target or (step.parameters and step.parameters.target) or "someone"
    goal.description = "Talk to " .. self:PrettyName(target)
    goal.target      = target

  elseif action == "PICKUP" then
    local item = step.item or (step.parameters and step.parameters.item) or "an item"
    local place = step.place or (step.parameters and step.parameters.place)
    goal.description = "Pick up the " .. self:ItemName(item)
      .. (place and (" in the " .. self:PlaceName(place)) or "")
    goal.item = item

  elseif action == "UNLOCK" then
    local place = step.target_place or (step.parameters and step.parameters.target_place)
                or step.place
    goal.description = "Unlock the " .. (self:PlaceName(place) or "door")
    goal.targetPlace = place

  elseif action == "TURN_POWER_ON" then
    local place = step.target_place or (step.parameters and step.parameters.target_place)
                or "laboratory"
    goal.description = "Restore power to the " .. self:PlaceName(place)
    goal.targetPlace = place

  elseif action == "FORTIFY" then
    -- per action library: parameters are actor, wood_item, place
    local place = (step.parameters and step.parameters.place)
              or step.place
    if place then
      goal.description = "Fortify the " .. self:PlaceName(place)
      goal.targetPlace = place
    else
      -- shouldn't happen with valid LLM output, but handle gracefully
      goal.description = "Fortify your current location"
      goal.targetPlace = nil
    end

  elseif action == "SYNTHESIZE_CURE" then
    goal.description = "Synthesize the antidote in the Laboratory"

  elseif action == "USE_CURE" then
    local target = step.target or (step.parameters and step.parameters.target) or "the patient"
    goal.description = "Use the antidote on " .. self:PrettyName(target)
    goal.target = target

  elseif action == "GIVE_ITEM" then
    local target = step.target or (step.parameters and step.parameters.target) or "someone"
    local item   = step.item   or (step.parameters and step.parameters.item)   or "the item"
    goal.description = "Give the " .. self:ItemName(item) .. " to " .. self:PrettyName(target)
    goal.target = target
    goal.item   = item

  elseif action == "REPAIR" then
    local target = step.target or (step.parameters and step.parameters.target) or "the object"
    goal.description = "Repair the " .. target
    goal.repairTarget = target

  else
    goal.description = action .. " (unhandled)"
  end

  return goal
end

function QuestRunner:PrettyName(npcID)
  local def = NPCDefinitions[npcID]
  if def and def.displayName then return def.displayName end
  return tostring(npcID)
end

function QuestRunner:ItemName(label)
  -- labels are like "fuse_1", "wood_2"; strip the suffix
  local base = label:match("^(.-)_%d+$") or label
  local def  = ItemDefinitions[base]
  if def and def.displayName then return def.displayName end
  return base
end

function QuestRunner:PlaceName(placeID)
  if placeID == nil then return "unknown" end
  local def = WorldState:GetPlaceDef(placeID)
  if def and def.displayName then return def.displayName end
  return placeID
end

-- =============================================================================
-- LIFECYCLE
-- =============================================================================

function QuestRunner:Start(chapter)
  self.chapter        = chapter
  self.currentChapterID = chapter.chapter_id
  self.goals          = self:BuildGoals(chapter)
  self.currentGoalIdx = 1
  self.completed      = false
  self.talkFlags      = {}
  self.checkTimer     = 0
  self.panelVisible    = false

  print("QuestRunner: started chapter '" .. tostring(chapter.chapter_title) .. "'")
  print("QuestRunner: " .. #self.goals .. " goals after collapsing")
  for i, g in ipairs(self.goals) do
    print(string.format("  %d. %s", i, g.description))
  end

  if #self.goals == 0 then
    self.completed = true
  end
  MessageQueue:Push("New chapter started: " .. tostring(chapter.chapter_title), 4, 0.3, function() self.panelVisible = true end)
end

function QuestRunner:Reset()
  self.chapter        = nil
  self.goals          = {}
  self.currentGoalIdx = 0
  self.completed      = false
  self.talkFlags      = {}
end

function QuestRunner:GetActiveGoal()
  if self.currentGoalIdx == 0 or self.currentGoalIdx > #self.goals then return nil end
  return self.goals[self.currentGoalIdx]
end

function QuestRunner:GetNextChapterID()
  if self.currentChapterID == nil then return nil end
  for i, id in ipairs(self.chapterSequence) do
    if id == self.currentChapterID then
      return self.chapterSequence[i + 1]
    end
  end
  return nil
end

function QuestRunner:GetGoals()         return self.goals          end
function QuestRunner:GetCurrentIndex()  return self.currentGoalIdx end
function QuestRunner:IsActive()         return self.chapter ~= nil and not self.completed end

-- =============================================================================
-- COMPLETION CHECKS
-- =============================================================================

function QuestRunner:Update(dt)
  if not self:IsActive() then
    return
  end  

  -- throttle: check 4x per second instead of every frame
  self.checkTimer = self.checkTimer + dt
  if self.checkTimer < 0.25 then return end
  self.checkTimer = 0

  -- advance through any contiguous block of completed goals
  while self.currentGoalIdx <= #self.goals do
    local goal = self.goals[self.currentGoalIdx]
    if self:IsGoalComplete(goal) then
        print("QuestRunner: goal " .. self.currentGoalIdx .. " complete: " .. goal.description)

        local justFinished = goal
        self.currentGoalIdx = self.currentGoalIdx + 1
        local next = self.goals[self.currentGoalIdx]

        -- detect quest transition: did we just leave one quest for another?
        local crossedQuest = next == nil
                        or next.questTitle ~= justFinished.questTitle

        if crossedQuest then
            MessageQueue:Push("Quest complete: " .. justFinished.questTitle, 3)
            -- hide the goal panel during the transition
            self.panelVisible = false
        end

        if self.currentGoalIdx > #self.goals then
            self.completed = true
            MessageQueue:Push("Chapter complete: " .. tostring(self.chapter.chapter_title), 5)
            print("QuestRunner: chapter complete")
            -- kick off next chapter generation if one exists
            local nextID = self:GetNextChapterID()
            if nextID then
                print("QuestRunner: triggering generation of next chapter " .. nextID)
                QuestSystem:GenerateChapter(nextID, function(data, err)
                if err then
                    MessageQueue:Push("Failed to generate next chapter: " .. err, 5, 0)
                else
                    QuestRunner:Start(data)
                end
                end)
            else
                MessageQueue:Push("All chapters complete. The story ends here.", 5, 0)
            end
            return
        end

        if crossedQuest then
            MessageQueue:Push("New quest started: " .. next.questTitle, 3, nil, function()
              self.panelVisible = true
            end)
            --self:QueueMessage("Goal: " .. next.description, 4, 0)
        --else
            --self:QueueMessage("Goal: " .. next.description, 4, 0)
        end
    else
        break
    end
  end
end

function QuestRunner:IsGoalComplete(goal)
  if goal.kind == "MOVE" then
    local place = WorldState:GetPlaceForPosition(
      level.levelName, math.ceil(player:GetX()), math.ceil(player:GetY()))
    return place == goal.destination

  elseif goal.kind == "TALK" then
    local stepNum = goal.coveredSteps.from
    return self.talkFlags[stepNum] == true

  elseif goal.kind == "PICKUP" then
    -- extract base type from labelled item id (e.g. "wood_2" -> "wood")
    local baseType = goal.item:match("^(.-)_%d+$") or goal.item
    local def = ItemDefinitions[baseType]

    if def and def.fungible then
      -- fungible: any instance of the type satisfies the goal
      for _, invItem in ipairs(player.itens) do
        if invItem.defID == baseType then return true end
      end
      -- also accept if a fungible item of this type was consumed
      -- (e.g. player picked up wood and immediately fortified with it)
      for _, instanceID in ipairs(ConsumedItems) do
        local consumedDef = WorldState:GetLabelFromInstanceID(instanceID)
        if consumedDef then
          local consumedBase = consumedDef:match("^(.-)_%d+$") or consumedDef
          if consumedBase == baseType then return true end
        end
      end
      return false
    end

    -- non-fungible: existing behaviour, must be the specific instance
    local instanceID = WorldState:GetInstanceIDFromLabel(goal.item)
    if instanceID == nil then return false end
    for _, invItem in ipairs(player.itens) do
      if invItem.instanceID == instanceID then return true end
    end
    if ItemWasConsumed(instanceID) then return true end
    return false

  elseif goal.kind == "UNLOCK" then
    return WorldState:HasPlaceCondition(goal.targetPlace, "unlocked")

  elseif goal.kind == "TURN_POWER_ON" then
    return WorldState:HasPlaceCondition(goal.targetPlace, "power_on")

  elseif goal.kind == "FORTIFY" then
    if goal.targetPlace then
      return WorldState:HasPlaceCondition(goal.targetPlace, "fortified")
    end
    -- no specific place requested: complete when player's current place is fortified
    local place = WorldState:GetPlaceForPosition(
      level.levelName, math.ceil(player:GetX()), math.ceil(player:GetY()))
    return WorldState:HasPlaceCondition(place, "fortified")

  elseif goal.kind == "SYNTHESIZE_CURE" then
    return player:HasItem("antidote")
        or self:AnyNPCHasItem("antidote")

  elseif goal.kind == "USE_CURE" then
    local npc = NPCManager:GetNPCByID(goal.target)
    if npc == nil then return false end
    return not npc:HasCondition("infected")

  elseif goal.kind == "GIVE_ITEM" then
    local npc = NPCManager:GetNPCByID(goal.target)
    if npc == nil then return false end
    local base = goal.item:match("^(.-)_%d+$") or goal.item
    return npc:HasItem(base)

  elseif goal.kind == "REPAIR" then
    return WorldObjects[goal.repairTarget] == "fixed"
  end

  return false
end

function QuestRunner:AnyNPCHasItem(defID)
  for _, npc in ipairs(NPCManager.npcs) do
    if npc:HasItem(defID) then return true end
  end
  return false
end

-- =============================================================================
-- TALK HANDLING
-- =============================================================================

-- called by main.lua when the player presses Enter and an active TALK goal
-- is targeting an adjacent NPC. opens a dialogue based on the step's
-- dialogue_content array.
function QuestRunner:TryStartTalk()
  local goal = self:GetActiveGoal()
  if goal == nil or goal.kind ~= "TALK" then return false end

  local target = goal.target
  local npc = self:FindAdjacentNPC(target)
  if npc == nil then return false end

  local dialogueContent = goal.step
    and goal.step.parameters
    and goal.step.parameters.dialogue_content

  if dialogueContent == nil or #dialogueContent == 0 then
    -- no scripted dialogue, just mark complete
    self.talkFlags[goal.coveredSteps.from] = true
    return true
  end

  QuestDialog:Open(dialogueContent, function()
    self.talkFlags[goal.coveredSteps.from] = true
  end)
  return true
end

function QuestRunner:FindAdjacentNPC(npcID)
  local px = math.ceil(player:GetX())
  local py = math.ceil(player:GetY())
  local npcs = NPCManager:GetNPCsForLevel(level.levelName)
  for _, npc in ipairs(npcs) do
    if npc.npcID == npcID then
      local nx = math.ceil(npc:GetX())
      local ny = math.ceil(npc:GetY())
      if math.abs(nx - px) <= 1 and math.abs(ny - py) <= 1 then
        return npc
      end
    end
  end
  return nil
end


