# Generation Scripts

This folder contains the standalone quest generation script used for single-run tests and manual generation of quest chapters outside the game environment. It uses the same prompt and generation pipeline as the evaluation script.

---

## Scripts

- `Quest_QwenV9.py` — main generation script; configure and run this
- `world_state_updater.py` — applies the generated quest steps to the world state; called automatically at the end of each run. Must be present in the same folder as `Quest_QwenV9.py`
- `system_prompt.txt` — the system and user prompts used for quest generation, provided as a standalone reference file

---

## What It Does

`Quest_QwenV9.py` generates a single quest chapter for a given chapter ID by:

1. Loading the chapter definition, characters, world state, action library, and world rules from the `inputs` folder
2. Building the system and user prompts
3. Calling the LLM API and parsing the JSON response
4. Validating that all TALK actions contain structured dialogue — retrying up to 3 times if not
5. Saving the generated quest plan as `quest_output_{CHAPTER_ID}.json`
6. Updating the world state based on the generated steps and saving it as `world_state_after_{CHAPTER_ID}.json`

To chain chapters, set `WORLD_STATE_FILE` to the previously saved world state output before running the next chapter.

---

## Configuration

At the top of `Quest_QwenV9.py`, set the following before running:

```python
OLLAMA_MODEL     = "Qwen3.6-27B"          # Model to use — see Model_List.ipynb for available models
TARGET_CHAPTER   = "C1"                   # Chapter to generate: "C1", "C2", or "C3"
WORLD_STATE_FILE = "world_state_initial.json"  # Starting world state; update when chaining chapters
ROOT_DIR         = r"C:\...\LLM-Quest-RPG\Generation_Scripts\inputs"  # Update to your local path
```

---

## Running the Script

```bash
cd Generation_Scripts
python Quest_QwenV9.py
```

The script prints progress to the terminal and saves two output files in the `Generation_Scripts` folder:

- `quest_output_{CHAPTER_ID}.json` — the generated quest plan
- `world_state_after_{CHAPTER_ID}.json` — the updated world state after applying all quest steps

To generate all three chapters in sequence:

1. Run with `TARGET_CHAPTER = "C1"`, `WORLD_STATE_FILE = "world_state_initial.json"`
2. Run with `TARGET_CHAPTER = "C2"`, `WORLD_STATE_FILE = "world_state_after_C1.json"`
3. Run with `TARGET_CHAPTER = "C3"`, `WORLD_STATE_FILE = "world_state_after_C2.json"`

---

## Inputs

All input files are located in the `inputs` folder:

```
inputs/
├── Chapters/         → Chapter definitions (id, quest_type, required, scale, situation)
├── Characters/       → Character definitions (name, role, personality, goal, dialogue_style)
├── World_State/      → world_state_initial.json and any previously saved world states
└── System/           → action_library.json and world_rules.json
```

---

## Sample Results

The `Results_*` folders contain sample outputs from manual generation runs used during development:

| Folder | Model |
|---|---|
| `Results_Claude` | Claude Opus 4.7 |
| `Results_GPT_OSS` | GPT-OSS-120B |
| `Results_LLama` | Llama-3.3-70B-Instruct |
| `Results_Qwen` | Qwen3.5-122B-A10B |

---

## Requirements

- Python 3.11+
- `openai`, `python-dotenv` 
- A valid `BUAS_LLM_KEY` in a `.env` file in this folder
