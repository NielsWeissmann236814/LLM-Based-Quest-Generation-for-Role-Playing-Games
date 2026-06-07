# Evaluation Scripts

This folder contains the evaluation script and analysis notebook used to measure quest generation quality across five LLMs, as described in the accompanying research paper. The evaluation runs generation and scoring independently of the game environment.

---

## Scripts and Files

- `eval_quest_generation.py` — main evaluation script for all local models; runs generation and scoring across all configured models and chapters
- `eval_quest_generation_Claude.py` — Claude-specific version of the evaluation script. Claude Opus 4.7 does not accept the `temperature` parameter or the `extra_body` thinking flags used by the local models. This version has those removed to avoid API errors. Run Claude separately using this script.
- `Evaluation_Notebook_First_Version.ipynb` — notebook for analysing and visualising the results; produces the tables and figures used in the paper
- `system_prompt.txt` — see `Generation_Scripts/system_prompt.txt`; the same prompt was used for both scripts

---

## What It Does

`eval_quest_generation.py` runs the full evaluation pipeline:

1. Loads chapters, characters, world state, action library, and world rules from the `inputs` folder
2. For each model and each run, generates all three chapters sequentially (C1 → C2 → C3), updating the world state between chapters
3. Evaluates each generated chapter across six metric categories (see below)
4. Saves a per-run checkpoint JSON and a per-run quest JSON after each run so nothing is lost on crash
5. At the end, produces a detail CSV (one row per run/chapter) and a summary CSV (mean ± stdev per model/chapter)

---

## Configuration

At the top of `eval_quest_generation.py`, set the following before running:

```python
MODEL_CONFIGS = [
    {"name": "Qwen3.5-122B",    "base_url": "https://edirlei.com/buas-llm-server/v1", "api_key": BUAS_LLM_KEY},
    {"name": "Qwen3.6-27B",     "base_url": "https://edirlei.com/buas-llm-server/v1", "api_key": BUAS_LLM_KEY},
    {"name": "GPT-OSS-120B",    "base_url": "https://edirlei.com/buas-llm-server/v1", "api_key": BUAS_LLM_KEY},
    {"name": "Llama3.3-70B",    "base_url": "https://edirlei.com/buas-llm-server/v1", "api_key": BUAS_LLM_KEY},
]

RUNS_PER_MODEL = 10
ROOT_DIR       = r"C:\...\LLM-Quest-RPG\Eval_Scripts\inputs"  # Update to your local path
OUTPUT_DIR     = "eval_results_buas"
```

Claude Opus 4.7 cannot be included in the same `MODEL_CONFIGS` list as the local models. Run it separately using `eval_quest_generation_Claude.py`, which has the same configuration structure but with the incompatible parameters removed. The name is "claude-opus-4-7".

---

## Running the Script

```bash
cd Eval_Scripts
python eval_quest_generation.py
```

For Claude:

```bash
python eval_quest_generation_Claude.py
```

Results are saved to the `OUTPUT_DIR` folder. Each run produces two files:

- `checkpoint_{model}_{timestamp}_run{N}.json` — per-run metrics
- `quests_{model}_{timestamp}_run{N}.json` — full generated quest plans with dialogue

At the end of all runs, two CSV files are produced:

- `eval_detail_{timestamp}.csv` — one row per model/run/chapter with all raw metric values
- `eval_summary_{timestamp}.csv` — mean and standard deviation per model/chapter across all runs

---

## Analysis Notebook

`Evaluation_Notebook_First_Version.ipynb` is used to analyse and visualise the results after running the evaluation script. Open it in Jupyter and run the cells to:

- Load the detail and summary CSVs produced by the evaluation script
- Generate the metric tables used in the paper
- Produce the NPC usage and dialogue length distribution figures
- Review per-model findings across all six metric categories

The notebook expects the results to be present in the `eval_results_buas_*` subfolders. If running a fresh evaluation, run the script first before opening the notebook.

The notebook uses hardcoded paths pointing to the specific timestamped result files from the original evaluation. If running a fresh evaluation, update the DETAIL_CSV_*, SUMMARY_CSV_*, and QUESTS_DIR_* variables at the top of the second cell to match your new output filenames.

---

## Metrics

The evaluation covers six categories:

**Structural validity** — does the output conform to the expected format and scale?
`json_parse_success`, `num_quests`, `num_steps`, `scale_mismatch`

**Action validity** — are the actions legal and correctly formed?
`invalid_actions`, `actor_not_player`, `missing_parameters`, `unknown_parameters`

**World state consistency** — do the steps respect the current state of the world?
`locked_move`, `move_noop`, `hallucinated_locations`, `hallucinated_npcs`, `hallucinated_items`

**Inventory consistency** — does the model correctly track what the player is carrying?
`pickup_no_move`, `synth_no_sample`, `repair_no_toolkit`, `repair_no_wood`, `use_cure_no_synth`

**Narrative coherence** — does the quest make sense as a story?
`quest_no_talk`, `duplicate_talk`

**Performance** — how efficiently did the model produce the output?
`generation_time_s`, `input_tokens`, `output_tokens`, `total_tokens`, `attempts`

---

## Results

Full results from the evaluation described in the paper are stored in the following subfolders:

| Folder | Model | Runs |
|---|---|---|
| `eval_results_buas_Claude` | Claude Opus 4.7 | 10 |
| `eval_results_buas_Speed_Test` | Qwen3.6-27B | 10 |
| `eval_results_buas_Three_Models` | GPT-OSS-120B, Llama-3.3-70B, Qwen3.5-122B | 10 each |

Each folder contains per-run checkpoint JSONs, per-run quest JSONs, and a detail and summary CSV.

The results were collected in 4 separate runs. The first run used Qwen3.6-27B as a single-model test to verify the pipeline but on a different and slower server. The second run evaluated GPT-OSS-120B, Llama-3.3-70B, and Qwen3.5-122B together. Qwen3.6-27B was then rerun on the correct and same server to ensure its performance metrics were comparable to the other models. Claude Opus 4.7 was evaluated in the last run due to API costs.

---

The three result folders correspond to the four separate evaluation runs. eval_results_buas_Three_Models contains the first three-model run (GPT-OSS-120B, Llama-3.3-70B, Qwen3.5-122B). eval_results_buas_Speed_Test contains the Qwen3.6-27B rerun on the correct server. eval_results_buas_Claude contains the Claude Opus 4.7 run.
## Hardware

The evaluation was run on:

- CPU: AMD EPYC 9555 64-Core Processor
- RAM: 1.5 TB
- GPU: 4 × NVIDIA RTX PRO 6000 Blackwell Server Edition

All models except Claude Opus 4.7 were hosted locally on this server. Claude Opus 4.7 was accessed via the Anthropic API routed through the same endpoint.

---

## Inputs

All input files are located in the `inputs` folder:

```
inputs/
├── Chapters/         → Chapter definitions (id, quest_type, required, scale, situation)
├── Characters/       → Character definitions (name, role, personality, goal, dialogue_style)
├── World_State/      → world_state_initial.json
└── System/           → action_library.json and world_rules.json
```

---

## Requirements

- Python 3.11+
- `openai`, `python-dotenv`
- A valid `BUAS_LLM_KEY` in a `.env` file in this folder