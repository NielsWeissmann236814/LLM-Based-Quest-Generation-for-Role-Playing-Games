require "Bullet"
require "BloodSpot"
require "Util"

Player = {}

function Player:new(xx, yy, ddir, animImg)
  local obj = {charQuads = {},
               charImage = animImg,
               frame = 1,
               time = 0,
               xws = 0,
               yws = 0,
               xs = 0,
               ys = 0,
               x = xx,
               y = yy,
               speed = 4,
               dir = ddir,
               bullets = {},
               life = 100,
               bulletCount = 32,
               itens = {}
               } 
  setmetatable(obj, self)
  self.__index = self
  obj:LoadAnimation()
  obj:Animate(ddir, 0)
  return obj
end

function Player:LoadAnimation()
  local count = 1  
  for j = 0, 3, 1 do
    for i = 0, 2, 1 do
      self.charQuads[count] = love.graphics.newQuad(i * 40,j * 40, 40, 40, self.charImage:getWidth(), self.charImage:getHeight())
      count = count + 1
    end
  end
end

function Player:Animate(dir, dt)
  if dir == "up" then
    if self.frame > 9 or self.frame < 7 then
      self.frame = 7
    end
      
    self.time = self.time + dt
    if self.time > 0.1 then      
      self.frame = self.frame + 1
       
      if self.frame > 9 or self.frame < 7 then
        self.frame = 7
      end
      self.time = 0
    end
  elseif dir == "down" then
    if self.frame > 3 then
      self.frame = 1
    end
    
    self.time = self.time + dt
    if self.time > 0.1 then      
      self.frame = self.frame + 1
       
      if self.frame > 3 then
        self.frame = 1
      end
      self.time = 0
    end
  elseif dir == "left" then
    if self.frame > 12 or self.frame < 10 then
      self.frame = 10
    end
    
    self.time = self.time + dt
    if self.time > 0.1 then      
      self.frame = self.frame + 1
       
      if self.frame > 12 or self.frame < 10 then
        self.frame = 10
      end
      self.time = 0
    end
  elseif dir == "right" then
    if self.frame > 6 or self.frame < 4 then
      self.frame = 4
    end
    
    self.time = self.time + dt
    if self.time > 0.1 then      
      self.frame = self.frame + 1
       
      if self.frame > 6 or self.frame < 4 then
        self.frame = 4
      end
      self.time = 0
    end
  end
end

function Player:SetPosition(x, y)
  self.x = x
  self.y = y
end

function Player:SetDirection(dir)
  self.dir = dir
end

function Player:CheckEnemyColision(enemies)
  for x = 1, #enemies, 1 do 
    if self.dir == "down" then
      if CheckBoxCollision((self.x * 32)-25, ((self.y*32)-30)+30, 28, 30, (enemies[x]:GetX()*32)-25, ((enemies[x]:GetY()*32)-30), 28,30) then
        return true
      end
    elseif self.dir == "up" then
      if CheckBoxCollision((self.x * 32)-25, ((self.y*32)-30)-30, 28, 30, (enemies[x]:GetX()*32)-25, ((enemies[x]:GetY()*32)-30), 28,30) then
        return true
      end
    elseif self.dir == "left" then
      if CheckBoxCollision(((self.x * 32)-25)-28, (self.y*32)-30, 28, 30, ((enemies[x]:GetX()*32)-25), ((enemies[x]:GetY()*32)-30), 28,30) then
        return true
      end
    elseif self.dir == "right" then
      if CheckBoxCollision(((self.x * 32)-25)+28, (self.y*32)-30, 28, 30, ((enemies[x]:GetX()*32)-25), ((enemies[x]:GetY()*32)-30), 28,30) then
        return true
      end
    end
  end
  return false
end

