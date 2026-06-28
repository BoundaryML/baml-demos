"""Streamlit UI for the BAML text-to-SQL demo.

A thin front-end over the exact same pieces the CLI uses: it hands BAML's
`run_text_to_sql` two psycopg host callables (introspect, execute) and renders
the typed `WorkflowResult`. All AI + orchestration still lives in `baml_src/`.

Run:  uv run streamlit run app.py
Config comes from the environment (OPENAI_API_KEY, DATABASE_URL, MODEL) — no .env.
"""

from __future__ import annotations

import json
import os

import pandas as pd
import streamlit as st

import baml_sdk  # noqa: F401 — importing initializes the BAML runtime
from baml_sdk import present_schema, run_text_to_sql

from db import Database
from seed import seed as seed_database

DEFAULT_DB = os.environ.get("DATABASE_URL", "postgresql://postgres:postgres@127.0.0.1:54422/postgres")

EXAMPLE_QUESTIONS = [
    "Which 5 companies have the highest average employee salary?",
    "List employees who know both Python and PostgreSQL, with their company",
    "How many projects are in each status, and what is the total budget?",
    "Show the 3 most common skills among employees",
    "Top 10 highest-paid employees with their company and department",
]

st.set_page_config(page_title="Text-to-SQL · BAML", page_icon="🗄️", layout="wide")


# ── Session state ─────────────────────────────────────────────────────────────
def _ss(key, default):
    if key not in st.session_state:
        st.session_state[key] = default


_ss("db", None)
_ss("schema", None)
_ss("history", [])  # list of WorkflowResult-like dicts, newest first


def connect(url: str) -> None:
    """Open a connection and introspect once; cache the schema in session."""
    if st.session_state.db is not None:
        try:
            st.session_state.db.close()
        except Exception:
            pass
    db = Database(url)
    st.session_state.db = db
    st.session_state.schema = db.introspect()


# ── Sidebar: connection / seeding / model ─────────────────────────────────────
with st.sidebar:
    st.header("⚙️ Setup")

    has_key = bool(os.environ.get("OPENAI_API_KEY"))
    st.caption(
        ("🟢 `OPENAI_API_KEY` detected" if has_key else "🔴 `OPENAI_API_KEY` not set — export it and restart")
    )

    model = st.text_input("Model", value=os.environ.get("MODEL", "gpt-4o"), help="Any OpenAI chat model.")

    db_url = st.text_input("Database URL", value=DEFAULT_DB)

    if st.button("🔌 Connect", use_container_width=True):
        try:
            with st.spinner("Connecting and introspecting…"):
                connect(db_url)
            st.success("Connected.")
        except Exception as e:  # noqa: BLE001
            st.session_state.db = None
            st.session_state.schema = None
            st.error(f"Connection failed: {e}")

    connected = st.session_state.db is not None
    schema = st.session_state.schema

    if connected:
        n_tables = schema.total_tables() if schema else 0
        st.metric("Tables", n_tables)
        if n_tables == 0:
            st.warning("Database is empty — seed it below or point at a populated DB.")

        if st.button("🌱 Seed sample data", use_container_width=True,
                     help="(Re)create and populate the 10-table business dataset."):
            try:
                with st.spinner("Seeding sample data… (a few seconds)"):
                    result = seed_database(st.session_state.db.conn)
                    st.session_state.schema = st.session_state.db.introspect()  # refresh
                st.success(result.message)
            except Exception as e:  # noqa: BLE001
                st.error(f"Seeding failed: {e}")

    st.divider()
    st.caption("All AI + orchestration runs in BAML (`baml_src/`). Python is just psycopg I/O passed in as host callables.")


# ── Main ──────────────────────────────────────────────────────────────────────
st.title("🗄️ Text-to-SQL")
st.caption("Natural language → safe PostgreSQL `SELECT`, powered by **BAML**. Ask a question; BAML introspects the schema, generates the query, gates it to read-only, and runs it.")

if not connected:
    st.info("👈 Set a **Database URL** and click **Connect** to begin. Start a local one with `supabase start`.")
    st.stop()

if schema is not None and schema.total_tables() == 0:
    st.warning("No tables found. Use **🌱 Seed sample data** in the sidebar, or connect to a populated database.")
    st.stop()

# Schema overview
with st.expander("📚 Database schema", expanded=False):
    st.markdown(present_schema(schema))

# Question input
st.subheader("Ask a question")

_ss("question", "")
cols = st.columns(len(EXAMPLE_QUESTIONS))
for col, ex in zip(cols, EXAMPLE_QUESTIONS):
    if col.button(ex, use_container_width=True, help="Use this example"):
        st.session_state.question = ex

with st.form("ask", clear_on_submit=False):
    question = st.text_area("Question", value=st.session_state.question, height=80,
                            placeholder="e.g. Which department has the highest average salary?")
    submitted = st.form_submit_button("▶️ Generate & run", type="primary")

if submitted and question.strip():
    if not has_key:
        st.error("OPENAI_API_KEY is not set in the environment.")
        st.stop()

    os.environ["MODEL"] = model  # BAML's SqlGenerator client reads env.MODEL at call time
    db = st.session_state.db
    cached_schema = st.session_state.schema
    try:
        with st.spinner("Thinking… (introspect → generate SQL → execute)"):
            result = run_text_to_sql(
                natural_language_query=question.strip(),
                introspect=lambda: cached_schema,  # reuse the cached schema
                execute=db.execute,
            )
    except BaseException as e:  # noqa: BLE001 — BAML panics subclass BaseException
        st.error(f"Failed: {e}")
        st.stop()

    st.session_state.history.insert(0, result)


# ── Render results (newest first) ─────────────────────────────────────────────
def render_result(result, expanded: bool) -> None:
    g = result.generated
    ex = result.execution
    with st.container(border=True):
        st.markdown(f"#### ❓ {result.natural_language_query}")

        c1, c2 = st.columns([3, 1])
        with c1:
            st.code(g.sql.strip(), language="sql")
        with c2:
            st.metric("Confidence", f"{round(g.confidence * 100)}%")
            st.progress(min(max(g.confidence, 0.0), 1.0))
            if g.tables_used:
                st.caption("**Tables:** " + ", ".join(g.tables_used))

        st.markdown(f"**📖 Explanation** — {g.explanation}")
        if g.assumptions:
            with st.expander("Assumptions"):
                for a in g.assumptions:
                    st.markdown(f"- {a}")

        if not ex.success:
            st.error(f"❌ {ex.error}")
            return

        rows = json.loads(ex.data)
        st.markdown(f"**📊 {ex.row_count} row(s)**")
        if rows:
            st.dataframe(pd.DataFrame(rows), use_container_width=True, hide_index=True)
        else:
            st.caption("No rows returned.")


if st.session_state.history:
    st.subheader("Results")
    for i, result in enumerate(st.session_state.history):
        render_result(result, expanded=(i == 0))
    if st.button("Clear history"):
        st.session_state.history = []
        st.rerun()
