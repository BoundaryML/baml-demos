# bamlcode demo (TypeScript)

A tiny TypeScript project with **one intentional bug**, so you can watch bamlcode
read, reason, edit, and re-run.

```
typescript_demo/
  fizzbuzz.ts        # fizzbuzz(n) — has a bug: 15, 30, 45… return "Fizz", not "FizzBuzz"
  test_fizzbuzz.ts   # plain-stdlib (node:test) test that currently FAILS on 15
```

## Try it

bamlcode operates on files in **whatever directory you launch it from**, so cd in
here first:

```bash
cd typescript_demo
pnpm install                         # one-time: tsx + the BAML runtime
export ANTHROPIC_API_KEY=sk-ant-...

# point at the packed binary (or use the project launcher: ../bamlcode)
../dist/bamlcode main
```

Then type a task, e.g.:

- `run the tests and tell me what's failing`
- `the fizzbuzz test fails on 15 — find and fix the bug, then re-run the tests`
- `run npx tsx fizzbuzz.ts and explain the output`
- `add a test for fizzbuzz(30) and make sure it passes`

Or one-shot, without the REPL:

```bash
cd typescript_demo
../dist/bamlcode ask --task "run npx tsx --test test_fizzbuzz.ts, fix the bug it reveals, and re-run it to confirm it passes"
```

## What "fixed" looks like

The bug is an ordering problem — `n % 3 === 0` catches multiples of 15 before the
`n % 15 === 0` branch ever runs. After the fix:

```bash
npx tsx --test test_fizzbuzz.ts
# all tests passed ✅
```

To reset the demo to its buggy state, just `git checkout typescript_demo/` (or
re-copy the files).
