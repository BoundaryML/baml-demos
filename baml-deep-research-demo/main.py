"""Thin human-in-the-loop CLI driver for the BAML deep-research app.

All the AI + orchestration logic lives in BAML (baml_src/). This file only:
  1. loads env (.env), requires OPENAI_API_KEY + EXA_API_KEY,
  2. asks for a topic and calls baml_sdk.research(topic),
  3. prints a summary and asks the user to approve (the dowhile approval loop),
  4. on approval, calls baml_sdk.generate_report(data) and prints/saves the markdown.

Ports generateReportWorkflow's human-in-the-loop: research -> approval gate -> report.
"""

import os
import sys
from datetime import datetime, timezone
from pathlib import Path


def load_env(path: str = ".env") -> None:
    """Minimal .env reader (no dependency on python-dotenv)."""
    p = Path(path)
    if not p.exists():
        return
    for line in p.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        value = value.strip().strip('"').strip("'")
        os.environ.setdefault(key.strip(), value)


def require_keys() -> None:
    missing = [k for k in ("OPENAI_API_KEY", "EXA_API_KEY") if not os.environ.get(k)]
    if missing:
        print(f"Error: missing required environment variable(s): {', '.join(missing)}")
        print("Set them in a .env file (see .env.example) or your shell, then re-run.")
        sys.exit(1)


def print_summary(data) -> None:
    """Readable summary of ResearchData (ports researchWorkflow's `summary`)."""
    print("\n" + "=" * 70)
    print(f"RESEARCH SUMMARY  (phase: {data.phase})")
    print("=" * 70)
    print(f"\nQueries used ({len(data.queries)}):")
    for q in data.queries:
        print(f"  - {q}")
    print(f"\nRelevant sources ({len(data.search_results)}):")
    for r in data.search_results:
        print(f"  - {r.title or '(untitled)'} — {r.url}")
    print(f"\nKey learnings ({len(data.learnings)}):")
    for l in data.learnings:
        print(f"  - {l.learning}")
        for fq in l.follow_up_questions:
            print(f"      follow-up: {fq}")
    print("=" * 70 + "\n")


def main() -> None:
    load_env()
    require_keys()

    # Import after env is loaded; BAML's env.* reads os.environ at call time.
    import baml_sdk

    # dowhile approval loop: re-prompt + re-run research until the user approves
    # (mirrors researchWorkflow's getUserQueryStep, which re-asks each iteration).
    data = None
    while True:
        topic = input("What would you like to research? ").strip()
        if not topic:
            print("No topic provided. Exiting.")
            return

        print(f'\nResearching "{topic}" ... (this runs two phases of web search)\n')
        try:
            data = baml_sdk.research(topic)
        except Exception as e:  # noqa: BLE001 - degrade gracefully like the original
            print(f"Research failed: {e}\nPlease try again.\n")
            continue
        print_summary(data)

        answer = input("Is this research sufficient? [y/n] ").strip().lower()
        if answer.startswith("y"):
            break
        print("Re-running research ...")

    print("\nGenerating report ...\n")
    today = datetime.now(timezone.utc).isoformat()
    try:
        report = baml_sdk.generate_report(data, today)
    except Exception as e:  # noqa: BLE001 - mirror generateReportWorkflow's catch
        print(f"Report generation failed: {e}")
        return

    print(report)

    out = Path("report.md")
    out.write_text(report)
    print(f"\nReport saved to {out.resolve()}")


if __name__ == "__main__":
    main()
