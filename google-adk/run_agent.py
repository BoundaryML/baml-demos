#!/usr/bin/env python3
"""One-shot programmatic run of the expense agent (no `adk web` needed).

Prints the full loop as it happens: every tool call the Gemini agent makes,
every typed result BAML hands back, then the agent's final answer.

Usage:
    uv run python run_agent.py                                  # sample notes
    uv run python run_agent.py "dinner w/ client 92 @ nobu"     # your own

Live keys (see README): GOOGLE_API_KEY for the agent, OPENAI_API_KEY for the
BAML parse tool. Loaded from ./.env when present.
"""

import asyncio
import sys

from dotenv import load_dotenv

load_dotenv()

from google.adk.runners import InMemoryRunner
from google.genai import types

from expense_agent.agent import root_agent

SAMPLE = """\
Expenses from my SF trip, can you check them?
- ubr 23.50 to airport tue
- team dinner @ Luigi's $184 (6 ppl, closing dinner)
- hotel 2 nights 240/night
- jetbrains license renewal 149 eur
"""


async def main() -> None:
    message = sys.argv[1] if len(sys.argv) > 1 else SAMPLE

    runner = InMemoryRunner(agent=root_agent, app_name="expense-approver")
    session = await runner.session_service.create_session(
        app_name="expense-approver", user_id="demo"
    )

    print(f">>> user\n{message.rstrip()}\n")
    content = types.Content(role="user", parts=[types.Part(text=message)])

    async for event in runner.run_async(
        user_id="demo", session_id=session.id, new_message=content
    ):
        for call in event.get_function_calls():
            print(f"[tool call]   {call.name}({call.args})")
        for response in event.get_function_responses():
            print(f"[tool result] {response.name} -> {response.response}")
        if event.is_final_response() and event.content and event.content.parts:
            text = "".join(part.text or "" for part in event.content.parts)
            print(f"\n<<< {root_agent.name}\n{text}")


if __name__ == "__main__":
    asyncio.run(main())
