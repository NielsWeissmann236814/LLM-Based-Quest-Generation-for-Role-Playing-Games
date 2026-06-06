require "NPCDefinitions"
require "Pathfinding"

NPC = {}

function NPC:new(npcID, levelFile, xx, yy, dir, conditions)
  local def = NPCDefinitions[npcID]
  if def == nil then
    print("WARNING: No NPCDefinition found for npcID: " .. tostring(npcID))
    return nil
  end
  local condTable = {}
  if type(conditions) == "string" then
    table.insert(condTable, conditions)
  elseif type(conditions) == "table" then
    condTable = conditions
  end
  local obj = {
    npcID        = npcID,
    levelFile    = levelFile,
    x            = xx,
    y            = yy,
    dir          = dir,
    conditions   = condTable,
    inventory    = {},
    charQuads    = {},
    charImage    = _G[def.image],
    frame        = 1,
    time         = 0,
    xws          = 0,
    yws          = 0,
    xs           = 0,
    ys           = 0,
    speed        = def.speed,
    balloonText    = nil,
    balloonTimer   = 0,
    balloonDuration = 3.0,
    -- pathfinding state
    path         = {},
    pathIndex    = 1,
    targetX      = nil,
    targetY      = nil,
    moving       = false
  }
  setmetatable(obj, self)
  self.__index = self
  if obj.charImage == nil then
    print("WARNING: Image not found for NPC: " .. npcID .. " image: " .. def.image)
  end
  obj:LoadAnimation()
  obj:Animate(dir, 0)
  return obj
end

function NPC:LoadAnimation()
  local def = NPCDefinitions[self.npcID]
  local sw  = def.spriteWidth
  local sh  = def.spriteHeight
  local count = 1
  for j = 0, 3, 1 do
    for i = 0, 2, 1 do
      self.charQuads[count] = love.graphics.newQuad(
        i * sw, j * sh, sw, sh,
        self.charImage:getWidth(), self.charImage:getHeight()
      )
      count = count + 1
    end
  end
end

function NPC:Animate(dir, dt)
  local ranges = {
    up    = {7, 9},
    down  = {1, 3},
    left  = {10, 12},
    right = {4, 6}
  }
  local r = ranges[dir]
  if not r then return end
  if self.frame < r[1] or self.frame > r[2] then
    self.frame = r[1]
  end
  self.time = self.time + dt
  if self.time > 0.1 then
    self.frame = self.frame + 1
    if self.frame > r[2] then
      self.frame = r[1]
    end
    self.time = 0
  end
end

function NPC:Say(text, duration)
  self.balloonText  = text
  self.balloonTimer = duration or self.balloonDuration
end

-- called by LLM system (or hardcoded test) to set a movement target
function NPC:MoveTo(tx, ty)
  self.targetX   = tx
  self.targetY   = ty
  self.path      = {}
  self.pathIndex = 1
  self.moving    = true
  print("NPC " .. self.npcID .. " moving to " .. tx .. "," .. ty)
end

function NPC:Move(dir, dt, level)
  self.dir = dir

  local dirData = {
    up    = { tx = math.floor(self.x),     ty = math.floor(self.y) - 1, dx = 0,          dy = -self.speed },
    down  = { tx = math.ceil(self.x),      ty = math.ceil(self.y) + 1,  dx = 0,           dy =  self.speed },
    left  = { tx = math.floor(self.x) - 1, ty = math.floor(self.y),     dx = -self.speed, dy = 0           },
    right = { tx = math.ceil(self.x) + 1,  ty = math.ceil(self.y),      dx =  self.speed, dy = 0           }
  }

  local d    = dirData[dir]
  local tile = level:GetTile(d.tx, d.ty)

  if tile == nil or tile.properties.obstacle then
    self:Animate(dir, dt)
    return
  end

  self.xws = self.xws + d.dx
  self.yws = self.yws + d.dy
  self:Animate(dir, dt)
end

