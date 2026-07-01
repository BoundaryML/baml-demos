// Shared types for the expense tools. `Expense`'s fields double as the LLM
// output schema for `parse_expense` — the return type *is* the contract.

enum Category {
    Travel,
    Meals,
    Lodging,
    Equipment,
    Software,
    Other,
}

class Expense {
    merchant: string @description("Normalized merchant/vendor name, e.g. 'Uber' not 'ubr'"),
    amount: float @description("Total amount as written, in the note's currency"),
    currency: string @description("ISO 4217 code; assume USD when the note gives none"),
    category: Category,
    expense_date: string? @description(
        "ISO date if the note names one, otherwise the raw hint ('tue', 'last week') or null",
    ),
    notes: string? @description("Anything a reviewer would want: attendee count, purpose, etc."),
}

class PolicyDecision {
    status: "approved" | "needs_receipt" | "needs_approval" | "rejected",
    // Per-category limit in USD that was applied.
    limit: float,
    // How far over the limit, 0.0 when within it.
    over_by: float,
    reasons: string[],
}
