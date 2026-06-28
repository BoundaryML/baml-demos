# bamlcode

A tiny **Claude Code**, written entirely in [BAML](https://github.com/boundaryml/baml).

It's an agentic coding CLI: you give it a task, and it reasons, then takes **one
tool action at a time** — read / write / edit files, list directories, run shell
commands — feeding each result back to the model until it answers you. The whole
agent loop (the brain, the tools, the REPL, the I/O) lives in `.baml`.

```
  ┌────────────────────────────────────────────┐
  │   bamlcode · a tiny Claude Code, in BAML     │
  └────────────────────────────────────────────┘

you › add a docstring to the top of hello.py
  · I'll look at the file first.
  → read hello.py
      Contents of hello.py:
      1	def hello():
      ...
  · Now I'll insert a module docstring.
  → edit hello.py
      Edited hello.py (replaced 1 occurrence).
● bamlcode
    Done — added a one-line module docstring to hello.py.
```

## Setup

```bash
brew tap boundaryml/baml && brew install baml   # if you don't have it
export ANTHROPIC_API_KEY=sk-ant-...             # the default brain is Claude
```

To use OpenAI instead, set `OPENAI_API_KEY` and switch `client: Brain` →
`client: BrainOpenAI` in `baml_src/ns_agent/agent.baml`.

## Run

```bash
baml run agent.main                                       # the REPL
baml run agent.ask -- --task "list the python files"      # one-shot
baml test                                                 # run the tool-layer tests
baml run --list                                           # see every function
```

Or build the standalone binaries (below) and run those:

```bash
dist/bamlcode                   # interactive REPL  (type 'exit' to quit)
dist/server                     # the concurrent HTTP server demo
```

## Build standalone binaries

The build command is itself a BAML function (`baml_src/ns_build/build.baml`)
that shells out to `baml pack` for each entry point:

```bash
baml run build.run
# → baml pack agent.main -o dist/bamlcode
#   ✓ dist/bamlcode
# → baml pack server.serve -o dist/server
#   ✓ dist/server
```

`baml pack` bundles the BAML source into a single self-contained executable — no
`baml` install, no `baml_src/` directory needed at runtime:

```bash
dist/bamlcode    # runs the REPL directly — no args, no subcommand
dist/server      # the BEP-034 concurrent HTTP server demo on :8080
```

Packing a positional function (no `-f`) makes a single-entry binary, so
`dist/bamlcode` launches the REPL straight away. Each is a ~10 MB native
binary (host platform by default; cross-compile with `--target <triple>`).
`bamlcode` still needs `ANTHROPIC_API_KEY` in the environment at run time;
`server` needs no keys. Ship each binary on its own.

> Want the one-shot mode in the bamlcode binary too? Pack with subcommands instead —
> `baml pack -f agent.main -f agent.ask -o dist/bamlcode` — then call `bamlcode agent.main` /
> `bamlcode agent.ask --task "..."`. Or just run `ask` from source: `baml run agent.ask -- --task "..."`.

## Try it on the demo

There's a tiny buggy Python project in [`python_demo/`](python_demo/) to play with:

```bash
cd python_demo
export ANTHROPIC_API_KEY=sk-ant-...
../dist/bamlcode ask --task "run test_fizzbuzz.py, fix the bug it reveals, then re-run it"
```

bamlcode operates on files in whatever directory you launch it from. See
[`python_demo/README.md`](python_demo/README.md) for more prompts to try.

## Queuing messages

bamlcode runs one turn at a time. The queue is just an in-memory list owned by
the REPL loop — no files, no daemon:

- `/queue <task>` — stage a message (stage as many as you like)
- `/queue` — show the staged queue   ·   `/clear` — empty it
- **enter** on an empty line — run the whole queue in order
- typing a task runs it now, then drains anything you'd staged with `/queue`

The prompt shows the count, e.g. `you (2 queued) ›`.

## Interrupting a turn

While bamlcode is working, you can stop it or feed it more work — just type a
line and press enter:

- press `esc` then `enter` — abort the current turn and go back to the prompt
- anything else — queue *that* to run after the current turn finishes
  (a bare empty enter is ignored)

A cancel takes effect **immediately — even mid-step, during an in-flight LLM call** —
not just between steps. Under the hood the turn runs in a spawned concurrent task
(`spawn { run_turn(...) }`, BAML's real concurrency primitive) while the main loop
watches stdin. On a cancel we call `future.cancel()`, which aborts the running
task on the spot (measured ~11 ms to abort a blocked call). It's a cooperative
cancel of the BAML task, not a `SIGKILL` of the process — so the session stays
intact.

If you cancel partway through a queued batch, the remaining queued messages are
skipped.

## How it works

| Piece | Where | What it does |
|-------|-------|--------------|
| `Step` | `ns_agent/agent.baml` | The model's structured decision: a `thought`, an `action`, and the args for that action. BAML's return-type parsing guarantees it's well-formed. |
| `decide(transcript)` | `ns_agent/agent.baml` | The brain. Given the running transcript, the LLM picks the next single step. |
| `tool_*` | `ns_agent/agent.baml` | The tools: `read_file`, `write_file`, `edit_file`, `list_dir`, `run_bash`. Each returns plain text the model can read; errors come back as recoverable `ERROR: …` strings rather than crashes. |
| `execute(step)` | `ns_agent/agent.baml` | Dispatches a `Step` to its tool via `match` on the action. |
| `run_turn(history, msg)` | `ns_agent/agent.baml` | The agent loop: `decide → execute → observe`, appending to the transcript, until the model chooses `respond` (or hits the 30-step cap). |
| `run_supervised(...)` | `ns_agent/agent.baml` | Runs `run_turn` in a spawned concurrent task while polling stdin, so esc + enter can `future.cancel()` it mid-step. Other typed lines are collected on `Turn.queued` to run after the turn. |
| `main()` / `ask(task)` | `ns_agent/agent.baml` | The interactive REPL and the one-shot entry point. |

The loop streams its progress straight to your terminal via `/dev/tty` (BAML
captures normal stdout, so output is written to the tty directly), and reads your
input from stdin.

## Tests

`baml_src/tests.baml` covers the tool layer deterministically — no LLM calls, no
tokens:

```bash
baml test
# 28 passed, 0 failed   (needs ANTHROPIC_API_KEY — the sentiment evals call live models)
```

## Testing showcase: the sentiment classifier

`baml_src/ns_sentiment/` is a guided tour of testing in BAML, built around a
tiny sentiment classifier (`sentiment.baml` is the thin function under test;
`eval.baml` holds the judge + case loaders; `tests.baml` is the tour):

1. **Start simple** — one live call with a direct expectation, plus a
   no-tokens test that decodes a frozen model reply with
   `baml.json.from_string<Verdict>`.
2. **Testsets** — groups generated with `let labels: Label[] = [...]` + `for`,
   producing nested IDs like `by_label::neutral/classifies its example`.
3. **LLM as judge** — a stronger model grades the classifier on a sarcastic
   input where the "right" answer is fuzzy. Used sparingly: everywhere the
   answer is known, tests assert directly.
4. **Synthetic tests** — a model generates examples whose label is known by
   construction; the classifier must recover it (with the judge as a lenient
   second opinion on mismatches).
5. **Tests from a file** — `testdata/sentiment_cases.json` is plain JSON, and
   the testset loop runs at discovery time, so every case in the file becomes
   its own named test. Edit the file, add cases, re-run — and filter to a
   single case with `baml test -i "from_file::3*"`.
6. **Tests from an API** — the test spawns a one-shot HTTP server that serves
   that same file, fetches the cases back via `baml.http.fetch`, and runs them.

```bash
baml test -i "basics::*"            # step 1 only
baml test -i "by_label::neutral*"   # one generated group
baml test -i "from_file::*"         # re-run after editing testdata/
```

## Layout

```
baml.toml
baml_src/
  ns_agent/         # namespace root.agent — everything bamlcode
    agent.baml      #   types, tools, the agent loop, entry points, I/O helpers
    clients.baml    #   LLM clients (Anthropic Brain, OpenAI BrainOpenAI)
    tests.baml      #   deterministic tool-layer tests
  ns_ansi/          # namespace root.ansi — terminal colors (kept separate;
    ansi.baml       #   other namespaces use it too)
  ns_build/         # namespace root.build — `baml run build.run` packs dist/
    build.baml
  ns_demo/          # namespace root.demo — minimal function for Python interop
    demo.baml
  ns_images/        # namespace root.images — image-generation pipeline
    pipeline.baml
  ns_sentiment/     # namespace root.sentiment — the testing showcase
    sentiment.baml  #   the classifier under test (thin on purpose)
    eval.baml       #   LLM judge, synthetic data, file/API case loading
    tests.baml      #   the guided tour of testsets
  ns_server/        # namespace root.server — BEP-034 concurrent HTTP demo
    server.baml
  generators.baml   # codegen config: emits the typed Python `baml_sdk` package
testdata/
  sentiment_cases.json  # editable eval cases (from_file / from_api testsets)
python_demo/
  baml_sdk/            # GENERATED Python package (baml generate) — do not edit
  hello_baml.py        # Python ↔ BAML interop demo (calls demo.greet via baml_sdk)
  server_roundtrip.py  # BAML server in a Python thread + concurrent BAML fetches
dist/               # packed binaries (gitignored — rebuild: baml run build.run)
```

## Calling BAML from Python

`baml generate` emits a typed `baml_sdk` package into `python_demo/`, right next to
the Python scripts that import it (no sys.path tweaking); each BAML namespace
becomes a subpackage, and classes come through as pydantic models:

```python
from baml_sdk import demo

greeting = demo.greet(name="vbv")   # -> Greeting(message='hello, vbv!', letters=3)
print(greeting.model_dump_json())

# BAML class methods come through too: factories (no self) as staticmethods,
# instance methods as bound methods on the model.
g = demo.Greeting.new("class methods")
g.shout()                           # 'HELLO, CLASS METHODS!'
g.repeated(3)                       # -> Greeting (chainable)
```

Every function also gets an `_async` twin (`greet_async`, …) for asyncio code.

The demo scripts carry their dependencies as PEP 723 inline metadata, so uv
handles them automatically:

```bash
uv run python_demo/hello_baml.py          # basics: functions, class methods, pydantic
uv run python_demo/server_roundtrip.py    # serve in BAML, fetch in BAML, orchestrate in Python
```

`server_roundtrip.py` is the fun one: it runs `server.serve` in a daemon
Python thread, then `asyncio.gather`s 4 `demo.fetch_reply_async` calls —
BAML's `baml.http.fetch` curling BAML's own socket server, with typed
`ServerReply` models coming back. All 4 finish in ~0.5 s wall clock (each
handler sleeps 500 ms), proving the per-connection `spawn` really is
concurrent:

```
4 concurrent fetches in 0.50s (handlers sleep 0.5s each — spawn works)
```