-- Process the effects of arriving at the current journey step's destination.
-- Used by both the multi-node arrival branch and the 1-node degenerate
-- branch in NPC:Update so the two paths can't drift out of sync.
-- Returns true if the journey was ended (failure reaction or completion),
-- false if the caller should keep advancing journey steps.
function NPC:OnJourneyStepArrived()
  if self.journey == nil then return true end
  local step = self.journey[self.journeyStep]
  if step == nil then return true end

  -- final-step failure reaction: NPC arrived at a destination flagged as
  -- a failure case. Say the line and end the journey here.
  if step.failureReaction then
    local r = step.failureReaction
    self:Say(NPCDialog:Pick(r.category, r.vars), 4)
    print("NPC " .. self.npcID .. " arrival reaction: " .. r.category)
    step.failureReaction = nil
    self.journey         = nil
    self.journeyStep     = 1
    self.moving          = false
    self.path            = {}
    return true
  end

  -- unlock place when NPC reaches the door (legacy unlockPlace flag,
  -- different from isUnlock; this is for journey steps that incidentally
  -- pass through a locked door the NPC has the key for)
  if step.unlockPlace then
    local placeDef = WorldState:GetPlaceDef(step.unlockPlace)
    local keyID    = placeDef
                  and WorldState:GetKeyForDestination(placeDef.levelFile)
    if keyID and self:HasItem(keyID) then
      for _, item in ipairs(self.inventory) do
        if item.defID == keyID then
          table.insert(ConsumedItems, item.instanceID)
          break
        end
      end
      self:RemoveItem(keyID)
      print("NPC " .. self.npcID .. " consumed key " .. keyID
        .. " unlocking " .. step.unlockPlace)
    end
    WorldState:AddPlaceCondition(step.unlockPlace, "unlocked")
    print("NPC " .. self.npcID .. " unlocked " .. step.unlockPlace)
    step.unlockPlace = nil
  end

  -- per-action arrival effects
  if step.isSynthesize then
    self:ExecuteSynthesize()
    self.journeyStep = self.journeyStep + 1
    self:AdvanceJourneyStep()
    return true
  end

  if step.isPickup then
    self:ExecutePickup(step.itemInstanceID, level)
    self.journeyStep = self.journeyStep + 1
    self:AdvanceJourneyStep()
    return true
  end

  if step.isTurnPowerOn then
    self:ExecuteTurnPowerOn()
    self.journeyStep = self.journeyStep + 1
    self:AdvanceJourneyStep()
    return true
  end

  if step.isUnlock then
    self:ExecuteUnlock(step.unlockTarget, step.unlockKeyDefID)
    self.journeyStep = self.journeyStep + 1
    self:AdvanceJourneyStep()
    return true
  end

  if step.isFortify then
    self:ExecuteFortify(step.fortifyDefID, step.fortifyPlace)
    self.journeyStep = self.journeyStep + 1
    self:AdvanceJourneyStep()
    return true
  end

  if step.isDrop then
    self:ExecuteDrop(step.dropDefID, step.dropLabel)
    self.journeyStep = self.journeyStep + 1
    self:AdvanceJourneyStep()
    return true
  end

  if step.isTalk then
    self:ExecuteTalk(step.talkTarget, step.talkLines)
    self.journeyStep = self.journeyStep + 1
    self:AdvanceJourneyStep()
    return true
  end

  -- level transition
  if step.nextLevel ~= nil then
    self.levelFile = step.nextLevel
    self.x         = step.arriveAtX
    self.y         = step.arriveAtY
    self.path      = {}
    print("NPC " .. self.npcID .. " transitioned to " .. step.nextLevel)
  end

  -- advance to next step
  self.journeyStep = self.journeyStep + 1
  self:AdvanceJourneyStep()
  return false
end

