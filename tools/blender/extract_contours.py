"""Extract clean, dense, smooth contours from raster frames (bypassing potrace).
numpy + scipy + PIL. Outputs contours.json for Blender to build GP strokes from.

Per frame: fill holes -> outer boundary; hole = filled & ~dark -> inner (eye).
Boundary pixels are ordered by angle around the region centroid (valid for the
star-convex blob/ellipse shapes here), smoothed, and arc-length resampled.
"""
import numpy as np
from scipy import ndimage
from PIL import Image
import json, glob, os

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = sorted(glob.glob(os.path.join(HERE, "gp_src", "ball_*.png")))
W = H = 1000
SCALE = 4.0  # GP-space extent

def to_gp(xs, ys):
    gx = (xs / W - 0.5) * SCALE
    gy = -(ys / H - 0.5) * SCALE   # flip: image y-down -> GP y-up
    return gx, gy

def ordered_boundary(mask):
    er = ndimage.binary_erosion(mask)
    bnd = mask & ~er
    ys, xs = np.nonzero(bnd)
    if len(xs) < 8:
        return None
    cx, cy = xs.mean(), ys.mean()
    ang = np.arctan2(ys - cy, xs - cx)
    order = np.argsort(ang)
    return xs[order].astype(float), ys[order].astype(float)

def smooth_closed(a, sigma):
    return ndimage.gaussian_filter1d(a, sigma, mode='wrap')

def resample_closed(xs, ys, n):
    p = np.stack([xs, ys], 1)
    seg = np.vstack([p, p[0]])
    d = np.sqrt(((seg[1:] - seg[:-1]) ** 2).sum(1))
    cum = np.concatenate([[0], np.cumsum(d)])
    total = cum[-1]
    targets = np.linspace(0, total, n, endpoint=False)
    out = np.empty((n, 2))
    j = 0
    for k, t in enumerate(targets):
        while j + 1 < len(cum) and cum[j + 1] < t:
            j += 1
        f = (t - cum[j]) / max(cum[j + 1] - cum[j], 1e-9)
        out[k] = seg[j] * (1 - f) + seg[j + 1] * f
    return out

def contour_from_mask(mask, n, sigma=2.5):
    ob = ordered_boundary(mask)
    if ob is None:
        return None
    xs, ys = ob
    xs = smooth_closed(xs, sigma)
    ys = smooth_closed(ys, sigma)
    p = resample_closed(xs, ys, n)
    gx, gy = to_gp(p[:, 0], p[:, 1])
    return [[float(x), float(y)] for x, y in zip(gx, gy)]

frames = []
for path in SRC:
    gray = np.array(Image.open(path).convert("L"))
    dark = gray < 128
    filled = ndimage.binary_fill_holes(dark)
    hole = filled & ~dark
    contours = []
    outer = contour_from_mask(filled, 160)
    if outer:
        contours.append({"pts": outer, "cyclic": True})
    if hole.sum() > 30:
        eye = contour_from_mask(hole, 48)
        if eye:
            contours.append({"pts": eye, "cyclic": True})
    # roundness check on outer
    p = np.array(outer)
    c = p.mean(0)
    r = np.sqrt(((p - c) ** 2).sum(1))
    print(f"{os.path.basename(path)}: {len(contours)} contours, outer {len(outer)} pts, "
          f"radius min={r.min():.3f} max={r.max():.3f} (round=>min~max)")
    frames.append({"contours": contours})

out = os.path.join(HERE, "contours.json")
with open(out, "w") as f:
    json.dump({"frames": frames}, f)
print("wrote", out)
