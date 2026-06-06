"""
Quest Generation API
Run with: python -m uvicorn quest_generation:app --reload --port 8000
Go to: http://localhost:8000/docs

Endpoints:
  POST /generate          — generate a chapter from provided inputs
  POST /validate          — validate a quest plan; auto-replans if invalid
  GET  /health            — health check

Terminology:
  "player"    — the single human-controlled character. Performs all quest steps.
  "character" — any named person in the world (player or NPC).
  "NPC"       — a non-player character. Appears in dialogue and world state only.
  "actor"     — the field in each step that names who performs the action (always "player").
"""

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from openai import OpenAI
import json
import re
from dotenv import load_dotenv
import os

load_dotenv()
BUAS_LLM_KEY = os.getenv("BUAS_LLM_KEY", "")

openai_client = OpenAI(base_url="https://edirlei.com/buas-llm-server/v1", api_key=BUAS_LLM_KEY)
OPENAI_MODEL  = "Qwen3.6-27B"

app = FastAPI(
    title="Quest Generation API",
    description="Generates RPG quest chapters using a local LLM.",
    version="5.2.0"
)

# =============================================================================
# REQUEST MODELS
# =============================================================================

class GenerateRequest(BaseModel):
    chapter: dict = Field(
        ...,
        description="Chapter definition with id, quest_type, required, scale, situation."
    )
    characters: list[dict] = Field(
        ...,
        description="List of character definitions available in the world."
    )
    world_state: dict = Field(
        ...,
        description="Current world state (locations, items, NPC positions, etc.)."
    )
    action_library: dict = Field(
        ...,
        description="Catalogue of valid actions. Filtered to player-only actions server-side."
    )
    world_rules: dict = Field(
        ...,
        description="Rules object with key 'world_rules' (list of {id, rule, description})."
    )
    total_chapters: int = Field(
        default=3,
        description="Total number of chapters in the game. Used to determine the final chapter."
    )


class ValidateRequest(BaseModel):
    quest_plan: dict = Field(
        ...,
        description="The quest plan to validate. Must contain a 'quests' list with steps."
    )
    chapter: dict = Field(
        ...,
        description="Original chapter definition (same as used in /generate)."
    )
    characters: list[dict] = Field(
        ...,
        description="List of character definitions (same as used in /generate)."
    )
    world_state: dict = Field(
        ...,
        description="The CURRENT live world state from the game (may differ from generation time)."
    )
    action_library: dict = Field(
        ...,
        description="Catalogue of valid actions (same as used in /generate)."
    )
    world_rules: dict = Field(
        ...,
        description="Rules object with key 'world_rules' (same as used in /generate)."
    )
    total_chapters: int = Field(
        default=3,
        description="Total number of chapters. Used for win condition if replanning is needed."
    )


# =============================================================================
# ACTION LIBRARY FILTER
# =============================================================================

def filter_player_actions(action_library: dict) -> dict:
    player_actions = [
        a for a in action_library.get("action_library", [])
        if "player" in a.get("actors", [])
    ]
    return {"action_library": player_actions}


# =============================================================================
# WORLD STATE NORMALISER
# =============================================================================

def normalise_world_state(world_state: dict) -> dict:
    if "world_state" in world_state:
        return world_state["world_state"]
    return world_state


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
    world_state_rules: dict,
    chapter: dict,
    total_chapters: int = 3,
) -> str:
    rules_text       = _format_rules(world_state_rules)
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


