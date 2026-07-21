"""Build the pencil-textured ball animation from clean contours.json (no potrace).
Round geometry from contour extraction; hand-drawn look = stroke TEXTURE.
Run: blender --background --python gp_contour.py
"""
import bpy, os, json, math, traceback

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "gp_final"); os.makedirs(OUT, exist_ok=True)
TEX = os.path.join(HERE, "pencil_tex.png")
DATA = json.load(open(os.path.join(HERE, "contours.json")))

STROKE_RADIUS = 0.055
SPACING       = 4
RENDER_PX     = 600

bpy.ops.wm.read_factory_settings(use_empty=True)

gp_data = bpy.data.grease_pencils_v3.new("BallFinalGP")
gp_obj = bpy.data.objects.new("BallFinal", gp_data)
bpy.context.collection.objects.link(gp_obj)
layer = gp_data.layers.new("pencil")

tex_img = bpy.data.images.load(TEX)
mat = bpy.data.materials.new("Pencil")
bpy.data.materials.create_gpencil_data(mat)
g = mat.grease_pencil
g.show_stroke = True; g.show_fill = False
g.stroke_style = 'TEXTURE'; g.stroke_image = tex_img
g.mode = 'LINE'; g.alignment_mode = 'PATH'
g.mix_stroke_factor = 1.0
g.color = (0.11, 0.10, 0.09, 1.0)
try: g.texture_scale = (5.0, 1.0)
except Exception: traceback.print_exc()
gp_data.materials.append(mat)

def add_frame(sf, contours):
    fr = layer.frames.new(sf); d = fr.drawing
    counts = [len(c["pts"]) for c in contours]
    d.add_strokes(counts)
    for si, c in enumerate(contours):
        st = d.strokes[si]; st.cyclic = c["cyclic"]; st.material_index = 0
        try: st.start_cap = 'ROUND'; st.end_cap = 'ROUND'
        except Exception: pass
        n = len(c["pts"])
        for pi, (x, y) in enumerate(c["pts"]):
            p = st.points[pi]
            p.position = (x, y, 0.0)
            p.radius = STROKE_RADIUS * (0.9 + 0.1*math.sin(pi/n*2*math.pi*2))
            p.opacity = 1.0

for i, frame in enumerate(DATA["frames"]):
    add_frame(1 + i*SPACING, frame["contours"])
    print(f"[FIN] frame {i}: {len(frame['contours'])} contours, "
          f"{sum(len(c['pts']) for c in frame['contours'])} pts")

# camera + paper
xs=[];ys=[]
for fr in layer.frames:
    for s in fr.drawing.strokes:
        for p in s.points: xs.append(p.position.x); ys.append(p.position.y)
cx=(min(xs)+max(xs))/2; cy=(min(ys)+max(ys))/2
span=max(max(xs)-min(xs),max(ys)-min(ys))*1.4
bpy.ops.object.camera_add(location=(cx,cy,10)); cam=bpy.context.active_object
cam.data.type='ORTHO'; cam.data.ortho_scale=max(span,1.0); bpy.context.scene.camera=cam
w=bpy.data.worlds.new("W"); w.use_nodes=True
w.node_tree.nodes["Background"].inputs[0].default_value=(0.95,0.93,0.88,1)
bpy.context.scene.world=w
sc=bpy.context.scene
sc.render.engine='BLENDER_EEVEE_NEXT'
try: sc.view_settings.view_transform='Standard'
except Exception: traceback.print_exc()
sc.render.resolution_x=sc.render.resolution_y=RENDER_PX
for i in range(len(DATA["frames"])):
    sc.frame_set(1+i*SPACING)
    sc.render.filepath=os.path.join(OUT,f"final_{i:02d}.png")
    bpy.ops.render.render(write_still=True)
print("[FIN] rendered",len(DATA["frames"]),"frames -> gp_final/")
print("[FIN] DONE")
