"""
eval_quest_generation.py

Technical evaluation script for LLM-based quest generation.

What it does:
  - Runs N quest generation runs per LLM (default: 10)
  - Chains chapters: C1 → C2 → C3, updating world state between chapters
  - Evaluates each chapter output on 6 metric categories
  - Saves per-run checkpoints (JSON) with metrics so nothing is lost on crash
  - Saves per-run quest JSONs with full dialogue for qualitative review
  - Produces 3 final outputs: detail CSV (one row per run/chapter), summary CSV (mean ± stdev per model/chapter), and per-run quest JSONs with full dialogue

Run:
  python eval_quest_generation.py

Configure at the top of the file (MODEL_CONFIGS, RUNS_PER_MODEL, etc.)
"""

import copy
import csv
import glob
import json
import os
import re
import time
from datetime import datetime
from dotenv import load_dotenv
from openai import OpenAI

# =============================================================================
# CONFIGURATION
# =============================================================================

load_dotenv()
BUAS_LLM_KEY = os.getenv("BUAS_LLM_KEY", "")

# Available models:
# {"name": "Qwen3.5-122B",    "base_url": "https://edirlei.com/buas-llm-server/v1", "api_key": BUAS_LLM_KEY},
# {"name": "Qwen3.6-27B",     "base_url": "https://edirlei.com/buas-llm-server/v1", "api_key": BUAS_LLM_KEY},
# {"name": "GPT-OSS-120B",    "base_url": "https://edirlei.com/buas-llm-server/v1", "api_key": BUAS_LLM_KEY},
# {"name": "Llama3.3-70B",    "base_url": "https://edirlei.com/buas-llm-server/v1", "api_key": BUAS_LLM_KEY},
# {"name": "claude-opus-4-7", "base_url": "https://edirlei.com/buas-llm-server/v1", "api_key": BUAS_LLM_KEY},

MODEL_CONFIGS = [
    {"name": "claude-opus-4-7", "base_url": "https://edirlei.com/buas-llm-server/v1", "api_key": BUAS_LLM_KEY},
]


RUNS_PER_MODEL   = 1
MAX_RETRIES      = 3
MAX_TOKENS       = 8192

ROOT_DIR = os.path.join(os.path.dirname(__file__), "Inputs")
CHAPTERS_DIR    = os.path.join(ROOT_DIR, "Chapters")
CHARACTERS_DIR  = os.path.join(ROOT_DIR, "Characters")
WORLD_STATE_DIR = os.path.join(ROOT_DIR, "World_State")
SYSTEM_DIR      = os.path.join(ROOT_DIR, "System")
WORLD_STATE_FILE = "world_state_initial.json"

OUTPUT_DIR = "eval_results_buas"
os.makedirs(OUTPUT_DIR, exist_ok=True)

SCALE_STEP_RANGES = {
    "small":  (5, 15),
    "medium": (10, 30),
    "large":  (20, 50),
}

# =============================================================================
# FILE LOADERS
# =============================================================================

def load_json(path: str) -> dict | list:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def load_all_chapters() -> list[dict]:
    files = glob.glob(os.path.join(CHAPTERS_DIR, "*.json"))
    chapters = []
    for path in files:
        data = load_json(path)
        entries = data if isinstance(data, list) else [data]
        chapters.extend(entries)
    chapters.sort(key=lambda c: c.get("id", ""))
    return chapters


def load_chapter(chapter_id: str) -> dict:
    files = glob.glob(os.path.join(CHAPTERS_DIR, "*.json"))
    for path in files:
        data = load_json(path)
        chapters = data if isinstance(data, list) else [data]
        for chapter in chapters:
            if chapter.get("id") == chapter_id:
                return chapter
    raise FileNotFoundError(f"Chapter '{chapter_id}' not found")


def load_characters() -> list[dict]:
    files = sorted(glob.glob(os.path.join(CHARACTERS_DIR, "*.json")))
    characters = []
    for path in files:
        data = load_json(path)
        characters.extend(data if isinstance(data, list) else [data])
    return characters


def load_world_state(path: str | None = None) -> dict:
    p = path or os.path.join(WORLD_STATE_DIR, WORLD_STATE_FILE)
    ws = load_json(p)
    ws.pop("_comment", None)
    if "world_state" in ws:
        return ws["world_state"]
    return ws


