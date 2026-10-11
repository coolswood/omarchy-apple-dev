#!/usr/bin/env python3
"""Compare two PNGs under the simview golden tolerance.

Tolerance, stated here and enforced below:
  - at most MAX_DIFFERING_PIXELS pixels may differ at all
  - every channel of every pixel may differ by at most MAX_CHANNEL_DIFF

Exit 0 when within tolerance, 1 otherwise (or on any size mismatch).
"""
import sys

from PIL import Image

MAX_CHANNEL_DIFF = 0
MAX_DIFFERING_PIXELS = 0


def fail(msg: str) -> None:
    print(f"FAIL {msg}")
    sys.exit(1)


def main() -> None:
    a = Image.open(sys.argv[1]).convert("RGBA")
    b = Image.open(sys.argv[2]).convert("RGBA")
    if a.size != b.size:
        fail(f"size {a.size[0]}x{a.size[1]} != {b.size[0]}x{b.size[1]}")
    pa, pb = a.tobytes(), b.tobytes()
    bad = 0
    max_diff = 0
    for i in range(0, len(pa), 4):
        px = 0
        for c in range(4):
            d = abs(pa[i + c] - pb[i + c])
            if d > max_diff:
                max_diff = d
            px = max(px, d)
        if px > 0:
            bad += 1
    if bad > MAX_DIFFERING_PIXELS or max_diff > MAX_CHANNEL_DIFF:
        fail(f"{a.size[0]}x{a.size[1]}: {bad} differing pixels "
             f"(limit {MAX_DIFFERING_PIXELS}), max channel diff {max_diff} "
             f"(limit {MAX_CHANNEL_DIFF})")
    print(f"ok   {a.size[0]}x{a.size[1]}: {bad} differing pixels "
          f"(limit {MAX_DIFFERING_PIXELS}), max channel diff {max_diff} "
          f"(limit {MAX_CHANNEL_DIFF})")


if __name__ == "__main__":
    main()
