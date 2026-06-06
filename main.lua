require "Debug"
require "Enemy"
require "Player"
require "Level"
require "WorldState"
require "ItemDefinitions"
require "NPCManager"
require "NPCDefinitions"
require "NPCActions"
require "ItemManager"
require "Inventory"
require "Shader"
require "QuestSystem"
require "QuestRunner"
require "NPCDialog"
require "NPCBehaviorSystem"
require "NPCScheduler"
require "MessageBox"
require "MessageQueue"
require "QuestDialog"
require "QuestUI"
require "ZombieManager"

local json = require ("libs/dkjson")

BASE_WIDTH = 800
BASE_HEIGHT = 600
SCALE = 2
LLM_QUESTS = true
LLM_NPCS = false

local lastLockedDest = nil 

function love.load(arg)  
  -- set nearest neighbour filtering for pixel perfect scaling
  love.graphics.setDefaultFilter("nearest", "nearest")  
  -- create the canvas at base resolution
  GameCanvas = love.graphics.newCanvas(BASE_WIDTH, BASE_HEIGHT)
  UICanvas   = love.graphics.newCanvas(BASE_WIDTH, BASE_HEIGHT)
  Shader:Load()
  TitleBackground = love.graphics.newImage("images/title_screen.png")
  TitleText = love.graphics.newImage("images/title_text.png")
  AudioBackground = love.audio.newSource("audio/background.mp3", "static")
  myfont = love.graphics.newFont("font/vrinda.ttf", 20)
  love.graphics.setFont(myfont)
  GameState = 0
  GameMessage = ""
  GameMessageTime = 0
  Loading = false
  ResourcesLoaded = false
  GenerationState = "idle"   -- "idle" | "generating" | "ready" | "failed"
  GenerationError = nil
  love.audio.play(AudioBackground)
end

function InitGame()      
  CaptureStartTime = os.date("*t", os.time()) 
  KilledEnemies = {}
  BloodSpots = {}
  CollectedItems = {}
  ConsumedItems   = {}
  InteractedNPCs = {}
  ActivatedEvents = {}
  GameMessage = ""
  GameMessageTime = 0
  LevelTransitionCooldown = 0
  MovementCooldown = 0
  ActionTimer = 0.5  -- wait 0.5 seconds before triggering NPC actions
  ActionTimerDone = false
  StartRecording = true
  WorldState:ClearRegistry()
  WorldState:InitDynamicConditions()
  ItemManager:Load()
  NPCManager:Load()
  ZombieManager:Load()
  QuestSystem:Load()
  NPCBehaviorSystem:Load()
  player = Player:new(14, 6, "right", PlayerImg)
  level = Level:new("safehouse.tmx")
  Shader:SetInterior()
  love.audio.stop(AudioBackground)
  love.audio.play(AudioBackground2)  
  ZombieIDCount = 100
  WorldObjects = {}
  for _, obj in ipairs(WorldState.definition.objects) do
    WorldObjects[obj.id] = obj.initialState
  end  
end

function LoadGameResources()
  if not ResourcesLoaded then
    PlayerImg = love.graphics.newImage("images/player/player01_gun.png")
    IconPlayer = love.graphics.newImage("images/player/player_icon.png")
    IconGun = love.graphics.newImage("images/player/player_gun_icon.png")

    BulletUp = love.graphics.newImage("images/player/bullet_up.png")
    BulletDown = love.graphics.newImage("images/player/bullet_down.png")
    BulletLeft = love.graphics.newImage("images/player/bullet_left.png")
    BulletRight = love.graphics.newImage("images/player/bullet_right.png")  

    ImgEnemy1 = love.graphics.newImage("images/npcs/zombie01.png")
    ImgEnemy2 = love.graphics.newImage("images/npcs/zombie02.png")
    ImgEnemy3 = love.graphics.newImage("images/npcs/zombie03.png")
    ImgEnemy4 = love.graphics.newImage("images/npcs/zombie04.png")
    ImgEnemy5 = love.graphics.newImage("images/npcs/zombie05.png")
    ImgEnemy6 = love.graphics.newImage("images/npcs/zombie06.png")

    ImgNPC1 = love.graphics.newImage("images/npcs/npc01.png")
    ImgNPC2 = love.graphics.newImage("images/npcs/npc02.png")
    ImgNPC3 = love.graphics.newImage("images/npcs/npc03.png")
    ImgNPC4 = love.graphics.newImage("images/npcs/npc04.png")
    ImgNPC5 = love.graphics.newImage("images/npcs/npc05.png")
    ImgNPC6 = love.graphics.newImage("images/npcs/npc06.png")
    ImgNPC7 = love.graphics.newImage("images/npcs/npc07.png")
    ImgNPC8 = love.graphics.newImage("images/npcs/npc08.png")

    AudioShoot = love.audio.newSource("audio/shoot.mp3", "static")
    AudioReload = love.audio.newSource("audio/reload.mp3", "static")
    AudioMedicine = love.audio.newSource("audio/medicine.mp3", "static")
    AudioAttacked = love.audio.newSource("audio/attacked.mp3", "static")
    AudioDeathNPC1 = love.audio.newSource("audio/death1.mp3", "static")
    AudioDeathNPC2 = love.audio.newSource("audio/death2.mp3", "static")
    AudioDeathNPC3 = love.audio.newSource("audio/death3.mp3", "static")
    AudioBackground2 = love.audio.newSource("audio/background2.mp3", "static")
        
    ItemAmmunition = love.graphics.newImage("images/items/ammunition.png")
    ItemMedicKit = love.graphics.newImage("images/items/medickit.png")
    ItemAntidote = love.graphics.newImage("images/items/antidote.png")
    ItemSample = love.graphics.newImage("images/items/sample.png")
    ItemKey = love.graphics.newImage("images/items/key.png")
    ItemFood = love.graphics.newImage("images/items/food_supplies.png")
    ItemFoodIcon = love.graphics.newImage("images/items/food_supplies_icon.png")
    ItemWood = love.graphics.newImage("images/items/wood.png")
    ItemToolkit = love.graphics.newImage("images/items/toolkit.png")
    ItemFuse = love.graphics.newImage("images/items/fuse.png")
    ItemWoodIcon = love.graphics.newImage("images/items/wood_icon.png")
           
    GameOverText = love.graphics.newImage("images/game_over.png")
    Blood1 = love.graphics.newImage("images/blood01.png")
    Blood2 = love.graphics.newImage("images/blood02.png")
    Blood3 = love.graphics.newImage("images/blood03.png")
    myfont2 = love.graphics.newFont("font/vrinda.ttf", 14)        
    ResourcesLoaded = true
  end
