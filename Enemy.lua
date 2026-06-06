require "Util"
require "Pathfinding"

Enemy = {}

function Enemy:new(idd, xx, yy, dir, animImg, lf, etype, rnpc)
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
               speed = 2,
               dir = dir,
               life = lf,
               state = 0,
               id = idd,
               knowPlPosX = 0,
               knowPlPosY = 0,
               path = {},
               pathIndex = 1,
               audioTime = love.math.random(5, 7),
               audioTimeCount = 0,
               audioZombie = love.audio.newSource("audio/zombie2.mp3", "static"),
               audioBite = love.audio.newSource("audio/bite.mp3", "static"),
               enemyType = etype,
               refNPC = rnpc
               } 
  setmetatable(obj, self)
  self.__index = self
  obj:LoadAnimation()
  obj:Animate(dir, 0)
  return obj
end

function Enemy:LoadAnimation()
  local count = 1  
  for j = 0, 3, 1 do
    for i = 0, 2, 1 do
      self.charQuads[count] = love.graphics.newQuad(i * 45,j * 36, 45, 36, self.charImage:getWidth(), self.charImage:getHeight())
      count = count + 1
    end
  end
end

function Enemy:Animate(dir, dt)
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

function Enemy:SetPosition(x, y)
  self.x = x
  self.y = y
end

function Enemy:CheckPlayerColision(pl)  
    if self.dir == "left" then
      if CheckBoxCollision(((self.x-1) * 32), (self.y * 32), 32, 32, ((player:GetX())*32), (player:GetY()*32), 32, 32) then
        return true
      end
    elseif self.dir == "right" then
      if CheckBoxCollision(((self.x+1) * 32), (self.y * 32), 32, 32, ((player:GetX())*32), (player:GetY()*32), 32, 32) then
        return true
      end
    elseif self.dir == "up" then
      if CheckBoxCollision((self.x * 32), ((self.y-1) * 32), 32, 32, ((player:GetX())*32), ((player:GetY())*32), 32, 32) then
        return true
      end
    elseif self.dir == "down" then
      if CheckBoxCollision((self.x * 32), ((self.y+1) * 32), 32, 32, ((player:GetX())*32), ((player:GetY())*32), 32, 32) then
        return true
      end
    end  
  return false
end

function Enemy:CheckEnemyColision(enemies)
  for x = 1, #enemies, 1 do 
    if self.dir == "down" then
      if CheckBoxCollision((self.x * 32), ((self.y+1) * 32), 32, 32, (enemies[x]:GetX()*32), (enemies[x]:GetY()*32), 32, 32) and self.id ~= enemies[x].id then
        return true
      end
    elseif self.dir == "up" then
      if CheckBoxCollision((self.x * 32), ((self.y-1) * 32), 32, 32, (enemies[x]:GetX()*32), (enemies[x]:GetY()*32), 32, 32) and self.id ~= enemies[x].id then
        return true
      end
    elseif self.dir == "left" then
      if CheckBoxCollision(((self.x-1) * 32), (self.y * 32), 32, 32, (enemies[x]:GetX()*32), (enemies[x]:GetY()*32), 32, 32) and self.id ~= enemies[x].id then
        return true
      end
    elseif self.dir == "right" then
      if CheckBoxCollision(((self.x+1) * 32), (self.y * 32), 32, 32, (enemies[x]:GetX()*32), (enemies[x]:GetY()*32), 32, 32) and self.id ~= enemies[x].id then
        return true
      end
    end
  end

  return false
end

function Enemy:CheckNPCCollision(npcs)
  for _, npc in ipairs(npcs) do
    if self.dir == "down" then
      if CheckBoxCollision(
        (self.x * 32), ((self.y + 1) * 32), 32, 32,
        (npc:GetX() * 32), (npc:GetY() * 32), 32, 32
      ) then return true end
    elseif self.dir == "up" then
      if CheckBoxCollision(
        (self.x * 32), ((self.y - 1) * 32), 32, 32,
        (npc:GetX() * 32), (npc:GetY() * 32), 32, 32
      ) then return true end
    elseif self.dir == "left" then
      if CheckBoxCollision(
        ((self.x - 1) * 32), (self.y * 32), 32, 32,
        (npc:GetX() * 32), (npc:GetY() * 32), 32, 32
      ) then return true end
    elseif self.dir == "right" then
      if CheckBoxCollision(
        ((self.x + 1) * 32), (self.y * 32), 32, 32,
        (npc:GetX() * 32), (npc:GetY() * 32), 32, 32
      ) then return true end
    end
  end
  return false
end

