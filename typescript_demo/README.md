# Calling BAML from TypeScript

The Node/TypeScript twin of [`python_demo/`](../python_demo/). Same two BAML-interop scripts as
the Python demo, calling the same BAML functions through the generated
`baml_sdk` package — just from Node instead of CPython.

| Python (`python_demo/`)        | TypeScript (`typescript_demo/`)   | BAML it calls                        |
|-------------------------|---------------------------|--------------------------------------|
| `hello_baml.py`         | `hello_baml.ts`           | `demo.greet`, `Greeting` methods     |
| `server_roundtrip.py`   | `server_roundtrip.ts`     | `server.serve`, `demo.fetch_reply`   |

(The `fizzbuzz.py` / `twosum.py` files in `python_demo/` aren't interop — they're scratch
files for the bamlcode agent to edit, so they have no TS counterpart.)

## Generate the SDK

`baml generate` emits a typed `baml_sdk` package into `typescript_demo/`, right next to
the scripts that import it. Each BAML namespace becomes a subpackage, and classes
come through as plain typed classes (with their BAML methods attached):

```bash
baml generate          # emits typescript_demo/baml_sdk/ (and python_demo/baml_sdk/ for Python)
```

The generator block lives in `baml_src/generators.baml` (`generator ts_target`,
`output_type "typescript/node"`). The generated code imports the
`@boundaryml/baml-core-node` runtime.

## Run

```bash
cd typescript_demo
pnpm install              # links @boundaryml/baml-core-node + tsx

pnpm hello            # basics: functions, class methods, JSON
pnpm server           # serve in BAML, fetch in BAML, orchestrate in Node
pnpm typecheck        # tsc --noEmit over the scripts + generated SDK
```

`pnpm hello` needs no API keys; `server` needs none either (the server demo
makes no LLM calls).

## How it maps to the Python demo

```ts
import { demo } from "./baml_sdk/index.js";

const greeting = demo.greet({ name: "vbv" }); // -> Greeting { message, letters }
JSON.stringify(greeting);                      // typed object → JSON for free

// BAML class methods come through too: factories (no self) as static methods,
// instance methods as bound methods on the instance.
const g = demo.Greeting.new("class methods");  // static factory
g.shout();                                      // 'HELLO, CLASS METHODS!'
g.repeated(3);                                  // -> Greeting (chainable)
```

Every function also gets an `_async` twin (`greet_async`, `fetch_reply_async`, …)
returning a `Promise`. `server_roundtrip.ts` uses those: it kicks off
`server.serve_async()` without awaiting (BAML runs it on its own async runtime —
the analog of Python's daemon thread), then `Promise.all`s 4
`demo.fetch_reply_async` calls. All 4 finish in ~0.5 s wall clock even though each
handler sleeps 500 ms, because the BAML server `spawn`s a task per connection:

```
4 concurrent fetches in 0.50s (handlers sleep 0.5s each — spawn works)
```
