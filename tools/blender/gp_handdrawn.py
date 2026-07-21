"""Hand-drawn version of the traced ball animation.
Trace -> read outline -> Chaikin round + densify -> smooth -> hand wobble ->
thin rounded ink stroke (no fill). Run: blender --background --python gp_handdrawn.py
"""
import bpy, os, glob, math, traceback

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = sorted(glob.glob(os.path.join(HERE, "gp_src", "ball_*.png")))
OUT = os.path.join(HERE, "gp_hand"); os.makedirs(OUT, exist_ok=True)

STROKE_RADIUS = 0.028      # thin
CHAIKIN_ITERS = 3          # rounding + vertex multiplication
SMOOTH_ITERS  = 2
WOBBLE_AMP    = 0.012      # hand-drawn wander (GP units; ball radius ~0.7)
SPACING       = 4

bpy.ops.wm.read_factory_settings(use_empty=True)

# ---------- polyline helpers (2D in XY, z kept) ----------
def chaikin(pts, cyclic, iters):
    for _ in range(iters):
        out = []
        n = len(pts)
        rng = range(n) if cyclic else range(n - 1)
        if not cyclic:
            out.append(pts[0])
        for i in rng:
            p, q = pts[i], pts[(i + 1) % n]
            out.append((0.75*p[0]+0.25*q[0], 0.75*p[1]+0.25*q[1], p[2]))
            out.append((0.25*p[0]+0.75*q[0], 0.25*p[1]+0.75*q[1], p[2]))
        if not cyclic:
            out.append(pts[-1])
        pts = out
    return pts

def smooth(pts, cyclic, iters):
    for _ in range(iters):
        n = len(pts); out = []
        for i in range(n):
            if not cyclic and (i == 0 or i == n-1):
                out.append(pts[i]); continue
            a, b, c = pts[(i-1) % n], pts[i], pts[(i+1) % n]
            out.append(((a[0]+2*b[0]+c[0])/4, (a[1]+2*b[1]+c[1])/4, b[2]))
        pts = out
    return pts

def wobble(pts, cyclic, amp):
    """Seam-continuous perpendicular offset (integer harmonics -> wraps cleanly)."""
    n = len(pts); out = []
    for i in range(n):
        a, c = pts[(i-1) % n], pts[(i+1) % n]
        tx, ty = c[0]-a[0], c[1]-a[1]
        tl = math.hypot(tx, ty) or 1.0
        px, py = -ty/tl, tx/tl                    # perpendicular
        t = i / n * 2*math.pi
        w = math.sin(3*t) * 0.6 + math.sin(5*t + 1.3) * 0.4
        out.append((pts[i][0] + px*amp*w, pts[i][1] + py*amp*w, pts[i][2]))
    return out

# ---------- trace one image -> list of (polyline, cyclic) ----------
def trace_outlines(path):
    bpy.ops.object.empty_add(type='IMAGE', location=(0, 0, 0))
    emp = bpy.context.active_object
    emp.data = bpy.data.images.load(path)
    emp.empty_display_size = 4.0
    for o in bpy.context.selected_objects: o.select_set(False)
    emp.select_set(True); bpy.context.view_layer.objects.active = emp
    before = set(bpy.data.objects)
    try:
        bpy.ops.grease_pencil.trace_image(target='NEW', threshold=0.5, turnpolicy='MINORITY')
    except Exception:
        traceback.print_exc()
    new = [o for o in bpy.data.objects if o not in before and o.type == 'GREASEPENCIL']
    outlines = []
    if new:
        gp = new[0]
        fr = gp.data.layers[0].frames[0]
        for s in fr.drawing.strokes:
            pl = [(p.position.x, p.position.y, p.position.z) for p in s.points]
            outlines.append((pl, bool(s.cyclic)))
        bpy.data.objects.remove(gp, do_unlink=True)
    bpy.data.objects.remove(emp, do_unlink=True)
    return outlines

def process(pl, cyclic):
    pl = chaikin(pl, cyclic, CHAIKIN_ITERS)
    pl = smooth(pl, cyclic, SMOOTH_ITERS)
    pl = wobble(pl, cyclic, WOBBLE_AMP)
    return pl

# ---------- build target GP with an ink (stroke-only) material ----------
gp_data = bpy.data.grease_pencils_v3.new("BallHandGP")
gp_obj = bpy.data.objects.new("BallHand", gp_data)
bpy.context.collection.objects.link(gp_obj)
layer = gp_data.layers.new("ink")

mat = bpy.data.materials.new("Ink")
try:
    bpy.data.materials.create_gpencil_data(mat)
except Exception:
    traceback.print_exc()
g = mat.grease_pencil
g.show_stroke = True
g.color = (0.09, 0.08, 0.07, 1.0)
g.show_fill = False
gp_data.materials.append(mat)

def add_frame(scene_frame, processed):
    fr = layer.frames.new(scene_frame)
    d = fr.drawing
    counts = [len(pl) for pl, _ in processed]
    d.add_strokes(counts)
    for si, (pl, cyclic) in enumerate(processed):
        st = d.strokes[si]
        st.cyclic = cyclic
        st.material_index = 0
        try:
            st.start_cap = 'ROUND'; st.end_cap = 'ROUND'
        except Exception:
            pass
        n = len(pl)
        for pi, pos in enumerate(pl):
            p = st.points[pi]
            p.position = pos
            # slight pressure variation for a hand-drawn feel
            press = 0.85 + 0.15*math.sin(pi/n * 2*math.pi * 2)
            p.radius = STROKE_RADIUS * press
            p.opacity = 1.0

tot_pts = 0
for i, path in enumerate(SRC):
    outs = trace_outlines(path)
    proc = [(process(pl, c), c) for pl, c in outs]
    add_frame(1 + i*SPACING, proc)
    tot_pts += sum(len(pl) for pl, _ in proc)
    print(f"[HD] frame {i}: {len(proc)} strokes, "
          f"{sum(len(pl) for pl,_ in proc)} pts (was ~{sum(len(pl) for pl,_ in outs)//max(1,2**CHAIKIN_ITERS)})")

print(f"[HD] total points across anim: {tot_pts} (avg {tot_pts//len(SRC)}/frame)")

# ---------- camera + paper world ----------
xs=[]; ys=[]
for fr in layer.frames:
    for s in fr.drawing.strokes:
        for p in s.points:
            xs.append(p.position.x); ys.append(p.position.y)
cx=(min(xs)+max(xs))/2; cy=(min(ys)+max(ys))/2
span=max(max(xs)-min(xs), max(ys)-min(ys))*1.35

bpy.ops.object.camera_add(location=(cx, cy, 10)); cam=bpy.context.active_object
cam.data.type='ORTHO'; cam.data.ortho_scale=max(span,1.0)
bpy.context.scene.camera=cam
w=bpy.data.worlds.new("W"); w.use_nodes=True
w.node_tree.nodes["Background"].inputs[0].default_value=(0.96,0.95,0.91,1)  # warm paper
bpy.context.scene.world=w

sc=bpy.context.scene
sc.render.engine='BLENDER_EEVEE_NEXT'
sc.render.resolution_x=sc.render.resolution_y=300
for i in range(len(SRC)):
    sc.frame_set(1+i*SPACING)
    sc.render.filepath=os.path.join(OUT, f"hand_{i:02d}.png")
    bpy.ops.render.render(write_still=True)
print("[HD] rendered", len(SRC), "frames -> gp_hand/")
print("[HD] DONE")
