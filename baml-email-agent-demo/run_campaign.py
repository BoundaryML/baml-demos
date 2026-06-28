#!/usr/bin/env python3
"""Drive the BAML email agent from Python.

This is the thin "bridge" half of the demo: BAML owns every AI decision
(company/people research over Exa, the email-writing prompt, the model calls,
the concurrency); Python just loads contacts, builds a campaign, hands each
contact to BAML, and renders the result. The original Vercel app did the same
orchestration in `workflows/process-contact.ts`.

Usage:
    uv run python run_campaign.py --dry-run        # offline: print assembled prompts, no API calls
    uv run python run_campaign.py                  # live: research + generate (needs API keys)
    uv run python run_campaign.py --contacts example-contacts.csv --follow-ups 2

Live mode needs:
    ANTHROPIC_API_KEY   — research + email generation
    EXA_API_KEY         — company/people research (only when research is enabled)
"""

from __future__ import annotations

import argparse
import csv
import os
import sys
import textwrap

# Importing the generated package initializes the BAML runtime.
import baml_sdk
from baml_sdk import (
    Campaign,
    Contact,
    ProcessedContact,
    build_email_prompt,
    default_system_prompt,
    process_contact,
)


def load_contacts(path: str) -> list[Contact]:
    """Read the CSV (same columns as the original app) into typed Contacts."""
    with open(path, newline="") as f:
        rows = list(csv.DictReader(f))
    contacts: list[Contact] = []
    for r in rows:
        contacts.append(
            Contact(
                first_name=r["firstName"].strip(),
                last_name=(r.get("lastName") or "").strip() or None,
                email=r["email"].strip(),
                title=(r.get("title") or "").strip() or None,
                company=r["company"].strip(),
                notes=(r.get("notes") or "").strip() or None,
            )
        )
    return contacts


def render_result(pc: ProcessedContact) -> str:
    """Pretty-print one processed contact: research + generated sequence."""
    out: list[str] = []
    c = pc.contact
    out.append(f"  subject: {pc.emails.subject}")
    if pc.company_research:
        feats = ", ".join(pc.company_research.existing_ai_features) or "none found"
        out.append(f"  company: {pc.company_research.company_summary}")
        out.append(f"  existing AI features: {feats}")
    if pc.people_research:
        out.append(f"  person: {pc.people_research.title} — {pc.people_research.contact_summary}")
    for i, body in enumerate(pc.emails.bodies, start=1):
        out.append(f"  --- email {i} ---")
        out.append(textwrap.indent(body, "    "))
    return "\n".join(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contacts", default="example-contacts.csv", help="CSV of contacts to process")
    parser.add_argument("--system-prompt", default=None, help="Campaign instructions for the AI (defaults to BAML's built-in)")
    parser.add_argument("--follow-ups", type=int, default=2, help="Number of follow-up emails (0-2)")
    parser.add_argument("--no-company-research", action="store_true", help="Disable Exa company research")
    parser.add_argument("--people-research", action="store_true", help="Enable Exa people research")
    parser.add_argument("--dry-run", action="store_true", help="Print the assembled prompt only — no API calls, no keys needed")
    parser.add_argument("--limit", type=int, default=None, help="Only process the first N contacts")
    args = parser.parse_args()

    # Clamp to 0..2, matching the original's MAX_FOLLOW_UPS (lib/email/schema.ts).
    follow_ups = max(0, min(args.follow_ups, 2))
    if follow_ups != args.follow_ups:
        print(f"note: --follow-ups {args.follow_ups} clamped to {follow_ups} (valid range 0-2)", file=sys.stderr)

    # `default_system_prompt` lives in BAML — pull the default across the bridge.
    system_prompt = args.system_prompt or default_system_prompt()

    campaign = Campaign(
        name="AWS re:Invent 2025 — Booth Visitors",
        system_prompt=system_prompt,
        research_enabled=not args.no_company_research,
        people_research_enabled=args.people_research,
        number_of_follow_ups=follow_ups,
    )

    try:
        contacts = load_contacts(args.contacts)
    except OSError as e:
        print(f"error: cannot read contacts file '{args.contacts}': {e}", file=sys.stderr)
        return 1
    if args.limit is not None:
        contacts = contacts[: args.limit]

    print(f"Campaign: {campaign.name}")
    print(f"Contacts: {len(contacts)} from {args.contacts}")
    print(f"Mode: {'DRY RUN (offline)' if args.dry_run else 'LIVE'}  "
          f"company_research={campaign.research_enabled} people_research={campaign.people_research_enabled} "
          f"follow_ups={campaign.number_of_follow_ups}\n")

    if args.dry_run:
        # Offline: only the pure BAML prompt builder runs — no model, no Exa.
        for c in contacts:
            print(f"=== {c.first_name} {c.last_name or ''} <{c.email}> @ {c.company} ===")
            prompt = build_email_prompt(c, campaign, None, None)
            print(textwrap.indent(prompt, "  "))
            print()
        return 0

    # Live mode: require keys up front rather than failing mid-run.
    # (The BAML clients use the OpenAI provider — see baml_src/clients.baml.)
    missing = []
    if not os.environ.get("OPENAI_API_KEY"):
        missing.append("OPENAI_API_KEY")
    if campaign.research_enabled or campaign.people_research_enabled:
        if not os.environ.get("EXA_API_KEY"):
            missing.append("EXA_API_KEY")
    if missing:
        print(f"error: live mode needs {', '.join(missing)} in the environment.", file=sys.stderr)
        print("       (try `--dry-run` to see the assembled prompts without any keys.)", file=sys.stderr)
        return 1

    failures = 0
    for c in contacts:
        print(f"=== {c.first_name} {c.last_name or ''} <{c.email}> @ {c.company} ===")
        try:
            # All research + generation (and its concurrency) happens inside BAML.
            result = process_contact(c, campaign)
            print(render_result(result))
        except Exception as e:  # surface per-contact failures, keep going
            failures += 1
            print(f"  FAILED: {type(e).__name__}: {e}")
        print()

    if failures:
        print(f"Done with {failures}/{len(contacts)} failures.", file=sys.stderr)
        return 1
    print(f"Done. Processed {len(contacts)} contacts.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
