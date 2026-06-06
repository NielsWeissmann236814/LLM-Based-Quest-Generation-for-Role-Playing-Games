Bullet = {}

function Bullet:new(x, y, dir)
  local obj = {px = x, 
               py = y,
               dir = dir,
               cam_x = 0,
               cam_y = 0,
               hit = 1} 
  setmetatable(obj, self)
  self.__index = self
  return obj
end

function Bullet:Update(dt)
    if self.dir == "down" then
      self.py = self.py + (300 * dt) + self.cam_y
    elseif self.dir == "up" then
      self.py = self.py - (300 * dt) + self.cam_y
    elseif self.dir == "left" then
      self.px = self.px - (300 * dt) + self.cam_x
    elseif self.dir == "right" then
      self.px = self.px + (300 * dt) + self.cam_x
    end  
end

function Bullet:GetX()
  return self.px
end

function Bullet:GetY()
  return self.py
end

function Bullet:GetDir()
  return self.dir
end

function Bullet:GetHit()
  return self.hit
end

function Bullet:Draw()
  if self.dir == "down" then
    love.graphics.draw(BulletDown, self.px, self.py, 0, 1, 1, 16, 16) 
  elseif self.dir == "up" then
    love.graphics.draw(BulletUp, self.px, self.py, 0, 1, 1, 16, 16)
  elseif self.dir == "left" then
    love.graphics.draw(BulletLeft, self.px, self.py, 0, 1, 1, 16, 16)
  elseif self.dir == "right" then
    love.graphics.draw(BulletRight, self.px, self.py, 0, 1, 1, 16, 16)
  end  
end
