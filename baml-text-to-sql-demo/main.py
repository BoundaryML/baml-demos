"""Interactive text-to-SQL CLI — the human-in-the-loop driver.

Mirrors the five steps of the Mastra `databaseQueryWorkflow` (connect → optional
seed → introspect → generate → review/execute), but the AI + orchestration is the
single BAML call `run_text_to_sql`. Here Python only:
  - reads config from the environment / connects (psycopg),
  - optionally seeds sample data,
  - hands BAML two host callables (`db.introspect`, `db.execute`),
  - renders the typed `WorkflowResult` it gets back.
"""

from __future__ import annotations

import argparse
import json
import os
import sys

# All config (OPENAI_API_KEY, DATABASE_URL, MODEL) is read from the process
# environment — no .env loading. BAML's SqlGenerator client reads env.MODEL;
# give it a sensible default.
os.environ.setdefault("MODEL", "gpt-4o")

import baml_sdk  # noqa: E402,F401 — importing initializes the BAML runtime
from baml_sdk import run_text_to_sql  # noqa: E402

from db import Database  # noqa: E402
from seed import seed as seed_database  # noqa: E402


def _render(result) -> None:
    print("\n" + "=" * 70)
    print(f"❓ {result.natural_language_query}")
    print("=" * 70)

    g = result.generated
    print("\n🔍 Generated SQL")
    print(g.sql.strip())
    print(f"\n📖 {g.explanation}")
    print(f"🎯 Confidence: {round(g.confidence * 100)}%   Tables: {', '.join(g.tables_used) or '—'}")
    if g.assumptions:
        print("   Assumptions: " + "; ".join(g.assumptions))

    ex = result.execution
    if not ex.success:
        print(f"\n❌ {ex.error}")
        return

    rows = json.loads(ex.data)
    print(f"\n📊 {ex.row_count} row(s)")
    _print_table(rows)


def _print_table(rows: list[dict], limit: int = 25) -> None:
    if not rows:
        print("   (no rows)")
        return
    cols = list(rows[0].keys())
    widths = {c: max(len(c), *(len(str(r.get(c, ""))) for r in rows[:limit])) for c in cols}
    line = " | ".join(c.ljust(widths[c]) for c in cols)
    print("   " + line)
    print("   " + "-+-".join("-" * widths[c] for c in cols))
    for r in rows[:limit]:
        print("   " + " | ".join(str(r.get(c, "")).ljust(widths[c]) for c in cols))
    if len(rows) > limit:
        print(f"   … and {len(rows) - limit} more")


def run_one(introspect, execute, question: str) -> None:
    # The whole text-to-SQL pipeline is this single typed BAML call.
    result = run_text_to_sql(
        natural_language_query=question,
        introspect=introspect,
        execute=execute,
    )
    _render(result)


def main() -> None:
    parser = argparse.ArgumentParser(description="Natural-language → SQL over Postgres, powered by BAML.")
    parser.add_argument("--db", default=os.environ.get("DATABASE_URL"), help="PostgreSQL connection string (or set DATABASE_URL).")
    parser.add_argument("--seed", action="store_true", help="(Re)create and seed the sample business dataset, then continue.")
    parser.add_argument("--query", help="Run a single question and exit (otherwise starts an interactive REPL).")
    args = parser.parse_args()

    if not args.db:
        sys.exit("error: provide a connection string via --db or DATABASE_URL")

    db = Database(args.db)
    try:
        # Seeding never calls the LLM, so it must not require an OpenAI key.
        if args.seed:
            print(seed_database(db.conn).message)

        # Introspect once per session and reuse it (faster REPL); also lets us
        # bail clearly on an empty database instead of asking the LLM to
        # hallucinate SQL against tables that don't exist.
        schema = db.introspect()
        if schema.total_tables() == 0:
            sys.exit("error: no tables found — run with --seed or point --db at a populated database.")

        # Asking questions needs the model; only enforce the key past this point.
        if not os.environ.get("OPENAI_API_KEY"):
            sys.exit("error: OPENAI_API_KEY is not set in the environment")

        introspect = lambda: schema  # noqa: E731 — host callable returns the cached schema
        if args.query:
            run_one(introspect, db.execute, args.query)
            return

        print("\n💬 Ask a question about your data (Ctrl-D or 'exit' to quit).")
        while True:
            try:
                question = input("\n> ").strip()
            except EOFError:
                break
            if question.lower() in {"exit", "quit"}:
                break
            if question:
                run_one(introspect, db.execute, question)
    finally:
        db.close()


if __name__ == "__main__":
    main()
