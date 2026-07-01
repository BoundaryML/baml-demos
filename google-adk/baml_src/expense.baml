// The LLM tool: turn one messy expense note into a typed Expense.
// BAML derives the output schema from the return type via ctx.output_format,
// validates the model's reply against it, and re-prompts on malformed JSON —
// the ADK agent always receives a well-formed record.

function parse_expense(text: string) -> Expense {
    client: ExpenseModel
    prompt: #"
        Extract exactly one structured expense record from this raw expense
        note, written by an employee in a hurry:

        {{ text }}

        Expand abbreviations ("ubr" -> "Uber"), pick the closest category,
        and keep anything else a reviewer would care about in notes.

        {{ ctx.output_format }}
    "#
}
