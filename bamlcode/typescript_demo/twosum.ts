/**
 * Demo: solving the Two Sum problem.
 *
 * Given a list of integers and a target value, find the two indices whose
 * elements add up to the target. Three approaches are shown:
 *
 *   1. Brute-force            O(n²)
 *   2. Hash-map               O(n)   ← the classic interview answer
 *   3. Sorted + two-pointer   O(n log n)  (maps back to original indices)
 *
 * Run:
 *   npx tsx twosum.ts
 */
import { fileURLToPath } from "node:url";

type Pair = [number, number];

// ---------------------------------------------------------------------------
// Approach 1 – Brute force  O(n²)
// ---------------------------------------------------------------------------
function twoSumBrute(nums: number[], target: number): Pair | null {
  for (let i = 0; i < nums.length; i++) {
    for (let j = i + 1; j < nums.length; j++) {
      if (nums[i] + nums[j] === target) {
        return [i, j];
      }
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Approach 2 – Hash-map  O(n)
// ---------------------------------------------------------------------------
function twoSumHashmap(nums: number[], target: number): Pair | null {
  const seen = new Map<number, number>(); // value -> index
  for (let j = 0; j < nums.length; j++) {
    const complement = target - nums[j];
    if (seen.has(complement)) {
      return [seen.get(complement)!, j];
    }
    seen.set(nums[j], j);
  }
  return null;
}

// ---------------------------------------------------------------------------
// Approach 3 – Sorted two-pointer  O(n log n)
//              (works on values; rebuilds original indices at the end)
// ---------------------------------------------------------------------------
function twoSumTwoPointer(nums: number[], target: number): Pair | null {
  const indexed = nums
    .map((val, idx): Pair => [idx, val])
    .sort((a, b) => a[1] - b[1]); // [origIdx, val]
  let lo = 0;
  let hi = indexed.length - 1;
  while (lo < hi) {
    const sum = indexed[lo][1] + indexed[hi][1];
    if (sum === target) {
      const [i, j] = [indexed[lo][0], indexed[hi][0]];
      return [Math.min(i, j), Math.max(i, j)];
    } else if (sum < target) {
      lo += 1;
    } else {
      hi -= 1;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Demo runner
// ---------------------------------------------------------------------------
const TEST_CASES: [number[], number][] = [
  [[2, 7, 11, 15], 9], // classic LeetCode example  -> (0, 1)
  [[3, 2, 4], 6], //        non-adjacent pair  -> (1, 2)
  [[3, 3], 6], //              duplicate values  -> (0, 1)
  [[1, 5, 3, 7, 2, 9], 10], //       longer list  -> (1, 3)  5+7
  [[1, 2, 3], 100], //               no solution  -> null
];

const SOLVERS: [string, (nums: number[], target: number) => Pair | null][] = [
  ["brute-force  O(n²)", twoSumBrute],
  ["hash-map     O(n) ", twoSumHashmap],
  ["two-pointer  O(n log n)", twoSumTwoPointer],
];

function pad(s: string, width: number, right = false): string {
  return right ? s.padStart(width) : s.padEnd(width);
}

function show(pair: Pair | null): string {
  return pair === null ? "null" : `(${pair[0]}, ${pair[1]})`;
}

function main(): void {
  const header =
    `${pad("nums", 30)}  ${pad("target", 6, true)}  ` +
    `${pad("brute", 10, true)}  ${pad("hashmap", 10, true)}  ${pad("2-ptr", 10, true)}`;
  console.log(header);
  console.log("-".repeat(header.length));

  for (const [nums, target] of TEST_CASES) {
    const results = SOLVERS.map(([, solver]) => solver([...nums], target));
    // Verify each result is correct (values sum to target, or all are null).
    results.forEach((r, idx) => {
      const name = SOLVERS[idx][0];
      if (r === null) {
        if (!results.every((res) => res === null)) {
          throw new Error(`${name}: returned null but another solver found a result`);
        }
      } else {
        const [i, j] = r;
        if (nums[i] + nums[j] !== target) {
          throw new Error(`${name}: nums[${i}]+nums[${j}]=${nums[i] + nums[j]} != ${target}`);
        }
      }
    });
    const cols = results.map((r) => pad(show(r), 10, true)).join("  ");
    console.log(`${pad(`[${nums.join(", ")}]`, 30)}  ${pad(String(target), 6, true)}  ${cols}`);
  }

  console.log("\nAll solvers agree on every test case. ✓");

  // -----------------------------------------------------------------
  // Walk through the hash-map approach step-by-step for one example
  // -----------------------------------------------------------------
  console.log("\n── Step-by-step trace (hash-map, nums=[2,7,11,15], target=9) ──");
  const numsTrace = [2, 7, 11, 15];
  const targetTrace = 9;
  const seen = new Map<number, number>();
  for (let j = 0; j < numsTrace.length; j++) {
    const num = numsTrace[j];
    const complement = targetTrace - num;
    console.log(`  j=${j}  num=${num}  complement=${complement}  seen=${JSON.stringify([...seen])}`);
    if (seen.has(complement)) {
      const i = seen.get(complement)!;
      console.log(
        `  → found! indices (${i}, ${j})  ` +
          `nums[${i}]+nums[${j}] = ${numsTrace[i]}+${numsTrace[j]} = ${targetTrace}`,
      );
      break;
    }
    seen.set(num, j);
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  main();
}
