#!/usr/bin/env python3
# Deterministic cel-shaded ground-patch generator for Kindling.
# Draws ONE top-down organic patch (moss / grass / rock / dirt / pebble) as a hard-edged
# cel-shaded blob (3 flat shades) on a #FF00FF transparent field, kept well clear of the
# image edges. Uses the studio PixelEngine (palette-indexed, #FF00FF transparency).
#
#   python tools/gen_kindling_ground_patch.py <material> <output.png> [variant]
import sys, math
from pixel_art_engine import PixelEngine

SIZE = 96

# dark, mid, light -- cel shades per material (hex). Moss is high-chroma green.
PALETTES = {
    "moss":  ("#1f7a2e", "#33b03c", "#7ee04e"),
    "grass": ("#356e2a", "#57a838", "#93d24c"),
    "rock":  ("#45454b", "#6d6d73", "#9c9ca2"),
    "dirt":  ("#553824", "#7c5634", "#a97d4c"),
    "pebble":("#5c5148", "#867567", "#b3a290"),
}


# Per-variant outline so a material has several distinct blob shapes.
def _outline(variant, ang, seed, R):
    if variant == 1:                     # pointier star (the original patch style)
        return R * (0.68
                    + 0.18 * math.sin(ang * 4.0 + seed)
                    + 0.10 * math.sin(ang * 7.0 - seed * 0.5)
                    + 0.06 * math.sin(ang * 13.0 + seed * 0.3))
    if variant == 2:                     # lumpy, slightly oval
        oval = 1.0 + 0.14 * math.cos(2.0 * ang + seed * 0.2)
        return R * 0.94 * oval * (0.82
                                  + 0.09 * math.sin(ang * 3.0 + seed)
                                  + 0.05 * math.sin(ang * 5.0 - seed * 0.4))
    return R * (0.84                      # rounded organic
                + 0.10 * math.sin(ang * 2.0 + seed)
                + 0.06 * math.sin(ang * 3.5 - seed * 0.5)
                + 0.035 * math.sin(ang * 6.0 + seed * 0.3))


def gen(material, out_path, variant=0):
    dark, mid, light = PALETTES[material]
    eng = PixelEngine(SIZE, SIZE, palette=["#FF00FF", dark, mid, light])
    seed = float(sum(ord(c) for c in material)) + variant * 23.7
    cx = cy = SIZE / 2.0
    R = SIZE * 0.40                      # base radius -> leaves a clear transparent border

    for y in range(SIZE):
        for x in range(SIZE):
            dx = x - cx + 0.5
            dy = y - cy + 0.5
            d = math.hypot(dx, dy)
            ang = math.atan2(dy, dx)
            outline = _outline(variant, ang, seed, R)
            if d > outline:
                continue                 # leave transparent (#FF00FF)
            # Coarse value field -> 3 hard cel bands, darker toward the rim.
            n = (0.5
                 + 0.22 * math.sin(x * 0.34 + seed)
                 + 0.22 * math.cos(y * 0.30 - seed * 0.7)
                 + 0.16 * math.sin((x + y) * 0.18 + seed * 0.2)
                 + 0.12 * math.sin((x - y) * 0.27 - seed * 0.4))
            val = n - 0.35 * (d / max(outline, 1.0))
            if val < 0.42:
                c = dark
            elif val < 0.72:
                c = mid
            else:
                c = light
            eng.set_pixel(x, y, c)

    eng.save(out_path)
    print("wrote", out_path, "(" + material + " v" + str(variant) + ")")


if __name__ == "__main__":
    v = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    gen(sys.argv[1], sys.argv[2], v)
