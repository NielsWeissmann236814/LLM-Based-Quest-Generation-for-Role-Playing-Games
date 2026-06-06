NPCActions = {}

-- Returns: journey table, blockedAtDoor boolean
-- If the route passes through a locked place that the NPC has no key for,
-- the returned journey is TRUNCATED at the door, with a door_locked_no_key
-- failure reaction attached to the last step. The caller can detect this
-- via the second return value if it needs to skip its own final-step append.
function NPCActions:BuildJourney(npc, route)
  local journey = {}

  for i = 1, #route - 1 do
    local fromPlace = route[i]
    local toPlace   = route[i + 1]
    local fromDef   = WorldState:GetPlaceDef(fromPlace)
    local toDef     = WorldState:GetPlaceDef(toPlace)

    if fromDef == nil or toDef == nil then
      print("NPCActions: missing place definition for "
        .. fromPlace .. " or " .. toPlace)
      return nil, false
    end

    if fromDef.levelFile == toDef.levelFile then
      print("NPCActions: same-level transition from " .. fromPlace
        .. " to " .. toPlace .. ", skipping connection lookup")
    else
      local conn = WorldState:GetConnection(fromPlace, toPlace)
      if conn == nil then
        print("NPCActions: no connection from " .. fromPlace
          .. " to " .. toPlace)
        return nil, false
      end

      local destLocked = not WorldState:HasPlaceCondition(toPlace, "unlocked")
      local hasKey     = false
      local unlockPlace = nil

      if destLocked then
        local keyID = WorldState:GetKeyForDestination(toDef.levelFile)
        if keyID and npc:HasItem(keyID) then
          hasKey      = true
          unlockPlace = toPlace
        end
      end

      -- If destination is locked AND we have no key: walk to the door
      -- (the connection's `from` side) and stop there with a reaction.
      if destLocked and not hasKey then
        local placeDisplay = toDef.displayName or toPlace
        table.insert(journey, {
          levelFile        = conn.from.levelFile,
          walkToX          = conn.from.x,
          walkToY          = conn.from.y,
          nextLevel        = nil,  -- do NOT cross over
          arriveAtX        = nil,
          arriveAtY        = nil,
          failureReaction  = {
            category = "door_locked_no_key",
            vars     = { place = placeDisplay }
          }
        })
        print("NPCActions: " .. npc.npcID
          .. " journey truncated at locked door of " .. toPlace)
        return journey, true
      end

      -- Normal step: walk to the door, transition into the destination level.
      table.insert(journey, {
        levelFile   = conn.from.levelFile,
        walkToX     = conn.from.x,
        walkToY     = conn.from.y,
        nextLevel   = conn.to.levelFile,
        arriveAtX   = conn.to.x,
        arriveAtY   = conn.to.y,
        unlockPlace = unlockPlace
      })
    end
  end

  return journey, false
end

function NPCActions:GetCurrentPlace(npc)
  return WorldState:GetPlaceForPosition(
    npc.levelFile,
    math.ceil(npc.x),
    math.ceil(npc.y)
  )
end

function NPCActions:Walk(npc, destPlace, destX, destY, failureReaction)
  local currentPlace = self:GetCurrentPlace(npc)

  if currentPlace == destPlace then
    npc:MoveTo(destX, destY)
    if failureReaction then
      npc.pendingArrivalReaction = failureReaction
    end
    return true
  end

  local destDef = WorldState:GetPlaceDef(destPlace)
  if destDef == nil then
    print("NPCActions: unknown place " .. destPlace)
    return false
  end

  if destDef.levelFile == npc.levelFile and destDef.bounds then
    npc:MoveTo(destX, destY)
    if failureReaction then
      npc.pendingArrivalReaction = failureReaction
    end
    return true
  end

  local route = WorldState:FindRoute(currentPlace, destPlace)
  if route == nil then
    print("NPCActions: no route found from " .. currentPlace
      .. " to " .. destPlace)
    return false
  end

  print("NPCActions: route for " .. npc.npcID .. ": "
    .. table.concat(route, " -> "))

  local journey, blockedAtDoor = self:BuildJourney(npc, route)
  if journey == nil then return false end

  -- If the journey hit a locked door, the truncated journey already has
  -- its failure reaction. Don't append our own final step.
  if not blockedAtDoor then
    table.insert(journey, {
      levelFile        = destDef.levelFile,
      walkToX          = destX,
      walkToY          = destY,
      nextLevel        = nil,
      failureReaction  = failureReaction
    })
  end

  npc:StartJourney(journey)
  NPCManager:PrecalculatePaths(npc)
  return true
end

function NPCActions:PickupItem(npc, itemInstanceID, destPlace, itemX, itemY)
  local currentPlace = self:GetCurrentPlace(npc)
  local destDef      = WorldState:GetPlaceDef(destPlace)

  if destDef == nil then
    print("NPCActions: unknown place " .. destPlace)
    return
  end

  -- verify item exists and is available
  local targetItem = nil
  for _, item in ipairs(ItemManager.items) do
    if item.instanceID == itemInstanceID then
      targetItem = item
      break
    end
  end

  if targetItem == nil then
    print("NPCActions: item not found " .. itemInstanceID)
    return
  end

  if ItemWasCollected(itemInstanceID) or ItemWasConsumed(itemInstanceID) then
    print("NPCActions: item already collected or consumed " .. itemInstanceID)
    return
  end

  print("NPCActions: " .. npc.npcID .. " picking up " .. itemInstanceID
    .. " at " .. destPlace)

  -- same level, no journey needed
  if currentPlace == destPlace then
    npc:StartPickupJourney(nil, itemInstanceID, itemX, itemY)
    NPCManager:PrecalculatePaths(npc)
    return
  end

  -- gate-bounded area in same level, just walk directly
  if destDef.levelFile == npc.levelFile and destDef.bounds then
    npc:StartPickupJourney(nil, itemInstanceID, itemX, itemY)
    NPCManager:PrecalculatePaths(npc)
    return
  end

  -- find route
  local route = WorldState:FindRoute(currentPlace, destPlace)
  if route == nil then
    print("NPCActions: no route found from " .. currentPlace 
      .. " to " .. destPlace)
    return
  end

  -- build journey with lock checks
  local journey, blockedAtDoor = self:BuildJourney(npc, route)
  if journey == nil then return end

  if blockedAtDoor then
    -- can't reach the item; door blocks us. Start the truncated journey
    -- so the NPC reacts at the door.
    npc:StartJourney(journey)
    NPCManager:PrecalculatePaths(npc)
    return
  end

  npc:StartPickupJourney(journey, itemInstanceID, itemX, itemY)
  NPCManager:PrecalculatePaths(npc)
end

function NPCActions:FindDropPosition(npc)
  local px = math.ceil(npc.x)
  local py = math.ceil(npc.y)

  local offsets = {
    down  = {x =  0, y =  1},
    up    = {x =  0, y = -1},
    left  = {x = -1, y =  0},
    right = {x =  1, y =  0}
  }

  -- check facing direction first, then others
  local order = { npc.dir }
  for dir, _ in pairs(offsets) do
    if dir ~= npc.dir then
      table.insert(order, dir)
    end
  end

  for _, dir in ipairs(order) do
    local off = offsets[dir]
    local tx  = px + off.x
    local ty  = py + off.y

    -- check tile walkability
    -- use current level if NPC is loaded, otherwise skip collision check
    local walkable = true
    if npc.levelFile == level.levelName then
      local tile = level:GetTile(tx, ty)
      if tile == nil or tile.properties.obstacle then
        walkable = false
      end
    end

    if walkable then
      -- check no item already at this position
      local occupied = false
      -- check in current level items
      if npc.levelFile == level.levelName then
        for _, item in ipairs(level.Itens) do
          if math.ceil(item:GetX()) == tx 
             and math.ceil(item:GetY()) == ty then
            occupied = true
            break
          end
        end
      end
      -- check in ItemManager for offscreen items
      if not occupied then
        for _, item in ipairs(ItemManager.items) do
          if item.levelFile == npc.levelFile
             and item.x == tx and item.y == ty
             and not ItemWasCollected(item.instanceID) then
            occupied = true
            break
          end
        end
      end

      if not occupied then
        return tx, ty
      end
    end
  end

  -- fallback: NPC's own tile
  return px, py
end


function NPCActions:UnlockNoKey(npc, targetPlace)
  -- Find the connection that ENTERS the locked place; the NPC needs
  -- to walk to its `from` side (the door).
  local doorConn = nil
  for _, conn in ipairs(WorldState.definition.connections) do
    if conn.to.place == targetPlace then
      doorConn = conn
      break
    end
  end
  if doorConn == nil then
    print("NPCActions: no connection found to " .. targetPlace)
    return false
  end

  local doorPlace = doorConn.from.place
  local doorX     = doorConn.from.x
  local doorY     = doorConn.from.y

  local placeDisplay = (WorldState:GetPlaceDef(targetPlace) or {}).displayName
                    or targetPlace

  local reaction = {
    category = "door_locked_no_key",
    vars     = { place = placeDisplay }
  }

  -- Use Walk to route them to the door tile, with the failure reaction.
  local ok = self:Walk(npc, doorPlace, doorX, doorY, reaction)
  if not ok then
    return false
  end
  print("NPCActions: " .. npc.npcID .. " walking to locked door of "
    .. targetPlace .. " (no key)")
  return true
end

function NPCActions:DropItem(npc, itemDefID, targetPlace, itemLabel)
  -- Walk the NPC to targetPlace if they're not already there, then drop on
  -- arrival. itemDefID may be nil (hallucinated label or NPC doesn't carry
  -- it); ExecuteDrop will react accordingly. itemLabel is kept around so
  -- the failure reaction can show the readable name.

  targetPlace = targetPlace or self:GetCurrentPlace(npc)

  local placeDef = WorldState:GetPlaceDef(targetPlace)
  if placeDef == nil then
    print("NPCActions: DropItem unknown place " .. tostring(targetPlace))
    npc:Say(NPCDialog:Pick("unknown_place"), 4)
    return
  end

  local currentPlace = self:GetCurrentPlace(npc)
  local journey      = {}
  local blockedAtDoor = false

  if currentPlace ~= targetPlace then
    local route = WorldState:FindRoute(currentPlace, targetPlace)
    if route == nil then
      print("NPCActions: no route to " .. targetPlace
        .. " for " .. npc.npcID)
      npc:Say(NPCDialog:Pick("no_route"), 4)
      return
    end

    journey, blockedAtDoor = self:BuildJourney(npc, route)
    if journey == nil then
      npc:Say(NPCDialog:Pick("no_route"), 4)
      return
    end

    if blockedAtDoor then
      npc:StartJourney(journey)
      NPCManager:PrecalculatePaths(npc)
      return
    end
  end

  -- final step: walk to the place's default tile and try to drop
  table.insert(journey, {
    levelFile  = placeDef.levelFile,
    walkToX    = placeDef.defaultX,
    walkToY    = placeDef.defaultY,
    nextLevel  = nil,
    isDrop     = true,
    dropDefID  = itemDefID,
    dropLabel  = itemLabel
  })

  npc:StartJourney(journey)
  NPCManager:PrecalculatePaths(npc)
  print("NPCActions: " .. npc.npcID .. " heading to drop "
    .. tostring(itemLabel) .. " at " .. targetPlace)
end

function NPCActions:FortifyLocation(npc, itemDefID, targetPlace)
  itemDefID   = itemDefID   or "wood"
  targetPlace = targetPlace or self:GetCurrentPlace(npc)

  local placeDef = WorldState:GetPlaceDef(targetPlace)
  if placeDef == nil then
    print("NPCActions: FortifyLocation unknown place " .. tostring(targetPlace))
    npc:Say(NPCDialog:Pick("unknown_place"), 4)
    return
  end

  -- exterior - reject up front (caller should also catch this)
  if placeDef.type ~= "interior" then
    npc:Say(NPCDialog:Pick("cant_fortify_outside"), 4)
    return
  end

  local currentPlace = self:GetCurrentPlace(npc)
  local journey      = {}
  local blockedAtDoor = false

  if currentPlace ~= targetPlace then
    local route = WorldState:FindRoute(currentPlace, targetPlace)
    if route == nil then
      print("NPCActions: no route to " .. targetPlace
        .. " for " .. npc.npcID)
      npc:Say(NPCDialog:Pick("no_route"), 4)
      return
    end

    journey, blockedAtDoor = self:BuildJourney(npc, route)
    if journey == nil then
      npc:Say(NPCDialog:Pick("no_route"), 4)
      return
    end

    if blockedAtDoor then
      npc:StartJourney(journey)
      NPCManager:PrecalculatePaths(npc)
      return
    end
  end

  -- final step: walk to the place's default tile and try to fortify
  table.insert(journey, {
    levelFile  = placeDef.levelFile,
    walkToX    = placeDef.defaultX,
    walkToY    = placeDef.defaultY,
    nextLevel  = nil,
    isFortify  = true,
    fortifyDefID = itemDefID,
    fortifyPlace = targetPlace
  })

  -- StartJourney works fine for arbitrary journeys
  npc:StartJourney(journey)
  NPCManager:PrecalculatePaths(npc)
  print("NPCActions: " .. npc.npcID .. " heading to fortify " .. targetPlace)
end

function NPCActions:SynthesizeAntidote(npc)
  local currentPlace = self:GetCurrentPlace(npc)
  local journey      = {}
  local blockedAtDoor = false

  if currentPlace ~= "laboratory" then
    local route = WorldState:FindRoute(currentPlace, "laboratory")
    if route == nil then
      print("NPCActions: no route found to laboratory for " .. npc.npcID)
      npc:Say(NPCDialog:Pick("no_route"), 4)
      return
    end

    journey, blockedAtDoor = self:BuildJourney(npc, route)
    if journey == nil then
      npc:Say(NPCDialog:Pick("no_route"), 4)
      return
    end

    if blockedAtDoor then
      -- can't reach the lab; door blocks us. Start the truncated journey
      -- so the NPC reacts at the locked door.
      npc:StartJourney(journey)
      NPCManager:PrecalculatePaths(npc)
      return
    end
  end

  -- final step: walk to the synthesis machine and try to synthesize
  local labDef = WorldState:GetPlaceDef("laboratory")
  local sampleDef = ItemDefinitions["cure_sample"]
  table.insert(journey, {
    levelFile    = labDef.levelFile,
    walkToX      = sampleDef.useAt.x,
    walkToY      = sampleDef.useAt.y,
    nextLevel    = nil,
    isSynthesize = true
  })

  npc:StartSynthesizeJourney(journey)
  NPCManager:PrecalculatePaths(npc)
  print("NPCActions: " .. npc.npcID .. " heading to synthesize antidote")
end


function NPCActions:WalkAround(npc, place)
  local placeDef = WorldState:GetPlaceDef(place)
  if placeDef == nil then
    print("NPCActions: unknown place " .. tostring(place) .. " for WalkAround")
    return false
  end

  -- pick a random target inside the place (unchanged from before)
  local targetX, targetY
  if placeDef.bounds then
    local b = placeDef.bounds
    for _ = 1, 10 do
      local tx = math.random(b.x1, b.x2)
      local ty = math.random(b.y1, b.y2)
      if npc.levelFile == level.levelName then
        local tile = level:GetTile(tx, ty)
        if tile and not tile.properties.obstacle then
          targetX, targetY = tx, ty
          break
        end
      else
        targetX, targetY = tx, ty
        break
      end
    end
  else
    local cx = placeDef.defaultX or math.ceil(npc.x)
    local cy = placeDef.defaultY or math.ceil(npc.y)
    for _ = 1, 10 do
      local tx = cx + math.random(-3, 3)
      local ty = cy + math.random(-3, 3)
      if npc.levelFile == level.levelName then
        local tile = level:GetTile(tx, ty)
        if tile and not tile.properties.obstacle then
          targetX, targetY = tx, ty
          break
        end
      else
        targetX, targetY = tx, ty
        break
      end
    end
  end

  if targetX == nil then
    print("NPCActions: WalkAround failed to find target in " .. place)
    return false
  end

  print("NPCActions: " .. npc.npcID .. " wandering to " .. targetX .. "," .. targetY
    .. " in " .. place)

  -- build a single-step journey so PrecalculatePaths uses the NPC's level,
  -- not the player's. without this, offscreen NPCs never move and onscreen
  -- ones may path through the wrong tilemap.
  local journey = {
    {
      levelFile = npc.levelFile,
      walkToX   = targetX,
      walkToY   = targetY,
      nextLevel = nil
    }
  }
  npc:StartJourney(journey)
  NPCManager:PrecalculatePaths(npc)
  return true
end

function NPCActions:TurnPowerOn(npc, fuseDefID)
  fuseDefID = fuseDefID or "fuse"

  local useAt        = ItemDefinitions[fuseDefID].useAt
  local currentPlace = self:GetCurrentPlace(npc)
  local journey      = {}
  local blockedAtDoor = false

  if currentPlace ~= "powerstation" then
    local route = WorldState:FindRoute(currentPlace, "powerstation")
    if route == nil then
      print("NPCActions: no route found to powerstation for " .. npc.npcID)
      npc:Say(NPCDialog:Pick("no_route"), 4)
      return
    end

    journey, blockedAtDoor = self:BuildJourney(npc, route)
    if journey == nil then
      npc:Say(NPCDialog:Pick("no_route"), 4)
      return
    end

    if blockedAtDoor then
      -- can't reach the powerstation; door blocks us. Start the truncated
      -- journey so the NPC reacts at the door.
      npc:StartJourney(journey)
      NPCManager:PrecalculatePaths(npc)
      return
    end
  end

  -- final step: walk to the power box and try to install the fuse
  table.insert(journey, {
    levelFile     = useAt.levelFile,
    walkToX       = useAt.x,
    walkToY       = useAt.y,
    nextLevel     = nil,
    isTurnPowerOn = true
  })

  npc:StartTurnPowerOnJourney(journey)
  NPCManager:PrecalculatePaths(npc)
  print("NPCActions: " .. npc.npcID .. " heading to restore power")
end

function NPCActions:Unlock(npc, keyDefID, targetPlace)
  -- Find the connection that ENTERS the locked place; the NPC walks
  -- to its `from` side (the door tile).
  local doorConn = nil
  for _, conn in ipairs(WorldState.definition.connections) do
    if conn.to.place == targetPlace then
      doorConn = conn
      break
    end
  end
  if doorConn == nil then
    print("NPCActions: no connection found to " .. targetPlace)
    npc:Say(NPCDialog:Pick("confused"), 4)
    return
  end

  local doorPlace = doorConn.from.place
  local doorX     = doorConn.from.x
  local doorY     = doorConn.from.y

  local currentPlace = self:GetCurrentPlace(npc)
  local journey      = {}
  local blockedAtDoor = false

  if currentPlace ~= doorPlace then
    local route = WorldState:FindRoute(currentPlace, doorPlace)
    if route == nil then
      print("NPCActions: no route to " .. doorPlace .. " for " .. npc.npcID)
      npc:Say(NPCDialog:Pick("no_route"), 4)
      return
    end

    journey, blockedAtDoor = self:BuildJourney(npc, route)
    if journey == nil then
      npc:Say(NPCDialog:Pick("no_route"), 4)
      return
    end

    if blockedAtDoor then
      -- some OTHER door en route is locked; let the truncated journey
      -- play out (it has its own door_locked_no_key reaction)
      npc:StartJourney(journey)
      NPCManager:PrecalculatePaths(npc)
      return
    end
  end

  -- final step: walk to the door tile and try to unlock the place
  table.insert(journey, {
    levelFile      = doorConn.from.levelFile,
    walkToX        = doorX,
    walkToY        = doorY,
    nextLevel      = nil,
    isUnlock       = true,
    unlockTarget   = targetPlace,
    unlockKeyDefID = keyDefID  -- may be nil; ExecuteUnlock handles it
  })

  npc:StartJourney(journey)
  NPCManager:PrecalculatePaths(npc)
  print("NPCActions: " .. npc.npcID .. " heading to door of " .. targetPlace)
end

function NPC:ExecuteDrop(itemDefID, itemLabel)
  -- no item to drop? react and abort
  if itemDefID == nil or not self:HasItem(itemDefID) then
    self:Say(NPCDialog:Pick("no_item_to_drop", {
      item = NPCDialog:ItemDisplayName(itemLabel)
    }), 4)
    print("NPC " .. self.npcID .. " arrived to drop "
      .. tostring(itemLabel) .. " but doesn't have it")
    if NPCScheduler.runners[self.npcID] then
      NPCScheduler.runners[self.npcID].abortAfterCurrent = true
    end
    return
  end

  -- find the inventory entry to get the instanceID
  local itemInstance = nil
  for _, item in ipairs(self.inventory) do
    if item.defID == itemDefID then
      itemInstance = item
      break
    end
  end

  if itemInstance == nil then
    -- HasItem said yes but the loop didn't find one - shouldn't happen,
    -- but guard against it
    self:Say(NPCDialog:Pick("confused"), 4)
    return
  end

  -- find a free tile next to the NPC
  local tx, ty = NPCActions:FindDropPosition(self)

  -- create a new world Item at the drop position
  local dropped = Item:new(itemDefID, tx, ty, itemInstance.instanceID)
  if dropped == nil then
    print("NPC " .. self.npcID .. " ExecuteDrop: Item:new returned nil")
    return
  end

  -- if the NPC's level is the level the player is in, push directly into
  -- the live items list. otherwise push into the persistent ItemManager.
  if self.levelFile == level.levelName then
    table.insert(level.Itens, dropped)
  else
    table.insert(ItemManager.items, {
      defID      = itemDefID,
      levelFile  = self.levelFile,
      x          = tx,
      y          = ty,
      instanceID = itemInstance.instanceID
    })
  end

  -- un-collect the item so it shows up in WorldState as in-the-world again
  for i, id in ipairs(CollectedItems) do
    if id == itemInstance.instanceID then
      table.remove(CollectedItems, i)
      break
    end
  end

  -- remove from NPC inventory
  self:RemoveItem(itemDefID)

  local def     = ItemDefinitions[itemDefID]
  local name    = def and def.displayName or itemDefID
  local npcDef  = NPCDefinitions[self.npcID]
  local npcName = npcDef and npcDef.displayName or self.npcID

  self:Say(NPCDialog:Pick("dropped"), 4)

  print("NPC " .. self.npcID .. " dropped " .. name
    .. " at " .. tx .. "," .. ty .. " in " .. self.levelFile)
  print("npc_drop: " .. self.npcID .. " -> " .. itemDefID)
end