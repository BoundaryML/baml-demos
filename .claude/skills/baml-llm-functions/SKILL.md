---
name: baml-llm-functions
description: Use when defining or editing a BAML LLM function — any `function X(...) -> T { client: ...  prompt: #"..."# }` declaration. Covers the `client<llm>` block (UpperCamelCase) with `provider` + `options`, the inline `client:` (colon) binding in the function body, the `client: "provider/model"` shorthand, Jinja prompts with `{{ ctx.output_format }}`, and structured output via the return type. Prerequisite: baml-core.
---

# baml-llm-functions

Load this when the task involves a BAML function that calls an LLM. The function takes typed inputs, declares a `client:`, writes a Jinja `prompt`, and returns a typed value. BAML uses the return type to drive parsing — let it do the work.

## 1. Anatomy of an LLM function

```baml
client<llm> FastOpenAI {
  provider openai
  options {
    model "gpt-4o-mini"
    api_key env.OPENAI_API_KEY
  }
}

class Email { id: string, from: string, subject: string, body: string, }

class Intent {
  kind: "billing" | "support" | "sales" | "spam" | "other",
  confidence: float,
  rationale: string,
}

function classify_email(email: Email) -> Intent {
  client: FastOpenAI
  prompt: #"
    Classify the user's email.

    From: {{ email.from }}
    Subject: {{ email.subject }}
    Body:
    {{ email.body }}

    {{ ctx.output_format }}
  "#
}
```

Three pieces:

1. **`client<llm> Name { provider X  options { ... } }`** — declares a reusable LLM client. **`UpperCamelCase`** name (e.g. `FastOpenAI`, `Sonnet`).
2. **A return type** — usually a `class`, enum, or literal union. BAML uses it to validate the response.
3. **Function body** with `client:` and `prompt:` — **both take a colon**, each on its own line. **You may still see the bare forms `client FastOpenAI` / `prompt #"..."#` in old examples; `baml fmt` normalizes to the colon form, so emit `client:` / `prompt:`.**

## 2. `client<llm>` declarations

Inside `options { ... }`: **no colons, no commas** between key/value pairs.

```baml
client<llm> FastOpenAI {
  provider openai
  options {
    model "gpt-4o-mini"
    api_key env.OPENAI_API_KEY
    temperature 0.2
    max_tokens 2000
  }
}

client<llm> Sonnet {
  provider anthropic
  options {
    model "claude-sonnet-4-6"
    api_key env.ANTHROPIC_API_KEY
    max_tokens 4096
  }
}

client<llm> LocalLlama {
  provider ollama
  options {
    model "llama3.1"
    base_url "http://localhost:11434"
  }
}
```

- `env.VAR_NAME` resolves at runtime. Don't hardcode keys.
- Provider options differ — Anthropic typically requires `max_tokens`. Inspect working clients or provider docs.
- The `options` dictionary supports nested blocks, arrays, and mixed types.

## 3. Client shorthand

For small functions, demos, and tests, skip the `client<llm>` block and use a `provider/model` string with standard env-based auth:

```baml
function classify_email_quick(email: Email) -> Intent {
  client: "openai/gpt-4o-mini"
  prompt: #"
    Classify the user's email.
    From: {{ email.from }}
    Subject: {{ email.subject }}
    Body: {{ email.body }}
    {{ ctx.output_format }}
  "#
}
```

Prefer a named `client<llm>` when you need custom options, retries, fallbacks, or non-default credentials.

## 4. Jinja prompts

Prompts use BAML block strings (`#"..."#`) with Jinja templates:

```baml
function summarize_tickets(tickets: Ticket[]) -> string {
  client: FastOpenAI
  prompt: #"
    Summarize these tickets.

    {% for t in tickets %}
    - {{ t.id }}: {{ t.title }} ({{ t.priority }})
    {% endfor %}

    {{ ctx.output_format }}
  "#
}
```

Rules:

- `#"..."#` delimits multi-line prompts — no escape interpretation.
- `{{ value }}` inserts BAML variables, fields, simple expressions.
- `{% if cond %}...{% endif %}`, `{% for item in items %}...{% endfor %}` for control flow.
- `{# comment #}` for prompt-local comments.
- **`{{ ctx.output_format }}` whenever the return type is structured or constrained.** It injects the schema/instructions BAML needs for reliable parsing.
- Don't paste JSON schemas manually unless intentionally overriding the generated output format.
- Put token-preservation rules (`{name}`, `(HOLD)`, IDs, markup that must survive byte-identically) in natural language near the relevant input.

## 5. Structured output via the return type

```baml
class Decision {
  action: "approve" | "deny" | "review",
  reason: string,
  follow_ups: string[],
  metadata: map<string, string>?,
}

function decide(case: string) -> Decision {
  client: FastOpenAI
  prompt: #"
    Review the case and return a decision.
    Case: {{ case }}
    {{ ctx.output_format }}
  "#
}
```

- Prefer classes, enums, and literal unions over free-form JSON.
- Optional fields (`T?`) are good for discriminated outputs where a fixed object is easier for the model than a wide union — but only `T?` when the LLM legitimately may omit the field.
- BAML re-prompts on malformed JSON up to its configured retry budget. Over-eager optional fields defeat validation.

## 6. Calling from host code

After `baml generate`, the function appears in the generated `baml_sdk` Python client (see `baml-bridges` for details):

```python
from baml_sdk.sync_client import b

intent = b.classify_email(email)
print(intent.kind, intent.confidence)
```

The function name in Python matches the BAML name (`classify_email`, snake_case).

## 7. Common pitfalls

- **Bare `client X` instead of `client: X`** — the colon form is the new style. The bare form may still parse but is deprecated for new code.
- **Forgetting `{{ ctx.output_format }}`** — structured outputs need it to inject the schema instructions. Without it, the model has no idea what shape to return.
- **CamelCase function names** — user-defined functions use `snake_case`. `client<llm>` declarations use `UpperCamelCase`.
- **Comma-separated `options`** — `options { model "x", api_key "y" }` will not parse. Whitespace between pairs, no commas.
- **Hardcoded API keys** — use `env.OPENAI_API_KEY`, `env.ANTHROPIC_API_KEY`, etc.
- **Forgetting `baml generate`** — schema changes don't reach host code until regenerated. See `baml-bridges`.
- **Pure-compute function with `client: + prompt`** — if you don't need an LLM, drop them. The function becomes a normal typed function with no API call.
- **Standard `"..."` instead of `#"..."#`** — standard strings interpret escapes and break multi-line prompts.
