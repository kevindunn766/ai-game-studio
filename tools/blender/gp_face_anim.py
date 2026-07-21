"""Full talking-head animation: static face + viseme-keyed mouth + blinks/gaze.
Renders PNG frames at 24fps. Run: blender --background --python gp_face_anim.py
"""
import bpy, os, json, traceback

HERE = os.path.dirname(os.path.abspath(__file__))
F = json.load(open(os.path.join(HERE, "face_shapes.json"), encoding="utf-8-sig"))
VIS = json.load(open(os.path.join(HERE, "voice", "visemes.json"), encoding="utf-8-sig"))
OUT = os.path.join(HERE, "face_frames")
os.makedirs(OUT, exist_ok=True)
# clear old frames
for fn in os.listdir(OUT):
    if fn.endswith(".png"): os.remove(os.path.join(OUT, fn))

FPS = 24
BASE = 0.009
vmap = F["viseme_map"]

# viseme timeline -> total duration
total_ms = max(v["start"] + v["dur"] for v in VIS)
N = 1 + int(round(total_ms/1000.0*FPS))
END = N + 8
print(f"[ANIM] total {total_ms}ms -> {N} frames @ {FPS}fps")

def active_viseme(t_ms):
    cur = 0
    for v in VIS:
        if v["start"] <= t_ms:
            cur = v["viseme"]
        else:
            break
    return cur

bpy.ops.wm.read_factory_settings(use_empty=True)

gp_data = bpy.data.grease_pencils_v3.new("FaceGP")
gp_obj = bpy.data.objects.new("Face", gp_data)
bpy.context.collection.objects.link(gp_obj)

mat = bpy.data.materials.new("Ink"); bpy.data.materials.create_gpencil_data(mat)
mg = mat.grease_pencil; mg.show_stroke=True; mg.show_fill=False; mg.color=(0.09,0.08,0.10,1)
gp_data.materials.append(mat)
matf = bpy.data.materials.new("Fill"); bpy.data.materials.create_gpencil_data(matf)
fg = matf.grease_pencil; fg.show_stroke=True; fg.show_fill=True
fg.color=(0.09,0.08,0.10,1); fg.fill_color=(0.20,0.07,0.10,1)
gp_data.materials.append(matf)

def fill_drawing(drawing, strokes):
    counts=[len(s["pts"]) for s in strokes]
    if not counts: return
    drawing.add_strokes(counts)
    for si,s in enumerate(strokes):
        st=drawing.strokes[si]; st.cyclic=s.get("cyclic",False)
        st.material_index = 1 if s.get("fill") else 0
        try: st.start_cap='ROUND'; st.end_cap='ROUND'
        except Exception: pass
        for pi,(x,y) in enumerate(s["pts"]):
            p=st.points[pi]; p.position=(x,y,0.0); p.radius=BASE*s.get("w",1.0); p.opacity=1.0

# --- static layer (one keyframe) ---
ls = gp_data.layers.new("static")
fill_drawing(ls.frames.new(1).drawing, F["static"])

# --- mouth layer: per-frame sample, key only on shape change ---
lm = gp_data.layers.new("mouth")
prev = None
mouth_keys = 0
for frame in range(1, N+1):
    t_ms = (frame-1)/FPS*1000.0
    shape = vmap[str(active_viseme(t_ms))]
    if shape != prev:
        fill_drawing(lm.frames.new(frame).drawing, F["mouths"][shape])
        prev = shape
        mouth_keys += 1
print(f"[ANIM] mouth keyframes: {mouth_keys}")

# --- eyes layer: blinks + gaze shifts ---
le = gp_data.layers.new("eyes")
eye_states = {
    "open": F["eyes_open"], "closed": F["eyes_closed"],
    "look_left": F["eyes_look_left"], "look_right": F["eyes_look_right"],
}
events = [
    (1,"open"),
    (45,"closed"),(48,"open"),
    (95,"look_left"),(130,"open"),
    (160,"closed"),(163,"open"),
    (210,"look_right"),(240,"open"),
    (275,"closed"),(278,"open"),
    (350,"closed"),(353,"open"),
]
events = [(min(f, N), s) for f, s in events]
seen = set()
for f, s in sorted(events):
    if f in seen:  # avoid duplicate keyframe on same frame
        continue
    seen.add(f)
    fill_drawing(le.frames.new(f).drawing, eye_states[s])
print(f"[ANIM] eye keyframes: {len(seen)}")

# --- camera / world / render ---
bpy.ops.object.camera_add(location=(0.0, 0.03, 10)); cam=bpy.context.active_object
cam.data.type='ORTHO'; cam.data.ortho_scale=2.7; bpy.context.scene.camera=cam
w=bpy.data.worlds.new("W"); w.use_nodes=True
w.node_tree.nodes["Background"].inputs[0].default_value=(0.97,0.95,0.92,1)
bpy.context.scene.world=w
sc=bpy.context.scene
sc.render.engine='BLENDER_EEVEE_NEXT'
try: sc.view_settings.view_transform='Standard'
except Exception: traceback.print_exc()
sc.render.resolution_x=560; sc.render.resolution_y=720
sc.render.image_settings.file_format='PNG'
sc.frame_start=1; sc.frame_end=END
sc.render.filepath=os.path.join(OUT, "f_")
bpy.ops.render.render(animation=True)
print(f"[ANIM] rendered frames 1..{END} -> face_frames/")
print("[ANIM] DONE")
