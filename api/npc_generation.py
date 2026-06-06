"""
NPC Schedule Generation API
----------------------------
A game-agnostic REST endpoint that accepts a character description, world state,
world rules, and action library, then returns an LLM-generated NPC daily schedule.

Usage:
    pip install fastapi uvicorn requests
    uvicorn npc_generation:app --host 0.0.0.0 --reload --port 8001

POST /generate
    Generate a daily schedule for a single NPC.

POST /validate
    Validate whether an existing schedule is still pursuable given an updated world state.

GET /health
    Returns: service status
"""

import re
import os
import json
import requests
import logging
from typing import Any
from openai import OpenAI
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from dotenv import load_dotenv

load_dotenv()
BUAS_LLM_KEY = os.getenv("BUAS_LLM_KEY", "")

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

openai_client = OpenAI(base_url="https://edirlei.com/buas-llm-server/v1", api_key=BUAS_LLM_KEY,)
OPENAI_MODEL = "Qwen3.6-27B" #"Qwen3.5-122B"
MAX_RETRIES   = 3

logging.basicConfig(level=logging.INFO, format="%(levelname)s | %(message)s")
log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Pydantic schemas
# ---------------------------------------------------------------------------

class GenerateRequest(BaseModel):
    """All fields required to generate a schedule for a single NPC."""

    npc_name: str = Field(
        ...,
        description="The name of the NPC whose schedule is being generated.",
        examples=["sarah"]
    )
    character_description: dict[str, Any] = Field(
        ...,
        description="Plain-text behavioral profile for this NPC."
    )
    world_state: dict[str, Any] = Field(
        ...,
        description="Full world state object (locations, items, characters, connections)."
    )
    world_rules: dict[str, Any] = Field(
        ...,
        description="JSON object describing the rules of this game world."
    )
    action_library: dict[str, Any] = Field(
        ...,
        description="The complete action library available to NPCs in this game."
    )
    temperature: float = Field(
        default=0.7,
        ge=0.0,
        le=1.0,
        description="LLM sampling temperature. Lower = more deterministic."
    )
    max_tokens: int = Field(
        default=4096,
        ge=256,
        le=32768,
        description="Maximum tokens the LLM may generate."
    )


class ValidateRequest(BaseModel):
    """All fields required to validate an existing schedule against an updated world state."""

    npc_name: str = Field(
        ...,
        description="The name of the NPC whose schedule is being validated.",
        examples=["sarah"]
    )
    character_description: str = Field(
        ...,
        description="Plain-text behavioral profile for this NPC."
    )
    current_schedule: dict[str, Any] = Field(
        ...,
        description="The existing schedule to validate, in the same format returned by /generate."
    )
    updated_world_state: dict[str, Any] = Field(
        ...,
        description="The new world state to validate the schedule against."
    )
    world_rules: dict[str, Any] = Field(
        ...,
        description="JSON object describing the rules of this game world."
    )
    action_library: dict[str, Any] = Field(
        ...,
        description="The complete action library available to NPCs in this game."
    )
    temperature: float = Field(default=0.7, ge=0.0, le=1.0)
    max_tokens: int    = Field(default=4096, ge=256, le=32768)


class ScheduleResult(BaseModel):
    goal:  str
    steps: list[str]


class GenerateResponse(BaseModel):
    npc_name: str
    schedule: ScheduleResult


class ValidateResponse(BaseModel):
    npc_name:       str
    pursuable:      bool = Field(
        ...,
        description="True if the existing schedule can still be executed, False if it must be regenerated."
    )
    reason:         str = Field(
        ...,
        description="Explanation of why the schedule is or is not still pursuable."
    )
    updated_schedule: ScheduleResult | None = Field(
        default=None,
        description="A revised schedule if the original is no longer pursuable, otherwise null."
    )


# ---------------------------------------------------------------------------
# System prompts
# ---------------------------------------------------------------------------

GENERATE_PROMPT_TEMPLATE = """You are an NPC behavior planner for a video game. Your task is to generate a
believable and executable daily schedule for a given NPC based on the current WORLD STATE
and available ACTION LIBRARY.

## YOUR ROLE
Given a WORLD STATE, an ACTION LIBRARY, and a target NPC, produce a sequential daily
schedule as a JSON array of action steps. Each step must be grounded in the formal
action definitions as descrived in the WORLD STATE -- meaning all preconditions must be 
satisfied at the time of execution, and effects must be tracked forward through the schedule.

## OUTPUT FORMAT
Answer only with the specified JSON. Do not add explanations outside the JSON.

{{
  "schedule": {{
    "goal": "<brief description of the daily schedule>",
    "steps": [
      "action1(parameter1, parameter2, ...)",
      "action2(parameter1, parameter2, ...)"
    ]
  }}
}}

## WORLD RULES
{world_rules}

## STRICT RULES
{strict_rules}
"""

