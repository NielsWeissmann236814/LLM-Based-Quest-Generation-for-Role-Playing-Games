# LLM-Based Quest Generation for Role-Playing Games

Repository for the graduation project **"LLM-Based Quest Generation for Role-Playing Games"** by Niels Weissmann (Student Number: 236814), Breda University of Applied Sciences, 2026.

This repository contains the full LÖVE2D game prototype, the Python generation API, generation scripts, evaluation scripts, and all generated results used in the accompanying research paper. The paper is available [here](https://github.com/NielsWeissmann236814/LLM-Based-Quest-Generation-for-Role-Playing-Games/blob/main/LLMQuestGenerationPaper.pdf).

---

## How It Works

When the player presses Enter on the title screen, the game jumps into a loading screen and immediately calls the Python API to generate the first quest chapter using an LLM. A timer is shown during generation. Once the quest plan is returned as JSON, the game starts and the player executes the generated quest steps.

The generation service receives three inputs: the shared input definitions (action library, world rules, chapter definitions, character definitions), the live world state exported from the game, and the system and user prompts that instruct the LLM. When a chapter is completed, the world state is updated and sent to the API as context for the next chapter generation.

This behaviour is controlled by two flags at the top of `main.lua`:

```lua
LLM_QUESTS = true   -- enable/disable LLM quest generation
LLM_NPCS   = false  -- enable/disable LLM NPC behaviour scheduling
```

Setting `LLM_QUESTS = false` launches the game without generating a quest. Setting `LLM_NPCS = true` enables the LLM-driven NPC behaviour system developed by peer Peter Husen (off by default).

---

## Repository Structure

```
/                        → LÖVE2D game source (Lua)
│   main.lua             → Game entry point: loop, rendering, input, generation trigger
│   QuestSystem.lua      → Calls the API and manages quest chapter state
│   QuestRunner.lua      → Tracks player progress through generated quest steps
│   QuestWorker.lua      → Background thread that handles the API call during loading
│   QuestDialog.lua      → Displays LLM-generated dialogue exchanges in-game
│   QuestUI.lua          → In-game quest objectives panel
│   WorldState.lua       → Tracks the current state of all locations, items, and characters
│   NPCfiles             → Manages NPC state, actions, position, inventory and more for Peter Husen's project
│   Player.lua           → Player movement, shooting, item collection
│   Level.lua            → Tiled map loading and tile management
│   ...                  → Supporting systems (inventory, pathfinding, enemies, shader, zombies, etc.)
│
/api                     → Python quest generation API (FastAPI)
│   quest_generation.py  → Quest generation API; /generate produces a chapter plan, /validate checks it against the live world state and automatically replans if invalid (/validate is not yet called from the game and remains future work)
│   npc_generation.py    → NPC behaviour generation endpoint for Peter Husen's project
│
/data                    → Shared input definitions — read by both the game client and the generation service
│   action_library.json  → All valid player actions with preconditions and parameters
│   world_rules.json     → World state rules governing action preconditions
│   chapters.json        → Chapter definitions with situation descriptions and scale
│   characters.json      → NPC definitions used during generation
│
/Generation_Scripts      → Standalone generation scripts, system_prompt.txt, and sample outputs per model — see README inside
/Eval_Scripts            → Evaluation script, analysis notebook, and full results per model — see README inside
/levels                  → Tiled map files (.tmx) for all game locations
/images                  → Game sprites and UI assets
/audio                   → Game audio files
/libs                    → Third-party Lua libraries
```

---

## Running the Game

### 1. Install LÖVE2D

Download and install LÖVE2D from [https://love2d.org/](https://love2d.org/)

Then add it to your system PATH so it can be called from the terminal:

1. Open **Edit the system environment variables** (search in the Windows start menu)
2. Click **Environment Variables**
3. Under **System variables**, select **Path** and click **Edit**
4. Click **New** and add the path to your LÖVE2D installation — typically `C:\Program Files\LOVE`
5. Click **OK** and save

### 2. Set Up the API Key

Create a `.env` file inside the `/api` folder:

```
BUAS_LLM_KEY=your_key_here
```

### 3. Start the Generation API

Open a terminal in the repo root and run:

```bash
cd api
pip install -r requirements.txt
uvicorn quest_generation:app --reload --port 8000
```

The API will be available at `http://localhost:8000`. You can verify it is running by visiting `http://localhost:8000/docs`.

### 4. Launch the Game

With the API running, go back to the repo root. Either:

- Press `Ctrl+Shift+B` in VS Code to run the default build task
- Or run manually from the terminal:

```bash
love .
```

Press **Enter** on the title screen to start. The game will generate the first quest chapter before gameplay begins.

---

## Generation Scripts

The `/Generation_Scripts` folder contains the standalone scripts (`quest_generation_local.py` and `quest_generation_local_claude.py`) used to generate quest plans outside of the game environment. These are the scripts used for single run tests.

Sample outputs from manual generation runs are stored per model:

| Folder | Model |
|---|---|
| `Results_Claude` | Claude Opus 4.7 |
| `Results_GPT_OSS` | GPT-OSS-120B |
| `Results_LLama` | Llama-3.3-70B-Instruct |
| `Results_Qwen` | Qwen3.5-122B-A10B |

See `Generation_Scripts/README.md` for setup instructions, configuration, and how to chain chapters. The system prompt used in this work is available at `Generation_Scripts/system_prompt.txt`.

---

## Evaluation Scripts

The `/Eval_Scripts` folder contains the scripts used to measure quest quality across the five models evaluated in the paper. These are the scripts used during the evaluation described in the paper.

- `eval_quest_generation.py` — runs generation and evaluation across all local models and chapters
- `eval_quest_generation_Claude.py` — Claude-specific version; run separately due to API parameter differences
- `Evaluation_Notebook_First_Version.ipynb` — notebook for analysing and visualising results

Full results are stored per model in subfolders:

| Folder | Model |
|---|---|
| `eval_results_buas_Claude` | Claude Opus 4.7 (10 runs) |
| `eval_results_buas_Speed_Test` | Qwen3.6-27B (10 runs) |
| `eval_results_buas_Three_Models` | GPT-OSS-120B, Llama-3.3-70B, Qwen3.5-122B (10 runs each) |

Each folder contains per-run quest outputs (JSON), checkpoints (JSON), and summary/detail CSVs.

See `Eval_Scripts/README.md` for a full description of all metrics, configuration, and hardware used during the evaluation.

---

## Requirements

- [LÖVE2D](https://love2d.org/) (game runtime)
- Python 3.11+
- `fastapi`, `uvicorn`, `openai`, `python-dotenv` (API dependencies)
- A valid `BUAS_LLM_KEY` in `/api/.env`

---

## Credits

The game prototype was originally developed by **Edirlei Soares de Lima** (supervisor) and adapted for this project. The NPC behaviour system was developed by **Peter Husen** as part of a parallel research track and is included here as an optional component.
