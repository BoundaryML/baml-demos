/**
 * Tests for fizzbuzz.ts — uses Node's built-in test runner (no external deps).
 *
 * Run with:
 *     npx tsx --test test_fizzbuzz.ts
 *     # or just: npx tsx test_fizzbuzz.ts
 */
import { describe, it } from "node:test";
import assert from "node:assert/strict";

import { fizzbuzz } from "./fizzbuzz.js";

describe("FizzBuzz sequence", () => {
  const seq15 = fizzbuzz(15);
  const seq20 = fizzbuzz(20);

  it("plain numbers appear as strings", () => {
    assert.equal(seq15[0], "1"); // 1
    assert.equal(seq15[1], "2"); // 2
    assert.equal(seq15[3], "4"); // 4
  });

  it("multiples of 3 (but not 15) are 'Fizz'", () => {
    assert.equal(seq15[2], "Fizz"); // 3
    assert.equal(seq15[5], "Fizz"); // 6
    assert.equal(seq15[8], "Fizz"); // 9
    assert.equal(seq15[11], "Fizz"); // 12
  });

  it("multiples of 5 (but not 15) are 'Buzz'", () => {
    assert.equal(seq15[4], "Buzz"); // 5
    assert.equal(seq15[9], "Buzz"); // 10
    assert.equal(seq20[19], "Buzz"); // 20
  });

  it("multiples of 15 are 'FizzBuzz' (the previously buggy case)", () => {
    assert.equal(seq15[14], "FizzBuzz"); // 15
    const seq30 = fizzbuzz(30);
    assert.equal(seq30[29], "FizzBuzz"); // 30
  });

  it("returns exactly n elements", () => {
    for (const n of [1, 5, 15, 20, 100]) {
      assert.equal(fizzbuzz(n).length, n);
    }
  });
});

describe("FizzBuzz edge cases", () => {
  it("n = 1", () => assert.deepEqual(fizzbuzz(1), ["1"]));
  it("n = 3", () => assert.deepEqual(fizzbuzz(3), ["1", "2", "Fizz"]));
  it("n = 5", () => assert.deepEqual(fizzbuzz(5), ["1", "2", "Fizz", "4", "Buzz"]));
  it("n = 15 tail", () => {
    const expectedTail = ["Buzz", "11", "Fizz", "13", "14", "FizzBuzz"];
    assert.deepEqual(fizzbuzz(15).slice(9), expectedTail);
  });
});

describe("FizzBuzz input validation", () => {
  it("throws TypeError for a non-integer number", () => {
    assert.throws(() => fizzbuzz(5.5), TypeError);
  });
  it("throws TypeError for a string", () => {
    assert.throws(() => fizzbuzz("10" as unknown as number), TypeError);
  });
  it("throws RangeError for zero", () => {
    assert.throws(() => fizzbuzz(0), RangeError);
  });
  it("throws RangeError for a negative number", () => {
    assert.throws(() => fizzbuzz(-1), RangeError);
  });
});
