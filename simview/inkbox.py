#!/usr/bin/env python3
"""Print the bounding box of non-white pixels inside a region of a PNG.

  inkbox.py FILE.png X0 Y0 X1 Y1     region is X0..X1-1 by Y0..Y1-1 (scene points)

Prints "MINX MINY MAXX MAXY" (inclusive), or "none" when the region is blank.
The M7 test uses it to check where text landed without trusting a golden.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from compare import read_png  # noqa: E402


def main() -> None:
    path = sys.argv[1]
    x0, y0, x1, y1 = (int(v) for v in sys.argv[2:6])
    (w, _h), px = read_png(path)
    xs, ys = [], []
    for y in range(y0, y1):
        for x in range(x0, x1):
            i = (y * w + x) * 4
            if px[i:i + 3] != b"\xff\xff\xff":
                xs.append(x)
                ys.append(y)
    print("none" if not xs else f"{min(xs)} {min(ys)} {max(xs)} {max(ys)}")


if __name__ == "__main__":
    main()