def load_action_library() -> dict:
    raw = load_json(os.path.join(SYSTEM_DIR, "action_library.json"))
    player_actions = [
        a for a in raw.get("action_library", [])
        if "player" in a.get("actors", [])
    ]
    return {"action_library": player_actions}


def load_world_rules() -> dict:
    return load_json(os.path.join(SYSTEM_DIR, "world_rules.json"))


# =============================================================================
# PROMPT BUILDERS
# =============================================================================

def _format_rules(world_state_rules: dict) -> str:
    rules_list = (
        world_state_rules.get("world_rules")
        or world_state_rules.get("world_state_rules", [])
    )
    return "\n".join(
        f"  {r['id']}: {r['rule']} — {r['description']}"
        for r in rules_list
    )


def build_system_prompt(action_library: dict, world_rules: dict, chapter: dict, total_chapters: int) -> str:
    rules_text       = _format_rules(world_rules)
    final_chapter_id = f"C{total_chapters}"
    is_final         = chapter.get("id") == final_chapter_id

    win_condition = (
        f"12. WIN CONDITION: This IS the final chapter ({final_chapter_id}). "
        "Bring the story to a satisfying close. The player should complete their final objective "
        "and the chapter should end in a way that feels conclusive. "
        "You decide what the final action is — it must follow logically from the situation and world state."
        if is_final else
        f"12. WIN CONDITION: The game ends when the final chapter ({final_chapter_id}) is completed — but NOT YET. "
        f"This is chapter {chapter.get('id')} of {total_chapters}. "
        "Focus on this chapter's situation. Do not try to end the game here."
    )

    return f"""You are a creative quest designer for a post-apocalyptic RPG game set on a zombie-infested island.

== TERMINOLOGY ==
- "player" — the single human-controlled character. The player is the only one who performs quest actions.
- "character" — any named person in the world (player or NPC). Used when referring to people in general.
- "NPC" — a non-player character (e.g. sarah, marcus, george, anne, mary, linda, viktor, the_doctor).
  NPCs appear in dialogue and the world state but do NOT perform quest steps — only the player does.
- "actor" — the field in each step that names who performs that action. For all quest steps, actor = "player".

== QUEST DESIGN INSTRUCTIONS ==
1. Read the situation — it describes a problem or state of the world, not a solution. You decide how to resolve it.
2. Be creative. The player might find a cure, or might decide to burn everything down. Both are valid.
3. Use only characters, locations, and items that exist in the world state. Character names must be used exactly as they appear — do not rename, invent, or substitute any character.
4. Only use actions from the provided action library. All actions are performed by the player.
5. CRITICAL — DIALOGUE: Every TALK action MUST include a "dialogue_content" field in its parameters.
   - It MUST be an array of turn objects, each with exactly: "speaker" (character name or "PLAYER") and "line".
   - Minimum 2 turns, maximum 8 turns.
   - Dialogue must match the actions that follow — a character must not promise to do something the player executes.
   - OMIT "dialogue_content" entirely for all non-TALK actions.
6. CRITICAL — MOVEMENT: Before every PICKUP or interaction, verify the player is at the correct location. If not, add a MOVE step first.
6b. CRITICAL — GIVE_ITEM: The player is always the actor (giver). The NPC is always the target (receiver). If an NPC is handing something to the player, model this as the player picking it up with PICKUP — not GIVE_ITEM.
7. CRITICAL — LOCKED PLACES: A location with the "locked" condition CANNOT be entered with MOVE. The player MUST use UNLOCK with the correct key item first. Check every location's conditions in the world state before planning any MOVE or action inside it. Ignoring a locked condition is invalid output.
   Also: if a location does NOT have "locked" in its conditions, it is already open — do NOT plan an UNLOCK for it.
8. Follow all world rules strictly.
9. Number steps globally (1, 2, 3...) across all quests in the chapter.
10. CRITICAL — QUEST START: Every quest MUST begin with a MOVE step followed immediately by a TALK with an NPC at that location. NO quest may start with TALK, PICKUP, or any other action before the first MOVE. No exceptions.
10b. CRITICAL — NO DUPLICATE TALKS: Never plan two consecutive TALK actions with the same NPC at the same location. Merge them into a single TALK with a longer dialogue_content array (up to 8 turns).
11. CRITICAL — WORLD STATE GROUNDING: Before planning any step, verify it against the world state.
   (a) ITEMS: every item you reference must be at the exact location listed in the world state items list — do not assume an item is somewhere based on its name or theme.
   (b) PATHS: to reach a location connected through locked intermediaries, you must UNLOCK and MOVE through every hop in the chain — you cannot jump directly to a deep location.
   (c) If your plan requires an item or location that the world state does not support, choose a different approach.
{win_condition}

World Rules:
{rules_text}

Action Library (player actions only):
{json.dumps(action_library, indent=2)}

Output Format:
Return ONLY a valid JSON object with this exact structure, no explanation:

{{
  "chapter_id": <string>,
  "chapter_title": <string>,
  "quest_type": <string>,
  "required": <boolean>,
  "scale": <string>,
  "quests": [
    {{
      "quest_id": <string>,
      "quest_title": <string>,
      "steps": [
        {{
          "step": <integer>,
          "action": <string>,
          "actor": "player",
          "parameters": {{
            "... action-specific fields ...": "...",
            "dialogue_content": [
              {{"speaker": "<character_name_or_PLAYER>", "line": "<what they say>"}},
              {{"speaker": "<character_name_or_PLAYER>", "line": "<what they say>"}}
            ]
          }}
        }}
      ]
    }}
  ]
}}
"""


