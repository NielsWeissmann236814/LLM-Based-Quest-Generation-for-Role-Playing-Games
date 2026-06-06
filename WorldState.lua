local json = require ("libs/dkjson")

WorldState = {}

----------------------------------------------------------------
-- Static world definition
-- Edit this section as the game world grows
----------------------------------------------------------------

WorldState.definition = {

  characters = {
    { id = "john", gameRef = "player" }
  },

  places = {
    { id = "safehouse",    levelFile = "safehouse.tmx",  displayName = "Safehouse",          type = "interior", conditions = {"unlocked"}, defaultX = 13,  defaultY = 11 },
    { id = "village",      levelFile = "world1.tmx",     displayName = "Village",            type = "exterior", conditions = {"unlocked"}, defaultX = 56,  defaultY = 34 },
    { id = "cave",         levelFile = "cave.tmx",       displayName = "Cave",               type = "exterior", conditions = {"unlocked"}, defaultX = 78,  defaultY = 78 },
    { id = "store",        levelFile = "store.tmx",      displayName = "Store",              type = "interior", conditions = {"unlocked"}, defaultX = 8,   defaultY = 10 },
    { id = "hospital1",    levelFile = "hospital1.tmx",  displayName = "Hospital",           type = "interior", conditions = {"unlocked"}, defaultX = 10,  defaultY = 12 },
    { id = "hospital2",    levelFile = "hospital2.tmx",  displayName = "Hospital, 2nd Floor", type = "interior", conditions = {"unlocked"}, defaultX = 9,  defaultY = 12 },
    { id = "laboratory",   levelFile = "laboratory.tmx", displayName = "Laboratory",         type = "interior", conditions = {"locked", "no_power"}, defaultX = 6,  defaultY = 10 },
    { id = "outpost1",     levelFile = "outpost1.tmx",   displayName = "Outpost",            type = "interior", conditions = {"locked"}, defaultX = 10,  defaultY = 10 },
    { id = "outpost2",     levelFile = "outpost2.tmx",   displayName = "Outpost, 2nd Floor",  type = "interior", conditions = {"unlocked"}, defaultX = 13,  defaultY = 8 },
    { id = "outpost3",     levelFile = "outpost3.tmx",   displayName = "Outpost, 3rd Floor",  type = "interior", conditions = {"unlocked"}, defaultX = 9,  defaultY = 9 },
    { id = "farm",         levelFile = "world1.tmx",     displayName = "Farm",               type = "exterior", conditions = {"unlocked"}, defaultX = 17,  defaultY = 15, gate = { x=14, y=18 }, bounds = { x1=11, y1=12, x2=23, y2=18 } },
    { id = "dock",         levelFile = "world1.tmx",     displayName = "Dock",               type = "exterior", conditions = {"unlocked"}, defaultX = 50,  defaultY = 44, gate = { x=50, y=42 }, bounds = { x1=49, y1=42, x2=50, y2=47 } },
    { id = "powerstation", levelFile = "world1.tmx",     displayName = "Power Station",      type = "exterior", conditions = {"unlocked"}, defaultX = 83,  defaultY = 44, gate = { x=83, y=47 }, bounds = { x1=80, y1=41,  x2=86, y2=47 } },
    { id = "graveyard",    levelFile = "world1.tmx",     displayName = "Graveyard",          type = "exterior", conditions = {"unlocked"}, defaultX = 57,  defaultY = 14 , gate = { x=56, y=16 }, bounds = { x1=50, y1=10, x2=60, y2=16 } }
  },

  paths = {
    { "safehouse",     "village" },
    { "village",  "safehouse" },
    { "village",  "store" },
    { "store",    "village" },
    { "village",  "hospital1"},
    { "hospital1", "village" },
    { "hospital1",  "hospital2"},
    { "hospital2", "hospital1" },
    { "village", "laboratory" },
    { "laboratory", "village" },
    { "village", "outpost1" },
    { "outpost1", "village" },
    { "village", "cave" },
    { "cave", "village" },
    { "village", "cave" },
    { "cave", "village" },
    { "outpost1", "outpost2" },
    { "outpost2", "outpost1" },
    { "outpost2", "outpost3" },
    { "outpost3", "outpost2" },
    { "village", "farm" },
    { "farm", "village" },
    { "village", "dock" },
    { "dock", "village" },    
    { "village", "powerstation" },
    { "powerstation", "village" },
    { "village", "graveyard" },
    { "graveyard", "village" }
  },

  objects = {
    { id = "boat", levelFile = "world1.tmx", x = 49, y = 46,
      states = {"broken", "fixed"}, initialState = "broken" }
  },

  connections = {
    {
      from     = { place = "safehouse",  levelFile = "safehouse.tmx",  x = 6,  y = 16 },
      to       = { place = "village",    levelFile = "world1.tmx",     x = 47, y = 33 }
    },
    {
      from     = { place = "village",    levelFile = "world1.tmx",     x = 47, y = 33  },
      to       = { place = "safehouse",  levelFile = "safehouse.tmx",  x = 6,  y = 15  }
    },
    {
      from     = { place = "store",      levelFile = "store.tmx",      x = 8,  y = 13 },
      to       = { place = "village",    levelFile = "world1.tmx",     x = 82, y = 26 }
    },
    {
      from     = { place = "village",    levelFile = "world1.tmx",     x = 82, y = 26 },
      to       = { place = "store",      levelFile = "store.tmx",      x = 8,  y = 13 }
    },    
    {
      from     = { place = "hospital1",  levelFile = "hospital1.tmx",  x = 10,  y = 15},
      to       = { place = "village",    levelFile = "world1.tmx",     x = 60, y = 32 }
    },
    {
      from     = { place = "village",    levelFile = "world1.tmx",     x = 60, y = 32 },
      to       = { place = "hospital1",  levelFile = "hospital1.tmx",  x = 10,  y = 15}
    },
    {
      from     = { place = "laboratory",  levelFile = "laboratory.tmx",  x = 10,  y = 15},
      to       = { place = "village",    levelFile = "world1.tmx",     x = 38, y = 33 }
    },
    {
      from     = { place = "village",    levelFile = "world1.tmx",     x = 38, y = 33 },
      to       = { place = "laboratory",  levelFile = "laboratory.tmx",  x = 10,  y = 15}
    },
    {
      from     = { place = "outpost1",  levelFile = "outpost1.tmx",  x = 10,  y = 15},
      to       = { place = "village",    levelFile = "world1.tmx",     x = 14, y = 40 }
    },
    {
      from     = { place = "village",    levelFile = "world1.tmx",     x = 14, y = 40 },
      to       = { place = "outpost1",  levelFile = "outpost1.tmx",  x = 10,  y = 15}
    },
    {
      from     = { place = "cave",  levelFile = "cave.tmx",  x = 78,  y = 82},
      to       = { place = "village",    levelFile = "world1.tmx",     x = 54, y = 14 }
    },
    {
      from     = { place = "village",    levelFile = "world1.tmx",     x = 54, y = 14 },
      to       = { place = "cave",  levelFile = "cave.tmx",  x = 78,  y = 82}
    },
    {
      from     = { place = "hospital1",  levelFile = "hospital1.tmx",  x = 3,  y = 12},
      to       = { place = "hospital2",    levelFile = "hospital2.tmx",     x = 4, y = 12 }
    },
    {
      from     = { place = "hospital2",    levelFile = "hospital2.tmx",     x = 3, y = 12 },
      to       = { place = "hospital1",  levelFile = "hospital1.tmx",  x = 4,  y = 12}
    },
    {
      from     = { place = "outpost1",  levelFile = "outpost1.tmx",  x = 15,  y = 5},
      to       = { place = "outpost2",    levelFile = "outpost2.tmx",     x =15, y = 6 }
    },
    {
      from     = { place = "outpost2",    levelFile = "outpost2.tmx",     x = 15, y = 5 },
      to       = { place = "outpost1",  levelFile = "outpost1.tmx",  x = 15,  y = 6}
    },
    {
      from     = { place = "outpost2",  levelFile = "outpost1.tmx",  x = 5,  y = 5},
      to       = { place = "outpost3",    levelFile = "outpost3.tmx",     x =5, y = 6 }
    },
    {
      from     = { place = "outpost3",    levelFile = "outpost3.tmx",     x = 5, y = 5 },
      to       = { place = "outpost2",  levelFile = "outpost2.tmx",  x = 5,  y = 6}
    }    
  }

}