def build_validation_prompt(
    quest_plan: dict,
    chapter: dict,
    characters: list[dict],
    world_state: dict,
    world_state_rules: dict,
    action_library: dict,
) -> str:
    rules_text = _format_rules(world_state_rules)
    return f"""You are a quest validator for a post-apocalyptic RPG game. A quest plan was generated earlier, but the game world may have changed since then. Your job is to determine whether the remaining steps in the quest plan are still valid given the CURRENT world state.

== TERMINOLOGY (reminder) ==
- "player" = the human-controlled character who performs all quest steps.
- "NPC" = any non-player character. Appears in dialogue only — never performs quest steps.
- "actor" = always "player" in valid quest steps.

For each remaining step, check:
1. Are all referenced characters still present and at the expected locations?
2. Are all referenced items still at the expected locations or in the expected inventories?
3. Are all referenced locations still accessible? (A location with "locked" condition cannot be entered via MOVE.)
4. Are all action names still valid in the action library?
5. Is each step's actor "player"?
6. Would any step now violate a world rule given the current state?
7. Are infected NPCs referenced in a way that requires them to perform actions?

World Rules:
{rules_text}

Action Library (player actions only):
{json.dumps(action_library, indent=2)}

== CHAPTER METADATA ==
{json.dumps(chapter, indent=2)}

== CHARACTERS ==
{json.dumps(characters, indent=2)}

== CURRENT LIVE WORLD STATE ==
{json.dumps(world_state, indent=2)}

== QUEST PLAN TO VALIDATE ==
{json.dumps(quest_plan, indent=2)}

Output ONLY one of two verdicts — no other output:

If VALID (all remaining steps are still achievable):
{{
  "valid": true,
  "issues": [],
  "recommendation": "Quest is still fully valid — continue running."
}}

If INVALID (one or more steps are now blocked):
{{
  "valid": false,
  "issues": [
    {{
      "step": <integer or null>,
      "quest_id": <string or null>,
      "issue": "<clear description of the problem>"
    }}
  ],
  "invalidated_from_step": <integer — earliest broken step>,
  "recommendation": "<brief suggestion>"
}}
"""


# =============================================================================
# LLM
# =============================================================================

def query_llm(system_prompt: str, user_prompt: str) -> str:
    response = openai_client.chat.completions.create(
        model=OPENAI_MODEL,
        messages=[
            {"role": "system", "content": system_prompt},
            {"role": "user",   "content": user_prompt},
        ],
        max_tokens=8192,
        temperature=0.7,
        extra_body={
            "chat_template_kwargs": {"enable_thinking": False},
            "reasoning_effort": "low",
        },
    )
    raw = (response.choices[0].message.content or "").strip()
    if not raw:
        print(f"  [DEBUG] Empty response — finish_reason: {response.choices[0].finish_reason}")
    return raw


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
                    warnings.append(f"Step {step_num}: dialogue_content is not an array")
                elif len(dialogue) < 2:
                    warnings.append(f"Step {step_num}: dialogue_content has fewer than 2 turns")
                else:
                    for i, turn in enumerate(dialogue):
                        if not isinstance(turn, dict) or "speaker" not in turn or "line" not in turn:
                            warnings.append(f"Step {step_num}, turn {i}: missing 'speaker' or 'line'")
    return warnings


# =============================================================================
# DIALOGUE REPAIR
# =============================================================================

def _collect_broken_talk_steps(chapter_data: dict) -> list[dict]:
    broken = []
    for quest in chapter_data.get("quests", []):
        for step in quest.get("steps", []):
            if step.get("action") == "TALK":
                dialogue = step.get("parameters", {}).get("dialogue_content")
                if (
                    dialogue is None
                    or not isinstance(dialogue, list)
                    or len(dialogue) < 2
                    or any(
                        not isinstance(t, dict) or "speaker" not in t or "line" not in t
                        for t in dialogue
                    )
                ):
                    broken.append(step)
    return broken


