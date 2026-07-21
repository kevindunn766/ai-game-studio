"""Contact sheet of sampled animation frames. System python + PIL."""
from PIL import Image, ImageDraw
import os
HERE = os.path.dirname(os.path.abspath(__file__))
FR = os.path.join(HERE, "face_frames")
picks = [(1,"start"),(45,"blink"),(72,"speak"),(100,"gaze L"),
         (150,"speak"),(205,"speak"),(230,"gaze R"),(300,"speak"),(360,"end")]
cell = (200, 257)
cols, rows = 3, 3
pad = 8
W = cols*cell[0] + (cols+1)*pad
H = rows*cell[1] + (rows+1)*pad
sheet = Image.new("RGB", (W, H), (30,30,34))
d = ImageDraw.Draw(sheet)
for i,(fn,label) in enumerate(picks):
    p = os.path.join(FR, f"f_{fn:04d}.png")
    if not os.path.exists(p): continue
    im = Image.open(p).convert("RGB").resize(cell)
    r, c = divmod(i, cols)
    x = pad + c*(cell[0]+pad); y = pad + r*(cell[1]+pad)
    sheet.paste(im, (x, y))
    d.text((x+6, y+6), f"{fn} {label}", fill=(230,120,90))
out = os.path.join(HERE, "montage.png")
sheet.save(out)
print("wrote", out)
