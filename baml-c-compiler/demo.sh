#!/usr/bin/env bash
#
# Live demo: a C compiler written entirely in BAML.
#
#   ./demo.sh                      # defaults to examples/fib.c
#   ./demo.sh examples/loop.c      # any .c file in the supported subset
#
# Uses the `baml` toolchain on your PATH. To drive a locally-built compiler:
#   BAML=/path/to/baml-cli ./demo.sh examples/fib.c
#
cd "$(dirname "$0")"
BAML="${BAML:-baml}"
SRC="${1:-examples/fib.c}"

rule() { printf '\n\033[1;36m──────── %s ────────\033[0m\n' "$*"; }

rule "1. The C program  ($SRC)"
cat "$SRC"

rule "2. Compiled to x86-64 assembly"
"$BAML" run cc.emit -- --path "$SRC" 2>/dev/null | grep -v '^null$'

rule "3. Assembled + linked + run  (BAML shells out to gcc, then runs it)"
"$BAML" run cc.run -- --path "$SRC" 2>/dev/null | grep -v '^null$'
