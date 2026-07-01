"""Google ADK agent whose tools are BAML functions.

The agent (Gemini) owns the conversation and decides *when* to call tools;
BAML owns *what the tools do*: `parse_expense` is a typed LLM extraction
function, `check_policy` is deterministic typed policy logic. Both arrive
here through the generated `baml_sdk` package (`baml generate`), so the
tool wrappers below are one line of logic each: call BAML, dump the
Pydantic model to a dict for the ADK.
"""

import sys
from pathlib import Path

# `adk run` / `adk web` import this package with the demo root on sys.path,
# which is also where `baml generate` emits `baml_sdk/`. Pin the path so the
# import also works when this module is loaded from another directory.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import baml_sdk
from google.adk.agents import Agent


def parse_expense(text: str) -> dict:
    """Turn one raw expense note into a structured expense record.

    Args:
        text: A single expense note exactly as the employee wrote it,
            e.g. "ubr 23.50 to airport tue".

    Returns:
        The structured record: merchant, amount, currency, category
        (Travel | Meals | Lodging | Equipment | Software | Other),
        expense_date, and notes.
    """
    expense = baml_sdk.parse_expense(text)
    return expense.model_dump(mode="json")


def check_expense_policy(amount: float, currency: str, category: str) -> dict:
    """Check one parsed expense against the company reimbursement policy.

    Args:
        amount: Total amount of the expense.
        currency: ISO 4217 code, e.g. "USD".
        category: One of Travel, Meals, Lodging, Equipment, Software, Other.

    Returns:
        The decision: status (approved | needs_receipt | needs_approval |
        rejected), the USD limit that was applied, how far over it the
        expense is, and the reasons.
    """
    try:
        parsed_category = baml_sdk.Category(category)
    except ValueError:
        return {
            "error": f"unknown category {category!r}",
            "valid_categories": [c.value for c in baml_sdk.Category],
        }
    decision = baml_sdk.check_policy(amount, currency, parsed_category)
    return decision.model_dump(mode="json")


root_agent = Agent(
    name="expense_approver",
    model="gemini-2.5-flash",
    description=(
        "Turns messy expense notes into structured records and checks them "
        "against company reimbursement policy."
    ),
    instruction="""\
You review employee expense notes.

For every expense line the user gives you:
1. Call parse_expense with that single line to get a structured record.
2. Call check_expense_policy with the parsed amount, currency, and category.

Never guess amounts, categories, or policy outcomes yourself — the tools are
the source of truth. Once you have a decision for every line, reply with a
short summary table (merchant, amount, category, status) plus one sentence
per non-approved expense telling the employee what to do next.
""",
    tools=[parse_expense, check_expense_policy],
)