end

function ClearObjects()
  for k in pairs(KilledEnemies) do
    KilledEnemies[k] = nil
  end  
  for k in pairs(BloodSpots) do
    BloodSpots[k] = nil
  end  
  for k in pairs(InteractedNPCs) do
    InteractedNPCs[k] = nil
  end  
  for k in pairs(ActivatedEvents) do
    ActivatedEvents[k] = nil
  end  
end


function DoLevelTransition(dest, doorx, doory, direction)
  print("DoLevelTransition: dest=" .. tostring(dest) 
    .. " doorx=" .. tostring(doorx) 
    .. " doory=" .. tostring(doory))
  if dest == nil or doorx == nil or doory == nil then
    print("DoLevelTransition: ERROR - nil values, transition aborted")
    return
  end
  level:LoadLevel(dest, false)
  player:SetPosition(doorx, doory)
  if direction then
    player:SetDirection(direction)
  end

  local place = WorldState:GetPlaceDef(WorldState:LevelToPlace(dest))
  if place and place.type == "interior" then
    Shader:SetInterior()
  else
    Shader:SetExterior()
  end

  -- set cooldown after transition
  LevelTransitionCooldown = 0.5
  MovementCooldown = 0.4

  print("level_transition: " .. dest)
end


function CheckMapEvent(x, y, dir)
  if LevelTransitionCooldown > 0 or MovementCooldown > 0 then return end

  if dir == "up" then y = y - 1 end

  local tile = level:GetTile(x, y)
  if tile == nil then
    lastLockedDest = nil
    return
  end
  if tile.properties.obstacle then
    lastLockedDest = nil
    return
  end

  local dest = tile.properties.destination
  if dest == nil then
    lastLockedDest = nil
    return
  end

  if tile.properties.target_x == nil or tile.properties.target_y == nil then
    print("ERROR: door tile at " .. x .. "," .. y ..
              " in " .. level.levelName ..
              " is missing target_x/target_y properties")
    return
  end

  if tile.properties.locked and tile.properties.locked == 1 then
    local placeID = WorldState:LevelToPlace(dest)
    if not WorldState:HasPlaceCondition(placeID, "unlocked") then
      if lastLockedDest ~= dest then
        MessageQueue:Push("The door is locked.", 2)
        lastLockedDest = dest
      end
      return
    end
  end

  -- not a locked door (or unlocked now)
  lastLockedDest = nil

  DoLevelTransition(dest, tile.properties.target_x, tile.properties.target_y, tile.properties.target_direction)
end