WorldState.itemRegistry = {}  -- maps "wood_1" -> instanceID
WorldState.registryReverse = {}  -- maps instanceID -> "wood_1"

function WorldState:RegisterItem(instanceID, defID)
  -- if already registered, return existing label
  if self.registryReverse[instanceID] then
    return self.registryReverse[instanceID]
  end
  -- count existing labels for this type
  local count = 0
  for _, label in pairs(self.registryReverse) do
    if label:match("^" .. defID .. "_") then
      count = count + 1
    end
  end
  local label = defID .. "_" .. (count + 1)
  self.itemRegistry[label]          = instanceID
  self.registryReverse[instanceID]  = label
  print("ItemRegistry: " .. label .. " -> " .. instanceID)
  return label
end

function WorldState:GetInstanceIDFromLabel(label)
  return self.itemRegistry[label]
end

function WorldState:GetLabelFromInstanceID(instanceID)
  return self.registryReverse[instanceID]
end

function WorldState:ClearRegistry()
  self.itemRegistry    = {}
  self.registryReverse = {}
end



function WorldState:FindItemInWorld(label)
  local instanceID = self:GetInstanceIDFromLabel(label)
  if instanceID == nil then
    print("WARNING: No item found for label: " .. label)
    return nil
  end
  -- search current level items
  for _, item in ipairs(level.Itens) do
    if item.instanceID == instanceID then
      return item
    end
  end
  -- item exists but is not in current level
  -- return the ItemManager record so caller knows where it is
  for _, item in ipairs(ItemManager.items) do
    if item.instanceID == instanceID then
      print("Item " .. label .. " is in level: " .. item.levelFile)
      return nil, item.levelFile
    end
  end
  return nil
