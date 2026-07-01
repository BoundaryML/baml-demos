// The deterministic tool: reimbursement policy as ordinary typed BAML.
// No LLM anywhere in this file — the ADK agent is instructed to call this
// instead of guessing limits from its weights, so decisions are exact,
// auditable, and testable offline (see policy_test.baml).

function category_limit(category: Category) -> float {
    match (category) {
        Category.Travel => 500.0,
        Category.Meals => 75.0,
        Category.Lodging => 300.0,
        Category.Equipment => 1000.0,
        Category.Software => 200.0,
        Category.Other => 50.0,
    }
}

function check_policy(amount: float, currency: string, category: Category) -> PolicyDecision {
    let limit = category_limit(category);

    if (amount <= 0.0) {
        return PolicyDecision {
            status: "rejected",
            limit: limit,
            over_by: 0.0,
            reasons: ["amount must be a positive number"],
        };
    };

    // Anything that needs a human: non-USD spend or blowing the category limit.
    let approval_reasons: string[] = [];
    let over_by = 0.0;

    if (currency.to_upper_case() != "USD") {
        approval_reasons.push("non-USD expense (" + currency + ") needs manual review");
    };

    if (amount > limit) {
        over_by = amount - limit;
        approval_reasons.push("exceeds the " + limit.to_string() + " USD category limit");
    };

    if (approval_reasons.length() > 0) {
        return PolicyDecision {
            status: "needs_approval",
            limit: limit,
            over_by: over_by,
            reasons: approval_reasons,
        };
    };

    if (amount > 25.0) {
        return PolicyDecision {
            status: "needs_receipt",
            limit: limit,
            over_by: 0.0,
            reasons: ["amounts over 25 USD need an attached receipt"],
        };
    };

    PolicyDecision { status: "approved", limit: limit, over_by: 0.0, reasons: ["within policy"] }
}