STRICT_RULES = """
1. Use only elements present in the WORLD STATE. Do not invent items, places, characters, or paths not explicitly listed.
2. Single actor: Every action must have the NPC as the actor. Other characters may appear as targets or parameters.
3. Goal alignment: The schedule must match the NPC's goals and personality.
4. NPC scope: The NPC is NOT the player. They act autonomously within their own context. They should not attempt objectives clearly belonging to the player.
5. The NPC may only perform actions in locations reachable given the WORLD STATE. Do not move to or from locked locations unless the NPC already has the access key needed to unlock the location in their own inventory.
6. The NPC can only perform the actions descrived in the provided ACTION LIBRARY.
7. Always validate whether an action can be executed at a certain time based on the provided WORLD STATE.
8. The NPC can only use items that are in their own inventory, as specified in the provided WORLD STATE.
9. The NPC must strictly follow ALL the WORLD RULES described above.
10. ALL generated actions must include all parameters as specified in the ACTION LIBRARY.
11. Output action steps using positional parameters only. Never use named parameters or equals signs (e.g. actor='george' is forbidden)."""

VALIDATE_PROMPT_TEMPLATE = """You are an NPC schedule validator for a video game. Your task is to assess
whether an existing NPC schedule is still pursuable given a changed world state.

## YOUR ROLE
You will receive an NPC's current schedule, their character description, an updated world
state, and the action library. Determine whether the schedule can still be executed as-is,
partially, or not at all. If it cannot be executed, produce a revised schedule that fits
the new world state and still aligns with the NPC's goals and personality.

## OUTPUT FORMAT
Answer only with the specified JSON. Do not add explanations outside the JSON.

If the schedule IS still pursuable:
{{
  "pursuable": true,
  "reason": "<brief explanation of why the schedule still works>",
  "updated_schedule": null
}}

If the schedule is NOT pursuable:
{{
  "pursuable": false,
  "reason": "<brief explanation of what changed and why the schedule breaks>",
  "updated_schedule": {{
    "goal": "<revised goal>",
    "steps": [
      "action1(arg1, arg2, ...)",
      "action2(arg1, arg2, ...)"
    ]
  }}
}}

## WORLD RULES
{world_rules}

## STRICT RULES
{strict_rules}
"""

# ---------------------------------------------------------------------------
# Core LLM logic
# ---------------------------------------------------------------------------

def build_generate_system_prompt(world_rules: dict) -> str:
    return GENERATE_PROMPT_TEMPLATE.format(world_rules=json.dumps(world_rules, indent=2), strict_rules=STRICT_RULES)


def build_validate_system_prompt(world_rules: dict) -> str:
    return VALIDATE_PROMPT_TEMPLATE.format(world_rules=json.dumps(world_rules, indent=2), strict_rules=STRICT_RULES)


def build_generate_user_prompt(npc_name: str, character_description: str,
                               world_state: dict, action_library: dict) -> str:
    return (
        f"Generate a daily schedule for {npc_name.capitalize()}.\n\n"
        f"{character_description}\n\n"
        f"== WORLD STATE ==\n{json.dumps(world_state, indent=2)}\n\n"
        f"== ACTION LIBRARY ==\n{json.dumps(action_library, indent=2)}\n"
        f"== STRICT RULES ==\n{STRICT_RULES}"
    )


def build_validate_user_prompt(npc_name: str, character_description: str,
                               current_schedule: dict, updated_world_state: dict,
                               action_library: dict) -> str:
    return (
        f"Validate the schedule for {npc_name.capitalize()}.\n\n"
        f"{character_description}\n\n"
        f"== CURRENT SCHEDULE ==\n{json.dumps(current_schedule, indent=2)}\n\n"
        f"== UPDATED WORLD STATE ==\n{json.dumps(updated_world_state, indent=2)}\n\n"
        f"== ACTION LIBRARY ==\n{json.dumps(action_library, indent=2)}\n"        
    )


def call_llm(system_prompt: str, user_prompt: str,
             temperature: float, max_tokens: int) -> str:
    try:
        response = openai_client.chat.completions.create(
            model=OPENAI_MODEL,
            messages=[
                {"role": "system", "content": "/no_think\n\n" + system_prompt},
                {"role": "user",   "content": user_prompt}
            ],
            max_tokens=max_tokens,
            temperature=temperature,
            extra_body={"chat_template_kwargs": {"enable_thinking": False}, "reasoning_effort": "low"},
        )

        return (response.choices[0].message.content or "").strip()        

    except requests.exceptions.RequestException as e:
        log.error(f"LLM request failed: {e}")
        raise HTTPException(status_code=502, detail=f"LLM backend unreachable: {e}")


def parse_json_response(raw: str) -> dict:
    cleaned = re.sub(r"```(?:json)?\s*|\s*```", "", raw).strip()
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError as e:
        log.error(f"JSON parse failed: {e}\nRaw:\n{raw}")
        raise ValueError(f"LLM returned invalid JSON: {e}")