end

function WorldState:InitDynamicConditions()
  self.dynamicPlaceConditions = {}
  for _, place in ipairs(self.definition.places) do
    if place.conditions then
      for _, c in ipairs(place.conditions) do
        self:AddPlaceCondition(place.id, c)
      end
    end
  end
end

----------------------------------------------------------------
-- Helper: resolve level filename to place id
----------------------------------------------------------------

function WorldState:LevelToPlace(levelFile)
  for _, place in ipairs(self.definition.places) do
    if place.levelFile == levelFile then
      return place.id
    end
  end
  return "unknown"
end

----------------------------------------------------------------
-- Helper: get place definition by id
----------------------------------------------------------------

function WorldState:GetPlaceDef(placeID)
  for _, place in ipairs(self.definition.places) do
    if place.id == placeID then
      return place
    end
  end
  return nil
end


function WorldState:GetKeyForDestination(levelFile)
  for defID, def in pairs(ItemDefinitions) do
    if def.unlocks then
      local place = self:GetPlaceDef(def.unlocks)
      if place and place.levelFile == levelFile then
        return defID
      end
    end
  end
  return nil
end

----------------------------------------------------------------
-- Dynamic state extraction
-- Reads from live game objects to build current world state
----------------------------------------------------------------

function WorldState:Extract()
  return {
    world_state = {
      player      = self:ExtractPlayer(),
      npcs        = self:ExtractNPCs(),
      locations   = self:ExtractLocations(),
      connections = self:ExtractConnections(),
      items       = self:ExtractItems(),
      objects     = self:ExtractObjects()
    }
  }
end

function WorldState:ExtractPlayer()
  return {
    location   = self:GetPlaceForPosition(level.levelName, player:GetX(), player:GetY()),
    conditions = self:ExtractPlayerConditions(),
    inventory  = self:ExtractPlayerInventory()
  }
end