function love.update(dt)
  local ok, err = xpcall(function()

    QuestSystem:Update(dt)
    NPCBehaviorSystem:Update(dt)
    NPCScheduler:Update(dt)
    QuestRunner:Update(dt)
    QuestDialog:Update(dt)

    if Loading then
      -- fade to black while still on the title screen
      if LoadingTime < 255 and GameState == 0 then
        LoadingTime = LoadingTime + (150 * dt)
      elseif GameState == 0 then
        GameState = 1
        LoadGameResources()
        InitGame()
        if LLM_QUESTS then
          -- kick off chapter generation now that everything is initialised
          if GenerationState == "idle" then
            GenerationState = "generating"
            GenerationStartTime = love.timer.getTime()
            QuestSystem:GenerateChapter("C1", function(data, err)
              if err then
                GenerationState = "failed"
                GenerationError = err
              else
                GenerationState = "ready"
                QuestRunner:Start(data)
                if LLM_NPCS then
                  NPCBehaviorSystem:QueueAll()
                end
              end
            end)
          end
        else
          if LLM_NPCS then
            NPCBehaviorSystem:QueueAll()
          end
        end
      end

      -- once generation is ready (or skipped), fade out
      if GameState ~= 0 and GenerationState ~= "generating" then
        if LoadingTime > 0 then
          LoadingTime = LoadingTime - (150 * dt)
        else
          Loading = false
        end
      end
    end

    MessageQueue:Update(dt)
    
    if GameState ~= 0 then   
      if not AudioBackground2:isPlaying() then
        love.audio.play(AudioBackground2)
      end
      if GameMessageTime > 0 then
        GameMessageTime = GameMessageTime - dt
      end
    end

    if GameState == 1 then 
      
      if ActionTimer > 0 then
        ActionTimer = ActionTimer - dt
        if ActionTimer <= 0 and not ActionTimerDone then
          ActionTimerDone = true

          -- hard-coded action tests
          
          --local george = NPCManager:GetNPCByID("george")
          --if george then
          --  NPCActions:Walk(george, "safehouse", 15, 11)
          --end

          --local george = NPCManager:GetNPCByID("george")
          --if george then
          --  NPCActions:PickupItem(george, "cure_sample_safehouse.tmx_18_5", "safehouse", 18, 5)
          --end

          --local george = NPCManager:GetNPCByID("george")
          --if george then
          --  george:AddItem("cure_sample", "cure_sample_test_001")
          --  table.insert(CollectedItems, "cure_sample_test_001")
          --  NPCActions:DropItem(george, "cure_sample")
          --end
          
          --local george = NPCManager:GetNPCByID("george")
          --if george then
          --  george:AddItem("wood", "wood_test_001")
          --  table.insert(CollectedItems, "wood_test_001")
          --  NPCActions:FortifyLocation(george)
          --end         
          
          --local george = NPCManager:GetNPCByID("george")
          --if george then
          --  george:AddItem("cure_sample", "cure_sample_test_001")
          --  george:AddItem("lab_key",     "lab_key_test_001")
          --  table.insert(CollectedItems,  "cure_sample_test_001")
          --  table.insert(CollectedItems,  "lab_key_test_001")
          --  NPCActions:SynthesizeAntidote(george)
          --end

          --local george = NPCManager:GetNPCByID("george")
          --if george then
          --  george:AddItem("outpost_key",     "outpost_key_test_001")
          --  NPCActions:Walk(george, "outpost2", 12, 8)
          --  --NPCActions:PickupItem(george, "cure_sample_outpost2.tmx_3_12", "outpost2", 3, 12)
          --end
        end
      end

      Shader:Update(dt)  
      if player:IsAlive() then
        player:UpdateAvatar(dt, level)
        player:UpdateBullets(dt, level)
        level:Update(dt, player)
        NPCManager:Update(dt, level)
        if LevelTransitionCooldown > 0 then
          LevelTransitionCooldown = LevelTransitionCooldown - dt
        end
        if MovementCooldown > 0 then
          MovementCooldown = MovementCooldown - dt
        end
        CheckMapEvent(player:GetX(), player:GetY(), player:GetDir())
      end
    end

  end, function(e)
    print("UPDATE CRASH: " .. tostring(e))
    print(debug.traceback())
    love.event.push("quit")
  end)
end