def _repair_dialogue(chapter_data: dict, broken_steps: list[dict]) -> dict:
    steps_summary = []
    for s in broken_steps:
        params = {k: v for k, v in s.get("parameters", {}).items() if k != "dialogue_content"}
        steps_summary.append({
            "step": s["step"],
            "action": "TALK",
            "actor": "player",
            "parameters": params
        })

    repair_system = (
        "You are a dialogue writer for a post-apocalyptic RPG. "
        "You will receive a list of TALK steps that are missing their dialogue_content. "
        "For each step, write a realistic, in-character dialogue_content array. "
        "Each entry must have exactly 'speaker' (character name or 'PLAYER') and 'line'. "
        "Minimum 2 turns, maximum 8 turns per step. "
        "Return ONLY a valid JSON array — no explanation, no markdown — with this structure:\n"
        '[{"step": <int>, "dialogue_content": [{"speaker": "...", "line": "..."}]}, ...]'
    )

    repair_user = (
        f"Fill in dialogue_content for each of these TALK steps:\n"
        f"{json.dumps(steps_summary, indent=2)}"
    )

    print(f"  [REPAIR] Requesting dialogue for {len(broken_steps)} broken TALK step(s)...")
    try:
        raw = query_llm(repair_system, repair_user)
    except Exception as e:
        print(f"  [REPAIR] LLM call failed: {e}")
        return chapter_data

    cleaned = re.sub(r"<think>.*?</think>", "", raw, flags=re.DOTALL).strip()
    cleaned = re.sub(r"```(?:json)?\s*|\s*```", "", cleaned).strip()
    try:
        repairs: list[dict] = json.loads(cleaned)
    except json.JSONDecodeError as e:
        print(f"  [REPAIR] Could not parse repair JSON: {e}")
        return chapter_data

    repair_map: dict[int, list] = {}
    for item in repairs:
        step_num = item.get("step")
        content  = item.get("dialogue_content")
        if step_num is not None and isinstance(content, list) and len(content) >= 2:
            repair_map[step_num] = content

    applied = 0
    for quest in chapter_data.get("quests", []):
        for step in quest.get("steps", []):
            if step.get("action") == "TALK" and step.get("step") in repair_map:
                step.setdefault("parameters", {})["dialogue_content"] = repair_map[step["step"]]
                applied += 1

    print(f"  [REPAIR] Applied {applied}/{len(broken_steps)} dialogue repairs.")
    return chapter_data


# =============================================================================
# SHARED GENERATION HELPER
# =============================================================================

def _run_generation(
    chapter: dict,
    characters: list[dict],
    world_state: dict,
    action_library: dict,
    world_state_rules: dict,
    total_chapters: int = 3,
) -> dict | None:
    system_prompt = build_system_prompt(action_library, world_state_rules, chapter, total_chapters)
    user_prompt   = build_chapter_prompt(chapter, world_state, characters)

    MAX_RETRIES  = 3
    chapter_data = None

    for attempt in range(1, MAX_RETRIES + 1):
        print(f"  [Attempt {attempt}/{MAX_RETRIES}] Querying LLM...")
        try:
            raw_output   = query_llm(system_prompt, user_prompt)
            chapter_data = parse_json_output(raw_output)
        except Exception as e:
            print(f"  [ERROR] Attempt {attempt} failed: {e}")
            continue

        if chapter_data is None:
            print("  [ERROR] JSON parsing failed, retrying...")
            continue

        warnings = validate_dialogue(chapter_data)

        if not warnings:
            print("  [OK] Dialogue valid.")
            break

        print(f"  [WARN] {len(warnings)} dialogue issue(s) — attempting repair...")
        broken_steps = _collect_broken_talk_steps(chapter_data)
        chapter_data = _repair_dialogue(chapter_data, broken_steps)
        warnings     = validate_dialogue(chapter_data)

        if not warnings:
            print("  [OK] Dialogue valid after repair.")
            break

        print(f"  [REPAIR] {len(warnings)} issue(s) remain after repair.")
        if attempt < MAX_RETRIES:
            print("  Retrying full generation...")
            chapter_data = None

    if chapter_data is None:
        return None

    remaining = validate_dialogue(chapter_data)
    if remaining:
        print(f"  [WARN] Returning chapter with {len(remaining)} unresolved dialogue warning(s).")

    return chapter_data


# =============================================================================
# INPUT VALIDATION
# =============================================================================

def validate_generate_inputs(req: GenerateRequest) -> None:
    if "id" not in req.chapter:
        raise HTTPException(status_code=422, detail="chapter must contain an 'id' field.")
    rules = req.world_rules
    if "world_rules" not in rules and "world_state_rules" not in rules:
        raise HTTPException(
            status_code=422,
            detail="world_rules must contain a top-level 'world_rules' list."
        )


def validate_validate_inputs(req: ValidateRequest) -> None:
    if "quests" not in req.quest_plan and "chapters" not in req.quest_plan:
        raise HTTPException(
            status_code=422,
            detail="quest_plan must contain a 'quests' list or a 'chapters' list."
        )
    rules = req.world_rules
    if "world_rules" not in rules and "world_state_rules" not in rules:
        raise HTTPException(
            status_code=422,
            detail="world_rules must contain a top-level 'world_rules' list."
        )


