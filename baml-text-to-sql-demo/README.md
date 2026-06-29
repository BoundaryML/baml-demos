# Text-to-SQL, in BAML

Natural-language questions → safe PostgreSQL `SELECT`s, with live schema introspection and AI query generation. This is the [Mastra text-to-SQL template](../mastra-text-to-sql) ported to [BAML](https://github.com/BoundaryML/baml) using the **Python bridge**.

The point of the port: in the Mastra version the AI logic, the typed schemas (Zod), the prompt, and the orchestration are all spread across TypeScript tool/agent/workflow files. Here, **all of that lives in `baml_src/` as typed BAML**, and Python shrinks to a thin psycopg I/O layer that BAML calls back into.

## Architecture: BAML owns the brain, Python owns the I/O

```
            ┌─────────────────────── baml_src/ (BAML) ───────────────────────┐
            │  run_text_to_sql(question, introspect, execute)                 │
            │     1. schema   = introspect()         ← host callable (Python) │
            │     2. present_schema(schema)          ← pure BAML, logged       │
            │     3. generated = GenerateSQL(...)    ← the one LLM call        │
            │     4. is_select_query(generated.sql)  ← pure BAML safety gate   │
            │     5. execute(generated.sql)          ← host callable (Python)  │
            └─────────────────────────────────────────────────────────────────┘
                          ▲ introspect()                  ▲ execute(sql)
                          │ returns DatabaseSchema         │ returns ExecutionResult
            ┌─────────────┴────────────────────────────────┴──────────────────┐
            │  db.py / seed.py (Python)  — psycopg, the only code touching PG  │
            └──────────────────────────────────────────────────────────────────┘
```

**Host callables** are the key mechanism. BAML's `run_text_to_sql` declares two function-typed parameters:

```baml
function run_text_to_sql(
    natural_language_query: string,
    introspect: () -> DatabaseSchema,
    execute: (string) -> ExecutionResult,
) -> WorkflowResult { ... }
```

Python passes ordinary closures for those; BAML invokes them mid-workflow and gets back typed values. So orchestration and AI stay in BAML, while the database connection (and the secrets in the connection string) never leave Python.

The same BAML `class` definitions are simultaneously:
- the **LLM's structured-output schema** (`GeneratedSQL` is the return type of `GenerateSQL` — no Zod, no `generateObject`),
- the **host-callable contract** the Python bridge fills in (`DatabaseSchema`, `ExecutionResult`),
- the **Pydantic models** Python imports from the generated `baml_sdk`.

One definition, typed end to end.

## How the Mastra pieces map

| Mastra (TypeScript) | Here (BAML + Python) |
|---|---|
| `sql-generation-tool.ts` (`generateObject` + Zod) | `GenerateSQL` LLM function in `generate_sql.baml`; schema is the return type |
| `createSchemaDescription` / `createSchemaPresentation` | pure functions `schema_to_description` / `present_schema` in `schema_format.baml` |
| `database-introspection-tool.ts` | `Database.introspect()` host callable in `db.py` |
| `sql-execution-tool.ts` (+ SELECT-only guard) | `Database.execute()` + `is_select_query` BAML gate |
| `database-seeding-tool.ts` | `seed.py` |
| `database-query-workflow.ts` (5 `createStep`s) | one BAML `run_text_to_sql` + the CLI driver in `main.py` |
| `sql-agent.ts` instructions | the prompt in `GenerateSQL` |
| Zod schemas | BAML `class`es in `types.baml` |

## Setup

Requires Python 3.10+, [uv](https://docs.astral.sh/uv/), the [Supabase CLI](https://supabase.com/docs/guides/cli) (with Docker running), the [Infisical CLI](https://infisical.com/docs/cli/overview), and the BAML CLI.

```bash
cd baml-text-to-sql-demo

# Generate the typed Python SDK from baml_src/ (creates ./baml_sdk).
baml generate --from baml_src

uv sync                       # installs baml_core, psycopg2-binary, pydantic
```

### 1. Start a local Postgres with Supabase

This project ships a [Supabase](https://supabase.com/docs/guides/cli/local-development) config for a one-command local Postgres (needs Docker running):

```bash
supabase start               # boots local Postgres in Docker (first run pulls images)
```

It serves Postgres at `postgresql://postgres:postgres@127.0.0.1:54422/postgres`. The db port is remapped to **54422** (`supabase/config.toml`) so it won't collide with any other local Supabase instance. Check status with `supabase status`, and run `supabase stop` when you're done. Any PostgreSQL URL works too — just point `DATABASE_URL`/`--db` at it.

### 2. Secrets, via Infisical

Config comes entirely from the environment (no `.env` loading). `OPENAI_API_KEY` is pulled from [Infisical](https://infisical.com/docs/cli/overview) — `.infisical.json` pins the workspace, so `infisical run -- <cmd>` injects the secrets before the process starts. Log in once with `infisical login`.

```bash
export DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:54422/postgres
# export MODEL=gpt-4o          # optional, defaults to gpt-4o
```

`DATABASE_URL` points at the local Supabase from step 1 (or any Postgres). `OPENAI_API_KEY` (and any other secrets) arrive via Infisical at run time — see [Run](#run).

> The BAML CLI used during development is the local toolchain binary
> (`~/baml/baml_language/target/debug/baml-cli generate --from baml_src`).
> `pyproject.toml` installs `baml_core` editable from that same checkout — point
> both at your release once BAML is published.

## Run

### Streamlit UI

```bash
# Infisical injects OPENAI_API_KEY from the pinned workspace, then runs Streamlit:
infisical run --projectId bdd280e2-259c-4750-9b16-a8597a67214c -- uv run streamlit run app.py
```

`.infisical.json` already pins this `projectId`, so `infisical run -- uv run streamlit run app.py` works too. (Without Infisical, just `export OPENAI_API_KEY=sk-...` and run `uv run streamlit run app.py` directly.)

A browser app: connect to a database in the sidebar, **🌱 Seed sample data** if it's empty, then ask questions in natural language. Each answer shows the generated SQL, a confidence meter, the tables used, assumptions, and the result table — all from the one `run_text_to_sql` BAML call. Pick the model in the sidebar. `OPENAI_API_KEY` is read from the environment.

### CLI

```bash
# Seed the sample business dataset (10 related tables) and start the REPL:
uv run python main.py --seed

# One-shot question:
uv run python main.py --query "Show me the top 5 highest-paid employees with their company and department"
```

Example questions the seeded dataset supports:
- "Which company has the highest average salary?"
- "List employees who know both Python and PostgreSQL"
- "How many active projects does each company have, by status?"
- "Show the 10 most populous departments by headcount"

Introspection is scoped to one schema (default `public`, override with `DB_SCHEMA`) so the LLM prompt stays focused on your tables rather than a managed Postgres's internal `auth`/`storage`/`realtime` schemas.

Every generated query is **read-only** — `is_select_query` (BAML) and a second check in `db.py` both refuse anything that isn't a `SELECT` or a leading `WITH … SELECT` CTE.

> The Mastra **workflow** had a human-in-the-loop "review/modify the SQL before running" suspend step. This port follows the Mastra **agent's** semantics instead (`sql-agent.ts`: *"Do NOT ask for approval to execute SELECT queries"*) and auto-executes the generated read-only query. Add an approval prompt in `main.py` before `db.execute` if you want the review gate back.

## Develop the BAML

```bash
baml check  --from baml_src     # type-check
baml test   --from baml_src     # run the offline tests (pure logic, no model/DB)
baml fmt    baml_src/*.baml      # format
baml generate --from baml_src    # regenerate ./baml_sdk after edits
```

The `test` blocks in `workflow.baml` exercise the pure logic — the SELECT gate and both schema formatters — on literal data, with **no** model call or database, exactly where the offline/online line should sit.

## Files

```
baml_src/
  baml.toml          # package + [generator.app] → emits ../baml_sdk (python/pydantic)
  types.baml         # all data classes (introspection, LLM output, results)
  schema_format.baml # pure schema → text / markdown
  generate_sql.baml  # SqlGenerator client + GenerateSQL LLM fn + is_select_query
  workflow.baml      # run_text_to_sql orchestration + offline tests
db.py                # psycopg introspect()/execute() host callables
seed.py              # sample business dataset
main.py              # CLI: connect → optional seed → REPL driving run_text_to_sql
app.py               # Streamlit UI over the same run_text_to_sql call
baml_sdk/            # generated (gitignored) — `baml generate` to recreate
```