function Enemy:Move(dir, dt, level, pl)
  self.dir = dir

  local dirData = {
    up    = { tx = math.floor(self.x),     ty = math.floor(self.y) - 1, dx = 0,          dy = -self.speed },
    down  = { tx = math.ceil(self.x),      ty = math.ceil(self.y) + 1,  dx = 0,           dy =  self.speed },
    left  = { tx = math.floor(self.x) - 1, ty = math.floor(self.y),     dx = -self.speed, dy = 0           },
    right = { tx = math.ceil(self.x) + 1,  ty = math.ceil(self.y),      dx =  self.speed, dy = 0           }
  }

  local d    = dirData[dir]
  local tile = level:GetTile(d.tx, d.ty)

  local npcs = NPCManager:GetNPCsForLevel(level.levelName)
  if tile == nil or tile.properties.obstacle
    or self:CheckEnemyColision(level.Enemies)
    or self:CheckNPCCollision(npcs) then
    self:Animate(dir, dt)
    return
  end

  if self:CheckPlayerColision(pl) then
    self:Animate(dir, dt)
    pl:Hit(20 * dt)
    if not self.audioBite:isPlaying() then
      love.audio.play(self.audioBite)
    end
    return
  end

  self.xws = self.xws + d.dx
  self.yws = self.yws + d.dy

  self:Animate(dir, dt)
end

function Enemy:Update(dt, level, pl)
  self.xws, self.yws = 0, 0
  local playerdist = dist(self.x, self.y, pl:GetX(), pl:GetY())

  if self.state == 0 then -- idle
    if playerdist < 11 then
      if not self.audioZombie:isPlaying() then
        love.audio.play(self.audioZombie)
      end
      self.state = 1
    end
  elseif self.state == 1 then -- follow and attack
    -- periodic zombie groan
    self.audioTimeCount = self.audioTimeCount + dt
    if self.audioTimeCount >= self.audioTime then
      if not self.audioZombie:isPlaying() then
        love.audio.play(self.audioZombie)
      end
      self.audioTimeCount = 0
    end

    -- recompute path when the player has moved to a different tile
    if math.ceil(pl:GetX()) ~= self.knowPlPosX
       or math.ceil(pl:GetY()) ~= self.knowPlPosY then
      self.path = astar.path(
        { x = math.ceil(self.x),    y = math.ceil(self.y)    },
        { x = math.ceil(pl:GetX()), y = math.ceil(pl:GetY()) },
        level, true
      )
      self.knowPlPosX = math.ceil(pl:GetX())
      self.knowPlPosY = math.ceil(pl:GetY())
      self.pathIndex  = 2
    end

    -- step along the path one waypoint at a time
    if self.path ~= nil and #self.path > 1 then
      local node = self.path[self.pathIndex]
      if node and (self.ys == 0) and (self.xs == 0) then
        if node.x > self.x then
          self:Move("right", dt, level, pl)
        elseif node.x < self.x then
          self:Move("left", dt, level, pl)
        elseif node.y > self.y then
          self:Move("down", dt, level, pl)
        elseif node.y < self.y then
          self:Move("up", dt, level, pl)
        end
        if self.pathIndex < #self.path then
          self.pathIndex = self.pathIndex + 1
        end
      end
    end

    -- lose interest if the player gets far enough away
    if playerdist > 12 then
      self.state = 0
    end
  end

  -- smooth movement integration (same pattern as Player and NPC)
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

function Enemy:Draw()
  love.graphics.draw(self.charImage, self.charQuads[self.frame], (self.x * 32)+19,  (self.y * 32)+17, 0, 1, 1, 20, 20)  
end

function Enemy:GetX()
  return self.x
end

function Enemy:GetY()
  return self.y
end

function Enemy:GetLife()
  return self.life
end

function Enemy:GetEnemyType()
  return self.enemyType
end

function Enemy:SetEnemyType(tt)
  self.enemyType = tt
end

function Enemy:GetRefNPC()
  return self.refNPC
end

function Enemy:Hit(hit)
  self.life = self.life - hit
  self.state = 1
  if AudioAttacked:isPlaying() then
    love.audio.stop(AudioAttacked)
  end
  love.audio.play(AudioAttacked)
  if self.life <= 0 then
    if self.audioZombie:isPlaying() then
      love.audio.stop(self.audioZombie)
    end
  end
  
end

function Enemy:GetDir()
  return self.dir
end

function Enemy:GetID()
  return self.id
end

function Enemy:GetActiveTime()
  return self.activeTime
end

function EnemyWasKilled(id)
  for x = 1, #KilledEnemies, 1 do
    if KilledEnemies[x] == id then
      return true
    end
  end
  return false
end



