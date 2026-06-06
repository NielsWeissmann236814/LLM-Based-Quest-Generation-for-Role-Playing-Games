require "ItemDefinitions"

ItemManager = {}
ItemManager.items = {}

function ItemManager:Load()
  self.items = {}
  local file = io.open("data/items.dat", "r")
  if file == nil then
    print("WARNING: items.dat not found")
    return
  end
  print("ItemManager: items.dat opened successfully")
  while true do
    local line = file:read("*line")
    if not line then break end
    line = StringTrim(line)
    if line ~= "" then
      local defID, levelFile, x, y = line:match("(%S+)%s+(%S+)%s+(%d+)%s+(%d+)")
      if defID == nil then
        print("WARNING: Could not parse item line: '" .. line .. "'")
      else
        x = tonumber(x)
        y = tonumber(y)
        local instanceID = defID .. "_" .. levelFile .. "_" .. x .. "_" .. y
        if ItemDefinitions[defID] == nil then
          print("WARNING: No ItemDefinition found for defID: " .. defID)
        else
          table.insert(self.items, {
            defID      = defID,
            levelFile  = levelFile,
            x          = x,
            y          = y,
            instanceID = instanceID
          })
          WorldState:RegisterItem(instanceID, defID)
          print("ItemManager: loaded and registered " .. instanceID .. " as " .. WorldState:GetLabelFromInstanceID(instanceID))
        end
      end
    end
  end
  print("ItemManager: total items loaded: " .. #self.items)
  file:close()
end

function ItemManager:GetItemsForLevel(levelFile)
  local result = {}
  for _, item in ipairs(self.items) do
    if item.levelFile == levelFile
       and not ItemWasCollected(item.instanceID)
       and not ItemWasConsumed(item.instanceID) then
      table.insert(result, Item:new(item.defID, item.x, item.y, item.instanceID))
    end
  end
  return result
end

function ItemManager:AddRuntimeItem(defID, instanceID)
  if ItemDefinitions[defID] == nil then
    print("WARNING: No ItemDefinition found for defID: " .. defID)
    return
  end
  table.insert(self.items, {
    defID      = defID,
    levelFile  = nil,   
    x          = nil,
    y          = nil,
    instanceID = instanceID,
    runtime    = true   
  })
  print("ItemManager: runtime item added " .. instanceID)
end