def build_chapter_prompt(chapter: dict, world_state: dict, characters: list[dict]) -> str:
    return f"""Generate a quest chapter based on the situation and world state below.

== SITUATION ==
{chapter.get('situation', 'No situation provided.')}

== CHAPTER METADATA ==
ID:       {chapter.get('id', 'UNKNOWN')}
Type:     {chapter.get('quest_type', 'UNKNOWN')}
Required: {chapter.get('required', False)}
Scale:    {chapter.get('scale', 'medium')}

== CHARACTERS ==
{json.dumps(characters, indent=2)}

== CURRENT WORLD STATE ==
{json.dumps(world_state, indent=2)}

== TASK ==
- You decide the chapter title, quest titles, number of quests, and how the situation is resolved.
- Be creative — the player does not have to follow an obvious path.
- Use character personalities to shape dialogue and interactions.
- All quest steps are performed by the player. NPCs appear only in dialogue and world state.
- IMPORTANT: Only use the NPC names listed in the world state. Never invent new character names.
- IMPORTANT: Every quest must start with the player MOVEing to a location where an NPC is present, followed immediately by a TALK with that NPC. No quest may begin with any other action.
- IMPORTANT: Never plan two consecutive TALK actions with the same NPC at the same location — merge them into one TALK.
- IMPORTANT: Check EVERY location's conditions before planning any MOVE or UNLOCK. If a location has "locked" in its conditions, use UNLOCK first. If it does NOT have "locked", do not plan UNLOCK — it is already open.
- IMPORTANT: If an NPC gives something to the player, model this as PICKUP by the player — not GIVE_ITEM. GIVE_ITEM is only for the player giving items to NPCs.
- IMPORTANT: NPC characters with the "infected" condition can only speak in dialogue. They cannot perform actions.
- For every TALK action, write the actual dialogue as a dialogue_content array of speaker/line turn objects.
- Follow all world rules.
- Number steps globally across all quests.
"""


# =============================================================================
# LLM
# =============================================================================

def make_client(config: dict) -> OpenAI:
    return OpenAI(base_url=config["base_url"], api_key=config["api_key"])


def query_llm(client: OpenAI, model_name: str, system_prompt: str, user_prompt: str) -> tuple[str, int, int]:
    """Returns (raw_text, input_tokens, output_tokens)."""
    response = client.chat.completions.create(
        model=model_name,
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user",   "content": user_prompt},
        ],
        max_tokens=MAX_TOKENS,
    )
    raw = (response.choices[0].message.content or "").strip()
    usage = response.usage
    input_tokens  = usage.prompt_tokens     if usage else 0
    output_tokens = usage.completion_tokens if usage else 0
    return raw, input_tokens, output_tokens


# =============================================================================
# STEP NORMALISER
# =============================================================================