function Player:CheckNPCCollision(npcs, dir)
  for _, npc in ipairs(npcs) do
    if dir == "down" then
      if CheckBoxCollision(
        (self.x * 32), ((self.y + 1) * 32), 32, 32,
        (npc:GetX() * 32), (npc:GetY() * 32), 32, 32
      ) then return true end
    elseif dir == "up" then
      if CheckBoxCollision(
        (self.x * 32), ((self.y - 1) * 32), 32, 32,
        (npc:GetX() * 32), (npc:GetY() * 32), 32, 32
      ) then return true end
    elseif dir == "left" then
      if CheckBoxCollision(
        ((self.x - 1) * 32), (self.y * 32), 32, 32,
        (npc:GetX() * 32), (npc:GetY() * 32), 32, 32
      ) then return true end
    elseif dir == "right" then
      if CheckBoxCollision(
        ((self.x + 1) * 32), (self.y * 32), 32, 32,
        (npc:GetX() * 32), (npc:GetY() * 32), 32, 32
      ) then return true end
    end
  end
  return false
end

function Player:Move(dir, dt, level)
  self.dir = dir

  local dirData = {
    up    = { tx = math.floor(self.x),     ty = math.floor(self.y) - 1, dx = 0,  dy = -self.speed },
    down  = { tx = math.ceil(self.x),      ty = math.ceil(self.y) + 1,  dx = 0,  dy =  self.speed },
    left  = { tx = math.floor(self.x) - 1, ty = math.floor(self.y),     dx = -self.speed, dy = 0  },
    right = { tx = math.ceil(self.x) + 1,  ty = math.ceil(self.y),      dx =  self.speed, dy = 0  }
  }

  local d    = dirData[dir]
  local tile = level:GetTile(d.tx, d.ty)

  local npcs = NPCManager:GetNPCsForLevel(level.levelName)
  if tile == nil or tile.properties.obstacle
    or self:CheckEnemyColision(level.Enemies)
    or self:CheckNPCCollision(npcs, dir) then
    self:Animate(dir, dt)
    return
  end

  level:UpdateLevelInfo(d.tx, d.ty, 1)
  self.xws = self.xws + d.dx
  self.yws = self.yws + d.dy

  self:Animate(dir, dt)
end

function Player:UpdateAvatar(dt, tileLayer)
  self.xws, self.yws = 0, 0

  if MovementCooldown > 0 then
    -- animate the idle frame so player doesn't freeze mid-step
    local ranges = { up={7,9}, down={1,3}, left={10,12}, right={4,6} }
    local r = ranges[self.dir]
    if r then self.frame = r[1] end
    return
  end
  
  if love.keyboard.isDown("up") and (self.ys == 0) and (self.xs == 0) then 
    self:Move("up", dt, tileLayer)     
  elseif love.keyboard.isDown("down") and (self.ys == 0) and (self.xs == 0) then 
    self:Move("down", dt, tileLayer)     
  elseif love.keyboard.isDown("left") and (self.ys == 0) and (self.xs == 0) then
    self:Move("left", dt, tileLayer)     
  elseif love.keyboard.isDown("right") and (self.ys == 0) and (self.xs == 0) then 
    self:Move("right", dt, tileLayer)     
  end    
      
  if self.yws ~= 0 and self.xs == 0 then
    self.ys = self.yws
  elseif self.ys ~= 0 then
    self:Animate(self.dir, dt) 
    if round(self.y,self.ys) ~= round(self.y + self.ys * dt,self.ys) then
      self.ys = 0
      self.y = round(self.y,self.ys)      
    end

  end
  if self.xws ~= 0 and self.ys == 0 then
    self.xs = self.xws
  elseif player.xs ~= 0 then
    self:Animate(self.dir, dt) 
    if round(self.x,self.xs) ~= round(self.x + self.xs * dt,self.xs) then
      self.xs = 0
      self.x = round(self.x,self.xs)      
    end
  
  end 
          
  self.x = self.x + self.xs * dt
  self.y = self.y + self.ys * dt
end


