"""Probe Grease Pencil v3 API + image-trace on Blender 4.5.
Run: blender --background --python probe_gp.py
Introspection only - learn the real API before building the demo.
"""
import bpy

print("[GP] Blender", bpy.app.version_string)

# --- 1. Grease Pencil data containers present? ---
print("[GP] data.grease_pencils_v3 exists:", hasattr(bpy.data, "grease_pencils_v3"))
print("[GP] legacy data.grease_pencil exists:", hasattr(bpy.data, "grease_pencil"))

# --- 2. Relevant operators available? ---
def has_op(path):
    parts = path.split(".")
    ops = bpy.ops
    try:
        for p in parts:
            ops = getattr(ops, p)
        return True
    except Exception:
        return False

for op in ["object.grease_pencil_add", "object.gpencil_add",
           "grease_pencil.trace_image", "gpencil.trace_image",
           "grease_pencil.draw", "object.convert"]:
    print(f"[GP] op {op:34s} -> {has_op(op)}")

# --- 3. Create a GP object and introspect the stroke API ---
try:
    bpy.ops.object.grease_pencil_add(type='EMPTY')
    gp = bpy.context.active_object
    print("[GP] created object type:", gp.type, "data type:", type(gp.data).__name__)
    data = gp.data
    print("[GP] data attrs:", [a for a in dir(data) if not a.startswith("_")][:20])
    print("[GP] has .layers:", hasattr(data, "layers"))
    layer = data.layers.new("L1")
    print("[GP] layer created:", layer.name, "| frame api:", [a for a in dir(layer.frames) if not a.startswith("_")])
    frame = layer.frames.new(1)
    print("[GP] frame created @", frame.frame_number)
    drawing = frame.drawing
    print("[GP] drawing type:", type(drawing).__name__)
    print("[GP] drawing attrs:", [a for a in dir(drawing) if not a.startswith("_")])
    # try to add a stroke
    if hasattr(drawing, "add_strokes"):
        drawing.add_strokes([4])  # one stroke of 4 points
        print("[GP] add_strokes OK, strokes now:", len(drawing.strokes))
        s = drawing.strokes[0]
        print("[GP] stroke attrs:", [a for a in dir(s) if not a.startswith("_")][:20])
        pts = s.points
        print("[GP] points count:", len(pts), "point attrs:", [a for a in dir(pts[0]) if not a.startswith("_")][:15])
except Exception:
    import traceback
    traceback.print_exc()

print("[GP] DONE")
