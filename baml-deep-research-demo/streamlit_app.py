"""Streamlit UI for the BAML deep-research app.

Same model as main.py — all AI + orchestration lives in BAML (baml_src/); this
file is just the front end. It mirrors generateReportWorkflow's human-in-the-loop:

    topic  ->  research()  ->  review findings  ->  approve gate  ->  generate_report()

The report is streamed token-by-token via BAML's `generate_report_stream`.

Run it:
    cd baml-deep-research-demo
    uv sync
    # OPENAI_API_KEY + EXA_API_KEY must be in the environment, a local .env,
    # or the repo-root .envrc (direnv) — this app loads all three.
    uv run streamlit run streamlit_app.py
"""

import os
from datetime import datetime, timezone
from pathlib import Path


def _load_env_files() -> None:
    """Populate os.environ from .env (KEY=VAL) and .envrc (export KEY=VAL),
    searching this dir and a few parents. Never overrides already-set vars."""
    here = Path(__file__).resolve().parent
    for d in [here, *here.parents[:3]]:
        for name in (".env", ".envrc"):
            p = d / name
            if not p.exists():
                continue
            for line in p.read_text().splitlines():
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith("export "):
                    line = line[len("export "):]
                if "=" not in line:
                    continue
                key, _, val = line.partition("=")
                os.environ.setdefault(key.strip(), val.strip().strip('"').strip("'"))


# Env must be in place before the first BAML call (env.* resolves at call time).
_load_env_files()

import streamlit as st

st.set_page_config(page_title="BAML Deep Research", page_icon="🔎", layout="centered")

REQUIRED_KEYS = ("OPENAI_API_KEY", "EXA_API_KEY")
missing = [k for k in REQUIRED_KEYS if not os.environ.get(k)]
if missing:
    st.error(
        "Missing required environment variable(s): "
        + ", ".join(missing)
        + ".\n\nSet them in a `.env` file (see `.env.example`), the repo-root "
        "`.envrc`, or your shell, then reload."
    )
    st.stop()

# Import after env is loaded; importing initializes the BAML runtime once.
import baml_sdk
from baml_sdk.baml.stream import StreamFinished

ss = st.session_state
ss.setdefault("stage", "input")   # input -> review -> report
ss.setdefault("topic", "")
ss.setdefault("data", None)
ss.setdefault("report", None)


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def reset_to_input() -> None:
    ss.stage = "input"
    ss.data = None
    ss.report = None


def render_findings(data, *, expanded: bool) -> None:
    """Render a ResearchData summary (queries / sources / learnings)."""
    box = st.expander("🔍 Research findings", expanded=expanded)
    with box:
        st.caption(
            f"Phase: **{data.phase}** · {len(data.queries)} queries · "
            f"{len(data.search_results)} sources · {len(data.learnings)} learnings"
        )
        st.markdown("**Queries**")
        for q in data.queries:
            st.markdown(f"- {q}")
        st.markdown("**Sources**")
        if data.search_results:
            for r in data.search_results:
                st.markdown(f"- [{r.title or r.url}]({r.url})")
        else:
            st.markdown("_none_")
        st.markdown("**Key learnings**")
        for learning in data.learnings:
            st.markdown(f"- {learning.learning}")
            for fq in learning.follow_up_questions:
                st.caption(f"↳ follow-up: {fq}")


def stream_report(data):
    """Adapt BAML's accumulated stream partials into deltas for st.write_stream."""
    stream = baml_sdk.generate_report_stream(data, _now_iso())
    prev = ""
    while True:
        v = stream.next()
        if isinstance(v, StreamFinished):
            break
        if v and v != prev:
            yield v[len(prev):] if v.startswith(prev) else v
            prev = v


# ── Header ──────────────────────────────────────────────────────────────────
st.title("🔎 BAML Deep Research")
st.caption(
    "A human-in-the-loop research assistant. Planning, web search (Exa), "
    "evaluation, learning extraction, the two-phase orchestration, and the "
    "report all run as BAML functions — this page is only the front end."
)

with st.sidebar:
    st.header("About")
    st.markdown(
        "- **Planner** · `gpt-4o`\n"
        "- **Summarize / Fast** · `gpt-4.1-mini`\n"
        "- **Evaluate / Extract / Report** · `gpt-4.1`\n"
        "- **Web search** · Exa\n\n"
        "Two phases: initial queries → follow-up questions from the first round "
        "of learnings → **stop**."
    )
    if st.button("↺ Start over"):
        reset_to_input()
        ss.topic = ""
        st.rerun()

# ── Stage: input ────────────────────────────────────────────────────────────
if ss.stage == "input":
    topic = st.text_input(
        "Research topic",
        value=ss.topic,
        placeholder="e.g. impact of green hydrogen on steel manufacturing",
    )
    if st.button("Run research", type="primary", disabled=not topic.strip()):
        ss.topic = topic.strip()
        with st.status(
            f'Researching "{ss.topic}" — two phases of web search…', expanded=True
        ) as status:
            st.write("Planning queries → searching → evaluating → extracting learnings.")
            st.write("This makes many LLM + search calls and can take ~30–60s.")
            try:
                ss.data = baml_sdk.research(ss.topic)
            except Exception as e:  # noqa: BLE001 - surface, don't crash the page
                status.update(label="Research failed", state="error")
                st.exception(e)
                st.stop()
            status.update(label="Research complete", state="complete")
        ss.stage = "review"
        ss.report = None
        st.rerun()

# ── Stage: review (the approval gate) ───────────────────────────────────────
elif ss.stage == "review":
    st.subheader(f'Findings for "{ss.topic}"')
    render_findings(ss.data, expanded=True)
    if not ss.data.search_results:
        st.warning("No relevant sources were found — consider refining the topic.")
    st.markdown("**Is this research sufficient?**")
    col1, col2 = st.columns(2)
    if col1.button("✅ Approve & generate report", type="primary"):
        ss.stage = "report"
        st.rerun()
    if col2.button("🔄 New topic / re-run"):
        reset_to_input()
        st.rerun()

# ── Stage: report ───────────────────────────────────────────────────────────
elif ss.stage == "report":
    st.subheader(f'Report — "{ss.topic}"')
    render_findings(ss.data, expanded=False)
    if ss.report is None:
        try:
            ss.report = st.write_stream(stream_report(ss.data))
        except Exception as e:  # noqa: BLE001
            st.exception(e)
            st.stop()
    else:
        st.markdown(ss.report)
    st.download_button(
        "⬇️ Download report.md",
        ss.report or "",
        file_name="report.md",
        mime="text/markdown",
    )
    if st.button("🔄 New topic"):
        reset_to_input()
        st.rerun()
