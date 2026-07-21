"""Generate a pencil/graphite stroke texture (RGBA strip) to map along GP strokes.
Solid graphite core + softly feathered edges + along-length grain/skips.
Alpha carries the mark; RGB is graphite. System python + PIL.
"""
from PIL import Image
import os, math, random

random.seed(7)
HERE = os.path.dirname(os.path.abspath(__file__))
W, H = 1024, 128
img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
px = img.load()

def wave(u, scale, seed):
    return math.sin(u*scale + seed)*0.6 + math.sin(u*scale*2.3 + seed*1.7)*0.4

for u in range(W):
    center = H/2 + wave(u, 0.02, 3.0) * 3.0          # gentle centerline wander
    half   = H/2 * (0.80 + 0.15*(0.5+0.5*wave(u, 0.015, 9.0)))  # fairly uniform width
    # along-length grain: gritty modulation + occasional pencil "skips"
    grit = 0.80 + 0.20*(0.5+0.5*math.sin(u*0.15 + 1.0))
    skip = 1.0
    if random.random() < 0.05:
        skip = random.uniform(0.35, 0.6)
    for v in range(H):
        dist = abs(v - center)
        if dist > half:
            continue
        edge = 1.0 - (dist/half)
        profile = min(1.0, edge * 1.7)                # solid core, feathered edge
        speck = 0.82 + 0.18*random.random()           # subtle graphite tooth
        a = profile * grit * speck * skip
        a = max(0.0, min(1.0, a))
        g = int(28 + 16*random.random())              # dark graphite
        px[u, v] = (g, g-3, g-6, int(a*255))

out = os.path.join(HERE, "pencil_tex.png")
img.save(out)
print("wrote", out, img.size)
