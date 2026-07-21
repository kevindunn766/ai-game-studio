"""Procedural front-facing anime face + viseme mouth shapes -> face_shapes.json.
Pure python (math only). Coordinate space: x right, y up, face ~[-1.2,1.3].
Each stroke = {"pts":[[x,y],...], "w":width_scale, "cyclic":bool}.
"""
import math, json, os

HERE = os.path.dirname(os.path.abspath(__file__))

# ---------- helpers ----------
def arc(cx, cy, rx, ry, a0, a1, n):
    return [[cx + rx*math.cos(a0 + (a1-a0)*i/(n-1)),
             cy + ry*math.sin(a0 + (a1-a0)*i/(n-1))] for i in range(n)]

def ellipse(cx, cy, rx, ry, n):
    return [[cx + rx*math.cos(2*math.pi*i/n), cy + ry*math.sin(2*math.pi*i/n)] for i in range(n)]

def catmull(points, closed, spp=12):
    p = list(points)
    if closed:
        pts = [p[-1]] + p + [p[0], p[1]]
        rng = range(1, len(pts)-2)
    else:
        pts = [p[0]] + p + [p[-1]]
        rng = range(1, len(pts)-2)
    out = []
    for i in rng:
        p0, p1, p2, p3 = pts[i-1], pts[i], pts[i+1], pts[i+2]
        for t in range(spp):
            s = t/spp
            s2, s3 = s*s, s*s*s
            x = 0.5*((2*p1[0])+(-p0[0]+p2[0])*s+(2*p0[0]-5*p1[0]+4*p2[0]-p3[0])*s2+(-p0[0]+3*p1[0]-3*p2[0]+p3[0])*s3)
            y = 0.5*((2*p1[1])+(-p0[1]+p2[1])*s+(2*p0[1]-5*p1[1]+4*p2[1]-p3[1])*s2+(-p0[1]+3*p1[1]-3*p2[1]+p3[1])*s3)
            out.append([x, y])
    if not closed:
        out.append(list(p[-1]))
    return out

def S(pts, w=1.0, cyclic=False, fill=False):
    return {"pts": pts, "w": w, "cyclic": cyclic, "fill": fill}

# ---------- static face ----------
static = []

# face outline (anime egg + tapered chin), smoothed closed
face_anchors = [
    [0.00, 1.03], [0.60, 0.86], [0.80, 0.36], [0.76, -0.14],
    [0.55, -0.60], [0.28, -1.00], [0.00, -1.12], [-0.28, -1.00],
    [-0.55, -0.60], [-0.76, -0.14], [-0.80, 0.36], [-0.60, 0.86],
]
static.append(S(catmull(face_anchors, True, 16), w=1.15, cyclic=True))

# hair: ONE smooth closed silhouette (crown + gently scalloped bangs)
hair_anchors = [
    [-0.80,0.42],[-0.55,1.05],[0.0,1.26],[0.55,1.05],[0.80,0.42],   # crown
    [0.52,0.40],[0.40,0.52],[0.22,0.34],[0.06,0.52],                # bangs R->L
    [-0.10,0.34],[-0.28,0.52],[-0.46,0.36],[-0.62,0.50],
]
static.append(S(catmull(hair_anchors, True, 12), w=1.15, cyclic=True))
# subtle center-part strand hints
static.append(S(catmull([[-0.06,1.06],[-0.16,0.74],[-0.20,0.52]], False, 8), w=0.6))
static.append(S(catmull([[0.08,1.06],[0.18,0.74],[0.22,0.52]], False, 8), w=0.6))
# side locks framing the cheeks
static.append(S(catmull([[0.80,0.42],[0.90,0.02],[0.82,-0.40],[0.70,-0.58]], False, 12), w=1.0))
static.append(S(catmull([[-0.80,0.42],[-0.90,0.02],[-0.82,-0.40],[-0.70,-0.58]], False, 12), w=1.0))

# eyebrows
static.append(S(catmull([[0.18,0.20],[0.36,0.28],[0.54,0.24]], False, 10), w=1.0))
static.append(S(catmull([[-0.18,0.20],[-0.36,0.28],[-0.54,0.24]], False, 10), w=1.0))

# nose: subtle short line
static.append(S([[0.03,-0.36],[-0.02,-0.46]], w=0.7))

