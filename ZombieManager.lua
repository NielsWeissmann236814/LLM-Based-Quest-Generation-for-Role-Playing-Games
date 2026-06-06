require "Enemy"

ZombieManager = {}
ZombieManager.zombies = {}

function ZombieManager:Load()
  self.zombies = {}
  local file = io.open("data/zombies.dat", "r")
  if file == nil then
    print("WARNING: zombies.dat not found")
    return
  end
  print("ZombieManager: zombies.dat opened successfully")

  while true do
    local line = file:read("*line")
    if not line then break end
    line = StringTrim(line)
    if line ~= "" then
      local id, levelFile, x, y, dir, rest =
        line:match("(%S+)%s+(%S+)%s+(%d+)%s+(%d+)%s+(%S+)%s*(.*)")
      if id == nil then
        print("WARNING: Could not parse zombie line: '" .. line .. "'")
      else
        -- last token of rest is enemyType; tokens before it (if any) are conditions
        -- (conditions are parsed but not used yet — kept for symmetry with NPCs)
        local tokens = {}
        for tok in rest:gmatch("%S+") do table.insert(tokens, tok) end
        local enemyType = tonumber(table.remove(tokens)) or 1

        local img  = self:ResolveImage(enemyType)
        local life = self:ResolveLife(enemyType)

        if img == nil then
          print("WARNING: Zombie image is nil for type " .. tostring(enemyType)
            .. " — make sure ZombieManager:Load runs after LoadGameResources")
        end

        local zombie = Enemy:new(
          tonumber(id),       -- numeric ID, matches what Player:UpdateBullets
                              -- inserts into KilledEnemies (Lua's == is type-strict)
          tonumber(x),
          tonumber(y),
          dir,
          img,
          life,
          enemyType,
          nil                 -- refNPC, unused for now
        )

        if zombie ~= nil then
          zombie.levelFile = levelFile   -- attach so we can filter by level
          table.insert(self.zombies, zombie)
          print("ZombieManager: loaded zombie " .. id
            .. " (type " .. enemyType .. ") in " .. levelFile
            .. " at " .. x .. "," .. y)
        else
          print("WARNING: Enemy:new returned nil for zombie " .. id)
        end
      end
    end
  end

  print("ZombieManager: total zombies loaded: " .. #self.zombies)
  file:close()
end

-- mirror of NPCManager:GetNPCsForLevel: returns objects whose levelFile matches
-- AND who are still alive (not in KilledEnemies)
function ZombieManager:GetZombiesForLevel(levelFile)
  local result = {}
  for _, zombie in ipairs(self.zombies) do
    if zombie.levelFile == levelFile and not EnemyWasKilled(zombie:GetID()) then
      table.insert(result, zombie)
    end
  end
  return result
end

-- used by WorldState:ExtractPlaceConditions to answer "is this place dangerous?"
-- works for any place, regardless of which level the player is currently in
function ZombieManager:HasLivingZombiesIn(placeID)
  for _, zombie in ipairs(self.zombies) do
    if not EnemyWasKilled(zombie:GetID()) then
      local zPlace = WorldState:GetPlaceForPosition(
        zombie.levelFile,
        math.ceil(zombie:GetX()),
        math.ceil(zombie:GetY())
      )
      if zPlace == placeID then
        return true
      end
    end
  end
  return false
end

function ZombieManager:GetZombieByID(id)
  for _, zombie in ipairs(self.zombies) do
    if zombie:GetID() == id then return zombie end
  end
  return nil
end

-- centralised so the .dat file only carries the type number
function ZombieManager:ResolveImage(enemyType)
  if enemyType == 1 then return ImgEnemy1 end
  if enemyType == 2 then return ImgEnemy2 end
  if enemyType == 3 then return ImgEnemy3 end
  if enemyType == 4 then return ImgEnemy4 end
  if enemyType == 5 then return ImgEnemy5 end
  if enemyType == 6 then return ImgEnemy6 end
  return ImgEnemy1
end

function ZombieManager:ResolveLife(enemyType)
  return 3
end