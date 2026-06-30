client<llm> GPTMini {
    provider: openai,
    options: {
        model: "gpt-5-mini",
    },
}

enum Tool {
    Add,
    Subtract,
    Multiply,
    Divide,
}

class CalculateResult {
    tool: Tool | null @description(
        "The tool used to calculate the result. If you know the result, leave as null.",
    ),
    a: int | null @description(
        "The left operand to pass to the tool. Leave as null when returning a known result.",
    ),
    b: int | null @description(
        "The right operand to pass to the tool. Leave as null when returning a known result.",
    ),
    result: int | null @description(
        "The result of the calculation. Iff you know the result, populate this field, otherwise leave as null.",
    ),
}

function Calculate(prompt: string) -> CalculateResult {
    client: GPTMini
    prompt: `
        Calculate the result of the following expression. Do not calculate anything without using a math tool. If you know the result, populate the result field.

        If you need a math tool, choose one tool and populate both operands a and b.

        ${prompt}

        ${ctx.output_format}
    `
}

function Agent(prompt: string) -> int {
    let result = Calculate(prompt);

    while (result.result is null) {
        match (result) {
            CalculateResult { result: let n: int } => {
                return n;
            },
            CalculateResult { tool: Tool.Add, a: let a: int, b: let b: int } => {
                return add(a, b);
            },
            CalculateResult { tool: Tool.Subtract, a: let a: int, b: let b: int } => {
                return subtract(a, b);
            },
            CalculateResult { tool: Tool.Multiply, a: let a: int, b: let b: int } => {
                return multiply(a, b);
            },
            CalculateResult { tool: Tool.Divide, a: let a: int, b: let b: int } => {
                return divide(a, b);
            },
            _ => throw "Something went wrong.",
        }
    }

    return 0;
}
