require "NPCDefinitions"

NPCManager = {}
NPCManager.npcs = {}

function NPCManager:Load()
  self.npcs = {}
  local file = io.open("data/npcs.dat", "r")
  if file == nil then
    print("WARNING: npcs.dat not found")
    return
  end
  print("NPCManager: npcs.dat opened successfully")
  while true do
    local line = file:read("*line")
    if not line then break end
    line = StringTrim(line)
    print("NPCManager: reading line: '" .. line .. "'")
    if line ~= "" then
      local npcID, levelFile, x, y, dir, rest =
        line:match("(%S+)%s+(%S+)%s+(%d+)%s+(%d+)%s+(%S+)%s*(.*)")
      if npcID == nil then
        print("WARNING: Could not parse NPC line: '" .. line .. "'")
      else
        local conditions = {}
        local inventory  = {}
        for token in rest:gmatch("%S+") do
          if token:sub(1, 1) == "+" then
            local defID      = token:sub(2)
            local instanceID = defID .. "_npc_" .. npcID .. "_" .. tostring(#inventory + 1)
            table.insert(inventory, { defID = defID, instanceID = instanceID })
            table.insert(CollectedItems, instanceID)
            print("NPCManager: NPC " .. npcID .. " has item: " .. defID)
          else
            table.insert(conditions, token)
          end
        end
        if #conditions == 0 then
          table.insert(conditions, "healthy")
        end
        local npc = NPC:new(npcID, levelFile, tonumber(x), tonumber(y), dir, conditions)
        if npc ~= nil then
          for _, item in ipairs(inventory) do
            npc:AddItem(item.defID, item.instanceID)
          end
          table.insert(self.npcs, npc)
          print("NPCManager: NPC loaded successfully: " .. npcID)
        else
          print("WARNING: NPC:new returned nil for: " .. npcID)
        end
      end
    end
  end
  print("NPCManager: total NPCs loaded: " .. #self.npcs)
  file:close()
end

-- returns only NPCs present in the given level
function NPCManager:GetNPCsForLevel(levelFile)
  local result = {}
  for _, npc in ipairs(self.npcs) do
    if npc.levelFile == levelFile then
      table.insert(result, npc)
    end
  end
  return result
end

function NPCManager:GetNPCByID(npcID)
  for _, npc in ipairs(self.npcs) do
    if npc.npcID == npcID then
      return npc
    end
  end
  return nil
end

-- called when an NPC moves to a different level (future use)
function NPCManager:MoveNPC(npcID, newLevelFile, x, y)
  local npc = self:GetNPCByID(npcID)
  if npc then
    npc.levelFile = newLevelFile
    npc.x = x
    npc.y = y
    print("NPC " .. npcID .. " moved to " .. newLevelFile)
  end
end

function NPCManager:Update(dt, currentLevel)
  for _, npc in ipairs(self.npcs) do
    if npc.levelFile == currentLevel.levelName then
      npc.wasOffscreen = false
      npc:Update(dt, nil, currentLevel)
    else
      npc.wasOffscreen = true
      npc:UpdateOffscreen(dt)
    end
  end
end

function NPCManager:PrecalculatePaths(npc)
  if npc.journey == nil then return end

  for i, step in ipairs(npc.journey) do
    local pathLevel = nil
    if step.levelFile == level.levelName then
      pathLevel = level
    else
      print("NPCManager: loading " .. step.levelFile .. " for pathfinding")
      local ok, result = pcall(function()
        return level:LoadForPathfinding(step.levelFile)
      end)
      if ok then
        pathLevel = result
      else
        print("NPCManager: failed to load " .. step.levelFile 
          .. " for pathfinding: " .. tostring(result))
      end
    end

    if pathLevel == nil then
      print("NPCManager: skipping pathfinding for step " .. i 
        .. " in " .. step.levelFile)
    else
      local startX, startY
      if i == 1 then
        startX = math.ceil(npc.x)
        startY = math.ceil(npc.y)
      else
        local prevStep = npc.journey[i - 1]
        startX = prevStep.arriveAtX or math.ceil(npc.x)
        startY = prevStep.arriveAtY or math.ceil(npc.y)
      end

      local path = astar.path(
        { x = startX,       y = startY },
        { x = step.walkToX, y = step.walkToY },
        pathLevel, true
      )

      if path == nil then
        print("NPCManager: no path found in " .. step.levelFile
          .. " from " .. startX .. "," .. startY
          .. " to " .. step.walkToX .. "," .. step.walkToY)
        local fallback = self:FindNearestWalkable(
          step.walkToX, step.walkToY, pathLevel)
        if fallback then
          print("NPCManager: using fallback position "
            .. fallback.x .. "," .. fallback.y)
          step.walkToX = fallback.x
          step.walkToY = fallback.y
          path = astar.path(
            { x = startX,       y = startY },
            { x = step.walkToX, y = step.walkToY },
            pathLevel, true
          )
        end
      end

      if path then
        step.precalculatedPath = path
        print("NPCManager: precalculated path for step " .. i
          .. " in " .. step.levelFile .. " (" .. #path .. " nodes)")
      else
        print("NPCManager: WARNING path still not found for step " .. i)
      end
    end
  end
end

function NPCManager:FindNearestWalkable(tx, ty, pathLevel)
  -- search in expanding radius for a walkable tile
  for radius = 1, 5 do
    for dx = -radius, radius do
      for dy = -radius, radius do
        if math.abs(dx) == radius or math.abs(dy) == radius then
          local tile = pathLevel:GetTile(tx + dx, ty + dy)
          if tile ~= nil and tile.properties.obstacle == nil then
            return { x = tx + dx, y = ty + dy }
          end
        end
      end
    end
  end
  return nil
end