#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = ["baml-core", "pydantic"]
# ///
"""Tiny Python <-> BAML interop demo.

Calls the BAML function `demo.greet` (baml_src/ns_demo/demo.baml) through the
generated `baml_sdk` package. Greeting comes back as a typed pydantic model.

Regenerate the SDK after editing the BAML side:  baml generate
Run:  uv run python_demo/hello_baml.py   (or just ./python_demo/hello_baml.py)
"""

from baml_sdk import demo  # generated next to this script (baml generate)


def main() -> None:
    for name in ["vbv", "  sheep council  ", "BAML"]:
        greeting = demo.greet(name=name)  # -> Greeting(message=..., letters=...)
        print(f"{greeting.message:30}  ({greeting.letters} letters)")

    # It's a real pydantic model — serialization comes for free.
    print("\nas JSON:", demo.greet(name="python").model_dump_json())

    # BAML class methods are callable from Python too:
    g = demo.Greeting.new("class methods")  # factory (no self) -> staticmethod
    print("\nfactory:  ", g.message)
    print("instance: ", g.shout())  # `shout(self)` -> bound method
    print("chained:  ", g.repeated(3).model_dump())  # methods returning Greeting chain


if __name__ == "__main__":
    main()
