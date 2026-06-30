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

## Run it

From this directory (needs `baml` on the **canary** channel and a `gcc`/`clang`).
`demo.sh` auto-selects the backend for your CPU:

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
`fib`, `factorial`.

> Using a locally built compiler instead of an installed one? Prefix any command
> with `BAML=/path/to/baml-cli` (the demo script honors it too).

## How it works

`baml_src/ns_cc/`: **lexer → parser → ast → backends/ → driver** (+ `tests`).
Each backend — `backends/x86.baml` and `backends/arm.baml` — is a stack-machine
code generator sharing one `Gen` context (`backends/gen.baml`). The compiler is
pure BAML; `cc.run` / `cc.run_arm64` shell out to `gcc`/`clang` only to assemble +
link the emitted `.s`, exactly how gcc and clang themselves hand off to `as`/`ld`.
