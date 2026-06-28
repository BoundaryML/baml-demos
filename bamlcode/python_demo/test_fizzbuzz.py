"""Tests for fizzbuzz.py — uses stdlib unittest (no external dependencies).

Run with:
    python3 -m unittest test_fizzbuzz.py -v
"""

import unittest

from fizzbuzz import fizzbuzz


class TestFizzBuzzSequence(unittest.TestCase):
    """Verify correct output values at key positions."""

    def setUp(self):
        self.seq15 = fizzbuzz(15)
        self.seq20 = fizzbuzz(20)

    def test_plain_number(self):
        """Numbers not divisible by 3 or 5 should appear as strings."""
        self.assertEqual(self.seq15[0], "1")   # 1
        self.assertEqual(self.seq15[1], "2")   # 2
        self.assertEqual(self.seq15[3], "4")   # 4

    def test_fizz(self):
        """Multiples of 3 (but not 15) should be 'Fizz'."""
        self.assertEqual(self.seq15[2], "Fizz")   # 3
        self.assertEqual(self.seq15[5], "Fizz")   # 6
        self.assertEqual(self.seq15[8], "Fizz")   # 9
        self.assertEqual(self.seq15[11], "Fizz")  # 12

    def test_buzz(self):
        """Multiples of 5 (but not 15) should be 'Buzz'."""
        self.assertEqual(self.seq15[4], "Buzz")   # 5
        self.assertEqual(self.seq15[9], "Buzz")   # 10
        self.assertEqual(self.seq20[19], "Buzz")  # 20

    def test_fizzbuzz(self):
        """Multiples of 15 should be 'FizzBuzz' (the previously buggy case)."""
        self.assertEqual(self.seq15[14], "FizzBuzz")  # 15
        seq30 = fizzbuzz(30)
        self.assertEqual(seq30[29], "FizzBuzz")       # 30

    def test_sequence_length(self):
        """Returned list should contain exactly n elements."""
        for n in [1, 5, 15, 20, 100]:
            with self.subTest(n=n):
                self.assertEqual(len(fizzbuzz(n)), n)


class TestFizzBuzzEdgeCases(unittest.TestCase):
    """Boundary and single-element cases."""

    def test_n_equals_1(self):
        self.assertEqual(fizzbuzz(1), ["1"])

    def test_n_equals_3(self):
        self.assertEqual(fizzbuzz(3), ["1", "2", "Fizz"])

    def test_n_equals_5(self):
        self.assertEqual(fizzbuzz(5), ["1", "2", "Fizz", "4", "Buzz"])

    def test_n_equals_15(self):
        expected_tail = ["Buzz", "11", "Fizz", "13", "14", "FizzBuzz"]
        self.assertEqual(fizzbuzz(15)[9:], expected_tail)


class TestFizzBuzzInputValidation(unittest.TestCase):
    """fizzbuzz() should raise on bad input."""

    def test_raises_type_error_for_float(self):
        with self.assertRaises(TypeError):
            fizzbuzz(5.0)

    def test_raises_type_error_for_string(self):
        with self.assertRaises(TypeError):
            fizzbuzz("10")

    def test_raises_value_error_for_zero(self):
        with self.assertRaises(ValueError):
            fizzbuzz(0)

    def test_raises_value_error_for_negative(self):
        with self.assertRaises(ValueError):
            fizzbuzz(-1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