function love.keypressed(k)
  local ok, err = xpcall(function()

    --if k == "g" then
    --  local george = NPCManager:GetNPCByID("george")
    --  if george then
    --    NPCActions:PickupItem(george, "food_supplies_world1.tmx_16_13", "farm", 16, 13)
    --  end
    --end

    if k == "p" then
      print(WorldState:ToJSON())
    end

    --if k == "1" then
    --  print("KEY 1 pressed")
    --  if QuestSystem:IsGenerating() then
    --    print("QuestSystem: already generating, ignoring")
    --  else
    --    MessageQueue:Push("Generating chapter...", 60)
    --    QuestSystem:GenerateChapter("C1", function(data, err)
    --      if err then
    --        MessageQueue:Push("Generation failed: " .. err, 5)
    --      else
    --        QuestRunner:Start(data)
    --      end
    --    end)
    --  end
    --end

    --if k == "2" then
    --  QuestSystem:DumpCurrentChapter()
    --end

    --if k == "3" then
    --  QuestDialog:Open({
    --    { speaker = "PLAYER", line = "Short line." },
    --    { speaker = "george", line = "A medium-length response that should fit comfortably on a single line of the dialog box without wrapping awkwardly." },
    --    { speaker = "PLAYER", line = "And here's a much longer line that goes on and on, deliberately stretching past what would fit on a single line so we can verify the wrapping behaviour, the printf width, and how the box looks when the text fills more vertical space than usual — making sure nothing overlaps the prompt at the bottom." },
    --    { speaker = "anne",   line = "Tiny." },
    --    { speaker = "sarah",  line = "What about a name nobody has set up properly?" },
    --    { speaker = "MYSTERY_NPC", line = "If the speaker isn't in NPCDefinitions, the raw ID should appear instead of crashing." },
    --    { speaker = "PLAYER", line = "Last line — pressing Enter here should close the dialog and return to gameplay." },
    --  }, function()
    --    print("test dialog closed")
    --  end)
    --end

    if k == "4" then
      local george = NPCManager:GetNPCByID("george")
      if george == nil then
        print("debug: george not found")
      else
        BalloonTestIndex = (BalloonTestIndex or 0) + 1
        local samples = {
          "Hi.",
          "I got the fuse.",
          "The grid won't run forever — keep that in mind.",
          "Listen, I've been thinking about all this. The power station is holding for now, but parts wear out, fuel runs low, and nobody else here knows how to fix anything. Sooner or later something gives, and then we're really in trouble.",
          "..."
        }
        local idx = ((BalloonTestIndex - 1) % #samples) + 1
        george:Say(samples[idx], 6)
        print("balloon test " .. idx .. ": " .. samples[idx])
      end
    end

    if k == "5" then
      local character = "sarah"
      print("KEY 5 pressed - generating schedule for " .. character)
      if NPCBehaviorSystem:IsGenerating() then
        print("NPCBehaviorSystem: already generating, ignoring")
      else
        --MessageQueue:Push("Generating NPC schedule...", 60)
        NPCBehaviorSystem:GenerateSchedule(character, function(schedule, err)
          if err then
            MessageQueue:Push("NPC generation failed: " .. err, 5)
            print("NPC generation failed: " .. err)
          else
            MessageQueue:Clear()
            NPCBehaviorSystem:DumpSchedule(character)
            NPCScheduler:Start(character, schedule)
          end
        end)
      end
    end


    if k == "6" then
      TestScheduleIndex = (TestScheduleIndex or 0) + 1

      -- Each scenario is a {npcID, schedule} pair. Schedules use the same
      -- format the LLM API returns: { goal = "...", steps = {"ACTION(args)", ...} }
      local scenarios = {

        {
          npc = "george",
          schedule = {
            goal  = "TEST: 1",
            steps = {
              "PICKUP(george, lab_key_1, graveyard)"
            }
          }
        },

        {
          npc = "george",
          schedule = {
            goal  = "TEST: 2",
            steps = {
              "UNLOCK(george, lab_key_1, laboratory)"
            }
          }
        },
        

        -- ===== 12. SYNTHESIZE_CURE happy path =====
        -- Pre-unlock the lab, give George a cure_sample. He should walk to
        -- the synth machine and say "Antidote ready!"
        {
          npc   = "george",
          setup = function()
            WorldState:RemovePlaceCondition("laboratory", "locked")
            WorldState:AddPlaceCondition("laboratory", "unlocked")
            WorldState:RemovePlaceCondition("laboratory", "no_power")
            WorldState:AddPlaceCondition("laboratory", "power_on")
            local george = NPCManager:GetNPCByID("george")
            if george and not george:HasItem("cure_sample") then
              local instanceID = "cure_sample_test_"
                .. tostring(os.time())
              george:AddItem("cure_sample", instanceID)
              table.insert(CollectedItems, instanceID)
              WorldState:RegisterItem(instanceID, "cure_sample")
              ItemManager:AddRuntimeItem("cure_sample", instanceID)
              print("TEST: gave george a cure_sample (" .. instanceID .. ")")
            end
          end,
          schedule = {
            goal  = "TEST: synthesize successfully",
            steps = {
              "SYNTHESIZE_CURE(george, laboratory)"
            }
          }
        },

        -- ===== 17. TALK to another NPC (|| format) =====
        -- George walks to the safehouse, stands one tile away from anne,
        -- and they trade three lines.
        {
          npc = "george",
          schedule = {
            goal  = "TEST: talk to anne (|| format)",
            steps = {
              "TALK(george, anne, store, \"Anne, you should rest. You look exhausted.||I'll rest when this is over, George.||That's what worries me.\")"
            }
          }
        },

        -- ===== 18. TALK to another NPC (JSON array format) =====
        -- Same as 17 but using the JSON-array dialogue format the LLM
        -- might produce based on the action library description.
        {
          npc = "george",
          schedule = {
            goal  = "TEST: talk to anne (JSON array format)",
            steps = {
              "TALK(george, anne, store, [\"Anne, did you sleep at all?\", \"A little. Don't fuss.\", \"I'm not fussing.\"])"
            }
          }
        },

        -- ===== 19. TALK to a target who isn't there =====
        -- George walks to the village to talk to anne, but anne is in the
        -- safehouse. He arrives and reacts: "I don't see Anne anywhere."
        {
          npc = "george",
          schedule = {
            goal  = "TEST: talk to anne where she isn't",
            steps = {
              "TALK(george, anne, village, \"Anne, are you here?\")"
            }
          }
        },

        -- ===== 20. TALK to a hallucinated target =====
        -- George walks to the safehouse to find a person who doesn't exist.
        {
          npc = "george",
          schedule = {
            goal  = "TEST: talk to a nonexistent character",
            steps = {
              "TALK(george, gandalf, village, \"You shall not pass!\")"
            }
          }
        },

        -- ===== 21. TALK to self =====
        -- George muses out loud at the safehouse - all turns over george.
        {
          npc = "george",
          schedule = {
            goal  = "TEST: george thinks out loud",
            steps = {
              "TALK(george, george, village, \"What am I even doing here.||I should make myself useful.||Right. One thing at a time.\")"
            }
          }
        },

        -- ===== 22. TALK to the player =====
        -- George walks adjacent to the player and speaks his lines.
        -- Player lines render over george (no player balloon).
        {
          npc = "george",
          schedule = {
            goal  = "TEST: george talks to the player",
            steps = {
              "TALK(george, john, village, \"There you are.||I needed to tell you something.||It can wait, I suppose.\")"
            }
          }
        },


        -- ===== 14. DROP successful =====
        -- Give George some food supplies, then have him drop them at the
        -- safehouse. He should walk there and react: "I don't need it anymore."
        {
          npc   = "george",
          setup = function()
            local george = NPCManager:GetNPCByID("george")
            if george and not george:HasItem("food_supplies") then
              local id = "food_supplies_test_" .. tostring(os.time())
              george:AddItem("food_supplies", id)
              table.insert(CollectedItems, id)
              WorldState:RegisterItem(id, "food_supplies")
              ItemManager:AddRuntimeItem("food_supplies", id)
              print("TEST: gave george food_supplies (" .. id .. ")")
              -- store the label for the schedule below
              TestDropLabel = WorldState:GetLabelFromInstanceID(id)
              print("TEST: drop label is " .. tostring(TestDropLabel))
            end
          end,
          buildSchedule = function()
            return {
              goal  = "TEST: drop food at safehouse",
              steps = {
                "DROP(george, food_supplies_2, safehouse)"
              }
            }
          end
        },

        -- ===== 15. DROP item the NPC doesn't have =====
        -- George doesn't have wood. Should walk to the village and react:
        -- "I thought I was carrying the Wood. I'm not."
        {
          npc = "george",
          schedule = {
            goal  = "TEST: drop wood the NPC doesn't have",
            steps = {
              "DROP(george, wood_1, village)"
            }
          }
        },

        -- ===== 16. DROP at unknown place =====
        -- Should fail fast: "Where was I supposed to go again?"
        {
          npc = "george",
          schedule = {
            goal  = "TEST: drop at unknown place",
            steps = {
              "DROP(george, food_supplies_1, atlantis)"
            }
          }
        },

        -- ===== 10. SYNTHESIZE_CURE with no power, no sample =====
        -- Lab starts with no_power. George should walk to the lab door,
        -- find it locked, and react with the door-locked line. (BuildJourney
        -- truncation - the lab is locked at the start of the game.)
        {
          npc = "george",
          schedule = {
            goal  = "TEST: synthesize with no power, no key, no sample",
            steps = {
              "SYNTHESIZE_CURE(george, laboratory)"
            }
          }
        },

        -- ===== 11. SYNTHESIZE_CURE with power on, no sample =====
        -- Pre-unlock and power-on the lab. George arrives at the machine
        -- but has no cure_sample - should react: "I need a sample to make..."
        {
          npc   = "george",
          setup = function()
            WorldState:RemovePlaceCondition("laboratory", "locked")
            WorldState:AddPlaceCondition("laboratory", "unlocked")
            WorldState:RemovePlaceCondition("laboratory", "no_power")
            WorldState:AddPlaceCondition("laboratory", "power_on")
            print("TEST: forced laboratory unlocked + power_on")
          end,
          schedule = {
            goal  = "TEST: synthesize with power but no sample",
            steps = {
              "SYNTHESIZE_CURE(george, laboratory)"
            }
          }
        },

        

        -- ===== 13. SYNTHESIZE_CURE but already have an antidote =====
        -- Same setup as 12, but ALSO give George an antidote first.
        -- He should walk all the way to the machine and react:
        -- "I already have an antidote. No need to make another."
        {
          npc   = "george",
          setup = function()
            WorldState:RemovePlaceCondition("laboratory", "locked")
            WorldState:AddPlaceCondition("laboratory", "unlocked")
            WorldState:RemovePlaceCondition("laboratory", "no_power")
            WorldState:AddPlaceCondition("laboratory", "power_on")
            local george = NPCManager:GetNPCByID("george")
            if george then
              if not george:HasItem("antidote") then
                local antidoteID = "antidote_test_" .. tostring(os.time())
                george:AddItem("antidote", antidoteID)
                table.insert(CollectedItems, antidoteID)
                WorldState:RegisterItem(antidoteID, "antidote")
                ItemManager:AddRuntimeItem("antidote", antidoteID)
                print("TEST: gave george an antidote (" .. antidoteID .. ")")
              end
              if not george:HasItem("cure_sample") then
                local sampleID = "cure_sample_test2_" .. tostring(os.time())
                george:AddItem("cure_sample", sampleID)
                table.insert(CollectedItems, sampleID)
                WorldState:RegisterItem(sampleID, "cure_sample")
                ItemManager:AddRuntimeItem("cure_sample", sampleID)
                print("TEST: gave george a cure_sample (" .. sampleID .. ")")
              end
            end
          end,
          schedule = {
            goal  = "TEST: synthesize when already have antidote",
            steps = {
              "SYNTHESIZE_CURE(george, laboratory)"
            }
          }
        },

        -- ===== 1. UNLOCK with no key (walk-first reaction) =====
        -- George doesn't have lab_key, so he should walk to the laboratory
        -- door in the village and react: "Oh... the door is locked..."
        {
          npc = "george",
          schedule = {
            goal  = "TEST: try to unlock lab without a key",
            steps = {
              "MOVE(george, safehouse, village)",
              "UNLOCK(george, lab_key_1, laboratory)"
            }
          }
        },

        -- ===== 2a. PICKUP item that's been collected =====
        -- Pre-mark fuse_1 as collected, then ask for it at its real location.
        -- Should walk there and say "Someone got to the Fuse before me."
        {
          npc   = "george",
          setup = function()
            local fuseInstanceID = WorldState:GetInstanceIDFromLabel("fuse_1")
            if fuseInstanceID then
              local already = false
              for _, id in ipairs(CollectedItems) do
                if id == fuseInstanceID then already = true; break end
              end
              if not already then
                table.insert(CollectedItems, fuseInstanceID)
                print("TEST: marked fuse_1 (" .. fuseInstanceID .. ") as collected")
              end
            end
          end,
          schedule = {
            goal  = "TEST: pick up a fuse that's already gone",
            steps = {
              "PICKUP(george, fuse_1, laboratory)"
            }
          }
        },

        -- ===== 2b. PICKUP item at the WRONG place (LLM hallucinated location) =====
        -- fuse_1 is in the laboratory, but we tell George it's at the powerstation.
        -- Should walk to powerstation and say "There's no Fuse here..."
        {
          npc = "george",
          schedule = {
            goal  = "TEST: pick up a fuse at the wrong place",
            steps = {
              "PICKUP(george, fuse_1, powerstation)"
            }
          }
        },

        -- ===== 3. MOVE to where the NPC already is =====
        -- George starts in the safehouse, asks him to MOVE to safehouse.
        -- Should immediately say "Wait - I'm already here."
        {
          npc = "george",
          schedule = {
            goal  = "TEST: move to current location",
            steps = {
              "MOVE(george, powerstation, powerstation)"
            }
          }
        },

        -- ===== 4. FORTIFY an exterior location =====
        -- The village is exterior, so fortifying it should fail immediately
        -- with: "Can't board this up - there's nothing to nail it to."
        {
          npc = "george",
          schedule = {
            goal  = "TEST: fortify outside",
            steps = {
              "MOVE(george, powerstation, village)",
              "FORTIFY(george, wood_1, village)"
            }
          }
        },

        -- ===== 4b. FORTIFY interior without wood (walk-first reaction) =====
        -- George has no wood. He should walk to the safehouse and react there
        -- with: "I don't have any wood to work with."
        {
          npc = "george",
          schedule = {
            goal  = "TEST: fortify safehouse with no wood",
            steps = {
              "FORTIFY(george, wood_1, safehouse)"
            }
          }
        },

        -- ===== 5. TURN_POWER_ON without a fuse =====
        -- George doesn't carry a fuse, so this should fail with: "I'd need a fuse for this."
        
        {
          npc = "george",
          schedule = {
            goal  = "TEST: turn on power with no fuse",
            steps = {
              "TURN_POWER_ON(george, fuse_99, powerstation, laboratory)"
            }
          }
        },

        {
          npc = "george",
          schedule = {
            goal  = "TEST: turn on power with no fuse",
            steps = {
              "TURN_POWER_ON(george, fuse_1, powerstation, laboratory)"
            }
          }
        },

        -- ===== 6. UNLOCK a place that's already unlocked =====
        -- The safehouse starts unlocked, so this should react: "This is already open."
        {
          npc = "george",
          schedule = {
            goal  = "TEST: unlock something already unlocked",
            steps = {
              "UNLOCK(george, outpost_key_1, safehouse)"
            }
          }
        },

        -- ===== 7. MOVE to an unknown place =====
        -- A place ID the LLM hallucinated. Should react: "Where was I supposed to go again?"
        {
          npc = "george",
          schedule = {
            goal  = "TEST: move to a hallucinated place",
            steps = {
              "MOVE(george, safehouse, atlantis)"
            }
          }
        },

        -- ===== 8. PICKUP an unknown item =====
        -- A label the LLM made up. Should react: "I have no idea what I was after."
        {
          npc = "george",
          schedule = {
            goal  = "TEST: pick up a hallucinated item",
            steps = {
              "PICKUP(george, magic_sword_42, village)"
            }
          }
        },

        -- ===== 9. Unsupported action (e.g. TALK isn't dispatched) =====
        -- Should react with the generic "confused" line.
        {
          npc = "george",
          schedule = {
            goal  = "TEST: unsupported action",
            steps = {
              "TALK(george, sarah, safehouse, \"Hello there.\")"
            }
          }
        }
      }

      local idx = ((TestScheduleIndex - 1) % #scenarios) + 1
      local s   = scenarios[idx]

      local schedule = s.schedule or (s.buildSchedule and s.buildSchedule())

      print("=================================================")
      print("TEST SCHEDULE " .. idx .. ": " .. schedule.goal)
      print("=================================================")

      if s.setup then s.setup() end

      -- Stop any existing schedule for this NPC so we can re-trigger cleanly.
      NPCScheduler:Stop(s.npc)

      
      if schedule == nil then
        print("TEST: scenario " .. idx .. " has no schedule")
      else
        NPCScheduler:Start(s.npc, schedule)
      end
    end

    -- handle the failed-generation prompt
    if Loading and GenerationState == "failed" then
      if k == "r" then
        GenerationState     = "generating"
        GenerationError     = nil
        GenerationStartTime = love.timer.getTime()
        QuestSystem:GenerateChapter("C1", function(data, err)
          if err then
            GenerationState = "failed"
            GenerationError = err
          else
            GenerationState = "ready"
            QuestRunner:Start(data)
          end
        end)
        return
      elseif k == "s" then
        GenerationState = "ready"   -- treat as ready, but no chapter to start
        return
      end
    end

    if k == "escape" then
      if GameState == 4 then
        Inventory:Toggle()
      else
        love.event.push("quit")
      end
    end

    if GameState == 0 then
      if k == "return" and Loading == false then        
        Loading = true
        LoadingTime = 0
      end
    else    

      if GameState == 4 then
        if k == "left" then
          Inventory:MoveSelection("left")
        elseif k == "right" then
          Inventory:MoveSelection("right")
        elseif k == "d" then
          Inventory:DropSelected()
        elseif k == "g" then
          Inventory:GiveSelected()
        elseif k == "return" then
          Inventory:UseSelected()
          return
        end
      end

      if k == "tab" and GameState == 1 then
        QuestUI:Toggle()
      end
      
      if k == "return" then
        if QuestDialog:IsOpen() then
          QuestDialog:Advance()
          return
        end
        if GameState == 1 then
          -- prefer active TALK goal; only fall back to inventory toggle if no TALK
          if QuestRunner:TryStartTalk() then
            return
          end
          Inventory:Toggle()
        end
      end 

      if GameState == 1 then
        if k == "space" and player:IsAlive() then
          player:Shoot()
        end  
      elseif GameState == 3 then
        if k == "return" or k == "space" then
          GameState = 1
        end
      end
    end
  end, function(e)
    print("KEYPRESSED CRASH: " .. tostring(e))
    print(debug.traceback())
    love.event.push("quit")
  end)
end

function love.draw()
  -- 1. draw game world to GameCanvas
  love.graphics.setCanvas(GameCanvas)
  love.graphics.clear()
  local ok, err = xpcall(function()
    if GameState ~= 0 and player:IsAlive() then
      local ftx = math.floor((-player:GetX()*32)+(BASE_WIDTH/2) + 20)
      local fty = math.floor((-player:GetY()*32)+(BASE_HEIGHT/2) + 20)
      love.graphics.push()
      local ok, err = pcall(function()
        love.graphics.translate(ftx, fty)
        level:Draw(ftx, fty)
        player:DrawBullets()
      end)
      love.graphics.pop()
      if not ok then print("DRAW CRASH: " .. tostring(err)) end
      player:Draw()  
    end
  end, function(e)
    print("DRAW CRASH: " .. tostring(e))
    print(debug.traceback())
  end)

  -- 2. draw UI to UICanvas
  love.graphics.setCanvas(UICanvas)
  love.graphics.clear(0, 0, 0, 0) -- transparent background
  if GameState == 0 then
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(TitleBackground, -50, -50, 0, 0.65, 0.65)
    love.graphics.draw(TitleText, 140, 100)
    love.graphics.print("PRESS ENTER TO START!", (BASE_WIDTH/2) - 100, BASE_HEIGHT/2)
  elseif GameState ~= 0 then
    if player:IsAlive() then
      player:DrawHUD()
      Inventory:Draw()
      QuestUI:Draw()
      QuestDialog:Draw()
    else
      love.graphics.setColor(1, 1, 1)
      love.graphics.draw(GameOverText, 145, 140)
      love.graphics.print("PRESS ENTER TO RESTART!", (BASE_WIDTH/2) - 105, (BASE_HEIGHT/2)+50)
    end
    if GameMessage ~= "" and GameMessageTime > 0 then
      MessageBox:Draw(nil, GameMessage, nil)
    end
    love.graphics.setFont(myfont)
    love.graphics.setColor(1, 1, 1)
  end
  if Loading then
    if LoadingTime > 255 then
      love.graphics.setColor(0, 0, 0, 1)
    else
      love.graphics.setColor(0, 0, 0, LoadingTime/255)
    end
    love.graphics.rectangle("fill", 0, 0, BASE_WIDTH, BASE_HEIGHT)

    -- show generation status when we're at full black
    if LoadingTime >= 255 then
      love.graphics.setFont(myfont)
      if GenerationState == "generating" then
        local elapsed = love.timer.getTime() - GenerationStartTime
        local msg     = "Generating story..."
        love.graphics.setColor(0.85, 0.75, 0.2)
        local msgW = myfont:getWidth(msg)
        love.graphics.print(msg, (BASE_WIDTH - msgW) / 2, BASE_HEIGHT / 2 - 40)

        -- indeterminate progress bar: a sliding chunk
        local barW   = 240
        local barH   = 6
        local barX   = (BASE_WIDTH - barW) / 2
        local barY   = BASE_HEIGHT / 2 - 8
        local chunkW = 60

        -- bar background
        love.graphics.setColor(0.2, 0.2, 0.2)
        love.graphics.rectangle("fill", barX, barY, barW, barH, 3, 3)

        -- moving chunk: bounces back and forth
        local cycle    = (love.timer.getTime() % 1.6) / 1.6   -- 0..1 over 1.6s
        local triangle = 1 - math.abs(cycle * 2 - 1)          -- 0..1..0
        local chunkX   = barX + (barW - chunkW) * triangle
        love.graphics.setColor(0.85, 0.75, 0.2)
        love.graphics.rectangle("fill", chunkX, barY, chunkW, barH, 3, 3)

        love.graphics.setFont(myfont2)
        love.graphics.setColor(0.6, 0.6, 0.6)
        local elapsedMsg = string.format("%ds elapsed", math.floor(elapsed))
        local ew         = myfont2:getWidth(elapsedMsg)
        love.graphics.print(elapsedMsg, (BASE_WIDTH - ew) / 2, BASE_HEIGHT / 2 + 10)

      elseif GenerationState == "failed" then
        love.graphics.setColor(0.85, 0.3, 0.3)
        local title = "Generation Failed"
        local w     = myfont:getWidth(title)
        love.graphics.print(title, (BASE_WIDTH - w) / 2, BASE_HEIGHT / 2 - 50)

        love.graphics.setFont(myfont2)
        love.graphics.setColor(0.9, 0.9, 0.9)
        love.graphics.printf(GenerationError or "Unknown error",
          40, BASE_HEIGHT / 2 - 20, BASE_WIDTH - 80, "center")

        love.graphics.setColor(0.85, 0.75, 0.2)
        local hint = "[R] Retry        [S] Skip and play without quest"
        local hw   = myfont2:getWidth(hint)
        love.graphics.print(hint, (BASE_WIDTH - hw) / 2, BASE_HEIGHT / 2 + 50)
      end
    end

    love.graphics.setFont(myfont)
    love.graphics.setColor(1, 1, 1)
  end

  -- 3. composite: draw game canvas with shader, then UI canvas without
  love.graphics.setCanvas()
  love.graphics.setColor(1, 1, 1)
  Shader:Apply()
  love.graphics.draw(GameCanvas, 0, 0, 0, SCALE, SCALE)
  Shader:Clear()
  love.graphics.draw(UICanvas, 0, 0, 0, SCALE, SCALE)
end

function love.quit()
  if QuestSystem then QuestSystem:StopWorker() end
  if NPCBehaviorSystem  then NPCBehaviorSystem:StopWorker() end
end

local love_errorhandler = love.errorhandler

function love.errorhandler(msg)
    if lldebugger then
        error(msg, 2)
    else
        return love_errorhandler(msg)
    end
end