function Player:UpdateBullets(dt, level)
  local bulletRemoveList = {}
  local enemyRemoveList = {}
  for x = 1, #self.bullets, 1 do
    --player.bullets[x]:UpdateCam(player.xs, player.ys)
    self.bullets[x]:Update(dt)
    
    if self.bullets[x]:GetDir() == "down" then
      if self.bullets[x]:GetY() > (self.y*32) + (love.graphics.getHeight()/2) + 20 then
        table.insert(bulletRemoveList, x)
      end
    
      local tile = level:GetTile(math.ceil((player.bullets[x]:GetX()/32))-1, math.ceil((player.bullets[x]:GetY()/32))-1)
      if tile ~= nil then
        if tile.properties.obstacle then 
          table.insert(bulletRemoveList, x)
        end
      end
    elseif self.bullets[x]:GetDir() == "up" then
      if self.bullets[x]:GetY() < (self.y*32) - (love.graphics.getHeight()/2) - 20 then
        table.insert(bulletRemoveList, x)
      end
      
      local tile = level:GetTile(math.ceil((player.bullets[x]:GetX()/32))-1, math.ceil((player.bullets[x]:GetY()/32))-1)
      if tile ~= nil then
        if tile.properties.obstacle then 
          table.insert(bulletRemoveList, x)
        end
      end
    elseif self.bullets[x]:GetDir() == "right" then
      if self.bullets[x]:GetX() > (self.x*32) + (BASE_WIDTH/2) + 20 then
        table.insert(bulletRemoveList, x)
      end
      
      local tile = level:GetTile(math.ceil((player.bullets[x]:GetX()/32))-1, math.ceil((player.bullets[x]:GetY()/32))-1)
      if tile ~= nil then
        if tile.properties.obstacle then 
          table.insert(bulletRemoveList, x)
        end
      end
    elseif self.bullets[x]:GetDir() == "left" then
      if self.bullets[x]:GetX() < (self.x*32) - (BASE_WIDTH/2) - 20 then
        table.insert(bulletRemoveList, x)
      end
      
      local tile = level:GetTile(math.ceil((player.bullets[x]:GetX()/32))-1, math.ceil((player.bullets[x]:GetY()/32))-1)
      if tile ~= nil then
        if tile.properties.obstacle then 
          table.insert(bulletRemoveList, x)
        end
      end
    end
    
    for y = 1, #level.Enemies, 1 do 
      if CheckBoxCollision(self.bullets[x]:GetX(), self.bullets[x]:GetY(), 6, 6, (level.Enemies[y]:GetX()*32), (level.Enemies[y]:GetY()*32), 32,32) then
        table.insert(bulletRemoveList, x)
        level.Enemies[y]:Hit(self.bullets[x]:GetHit())
        if level.Enemies[y]:GetLife() <= 0 then
          table.insert(enemyRemoveList, y)
          table.insert(KilledEnemies, level.Enemies[y]:GetID())
          table.insert(BloodSpots, BloodSpot:new(level.Enemies[y]:GetX(), level.Enemies[y]:GetY(), level.levelName))          

          if level.Enemies[y]:GetEnemyType() == 2 then            
            for x = 1, #level.NPCs, 1 do
              if level.Enemies[y]:GetRefNPC() == level.NPCs[x]:GetID() then
                level.NPCs[x]:RemoveBlockingEnemy()
                break
              end              
            end
          end        
        end        
      end    
    end   
    
  end
  for x = 1, #bulletRemoveList, 1 do
    table.remove(self.bullets, bulletRemoveList[x])
  end 
  for x = 1, #enemyRemoveList, 1 do
    table.remove(level.Enemies, enemyRemoveList[x])
  end 

end

function Player:Shoot()
  if self.bulletCount > 0 then
    if self.dir == "down" then
      table.insert(self.bullets, Bullet:new((self.x*32)+5, (self.y*32)+30, self.dir))
    elseif self.dir == "up" then
      table.insert(self.bullets, Bullet:new((self.x*32)+28, (self.y*32)+4, self.dir))
    elseif self.dir == "left" then
      table.insert(self.bullets, Bullet:new((self.x*32)+8, (self.y*32)+26, self.dir))
    else
      table.insert(self.bullets, Bullet:new((self.x*32)+24, (self.y*32)+26, self.dir))
    end
    if AudioShoot:isPlaying() then
      love.audio.stop(AudioShoot)
    end
    
    love.audio.play(AudioShoot)
    self.bulletCount = self.bulletCount - 1
  end
end

function Player:Draw()
  love.graphics.draw(self.charImage, self.charQuads[self.frame], 
    (BASE_WIDTH/2) + 16, (BASE_HEIGHT/2) + 13, 0, 1, 1)
end