# ---------- eyes ----------
EY = -0.02          # eye center y
EX = 0.36           # eye center x offset
def one_eye(cx, cy, iris_dx=0.0):
    strokes = []
    # upper lid (bold arc)
    strokes.append(S(catmull([[cx-0.19,cy+0.03],[cx-0.02,cy+0.17],[cx+0.17,cy+0.10]], False, 12), w=1.7))
    # outer corner lash
    strokes.append(S([[cx+0.17,cy+0.10],[cx+0.24,cy+0.12]], w=1.4))
    # lower lid (short shallow)
    strokes.append(S(catmull([[cx-0.14,cy-0.08],[cx+0.02,cy-0.12],[cx+0.15,cy-0.07]], False, 10), w=0.9))
    # iris (tall ellipse), pupil, highlight glint - shifted by iris_dx for gaze
    ix = cx + iris_dx
    strokes.append(S(ellipse(ix, cy-0.005, 0.11, 0.13, 26), w=1.1, cyclic=True))
    strokes.append(S(ellipse(ix, cy-0.02, 0.042, 0.05, 16), w=1.0, cyclic=True, fill=True))
    strokes.append(S(ellipse(ix-0.05, cy+0.055, 0.032, 0.035, 12), w=0.9, cyclic=True))
    return strokes

def closed_eye(cx, cy):
    return [
        S(catmull([[cx-0.19,cy+0.02],[cx-0.01,cy-0.07],[cx+0.18,cy+0.02]], False, 12), w=1.6),
        S([[cx+0.18,cy+0.02],[cx+0.25,cy+0.05]], w=1.3),
    ]

eyes_open  = one_eye(EX, EY, 0.0)  + one_eye(-EX, EY, 0.0)
eyes_LL    = one_eye(EX, EY, -0.05) + one_eye(-EX, EY, -0.05)
eyes_LR    = one_eye(EX, EY, 0.05) + one_eye(-EX, EY, 0.05)
eyes_closed= closed_eye(EX, EY)    + closed_eye(-EX, EY)

# ---------- mouths (viseme shapes) ----------
MY = -0.72
def lips(w, h, tongue=False):
    # dark-filled interior reads as an open anime mouth
    strokes = [S(ellipse(0.0, MY, w, h, 28), w=1.05, cyclic=True, fill=True)]
    if tongue:
        strokes.append(S(arc(0.0, MY-h*0.3, w*0.5, h*0.34, math.radians(205), math.radians(335), 8), w=0.8))
    return strokes

def line_mouth(w, dip=0.02):
    return [S(catmull([[-w,MY+0.01],[0,MY-dip],[w,MY+0.01]], False, 8), w=1.0)]

def fv_mouth(w):
    return [S(catmull([[-w,MY+0.01],[0,MY-0.02],[w,MY+0.01]], False, 8), w=1.0),
            S([[-w*0.7,MY+0.055],[w*0.7,MY+0.055]], w=0.6)]  # upper teeth on lip

mouths = {
    "CLOSED":      line_mouth(0.16, 0.02),
    "SLIGHT":      lips(0.12, 0.05),
    "WIDE":        lips(0.19, 0.07),
    "OPEN_MID":    lips(0.13, 0.13),
    "OPEN_BIG":    lips(0.15, 0.21),
    "ROUND_SMALL": lips(0.075, 0.085),
    "ROUND_BIG":   lips(0.11, 0.135),
    "FV":          fv_mouth(0.15),
    "L":           lips(0.12, 0.11, tongue=True),
    "TH":          lips(0.12, 0.06, tongue=True),
}

# SAPI viseme id (0..21) -> mouth shape
viseme_map = {
    0:"CLOSED", 1:"OPEN_MID", 2:"OPEN_BIG", 3:"ROUND_BIG", 4:"OPEN_MID",
    5:"SLIGHT", 6:"WIDE", 7:"ROUND_SMALL", 8:"ROUND_BIG", 9:"OPEN_BIG",
    10:"ROUND_BIG", 11:"OPEN_MID", 12:"OPEN_MID", 13:"SLIGHT", 14:"L",
    15:"SLIGHT", 16:"ROUND_SMALL", 17:"TH", 18:"FV", 19:"SLIGHT",
    20:"SLIGHT", 21:"CLOSED",
}

out = {
    "static": static,
    "eyes_open": eyes_open, "eyes_look_left": eyes_LL,
    "eyes_look_right": eyes_LR, "eyes_closed": eyes_closed,
    "mouths": mouths, "viseme_map": {str(k): v for k, v in viseme_map.items()},
}
path = os.path.join(HERE, "face_shapes.json")
json.dump(out, open(path, "w"))
print("wrote", path)
print("static strokes:", len(static), "| mouth shapes:", len(mouths))
