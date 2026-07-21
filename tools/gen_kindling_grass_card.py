#!/usr/bin/env python3
# Deterministic grass-tuft CARD generator for Kindling (side view, for a standing quad card).
# Draws a fan of cel-shaded blades rising from the base-centre on a #FF00FF transparent field,
# darker at the root -> lighter at the tips (3 flat shades). Uses the studio PixelEngine
# (palette-indexed, #FF00FF transparency). Several variants give a lush, non-repeating field.
#
#   python tools/gen_kindling_grass_card.py <output.png> [variant]
import sys, math, random
from pixel_art_engine import PixelEngine

SIZE = 96

# root(dark) / blade(mid) / tip(light) -- lush BRIGHT greens, slight per-variant hue shift.
# Kept light: the dark shade is only the very base, so dense tufts don't read black/twiggy.
PALETTES = [
    ("#3a7a34", "#5fa83e", "#9ad452"),
    ("#40803a", "#63ad3f", "#a0d94b"),
    ("#387a42", "#54a052", "#8fd070"),
]


def gen(out_path, variant=0):
    dark, mid, light = PALETTES[variant % len(PALETTES)]
    eng = PixelEngine(SIZE, SIZE, palette=["#FF00FF", dark, mid, light])
    rng = random.Random(1000 + variant)

    base_y = SIZE - 2                       # blades root just off the bottom edge
    n_blades = 9 + variant % 3
    # A spread of blades: mostly central, fanning outward, varied height + lean + curve.
    for b in range(n_blades):
        x0 = SIZE * rng.uniform(0.26, 0.74)
        height = SIZE * rng.uniform(0.52, 0.94)
        lean = rng.uniform(-0.30, 0.30)     # sideways drift toward the tip (fraction of SIZE)
        wiggle = rng.uniform(0.0, 2.2)
        wfreq = rng.uniform(2.0, 4.0)
        basew = rng.uniform(1.8, 3.4)       # half-width at the root, tapers to a point
        cshift = rng.uniform(-0.08, 0.08)   # per-blade cel-band bias
        steps = int(height)
        for s in range(steps + 1):
            t = float(s) / max(height, 1.0)                 # 0 root -> 1 tip
            y = int(round(base_y - s))
            cx = x0 + lean * SIZE * (t * t) + wiggle * math.sin(t * math.pi * wfreq)
            hw = max(0.5, basew * (1.0 - t))
            # Cel band by height: only the very base is dark, then mid, bright tips.
            val = t + cshift
            col = dark if val < 0.24 else (mid if val < 0.68 else light)
            x_lo = int(math.floor(cx - hw))
            x_hi = int(math.ceil(cx + hw))
            for xx in range(x_lo, x_hi + 1):
                if 0 <= xx < SIZE and 0 <= y < SIZE:
                    eng.set_pixel(xx, y, col)

    eng.save(out_path)
    print("wrote", out_path, "(grass card v" + str(variant) + ")")


if __name__ == "__main__":
    v = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    gen(sys.argv[1], v)
