"""Trace a sequence of raster frames into ONE Grease Pencil object as keyframes,
then render the 2D animation. Proves: artwork -> vector GP strokes -> animation.
Run: blender --background --python gp_demo.py
"""
import bpy, os, glob, math, traceback

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = sorted(glob.glob(os.path.join(HERE, "gp_src", "ball_*.png")))
OUT = os.path.join(HERE, "gp_out")
os.makedirs(OUT, exist_ok=True)
print("[GPD] source frames:", len(SRC))

bpy.ops.wm.read_factory_settings(use_empty=True)

def trace_one(path):
    """Load image as reference empty, trace to a NEW grease pencil, return GP obj."""
    bpy.ops.object.empty_add(type='IMAGE', location=(0, 0, 0))
    emp = bpy.context.active_object
    img = bpy.data.images.load(path)
    emp.data = img
    emp.empty_display_size = 4.0
    for o in bpy.context.selected_objects: o.select_set(False)
    emp.select_set(True)
    bpy.context.view_layer.objects.active = emp
    before = set(bpy.data.objects)
    try:
        bpy.ops.grease_pencil.trace_image(target='NEW', threshold=0.5, turnpolicy='MINORITY')
    except Exception:
        traceback.print_exc()
    new = [o for o in bpy.data.objects if o not in before and o.type == 'GREASEPENCIL']
    gp = new[0] if new else None
    # clean up the empty + image
    bpy.data.objects.remove(emp, do_unlink=True)
    return gp

def first_drawing(gp):
    lyr = gp.data.layers[0]
    fr = lyr.frames[0] if len(lyr.frames) else None
    return fr.drawing if fr else None

# --- trace frame 0 -> becomes our base animated object ---
base = trace_one(SRC[0])
if base is None:
    print("[GPD] FAIL: trace produced no GP object"); raise SystemExit
base.name = "BallAnim"
layer = base.data.layers[0]
d0 = first_drawing(base)
print(f"[GPD] frame0 traced: {len(d0.strokes)} strokes, "
      f"{sum(len(s.points) for s in d0.strokes)} pts")

SPACING = 4  # scene frames between drawings

def copy_strokes(src_drawing, dst_drawing):
    counts = [len(s.points) for s in src_drawing.strokes]
    if not counts: return
    dst_drawing.add_strokes(counts)
    nmat = len(base.data.materials)
    for si, s in enumerate(src_drawing.strokes):
        ds = dst_drawing.strokes[si]
        ds.cyclic = s.cyclic
        ds.material_index = min(s.material_index, max(nmat - 1, 0))
        for pi, p in enumerate(s.points):
            dp = ds.points[pi]
            dp.position = p.position
            dp.radius = p.radius
            dp.opacity = p.opacity

# --- trace remaining frames, copy their strokes onto new keyframes ---
for i in range(1, len(SRC)):
    tmp = trace_one(SRC[i])
    if tmp is None:
        print(f"[GPD] frame {i} trace failed"); continue
    src_d = first_drawing(tmp)
    fr = layer.frames.new(1 + i * SPACING)
    copy_strokes(src_d, fr.drawing)
    print(f"[GPD] keyframe @ scene-frame {1 + i*SPACING}: "
          f"{len(fr.drawing.strokes)} strokes")
    # delete temp GP object + data
    dat = tmp.data
    bpy.data.objects.remove(tmp, do_unlink=True)
    try: bpy.data.grease_pencils_v3.remove(dat)
    except Exception: pass

print(f"[GPD] final: layer has {len(layer.frames)} keyframes")

# --- camera + world: look straight at the XY plane the GP lives in ---
# compute GP bounds to frame it
xs, ys = [], []
for fr in layer.frames:
    for s in fr.drawing.strokes:
        for p in s.points:
            xs.append(p.position.x); ys.append(p.position.y)
cx = (min(xs)+max(xs))/2; cy = (min(ys)+max(ys))/2
span = max(max(xs)-min(xs), max(ys)-min(ys)) * 1.3
print(f"[GPD] bounds center=({cx:.2f},{cy:.2f}) span={span:.2f}")

bpy.ops.object.camera_add(location=(cx, cy, 10))
cam = bpy.context.active_object
cam.data.type = 'ORTHO'
cam.data.ortho_scale = max(span, 1.0)
bpy.context.scene.camera = cam

w = bpy.data.worlds.new("W"); w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.95, 0.95, 0.95, 1)
bpy.context.scene.world = w

sc = bpy.context.scene
sc.render.engine = 'BLENDER_EEVEE_NEXT'
sc.render.resolution_x = sc.render.resolution_y = 300
sc.frame_start = 1
sc.frame_end = 1 + (len(SRC)-1)*SPACING

# --- render each keyframe's scene-frame ---
for i in range(len(SRC)):
    f = 1 + i*SPACING
    sc.frame_set(f)
    sc.render.filepath = os.path.join(OUT, f"anim_{i:02d}.png")
    bpy.ops.render.render(write_still=True)
print("[GPD] rendered", len(SRC), "frames to gp_out/")

# --- also export the GP as SVG-capable? report frame data instead ---
print("[GPD] DONE")
