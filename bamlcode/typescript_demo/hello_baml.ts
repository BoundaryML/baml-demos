// Tiny TypeScript <-> BAML interop demo (the Node twin of python_demo/hello_baml.py).
//
// Calls the BAML function `demo.greet` (baml_src/ns_demo/demo.baml) through the
// generated `baml_sdk` package. The greeting comes back as a typed class.
//
// Regenerate the SDK after editing the BAML side:  baml generate
// Run:  pnpm hello   (from typescript_demo/, after `pnpm install`)
import { demo } from "./baml_sdk/index.js"; // generated next to this script (baml generate)

function main(): void {
  for (const name of ["vbv", "  sheep council  ", "BAML"]) {
    const greeting = demo.greet({ name }); // -> Greeting { message, letters }
    console.log(`${greeting.message.padEnd(30)}  (${greeting.letters} letters)`);
  }

  // It's a plain typed object — JSON serialization comes for free (the bound
  // method fields are functions, so JSON.stringify drops them).
  console.log("\nas JSON:", JSON.stringify(demo.greet({ name: "python" })));

  // BAML class methods are callable from TypeScript too:
  const g = demo.Greeting.new("class methods"); // factory (no self) -> static method
  console.log("\nfactory:  ", g.message);
  console.log("instance: ", g.shout()); // shout(self) -> bound instance method
  // methods returning Greeting chain; strip the bound methods for a clean dump.
  console.log("chained:  ", JSON.parse(JSON.stringify(g.repeated(3))));
}

main();
