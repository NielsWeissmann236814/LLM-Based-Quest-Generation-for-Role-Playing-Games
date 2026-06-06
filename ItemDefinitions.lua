ItemDefinitions = {
  ["antidote"] = {
    type        = "collectible",
    displayName = "Antidote",
    image       = "ItemAntidote",
    use = {
      label        = "Use Antidote",
      consumeOnUse = true,
      closeOnUse   = true,
      preconditions = {
        {
          check = function()
            return ItemDefinitions["antidote"].use._findInfectedNPC() ~= nil
          end,
          failMessage = "There is no infected person nearby."
        }
      },
      effect = function()
        local npc = ItemDefinitions["antidote"].use._findInfectedNPC()
        if npc then
          npc:SetCondition("healthy")
          npc:RemoveCondition("infected")
          local def         = NPCDefinitions[npc.npcID]
          local name        = def and def.displayName or npc.npcID
          MessageQueue:Push("You cured " .. name .. " with the antidote!", 4)
          print("item_used: antidote -> cured " .. npc.npcID)
        end
      end,
      -- private helper, finds an adjacent infected NPC
      _findInfectedNPC = function()
        local px = math.ceil(player:GetX())
        local py = math.ceil(player:GetY())
        for _, npc in ipairs(level.NPCs) do
          local nx = math.ceil(npc:GetX())
          local ny = math.ceil(npc:GetY())
          -- check if NPC is adjacent (within 1 tile)
          if math.abs(nx - px) <= 1 and math.abs(ny - py) <= 1 then
            if npc:HasCondition("infected") then
              return npc
            end
          end
        end
        return nil
      end
    }
  },
  ["cure_sample"] = {
    type        = "collectible",
    displayName = "Cure Sample",
    image       = "ItemSample",
    useAt = {
      levelFile = "laboratory.tmx",
      x = 5,
      y = 7
    },
    use = {
      label        = "Synthesize Cure",
      consumeOnUse = true,
      closeOnUse   = true,
      preconditions = {
        {
          check = function()
            local def = ItemDefinitions["cure_sample"]
            return level.levelName == def.useAt.levelFile
          end,
          failMessage = "You can only use this item in the synthesis machine."
        },
        {
          check = function()
            local def = ItemDefinitions["cure_sample"]
            local px  = math.ceil(player:GetX())
            local py  = math.ceil(player:GetY())
            return px == def.useAt.x and py == def.useAt.y
          end,
          failMessage = "You can only use this item in the synthesis machine."
        },
        {
          check = function()
            local conditions = WorldState:GetPlaceConditions("laboratory")
            for _, c in ipairs(conditions) do
              if c == "power_on" then return true end
            end
            return false
          end,
          failMessage = "The synthesis machine has no power. You need to restore \npower to the laboratory first."
        },
        {
          check = function()
            return not player:HasItem("antidote")
          end,
          failMessage = "You already have an antidote."
        }
      },
      effect = function()
        -- generate a unique instance ID for the synthesized antidote
        local instanceID = "antidote_synthesized_" .. tostring(os.time())
        player:AddItem("antidote", instanceID)
        table.insert(CollectedItems, instanceID)
        WorldState:RegisterItem(instanceID, "antidote")
        ItemManager:AddRuntimeItem("antidote", instanceID)
        MessageQueue:Push("You synthesized an antidote from the cure sample!", 4)
        print("item_used: cure_sample -> antidote synthesized")
      end
    }
  },
  ["lab_key"] = {
    type        = "collectible",
    displayName = "Laboratory Key",
    image       = "ItemKey",
    unlocks     = "laboratory",
    useAt = {
      levelFile = "world1.tmx",
      x         = 38,
      y         = 32,
      doorTileX = 38,
      doorTileY = 32
    },
    use = {
      label        = "Unlock Door",
      consumeOnUse = true,
      closeOnUse   = true,
      preconditions = {
        {
          check = function()
            local def = ItemDefinitions["lab_key"]
            return level.levelName == def.useAt.levelFile
          end,
          failMessage = "There is no door to unlock here."
        },
        {
          check = function()
            local def = ItemDefinitions["lab_key"]
            local px  = math.ceil(player:GetX())
            local py  = math.ceil(player:GetY())
            return px == def.useAt.x and py == def.useAt.y
          end,
          failMessage = "You need to be in front of the laboratory door to use the key."
        }
      },
      effect = function()
        local def  = ItemDefinitions["lab_key"]
        local tile = level:GetTile(def.useAt.doorTileX, def.useAt.doorTileY)
        WorldState:RemovePlaceCondition("laboratory", "locked")
        WorldState:AddPlaceCondition("laboratory", "unlocked")
        MessageQueue:Push("You unlocked the laboratory door.", 3)
        print("item_used: lab_key -> unlocked laboratory")
        if tile and tile.properties.destination then
          DoLevelTransition(
            tile.properties.destination,
            tile.properties.target_x,
            tile.properties.target_y,
            tile.properties.target_direction
          )
        end
      end
    }
  },
  ["outpost_key"] = {
    type        = "collectible",
    displayName = "Outpost Key",
    image       = "ItemKey",
    unlocks     = "outpost1",
    useAt = {
      levelFile = "world1.tmx",
      x         = 14,
      y         = 39,
      doorTileX = 14,
      doorTileY = 39
    },
    use = {
      label        = "Unlock Door",
      consumeOnUse = true,
      closeOnUse   = true,
      preconditions = {
        {
          check = function()
            local def = ItemDefinitions["outpost_key"]
            return level.levelName == def.useAt.levelFile
          end,
          failMessage = "There is no door to unlock here."
        },
        {
          check = function()
            local def = ItemDefinitions["outpost_key"]
            local px  = math.ceil(player:GetX())
            local py  = math.ceil(player:GetY())
            return px == def.useAt.x and py == def.useAt.y
          end,
          failMessage = "You need to be in front of the outpost door to use the key."
        }
      },
      effect = function()
        local def  = ItemDefinitions["outpost_key"]
        local tile = level:GetTile(def.useAt.doorTileX, def.useAt.doorTileY)
        WorldState:AddPlaceCondition("outpost1", "unlocked")
        MessageQueue:Push("You unlocked the outpost door.", 3)
        print("item_used: outpost_key -> unlocked outpost")
        if tile and tile.properties.destination then
          DoLevelTransition(
            tile.properties.destination,
            tile.properties.target_x,
            tile.properties.target_y,
            tile.properties.target_direction
          )
        end
      end
    }
  },
  ["food_supplies"] = {
    type        = "collectible",
    displayName = "Food Supplies",
    image       = "ItemFood",
    inventoryImage = "ItemFoodIcon",
    fungible    = true,
  },
  ["fuse"] = {
    type        = "collectible",
    displayName = "Fuse",
    image       = "ItemFuse",
    useAt = {
      levelFile    = "world1.tmx",
      x            = 83,
      y            = 43      
    },
    use = {
      label        = "Restore Power",
      consumeOnUse = true,
      preconditions = {
        {
          check = function()
            return level.levelName == ItemDefinitions["fuse"].useAt.levelFile
          end,
          failMessage = "There is nothing to use this on here."
        },
        {
          check = function()
            local d  = ItemDefinitions["fuse"].useAt
            local px = math.ceil(player:GetX())
            local py = math.ceil(player:GetY())
            return math.abs(px - d.x) <= 1 and math.abs(py - d.y) <= 1
          end,
          failMessage = "You need to be next to the power box."
        },
        {
          check = function()
            local conditions = WorldState:GetPlaceConditions("laboratory")
            for _, c in ipairs(conditions) do
              if c == "no_power" then return true end
            end
            return false
          end,
          failMessage = "The power is already restored."
        }
      },
      effect = function()
        WorldState:RemovePlaceCondition("laboratory", "no_power")
        WorldState:AddPlaceCondition("laboratory", "power_on")
        MessageQueue:Push("You restored power to the laboratory!", 3)
        print("item_used: fuse -> laboratory power restored")
        print("fuse_used")
      end
    }
  },
  ["toolkit"] = {
    type        = "collectible",
    displayName = "Toolkit",
    image       = "ItemToolkit",
    useAt = {
      levelFile    = "world1.tmx",
      x            = 49,
      y            = 46      
    },
    use = {
      label        = "Fix Boat",
      consumeOnUse = true,
      preconditions = {
        {
          check = function()
            return level.levelName == ItemDefinitions["toolkit"].useAt.levelFile
          end,
          failMessage = "You can only use this here."
        },
        {
          check = function()
            local px = math.ceil(player:GetX())
            local py = math.ceil(player:GetY())
            local d  = ItemDefinitions["toolkit"].useAt
            return math.abs(px - d.x) <= 1 and math.abs(py - d.y) <= 1
          end,
          failMessage = "You need to be next to the boat."
        },
        {
          check = function()
            return player:HasItem("wood")
          end,
          failMessage = "You need wood to fix the boat."
        },
        {
          check = function()
            return WorldObjects["boat"] == "broken"
          end,
          failMessage = "The boat is already fixed."
        }
      },
      effect = function()
        player:RemoveItem("wood")
        WorldObjects["boat"] = "fixed"
        MessageQueue:Push("You fixed the boat!", 4)
        print("item_used: toolkit -> boat fixed")
      end
    }
  },
  ["wood"] = {
    type        = "collectible",
    displayName = "Wood",
    image       = "ItemWood",
    inventoryImage = "ItemWoodIcon",
    fungible    = true,
    use = {
      label       = "Fortify",
      consumeOnUse = true,
      closeOnUse   = true,
      preconditions = {
        {
          check = function()
            local place = WorldState:GetPlaceDef(
              WorldState:LevelToPlace(level.levelName)
            )
            return place ~= nil and place.type == "interior"
          end,
          failMessage = "You cannot fortify this location."
        },
        {
          check = function()
            local placeID = WorldState:LevelToPlace(level.levelName)
            local conditions = WorldState:GetPlaceConditions(placeID)
            for _, c in ipairs(conditions) do
              if c == "fortified" then return false end
            end
            return true
          end,
          failMessage = "This location is already fortified."
        }
      },
      effect = function()
        local placeID = WorldState:LevelToPlace(level.levelName)
        WorldState:AddPlaceCondition(placeID, "fortified")
        MessageQueue:Push("You fortified this location.", 3)
        print("item_used: wood -> fortified " .. placeID)
      end
    }
  },
  ["medkit"] = {
    type        = "consumable",
    displayName = "Medkit",
    image       = "ItemMedicKit",
    effect      = function(pl) pl:AddLife(30) end,
    fungible    = true,
  },
  ["ammo"] = {
    type        = "consumable",
    displayName = "Ammunition",
    image       = "ItemAmmunition",
    effect      = function(pl) pl:AddAmmunition(16) end,
    fungible    = true,
  }
}

