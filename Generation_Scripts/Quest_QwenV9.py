from openai import OpenAI
from dotenv import load_dotenv
from world_state_updater import apply_chapter_to_world_state
import json
import re
import os
import glob

# =============================================================================
# CONFIGURATION
# =============================================================================
load_dotenv()
BUAS_LLM_KEY = os.getenv("BUAS_LLM_KEY")

openai_client = OpenAI(
    base_url="https://edirlei.com/buas-llm-server/v1",
    api_key=BUAS_LLM_KEY,
)
OLLAMA_MODEL = "GPT-OSS-120B" # Check the Model List Notebook for available models on the server

# Chapter to generate — change this to any chapter ID (e.g. "C1", "C2", "C3")
TARGET_CHAPTER = "C1"

# World state input — change to a previously saved one to chain chapters.
# e.g. "world_state_after_C1.json" when generating C2.
WORLD_STATE_FILE = "world_state_initial.json"

# Paths
ROOT_DIR        = r"C:\Users\niels\OneDrive\Documents\2025-26-graduation-NielsWeissmann236814\Inputs"
CHAPTERS_DIR    = os.path.join(ROOT_DIR, "Chapters")
CHARACTERS_DIR  = os.path.join(ROOT_DIR, "Characters")
WORLD_STATE_DIR = os.path.join(ROOT_DIR, "World_State")
SYSTEM_DIR      = os.path.join(ROOT_DIR, "System")

# =============================================================================
# LOAD INPUTS FROM FILES
# =============================================================================

def load_json(path: str):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def load_all_chapters() -> list[dict]:
    """Load all chapter definitions from the chapters directory."""
    files = glob.glob(os.path.join(CHAPTERS_DIR, "*.json"))
    chapters = []
    for path in files:
        data = load_json(path)
        entries = data if isinstance(data, list) else [data]
        chapters.extend(entries)
    chapters.sort(key=lambda c: c.get("id", ""))
    return chapters


def load_chapter(chapter_id: str) -> dict:
    """Load a single chapter definition by ID from the chapters directory."""
    files = glob.glob(os.path.join(CHAPTERS_DIR, "*.json"))
    for path in files:
        data = load_json(path)
        chapters = data if isinstance(data, list) else [data]
        for chapter in chapters:
            if chapter.get("id") == chapter_id:
                print(f"  [LOADED] {os.path.basename(path)} (chapter {chapter_id})")
                return chapter
    raise FileNotFoundError(f"Chapter '{chapter_id}' not found in {CHAPTERS_DIR}")


def load_characters() -> list[dict]:
    """Load all character definitions from the characters directory."""
    files = sorted(glob.glob(os.path.join(CHARACTERS_DIR, "*.json")))
    characters = []
    for path in files:
        data = load_json(path)
        if isinstance(data, list):
            characters.extend(data)
        else:
            characters.append(data)
        print(f"  [LOADED] {os.path.basename(path)}")
    return characters


def load_world_state() -> dict:
    """Load the current world state. Checks local directory first for chained runs."""
    local_path = WORLD_STATE_FILE
    input_path = os.path.join(WORLD_STATE_DIR, WORLD_STATE_FILE)
    path = local_path if os.path.exists(local_path) else input_path
    ws = load_json(path)
    ws.pop("_comment", None)
    print(f"  [LOADED] {os.path.basename(path)}")
    return ws


def load_action_library() -> dict:
    """Load the action library and filter to player-only actions."""
    raw = load_json(os.path.join(SYSTEM_DIR, "action_library.json"))
    player_actions = [
        a for a in raw.get("action_library", [])
        if "player" in a.get("actors", [])
    ]
    return {"action_library": player_actions}


def load_world_state_rules() -> dict:
    """Load the world rules from the system directory."""
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


def build_system_prompt(
    action_library: dict,
    world_rules: dict,
    chapter: dict,
    total_chapters: int,
) -> str:
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
ID:       {chapter['id']}
Type:     {chapter['quest_type']}
Required: {chapter['required']}
Scale:    {chapter.get('scale', 'medium')} (small = 5–15 steps, medium = 10–30 steps, large = 20–50 steps)

== CHARACTERS ==
{json.dumps(characters, indent=2)}

== CURRENT WORLD STATE ==
{json.dumps(world_state, indent=2)}

