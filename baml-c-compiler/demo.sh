#!/usr/bin/env bash
#
# Live demo: a C compiler written entirely in BAML.
#
#   ./demo.sh                      # defaults to examples/fib.c
#   ./demo.sh examples/loop.c      # any .c file in the supported subset
#
# Picks the backend for the host CPU automatically: AArch64 on Apple Silicon,
# x86-64 elsewhere (override with ARCH=arm64 or ARCH=x86). Uses the `baml`
# toolchain on your PATH; for a local build: BAML=/path/to/baml-cli ./demo.sh.
#
cd "$(dirname "$0")"
BAML="${BAML:-baml}"
SRC="${1:-examples/fib.c}"

case "${ARCH:-$(uname -m)}" in
  arm64 | aarch64) EMIT=cc.emit_arm64; RUN=cc.run_arm64; ARCH_LABEL="AArch64 (Apple Silicon)" ;;
  *)               EMIT=cc.emit;       RUN=cc.run;       ARCH_LABEL="x86-64" ;;
esac

rule() { printf '\n\033[1;36m──────── %s ────────\033[0m\n' "$*"; }

rule "1. The C program  ($SRC)"
cat "$SRC"

rule "2. Compiled to $ARCH_LABEL assembly"
"$BAML" run "$EMIT" -- --path "$SRC" 2>/dev/null | grep -v '^null$'

rule "3. Assembled + linked + run  (BAML shells out to gcc/clang, then runs it)"
"$BAML" run "$RUN" -- --path "$SRC" 2>/dev/null | grep -v '^null$'
