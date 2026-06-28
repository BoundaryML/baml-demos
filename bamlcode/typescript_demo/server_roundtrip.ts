// BAML <-> TypeScript round trip: serve in BAML, fetch in BAML, orchestrate in
// Node (the twin of python_demo/server_roundtrip.py).
//
// - `server.serve` (baml_src/ns_server/server.baml) loops forever accepting
//   connections, spawning a BAML handler per connection (each sleeps 500 ms to
//   simulate work). Python parks it in a daemon thread; Node kicks off the
//   async twin without awaiting — BAML runs it on its own async runtime.
// - `demo.fetch_reply_async` (baml_src/ns_demo/demo.baml) curls it back with
//   BAML's own `baml.http.fetch`, returning a typed ServerReply.
// - Promise.all fires 4 fetches concurrently; since the server spawns per
//   connection, all 4 finish in ~0.5 s wall clock, not ~2 s.
//
// Run:  pnpm server   (from typescript_demo/, after `pnpm install`)
import { demo, server } from "./baml_sdk/index.js"; // generated next to this script (baml generate)

const URL = "http://127.0.0.1:8080/";

async function waitUntilReady(timeoutMs = 5000): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    try {
      await demo.fetch_reply_async(URL);
      return;
    } catch {
      if (Date.now() > deadline) throw new Error(`server not ready after ${timeoutMs}ms`);
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
  }
}

async function main(): Promise<void> {
  // serve() loops forever — fire it off without awaiting (the daemon-thread
  // analog), so the process can move on to firing concurrent fetches.
  void server.serve_async();
  await waitUntilReady();

  const start = Date.now();
  const replies = await Promise.all(
    Array.from({ length: 4 }, () => demo.fetch_reply_async(URL)),
  );
  const elapsed = (Date.now() - start) / 1000;

  console.log();
  for (const r of replies) {
    // typed objects, decoded by BAML
    console.log(`  ServerReply(hello=${JSON.stringify(r.hello)}, conn=${r.conn})`);
  }
  console.log(
    `\n4 concurrent fetches in ${elapsed.toFixed(2)}s (handlers sleep 0.5s each — spawn works)`,
  );

  // serve_async() never resolves; exit cleanly like the Python daemon thread.
  process.exit(0);
}

main();