def normalise_step(step: dict) -> dict:
    """
    Move any top-level fields that belong inside parameters into parameters.
    This fixes Qwen's habit of placing action fields at the wrong JSON level.
    Reserved fields that must stay at the top level: step, action, actor, parameters.
    All other fields are moved into parameters. parameters values take priority
    if the same key exists at both levels.
    """
    reserved = {"step", "action", "actor", "parameters"}
    params = step.get("parameters", {})
    top_level_fields = {k: v for k, v in step.items() if k not in reserved}
    if top_level_fields:
        merged = {**top_level_fields, **params}
        step = {k: v for k, v in step.items() if k in reserved}
        step["parameters"] = merged
    return step


def parse_json_output(raw: str) -> dict | None:
    cleaned = re.sub(r"<think>.*?</think>", "", raw, flags=re.DOTALL).strip()
    cleaned = re.sub(r"```(?:json)?\s*|\s*```", "", cleaned).strip()
    try:
        data = json.loads(cleaned)
        # Normalise step formatting — move misplaced top-level fields into parameters
        for quest in data.get("quests", []):
            quest["steps"] = [normalise_step(s) for s in quest.get("steps", [])]
        return data
    except json.JSONDecodeError:
        return None


# =============================================================================
# WORLD STATE UPDATER
# =============================================================================

def _get_character(ws, name):
    if name == "player":
        return ws.get("player")
    return next((n for n in ws.get("npcs", []) if n["name"] == name), None)

def _get_location(ws, name):
    return next((l for l in ws.get("locations", []) if l["name"] == name), None)

def _get_item(ws, name):
    return next((i for i in ws.get("items", []) if i["name"] == name), None)

def _get_object(ws, name):
    return next((o for o in ws.get("objects", []) if o["name"] == name), None)

def _rm_inv(char, item):
    inv = char.get("inventory", [])
    if item in inv:
        inv.remove(item)
        return True
    return False

def _add_inv(char, item):
    char.setdefault("inventory", []).append(item)

def _rm_cond(entity, cond):
    c = entity.get("conditions", [])
    if cond in c:
        c.remove(cond)

def _add_cond(entity, cond):
    c = entity.setdefault("conditions", [])
    if cond not in c:
        c.append(cond)


def apply_chapter_to_world_state(world_state: dict, chapter: dict) -> tuple[dict, list[str]]:
    ws = copy.deepcopy(world_state)
    errors = []

    def handle(step):
        action = step.get("action", "").upper()
        p      = {**step, **step.get("parameters", {})}
        sn     = step.get("step")

        if action == "MOVE":
            actor = _get_character(ws, p.get("actor"))
            if actor:
                actor["location"] = p.get("to")

        elif action == "PICKUP":
            actor = _get_character(ws, p.get("actor"))
            item  = _get_item(ws, p.get("item"))
            if actor and item:
                item["location"] = None
                _add_inv(actor, p.get("item"))

        elif action == "DROP":
            actor = _get_character(ws, p.get("actor"))
            item  = _get_item(ws, p.get("item"))
            if actor and item:
                _rm_inv(actor, p.get("item"))
                item["location"] = p.get("place")

        elif action == "GIVE_ITEM":
            actor  = _get_character(ws, p.get("actor"))
            target = _get_character(ws, p.get("target"))
            if actor and target:
                if not _rm_inv(actor, p.get("item")):
                    errors.append(f"Step {sn}: GIVE_ITEM item not in inventory")
                else:
                    _add_inv(target, p.get("item"))

        elif action == "UNLOCK":
            actor = _get_character(ws, p.get("actor"))
            loc   = _get_location(ws, p.get("target_place"))
            if actor and loc:
                _rm_inv(actor, p.get("key_item"))
                _rm_cond(loc, "locked")
                actor["location"] = p.get("target_place")

        elif action == "REPAIR":
            actor = _get_character(ws, p.get("actor"))
            obj   = _get_object(ws, p.get("target"))
            if actor and obj:
                _rm_inv(actor, p.get("toolkit_item"))
                _rm_inv(actor, p.get("wood_item"))
                obj["state"] = "fixed"

        elif action == "TURN_POWER_ON":
            actor = _get_character(ws, p.get("actor"))
            loc   = _get_location(ws, p.get("target_place"))
            if actor and loc:
                _rm_inv(actor, p.get("fuse_item"))
                _rm_cond(loc, "no_power")
                _add_cond(loc, "power_on")

        elif action == "FORTIFY":
            actor = _get_character(ws, p.get("actor"))
            loc   = _get_location(ws, p.get("place"))
            if actor and loc:
                _rm_inv(actor, p.get("wood_item"))
                _add_cond(loc, "fortified")

        elif action == "SYNTHESIZE_CURE":
            actor = _get_character(ws, p.get("actor"))
            if actor:
                sample = next((i for i in actor.get("inventory", []) if "cure_sample" in i), None)
                if sample:
                    _rm_inv(actor, sample)
                    _add_inv(actor, "antidote_1")

        elif action == "USE_CURE":
            actor  = _get_character(ws, p.get("actor"))
            target = _get_character(ws, p.get("target"))
            if actor and target:
                _rm_inv(actor, p.get("item"))
                _rm_cond(target, "infected")
                _rm_cond(target, "injured")
                _add_cond(target, "healthy")

    for quest in chapter.get("quests", []):
        for step in quest.get("steps", []):
            handle(step)

    return ws, errors


