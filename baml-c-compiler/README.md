# baml-c-compiler

A small **C → x86-64 compiler written entirely in [BAML](https://github.com/boundaryml/baml)**.
It lexes C, parses it to a typed AST, and emits real x86-64 assembly that `gcc`
then assembles, links, and runs.

## What it can compile

Functions + parameters + **recursion** · local `int` variables + assignment ·
`if / else` · `while` · `printf(...)` (strings and `%d`) · integer arithmetic &
comparison (`+ - * / %   < <= > >= == !=`, unary `-`) · parentheses.

Verified working: recursive `fib(10) = 55`, `10! = 3628800`, a counting loop,
hello world. **Not yet:** other types, pointers, arrays, structs, `for`, preprocessor.

## Run it

From this directory (needs `baml` on the **canary** channel and a `gcc`):

```bash
baml test                                   # run the 7 deterministic tests

./demo.sh examples/fib.c                    # narrated: C source → assembly → running program

baml run cc.emit -- --path examples/fib.c   # just print the x86-64 our compiler emits
baml run cc.run  -- --path examples/fib.c   # compile, assemble + link with gcc, and run
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

`baml_src/ns_cc/`: **lexer → parser → ast → codegen → driver** (+ `tests`).
A stack-machine code generator (System V ABI, 16-byte-aligned calls). The compiler
is pure BAML; `cc.run` shells out to `gcc` only to assemble + link the emitted `.s`
— exactly how gcc and clang themselves hand off to `as` and `ld`.
