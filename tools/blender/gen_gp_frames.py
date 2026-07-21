"""Generate stand-in 'artwork' frames (high-contrast silhouettes) to trace into
Grease Pencil. Stands in for diffusion output. System python + PIL.
Bouncing ball: squash/stretch + vertical position over 5 frames.
"""
from PIL import Image, ImageDraw
import os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gp_src")
os.makedirs(OUT, exist_ok=True)
W = H = 1000
SS = 4  # supersample factor for antialiased (smooth, non-blocky) edges

# (center_y, half_width, half_height) per frame: fall -> squash -> rebound
# scaled to the 1000px canvas
frames = [
    (300, 175, 180),   # up, round
    (525, 185, 165),   # falling, slight stretch
    (750, 240, 100),   # impact, squashed wide
    (525, 170, 185),   # rebound, stretched tall
    (300, 175, 180),   # back up, round
]

for i, (cy, hw, hh) in enumerate(frames):
    # draw big, then downscale -> smooth antialiased edges (round, not blocky)
    big = Image.new("RGB", (W*SS, H*SS), (255, 255, 255))
    d = ImageDraw.Draw(big)
    cx = 500
    d.ellipse([(cx-hw)*SS, (cy-hh)*SS, (cx+hw)*SS, (cy+hh)*SS], fill=(15, 15, 15))
    d.ellipse([(cx+30)*SS, (cy-60)*SS, (cx+85)*SS, (cy-5)*SS], fill=(255, 255, 255))
    img = big.resize((W, H), Image.LANCZOS)
    p = os.path.join(OUT, f"ball_{i:02d}.png")
    img.save(p)
    print("wrote", p)
print("DONE")