function WorldState:ExtractPlayerConditions()
  local conditions = {}
  if player.life >= 70 then
    table.insert(conditions, "healthy")
  elseif player.life >= 30 then
    table.insert(conditions, "injured")
  else
    table.insert(conditions, "critical")
  end
  return conditions
end

function WorldState:ExtractPlayerInventory()
  local inv = {}
  for _, invItem in ipairs(player.itens) do
    local label = self:GetLabelFromInstanceID(invItem.instanceID)
    table.insert(inv, label or invItem.defID)
  end
  return inv
end

function WorldState:ExtractNPCs()
  local npcs = {}
  if NPCManager == nil or NPCManager.npcs == nil then
    print("WorldState ERROR: NPCManager.npcs is nil")
    return npcs
  end
  for _, npc in ipairs(NPCManager.npcs) do
    local inv = {}
    for _, invItem in ipairs(npc:GetInventory() or {}) do
      local label = self:GetLabelFromInstanceID(invItem.instanceID)
      table.insert(inv, label or invItem.defID)
    end
    local entry = {
      name         = npc.npcID,
      location   =  self:GetPlaceForPosition(npc.levelFile, npc:GetX(), npc:GetY()),
      conditions = npc:GetConditions() or {},
      inventory  = inv
    }
    table.insert(npcs, entry)
  end
  return npcs
end

function WorldState:ExtractLocations()
  local locs = {}
  if self.definition.places == nil then
    print("WorldState ERROR: definition.places is nil")
    return locs
  end
  for _, place in ipairs(self.definition.places) do
    local conditions = self:ExtractPlaceConditions(place.id)
    local entry = {
      name         = place.id,
      type       = place.type,
      conditions = conditions
    }
    -- add access requirements if any key unlocks this place
    local keyLabel = self:GetKeyLabelForPlace(place.id)
    if keyLabel then
      entry.access = { requires_key = keyLabel }
    end
    table.insert(locs, entry)
  end
  return locs
end

function WorldState:ExtractConnections()
  local seen  = {}
  local conns = {}
  for _, path in ipairs(self.definition.paths) do
    local key = path[1] .. "->" .. path[2]
    local rev = path[2] .. "->" .. path[1]
    if not seen[key] and not seen[rev] then
      table.insert(conns, { from = path[1], to = path[2] })
      seen[key] = true
    end
  end
  return conns
end

function WorldState:ExtractItems()
  local items = {}
  if ItemManager == nil or ItemManager.items == nil then
    print("WorldState ERROR: ItemManager.items is nil")
    return items
  end
  for _, item in ipairs(ItemManager.items) do
    local def = ItemDefinitions[item.defID]
    if def and def.type == "collectible" then
      local label    = self:GetLabelFromInstanceID(item.instanceID)
      local location = self:ResolveItemLocation(item)
      table.insert(items, {
        name       = label or item.instanceID,
        type     = item.defID,
        location = location
      })
    end
  end
  table.sort(items, function(a, b) return a.name < b.name end)
  return items
end

function WorldState:ResolveItemLocation(item)
  -- check player inventory
  for _, invItem in ipairs(player.itens) do
    if invItem.instanceID == item.instanceID then
      return "player:inventory"
    end
  end
  -- check NPC inventories
  for _, npc in ipairs(NPCManager.npcs) do
    for _, invItem in ipairs(npc:GetInventory() or {}) do
      if invItem.instanceID == item.instanceID then
        return "npc:" .. npc.npcID
      end
    end
  end
  -- consumed (used up, e.g. medkit)
  if ItemWasConsumed and ItemWasConsumed(item.instanceID) then
    return "consumed"
  end
  -- collected but not in any inventory
  if ItemWasCollected(item.instanceID) then
    return "taken"
  end
  -- still in the world, use fields directly from ItemManager record
  return self:GetPlaceForPosition(item.levelFile, item.x, item.y)
end


function WorldState:ExtractObjects()
  local objs = {}
  if self.definition.objects == nil then return objs end
  for _, objDef in ipairs(self.definition.objects) do
    table.insert(objs, {
      name       = objDef.id,
      location = self:GetPlaceForPosition(objDef.levelFile, objDef.x, objDef.y),
      state    = WorldObjects and WorldObjects[objDef.id] or "unknown"
    })
  end
  return objs