def run_generate(npc_name: str, character_description: str,
                 world_state: dict, world_rules: dict,
                 action_library: dict, temperature: float,
                 max_tokens: int) -> ScheduleResult:
    system_prompt = build_generate_system_prompt(world_rules)
    user_prompt   = build_generate_user_prompt(npc_name, character_description,
                                               world_state, action_library)
    last_error = None

    #print("SYSTEM PROMPT: " + system_prompt)
    #print("USER PROMPT: " + user_prompt)

    for attempt in range(1, MAX_RETRIES + 1):
        log.info(f"[generate/{npc_name}] Attempt {attempt}/{MAX_RETRIES}")
        try:
            raw  = call_llm(system_prompt, user_prompt, temperature, max_tokens)
            data = parse_json_response(raw)
            schedule = data.get("schedule", {})
            return ScheduleResult(
                goal  = schedule.get("goal", ""),
                steps = schedule.get("steps", [])
            )
        except (ValueError, KeyError) as e:
            last_error = e
            log.warning(f"[generate/{npc_name}] Attempt {attempt} failed: {e}")

    raise HTTPException(
        status_code=500,
        detail=f"Failed to generate schedule for '{npc_name}' after {MAX_RETRIES} attempts. Last error: {last_error}"
    )


def run_validate(npc_name: str, character_description: str,
                 current_schedule: dict, updated_world_state: dict,
                 world_rules: dict, action_library: dict,
                 temperature: float, max_tokens: int) -> dict:
    system_prompt = build_validate_system_prompt(world_rules)
    user_prompt   = build_validate_user_prompt(npc_name, character_description,
                                               current_schedule, updated_world_state,
                                               action_library)
    last_error = None

    for attempt in range(1, MAX_RETRIES + 1):
        log.info(f"[validate/{npc_name}] Attempt {attempt}/{MAX_RETRIES}")
        try:
            raw  = call_llm(system_prompt, user_prompt, temperature, max_tokens)
            data = parse_json_response(raw)
            return data
        except (ValueError, KeyError) as e:
            last_error = e
            log.warning(f"[validate/{npc_name}] Attempt {attempt} failed: {e}")

    raise HTTPException(
        status_code=500,
        detail=f"Failed to validate schedule for '{npc_name}' after {MAX_RETRIES} attempts. Last error: {last_error}"
    )


# ---------------------------------------------------------------------------
# FastAPI app
# ---------------------------------------------------------------------------

app = FastAPI(
    title       = "NPC Schedule API",
    description = (
        "A game-agnostic API for generating and validating LLM-driven NPC daily schedules. "
        "Accepts a character description, world state, world rules, and action library."
    ),
    version     = "1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins     = ["*"],  # Restrict to specific domains in production
    allow_credentials = True,
    allow_methods     = ["*"],
    allow_headers     = ["*"],
)


@app.get("/health", tags=["Utility"])
def health_check():
    """Returns the current service status."""
    return {"status": "ok", "model": OPENAI_MODEL, "server": OPENAI_MODEL}


@app.post("/generate", response_model=GenerateResponse, tags=["Schedule"])
def generate(req: GenerateRequest):
    """
    Generate a daily schedule for a single NPC.

    Call this at the start of a day cycle or when an NPC needs a fresh schedule.
    All game context is provided per request, making this endpoint reusable across any game.
    """
    log.info(f"Generate request for NPC: {req.npc_name}")
    result = run_generate(
        npc_name              = req.npc_name,
        character_description = req.character_description,
        world_state           = req.world_state,
        world_rules           = req.world_rules,
        action_library        = req.action_library,
        temperature           = req.temperature,
        max_tokens            = req.max_tokens
    )
    return GenerateResponse(npc_name=req.npc_name, schedule=result)


@app.post("/validate", response_model=ValidateResponse, tags=["Schedule"])
def validate(req: ValidateRequest):
    """
    Validate whether an existing NPC schedule is still pursuable after a world state change.

    Call this whenever the world state changes significantly (e.g. a location becomes
    blocked, an item is removed, a character dies). Returns whether the schedule still
    holds, a reason, and a revised schedule if it does not.
    """
    log.info(f"Validate request for NPC: {req.npc_name}")
    result = run_validate(
        npc_name              = req.npc_name,
        character_description = req.character_description,
        current_schedule      = req.current_schedule,
        updated_world_state   = req.updated_world_state,
        world_rules           = req.world_rules,
        action_library        = req.action_library,
        temperature           = req.temperature,
        max_tokens            = req.max_tokens
    )

    updated_schedule = None
    if not result.get("pursuable", True) and result.get("updated_schedule"):
        s = result["updated_schedule"]
        updated_schedule = ScheduleResult(
            goal  = s.get("goal", ""),
            steps = s.get("steps", [])
        )

    return ValidateResponse(
        npc_name         = req.npc_name,
        pursuable        = result.get("pursuable", False),
        reason           = result.get("reason", ""),
        updated_schedule = updated_schedule
    )