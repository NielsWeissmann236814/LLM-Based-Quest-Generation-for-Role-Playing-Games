BloodSpot = {}

function BloodSpot:new(x, y, lv)
  local obj = {px = x, 
               py = y,
               blood = love.math.random(1, 3),
               spotlevel = lv} 
  setmetatable(obj, self)
  self.__index = self
  return obj
end

function BloodSpot:Draw(lv)
  if lv == self.spotlevel then
    if self.blood == 1 then
      love.graphics.draw(Blood1, (self.px * 32),  (self.py * 32))
    elseif self.blood == 2 then
      love.graphics.draw(Blood2, (self.px * 32),  (self.py * 32))
    elseif self.blood == 3 then
      love.graphics.draw(Blood3, (self.px * 32),  (self.py * 32))
    end  
  end
end
