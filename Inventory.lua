Inventory = {}

Inventory.open       = false
Inventory.selectedSlot = 1

function Inventory:Open()
  self.open          = true
  self.selectedSlot  = 1
  GameState          = 4
end

function Inventory:Close()
  self.open  = false
  GameState  = 1
end

function Inventory:Toggle()
  if self.open then
    self:Close()
  else
    self:Open()
  end
end

function Inventory:MoveSelection(dir)
  if dir == "right" then
    self.selectedSlot = math.min(self.selectedSlot + 1, #player.itens)
  elseif dir == "left" then
    self.selectedSlot = math.max(self.selectedSlot - 1, 1)
  end
end


function Inventory:FindDropPosition()
  -- check tiles in order: facing direction first, then others, then current
  local px = math.ceil(player:GetX())
  local py = math.ceil(player:GetY())
  local facing = player:GetDir()

  local offsets = {
    down  = {x =  0, y =  1},
    up    = {x =  0, y = -1},
    left  = {x = -1, y =  0},
    right = {x =  1, y =  0}
  }

  -- build check order: facing direction first, then the rest
  local order = { facing }
  for dir, _ in pairs(offsets) do
    if dir ~= facing then
      table.insert(order, dir)
    end
  end

  for _, dir in ipairs(order) do
    local off = offsets[dir]
    local tx  = px + off.x
    local ty  = py + off.y

    -- check tile is walkable
    local tile = level:GetTile(tx, ty)
    if tile ~= nil and not tile.properties.obstacle then
      -- check no item already at this position
      local occupied = false
      for _, item in ipairs(level.Itens) do
        if math.ceil(item:GetX()) == tx and math.ceil(item:GetY()) == ty then
          occupied = true
          break
        end
      end
      if not occupied then
        return tx, ty
      end
    end
  end

  -- fallback: player's own tile
  return px, py
end


function Inventory:DropSelected()
  if #player.itens == 0 then return end
  local item = player.itens[self.selectedSlot]
  if item == nil then return end

  local tx, ty = self:FindDropPosition()

  local dropped = Item:new(item.defID, tx, ty, item.instanceID)
  if dropped then
    table.insert(level.Itens, dropped)
    for i, id in ipairs(CollectedItems) do
      if id == item.instanceID then
        table.remove(CollectedItems, i)
        break
      end
    end
    player:RemoveItem(item.defID)
    print("Dropped item: " .. item.defID .. " at " .. tx .. "," .. ty)
  end

  if self.selectedSlot > #player.itens then
    self.selectedSlot = math.max(1, #player.itens)
  end
end

function Inventory:UseSelected()
  if #player.itens == 0 then return end
  local item = player.itens[self.selectedSlot]
  if item == nil then return end

  local def = ItemDefinitions[item.defID]
  if def == nil or def.use == nil then
    MessageQueue:Push("This item cannot be used.", 2)
    return
  end

  -- check preconditions
  for _, pre in ipairs(def.use.preconditions) do
    if not pre.check() then
      MessageQueue:Push(pre.failMessage, 2)
      return
    end
  end

  -- execute effect
  def.use.effect()

  -- consume if needed
  if def.use.consumeOnUse then
    -- add to permanently consumed list
    table.insert(ConsumedItems, item.instanceID)
    -- also remove from collected so world state is clean
    for i, id in ipairs(CollectedItems) do
        if id == item.instanceID then
        table.remove(CollectedItems, i)
        break
        end
    end
    player:RemoveItem(item.defID)
    if self.selectedSlot > #player.itens then
        self.selectedSlot = math.max(1, #player.itens)
    end
    end

  if def.use.closeOnUse ~= false then
    self:Close()
  end
end

function Inventory:FindNearbyNPC()
  local px   = math.ceil(player:GetX())
  local py   = math.ceil(player:GetY())
  local npcs = NPCManager:GetNPCsForLevel(level.levelName)
  for _, npc in ipairs(npcs) do
    local nx = math.ceil(npc:GetX())
    local ny = math.ceil(npc:GetY())
    if math.abs(nx - px) <= 1 and math.abs(ny - py) <= 1 then
      return npc
    end
  end
  return nil
end

function Inventory:GiveSelected()
  if #player.itens == 0 then return end
  local item = player.itens[self.selectedSlot]
  if item == nil then return end

  local npc = self:FindNearbyNPC()
  if npc == nil then
    MessageQueue:Push("There is nobody nearby to give this to.", 3)
    return
  end

  -- transfer item from player to NPC
  npc:AddItem(item.defID, item.instanceID)
  player:RemoveItem(item.defID)

  local itemDef = ItemDefinitions[item.defID]
  local itemName = itemDef and itemDef.displayName or item.defID
  local npcDef  = NPCDefinitions[npc.npcID]
  local npcName = npcDef and npcDef.displayName or npc.npcID

  MessageQueue:Push("You gave " .. itemName .. " to " .. npcName .. ".", 3)

  if self.selectedSlot > #player.itens then
    self.selectedSlot = math.max(1, #player.itens)
  end

  print("item_given: " .. item.defID .. " -> " .. npc.npcID)
  self:Close()
end

function Inventory:Draw()
  if not self.open then return end

  local panelW   = 320
  local panelH   = 200
  local panelX   = (BASE_WIDTH  / 2) - (panelW / 2)
  local panelY   = (BASE_HEIGHT / 2) - (panelH / 2)
  local slotSize = 48
  local slotPad  = 12
  local slotsX   = panelX + (panelW - (4 * slotSize + 3 * slotPad)) / 2
  local slotsY   = panelY + 42

  -- background panel (matches QuestUI / MessageBox style)
  love.graphics.setColor(0.05, 0.05, 0.05, 0.92)
  love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 6, 6)
  love.graphics.setColor(0.7, 0.6, 0.1)   -- gold border = interactive panel
  love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 6, 6)

  -- title (gold, matches QuestUI chapter title)
  love.graphics.setFont(myfont)
  love.graphics.setColor(0.85, 0.75, 0.2)
  local titleText = "INVENTORY"
  local titleW    = myfont:getWidth(titleText)
  love.graphics.print(titleText, panelX + (panelW - titleW) / 2, panelY + 10)

  -- slots
  for i = 1, 4 do
    local sx = slotsX + (i - 1) * (slotSize + slotPad)
    local sy = slotsY

    love.graphics.setColor(0.15, 0.15, 0.15)
    love.graphics.rectangle("fill", sx, sy, slotSize, slotSize, 4, 4)

    if i == self.selectedSlot then
      love.graphics.setColor(0.85, 0.75, 0.2)   -- gold = selected (matches title)
    else
      love.graphics.setColor(0.35, 0.35, 0.35)
    end
    love.graphics.rectangle("line", sx, sy, slotSize, slotSize, 4, 4)

    local item = player.itens[i]
    if item then
      local def = ItemDefinitions[item.defID]
      if def then
        local imgName = def.inventoryImage or def.image
        local img = _G[imgName]
        if img then
          local ix = sx + (slotSize / 2) - (img:getWidth()  / 2)
          local iy = sy + (slotSize / 2) - (img:getHeight() / 2)
          love.graphics.setColor(1, 1, 1)
          love.graphics.draw(img, ix, iy)
        end
      end
    end
  end

  -- selected item info
  local detailY  = slotsY + slotSize + 14
  local hintY    = detailY + 22
  local hintGap  = 18

  local selected = player.itens[self.selectedSlot]
  if selected then
    local def = ItemDefinitions[selected.defID]
    love.graphics.setFont(myfont)
    love.graphics.setColor(0.95, 0.95, 0.95)
    love.graphics.print(def and def.displayName or selected.defID,
      panelX + 12, detailY)

    love.graphics.setFont(myfont2)
    local nearNPC = self:FindNearbyNPC()
    local hasUse  = def and def.use ~= nil

    -- collect available actions, draw them on consecutive lines
    local lines = {}
    if hasUse then
      table.insert(lines, { key = "[Enter]", label = def.use.label })
    end
    if nearNPC then
      local npcDef  = NPCDefinitions[nearNPC.npcID]
      local npcName = npcDef and npcDef.displayName or nearNPC.npcID
      table.insert(lines, { key = "[G]", label = "Give to " .. npcName })
    end
    table.insert(lines, { key = "[D]",      label = "Drop" })
    table.insert(lines, { key = "[Escape]", label = "Close" })

    for i, ln in ipairs(lines) do
      local y = hintY + (i - 1) * hintGap
      -- key label in gold accent, action in muted text
      love.graphics.setColor(0.85, 0.75, 0.2)
      love.graphics.print(ln.key, panelX + 12, y)
      love.graphics.setColor(0.7, 0.7, 0.7)
      local keyW = myfont2:getWidth(ln.key)
      love.graphics.print(ln.label, panelX + 12 + keyW + 8, y)
    end
  else
    love.graphics.setFont(myfont)
    love.graphics.setColor(0.5, 0.5, 0.5)
    love.graphics.print("No items", panelX + 12, detailY)

    love.graphics.setFont(myfont2)
    love.graphics.setColor(0.85, 0.75, 0.2)
    love.graphics.print("[Escape]", panelX + 12, hintY)
    love.graphics.setColor(0.7, 0.7, 0.7)
    love.graphics.print("Close", panelX + 12 + myfont2:getWidth("[Escape]") + 8, hintY)
  end

  love.graphics.setColor(1, 1, 1)
  love.graphics.setFont(myfont)
end