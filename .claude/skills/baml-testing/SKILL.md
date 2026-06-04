---
name: baml-testing
description: Use when writing or running BAML tests. Covers `testset` / `test` blocks with `let` bindings + `assert.equal` / `assert.*`, running tests with `baml test --list / -i / -e`, decoding cached LLM replies and fixtures via `baml.json.from_string<T>(raw)` or the compiler-synthesized `F$parse(raw)` companion (you don't hand-write `$` names, but the generated one is callable), and nested testsets for grouping. Prerequisite: baml-core. Pair with baml-llm-functions or baml-pipelines if the function under test calls an LLM.
---

# baml-testing

Load this when the task involves authoring BAML tests or invoking `baml test`. Tests are imperative — bind locals, call functions, assert on results.

## 1. Test block, minimal

```baml
function gcd(a: int, b: int) -> int {
  if (b == 0) { a } else { gcd(b, a - (a / b) * b) }
}

testset "gcd_smoke" {
  test "trivial" {
    let r = gcd(12, 8);
    assert.equal(r, 4);
  }

  test "coprime" {
    let r = gcd(17, 13);
    assert.equal(r, 1);
  }
}
```

Run them:

```bash
baml test --list                          # list testsets + cases
baml test                                 # run everything
baml test -i "gcd_smoke::trivial"         # run one case
baml test -i "gcd_smoke::*"               # run all cases in the set
baml test -e 'gcd(12, 8) == 4'            # ad-hoc, no test block needed
```

## 2. The grammar

```baml
testset "<suite_name>" {
  test "<case_name>" {
    let <var> = <expr>;
    assert.<op>(<args>);
  }
}
```

- `<suite_name>` and `<case_name>` are string literals.
- Test path for `-i` is `<suite>::<case>`.
- Test body is a list of statements (`let`, calls, asserts).
- Asserts available today: `assert.equal(actual, expected)`, `assert.is_true(cond)`, `assert.not_null(value)`, `assert.contains(haystack, needle)` (string substring). No `not_equal` / `true` / `false` / `throws` in current builds — see §5 for the catch-based pattern.

## 3. Nested testsets for grouping

`testset` blocks nest. You can also drive nesting via `let` + `for`:

```baml
testset "sentiment" {
  let topics = ["happy", "sad", "neutral"];
  for (let t in topics) {
    testset t {
      test "single example" {
        let r = classify_sentiment("today is " + t);
        assert.equal(r, t);
      }
    }
  }
}
```

Fully-qualified case ID: `sentiment::happy::single example` (testset names join with `::`). Use `-i "sentiment::happy::*"` to scope a run.

## 4. Testing LLM functions deterministically — decode cached JSON

You almost never want a test to call a live LLM. The pattern: capture the model's reply once, paste it as a fixture, decode it with the JSON stdlib, exercise the rest of the pipeline.

```baml
// The LLM function `classify_email` returns `Intent` and lives in your project
// (defined as in `baml-llm-functions`). For tests, decode a captured reply
// straight into `Intent` — the parsing logic the runtime would apply on a live
// model response is the same logic `baml.json.from_string<Intent>` runs.

class Email { id: string, from: string, subject: string, body: string, }
class Intent {
  kind: "billing" | "support" | "sales" | "spam" | "other",
  confidence: float,
  rationale: string,
}

function load_emails(raw: string) -> Email[] {
  baml.json.from_string<Email[]>(raw)
}

testset "intent_parse" {
  test "cancel" {
    // Captured LLM reply, frozen in the test. No API call.
    let raw = #"{ "kind": "support", "confidence": 0.94, "rationale": "asks for cancellation" }"#;
    let r = baml.json.from_string<Intent>(raw);

    assert.equal(r.kind, "support");
  }

  test "load emails fixture" {
    let raw = #"[{"id":"1","from":"a@example.com","subject":"Hi","body":"Need help"}]"#;
    let emails = load_emails(raw);

    assert.equal(emails.length(), 1);
    assert.equal(emails[0].subject, "Hi");
  }
}
```

Helpers (run `baml describe baml.json` for the live list):

- `baml.json.from_string<T>(s)` — decode a string straight into type `T` when the whole payload matches.
- `baml.json.parse(s)` — `string -> json` (untyped), then narrow with `from_json<T>` if you need partial extraction.
- For an **LLM function** `F`, the compiler also synthesizes a parse-only companion **`F$parse(raw: string) -> ReturnType`** — calling it runs exactly the parser the live call would, against a captured reply. Use it when you want to test the real parsing path (not just generic JSON decode).

For pipelines: feed each stage cached JSON via `baml.json.from_string<StageType>(...)` (or `Stage$parse(raw)`) and assert on the stage's output. No tokens burned, fully deterministic.

> **You don't hand-write `$` names** — the compiler owns the `$` namespace. But the auto-generated `F$parse` companion is real and callable; the deprecated pattern was *defining your own* `<fn>$parse` function, not using the synthesized one.

## 5. Testing error paths — catch + assert pattern

There is no `assert.throws` in current CLIs. The portable pattern is to `catch` the expected throw into a sentinel value, then assert on it. Both arms of the `catch` must produce a value compatible with the success path's type, so plan a sentinel that fits.

```baml
function divide(a: int, b: int) -> int throws string {
  if (b == 0) { throw "division by zero" };
  a / b
}

testset "divide" {
  test "happy" {
    assert.equal(divide(10, 2), 5);
  }

  test "by zero caught" {
    let result = divide(10, 0) catch (e) { string => -1 };
    assert.equal(result, -1);
  }
}
```

For typed errors:

```baml
class BadInput { message: string, }

function require_positive(n: int) -> int throws BadInput {
  if (n <= 0) { throw BadInput { message: "must be positive" } };
  n
}

testset "require_positive" {
  test "rejects zero" {
    let caught_msg = require_positive(0) catch (e) {
      BadInput => -1
    };
    assert.equal(caught_msg, -1);
  }
}
```

If you need the message: capture it into a side variable inside the catch arm before returning the sentinel.

## 6. Test discovery

`baml test --list` walks every `.baml` file in the project and prints `<testset>::<test>` for each block found. No registration; tests can live in the same file as the function under test or in a sibling `*.test.baml`.

## 7. Common pitfalls

- **Reaching for `assert.throws` / `assert.not_equal` / `assert.true` / `assert.false`** — these don't exist in current builds. The only asserts are `equal`, `is_true`, `not_null`, `contains`. Use the catch-and-assert pattern from §5 for error paths; use `assert.is_true(a != b)` for inequality.
- **Live LLM call in a test** — slow, costs tokens, flaky. Decode cached JSON with `baml.json.from_string<T>(raw)`.
- **Defining your own `<fn>$parse`** — wrong; the `$` namespace belongs to the compiler. But the *synthesized* `F$parse(raw) -> ReturnType` for an LLM function `F` is real and callable — use it (or `baml.json.from_string<T>`) to parse a captured reply.
- **`baml.json.decode_str` / `encode`** — wrong API names. The current ones are `parse`, `stringify`, `stringify_pretty`, `from_string`, `from_json`, `to_json`, `to_string` (the encode-side helpers need a CLI build with the `json` type alias resolved).
- **Forgetting `;` after `let`** — every statement in a test body needs a trailing semicolon.
- **`assert.equal` argument order** — actual first, expected second by convention.
- **No `assert` at all** — a `test` block with no asserts passes vacuously. The compiler doesn't warn; you have to remember.
- **Asserting equality on classes with optional fields** — equality is structural. If the LLM may omit a field, build the expected value with that field as `null` rather than expecting it absent.
- **Live bridges or providers in the full suite** — if it makes things slow or flaky, add smaller filtered `-i` commands for CI.
