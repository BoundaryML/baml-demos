# BAML Email Agent Demo

A port of the [Vercel Email Agent](../vercel-email-agent)'s AI core to **[BAML](https://docs.boundaryml.com)**, driven from Python via the generated SDK (the "Python bridge").

The original is a Next.js app that, for each contact, researches their company (and optionally the person) via [Exa](https://exa.ai), then generates a personalized 3-email sequence with an LLM. All of that — the research, the prompt construction, the model calls, and the concurrency — was TypeScript spread across `lib/research/`, `lib/email/`, and a Vercel Workflow. **Here it all lives in BAML**, and Python is a thin driver.

## What moved where

| Original (TypeScript) | Here (BAML) |
|---|---|
| `lib/research/company.ts` — Exa search + Haiku summary | `baml_src/research.baml` → `research_company` |
| `lib/research/people.ts` — Exa search + Haiku verify | `baml_src/research.baml` → `research_person` |
| `lib/email/generation.ts` — prompt builder | `baml_src/email.baml` → `build_email_prompt` (+ section builders) |
| `lib/email/schema.ts` — zod output schema | `baml_src/types.baml` → `EmailSequence` (return type *is* the schema) |
| `workflows/process-contact.ts` — orchestration | `baml_src/workflow.baml` → `process_contact` |
| `Promise.all` over two Exa calls | `spawn { … }` green threads + `await` |
| `db/schema.ts` types | `baml_src/types.baml` classes |

What's intentionally **left out**: Postgres/Drizzle persistence, the Outreach CRM integration, the React UI, and durable-workflow retries. Those are app plumbing, not AI. The demo keeps the agent logic and lets Python own I/O (reading the CSV, printing results) — exactly the boundary the bridge is meant to draw.

## How the bridge works

1. `baml_src/*.baml` defines typed classes and functions, including LLM functions whose **return type is the output schema**.
2. `baml generate` (configured by `baml.toml`) emits a typed `baml_sdk/` Python package.
3. `run_campaign.py` imports `baml_sdk` and calls the functions with native Python objects — Pydantic models in, Pydantic models out:

```python
import baml_sdk
from baml_sdk import Campaign, Contact, process_contact

result = process_contact(contact, campaign)   # research + generation happen in BAML
print(result.emails.subject, result.emails.bodies)
```

## Layout

```
baml-email-agent-demo/
├── baml.toml               # package + [generator.app] → python/pydantic
├── baml_src/
│   ├── clients.baml        # OpenAI clients (gpt-4o-mini for research, gpt-4o for email)
│   ├── types.baml          # Campaign, Contact, *Research, EmailSequence, ProcessedContact
│   ├── research.baml       # Exa search (baml.http) + LLM summarize/verify, run concurrently
│   ├── email.baml          # pure prompt builders (unit-tested) + generate_emails LLM call
│   └── workflow.baml       # process_contact: research → generate
├── app.py                  # Streamlit UI over the same bridge
├── run_campaign.py         # the Python bridge / CLI driver
├── example-contacts.csv    # sample contacts (same as the original app)
└── pyproject.toml          # uv project; depends on baml_core (the runtime)
```

## Run it

### Prerequisites

```bash
# Generate the Python SDK from the BAML sources (uses the local CLI in this repo):
~/baml/baml_language/target/debug/baml-cli generate

# Create the venv and install the BAML runtime:
uv sync
```

### Offline — see the assembled prompts (no API keys)

The prompt builders are pure BAML, so you can inspect exactly what each contact's prompt looks like without calling any model:

```bash
uv run python run_campaign.py --dry-run
```

### Live — research + generate

Needs `OPENAI_API_KEY` (research + email generation) and `EXA_API_KEY` (research):

```bash
export OPENAI_API_KEY=sk-...
export EXA_API_KEY=...
uv run python run_campaign.py                 # all contacts, 2 follow-ups, company research
uv run python run_campaign.py --people-research --follow-ups 1
uv run python run_campaign.py --no-company-research --limit 2
```

### Streamlit UI

A browser UI over the same bridge — configure the campaign in the sidebar, then generate for a single contact (form) or a batch (CSV upload):

```bash
uv run streamlit run app.py
```

Keys are read from the environment, or auto-loaded from a sibling `.envrc` if present. The single-contact tab includes a "Preview assembled prompt" expander that runs offline (no API calls). Each generated email body is rendered as HTML, and the company/people research is shown in collapsible sections.

Flags: `--contacts <csv>`, `--system-prompt <text>`, `--follow-ups 0..2`, `--no-company-research`, `--people-research`, `--limit N`, `--dry-run`.

## Tests

The pure logic — prompt assembly, pluralization, optional-field handling, source rendering — is unit-tested in BAML with no model calls:

```bash
~/baml/baml_language/target/debug/baml-cli test
```

Each `test` runs offline on literal data; the LLM functions are exercised only in live runs (calling one in a `test` would make a real request). This mirrors the original repo's "test the orchestration, not the model" stance.

## Notes on the port

- **The return type is the schema.** `generate_emails` returns `EmailSequence { subject, bodies }`; `summarize_company` returns `CompanyResearch`. No separate zod/JSON-schema declaration — `${ctx.output_format}` injects it into the prompt.
- **Concurrency is green threads.** `research_company` fires its two Exa searches with `spawn { … }` and merges them with `await`, replacing the TS `Promise.all`.
- **Research degrades gracefully.** A failed/empty Exa call collapses to no sources via `catch_all`, and the company summary falls back to `"<name> is a company."` — same behavior as the original try/catch.
- **A leading `\n` inside a backtick string is trimmed** (block-string dedent), so the contact section is assembled by pushing lines and `join("\n")` rather than prefixing optional fields with `\n`. See `build_contact_section`.
