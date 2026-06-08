# LLM-Based Quest Generation for Role-Playing Games

Repository for the graduation project **"LLM-Based Quest Generation for Role-Playing Games"** by Niels Weissmann (Student Number: 236814), Breda University of Applied Sciences, 2026.

This repository contains the Python quest generation API, evaluation scripts, input definitions, and all generated results used in the accompanying research paper. The paper is available [here](https://github.com/NielsWeissmann236814/LLM-Based-Quest-Generation-for-Role-Playing-Games/blob/main/LLMQuestGenerationPaper.pdf).

The game prototype used in this project was developed by **Edirlei Soares de Lima** and is available at [https://github.com/edirleilima/zombie-days](https://github.com/edirleilima/zombie-days).

---

## How It Works

The generation pipeline receives the current world state from the game alongside shared input definitions (action library, world rules, chapter definitions, character definitions) and a system prompt, and calls an LLM to produce a structured quest plan in JSON format. The quest plan is validated for structural correctness and retried if malformed. When a chapter is completed, the world state is updated and passed as context for the next chapter.

The full system and user prompts used in this work are available in `system_prompt.md` at the root of this repository.

---

## Repository Structure

```
/
│   system_prompt.md     → Full system and user prompts used for quest generation
│   LLMQuestGenerationPaper.pdf → Accompanying research paper
│
/api                     → Python quest generation API (FastAPI)
│   quest_generation.py  → /generate produces a chapter plan, /validate checks it against
│                          the live world state and automatically replans if invalid
│                          (/validate is implemented but not yet called from the game)
│
/data                    → Input definitions used in the evaluation
│   action_library.json  → All valid player actions with preconditions and parameters
│   world_rules.json     → World state rules governing action preconditions
│   chapters.json        → Chapter definitions with situation descriptions and scale
│   characters.json      → NPC definitions used during generation
│
/Eval_Scripts            → Evaluation scripts, notebook, and full results — see README inside
```

---

## API

The `/api` folder contains the FastAPI quest generation service.

### Setup

Create a `.env` file inside the `/api` folder:

```
BUAS_LLM_KEY=your_key_here
```

### Running

```bash
cd api
pip install fastapi uvicorn openai python-dotenv
uvicorn quest_generation:app --reload --port 8000
```

The API will be available at `http://localhost:8000`. Visit `http://localhost:8000/docs` to verify it is running and explore the endpoints.

### Endpoints

- `POST /generate` — generates a quest chapter from the provided world state, action library, world rules, and chapter definition
- `POST /validate` — validates an existing quest plan against the current world state and automatically replans if invalid (implemented but not yet called from the game)
- `GET /health` — service status check

The scripts are configured to use a BUAS-hosted inference server. To reproduce with your own models, update `base_url` and `api_key` in the script to point to any OpenAI-compatible API endpoint.

---

## Input Definitions

The `/data` folder contains the structured input files used by both the generation API and the evaluation scripts:

| File | Description |
|---|---|
| `action_library.json` | All valid player actions with preconditions and parameters |
| `world_rules.json` | World state rules governing action preconditions |
| `chapters.json` | Chapter definitions with situation descriptions and scale |
| `characters.json` | NPC definitions used during generation |

---

## Evaluation Scripts

The `/Eval_Scripts` folder contains the scripts used to measure quest quality across the five models evaluated in the paper.

- `eval_quest_generation.py` — runs generation and evaluation across all local models and chapters
- `eval_quest_generation_Claude.py` — Claude-specific version; run separately due to API parameter differences
- `Evaluation_Notebook_Final_Version.ipynb` — notebook for analysing and visualising results

Full results are stored per model in subfolders:

| Folder | Model |
|---|---|
| `eval_results_buas_Claude` | Claude Opus 4.7 (10 runs) |
| `eval_results_buas_Speed_Test` | Qwen3.6-27B (10 runs) |
| `eval_results_buas_Three_Models` | GPT-OSS-120B, Llama-3.3-70B, Qwen3.5-122B (10 runs each) |

See `Eval_Scripts/README.md` for a full description of all metrics, configuration, and hardware used during the evaluation.

---

## Requirements

- Python 3.11+
- `fastapi`, `uvicorn`, `openai`, `python-dotenv`
- A valid API key in `/api/.env`

---

## Credits

The game prototype was developed by **Edirlei Soares de Lima** (supervisor).