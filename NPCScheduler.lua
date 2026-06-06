require "NPCDialog"

NPCScheduler = {}

NPCScheduler.listeners = {}
NPCScheduler.runners    = {}
NPCScheduler.checkTimer = 0

-- =============================================================================
-- PUBLIC API
-- =============================================================================

function NPCScheduler:Start(npcID, schedule)
  local npc = NPCManager:GetNPCByID(npcID)
  if npc == nil then
    print("NPCScheduler: unknown npc " .. tostring(npcID))
    return
  end
  if schedule == nil or schedule.steps == nil or #schedule.steps == 0 then
    print("NPCScheduler: empty schedule for " .. npcID)
    return
  end

  print("NPCScheduler: starting schedule for " .. npcID
    .. " (" .. #schedule.steps .. " steps)")
  print("  Goal: " .. tostring(schedule.goal))
  for i, s in ipairs(schedule.steps) do
    print(string.format("  %d. %s", i, s))
  end

  self.runners[npcID] = {
    npcID    = npcID,
    schedule = schedule,
    stepIdx  = 1,
    state    = "ready",
    current  = nil
  }
end

function NPCScheduler:Stop(npcID)
  self.runners[npcID] = nil
end

function NPCScheduler:IsActive(npcID)
  local r = self.runners[npcID]
  return r ~= nil and r.state ~= "complete" and r.state ~= "failed"
end

-- Abort the schedule with a contextual reaction line, then a generic
-- "I'll come up with something else" line. Schedule stops here -- the next
-- plan will be regenerated externally.
function NPCScheduler:Abort(runner, npc, reactionCategory, reactionVars)
  if reactionCategory and npc then
    npc:Say(NPCDialog:Pick(reactionCategory, reactionVars), 4)
  end
  -- short delay before the abandonment line, so they don't overlap
  -- (the balloon system shows whichever was set last; we just stack the
  -- abandonment line over the reaction. Keeping it simple.)
  if npc then
    -- queue the abandonment line so it shows after the first one fades.
    -- there's no real timer system for this, so we attach it to the runner
    -- and let Update spit it out a moment later.
    runner.pendingAbandonLine = {
      timer = 3.5,
      npc   = npc
    }
  end
  runner.state = "failed"
  print("NPCScheduler: " .. runner.npcID .. " schedule aborted")
  self:FireScheduleEnd(runner, "failed")
end

-- =============================================================================
-- UPDATE LOOP
-- =============================================================================

function NPCScheduler:Update(dt)
  -- handle pending abandonment lines (these run on real dt, not throttled)
  for _, runner in pairs(self.runners) do
    if runner.pendingAbandonLine then
      runner.pendingAbandonLine.timer = runner.pendingAbandonLine.timer - dt
      if runner.pendingAbandonLine.timer <= 0 then
        local npc = runner.pendingAbandonLine.npc
        if npc then
          npc:Say(NPCDialog:Pick("schedule_abandoned"), 4)
        end
        runner.pendingAbandonLine = nil
      end
    end
  end

  -- throttle to 4Hz, same as QuestRunner
  self.checkTimer = self.checkTimer + dt
  if self.checkTimer < 0.25 then return end
  self.checkTimer = 0

  for npcID, runner in pairs(self.runners) do
    if runner.state == "ready" then
      self:DispatchNext(runner)
    elseif runner.state == "dispatched" then
      if self:IsCurrentStepComplete(runner) then
        print("NPCScheduler: " .. npcID .. " step "
          .. runner.stepIdx .. " complete")
        runner.stepIdx = runner.stepIdx + 1
        runner.current = nil
        if runner.stepIdx > #runner.schedule.steps then
          runner.state = "complete"
          print("NPCScheduler: " .. npcID .. " schedule complete")
          self:FireScheduleEnd(runner, "complete")
        else
          runner.state = "ready"
        end
      end
    end
  end
end

-- =============================================================================
-- DISPATCH
-- =============================================================================

function NPCScheduler:DispatchNext(runner)
  local stepStr = runner.schedule.steps[runner.stepIdx]
  local parsed  = self:ParseStep(stepStr)

  local npc = NPCManager:GetNPCByID(runner.npcID)
  if npc == nil then
    runner.state = "failed"
    self:FireScheduleEnd(runner, "failed")
    return
  end

  if parsed == nil then
    print("NPCScheduler: " .. runner.npcID
      .. " could not parse step: " .. tostring(stepStr))
    self:Abort(runner, npc, "confused")
    return
  end

  print("NPCScheduler: " .. runner.npcID .. " dispatching step "
    .. runner.stepIdx .. ": " .. parsed.action
    .. "(" .. table.concat(parsed.args, ", ") .. ")")

  local ok = self:Dispatch(npc, parsed, runner)
  runner.current = parsed

  if not ok then
    -- Dispatch already issued the appropriate Say() and called Abort()
    return
  else
    runner.state = "dispatched"
  end
end


-- Finds a walkable tile immediately adjacent to (tx, ty) in the given level.
-- Returns nil, nil if nothing walkable is found within 1 tile (which means
-- the NPC will fall back to aiming at the original tile and stop short
-- via pathfinding).
function NPCScheduler:FindAdjacentWalkable(levelFile, tx, ty)
  local pathLevel = nil
  if levelFile == level.levelName then
    pathLevel = level
  else
    local ok, result = pcall(function()
      return level:LoadForPathfinding(levelFile)
    end)
    if ok then pathLevel = result end
  end

  if pathLevel == nil then return nil, nil end

  -- check the four cardinal neighbors; prefer the one closest to standard
  -- "in front of" positioning (down/up/left/right in that order)
  local offsets = {
    { x =  0, y =  1 },  -- below the target
    { x =  0, y = -1 },  -- above
    { x = -1, y =  0 },  -- left
    { x =  1, y =  0 }   -- right
  }
  for _, off in ipairs(offsets) do
    local nx = tx + off.x
    local ny = ty + off.y
    local tile = pathLevel:GetTile(nx, ny)
    if tile ~= nil and tile.properties.obstacle == nil then
      return nx, ny
    end
  end
  return nil, nil
end

-- Maps a parsed step to the corresponding NPCActions call.
-- Returns true if the action was successfully dispatched, false if the
-- schedule should be aborted. On false, the caller has already said
-- the appropriate line via Abort().
function NPCScheduler:Dispatch(npc, parsed, runner)
  local action = parsed.action
  local args   = parsed.args

  if action == "MOVE" then
    -- args: actor, from, to
    local toPlace = args[3]
    local placeDef = WorldState:GetPlaceDef(toPlace)
    if placeDef == nil then
      print("NPCScheduler: MOVE to unknown place " .. tostring(toPlace))
      self:Abort(runner, npc, "unknown_place")
      return false
    end

    -- already at the destination?
    local currentPlace = WorldState:GetPlaceForPosition(
      npc.levelFile, math.ceil(npc.x), math.ceil(npc.y))
    if currentPlace == toPlace then
      self:Abort(runner, npc, "already_at_destination")
      return false
    end

    local dx = placeDef.defaultX
    local dy = placeDef.defaultY
    if dx == nil or dy == nil then
      print("NPCScheduler: place " .. toPlace .. " has no defaultX/Y")
      self:Abort(runner, npc, "unknown_place")
      return false
    end

    -- delegate; NPCActions:Walk will detect locked-no-key situations and
    -- attach a failure reaction to the final journey step.
    local walkOk = NPCActions:Walk(npc, toPlace, dx, dy)
    if not walkOk then
      self:Abort(runner, npc, "no_route")
      return false
    end
    return true

  elseif action == "PICKUP" then
    -- args: actor, item, place
    local itemLabel = args[2]
    local place     = args[3]
    local instanceID = WorldState:GetInstanceIDFromLabel(itemLabel)
    if instanceID == nil then
      print("NPCScheduler: PICKUP unknown item label " .. tostring(itemLabel))
      self:Abort(runner, npc, "unknown_item")
      return false
    end

    -- Validate the destination place exists
    local placeDef = WorldState:GetPlaceDef(place)
    if placeDef == nil then
      print("NPCScheduler: PICKUP unknown place " .. tostring(place))
      self:Abort(runner, npc, "unknown_place")
      return false
    end

    -- find the item record
    local itemRecord = nil
    for _, item in ipairs(ItemManager.items) do
      if item.instanceID == instanceID then
        itemRecord = item
        break
      end
    end

    -- (a) Item already collected/consumed by someone else.
    -- Walk to the LLM-specified place; react with "item_gone" on arrival.
    if itemRecord == nil
       or ItemWasCollected(instanceID)
       or ItemWasConsumed(instanceID) then
      local walkOk = NPCActions:Walk(npc, place, placeDef.defaultX, placeDef.defaultY, {
        category = "item_gone",
        vars     = { item = NPCDialog:ItemDisplayName(itemLabel) }
      })
      if not walkOk then
        self:Abort(runner, npc, "no_route")
        return false
      end
      runner.abortAfterCurrent = true
      return true
    end

    -- (b) Item exists, but the LLM said the wrong place.
    -- Cross-check the item's actual location against `place`.
    local itemActualPlace = WorldState:GetPlaceForPosition(
      itemRecord.levelFile, itemRecord.x, itemRecord.y)
    if itemActualPlace ~= place then
      print("NPCScheduler: PICKUP place mismatch - "
        .. itemLabel .. " is at " .. tostring(itemActualPlace)
        .. " but LLM said " .. tostring(place))
      local walkOk = NPCActions:Walk(npc, place, placeDef.defaultX, placeDef.defaultY, {
        category = "item_not_here",
        vars     = { item = NPCDialog:ItemDisplayName(itemLabel) }
      })
      if not walkOk then
        self:Abort(runner, npc, "no_route")
        return false
      end
      runner.abortAfterCurrent = true
      return true
    end

    -- (c) Normal pickup. Mark the runner so completion detects pathfinding
    -- failures (i.e. the journey ends without the item being picked up).
    runner.expectingPickup = instanceID
    NPCActions:PickupItem(npc, instanceID, place, itemRecord.x, itemRecord.y)
    return true

  elseif action == "FORTIFY" then
    -- args: actor, wood_item, place
    local itemLabel = args[2]
    local place     = args[3]

    local placeDef = WorldState:GetPlaceDef(place)
    if placeDef == nil then
      self:Abort(runner, npc, "unknown_place")
      return false
    end

    -- exterior locations can't be fortified, period - react immediately
    -- (no point walking somewhere just to say you can't fortify it).
    if placeDef.type == "exterior" then
      self:Abort(runner, npc, "cant_fortify_outside")
      return false
    end

    -- Item label hallucinated? abort immediately.
    --if WorldState:GetInstanceIDFromLabel(itemLabel) == nil then
    --  self:Abort(runner, npc, "unknown_item")
    --  return false
    --end

    -- Walk to the place. On arrival, FortifyLocation will check if NPC
    -- has wood and if the place isn't already fortified.
    NPCActions:FortifyLocation(npc, "wood", place)
    return true

  elseif action == "WALK_AROUND" then
    -- args: actor, place
    local place = args[2]
    local placeDef = WorldState:GetPlaceDef(place)
    if placeDef == nil then
      self:Abort(runner, npc, "unknown_place")
      return false
    end

    parsed.wanderTotal = 4
    parsed.wanderDone  = 0
    local ok = NPCActions:WalkAround(npc, place)
    if ok then parsed.wanderDone = 1 end
    -- don't abort if wander couldn't start - just consider it done.
    -- IsCurrentStepComplete will short-circuit and we move on.
    return true

  elseif action == "TURN_POWER_ON" then
    -- args: actor, fuse_item, place, target_place
    local itemLabel   = args[2]
    local targetPlace = args[4] or "laboratory"

    -- power already on? walk-first reaction so the NPC arrives at the
    -- powerstation and sees for themselves.
    if WorldState:HasPlaceCondition(targetPlace, "power_on") then
      -- still walk them to the powerstation so the line plays in context
      local fuseDef = ItemDefinitions["fuse"]
      if fuseDef and fuseDef.useAt then
        local walkOk = NPCActions:Walk(npc, "powerstation",
          fuseDef.useAt.x, fuseDef.useAt.y, {
            category = "power_already_on"
          })
        if not walkOk then
          self:Abort(runner, npc, "no_route")
          return false
        end
        runner.abortAfterCurrent = true
        return true
      end
      -- no useAt info, fall back to immediate abort
      self:Abort(runner, npc, "power_already_on")
      return false
    end

    -- Item label hallucinated entirely? abort immediately.
    --if WorldState:GetInstanceIDFromLabel(itemLabel) == nil then
    --  self:Abort(runner, npc, "unknown_item")
    --  return false
    --end

    -- Walk to the power box. The NPC will check on arrival whether they
    -- have a fuse; if not, they'll react with the no-fuse line and the
    -- schedule aborts. If they do, the existing TurnPowerOn flow runs.
    NPCActions:TurnPowerOn(npc, "fuse")
    return true

  elseif action == "UNLOCK" then
    -- args: actor, key_item, target_place
    local itemLabel   = args[2]
    local targetPlace = args[3]

    local placeDef = WorldState:GetPlaceDef(targetPlace)
    if placeDef == nil then
      self:Abort(runner, npc, "unknown_place")
      return false
    end

    local keyDefID    = nil
    local instanceID  = WorldState:GetInstanceIDFromLabel(itemLabel)
    if instanceID then
      for _, invItem in ipairs(npc:GetInventory() or {}) do
        if invItem.instanceID == instanceID then
          keyDefID = invItem.defID
          break
        end
      end
    end

    NPCActions:Unlock(npc, keyDefID, targetPlace)
    return true
  elseif action == "SYNTHESIZE_CURE" then
    -- args: actor, place
    -- Most of this is decided on arrival - the NPC walks to the lab
    -- synthesis machine and reacts appropriately.

    -- Power not on yet? Walk-first reaction so the NPC arrives at the
    -- machine and sees for themselves.
    if not WorldState:HasPlaceCondition("laboratory", "power_on") then
      local sampleDef = ItemDefinitions["cure_sample"]
      if sampleDef and sampleDef.useAt then
        local walkOk = NPCActions:Walk(npc, "laboratory",
          sampleDef.useAt.x, sampleDef.useAt.y, {
            category = "no_power_synth"
          })
        if not walkOk then
          self:Abort(runner, npc, "no_route")
          return false
        end
        runner.abortAfterCurrent = true
        return true
      end
      self:Abort(runner, npc, "no_power_synth")
      return false
    end

    -- Power's on. Walk to the machine; ExecuteSynthesize will check on
    -- arrival whether the NPC has a sample and isn't already carrying
    -- an antidote.
    NPCActions:SynthesizeAntidote(npc)
    return true
  
  elseif action == "DROP" then
    -- args: actor, item, place
    local itemLabel = args[2]
    local place     = args[3]

    local placeDef = WorldState:GetPlaceDef(place)
    if placeDef == nil then
      self:Abort(runner, npc, "unknown_place")
      return false
    end

    -- Resolve the item's def ID if the label is valid; nil is fine here -
    -- ExecuteDrop will react with "no_item_to_drop" on arrival if the NPC
    -- doesn't actually have it.
    local itemDefID  = nil
    local instanceID = WorldState:GetInstanceIDFromLabel(itemLabel)
    if instanceID then
      for _, invItem in ipairs(npc:GetInventory() or {}) do
        if invItem.instanceID == instanceID then
          itemDefID = invItem.defID
          break
        end
      end
    end

    NPCActions:DropItem(npc, itemDefID, place, itemLabel)
    return true

  elseif action == "TALK" then
    -- args: actor, target, place, dialogue_content
    -- (parsed specially by ParseStep so dialogue_content keeps commas/quotes)
    local targetID = args[2]
    local place    = args[3]
    local dialogue = args[4]

    local placeDef = WorldState:GetPlaceDef(place)
    if placeDef == nil then
      self:Abort(runner, npc, "unknown_place")
      return false
    end

    -- Always walk to the place the LLM specified - never override with the
    -- target's actual location. If the target isn't there when the NPC
    -- arrives, ExecuteTalk reacts with target_not_here.
    local destPlace = place
    local destX     = placeDef.defaultX
    local destY     = placeDef.defaultY

    -- If the target is actually in the destination place, aim for an
    -- adjacent tile to them so the NPC stops next to (not on top of) them.
    if targetID == "player" or targetID == "john" then
      local playerPlace = WorldState:GetPlaceForPosition(
        level.levelName, math.ceil(player:GetX()), math.ceil(player:GetY()))
      if playerPlace == place then
        local adjX, adjY = self:FindAdjacentWalkable(
          level.levelName, math.ceil(player:GetX()), math.ceil(player:GetY()))
        if adjX then
          destX = adjX
          destY = adjY
        end
      end
    elseif targetID ~= npc.npcID then
      local target = NPCManager:GetNPCByID(targetID)
      if target then
        local targetPlace = WorldState:GetPlaceForPosition(
          target.levelFile, math.ceil(target.x), math.ceil(target.y))
        if targetPlace == place then
          local adjX, adjY = self:FindAdjacentWalkable(
            target.levelFile, math.ceil(target.x), math.ceil(target.y))
          if adjX then
            destX = adjX
            destY = adjY
          end
        end
      end
      -- if target doesn't exist, fall through with the place's defaults;
      -- ExecuteTalk will react on arrival
    end

    -- Build a journey to the place, and attach the talk payload as a
    -- final-step effect.
    local currentPlace = NPCActions:GetCurrentPlace(npc)
    local journey      = {}
    local blockedAtDoor = false

    if currentPlace ~= destPlace then
      local route = WorldState:FindRoute(currentPlace, destPlace)
      if route == nil then
        self:Abort(runner, npc, "no_route")
        return false
      end
      journey, blockedAtDoor = NPCActions:BuildJourney(npc, route)
      if journey == nil then
        self:Abort(runner, npc, "no_route")
        return false
      end
      if blockedAtDoor then
        npc:StartJourney(journey)
        NPCManager:PrecalculatePaths(npc)
        return true
      end
    end

    -- final step: walk to the destination tile and execute the talk
    table.insert(journey, {
      levelFile  = placeDef.levelFile,
      walkToX    = destX,
      walkToY    = destY,
      nextLevel  = nil,
      isTalk     = true,
      talkTarget = targetID,
      talkLines  = dialogue
    })

    npc:StartJourney(journey)
    NPCManager:PrecalculatePaths(npc)
    return true

  else
    print("NPCScheduler: unsupported action " .. action)
    self:Abort(runner, npc, "confused")
    return false
  end
end

-- =============================================================================
-- COMPLETION CHECKS
-- =============================================================================

function NPCScheduler:IsCurrentStepComplete(runner)
  local parsed = runner.current
  if parsed == nil then return true end

  local npc = NPCManager:GetNPCByID(runner.npcID)
  if npc == nil then return true end

  local action = parsed.action
  local args   = parsed.args

  -- Walk-first failure cases: when the NPC arrives and reacts, the journey
  -- ends with moving=false. We then mark the runner as failed so the
  -- schedule stops after the reaction line plays.
  if runner.abortAfterCurrent and not npc.moving then
    -- delay one tick to let the reaction balloon appear before we say the
    -- abandonment line
    self:Abort(runner, npc, nil) -- no extra reaction; the journey already said it
    runner.abortAfterCurrent = nil
    return false  -- don't advance; Abort sets state to failed
  end

  if action == "MOVE" then
    if npc.moving then return false end
    local toPlace = args[3]
    local current = WorldState:GetPlaceForPosition(
      npc.levelFile, math.ceil(npc.x), math.ceil(npc.y))
    if current == toPlace then
      return true
    end
    -- NPC stopped moving but never made it. Either the door blocked them
    -- (and they already said the door_locked line), or pathfinding failed.
    -- Either way, abort so the schedule doesn't hang.
    self:Abort(runner, npc, nil)  -- no extra reaction; door-locked already spoke
    return false

  elseif action == "PICKUP" then
    local itemLabel  = args[2]
    local instanceID = WorldState:GetInstanceIDFromLabel(itemLabel)
    if instanceID == nil then return true end

    -- success: NPC actually has the item
    for _, invItem in ipairs(npc:GetInventory() or {}) do
      if invItem.instanceID == instanceID then
        runner.expectingPickup = nil
        return true
      end
    end

    if not npc.moving then
      -- consumed mid-flight (e.g. someone else used it)
      if ItemWasConsumed(instanceID) then
        runner.expectingPickup = nil
        return true
      end
      -- vanished from the world somehow
      local stillInWorld = false
      for _, item in ipairs(ItemManager.items) do
        if item.instanceID == instanceID
           and not ItemWasCollected(instanceID) then
          stillInWorld = true
          break
        end
      end
      if not stillInWorld then
        runner.expectingPickup = nil
        return true
      end

      -- NPC stopped moving but never picked up the item AND it's still
      -- in the world. This means pathfinding failed (couldn't reach it).
      -- React and abort.
      if runner.expectingPickup then
        runner.expectingPickup = nil
        local item = NPCDialog:ItemDisplayName(itemLabel)
        self:Abort(runner, npc, "no_route", { item = item })
        return false
      end
    end
    return false

  elseif action == "FORTIFY" then
    return true

  elseif action == "TURN_POWER_ON" then
    local targetPlace = args[4] or "laboratory"
    if WorldState:HasPlaceCondition(targetPlace, "power_on") then
      return true
    end
    if not npc.moving then return true end
    return false

  elseif action == "UNLOCK" then
    local targetPlace = args[3]
    if WorldState:HasPlaceCondition(targetPlace, "unlocked") then
      return true
    end
    if not npc.moving then return true end
    return false

  elseif action == "WALK_AROUND" then
    if npc.moving then return false end

    if parsed.wanderDone < parsed.wanderTotal then
      local place = parsed.args[2]
      print("NPCScheduler: " .. runner.npcID
        .. " wander " .. parsed.wanderDone .. "/" .. parsed.wanderTotal
        .. " complete, starting next")
      if NPCActions:WalkAround(npc, place) then
        parsed.wanderDone = parsed.wanderDone + 1
        return false
      else
        return true
      end
    end

    return true
  elseif action == "SYNTHESIZE_CURE" then
    -- success: NPC has an antidote
    if npc:HasItem("antidote") then return true end
    -- failure cases: NPC has stopped moving but didn't synthesize anything.
    -- (failureReaction in NPC:Update or ExecuteSynthesize already played
    -- the reaction; if abortAfterCurrent is set, the top-of-function check
    -- will fire on the next tick and call Abort)
    if not npc.moving then return true end
    return false
    
  elseif action == "DROP" then
    -- success: NPC no longer has the item (it was consumed/dropped)
    local itemLabel  = args[2]
    local instanceID = WorldState:GetInstanceIDFromLabel(itemLabel)
    if instanceID == nil then
      -- hallucinated label - completion happens via abortAfterCurrent
      if not npc.moving then return true end
      return false
    end
    local stillHas = false
    for _, invItem in ipairs(npc:GetInventory() or {}) do
      if invItem.instanceID == instanceID then
        stillHas = true
        break
      end
    end
    if not stillHas then return true end
    if not npc.moving then return true end
    return false
    
  elseif action == "TALK" then
    -- waiting for arrival, then conversation. once the conversation
    -- is over (npc:IsTalking() returns false) and the NPC isn't moving,
    -- we're done.
    if npc.moving then return false end
    if npc:IsTalking() then return false end
    return true
  end

  if runner.abortAfterCurrent then
    return not npc.moving
  end
  return true
end

-- =============================================================================
-- PARSER
-- =============================================================================

function NPCScheduler:ParseStep(stepStr)
  if type(stepStr) ~= "string" then return nil end

  local action, argStr = stepStr:match("^%s*([A-Z_]+)%s*%((.*)%)%s*$")
  if action == nil then return nil end

  local args = {}

  if action == "TALK" then
    local actor, target, place, rest = argStr:match(
      "^%s*([^,]+)%s*,%s*([^,]+)%s*,%s*([^,]+)%s*,%s*(.*)$")
    if actor then
      table.insert(args, StringTrim(actor))
      table.insert(args, StringTrim(target))
      table.insert(args, StringTrim(place))
      rest = StringTrim(rest)
      if rest:sub(1, 1) == '"' and rest:sub(-1, -1) == '"' then
        rest = rest:sub(2, -2)
      end
      table.insert(args, rest)
    end
  else
    for arg in argStr:gmatch("[^,]+") do
      table.insert(args, StringTrim(arg))
    end
  end

  return { action = action, args = args, raw = stepStr }
end

-- Register a callback that fires when any NPC's schedule transitions to
-- "complete" or "failed". The callback receives (npcID, finalState).
-- finalState is either "complete" or "failed".
function NPCScheduler:OnScheduleEnd(callback)
  table.insert(self.listeners, callback)
end

-- Internal: notify all listeners that a runner ended.
function NPCScheduler:FireScheduleEnd(runner, finalState)
  for _, cb in ipairs(self.listeners) do
    local ok, err = pcall(cb, runner.npcID, finalState)
    if not ok then
      print("NPCScheduler: listener error: " .. tostring(err))
    end
  end
end