"""Streamlit UI for the BAML email agent.

Same bridge as run_campaign.py — BAML owns the research + generation; this just
drives it interactively. Run with:

    uv run streamlit run app.py

API keys (OPENAI_API_KEY, EXA_API_KEY) are read from the environment, or loaded
from a sibling `.envrc` if present.
"""

from __future__ import annotations

import csv
import io
import os
from pathlib import Path


def _load_envrc() -> None:
    """Best-effort load of KEY=VALUE lines from local/parent .envrc files."""
    for p in (Path(__file__).parent / ".envrc", Path(__file__).parent.parent / ".envrc"):
        if not p.exists():
            continue
        for raw in p.read_text().splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[len("export "):].strip()
            if "=" not in line:
                continue
            key, val = line.split("=", 1)
            os.environ.setdefault(key.strip(), val.strip().strip('"').strip("'"))


_load_envrc()

import streamlit as st  # noqa: E402

# Importing the generated package initializes the BAML runtime.
import baml_sdk  # noqa: E402,F401
from baml_sdk import (  # noqa: E402
    Campaign,
    Contact,
    ProcessedContact,
    build_email_prompt,
    default_system_prompt,
    process_contact,
)

st.set_page_config(page_title="BAML Email Agent", page_icon="✉️", layout="wide")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def render_emails(pc: ProcessedContact) -> None:
    """Show research context + the generated email sequence."""
    if pc.company_research:
        with st.expander("🏢 Company research", expanded=False):
            st.write(pc.company_research.company_summary)
            feats = pc.company_research.existing_ai_features
            st.caption("Existing AI features: " + (", ".join(feats) if feats else "none found"))
    if pc.people_research:
        with st.expander("👤 People research", expanded=False):
            st.write(f"**{pc.people_research.title}** — {pc.people_research.contact_summary}")
            if pc.people_research.recent_activity:
                st.caption("Recent activity:")
                for a in pc.people_research.recent_activity:
                    st.caption(f"• {a}")

    st.markdown(f"#### Subject: {pc.emails.subject}")
    for i, body in enumerate(pc.emails.bodies, start=1):
        st.markdown(f"**Email {i}**")
        st.markdown(
            f"<div style='border-left:3px solid #ddd;padding-left:12px;margin-bottom:8px'>{body}</div>",
            unsafe_allow_html=True,
        )


def keys_present() -> tuple[bool, bool]:
    return bool(os.environ.get("OPENAI_API_KEY")), bool(os.environ.get("EXA_API_KEY"))


# ---------------------------------------------------------------------------
# Sidebar — campaign configuration
# ---------------------------------------------------------------------------

st.sidebar.header("Campaign")

has_openai, has_exa = keys_present()
st.sidebar.markdown(
    f"**Keys** &nbsp; OpenAI {'✅' if has_openai else '❌'} &nbsp; Exa {'✅' if has_exa else '❌'}"
)
if not has_openai:
    st.sidebar.warning("OPENAI_API_KEY missing — set it (or add it to .envrc) to generate.")

campaign_name = st.sidebar.text_input("Name", "AWS re:Invent 2025 — Booth Visitors")
research_enabled = st.sidebar.toggle("Company research (Exa)", value=True)
people_research_enabled = st.sidebar.toggle("People research (Exa)", value=False)
follow_ups = st.sidebar.slider("Follow-up emails", 0, 2, 2)

with st.sidebar.expander("System prompt", expanded=False):
    system_prompt = st.text_area(
        "Instructions for the AI",
        value=default_system_prompt(),
        height=300,
        label_visibility="collapsed",
    )


def build_campaign() -> Campaign:
    return Campaign(
        name=campaign_name,
        system_prompt=system_prompt,
        research_enabled=research_enabled,
        people_research_enabled=people_research_enabled,
        number_of_follow_ups=follow_ups,
    )


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

st.title("✉️ BAML Email Agent")
st.caption(
    "Research a contact's company (and optionally the person) via Exa, then generate a "
    "personalized email sequence — all orchestrated in BAML, driven from this Python UI."
)

tab_single, tab_batch = st.tabs(["Single contact", "Batch (CSV)"])

# --- Single contact -------------------------------------------------------
with tab_single:
    with st.form("contact_form"):
        c1, c2 = st.columns(2)
        first_name = c1.text_input("First name", "Sarah")
        last_name = c2.text_input("Last name", "Chen")
        email = c1.text_input("Email", "sarah.chen@acmecorp.io")
        company = c2.text_input("Company", "Acme Corp")
        title = c1.text_input("Title", "VP of Engineering")
        notes = c2.text_input("Notes", "Met at AWS re:Invent booth — interested in our AI features")
        submitted = st.form_submit_button("Generate emails", type="primary")

    contact = Contact(
        first_name=first_name,
        last_name=last_name or None,
        email=email,
        title=title or None,
        company=company,
        notes=notes or None,
    )

    with st.expander("🔍 Preview assembled prompt (offline, no API calls)"):
        st.code(build_email_prompt(contact, build_campaign(), None, None), language="markdown")

    if submitted:
        if not has_openai:
            st.error("OPENAI_API_KEY is required to generate emails.")
        elif (research_enabled or people_research_enabled) and not has_exa:
            st.error("EXA_API_KEY is required when research is enabled.")
        else:
            with st.spinner("Researching and generating…"):
                try:
                    result = process_contact(contact, build_campaign())
                except Exception as e:  # noqa: BLE001 — surface any engine/API error
                    st.error(f"{type(e).__name__}: {e}")
                else:
                    render_emails(result)

# --- Batch ----------------------------------------------------------------
with tab_batch:
    st.write("Upload a CSV with columns: `email, firstName, lastName, company, title, notes`.")
    uploaded = st.file_uploader("Contacts CSV", type="csv")
    if uploaded is not None:
        rows = list(csv.DictReader(io.StringIO(uploaded.getvalue().decode("utf-8"))))
        st.dataframe(rows, use_container_width=True)

        if st.button(f"Process {len(rows)} contacts", type="primary", disabled=not has_openai):
            campaign = build_campaign()
            progress = st.progress(0.0)
            for idx, r in enumerate(rows):
                contact = Contact(
                    first_name=(r.get("firstName") or "").strip(),
                    last_name=(r.get("lastName") or "").strip() or None,
                    email=(r.get("email") or "").strip(),
                    title=(r.get("title") or "").strip() or None,
                    company=(r.get("company") or "").strip(),
                    notes=(r.get("notes") or "").strip() or None,
                )
                label = f"{contact.first_name} {contact.last_name or ''} @ {contact.company}".strip()
                with st.expander(label, expanded=False):
                    try:
                        result = process_contact(contact, campaign)
                    except Exception as e:  # noqa: BLE001
                        st.error(f"{type(e).__name__}: {e}")
                    else:
                        render_emails(result)
                progress.progress((idx + 1) / len(rows))