== TASK ==
- You decide the chapter title, quest titles, number of quests, and how the situation is resolved.
- Be creative — the player does not have to follow an obvious path.
- Use character personalities to shape dialogue and interactions.
- All quest steps are performed by the player. NPCs appear only in dialogue and world state.
- IMPORTANT: Every quest must start with the player MOVEing to a location where an NPC is present, followed immediately by a TALK with that NPC. No quest may begin with any other action.
- IMPORTANT: Never plan two consecutive TALK actions with the same NPC at the same location — merge them into one TALK.
- IMPORTANT: Check EVERY location's conditions before planning any MOVE or UNLOCK. If a location has "locked" in its conditions, use UNLOCK first. If it does NOT have "locked", do not plan UNLOCK — it is already open.
- IMPORTANT: If an NPC gives something to the player, model this as PICKUP by the player — not GIVE_ITEM. GIVE_ITEM is only for the player giving items to NPCs.
- IMPORTANT: NPC characters with the "infected" condition cannot be talked to in a way that requires them to perform actions. They can only speak in dialogue.
- IMPORTANT: Characters with role "antagonist_npc" or "hostile_npc" will not help the player. Do not write quests where the player goes to them for assistance or cooperation.
- For every TALK action, write the actual dialogue as a dialogue_content array of speaker/line turn objects.
- Follow all world rules.
- Number steps globally across all quests.
"""


# =============================================================================
# LLM INTERACTION
# =============================================================================

def query_llm(system_prompt: str, user_prompt: str) -> str:
    try:
        response = openai_client.chat.completions.create(
            model=OLLAMA_MODEL,
            messages=[
                {"role": "system", "content": system_prompt},
                {"role": "user",   "content": user_prompt},
            ],
            max_tokens=8192,
            temperature=0.7,
        )
        raw = (response.choices[0].message.content or "").strip()
        if not raw:
            print(f"  [DEBUG] Empty response — finish_reason: {response.choices[0].finish_reason}")
        return raw
    except Exception as e:
        print(f"[ERROR] LLM query failed: {e}")
        return ""


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


def parse_json(raw_output: str) -> dict | None:
    cleaned = re.sub(r"<think>.*?</think>", "", raw_output, flags=re.DOTALL).strip()
    cleaned = re.sub(r"```(?:json)?\s*|\s*```", "", cleaned).strip()
    try:
        data = json.loads(cleaned)
        # Normalise step formatting — move misplaced top-level fields into parameters
        for quest in data.get("quests", []):
            quest["steps"] = [normalise_step(s) for s in quest.get("steps", [])]
        return data
    except json.JSONDecodeError as e:
        print(f"[ERROR] JSON parsing failed: {e}")
        print(f"[DEBUG] Raw output:\n{raw_output[:800]}")
        return None


def validate_dialogue(chapter: dict) -> list[str]:
    """Check that all TALK actions have valid structured dialogue_content."""
    warnings = []
    for quest in chapter.get("quests", []):
        for step in quest.get("steps", []):
            if step.get("action") == "TALK":
                params   = step.get("parameters", {})
                dialogue = params.get("dialogue_content")
                step_num = step.get("step")
                if dialogue is None:
                    warnings.append(f"Step {step_num}: TALK action missing dialogue_content")
                elif not isinstance(dialogue, list):
                    warnings.append(f"Step {step_num}: dialogue_content is not an array (got {type(dialogue).__name__})")
                elif len(dialogue) < 2:
                    warnings.append(f"Step {step_num}: dialogue_content has fewer than 2 turns")
                else:
                    for i, turn in enumerate(dialogue):
                        if not isinstance(turn, dict):
                            warnings.append(f"Step {step_num}, turn {i}: not an object")
                        elif "speaker" not in turn or "line" not in turn:
                            warnings.append(f"Step {step_num}, turn {i}: missing 'speaker' or 'line' key")
    return warnings


# =============================================================================
# OUTPUT
# =============================================================================

def print_chapter(chapter: dict) -> None:
    """Print a formatted summary of the generated chapter to the console."""
    required_label = "Required" if chapter.get("required") else "Optional"
    quest_type     = chapter.get("quest_type", "").upper()
    print(f"\n=== [{quest_type}] {chapter.get('chapter_id')}: {chapter.get('chapter_title')} [{required_label}] ===")
    for quest in chapter.get("quests", []):
        print(f"\n  -- {quest.get('quest_id')}: {quest.get('quest_title')} --")
        for step in quest.get("steps", []):
            params = step.get("parameters", {})
            action = step.get("action")
            if action == "TALK" and isinstance(params.get("dialogue_content"), list):
                dialogue = params.pop("dialogue_content")
                print(
                    f"    Step {step.get('step'):>2}: {action:<20} "
                    f"Actor: {step.get('actor'):<12} "
                    f"Params: {json.dumps(params)}"
                )
                for turn in dialogue:
                    print(f"              [{turn.get('speaker')}]: {turn.get('line')}")
                params["dialogue_content"] = dialogue
            else:
                print(
                    f"    Step {step.get('step'):>2}: {action:<20} "
                    f"Actor: {step.get('actor'):<12} "
                    f"Params: {json.dumps(params)}"
                )


# =============================================================================
# MAIN
# =============================================================================

if __name__ == "__main__":
    print("=== LOADING INPUTS ===\n")

    all_chapters   = load_all_chapters()
    total_chapters = len(all_chapters)
    print(f"[Chapters] {total_chapters} chapters found in {CHAPTERS_DIR}")

    print(f"\n[Chapter] Loading '{TARGET_CHAPTER}'...")
    chapter = load_chapter(TARGET_CHAPTER)

    print("\n[Characters]")
    characters = load_characters()

    print("\n[World State]")
    world_state    = load_world_state()
    action_library = load_action_library()
    wsr            = load_world_state_rules()

    rules_list = wsr.get("world_rules", [])
    print(f"\n[Characters]     {len(characters)} loaded")
    print(f"[Action Library] {len(action_library.get('action_library', []))} player actions loaded")
    print(f"[World Rules]    {len(rules_list)} rules loaded")
    print(f"[Total Chapters] {total_chapters} (final chapter: C{total_chapters})")

    system_prompt = build_system_prompt(action_library, wsr, chapter, total_chapters)

    print(f"\n=== GENERATING CHAPTER {TARGET_CHAPTER} ===\n")
    print(f"Situation: {chapter.get('situation')}\n")

    prompt = build_chapter_prompt(chapter, world_state, characters)

    MAX_RETRIES  = 3
    chapter_data = None
    warnings     = []

    for attempt in range(1, MAX_RETRIES + 1):
        print(f"[Attempt {attempt}/{MAX_RETRIES}] Querying LLM...")
        raw_output   = query_llm(system_prompt, prompt)
        chapter_data = parse_json(raw_output)

        if chapter_data is None:
            print("  [ERROR] JSON parsing failed, retrying...")
            continue

        warnings = validate_dialogue(chapter_data)
        if not warnings:
            print("\n[DIALOGUE] All TALK actions have valid structured dialogue ✓")
            break

        print("  [DIALOGUE WARNINGS] Dialogue invalid, retrying...")
        for w in warnings:
            print(f"    ⚠ {w}")

    if chapter_data is None:
        print("[ERROR] Failed to generate valid chapter after all retries. Exiting.")
        exit(1)

    if warnings:
        print("\n[WARNING] Saving despite dialogue issues after max retries.")

    print_chapter(chapter_data)

    quest_output_file = f"quest_output_{TARGET_CHAPTER}.json"
    with open(quest_output_file, "w") as f:
        json.dump(chapter_data, f, indent=2)
    print(f"\n[SAVED] {quest_output_file}")

    print(f"\n=== UPDATING WORLD STATE ===\n")
    updated_world_state, errors = apply_chapter_to_world_state(world_state, chapter_data)

    if errors:
        print("[WORLD STATE WARNINGS] Some steps could not be applied cleanly:")
        for err in errors:
            print(f"  ⚠ {err}")
    else:
        print("[WORLD STATE] All steps applied cleanly ✓")

    world_state_output_file = f"world_state_after_{TARGET_CHAPTER}.json"
    with open(world_state_output_file, "w") as f:
        json.dump(updated_world_state, f, indent=2)
    print(f"[SAVED] {world_state_output_file}")
    print(f"\nTo generate the next chapter, set:")
    print(f"  TARGET_CHAPTER   = 'C{int(TARGET_CHAPTER[1:]) + 1}'")
    print(f"  WORLD_STATE_FILE = '{world_state_output_file}'")