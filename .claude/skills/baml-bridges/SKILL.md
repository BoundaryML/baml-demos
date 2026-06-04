---
name: baml-bridges
description: Use when calling BAML from host code, or when BAML needs a host capability it lacks (DBs, sockets, crypto). Today's supported host is Python via `baml generate` -> the `baml_sdk` package (NOT the older `baml_client` name). Covers the `generator target { ... }` block (in a `.baml` file, NOT TOML), the generated `b.<function>` API, and the host-bridge pattern (BAML shells out to a thin Python entrypoint via `baml.sys.shell`). Other host languages exist upstream but should not be assumed in this repo. Prerequisite: baml-core.
---

# baml-bridges

Load this when the task crosses the BAML / host boundary. Host code calls BAML through the **generated `baml_sdk` Python package**; BAML reaches host capabilities through `baml.sys.shell` + a thin generic bridge.

> **Today's supported host is Python.** TypeScript / Go / Ruby clients exist upstream but **do not assume them here** until the repo adds generators and examples for them.

## 1. The `generator` block

Generators live in a `.baml` file (usually `baml_src/generators.baml`), **not** in `baml.toml`. The block syntax is BAML, not TOML.

```baml
// baml_src/generators.baml
//
// NOTE: Generator field names and valid output_type values change across BAML
// releases. Treat this block as illustrative; copy from your checked-in
// generators.baml and run `baml generate` after edits.
generator target {
  output_type "python/pydantic"

  // Relative to baml_src/. Layout must match where `baml_sdk` is imported from.
  output_dir "../"

  default_client_mode "sync"
}
```

Run:

```bash
baml generate
```

This emits a **`baml_sdk`** Python package (typed entrypoints + types) at the configured `output_dir`. **The package is `baml_sdk`, not the older `baml_client` name** that appears in old docs.

## 2. The generated Python client

```python
# Import path matches generated layout — this guide assumes the package name `baml_sdk`.
from baml_sdk.sync_client import b

ticket = b.extract_ticket("refund request text")
print(ticket.title, ticket.priority)
```

- Function names in Python match the BAML names (snake_case stays snake_case).
- Types come through as pydantic models (when `output_type "python/pydantic"`).
- For async: import from `baml_sdk.async_client` (when `default_client_mode "async"` or per-call).

Use generated clients for product code. Use `baml run` for local debugging, scripts, demos, and CI checks.

## 3. Fan-out in host code

BAML's `for / in` is sequential. For real concurrency, fan out at the host layer:

```python
import asyncio
from baml_sdk.async_client import b

async def triage_many(emails):
    return await asyncio.gather(*(b.classify_email(e) for e in emails))
```

When parallelism inside BAML is acceptable, write the loop in BAML and let it run sequentially.

## 4. Bridge pattern — BAML -> host capability

Use a host bridge only when the task needs a capability BAML doesn't yet provide well: databases, sockets, crypto, advanced byte processing, browser/server runtimes, vector ops, or a missing stdlib primitive.

The bridge should be thin, generic, and protocol-driven.

```baml
// ---------------------------------------------------------------------------
// BRIDGE SKETCH — inline comments go stale fast.
// Path, interpreter (python3 vs uv run vs venv), and argv layout drift from
// what this markdown shows. Read the actual bridge entrypoint + JSON schema in
// the repo before editing a real bridge.
// ---------------------------------------------------------------------------
class BridgeRequest {
  op: "query" | "execute" | "sign",
  payload: json,
}

class BridgeResponse {
  ok: bool,
  data: json?,
  error: string?,
}

function call_bridge(req: BridgeRequest) -> BridgeResponse {
  let payload_json = baml.json.stringify(req.to_json());
  let request_path = ".baml_bridge_request.json";

  baml.fs.write(request_path, payload_json);
  // Same caveat: command line below is illustrative; sync with your bridge script.
  let out = baml.sys.shell("python3 bridge.py " + request_path, null);

  if (!out.ok()) {
    throw "bridge exited " + baml.unstable.string(out.exit_code) + ": " + out.stderr.to_string();
  };

  baml.json.from_string<BridgeResponse>(out.stdout.to_string())
}
```

Note: `baml.sys.shell(cmd, options?)` returns `ShellOutput { stdout: uint8array, stderr: uint8array, exit_code: int }` plus `.ok()`. Decode the byte buffer with `.to_string()` before handing it to `baml.json.from_string<T>`. `baml.json.stringify(req.to_json())` round-trips a typed request to JSON.

Bridge rules:

- Keep domain policy in BAML; keep external capability in the bridge.
- Don't hardcode one component, route, table, or test case in the bridge.
- Use JSON or a documented line protocol. Avoid fragile string scraping.
- When the host calls BAML, use `baml run --output json`.
- Surface bridge errors via stderr, exit code, and context.
- Add tests for BAML-side protocol classes (the bridge wire format) and bridge happy/error paths.

> **Inline comments in bridge sketches go stale.** Always cross-check `python3` vs `uv run`, argv shape, env wiring, and the JSON envelope against the real bridge entrypoint and tests in your repo before relying on them.

## 5. When to bridge (vs. keep it in BAML)

**BAML handles well:**
- Typed structured-output LLM calls
- Multi-stage LLM pipelines
- Parse-only tests with cached JSON fixtures
- Validation, scoring, formatting
- Line-oriented string processing
- Small CLIs and typed APIs over external systems

**Reach for a bridge when:**
- Long-lived network serving
- Database connection lifetime
- Filesystem watching
- Cryptography
- Binary protocols
- High-concurrency fanout before BAML exposes the needed runtime primitive
- Stdlib functionality that `baml describe` confirms is missing

Keep the BAML surface clean even when you bridge. The bridge should be replaceable when the stdlib catches up.

## 6. Common pitfalls

- **TOML `[[generator]]` in `baml.toml`** — wrong. Generators are a `generator <name> { ... }` block in a `.baml` file.
- **Package name `baml_client`** — that's the old name. Today it's `baml_sdk`.
- **Stale generated client** — `baml generate` after every schema change. Wire it into your dev loop (file watcher, pre-commit, `make generate`).
- **Assuming TS / Go / Ruby support** — Python is the only host currently exercised in this repo. Don't paste host snippets for other languages from old docs.
- **Shelling out to `baml run` from product code** when `baml_sdk` is available — slow and brittle. Use generated clients in product paths.
- **Per-call `baml.sys.shell` inside tight loops** — repeated shell calls dominate runtime and make tests flaky. Prefer one structured bridge call over many tiny ones.
- **Hardcoding component-specific logic in the bridge** — keep the bridge generic with a documented `op` / `payload` protocol; keep domain rules in BAML.
- **Trying to invoke host functions from BAML via syntax** — there's no `extern function`. BAML reaches host capability via `baml.sys.shell` + a generic bridge.
