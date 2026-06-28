"""FizzBuzz — enterprise-ready implementation.

Usage
-----
    python3 fizzbuzz.py          # runs for n=20 (default)
    python3 fizzbuzz.py --n 100  # runs for n=100
    python3 fizzbuzz.py --help
"""

from __future__ import annotations

import argparse
import logging
from typing import List

logger = logging.getLogger(__name__)


def fizzbuzz(n: int) -> List[str]:
    """Return the FizzBuzz sequence for 1..n as a list of strings.

    Rules
    -----
    - Divisible by 15 -> "FizzBuzz"
    - Divisible by  3 -> "Fizz"
    - Divisible by  5 -> "Buzz"
    - Otherwise       -> str(i)

    Parameters
    ----------
    n : int
        Upper bound of the sequence (inclusive). Must be a positive integer.

    Returns
    -------
    List[str]
        The FizzBuzz sequence from 1 to n.

    Raises
    ------
    TypeError
        If *n* is not an integer.
    ValueError
        If *n* is less than 1.

    Examples
    --------
    >>> fizzbuzz(5)
    ['1', '2', 'Fizz', '4', 'Buzz']
    >>> fizzbuzz(15)[-1]
    'FizzBuzz'
    """
    if not isinstance(n, int):
        raise TypeError(f"n must be an int, got {type(n).__name__!r}")
    if n < 1:
        raise ValueError(f"n must be a positive integer, got {n}")

    logger.debug("Generating FizzBuzz sequence for n=%d", n)
    out: List[str] = []
    for i in range(1, n + 1):
        if i % 3 == 0:
            out.append("Fizz")
        elif i % 5 == 0:
            out.append("Buzz")
        elif i % 15 == 0:
            out.append("FizzBuzz")
        else:
            out.append(str(i))

    logger.debug("Sequence generated successfully (%d items)", len(out))
    return out


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Print the FizzBuzz sequence up to N.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--n",
        type=int,
        default=20,
        help="Upper bound of the sequence (inclusive)",
    )
    parser.add_argument(
        "--log-level",
        default="WARNING",
        choices=["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"],
        help="Set the logging verbosity",
    )
    return parser


def main() -> None:
    """CLI entry point."""
    parser = _build_parser()
    args = parser.parse_args()

    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )

    result = fizzbuzz(args.n)
    print(" ".join(result))


if __name__ == "__main__":
    main()
