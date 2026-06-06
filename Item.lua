Item = {}

function Item:new(defID, xx, yy, instanceID)
  local def = ItemDefinitions[defID]
  if def == nil then
    print("WARNING: No ItemDefinition found for defID: " .. tostring(defID))
    return nil
  end
  local obj = {
    defID      = defID,
    instanceID = instanceID or (defID .. "_" .. tostring(xx) .. "_" .. tostring(yy)),
    x          = xx,
    y          = yy
  }
  setmetatable(obj, self)
  self.__index = self
  return obj
end

function Item:GetDefinition()
  return ItemDefinitions[self.defID]
end

function Item:GetDefinitionID()
  return self.defID
end

function Item:GetInstanceID()
  return self.instanceID
end

function ItemWasConsumed(instanceID)
  for _, id in ipairs(ConsumedItems) do
    if id == instanceID then return true end
  end
  return false
end

function Item:CheckPlayerCollision(pl)
  if not CheckBoxCollision(
    (self.x * 32), (self.y * 32), 32, 32,
    (pl:GetX() * 32), (pl:GetY() * 32), 32, 32
  ) then
    return false
  end

  local def = self:GetDefinition()
  if def == nil then return false end

  if def.type == "collectible" then
    if #pl.itens >= 4 then
      MessageQueue:Push("Your inventory is full. Drop an item to pick this up.", 3)
      return false 
    end
    pl:AddItem(self.defID, self.instanceID)
    table.insert(CollectedItems, self.instanceID)
  elseif def.type == "consumable" then
    def.effect(pl)
    table.insert(CollectedItems, self.instanceID)
    if self.defID == "ammo" then
      if not AudioReload:isPlaying() then love.audio.play(AudioReload) end
    elseif self.defID == "medkit" then
      if not AudioMedicine:isPlaying() then love.audio.play(AudioMedicine) end
    end
  end

  print("item_collected: " .. self.instanceID)
  return true
end

function Item:Draw()
  local def = self:GetDefinition()
  if def == nil then return end
  local img = _G[def.image]
  if img then
    love.graphics.draw(img, (self.x * 32), (self.y * 32))
  end
end

function Item:GetX() return self.x end
function Item:GetY() return self.y end

function ItemWasCollected(instanceID)
  for _, id in ipairs(CollectedItems) do
    if id == instanceID then return true end
  end
  return false
end