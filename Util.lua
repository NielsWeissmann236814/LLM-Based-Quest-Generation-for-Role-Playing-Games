function CheckBoxCollision(x1,y1,w1,h1,x2,y2,w2,h2)
  return x1 < x2+w2 and x2 < x1+w1 and y1 < y2+h2 and y2 < y1+h1
end

function round(r,b)
   if b < 0 then
      return math.floor(r)
   elseif b > 0 then
      return math.ceil(r)
   else
      return math.floor(r+0.5)
   end
end

function GetFileName(url)
  return url:match("(.+)%..+")
end

function dist(x1, y1, x2, y2)	
	return math.sqrt(math.pow (x2 - x1, 2) + math.pow (y2 - y1, 2))
end

function table.contains(set, elem)
  for x = 1, #set, 1 do
    if set[x].x == elem.x and set[x].y == elem.y then
      return true
    end
  end
  return false
end

function StringSplit(str, delim, maxNb)
    -- Eliminate bad cases...
    if string.find(str, delim) == nil then
        return { str }
    end
    if maxNb == nil or maxNb < 1 then
        maxNb = 0    -- No limit
    end
    local result = {}
    local pat = "(.-)" .. delim .. "()"
    local nb = 0
    local lastPos
    for part, pos in string.gfind(str, pat) do
        nb = nb + 1
        result[nb] = part
        lastPos = pos
        if nb == maxNb then break end
    end
    -- Handle the last field
    if nb ~= maxNb then
        result[nb + 1] = string.sub(str, lastPos)
    end
    return result
end

function StringTrim(s)
 local from = s:match"^%s*()"
 return from > #s and "" or s:match(".*%S", from)
end

function ComputeAvg(vet)
  local avg = 0
  local n = #vet
  if n == 0 then
    return -1
  end
  for x = 1, n, 1 do
    avg = avg + vet[x]
  end
  return avg/n
end

function ComputeStd(vet, avg)
  local sumOfSqrs = 0
  local n = #vet
  if n == 0 then
    return -1
  elseif n == 1 then
    return 0
  end
  for x = 1, n, 1 do
    sumOfSqrs = sumOfSqrs + math.pow(vet[x] - avg, 2)
  end
  return math.sqrt(sumOfSqrs/n)
end

function GenerateZombieID()
  ZombieIDCount = ZombieIDCount + 1
  return ZombieIDCount
end

  
