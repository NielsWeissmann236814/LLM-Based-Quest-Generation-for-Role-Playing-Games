-- All NPC failure-reaction dialogue lines, organised by category.
-- One pool per category, picked at random. Lines may contain {tokens}
-- like {item} or {place} that NPCDialog:Pick substitutes from a vars table.
--
-- Add new lines freely - the system picks one at random per call.

NPCDialog = {}

NPCDialog.lines = {

  -- ============================================================
  -- WALK-FIRST REACTIONS (NPC arrives at the destination first)
  -- ============================================================

  -- door is locked and the NPC has no key for it
  door_locked_no_key = {
    "Oh... the door is locked. I can't open it.",
    "Locked. And I don't have the key.",
    "Of course it's locked. Why wouldn't it be.",
    "I should have grabbed the key first.",
    "No way through here without a key."
  },

  -- arrived at item location but the item is gone
  item_gone = {
    "I can't find the {item} here...",
    "It was supposed to be right here.",
    "Someone got to the {item} before me.",
    "Where did the {item} go?",
    "Nothing here. I must be misremembering."
  },

  -- arrived to fortify but it's already fortified
  already_fortified_arrived = {
    "Looks like someone already boarded this place up.",
    "Already fortified. Good - one less thing to worry about.",
    "Huh. This is already done."
  },

  -- ============================================================
  -- INVENTORY FAILURES (no item to perform the action)
  -- ============================================================

  no_key = {
    "I don't have the key for this.",
    "I'd need a key. I don't have one.",
    "Locked, and I'm empty-handed."
  },

  no_fuse = {
    "I'd need a fuse for this.",
    "Nothing to install. I'm out of fuses.",
    "Can't fix the power without a fuse."
  },

  no_wood = {
    "I don't have any wood to work with.",
    "I'd need some wood to board this up.",
    "Empty-handed. I need wood for this."
  },

  no_cure_sample = {
    "I need a sample to make the antidote.",
    "I can't synthesize anything without a sample.",
    "There's nothing to work with - I need a cure sample first."
  },

  no_item_generic = {
    "I don't have what I need for this.",
    "I'm missing something. I'll come back to it.",
    "Wait - I don't have the right thing on me."
  },

  -- arrived at the synthesis machine but no power
  no_power_synth = {
    "The machine's dead. No power.",
    "Without power, this thing is just a paperweight.",
    "I need to get the power back on first.",
    "No power - I can't synthesize anything."
  },

  -- arrived at the synthesis machine but already carrying an antidote
  already_have_antidote = {
    "I already have an antidote. No need to make another.",
    "Wait - I'm already carrying one of these.",
    "One antidote is enough. I'll save the supplies."
  },

  -- arrived at place to drop something but doesn't have it
  no_item_to_drop = {
    "Wait - I don't have it on me.",
    "I thought I was carrying the {item}. I'm not.",
    "Where did the {item} go? I don't have it.",
    "Empty-handed. I must have left it somewhere."
  },

  -- successful drop reaction (replaces the existing hardcoded "I don't need it!")
  dropped = {
    "There. I don't need it anymore.",
    "I'll leave it here.",
    "Done. Someone else can use it.",
    "I don't need this. Leaving it here."
  },

    -- arrived but the target NPC isn't here
  target_not_here = {
    "Where's {target}? They're not here.",
    "I don't see {target} anywhere.",
    "I came to talk to {target}, but they're gone.",
    "Hm. {target} should be here. They're not."
  },

  -- target NPC doesn't exist at all (LLM hallucinated)
  unknown_target = {
    "Who was I supposed to talk to again?",
    "I can't remember who I was looking for.",
    "There's no one by that name around."
  },

  -- ============================================================
  -- STATE CONFLICTS (action already done / not applicable)
  -- ============================================================

  already_unlocked = {
    "This is already open.",
    "No need - it's already unlocked.",
    "Already taken care of."
  },

  power_already_on = {
    "Power's already on. Never mind.",
    "Someone's already done this. Good.",
    "Already running. Move on."
  },

  already_fortified = {
    "This place is already secure.",
    "Already done. Good.",
    "Nothing to add - it's already fortified."
  },

  cant_fortify_outside = {
    "Can't board this up - there's nothing to nail it to.",
    "I can only fortify a building from inside.",
    "Out here? No point trying to fortify this."
  },

  already_at_destination = {
    "Wait - I'm already here.",
    "Why was I going to walk here? I'm already here.",
    "I'm here. What was I doing again?"
  },

  -- ============================================================
  -- ITEM TRACKING (PICKUP-specific)
  -- ============================================================

  item_already_taken = {
    "Someone already grabbed the {item}.",
    "The {item} is gone. Someone got there first.",
    "No {item} here. Already taken."
  },

  item_unknown = {
    "I don't know what I was supposed to pick up.",
    "I've forgotten what I was looking for.",
    "Was there even an item here?"
  },

  item_not_here = {
    "There's no {item} here...",
    "I was told the {item} would be here. It's not.",
    "Hmm. No {item} in sight.",
    "I don't see any {item} around.",
    "Whoever sent me here was wrong - no {item}."
  },

  -- ============================================================
  -- ROUTING / PLANNING FAILURES
  -- ============================================================

  unknown_place = {
    "Where was I supposed to go again?",
    "I've lost track of where I'm going.",
    "I don't even know where that is."
  },

  no_route = {
    "I can't find a way there from here.",
    "There's no path through. I'll have to think of something else.",
    "Dead end. I can't reach it."
  },

  unknown_item = {
    "I have no idea what I was after.",
    "I've forgotten what I'm carrying.",
    "Something's off - I can't find what I need."
  },

  -- ============================================================
  -- GENERIC FALLBACK (when nothing else fits)
  -- ============================================================

  confused = {
    "Wait - that's not right.",
    "Something's off. I'll figure it out later.",
    "This isn't going to work.",
    "I can't do this right now."
  },

  -- said when the schedule is being abandoned entirely
  schedule_abandoned = {
    "Forget it. I need a new plan.",
    "I give up on this. Time to think.",
    "I'm done with this for now.",
    "Alright. Different approach.",
    "This isn't working. Let me think.",
    "Scratch that. I'll figure something else out.",
    "Right. Back to the drawing board.",
    "I'll come back to this later.",
    "Maybe I'm going about this wrong.",
    "Forget the plan. I'll improvise.",
    "Useless. I need to rethink this.",
    "I can't keep banging my head against this.",
    "Time to try something different.",
    "I should have thought this through better.",
    "Enough. I need a moment to think.",
    "This whole plan was a mess.",
    "Step back. Start over.",
    "Nothing's going right today.",
    "I'll figure it out. Just not like this.",
    "Walking away from this one."
  },

  -- ============================================================
  -- SUCCESS REACTIONS (NPC completed an action that's worth noting)
  -- ============================================================

  pickup_success = {
    "Got it!",
    "I got it!",
    "Got what I came for.",
    "There we go.",
    "This is mine now."
  },

  unlock_success = {
    "Unlocked!",
    "There. The door's open.",
    "That should do it.",
    "Got it open.",
    "Click. Open."
  },

  turn_power_on_success = {
    "Power's on!",
    "Got the lights back on.",
    "There - we have power again.",
    "The grid's running.",
    "We've got electricity. About time."
  },

  synthesize_success = {
    "Antidote ready!",
    "I did it. The antidote is ready.",
    "It worked. I have an antidote.",
    "There - one antidote. Use it well.",
    "The synthesizer worked. I have a cure."
  },

  fortify_success = {
    "Place fortified!",
    "That should hold.",
    "Boarded up. Safer now.",
    "Done. They'll have a hard time getting in.",
    "There. One less weak point."
  },
}


-- Pick a random line from the named pool, with optional variable substitution.
--   category: string key into NPCDialog.lines
--   vars:     optional table of {token = replacement} for {token} substitution
-- Falls back to the "confused" pool if the category doesn't exist, so a typo
-- never crashes the game.
function NPCDialog:Pick(category, vars)
  local pool = self.lines[category]
  if pool == nil or #pool == 0 then
    print("NPCDialog: unknown category '" .. tostring(category) .. "', falling back to confused")
    pool = self.lines.confused
  end

  local line = pool[love.math.random(1, #pool)]

  if vars ~= nil then
    for token, value in pairs(vars) do
      line = line:gsub("{" .. token .. "}", tostring(value))
    end
  end

  return line
end

-- Helper: turn an item label like "fuse_1" into a display name like "Fuse"
function NPCDialog:ItemDisplayName(itemLabel)
  if itemLabel == nil then return "item" end
  local base = itemLabel:match("^(.-)_%d+$") or itemLabel
  local def  = ItemDefinitions and ItemDefinitions[base]
  if def and def.displayName then return def.displayName end
  return base
end

-- Helper: turn a place ID into a display name
function NPCDialog:PlaceDisplayName(placeID)
  if placeID == nil then return "there" end
  local def = WorldState and WorldState:GetPlaceDef(placeID)
  if def and def.displayName then return def.displayName end
  return placeID
end