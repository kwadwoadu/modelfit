---
id: example-chunk
category: surgical-correctness
scoring: judge
---

# PROMPT
Write a single TypeScript function with this exact signature:

    function chunk<T>(arr: T[], size: number): T[][]

It splits `arr` into consecutive sub-arrays of length `size`. The final chunk may be
shorter when the array does not divide evenly. If `size` is not a positive integer
(zero, negative, or non-integer), throw a `RangeError`. An empty input array returns
an empty array.

Output ONLY the function. No prose, no tests, no usage example.

# RUBRIC
Discriminator: the `size <= 0` guard. A naive implementation loops `i += size` and
either infinite-loops or returns garbage when `size` is 0 or negative; many also skip
the non-integer check.

PASS requires ALL of:
- M1 Signature is exactly `function chunk<T>(arr: T[], size: number): T[][]` (generic preserved).
- M2 Correctly chunks a non-evenly-divisible array, last chunk shorter (e.g. [1,2,3,4,5] size 2 -> [[1,2],[3,4],[5]]).
- M3 Throws `RangeError` when `size` is 0, negative, or non-integer (e.g. checks `!Number.isInteger(size) || size <= 0`).
- M4 Empty input array returns `[]` (no throw).
- M5 Code compiles as written: valid TypeScript, no undefined symbols, no missing return.

FAIL if: the guard is missing or only checks `size === 0`; an infinite loop is possible
for size <= 0; the non-integer case is unhandled; the signature was changed; or prose/tests
were included against the instruction (prose alone = instruction-following ding, not auto-FAIL,
unless it breaks "output ONLY the function").

Quality pluses (do not gate): single clean pass with `slice`; clear error message;
no needless allocation.
