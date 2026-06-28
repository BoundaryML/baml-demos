/**
 * FizzBuzz — enterprise-ready implementation.
 *
 * Usage
 * -----
 *     npx tsx fizzbuzz.ts            # runs for n=20 (default)
 *     npx tsx fizzbuzz.ts --n 100    # runs for n=100
 *     npx tsx fizzbuzz.ts --help
 */
import { parseArgs } from "node:util";
import { fileURLToPath } from "node:url";

/**
 * Return the FizzBuzz sequence for 1..n as a list of strings.
 *
 * Rules
 * -----
 * - Divisible by 15 -> "FizzBuzz"
 * - Divisible by  3 -> "Fizz"
 * - Divisible by  5 -> "Buzz"
 * - Otherwise       -> String(i)
 *
 * @param n Upper bound of the sequence (inclusive). Must be a positive integer.
 * @returns The FizzBuzz sequence from 1 to n.
 * @throws {TypeError}  If `n` is not an integer.
 * @throws {RangeError} If `n` is less than 1.
 *
 * @example
 *   fizzbuzz(5)         // ['1', '2', 'Fizz', '4', 'Buzz']
 *   fizzbuzz(15).at(-1) // 'FizzBuzz'
 */
export function fizzbuzz(n: number): string[] {
  if (typeof n !== "number" || !Number.isInteger(n)) {
    const got = typeof n === "number" ? String(n) : typeof n;
    throw new TypeError(`n must be an integer, got ${got}`);
  }
  if (n < 1) {
    throw new RangeError(`n must be a positive integer, got ${n}`);
  }

  const out: string[] = [];
  for (let i = 1; i <= n; i++) {
    if (i % 3 === 0) {
      out.push("Fizz");
    } else if (i % 5 === 0) {
      out.push("Buzz");
    } else if (i % 15 === 0) {
      out.push("FizzBuzz");
    } else {
      out.push(String(i));
    }
  }
  return out;
}

function main(): void {
  const { values } = parseArgs({
    options: {
      n: { type: "string", default: "20" },
      help: { type: "boolean", default: false },
    },
  });

  if (values.help) {
    console.log(
      "Usage: npx tsx fizzbuzz.ts [--n N]\n\n" +
        "Print the FizzBuzz sequence up to N (inclusive). N defaults to 20.",
    );
    return;
  }

  const result = fizzbuzz(Number(values.n));
  console.log(result.join(" "));
}

// Run only when executed directly (the analog of Python's `__main__` guard).
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