end

-- returns the human-readable label of the key that unlocks a place, if any
function WorldState:GetKeyLabelForPlace(placeID)
  if ItemManager == nil then return nil end
  for _, item in ipairs(ItemManager.items) do
    local def = ItemDefinitions[item.defID]
    if def and def.unlocks == placeID then
      return self:GetLabelFromInstanceID(item.instanceID)
    end
  end
  return nil
end

function WorldState:ToJSON()
  local ws = self:Extract().world_state

  -- encode player with name first
  local player_str = self:EncodeOrdered(
    {"name", "location", "conditions", "inventory"},
    ws.player
  )

  -- encode each NPC with name first
  local npc_parts = {}
  for _, npc in ipairs(ws.npcs) do
    table.insert(npc_parts, self:EncodeOrdered(
      {"name", "location", "conditions", "inventory"},
      npc
    ))
  end

  -- encode each location with name first
  local loc_parts = {}
  for _, loc in ipairs(ws.locations) do
    table.insert(loc_parts, self:EncodeOrdered(
      {"name", "type", "conditions", "access"},
      loc
    ))
  end

  -- encode each item with name first
  local item_parts = {}
  for _, item in ipairs(ws.items) do
    table.insert(item_parts, self:EncodeOrdered(
      {"name", "type", "location"},
      item
    ))
  end

  -- encode each object with name first
  local obj_parts = {}
  for _, obj in ipairs(ws.objects) do
    table.insert(obj_parts, self:EncodeOrdered(
      {"name", "state", "location"},
      obj
    ))
  end

  -- encode each connection with from first
  local conn_parts = {}
  for _, conn in ipairs(ws.connections) do
    table.insert(conn_parts, self:EncodeOrdered(
      {"from", "to"},
      conn
    ))
  end

  -- assemble final JSON with world_state sections in logical order
  local sections = {
    '"player":'      .. player_str,
    '"npcs":'        .. "[" .. table.concat(npc_parts,  ",") .. "]",
    '"locations":'   .. "[" .. table.concat(loc_parts,  ",") .. "]",
    '"connections":' .. "[" .. table.concat(conn_parts, ",") .. "]",
    '"items":'       .. "[" .. table.concat(item_parts, ",") .. "]",
    '"objects":'     .. "[" .. table.concat(obj_parts,  ",") .. "]"
  }

  return '{"world_state":{' .. table.concat(sections, ",") .. "}}"
end

----------------------------------------------------------------
-- Extract player conditions from live game state
----------------------------------------------------------------

function WorldState:ExtractPlayerConditions()
  local conditions = {}
  if player.life >= 70 then
    table.insert(conditions, "healthy")
  elseif player.life >= 30 then
    table.insert(conditions, "injured")
  else
    table.insert(conditions, "critical")
  end
  return conditions
end


----------------------------------------------------------------
-- Extract dynamic conditions for a place
----------------------------------------------------------------

function WorldState:ExtractPlaceConditions(placeID)
  local conditions = {}
  local seen = {}

  local function add(c)
    if not seen[c] then
      table.insert(conditions, c)
      seen[c] = true
    end
  end

  -- 1. dynamic conditions set at runtime (e.g. fortified, power_on)
  if self.dynamicPlaceConditions and self.dynamicPlaceConditions[placeID] then
    for _, c in ipairs(self.dynamicPlaceConditions[placeID]) do
      add(c)
    end
  end

  -- 2. live conditions
  if ZombieManager:HasLivingZombiesIn(placeID) then
    add("dangerous")
  else
    add("safe")
  end

  return conditions
end

----------------------------------------------------------------
-- Check if a key has been used (door was opened)
----------------------------------------------------------------

function WorldState:KeyUsed(keyID)
  -- currently approximated by whether the key item was picked up
  -- and the hospital has been visited
  for _, evtID in ipairs(ActivatedEvents) do
    -- refine this when events are properly mapped to key usage
    if evtID == keyID then return true end
  end
  return false
end

