#!/usr/bin/env python3
# Deterministic BURN-MARK stamp for Kindling: a charred scorch blob (burnt-black core, thin
# irregular ashy rim) on a #FF00FF transparent field, matching shaders/scorch.gdshader's look.
# Used as the decal texture painted onto un-burnable items where the flame brushes them.
#
#   python tools/gen_kindling_burn_mark.py <output.png>
import sys, math
from pixel_art_engine import PixelEngine

SIZE = 96
CHAR = "#0d0a09"    # burnt core   (scorch.gdshader char_col 0.05,0.04,0.035)
ASH = "#383029"     # ashy rim     (scorch.gdshader ash_col 0.22,0.19,0.16)
SEED = 3.0


def gen(out_path):
    eng = PixelEngine(SIZE, SIZE, palette=["#FF00FF", CHAR, ASH])
    cx = cy = SIZE / 2.0
    for y in range(SIZE):
        for x in range(SIZE):
            px = (x + 0.5 - cx) / (SIZE * 0.5)
            py = (y + 0.5 - cy) / (SIZE * 0.5)
            r = math.hypot(px, py)                       # 0 centre .. 1 edge
            ang = math.atan2(py, px)
            edge = 0.9 + 0.08 * math.sin(ang * 6.0 + SEED * 20.0) + 0.04 * math.sin(ang * 13.0 - SEED * 11.0)
            if r > edge:
                continue                                 # transparent outside the blob
            nr = r / max(edge, 0.001)
            ash_thresh = (0.90 + 0.10 * math.sin(ang * 7.0 + SEED * 30.0)
                          + 0.07 * math.sin(ang * 23.0 - SEED * 12.0)
                          + 0.05 * math.sin(ang * 43.0 + SEED * 7.0))
            eng.set_pixel(x, y, ASH if nr > ash_thresh else CHAR)
    eng.save(out_path)
    print("wrote", out_path)


if __name__ == "__main__":
    gen(sys.argv[1])
