# Deep Research Assistant — BAML port

A port of the [Mastra deep-research app](../mastra-deep-research) to [BAML](https://github.com/BoundaryML/baml) using the Python bridge.

The original app is a TypeScript/Mastra project built from five agents, three tools, and two workflows. This port follows the BAML philosophy — **keep AI-related things and workflow logic in BAML as much as possible** — so all of the LLM functions *and* the deterministic research orchestration live in `baml_src/`. Python is only a thin human-in-the-loop CLI driver.

## How it maps to Mastra

| Mastra piece | BAML equivalent | File |
| --- | --- | --- |
| `webSummarizationAgent` (gpt-4.1-mini) | `summarize_web()` LLM fn + `Fast` client | `search.baml`, `clients.baml` |
| `webSearchTool` (Exa search + summarize) | `exa_search()` — Exa HTTP POST + concurrent `summarize_web` | `search.baml` |
| `evaluationAgent` + `evaluateResultTool` | `evaluate_result()` LLM fn → `Evaluation` | `research.baml`, `types.baml` |
| `learningExtractionAgent` + `extractLearningsTool` | `extract_learnings()` LLM fn → `Learning` (max 1 follow-up) | `research.baml`, `types.baml` |
| `researchAgent` (tool-calling planner, gpt-4o) | `plan_research_queries()` (on the `Planner` / gpt-4o client) + `research()` orchestration | `research.baml`, `clients.baml` |
| `researchWorkflow` research step | `research()` — deterministic 2-phase orchestration → `ResearchData` | `research.baml` |
| `reportAgent` (gpt-4.1) | `generate_report()` LLM fn (+ `research_to_text()` renderer) | `report.baml` |
| `researchWorkflow` + `generateReportWorkflow` (suspend/resume, dowhile approval) | interactive front end (research → approval gate → report) | `streamlit_app.py` (web) / `main.py` (CLI) |

The Mastra `researchAgent` drove the two-phase process via free-form tool-calling. The port makes that process **deterministic BAML orchestration** instead, which is cheaper, faster, and reproducible:

- **Phase 1 (initial):** `plan_research_queries(topic)` produces the focused initial queries; each query fans out concurrently → `exa_search` → `evaluate_result` on every result → for relevant, URL-unseen results → `extract_learnings`.
- **Phase 2 (follow-up):** collect all follow-up questions from the Phase-1 learnings → search/evaluate/extract for each → **STOP** (no recursion into Phase-2 follow-ups, matching `researchAgent`'s critical "stop after Phase 2" rule).
- URL dedup (ports `evaluateResultTool`'s `existingUrls` check) is tracked in a shared `seen_urls` list across both phases.
- `spawn` / `await baml.future.all(...)` fan out the independent searches and evaluations concurrently.

### Types (port of the zod schemas)

- `SearchResult { title, url, content }`
- `Evaluation { is_relevant, reason }`
- `Learning { learning, follow_up_questions, source }`
- `ResearchData { queries, search_results, learnings, completed_queries, phase }`

## Clients

- `Fast` = `gpt-4.1-mini` — summarization (`webSummarizationAgent`).
- `Smart` = `gpt-4.1` — evaluation, learning extraction, report (the other agents).
- `Planner` = `gpt-4o` — query planning (`plan_research_queries`), matching `researchAgent`'s `openai/gpt-4o`.

All three read `env.OPENAI_API_KEY`. `exa_search` reads `env.EXA_API_KEY`.

## Robustness (ports the Mastra try/catch fallbacks)

The original degraded gracefully on transient failures; the port mirrors that:

- `exa_search` returns `[]` on a missing/invalid Exa key, a 4xx/5xx status, an outage, or a non-conforming body (via `fetch_exa_results` + `catch_all`), rather than aborting the run.
- `safe_evaluate` falls back to `{ is_relevant: false, reason: "Error in evaluation" }` and `safe_extract` to a placeholder learning on an LLM/parse error — exactly the `evaluateResultTool` / `extractLearningsTool` fallbacks.
- `research()` has a top-level `catch_all` returning empty findings (mirrors the research step's `{ error }`); `main.py` additionally wraps `research()` / `generate_report()` in `try/except`.
- Prompt inputs are capped to match the original (summarizer input ≤ 8000 chars, evaluate ≤ 500, extract ≤ 1500), and follow-ups are truncated to at most 1 per learning (Mastra's `z.array().max(1)`).

## Files

- `baml.toml` — package + Python generator config.
- `pyproject.toml` — Python project; editable-links the local `baml_core` SDK.
- `baml_src/clients.baml` — `Fast` / `Smart` LLM clients.
- `baml_src/types.baml` — `SearchResult`, `Evaluation`, `Learning`, `ResearchData`.
- `baml_src/search.baml` — `summarize_web`, `exa_search` (Exa POST + concurrent summarize).
- `baml_src/research.baml` — `evaluate_result`, `extract_learnings`, `plan_research_queries`, and the 2-phase `research()` orchestration (+ `merge_research`, `collect_follow_ups`, `research_one_query`).
- `baml_src/report.baml` — `generate_report` + `research_to_text` renderer.
- `baml_src/tests.baml` — pure (no-LLM) unit tests for the orchestration/post-processing.
- `main.py` — thin interactive HITL CLI driver.
- `streamlit_app.py` — Streamlit web UI for the same flow (research → approval gate → streamed report).
- `.env.example` — required env vars.

## Run it

> **Local SDK dependency:** `pyproject.toml` pins `baml_core` to a local editable path
> (`/Users/sam/baml/baml_language/sdks/python`) and the commands below used the local debug
> `baml-cli` at `/Users/sam/baml/baml_language/target/debug/baml-cli`. On another machine,
> repoint both to your BAML checkout (or an installed `baml`/`baml_core`) before `uv sync`.

```bash
# 1. Build the venv (editable-links the local baml_core SDK)
uv sync

# 2. Generate the Python baml_sdk from baml_src/
baml-cli generate

# 3. Provide keys
cp .env.example .env   # then fill in OPENAI_API_KEY and EXA_API_KEY

# 4a. Run the Streamlit web UI (recommended)
uv run streamlit run streamlit_app.py

# 4b. …or the interactive CLI
uv run python main.py
```

Both front ends drive the same BAML functions. They ask for a topic, run the two-phase research, show a summary, and present the approval gate (**"Is this research sufficient?"**): reject to refine the topic and re-run (the dowhile approval loop), or approve to generate the comprehensive markdown report.

- **`streamlit_app.py`** — a web UI. The report is streamed token-by-token via BAML's `generate_report_stream`, and can be downloaded as `report.md`. Keys are read from the environment, a local `.env`, or the repo-root `.envrc` automatically.
- **`main.py`** — the terminal CLI; prints the report and saves it to `report.md`.

## Development loop

```bash
baml-cli check     # compile-check all baml
baml-cli test      # run the pure (no-LLM) test blocks
baml-cli generate  # regenerate baml_sdk/ after baml changes
```

> The exact `baml-cli` invocations in this repo used the local debug binary at
> `/Users/sam/baml/baml_language/target/debug/baml-cli` with
> `--from /Users/sam/work-repos/agent-demos/baml-deep-research-demo`.

The `test` blocks call **no** LLM functions — they exercise pure BAML logic (follow-up dedup, merge, URL dedup) on literal data, so they run offline with no API keys.