# =============================================================================
# METRICS
# =============================================================================

def _all_steps(chapter: dict) -> list[dict]:
    steps = []
    for quest in chapter.get("quests", []):
        steps.extend(quest.get("steps", []))
    return steps


def _known_names(world_state: dict) -> tuple[set, set, set]:
    locations = {l["name"] for l in world_state.get("locations", [])}
    npcs      = {n["name"] for n in world_state.get("npcs", [])}
    items     = {i["name"] for i in world_state.get("items", [])}
    return locations, npcs, items


def _valid_action_names(action_library: dict) -> set:
    return {a["action"] for a in action_library.get("action_library", [])}


def _required_params(action_library: dict) -> dict[str, set]:
    result = {}
    for a in action_library.get("action_library", []):
        params = set(a.get("parameters", [])) - {"actor"}
        result[a["action"]] = params
    return result


def evaluate_chapter(
    chapter: dict,
    world_state: dict,
    action_library: dict,
    chapter_id: str,
    locked_locations: set | None = None,
) -> dict:
    steps       = _all_steps(chapter)
    valid_acts  = _valid_action_names(action_library)
    req_params  = _required_params(action_library)
    known_locs, known_npcs, known_items = _known_names(world_state)

    all_npc_names  = known_npcs | {"player"}
    all_item_names = known_items

    num_quests = len(chapter.get("quests", []))
    num_steps  = len(steps)
    scale      = chapter.get("scale", "medium")
    lo, hi     = SCALE_STEP_RANGES.get(scale, (0, 9999))
    scale_mismatch = int(not (lo <= num_steps <= hi))

    invalid_actions    = 0
    actor_not_player   = 0
    missing_parameters = 0
    unknown_parameters = 0

    for step in steps:
        action = step.get("action", "")
        actor  = step.get("actor", "")
        params = step.get("parameters", {})

        if action not in valid_acts:
            invalid_actions += 1
            continue

        if actor != "player":
            actor_not_player += 1

        expected       = req_params.get(action, set())
        expected_check = expected - {"dialogue_content"}
        actual         = set(params.keys()) - {"dialogue_content"}

        for ep in expected_check:
            if ep not in params:
                missing_parameters += 1

        all_expected = expected | {"dialogue_content"}
        for ap in actual:
            if ap not in all_expected:
                unknown_parameters += 1

    locked_move            = 0
    move_noop              = 0
    hallucinated_locations = 0
    hallucinated_npcs      = 0
    hallucinated_items     = 0

    # Build a mutable locked set — updated as UNLOCK steps are encountered
    # so that re-entering a previously unlocked location is not falsely flagged
    if locked_locations is None:
        locked_locations = {
            l["name"]
            for l in world_state.get("locations", [])
            if "locked" in l.get("conditions", [])
        }
    else:
        locked_locations = set(locked_locations)

    for step in steps:
        action = step.get("action", "")
        params = step.get("parameters", {})

        if action == "MOVE":
            to_loc   = params.get("to", "")
            from_loc = params.get("from", "")
            if to_loc in locked_locations:
                locked_move += 1
            if to_loc == from_loc:
                move_noop += 1
            if to_loc and to_loc not in known_locs:
                hallucinated_locations += 1
            if from_loc and from_loc not in known_locs:
                hallucinated_locations += 1

        elif action == "UNLOCK":
            target = params.get("target_place", "")
            # Remove from locked set so subsequent MOVE steps are not falsely flagged
            if target:
                locked_locations.discard(target)
            if target and target not in known_locs:
                hallucinated_locations += 1

        elif action == "TALK":
            target = params.get("target", "")
            place  = params.get("place", "")
            if target and target not in all_npc_names:
                hallucinated_npcs += 1
            if place and place not in known_locs:
                hallucinated_locations += 1

        elif action in ("PICKUP", "DROP"):
            item  = params.get("item", "")
            place = params.get("place", "")
            if item and item not in all_item_names:
                hallucinated_items += 1
            if place and place not in known_locs:
                hallucinated_locations += 1

        elif action == "GIVE_ITEM":
            item   = params.get("item", "")
            target = params.get("target", "")
            if item and item not in all_item_names:
                hallucinated_items += 1
            if target and target not in all_npc_names:
                hallucinated_npcs += 1

        elif action in ("SYNTHESIZE_CURE", "USE_CURE"):
            item = params.get("item", "")
            if item and item not in all_item_names and item != "antidote_1":
                hallucinated_items += 1

    pickup_no_move    = 0
    synth_no_sample   = 0
    repair_no_toolkit = 0
    repair_no_wood    = 0
    use_cure_no_synth = 0

    sim_inventory        : list[str] = list(world_state.get("player", {}).get("inventory", []))
    sim_location         : str       = world_state.get("player", {}).get("location", "")
    sim_synthesized_cure : bool      = False

    item_locations: dict[str, str] = {
        i["name"]: i.get("location", "")
        for i in world_state.get("items", [])
    }

    for step in steps:
        action = step.get("action", "")
        params = step.get("parameters", {})

        if action == "MOVE":
            sim_location = params.get("to", sim_location)

        elif action == "PICKUP":
            item           = params.get("item", "")
            expected_place = item_locations.get(item, "")
            if expected_place and sim_location != expected_place:
                pickup_no_move += 1
            sim_inventory.append(item)
            item_locations[item] = None

        elif action == "DROP":
            item = params.get("item", "")
            if item in sim_inventory:
                sim_inventory.remove(item)
            item_locations[item] = sim_location

        elif action == "GIVE_ITEM":
            item = params.get("item", "")
            if item in sim_inventory:
                sim_inventory.remove(item)

        elif action == "UNLOCK":
            key = params.get("key_item", "")
            if key in sim_inventory:
                sim_inventory.remove(key)
            sim_location = params.get("target_place", sim_location)

        elif action == "SYNTHESIZE_CURE":
            sample = next((i for i in sim_inventory if "cure_sample" in i), None)
            if not sample:
                synth_no_sample += 1
            else:
                sim_inventory.remove(sample)
                sim_inventory.append("antidote_1")
                sim_synthesized_cure = True

        elif action == "REPAIR":
            toolkit = params.get("toolkit_item", "")
            wood    = params.get("wood_item", "")
            if toolkit not in sim_inventory:
                repair_no_toolkit += 1
            else:
                sim_inventory.remove(toolkit)
            if wood not in sim_inventory:
                repair_no_wood += 1
            else:
                sim_inventory.remove(wood)

        elif action == "USE_CURE":
            item = params.get("item", "")
            if not sim_synthesized_cure and "antidote_1" not in sim_inventory:
                use_cure_no_synth += 1
            if item in sim_inventory:
                sim_inventory.remove(item)

    quest_no_talk  = 0
    duplicate_talk = 0

    for quest in chapter.get("quests", []):
        qsteps   = quest.get("steps", [])
        has_talk = any(s.get("action") == "TALK" for s in qsteps)
        if not has_talk:
            quest_no_talk += 1

        prev_talk_target  = None
        prev_talk_place   = None
        consecutive_count = 0
        for s in qsteps:
            if s.get("action") == "TALK":
                target = s.get("parameters", {}).get("target")
                place  = s.get("parameters", {}).get("place")
                if target == prev_talk_target and place == prev_talk_place:
                    consecutive_count += 1
                else:
                    consecutive_count = 0
                prev_talk_target = target
                prev_talk_place  = place
            else:
                prev_talk_target  = None
                prev_talk_place   = None
                consecutive_count = 0
            if consecutive_count >= 1:
                duplicate_talk += 1

    return {
        "chapter_id":             chapter_id,
        "num_quests":             num_quests,
        "num_steps":              num_steps,
        "scale_mismatch":         scale_mismatch,
        "invalid_actions":        invalid_actions,
        "actor_not_player":       actor_not_player,
        "missing_parameters":     missing_parameters,
        "unknown_parameters":     unknown_parameters,
        "locked_move":            locked_move,
        "move_noop":              move_noop,
        "hallucinated_locations": hallucinated_locations,
        "hallucinated_npcs":      hallucinated_npcs,
        "hallucinated_items":     hallucinated_items,
        "pickup_no_move":         pickup_no_move,
        "synth_no_sample":        synth_no_sample,
        "repair_no_toolkit":      repair_no_toolkit,
        "repair_no_wood":         repair_no_wood,
        "use_cure_no_synth":      use_cure_no_synth,
        "quest_no_talk":          quest_no_talk,
        "duplicate_talk":         duplicate_talk,
    }