function NPC:Update(dt, pl, level)
  self.xws, self.yws = 0, 0

  -- countdown balloon
  if self.balloonTimer > 0 then
    self.balloonTimer = self.balloonTimer - dt
    if self.balloonTimer <= 0 then
      self.balloonText  = nil
      self.balloonTimer = 0
    end
  end

  -- drive any in-flight conversation independently of movement
  self:UpdateConversation(dt)

  if self.moving and self.targetX ~= nil and self.targetY ~= nil then
    -- only pathfind if we have a valid level reference
    if level == nil then
      self:UpdateOffscreen(dt)
      return
    end

    -- compute path if we don't have one yet
    if #self.path == 0 then
      local step = self.journey and self.journey[self.journeyStep]
      if step and step.precalculatedPath and #step.precalculatedPath > 0 then
        -- resume from current pathIndex, don't reset it
        self.path = step.precalculatedPath
        print("NPC " .. self.npcID .. " resuming precalculated path from index "
          .. self.pathIndex)
      else
        self.path = astar.path(
          { x = math.ceil(self.x), y = math.ceil(self.y) },
          { x = self.targetX,      y = self.targetY },
          level, true
        )
        self.pathIndex = 2
        if self.path == nil or #self.path == 0 then
          print("NPC " .. self.npcID .. ": no path found to "
            .. self.targetX .. "," .. self.targetY)
          self.moving = false
          self.path   = {}
          return
        end
      end
    end

    -- degenerate case: path has 1 node because we're already at the
    -- target tile. Treat as immediate arrival.
    if self.path ~= nil and #self.path == 1 and self.targetX ~= nil then
      if math.ceil(self.x) == self.targetX
         and math.ceil(self.y) == self.targetY then
        self.x      = self.targetX
        self.y      = self.targetY
        self.moving = false
        self.path   = {}
        if self.journey ~= nil then
          self:OnJourneyStepArrived()
        end
        return
      end
    end

    -- follow path
    if self.path ~= nil and #self.path > 1 and self.pathIndex <= #self.path then
      local target = self.path[self.pathIndex]

      if (self.ys == 0) and (self.xs == 0) then
        if target.x > self.x then
          self:Move("right", dt, level)
        elseif target.x < self.x then
          self:Move("left", dt, level)
        elseif target.y > self.y then
          self:Move("down", dt, level)
        elseif target.y < self.y then
          self:Move("up", dt, level)
        else
          -- reached this waypoint, advance to next
          if self.pathIndex < #self.path then
            self.pathIndex = self.pathIndex + 1
          end
        end
      end

      -- check if reached current waypoint
      if self.pathIndex >= #self.path
        and math.abs(self.x - self.targetX) < 0.1
        and math.abs(self.y - self.targetY) < 0.1 then
        self.moving = false
        self.x      = self.targetX
        self.y      = self.targetY

        -- handle same-level pendingArrivalReaction (set by NPCActions:Walk
        -- when the NPC didn't need a journey)
        if self.pendingArrivalReaction then
          local r = self.pendingArrivalReaction
          self:Say(NPCDialog:Pick(r.category, r.vars), 4)
          self.pendingArrivalReaction = nil
          -- if no journey, we're done
          if self.journey == nil then
            return
          end
        end

        if self.journey ~= nil then
          self:OnJourneyStepArrived()
        end
      end
    end
  else
    -- idle: hold first frame of facing direction
    local ranges = { up={7,9}, down={1,3}, left={10,12}, right={4,6} }
    local r = ranges[self.dir]
    if r then self.frame = r[1] end
  end

  -- smooth movement (same pattern as player and enemy)
  if self.yws ~= 0 and self.xs == 0 then
    self.ys = self.yws
  elseif self.ys ~= 0 then
    self:Animate(self.dir, dt)
    if round(self.y, self.ys) ~= round(self.y + self.ys * dt, self.ys) then
      self.ys = 0
      self.y  = round(self.y, self.ys)
    end
  end
  if self.xws ~= 0 and self.ys == 0 then
    self.xs = self.xws
  elseif self.xs ~= 0 then
    self:Animate(self.dir, dt)
    if round(self.x, self.xs) ~= round(self.x + self.xs * dt, self.xs) then
      self.xs = 0
      self.x  = round(self.x, self.xs)
    end
  end
  self.x = self.x + self.xs * dt
  self.y = self.y + self.ys * dt
end

function NPC:Draw()
  love.graphics.draw(
    self.charImage, self.charQuads[self.frame],
    (self.x * 32) + 16, (self.y * 32) + 11,
    0, 1, 1, 20, 20
  )
end

function NPC:DrawBalloon()
  if self.balloonText == nil then return end

  -- text wrapping
  love.graphics.setFont(myfont2)
  local maxTextW = 180
  local _, wrappedLines = myfont2:getWrap(self.balloonText, maxTextW)
  local nLines = math.max(1, #wrappedLines)
  local lineH  = myfont2:getHeight()
  local textH  = nLines * lineH

  local textW = 0
  for _, line in ipairs(wrappedLines) do
    textW = math.max(textW, myfont2:getWidth(line))
  end

  -- bubble dimensions
  local padX = 10
  local padY = 6
  local bubbleW = textW + (padX * 2)
  local bubbleH = textH + (padY * 2)

  -- anchor: NPC's head
  local headX = (self.x * 32) + 16
  local headY = (self.y * 32) - 4

  -- tail geometry
  local tailH = 10
  local tailW = 10

  -- bubble origin
  local bubbleX = headX - (bubbleW / 2)
  local bubbleY = headY - tailH - bubbleH

  -- bubble fill
  love.graphics.setColor(0.98, 0.98, 0.96)
  love.graphics.rectangle("fill", bubbleX, bubbleY, bubbleW, bubbleH, 6, 6)

  -- tail fill (drawn over bubble fill to hide the seam)
  local tailBaseCenterX = headX
  local tailLeft        = tailBaseCenterX - (tailW / 2)
  local tailRight       = tailBaseCenterX + (tailW / 2)
  local tailTopY        = bubbleY + bubbleH - 1
  local tailTipX        = headX
  local tailTipY        = headY
  love.graphics.polygon("fill",
    tailLeft,  tailTopY,
    tailRight, tailTopY,
    tailTipX,  tailTipY
  )

  -- ======================================================================
  -- border: drawn as separate segments so it skips the tail-base region
  -- ======================================================================
  love.graphics.setColor(0.15, 0.15, 0.15)
  love.graphics.setLineWidth(1)

  local r = 6  -- corner radius (must match the fill's radius)

  -- corner arcs
  -- top-left
  love.graphics.arc("line", "open",
    bubbleX + r, bubbleY + r, r, math.pi, math.pi * 1.5)
  -- top-right
  love.graphics.arc("line", "open",
    bubbleX + bubbleW - r, bubbleY + r, r, math.pi * 1.5, math.pi * 2)
  -- bottom-right
  love.graphics.arc("line", "open",
    bubbleX + bubbleW - r, bubbleY + bubbleH - r, r, 0, math.pi * 0.5)
  -- bottom-left
  love.graphics.arc("line", "open",
    bubbleX + r, bubbleY + bubbleH - r, r, math.pi * 0.5, math.pi)

  -- straight edges
  love.graphics.line(bubbleX + r,           bubbleY,
                     bubbleX + bubbleW - r, bubbleY)                  -- top
  love.graphics.line(bubbleX + bubbleW,     bubbleY + r,
                     bubbleX + bubbleW,     bubbleY + bubbleH - r)    -- right
  love.graphics.line(bubbleX,               bubbleY + r,
                     bubbleX,               bubbleY + bubbleH - r)    -- left

  -- bottom edge: split into two segments, leaving a gap where the tail attaches
  local bottomY = bubbleY + bubbleH
  -- segment from bottom-left corner to tail's left base
  love.graphics.line(bubbleX + r,  bottomY,
                     tailLeft,     bottomY)
  -- segment from tail's right base to bottom-right corner
  love.graphics.line(tailRight,    bottomY,
                     bubbleX + bubbleW - r, bottomY)

  -- tail's two slanted edges, connecting the bottom edge ends to the tip
  love.graphics.line(tailLeft,  bottomY, tailTipX, tailTipY)
  love.graphics.line(tailRight, bottomY, tailTipX, tailTipY)

  -- text
  love.graphics.setColor(0.1, 0.1, 0.1)
  love.graphics.printf(self.balloonText, bubbleX + padX, bubbleY + padY,
    textW, "left")

  love.graphics.setColor(1, 1, 1)
  love.graphics.setFont(myfont)
end

function NPC:HasCondition(condition)
  for _, c in ipairs(self.conditions) do
    if c == condition then return true end
  end
  return false
end

function NPC:AddCondition(condition)
  if not self:HasCondition(condition) then
    table.insert(self.conditions, condition)
  end
end

function NPC:RemoveCondition(condition)
  for i, c in ipairs(self.conditions) do
    if c == condition then
      table.remove(self.conditions, i)
      return
    end
  end
end

function NPC:GetCondition()
  -- returns primary condition for backward compatibility
  return self.conditions[1] or "healthy"
end

function NPC:SetCondition(condition)
  -- replaces primary condition, keeps others
  if #self.conditions > 0 then
    self.conditions[1] = condition
  else
    table.insert(self.conditions, condition)
  end
end

function NPC:GetConditions()
  return self.conditions
end

function NPC:AddItem(defID, instanceID)
  table.insert(self.inventory, { defID = defID, instanceID = instanceID })
end

function NPC:RemoveItem(defID)
  for i, item in ipairs(self.inventory) do
    if item.defID == defID then
      table.remove(self.inventory, i)
      return
    end
  end
end

function NPC:HasItem(defID)
  for _, item in ipairs(self.inventory) do
    if item.defID == defID then return true end
  end
  return false
end

function NPC:GetInventory()
  return self.inventory
end

function NPC:OnOffscreenWaypointReached(step)
  print("NPC " .. self.npcID .. " (offscreen) reached waypoint "
    .. step.walkToX .. "," .. step.walkToY)

  -- delegate to the shared arrival handler. it processes failure
  -- reactions, unlock-place flags, all is* step types, level transitions,
  -- and advances the journey.
  self:OnJourneyStepArrived()

  -- reset the offscreen-specific bookkeeping when the journey ends or
  -- when we transitioned to a new level
  if self.journey == nil then
    self.offscreenMoveTimer = 0
  else
    -- if we just transitioned to a new level, the offscreen pathIndex
    -- needs to start fresh on the new step's path
    step.offscreenPathIndex = 1
  end
end

function NPC:StartJourney(journey)
  self.journey      = journey
  self.journeyStep  = 1
  self.moving       = true
  self.path         = {}
  self:AdvanceJourneyStep()
  print("NPC " .. self.npcID .. " starting journey with " .. #journey .. " steps")
end

function NPC:AdvanceJourneyStep()
  if self.journey == nil or self.journeyStep > #self.journey then
    self.journey     = nil
    self.journeyStep = 1
    self.moving      = false
    self.path        = {}
    self.pathIndex   = 1
    print("NPC " .. self.npcID .. " completed journey")
    return
  end

  local step = self.journey[self.journeyStep]

  if step.levelFile ~= self.levelFile then
    self.levelFile = step.levelFile
    self.x         = step.arriveAtX or self.x
    self.y         = step.arriveAtY or self.y
  end

  -- reset path index for new step
  self.path      = {}
  self.pathIndex = 2  -- index 1 is start node, begin from 2

  self:MoveTo(step.walkToX, step.walkToY)
end

function NPC:StartPickupJourney(journey, itemInstanceID, itemX, itemY)
  -- final step: walk to item and pick it up
  local pickupStep = {
    levelFile      = self.levelFile,
    walkToX        = itemX,
    walkToY        = itemY,
    nextLevel      = nil,
    isPickup       = true,
    itemInstanceID = itemInstanceID
  }

  -- if there's a journey, the pickup happens in the destination level
  if journey ~= nil and #journey > 0 then
    local lastStep = journey[#journey]
    pickupStep.levelFile = lastStep.nextLevel or lastStep.levelFile
  end

  -- verify the pickup level matches item position
  local pickupPlace = WorldState:GetPlaceForPosition(
    pickupStep.levelFile, itemX, itemY)
  print("NPC " .. self.npcID .. " pickup step: place=" .. pickupPlace
    .. " level=" .. pickupStep.levelFile
    .. " at " .. itemX .. "," .. itemY)

  if journey == nil then
    self.journey = { pickupStep }
  else
    journey[#journey + 1] = pickupStep
    self.journey = journey
  end

  self.journeyStep = 1
  self.moving      = true
  self.path        = {}
  self.pathIndex   = 2
  self:AdvanceJourneyStep()
  print("NPC " .. self.npcID .. " starting pickup journey for " 
    .. itemInstanceID)
end

function NPC:ExecutePickup(itemInstanceID, level)
  -- add to NPC inventory
  local defID = nil
  for _, item in ipairs(ItemManager.items) do
    if item.instanceID == itemInstanceID then
      defID = item.defID
      break
    end
  end

  if defID == nil then
    print("NPC " .. self.npcID .. " pickup failed: defID not found for " .. itemInstanceID)
    return
  end

  self:AddItem(defID, itemInstanceID)
  table.insert(CollectedItems, itemInstanceID)

  -- remove from level if currently loaded
  if level ~= nil then
    local removeIdx = nil
    for i, item in ipairs(level.Itens) do
      if item.instanceID == itemInstanceID then
        removeIdx = i
        break
      end
    end
    if removeIdx then
      table.remove(level.Itens, removeIdx)
    end
  end

  local def  = ItemDefinitions[defID]
  local name = def and def.displayName or defID
  self:Say(NPCDialog:Pick("pickup_success"), 3)
  print("NPC " .. self.npcID .. " picked up " .. name .. " (" .. itemInstanceID .. ")")
  print("npc_pickup: " .. self.npcID .. " -> " .. itemInstanceID)
end

function NPC:StartTurnPowerOnJourney(journey)
  self.journey     = journey
  self.journeyStep = 1
  self.moving      = true
  self.path        = {}
  self.pathIndex   = 2
  self:AdvanceJourneyStep()
  print("NPC " .. self.npcID .. " starting turn-power-on journey")
end

function NPC:ExecuteTurnPowerOn()
  -- check power isn't already on
  if WorldState:HasPlaceCondition("laboratory", "power_on") then
    self:Say(NPCDialog:Pick("power_already_on"), 4)
    print("NPC " .. self.npcID .. " arrived at power box but power already on")
    -- mark schedule for abort
    if NPCScheduler.runners[self.npcID] then
      NPCScheduler.runners[self.npcID].abortAfterCurrent = true
    end
    return
  end

  -- find a fuse in inventory
  local fuseInstance = nil
  for _, item in ipairs(self.inventory) do
    if item.defID == "fuse" then
      fuseInstance = item
      break
    end
  end

  if fuseInstance == nil then
    print("NPC " .. self.npcID .. " arrived at power box but has no fuse")
    self:Say(NPCDialog:Pick("no_fuse"), 4)
    -- mark schedule for abort
    if NPCScheduler.runners[self.npcID] then
      NPCScheduler.runners[self.npcID].abortAfterCurrent = true
    end
    return
  end

  -- success: consume fuse and apply effect
  table.insert(ConsumedItems, fuseInstance.instanceID)
  self:RemoveItem("fuse")

  WorldState:RemovePlaceCondition("laboratory", "no_power")
  WorldState:AddPlaceCondition("laboratory", "power_on")

  self:Say(NPCDialog:Pick("turn_power_on_success"), 3)
  print("NPC " .. self.npcID .. " restored power to the laboratory")
  print("npc_turn_power_on: " .. self.npcID .. " -> laboratory")
end

function NPC:ExecuteFortify(itemDefID, targetPlace)
  itemDefID   = itemDefID   or "wood"
  targetPlace = targetPlace or NPCActions:GetCurrentPlace(self)

  -- already fortified?
  if WorldState:HasPlaceCondition(targetPlace, "fortified") then
    self:Say(NPCDialog:Pick("already_fortified_arrived"), 4)
    print("NPC " .. self.npcID .. " arrived but " .. targetPlace
      .. " is already fortified")
    if NPCScheduler.runners[self.npcID] then
      NPCScheduler.runners[self.npcID].abortAfterCurrent = true
    end
    return
  end

  -- no wood in inventory?
  if not self:HasItem(itemDefID) then
    self:Say(NPCDialog:Pick("no_wood"), 4)
    print("NPC " .. self.npcID .. " arrived to fortify but has no "
      .. itemDefID)
    if NPCScheduler.runners[self.npcID] then
      NPCScheduler.runners[self.npcID].abortAfterCurrent = true
    end
    return
  end

  -- consume the item
  for _, item in ipairs(self.inventory) do
    if item.defID == itemDefID then
      table.insert(ConsumedItems, item.instanceID)
      break
    end
  end
  self:RemoveItem(itemDefID)

  WorldState:AddPlaceCondition(targetPlace, "fortified")
  self:Say(NPCDialog:Pick("fortify_success"), 3)

  print("NPC " .. self.npcID .. " fortified " .. targetPlace)
  print("npc_fortify: " .. self.npcID .. " -> " .. targetPlace)
end

function NPC:UpdateOffscreen(dt)
  -- drive any in-flight conversation even when off-screen
  self:UpdateConversation(dt)
  -- balloon timer also needs to count down off-screen so old balloons clear
  if self.balloonTimer > 0 then
    self.balloonTimer = self.balloonTimer - dt
    if self.balloonTimer <= 0 then
      self.balloonText  = nil
      self.balloonTimer = 0
    end
  end

  if not self.moving then return end
  if self.journey == nil then return end

  local step = self.journey[self.journeyStep]
  if step == nil then return end

  self.offscreenMoveTimer = (self.offscreenMoveTimer or 0) + dt
  local moveInterval = 1.0 / self.speed
  if self.offscreenMoveTimer < moveInterval then return end
  self.offscreenMoveTimer = 0

  if step.precalculatedPath and #step.precalculatedPath > 0 then
    -- use self.pathIndex, same as onscreen update
    if self.pathIndex > #step.precalculatedPath then
      self:OnOffscreenWaypointReached(step)
      return
    end

    local node = step.precalculatedPath[self.pathIndex]
    local dx   = node.x - math.ceil(self.x)
    local dy   = node.y - math.ceil(self.y)
    if math.abs(dx) >= math.abs(dy) then
      self.dir = dx > 0 and "right" or "left"
    else
      self.dir = dy > 0 and "down" or "up"
    end

    self.x         = node.x
    self.y         = node.y
    self.pathIndex = self.pathIndex + 1

  else
    -- no precalculated path, tile by tile fallback
    local tx = math.ceil(self.x)
    local ty = math.ceil(self.y)
    if tx == step.walkToX and ty == step.walkToY then
      self:OnOffscreenWaypointReached(step)
      return
    end
    local dx = step.walkToX - tx
    local dy = step.walkToY - ty
    if math.abs(dx) >= math.abs(dy) then
      self.x   = tx + (dx > 0 and 1 or -1)
      self.dir = dx > 0 and "right" or "left"
    else
      self.y   = ty + (dy > 0 and 1 or -1)
      self.dir = dy > 0 and "down" or "up"
    end
    self.x = math.ceil(self.x)
    self.y = math.ceil(self.y)
  end
end

function NPC:StartSynthesizeJourney(journey)
  self.journey     = journey
  self.journeyStep = 1
  self.moving      = true
  self.path        = {}
  self.pathIndex   = 2
  self:AdvanceJourneyStep()
  print("NPC " .. self.npcID .. " starting synthesize journey")
end

function NPC:ExecuteSynthesize()
  -- power went out between dispatch and arrival? react
  if not WorldState:HasPlaceCondition("laboratory", "power_on") then
    self:Say(NPCDialog:Pick("no_power_synth"), 4)
    print("NPC " .. self.npcID .. " arrived at synth machine but power is off")
    if NPCScheduler.runners[self.npcID] then
      NPCScheduler.runners[self.npcID].abortAfterCurrent = true
    end
    return
  end

  -- already carrying an antidote? react
  if self:HasItem("antidote") then
    self:Say(NPCDialog:Pick("already_have_antidote"), 4)
    print("NPC " .. self.npcID
      .. " arrived at synth machine but already has an antidote")
    if NPCScheduler.runners[self.npcID] then
      NPCScheduler.runners[self.npcID].abortAfterCurrent = true
    end
    return
  end

  -- find a cure_sample in inventory
  local sampleInstance = nil
  for _, item in ipairs(self.inventory) do
    if item.defID == "cure_sample" then
      sampleInstance = item
      break
    end
  end

  if sampleInstance == nil then
    self:Say(NPCDialog:Pick("no_cure_sample"), 4)
    print("NPC " .. self.npcID
      .. " arrived at synth machine but has no cure_sample")
    if NPCScheduler.runners[self.npcID] then
      NPCScheduler.runners[self.npcID].abortAfterCurrent = true
    end
    return
  end

  -- success: consume sample, produce antidote, register it everywhere
  table.insert(ConsumedItems, sampleInstance.instanceID)
  self:RemoveItem("cure_sample")

  local instanceID = "antidote_synthesized_"
    .. self.npcID .. "_" .. tostring(os.time())
  self:AddItem("antidote", instanceID)
  table.insert(CollectedItems, instanceID)
  -- mirror the player's use of the synth machine: register the new antidote
  -- in the world's item systems so it shows up in WorldState dumps and is
  -- discoverable by other systems.
  WorldState:RegisterItem(instanceID, "antidote")
  ItemManager:AddRuntimeItem("antidote", instanceID)

  self:Say(NPCDialog:Pick("synthesize_success"), 4)
  print("NPC " .. self.npcID .. " synthesized antidote: " .. instanceID)
  print("npc_synthesize: " .. self.npcID .. " -> antidote")
end

function NPC:StartUnlockJourney(journey)
  self.journey     = journey
  self.journeyStep = 1
  self.moving      = true
  self.path        = {}
  self.pathIndex   = 2
  self:AdvanceJourneyStep()
  print("NPC " .. self.npcID .. " starting unlock journey")
end

function NPC:ExecuteUnlock(targetPlace, keyDefID)
  -- already unlocked? react and abort
  if WorldState:HasPlaceCondition(targetPlace, "unlocked") then
    self:Say(NPCDialog:Pick("already_unlocked"), 4)
    print("NPC " .. self.npcID .. " arrived at " .. targetPlace
      .. " door but it is already unlocked")
    if NPCScheduler.runners[self.npcID] then
      NPCScheduler.runners[self.npcID].abortAfterCurrent = true
    end
    return
  end

  -- no usable key? react and abort
  if keyDefID == nil or not self:HasItem(keyDefID) then
    self:Say(NPCDialog:Pick("door_locked_no_key"), 4)
    print("NPC " .. self.npcID .. " arrived at " .. targetPlace
      .. " door but has no key")
    if NPCScheduler.runners[self.npcID] then
      NPCScheduler.runners[self.npcID].abortAfterCurrent = true
    end
    return
  end

  -- success: consume key, unlock, continue schedule
  for _, item in ipairs(self.inventory) do
    if item.defID == keyDefID then
      table.insert(ConsumedItems, item.instanceID)
      break
    end
  end
  self:RemoveItem(keyDefID)

  WorldState:RemovePlaceCondition(targetPlace, "locked")
  WorldState:AddPlaceCondition(targetPlace, "unlocked")

  self:Say(NPCDialog:Pick("unlock_success"), 3)
  print("NPC " .. self.npcID .. " unlocked " .. targetPlace
    .. " with " .. keyDefID)
  print("npc_unlock: " .. self.npcID .. " -> " .. targetPlace)
end

-- ============================================================
-- NPC CONVERSATION RUNNER
-- ============================================================
-- TALK action arrived at the destination. Plays a sequence of dialogue
-- turns through balloons. Each turn is rendered over its speaker's head
-- (or over the actor NPC if the speaker can't be located).
--
-- turns: list of { speaker = "npcID"|"player"|"john", line = "..." }
-- onComplete: optional callback fired after the last turn finishes
function NPC:StartConversation(turns, onComplete)
  if turns == nil or #turns == 0 then
    if onComplete then onComplete() end
    return
  end
  self.conversation = {
    turns       = turns,
    index       = 0,
    timer       = 0,
    onComplete  = onComplete
  }
  -- kick off the first turn
  self:AdvanceConversation()
end

function NPC:AdvanceConversation()
  if self.conversation == nil then return end
  self.conversation.index = self.conversation.index + 1
  local turn = self.conversation.turns[self.conversation.index]

  if turn == nil then
    -- conversation finished
    local cb = self.conversation.onComplete
    self.conversation = nil
    if cb then cb() end
    return
  end

  -- resolve the speaker. Player and "john" both refer to the player; we
  -- render their lines over the actor NPC since there's no player balloon.
  local speakerID = turn.speaker or self.npcID
  local speakerNPC = nil
  if speakerID == "player" or speakerID == "john" then
    speakerNPC = self  -- player lines render over the talking NPC
  else
    speakerNPC = NPCManager:GetNPCByID(speakerID)
  end
  if speakerNPC == nil then
    speakerNPC = self  -- fallback
  end

  -- pick a duration based on line length: ~2s minimum, +0.05s per char
  local duration = math.max(2.0, 2.0 + (#turn.line * 0.045))
  speakerNPC:Say(turn.line, duration)
  -- short gap before advancing so balloons don't overlap awkwardly
  self.conversation.timer = duration + 0.4
end

function NPC:UpdateConversation(dt)
  if self.conversation == nil then return end
  self.conversation.timer = self.conversation.timer - dt
  if self.conversation.timer <= 0 then
    self:AdvanceConversation()
  end
end

function NPC:IsTalking()
  return self.conversation ~= nil
end

function NPC:ExecuteTalk(targetID, dialogueContent)
  -- Decide where the target stands. If "self" (self-talk), no target needed.
  -- If "player"/"john", render lines over the actor NPC. If a real NPC ID,
  -- find them. If they're not there, react and abort.

  local isSelf = (targetID == self.npcID)
  local isPlayer = (targetID == "player" or targetID == "john")

  -- Validate target exists at this place (skip for self-talk and player)
  -- Validate target is here. Skip for self-talk.
  if not isSelf then
    local myPlace = WorldState:GetPlaceForPosition(
      self.levelFile, math.ceil(self.x), math.ceil(self.y))
    local targetName, targetPlace

    if isPlayer then
      targetName  = "John"
      targetPlace = WorldState:GetPlaceForPosition(
        level.levelName,
        math.ceil(player:GetX()), math.ceil(player:GetY()))
    else
      local target = NPCManager:GetNPCByID(targetID)
      targetName  = (NPCDefinitions[targetID]
                      and NPCDefinitions[targetID].displayName)
                      or targetID
      if target == nil then
        self:Say(NPCDialog:Pick("unknown_target", { target = targetName }), 4)
        print("NPC " .. self.npcID .. " arrived to talk to "
          .. tostring(targetID) .. " but no such NPC exists")
        if NPCScheduler.runners[self.npcID] then
          NPCScheduler.runners[self.npcID].abortAfterCurrent = true
        end
        return
      end
      targetPlace = WorldState:GetPlaceForPosition(
        target.levelFile, math.ceil(target.x), math.ceil(target.y))
    end

    if myPlace ~= targetPlace then
      self:Say(NPCDialog:Pick("target_not_here", { target = targetName }), 4)
      print("NPC " .. self.npcID .. " arrived to talk to "
        .. targetID .. " at " .. tostring(myPlace)
        .. " but target is at " .. tostring(targetPlace))
      if NPCScheduler.runners[self.npcID] then
        NPCScheduler.runners[self.npcID].abortAfterCurrent = true
      end
      return
    end
  end

  -- Build the turn list. dialogueContent can be either:
  --   - a string with no delimiter: single line by the actor
  --   - a string in JSON-array form: [\"line1\", \"line2\", ...] - parsed
  --     as a sequence of alternating-speaker turns
  --   - a string with "||" delimiter: alternating actor/target turns
  --   - a string with "Speaker: text" prefix: explicit speaker for that line
  --   - a list of strings or {speaker, line} tables: explicit list
  local turns = {}

  local function addTurnFromString(s, autoSpeaker)
    s = StringTrim(s)
    if s == "" then return end
    -- check for "Speaker: text" prefix
    local prefix, rest = s:match("^(%w+)%s*:%s*(.+)$")
    if prefix and (NPCDefinitions[prefix:lower()]
                    or prefix:lower() == "player"
                    or prefix:lower() == "john") then
      table.insert(turns, { speaker = prefix:lower(), line = rest })
    else
      table.insert(turns, { speaker = autoSpeaker, line = s })
    end
  end

  -- Detect JSON-array-style strings and convert them to a list of strings.
  -- Handles inputs like: ["Hi.", "Hello.", "Goodbye."]
  -- Tolerates escaped quotes (\") because the scheduler may receive the
  -- content already string-escaped from the schedule format.
  local function tryParseJSONArray(s)
    s = StringTrim(s)
    if s:sub(1, 1) ~= "[" or s:sub(-1, -1) ~= "]" then return nil end
    local inner = s:sub(2, -2)
    -- split on quoted segments
    local items = {}
    -- match either escaped ("\"...\"") or plain ("...") quoted strings
    for chunk in inner:gmatch('\\?"([^"\\]*)\\?"') do
      table.insert(items, chunk)
    end
    if #items == 0 then return nil end
    return items
  end

  if type(dialogueContent) == "string" then
    local arrayItems = tryParseJSONArray(dialogueContent)
    if arrayItems then
      -- treat as a list of strings
      for i, item in ipairs(arrayItems) do
        local autoSpeaker = self.npcID
        if not isSelf and (i % 2 == 0) then autoSpeaker = targetID end
        addTurnFromString(item, autoSpeaker)
      end
    else
      -- split on ||, alternate speakers
      local i = 0
      for chunk in (dialogueContent .. "||"):gmatch("(.-)||") do
        i = i + 1
        local autoSpeaker = self.npcID
        if not isSelf and (i % 2 == 0) then autoSpeaker = targetID end
        addTurnFromString(chunk, autoSpeaker)
      end
    end
  elseif type(dialogueContent) == "table" then
    for i, entry in ipairs(dialogueContent) do
      if type(entry) == "string" then
        local autoSpeaker = self.npcID
        if not isSelf and (i % 2 == 0) then autoSpeaker = targetID end
        addTurnFromString(entry, autoSpeaker)
      elseif type(entry) == "table" and entry.line then
        table.insert(turns, {
          speaker = entry.speaker or self.npcID,
          line    = entry.line
        })
      end
    end
  end

  if #turns == 0 then
    self:Say(NPCDialog:Pick("confused"), 4)
    if NPCScheduler.runners[self.npcID] then
      NPCScheduler.runners[self.npcID].abortAfterCurrent = true
    end
    return
  end

  -- Start the conversation. The completion check on the scheduler side
  -- waits for npc:IsTalking() to return false.
  print("NPC " .. self.npcID .. " starting conversation with "
    .. tostring(targetID) .. " (" .. #turns .. " turns)")
  self:StartConversation(turns)
  print("npc_talk: " .. self.npcID .. " -> " .. tostring(targetID))
end

function NPC:GetX()         return self.x         end
function NPC:GetY()         return self.y         end
function NPC:GetID()        return self.npcID     end
function NPC:GetLevel()     return self.levelFile  end
function NPC:GetDir()       return self.dir       end
function NPC:SetPosition(x, y) self.x = x; self.y = y end