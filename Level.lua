require "Util"
require "Item"
require "NPC"
require "BloodSpot"
require "ItemDefinitions"

Level = {}

function Level:new(lname)
  local obj = {loader = require("libs.AdvTiledLoader.Loader"),
              map = nil, -- 
              tileLayer = nil,
              Enemies = {},
              Itens = {},
              NPCs = {},
              levelName = lname,
              LevelInfo = {}
              } 
  setmetatable(obj, self)
  self.__index = self
  obj.loader.path = "levels/" 
  obj:LoadLevel(lname, true)  
  return obj
end

function Level:LoadForPathfinding(lname)
  -- reuse the existing loader instance
  self.loader.path = "levels/"
  local tempMap       = self.loader.load(lname)
  local tempTileLayer = tempMap.layers["Colisao"]
  return {
    levelName = lname,
    GetTile   = function(self, x, y)
      return tempTileLayer(math.ceil(x), math.ceil(y))
    end
  }
end

function Level:CreateEnemies(lname)
  self.Enemies = ZombieManager:GetZombiesForLevel(lname)
  print("Level: " .. lname .. " has " .. #self.Enemies .. " enemies")
end

function Level:CreateItens(lname)
  self.Itens = ItemManager:GetItemsForLevel(lname)
  print("Level: " .. lname .. " has " .. #self.Itens .. " items")
end

function Level:GetTile(x, y)
  return self.tileLayer(math.ceil(x), math.ceil(y))
end

function Level:Update(dt, pl)
  --TEMPORARY COMMENT TO DISABLE ZOMBIES
  --for x = 1, #self.Enemies, 1 do    
  --  self.Enemies[x]:Update(dt, self, pl, self.Enemies)
  --end  
  local itemRemoveList = {}
  for x = 1, #self.Itens, 1 do
    if self.Itens[x]:CheckPlayerCollision(pl) then
      table.insert(itemRemoveList, x)
    end    
  end
  for x = 1, #itemRemoveList, 1 do
    table.remove(self.Itens, itemRemoveList[x])
  end 
  self:UpdateGates(pl:GetX(), pl:GetY())
end

function Level:LoadLevel(lname, newgame)  
  for k in pairs(self.NPCs) do
    self.NPCs[k] = nil
  end
  self.levelName = lname
  self.map = self.loader.load(lname)
  self.map.useSpriteBatch = true  
  self.tileLayer = self.map.layers["Colisao"]
  self.NPCs = NPCManager:GetNPCsForLevel(lname)
  
  self.LevelInfo = {}
  for x = 1, self.map.width, 1 do
    self.LevelInfo[x] = {}
    for y = 1, self.map.height, 1 do
      self.LevelInfo[x][y] = 0
    end
  end
  
  self:CreateEnemies(lname)
  self:CreateItens(lname)
  self:SetupGates()
end

function Level:Draw(ftx, fty)
  -- draw atmospheric background behind map
  love.graphics.setColor(0.125, 0.172, 0.133) -- dark greenish-black
  love.graphics.rectangle("fill", -ftx, -fty, BASE_WIDTH, BASE_HEIGHT)
  love.graphics.setColor(1, 1, 1)
  self.map:autoDrawRange(ftx, fty, 1, 1)     
  self.map:draw()
  for x = 1, #self.Itens, 1 do      
    self.Itens[x]:Draw()
  end  
  for x = 1, #BloodSpots, 1 do      
    BloodSpots[x]:Draw(self.levelName)
  end  

  local npcs = NPCManager:GetNPCsForLevel(self.levelName)
  for _, npc in ipairs(npcs) do
    npc:Draw()
  end
  for x = 1, #self.Enemies, 1 do      
    self.Enemies[x]:Draw()
  end
  for _, npc in ipairs(npcs) do
    npc:DrawBalloon()
  end
end

function Level:GetNPCByID(npcid)
  for x = 1, #self.NPCs, 1 do
    if self.NPCs[x]:GetID() == npcid then
      return self.NPCs[x]
    end 
  end
  return nil
end

function Level:GetItemByID(itemid)
  for x = 1, #self.Itens, 1 do
    if self.Itens[x]:GetID() == itemid then
      return self.Itens[x]
    end 
  end
  return nil
end

function Level:GetZombieByID(zombieid)
  for x = 1, #self.Enemies, 1 do
    if self.Enemies[x]:GetID() == zombieid then
      return self.Enemies[x]
    end 
  end
  return nil
end

function Level:UpdateLevelInfo(x, y, info)
  if self.LevelInfo[x][y] ~= info then
    self.LevelInfo[x][y] = info
  end
end

function Level:GetTotalVisited()
  local total = 0
  for x = 1, self.map.width, 1 do
    for y = 1, self.map.height, 1 do
      if self.LevelInfo[x][y] == 1 then
        total = total + 1
      end      
    end
  end
  return total
end

function Level:SetupGates()
  self.gates = {}
  local objLayer = self.map.layers["Objetos2"]
  if objLayer == nil then return end

  for x, col in pairs(objLayer.cells) do
    for y, cell in pairs(col) do
      if type(cell) == "table" and cell.id == 547 then
        table.insert(self.gates, {
          x        = x,
          y        = y,
          closedID = 547,
          openID   = 562,
          isOpen   = false,
          layer    = objLayer
        })
        print("Gate found at " .. x .. "," .. y)
      end
    end
  end
  print("Total gates found: " .. #self.gates)
end

function Level:UpdateGates(px, py)
  local pcx = math.ceil(px)
  local pcy = math.ceil(py)

  for _, gate in ipairs(self.gates) do
    -- check player proximity
    local nearGate = (pcx == gate.x) and
                     (math.abs(pcy - gate.y) <= 1)

    -- check NPC proximity
    if not nearGate then
      local npcs = NPCManager:GetNPCsForLevel(self.levelName)
      for _, npc in ipairs(npcs) do
        local nx = math.ceil(npc.x)
        local ny = math.ceil(npc.y)
        if (nx == gate.x) and (math.abs(ny - gate.y) <= 1) then
          nearGate = true
          break
        end
      end
    end

    if nearGate and not gate.isOpen then
      gate.isOpen = true
      gate.layer:set(gate.x, gate.y, self.map.tiles[gate.openID])
      gate.layer._redraw = true
      for k, _ in pairs(gate.layer._batches) do
        gate.layer._batches[k] = nil
      end
      self.map:forceRedraw()
      print("Gate opened at " .. gate.x .. "," .. gate.y)

    elseif not nearGate and gate.isOpen then
      gate.isOpen = false
      gate.layer:set(gate.x, gate.y, self.map.tiles[gate.closedID])
      gate.layer._redraw = true
      for k, _ in pairs(gate.layer._batches) do
        gate.layer._batches[k] = nil
      end
      self.map:forceRedraw()
      print("Gate closed at " .. gate.x .. "," .. gate.y)
    end
  end
end