function Player:DrawHUD()
  -- health bar
  love.graphics.setColor(0, 0, 0)
  love.graphics.rectangle("line", 50, 14, 200, 25)
  love.graphics.setColor(1, 0, 0, 0.75)
  love.graphics.rectangle("fill", 50, 14, self.life * 2, 25)
  love.graphics.setColor(1, 1, 1, 1)

  -- icons
  love.graphics.draw(IconGun, 10, 40)
  love.graphics.draw(IconPlayer, 10, 10)

  -- inventory
  self:DrawItens()

  -- ammo
  for x = 1, self.bulletCount, 1 do
    love.graphics.line(50 + (x * 3), 45, 50 + (x * 3), 65)
  end
end

function Player:DrawBullets()
  for x = 1, #self.bullets, 1 do      
    self.bullets[x]:Draw()
  end
end

function Player:DrawItens()
  if #self.itens >= 4 then 
    love.graphics.rectangle("line", 169, 45, 80, 20)
    love.graphics.line(189, 47, 189, 63)
    love.graphics.line(209, 47, 209, 63)
    love.graphics.line(229, 47, 229, 63)
  elseif #self.itens == 3 then
    love.graphics.rectangle("line", 169, 45, 60, 20)
    love.graphics.line(189, 47, 189, 63)
    love.graphics.line(209, 47, 209, 63)
  elseif #self.itens == 2 then
    love.graphics.rectangle("line", 169, 45, 40, 20)
    love.graphics.line(189, 47, 189, 63)
  elseif #self.itens == 1 then
    love.graphics.rectangle("line", 169, 45, 20, 20)
  end
  for x = 1, #self.itens, 1 do
    local def = ItemDefinitions[self.itens[x].defID]
    if def then
      local imgName = def.inventoryImage or def.image
      local img = _G[imgName]
      if img then
        love.graphics.draw(img, 162 + (20 * x) - 20, 38)
      end
    end
  end
end

function Player:GetX()
  return self.x
end

function Player:GetY()
  return self.y
end

function Player:GetDir()
  return self.dir
end

function Player:Hit(hit)
  if self.life > 0 then
    self.life = self.life - hit
  end
  Shader:TriggerHit()
  if self:HasItem("antidote_hospital") then
    self:RemoveItem("antidote_hospital")
    GameState = 3
  elseif self:HasItem("antidote_store") then
    self:RemoveItem("antidote_store")
    GameState = 3
  end
end

function Player:AddAmmunition(qtd)
  self.bulletCount = self.bulletCount + qtd
  if self.bulletCount > 32 then
    self.bulletCount = 32
  end
end

function Player:AddLife(qtd)
  self.life = self.life + qtd
  
  if self.life > 100 then
    self.life = 100
  end
end

function Player:AddItem(defID, instanceID)
  if #self.itens >= 4 then return false end
  local id = instanceID or (defID .. "_" .. tostring(os.time()))
  for _, item in ipairs(self.itens) do
    if item.instanceID == id then return false end
  end
  table.insert(self.itens, { defID = defID, instanceID = id })
  return true
end

function Player:RemoveItem(defID)
  for i, item in ipairs(self.itens) do
    if item.defID == defID then
      table.remove(self.itens, i)
      return
    end
  end
end

function Player:HasItem(defID)
  for _, item in ipairs(self.itens) do
    if item.defID == defID then return true end
  end
  return false
end

function Player:IsAlive()
  if (self.life > 0) then
    return true
  else
    EndGame = true    
    return false
  end
end

function Player:TryUseItems(level)
  for _, invItem in ipairs(self.itens) do
    local def = ItemDefinitions[invItem.defID]
    if def and def.use then
      -- check all preconditions
      local allMet    = true
      local failMsg   = nil
      for _, pre in ipairs(def.use.preconditions) do
        if not pre.check() then
          allMet  = false
          failMsg = pre.failMessage
          break
        end
      end

      if allMet then
        -- run the effect
        def.use.effect()
        -- consume the item if needed
        if def.use.consumeOnUse then
          self:RemoveItem(invItem.defID)
        end
        return true
      elseif failMsg then
        -- only show fail message if player is near the useAt location
        -- to avoid spamming messages for items not relevant to current location
        if def.useAt and level.levelName == def.useAt.levelFile then
          MessageQueue:Push(failMsg, 3)
        end
      end
    end
  end
  return false
end
