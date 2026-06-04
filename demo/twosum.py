#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = []
# ///
"""Demo: solving the Two Sum problem.

Given a list of integers and a target value, find the two indices whose
elements add up to the target.  Three approaches are shown:

  1. Brute-force  O(n²)
  2. Hash-map      O(n)   ← the classic interview answer
  3. Sorted + two-pointer  O(n log n)  (returns values, not original indices)

Run:
  python twosum.py
  # or, if uv is available:
  uv run twosum.py
"""

from __future__ import annotations


# ---------------------------------------------------------------------------
# Approach 1 – Brute force  O(n²)
# ---------------------------------------------------------------------------

def two_sum_brute(nums: list[int], target: int) -> tuple[int, int] | None:
    """Return (i, j) with i < j such that nums[i] + nums[j] == target."""
    for i in range(len(nums)):
        for j in range(i + 1, len(nums)):
            if nums[i] + nums[j] == target:
                return (i, j)
    return None


# ---------------------------------------------------------------------------
# Approach 2 – Hash-map  O(n)
# ---------------------------------------------------------------------------

def two_sum_hashmap(nums: list[int], target: int) -> tuple[int, int] | None:
    """Single-pass hash-map lookup.  Returns (i, j) with i < j."""
    seen: dict[int, int] = {}          # value -> index
    for j, num in enumerate(nums):
        complement = target - num
        if complement in seen:
            return (seen[complement], j)
        seen[num] = j
    return None


# ---------------------------------------------------------------------------
# Approach 3 – Sorted two-pointer  O(n log n)
#              (works on values; rebuilds original indices at the end)
# ---------------------------------------------------------------------------

def two_sum_two_pointer(nums: list[int], target: int) -> tuple[int, int] | None:
    """Sort a copy, use two pointers, then map back to original indices."""
    indexed = sorted(enumerate(nums), key=lambda x: x[1])  # (orig_idx, val)
    lo, hi = 0, len(indexed) - 1
    while lo < hi:
        s = indexed[lo][1] + indexed[hi][1]
        if s == target:
            i, j = indexed[lo][0], indexed[hi][0]
            return (min(i, j), max(i, j))
        elif s < target:
            lo += 1
        else:
            hi -= 1
    return None


# ---------------------------------------------------------------------------
# Demo runner
# ---------------------------------------------------------------------------

TEST_CASES: list[tuple[list[int], int]] = [
    ([2, 7, 11, 15], 9),          # classic LeetCode example  → (0, 1)
    ([3, 2, 4], 6),               # non-adjacent pair         → (1, 2)
    ([3, 3], 6),                  # duplicate values          → (0, 1)
    ([1, 5, 3, 7, 2, 9], 10),     # longer list               → (1, 3)  5+7
    ([1, 2, 3], 100),             # no solution               → None
]

SOLVERS = [
    ("brute-force  O(n²)",       two_sum_brute),
    ("hash-map     O(n) ",       two_sum_hashmap),
    ("two-pointer  O(n log n)",  two_sum_two_pointer),
]


def main() -> None:
    header = f"{'nums':<30}  {'target':>6}  {'brute':>10}  {'hashmap':>10}  {'2-ptr':>10}"
    print(header)
    print("-" * len(header))

    for nums, target in TEST_CASES:
        results = [solver(list(nums), target) for _, solver in SOLVERS]
        # Verify each result is correct (values sum to target, or both None)
        for (name, _), r in zip(SOLVERS, results):
            if r is None:
                assert all(res is None for res in results), (
                    f"{name}: returned None but another solver found a result"
                )
            else:
                i, j = r
                assert nums[i] + nums[j] == target, (
                    f"{name}: nums[{i}]+nums[{j}]={nums[i]+nums[j]} != {target}"
                )
        cols = "  ".join(f"{str(r):>10}" for r in results)
        print(f"{str(nums):<30}  {target:>6}  {cols}")

    print("\nAll solvers agree on every test case. ✓")

    # -----------------------------------------------------------------
    # Walk through the hash-map approach step-by-step for one example
    # -----------------------------------------------------------------
    print("\n── Step-by-step trace (hash-map, nums=[2,7,11,15], target=9) ──")
    nums_trace = [2, 7, 11, 15]
    target_trace = 9
    seen: dict[int, int] = {}
    for j, num in enumerate(nums_trace):
        complement = target_trace - num
        print(f"  j={j}  num={num}  complement={complement}  seen={seen}")
        if complement in seen:
            i = seen[complement]
            print(f"  → found! indices ({i}, {j})  "
                  f"nums[{i}]+nums[{j}] = {nums_trace[i]}+{nums_trace[j]} = {target_trace}")
            break
        seen[num] = j


if __name__ == "__main__":
    main()
