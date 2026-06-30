# baml-c-compiler

A small **C compiler written entirely in [BAML](https://github.com/boundaryml/baml)**.
It lexes C, parses it to a typed AST, and emits real assembly that the system
toolchain assembles, links, and runs — with two backends: **x86-64** (Linux) and
**AArch64** (macOS / Apple Silicon).

## What it can compile

Functions + parameters + **recursion** · local `int` variables + assignment ·
`if / else` · `while` · `printf(...)` (strings and `%d`) · integer arithmetic &
comparison (`+ - * / %   < <= > >= == !=`, unary `-`) · parentheses.

Verified working: recursive `fib(10) = 55`, `10! = 3628800`, a counting loop,
hello world. **Not yet:** other types, pointers, arrays, structs, `for`, preprocessor.

## Setup (Apple Silicon Mac)

**Prerequisite:** Xcode Command Line Tools — `xcode-select --install`. Provides
`clang` (and the `gcc`/`as`/`ld` shims) used to assemble + link the emitted `.s`.

Then you need the `baml` CLI. Either works:

**A — Installed `baml` (simplest).** If you have it via Homebrew
(`brew install boundaryml/tap/baml`), you're set: `baml.toml` here pins the
**canary** toolchain, so the first `baml` command in this directory auto-fetches
it. Confirm with `baml --version`, then jump to **Run it**.

**B — Built from the baml repo (verified fallback).** If step A's `baml test`
reports a parse/check error, your published canary is older than this demo — build
the CLI from your local `baml` checkout and run the demo against it:

```bash
cd /path/to/baml/baml_language            # e.g. ../baml/baml_language
cargo build -p baml_cli --bin baml-cli    # → target/debug/baml-cli

# Point the demo at it (export once; demo.sh and the raw commands honor $BAML):
export BAML=/path/to/baml/baml_language/target/debug/baml-cli
export BAML_CLI_ALLOW_DIRECT=1            # silences a "use the wrapper" notice
```

With **A**, run the commands below as written (`baml ...`). With **B**, prefix
them with `$BAML` instead (`$BAML test`, `$BAML run cc.run_arm64 -- ...`);
`./demo.sh` picks up `$BAML` automatically either way. This is the exact path
verified on an M-series Mac.

## Run it

`demo.sh` auto-selects the backend for your CPU (AArch64 on Apple Silicon):

```bash
baml test                                   # run the 7 deterministic tests
./demo.sh examples/fib.c                    # narrated: C source → assembly → running program
```

Or pick a backend explicitly:

```bash
# x86-64 (Linux)
baml run cc.emit       -- --path examples/fib.c   # print the assembly
baml run cc.run        -- --path examples/fib.c   # build with gcc, then run

# AArch64 (macOS / Apple Silicon)
baml run cc.emit_arm64 -- --path examples/fib.c   # print the assembly
baml run cc.run_arm64  -- --path examples/fib.c   # build with clang, then run
```

`cc.run` on `fib.c` prints:

```
fib(0) = 0
fib(1) = 1
...
fib(10) = 55
```

Examples in [`examples/`](examples/): `return_42`, `arithmetic`, `hello`, `loop`,
`fib`, `factorial`. All six are verified working on Apple Silicon (M-series).

## How it works

`baml_src/ns_cc/`: **lexer → parser → ast → backends/ → driver** (+ `tests`).
Each backend — `backends/x86.baml` and `backends/arm.baml` — is a stack-machine
code generator sharing one `Gen` context (`backends/gen.baml`). The compiler is
pure BAML; `cc.run` / `cc.run_arm64` shell out to `gcc`/`clang` only to assemble +
link the emitted `.s`, exactly how gcc and clang themselves hand off to `as`/`ld`.
