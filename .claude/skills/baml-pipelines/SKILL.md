---
name: baml-pipelines
description: Use when composing multiple BAML functions into a typed pipeline — `let stage1 = ...; let stage2 = ...; Result { ... }`. Covers function-to-function composition with typed values flowing between stages, dispatch via `match` on enums / literal unions / `let <name>: <Type> =>` bindings, error propagation with `throws T` / `catch (e) { T => ... }` type-only arms, and fan-out patterns (sequential in BAML, parallel via host). Prerequisite: baml-core. Often paired with baml-llm-functions.
---

# baml-pipelines

Load this when the task chains multiple BAML functions. Composition stays in BAML so the workflow is typed end-to-end and testable without host code.

For a single-function task, you don't need this skill.

## 1. Typed pipeline pattern

```baml
class TriageResult {
  email: Email,
  intent: Intent,
  draft: ReplyDraft,
  score: int,
}

function judge_draft(email: Email, draft: ReplyDraft) -> int {
  client: FastOpenAI
  prompt: #"
    Score this reply from 1 to 5.
    Email:
    {{ email.body }}

    Reply:
    {{ draft.body }}

    {{ ctx.output_format }}
  "#
}

function triage_one(email: Email) -> TriageResult {
  let intent = classify_email(email);
  let draft = draft_reply(email, intent);
  let score = judge_draft(email, draft);

  TriageResult {
    email: email,
    intent: intent,
    draft: draft,
    score: score,
  }
}

function triage_batch(raw_json: string) -> TriageResult[] {
  let emails = load_emails(raw_json);
  let results: TriageResult[] = [];

  for (let email in emails) {
    results.push(triage_one(email));
  }

  results
}
```

This shape works well in real agent runs: typed load at the boundary, small LLM stages, pure orchestration, typed results.

Things to notice:
- The composing function (`triage_one`, `triage_batch`) has no `client:` directive — it's not itself an LLM call.
- Types flow through. The compiler enforces that each stage's output type matches the next stage's input.
- Each `let` is a stage you can inspect, test, and rewire.

## 2. Pass typed values, not stringified JSON

```baml
// Good — typed
class ParsedTicket { subject: string, body: string, priority: int, }
class Routed       { ticket: ParsedTicket, queue: string, }

function parse_ticket(raw: string) -> ParsedTicket {
  client: "openai/gpt-4o-mini"
  prompt: #"parse: {{ raw }}  {{ ctx.output_format }}"#
}

function route_ticket(t: ParsedTicket) -> Routed {
  client: "openai/gpt-4o-mini"
  prompt: #"route: {{ t }}  {{ ctx.output_format }}"#
}

function handle(raw: string) -> Routed {
  route_ticket(parse_ticket(raw))
}
```

Keep `client:` and `prompt: #"..."#` on their own lines — the parser rejects one-liner LLM function bodies that combine them.

Don't pass JSON strings between stages. Typed values give compile-time guarantees and skip a redundant encode/decode.

## 3. Routing via `match`

```baml
enum Intent { Cancel, Refund, Question, Spam, }
class Response { message: string, }

function classify_intent(text: string) -> Intent {
  client: "openai/gpt-4o-mini"
  prompt: #"classify the intent of: {{ text }}  {{ ctx.output_format }}"#
}

function handle_cancel(text: string) -> Response {
  client: "openai/gpt-4o-mini"
  prompt: #"cancel: {{ text }}  {{ ctx.output_format }}"#
}

function handle_refund(text: string) -> Response {
  client: "openai/gpt-4o-mini"
  prompt: #"refund: {{ text }}  {{ ctx.output_format }}"#
}

function handle_question(text: string) -> Response {
  client: "openai/gpt-4o-mini"
  prompt: #"question: {{ text }}  {{ ctx.output_format }}"#
}

function handle_message(text: string) -> Response {
  match (classify_intent(text)) {
    Intent.Cancel   => handle_cancel(text),
    Intent.Refund   => handle_refund(text),
    Intent.Question => handle_question(text),
    Intent.Spam     => Response { message: "ignored" },
  }
}
```

- `match (x)` has parens around the scrutinee.
- Use a cheap model (`"openai/gpt-4o-mini"`, Haiku) for the classifier and the expensive one for the branch that actually does the work.

### Type narrowing with `let` bindings

```baml
function json_to_string(value: json) -> string {
  match (value) {
    null => "null",
    let s: string => s,
    let n: int => baml.unstable.string(n),
    let items: json[] => baml.json.stringify(items.to_json()),
    let obj: map<string, json> => baml.json.stringify(obj.to_json()),
    _ => "other",
  }
}
```

`let <name>: <Type> =>` binds the narrowed value inside the arm. Use it whenever you need to reach into the narrowed value, like serializing a sub-structure or pulling a field. `_: <Type> =>` matches without binding when you don't need the value.

## 4. Error propagation

```baml
class StageError { stage: string, message: string, }

class Parsed { value: string, }
class Routed { destination: string, }

function parse_stage(s: string) -> Parsed throws StageError {
  if (s.length() == 0) {
    throw StageError { stage: "parse", message: "empty input" };
  };
  Parsed { value: s.trim() }
}

function route_stage(p: Parsed) -> Routed throws StageError {
  Routed { destination: "queue:" + p.value }
}

function pipeline(s: string) -> Routed throws StageError {
  route_stage(parse_stage(s))
}

function pipeline_safe(s: string) -> Routed? {
  pipeline(s) catch (e) {
    StageError => null,
  }
}
```

`throws T` is part of the signature. The compiler enforces that callers either `catch` the error or re-`throw` (or propagate by also declaring `throws T`). Throw classes give callers a typed shape to match on; you can also throw strings or ints if the failure is simple.

`catch` is an expression — each arm produces a value compatible with the success-path type.

## 5. Fan-out

BAML's `for / in` is sequential. For real concurrency, fan out at the host layer (`asyncio.gather`, `Promise.all` — see `baml-bridges`).

When the parallelism is over a typed array and sequential is fine, write the loop in BAML:

```baml
function summarize_all(docs: string[]) -> string[] {
  let out: string[] = [];
  for (let d in docs) {
    out.push(summarize(d));   // sequential
  }
  out
}
```

## 6. Common pitfalls

- **String-passing between stages** — see §2. Use typed values; the compiler catches drift.
- **Picking too-expensive a classifier model** — classifier-then-handler is the cheapest pattern. Cheap classifier, expensive worker.
- **Catching too broadly** — `catch (e) { _ => ... }` swallows the error type. Use a specific arm (`catch (e) { StageError => ... }`) so unexpected failures still propagate.
- **Live LLM tests on the pipeline** — slow and flaky. Decode cached JSON fixtures with `baml.json.from_string<T>(raw)` to exercise the parsing/orchestration paths deterministically. See `baml-testing`.
- **`for / in` is sequential** — for true concurrency, fan out at the host layer.
- **Missing `{{ ctx.output_format }}` on stages** — every LLM stage with a typed return needs it.
- **Forgetting that `match` and `catch` are expressions** — each arm must produce a value compatible with the surrounding type. Don't put a `;` after the closing `}`.