# =============================================================================
# GENERATION LOOP
# =============================================================================

def generate_chapter(
    client: OpenAI,
    model_name: str,
    chapter: dict,
    characters: list[dict],
    world_state: dict,
    action_library: dict,
    world_rules: dict,
    total_chapters: int,
) -> tuple[dict | None, int, int, int, float]:
    system_prompt = build_system_prompt(action_library, world_rules, chapter, total_chapters)
    user_prompt   = build_chapter_prompt(chapter, world_state, characters)

    total_input  = 0
    total_output = 0
    chapter_data = None
    t_start      = time.time()

    for attempt in range(1, MAX_RETRIES + 1):
        print(f"      [Attempt {attempt}/{MAX_RETRIES}] Querying LLM...")
        try:
            raw, inp, out = query_llm(client, model_name, system_prompt, user_prompt)
            total_input  += inp
            total_output += out
        except Exception as e:
            print(f"      [ERROR] LLM call failed: {e}")
            continue

        chapter_data = parse_json_output(raw)
        if chapter_data is not None:
            print(f"      [OK] JSON parsed and normalised successfully.")
            break
        print(f"      [WARN] JSON parse failed, retrying...")

    elapsed = time.time() - t_start
    return chapter_data, total_input, total_output, attempt, elapsed


# =============================================================================
# MAIN EVALUATION LOOP
# =============================================================================