----------------------------------------------------------------
-- Utility: extract just the id fields from a definition list
----------------------------------------------------------------

function WorldState:ExtractIDs(defList)
  local ids = {}
  for _, def in ipairs(defList) do
    table.insert(ids, def.id)
  end
  return ids
end

----------------------------------------------------------------
-- Public: serialize current world state to JSON for the LLM
----------------------------------------------------------------

function WorldState:AddPlaceCondition(placeID, condition)
  if self.dynamicPlaceConditions == nil then
    self.dynamicPlaceConditions = {}
  end
  if self.dynamicPlaceConditions[placeID] == nil then
    self.dynamicPlaceConditions[placeID] = {}
  end
  -- avoid duplicates
  for _, c in ipairs(self.dynamicPlaceConditions[placeID]) do
    if c == condition then return end
  end
  table.insert(self.dynamicPlaceConditions[placeID], condition)
  print("WorldState: " .. placeID .. " condition added: " .. condition)
end

function WorldState:RemovePlaceCondition(placeID, condition)
  if self.dynamicPlaceConditions == nil then return end
  if self.dynamicPlaceConditions[placeID] == nil then return end
  for i, c in ipairs(self.dynamicPlaceConditions[placeID]) do
    if c == condition then
      table.remove(self.dynamicPlaceConditions[placeID], i)
      return
    end
  end
end

function WorldState:GetPlaceConditions(placeID)
  local conditions = {}
  if self.dynamicPlaceConditions and self.dynamicPlaceConditions[placeID] then
    for _, c in ipairs(self.dynamicPlaceConditions[placeID]) do
      table.insert(conditions, c)
    end
  end
  return conditions
end

function WorldState:ExtractItemIDs()
  local ids = {}
  for _, itemData in ipairs(ItemManager.items) do
    local def = ItemDefinitions[itemData.defID]
    if def and def.type == "collectible" then
      table.insert(ids, itemData.instanceID)
    end
  end
  return ids
end

function WorldState:HasPlaceCondition(placeID, condition)
  if self.dynamicPlaceConditions == nil then return false end
  if self.dynamicPlaceConditions[placeID] == nil then return false end
  for _, c in ipairs(self.dynamicPlaceConditions[placeID]) do
    if c == condition then return true end
  end
  return false
end

-- get the connection from placeA to placeB
function WorldState:GetConnection(fromPlace, toPlace)
  for _, conn in ipairs(self.definition.connections) do
    if conn.from.place == fromPlace and conn.to.place == toPlace then
      return conn
    end
  end
  return nil
end

-- find a route (list of place IDs) from startPlace to destPlace
-- uses simple BFS over the paths table
function WorldState:FindRoute(startPlace, destPlace)
  if startPlace == destPlace then return { startPlace } end

  local visited = { [startPlace] = true }
  local queue   = { { place = startPlace, route = { startPlace } } }

  while #queue > 0 do
    local current = table.remove(queue, 1)
    for _, path in ipairs(self.definition.paths) do
      local next = nil
      if path[1] == current.place then next = path[2] end
      if next and not visited[next] then
        local newRoute = {}
        for _, p in ipairs(current.route) do
          table.insert(newRoute, p)
        end
        table.insert(newRoute, next)
        if next == destPlace then
          return newRoute
        end
        visited[next] = true
        table.insert(queue, { place = next, route = newRoute })
      end
    end
  end

  return nil -- no route found
end

function WorldState:GetPlaceForPosition(levelFile, x, y)
  -- check gate-bounded areas first
  for _, place in ipairs(self.definition.places) do
    if place.levelFile == levelFile and place.bounds then
      local b = place.bounds
      if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then
        return place.id
      end
    end
  end
  -- fall back to level-based place
  return self:LevelToPlace(levelFile)
end

function WorldState:EncodeOrdered(keys, data)
  local parts = {}
  for _, k in ipairs(keys) do
    local v = data[k]
    if v ~= nil then
      table.insert(parts, json.encode(k) .. ":" .. json.encode(v))
    end
  end
  return "{" .. table.concat(parts, ",") .. "}"
end