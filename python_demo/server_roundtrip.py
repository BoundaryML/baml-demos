#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["baml-core", "pydantic"]
# ///
"""BAML <-> Python round trip: serve in BAML, fetch in BAML, orchestrate in Python.

- `server.serve` (baml_src/ns_server/server.baml) runs in a daemon Python
  thread — it loops forever accepting connections, spawning a BAML handler
  per connection (each sleeps 500 ms to simulate work).
- `demo.fetch_reply_async` (baml_src/ns_demo/demo.baml) curls it back with
  BAML's own `baml.http.fetch`, returning a typed ServerReply.
- Python's asyncio.gather fires 4 fetches concurrently; since the server
  spawns per connection, all 4 finish in ~0.5 s wall clock, not ~2 s.

Run:  uv run python_demo/server_roundtrip.py   (or just ./python_demo/server_roundtrip.py)
"""

import asyncio
import threading
import time

from baml_sdk import demo, server  # generated next to this script (baml generate)

URL = "http://127.0.0.1:8080/"


async def wait_until_ready(timeout: float = 5.0) -> None:
    deadline = time.monotonic() + timeout
    while True:
        try:
            await demo.fetch_reply_async(URL)
            return
        except Exception:
            if time.monotonic() > deadline:
                raise
            await asyncio.sleep(0.05)


async def main() -> None:
    # serve() loops forever — park it in a daemon thread so the process can exit.
    threading.Thread(target=server.serve, daemon=True).start()
    await wait_until_ready()

    start = time.monotonic()
    replies = await asyncio.gather(*(demo.fetch_reply_async(URL) for _ in range(4)))
    elapsed = time.monotonic() - start

    print()
    for r in replies:  # typed pydantic models, decoded by BAML
        print(f"  ServerReply(hello={r.hello!r}, conn={r.conn})")
    print(f"\n4 concurrent fetches in {elapsed:.2f}s (handlers sleep 0.5s each — spawn works)")


if __name__ == "__main__":
    asyncio.run(main())
