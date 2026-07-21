"""Preview the procedural anime face (neutral) as one still.
Run: blender --background --python gp_face_still.py
"""
import bpy, os, json, traceback

HERE = os.path.dirname(os.path.abspath(__file__))
F = json.load(open(os.path.join(HERE, "face_shapes.json")))
OUT = os.path.join(HERE, "face_out"); os.makedirs(OUT, exist_ok=True)
BASE = 0.009

bpy.ops.wm.read_factory_settings(use_empty=True)

gp_data = bpy.data.grease_pencils_v3.new("FaceGP")
gp_obj = bpy.data.objects.new("Face", gp_data)
bpy.context.collection.objects.link(gp_obj)

mat = bpy.data.materials.new("Ink"); bpy.data.materials.create_gpencil_data(mat)
g = mat.grease_pencil; g.show_stroke=True; g.show_fill=False; g.color=(0.09,0.08,0.10,1)
gp_data.materials.append(mat)
# fill material for open-mouth interior (dark)
matf = bpy.data.materials.new("MouthFill"); bpy.data.materials.create_gpencil_data(matf)
gf = matf.grease_pencil; gf.show_stroke=True; gf.show_fill=True
gf.color=(0.09,0.08,0.10,1); gf.fill_color=(0.20,0.07,0.10,1)
gp_data.materials.append(matf)

def add_strokes(drawing, strokes):
    counts=[len(s["pts"]) for s in strokes]
    if not counts: return
    drawing.add_strokes(counts)
    for si,s in enumerate(strokes):
        st=drawing.strokes[si]; st.cyclic=s.get("cyclic",False)
        st.material_index=1 if s.get("fill") else 0
        try: st.start_cap='ROUND'; st.end_cap='ROUND'
        except Exception: pass
        for pi,(x,y) in enumerate(s["pts"]):
            p=st.points[pi]; p.position=(x,y,0.0); p.radius=BASE*s.get("w",1.0); p.opacity=1.0

def layer_with(name, strokes):
    lyr=gp_data.layers.new(name); fr=lyr.frames.new(1)
    add_strokes(fr.drawing, strokes); return lyr

layer_with("static", F["static"])
layer_with("eyes", F["eyes_open"])
layer_with("mouth", F["mouths"]["OPEN_BIG"])

# camera + cream world
bpy.ops.object.camera_add(location=(0.0, 0.02, 10)); cam=bpy.context.active_object
cam.data.type='ORTHO'; cam.data.ortho_scale=2.7; bpy.context.scene.camera=cam
w=bpy.data.worlds.new("W"); w.use_nodes=True
w.node_tree.nodes["Background"].inputs[0].default_value=(0.97,0.95,0.92,1)
bpy.context.scene.world=w
sc=bpy.context.scene; sc.render.engine='BLENDER_EEVEE_NEXT'
try: sc.view_settings.view_transform='Standard'
except Exception: traceback.print_exc()
sc.render.resolution_x=560; sc.render.resolution_y=720
sc.render.filepath=os.path.join(OUT,"neutral.png")
bpy.ops.render.render(write_still=True)
print("[FACE] rendered neutral.png")