# =============================================================================
# ENDPOINTS
# =============================================================================

@app.get("/health")
def health():
    return {"status": "ok", "model": OPENAI_MODEL}


@app.post("/generate")
def generate_chapter(request: GenerateRequest):
    """
    Generate a quest chapter from fully client-supplied inputs.

    Request body:
    - **chapter**: chapter definition (id, quest_type, required, scale, situation)
    - **characters**: list of character definitions
    - **world_state**: current world state (flat or wrapped — both handled)
    - **action_library**: catalogue of valid actions (filtered to player-only server-side)
    - **world_state_rules**: object with a 'world_rules' list
    - **total_chapters**: total number of chapters (default 3), used for win condition
    """
    print("Starting quest generation...")
    validate_generate_inputs(request)

    world_state    = normalise_world_state({k: v for k, v in request.world_state.items() if k != "_comment"})
    action_library = filter_player_actions(request.action_library)

    print(f"  [INFO] NPCs in world state: {[n.get('name') for n in world_state.get('npcs', [])]}")

    chapter_data = _run_generation(
        chapter=request.chapter,
        characters=request.characters,
        world_state=world_state,
        action_library=action_library,
        world_state_rules=request.world_rules,
        total_chapters=request.total_chapters,
    )

    if chapter_data is None:
        raise HTTPException(status_code=500, detail="LLM returned unparseable JSON after all retries.")

    response_data = {k: v for k, v in chapter_data.items() if k != "world_state_after"}
    print("Quest generation done!")
    return response_data


@app.post("/validate")
def validate_quest_plan(request: ValidateRequest):
    """
    Validate a quest plan against the current live world state.

    - If VALID  → returns { valid: true } and the game continues running.
    - If INVALID → automatically regenerates a fresh quest plan using the current
                   world state and returns it so the game can swap it in immediately.
    """
    print("Starting quest validation...")
    validate_validate_inputs(request)

    world_state    = normalise_world_state({k: v for k, v in request.world_state.items() if k != "_comment"})
    action_library = filter_player_actions(request.action_library)

    VALIDATION_SYSTEM_PROMPT = (
        "You are a precise quest validator for an RPG game engine. "
        "Check whether a quest plan is still executable given the current world state. "
        "Be thorough but practical — only flag genuine blockers, not minor inconsistencies. "
        "Return ONLY valid JSON with exactly the structure requested. "
        "Respond with valid=true if everything is fine, valid=false if any step is blocked."
    )

    user_prompt = build_validation_prompt(
        quest_plan=request.quest_plan,
        chapter=request.chapter,
        characters=request.characters,
        world_state=world_state,
        world_state_rules=request.world_rules,
        action_library=action_library,
    )

    try:
        raw_output = query_llm(VALIDATION_SYSTEM_PROMPT, user_prompt)
        result     = parse_json_output(raw_output)
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"LLM query failed: {e}")

    if result is None:
        raise HTTPException(status_code=500, detail="LLM returned unparseable JSON during validation.")

    is_valid = bool(result.get("valid", False))

    if is_valid:
        print("Quest validation done — valid, continuing.")
        return {
            "valid": True,
            "issues": [],
            "recommendation": "Quest is still fully valid — continue running.",
        }

    print(f"Quest invalid from step {result.get('invalidated_from_step')} — replanning...")

    new_plan = _run_generation(
        chapter=request.chapter,
        characters=request.characters,
        world_state=world_state,
        action_library=action_library,
        world_state_rules=request.world_rules,
        total_chapters=request.total_chapters,
    )

    if new_plan is None:
        raise HTTPException(
            status_code=500,
            detail="Quest was invalid and replanning also failed — LLM returned unparseable JSON."
        )

    print("Replanning done — returning updated quest plan.")
    return {
        "valid": False,
        "issues": result.get("issues", []),
        "invalidated_from_step": result.get("invalidated_from_step"),
        "recommendation": result.get("recommendation", "Regenerated from current world state."),
        "updated_quest_plan": new_plan,
    }