def run_evaluation():
    timestamp    = datetime.now().strftime("%Y%m%d_%H%M%S")
    all_chapters = load_all_chapters()
    total_chaps  = len(all_chapters)
    characters   = load_characters()
    action_lib   = load_action_library()
    world_rules  = load_world_rules()

    print(f"=== EVALUATION START: {timestamp} ===")
    print(f"Chapters: {[c['id'] for c in all_chapters]}")
    print(f"Models:   {[m['name'] for m in MODEL_CONFIGS]}")
    print(f"Runs/model: {RUNS_PER_MODEL}\n")

    all_rows = []

    for model_cfg in MODEL_CONFIGS:
        model_name = model_cfg["name"]
        client     = make_client(model_cfg)
        print(f"\n{'='*60}")
        print(f"MODEL: {model_name}")
        print(f"{'='*60}")

        for run in range(1, RUNS_PER_MODEL + 1):
            print(f"\n  --- Run {run}/{RUNS_PER_MODEL} ---")

            world_state = load_world_state()
            run_rows    = []
            run_quests  = []
            current_locked = {
                l["name"]
                for l in world_state.get("locations", [])
                if "locked" in l.get("conditions", [])
            }

            for chapter_def in all_chapters:
                chapter_id = chapter_def["id"]
                print(f"    [Chapter {chapter_id}]")

                chapter_data, inp_tok, out_tok, attempts, elapsed = generate_chapter(
                    client, model_name,
                    chapter_def, characters,
                    world_state, action_lib,
                    world_rules, total_chaps,
                )

                json_parse_success = int(chapter_data is not None)

                if chapter_data is not None:
                    metrics = evaluate_chapter(chapter_data, world_state, action_lib, chapter_id, current_locked)
                    for quest in chapter_data.get("quests", []):
                        for step in quest.get("steps", []):
                            if step.get("action") == "UNLOCK":
                                current_locked.discard(step.get("parameters", {}).get("target_place", ""))
                else:
                    metrics = {
                        "chapter_id": chapter_id,
                        "num_quests": 0, "num_steps": 0, "scale_mismatch": 1,
                        "invalid_actions": 0, "actor_not_player": 0,
                        "missing_parameters": 0, "unknown_parameters": 0,
                        "locked_move": 0, "move_noop": 0,
                        "hallucinated_locations": 0, "hallucinated_npcs": 0, "hallucinated_items": 0,
                        "pickup_no_move": 0, "synth_no_sample": 0,
                        "repair_no_toolkit": 0, "repair_no_wood": 0, "use_cure_no_synth": 0,
                        "quest_no_talk": 0, "duplicate_talk": 0,
                    }

                row = {
                    "model":              model_name,
                    "run":                run,
                    "chapter_id":         chapter_id,
                    "json_parse_success": json_parse_success,
                    "attempts":           attempts,
                    "generation_time_s":  round(elapsed, 2),
                    "input_tokens":       inp_tok,
                    "output_tokens":      out_tok,
                    "total_tokens":       inp_tok + out_tok,
                    **{k: v for k, v in metrics.items() if k != "chapter_id"},
                }
                run_rows.append(row)
                all_rows.append(row)

                if chapter_data is not None:
                    run_quests.append({
                        "model":      model_name,
                        "run":        run,
                        "chapter_id": chapter_id,
                        "quest_data": chapter_data,
                    })

                print(f"      json_ok={json_parse_success}  steps={metrics['num_steps']}  "
                      f"missing_params={metrics['missing_parameters']}  "
                      f"halluc_npcs={metrics['hallucinated_npcs']}  "
                      f"time={elapsed:.1f}s  tokens={inp_tok+out_tok}")

                if chapter_data is not None:
                    world_state, ws_errors = apply_chapter_to_world_state(world_state, chapter_data)
                    if ws_errors:
                        print(f"      [WS WARNINGS] {len(ws_errors)} issue(s):")
                        for e in ws_errors:
                            print(f"        ⚠ {e}")

            checkpoint_path = os.path.join(
                OUTPUT_DIR,
                f"checkpoint_{model_name.replace('/', '_')}_{timestamp}_run{run:02d}.json"
            )
            with open(checkpoint_path, "w", encoding="utf-8") as f:
                json.dump(run_rows, f, indent=2)
            print(f"    [CHECKPOINT] Saved → {checkpoint_path}")

            quests_path = os.path.join(
                OUTPUT_DIR,
                f"quests_{model_name.replace('/', '_')}_{timestamp}_run{run:02d}.json"
            )
            with open(quests_path, "w", encoding="utf-8") as f:
                json.dump(run_quests, f, indent=2)
            print(f"    [QUESTS]     Saved → {quests_path}")

    if not all_rows:
        print("\n[ERROR] No results to save.")
        return

    fieldnames = list(all_rows[0].keys())

    detail_csv = os.path.join(OUTPUT_DIR, f"eval_detail_{timestamp}.csv")
    with open(detail_csv, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(all_rows)
    print(f"\n[SAVED] Detail CSV → {detail_csv}")

    import statistics
    numeric_fields = [k for k in fieldnames if k not in ("model", "run", "chapter_id")]
    summary_rows   = []

    groups: dict[tuple, list[dict]] = {}
    for row in all_rows:
        key = (row["model"], row["chapter_id"])
        groups.setdefault(key, []).append(row)

    for (model, chapter_id), rows in sorted(groups.items()):
        summary = {"model": model, "chapter_id": chapter_id, "n_runs": len(rows)}
        for field in numeric_fields:
            vals = [r[field] for r in rows if isinstance(r.get(field), (int, float))]
            if vals:
                summary[f"{field}_mean"]  = round(statistics.mean(vals), 3)
                summary[f"{field}_stdev"] = round(statistics.stdev(vals) if len(vals) > 1 else 0.0, 3)
            else:
                summary[f"{field}_mean"]  = None
                summary[f"{field}_stdev"] = None
        summary_rows.append(summary)

    summary_csv = os.path.join(OUTPUT_DIR, f"eval_summary_{timestamp}.csv")
    with open(summary_csv, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(summary_rows[0].keys()))
        writer.writeheader()
        writer.writerows(summary_rows)
    print(f"[SAVED] Summary CSV → {summary_csv}")
    print("\n=== EVALUATION COMPLETE ===")


# =============================================================================
# ENTRY POINT
# =============================================================================

if __name__ == "__main__":
    run_evaluation()