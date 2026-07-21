"""Round outline + textured PENCIL stroke (the hand-drawn look comes from the
stroke texture, not geometry). Run: blender --background --python gp_brush.py
"""
import bpy, os, glob, math, traceback

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = sorted(glob.glob(os.path.join(HERE, "gp_src", "ball_*.png")))
OUT = os.path.join(HERE, "gp_brush"); os.makedirs(OUT, exist_ok=True)
TEX = os.path.join(HERE, "pencil_tex.png")

STROKE_RADIUS = 0.10       # wider so the grain reads as a body, not just edges
CHAIKIN_ITERS = 4          # heavy rounding: decagon -> smooth circle
SMOOTH_ITERS  = 3
SPACING       = 4
RENDER_PX     = 600        # bigger so grain reads

bpy.ops.wm.read_factory_settings(use_empty=True)

def chaikin(pts, cyclic, iters):
    for _ in range(iters):
        out=[]; n=len(pts); rng=range(n) if cyclic else range(n-1)
        if not cyclic: out.append(pts[0])
        for i in rng:
            p,q=pts[i],pts[(i+1)%n]
            out.append((0.75*p[0]+0.25*q[0],0.75*p[1]+0.25*q[1],p[2]))
            out.append((0.25*p[0]+0.75*q[0],0.25*p[1]+0.75*q[1],p[2]))
        if not cyclic: out.append(pts[-1])
        pts=out
    return pts

def smooth(pts, cyclic, iters):
    for _ in range(iters):
        n=len(pts); out=[]
        for i in range(n):
            if not cyclic and (i==0 or i==n-1): out.append(pts[i]); continue
            a,b,c=pts[(i-1)%n],pts[i],pts[(i+1)%n]
            out.append(((a[0]+2*b[0]+c[0])/4,(a[1]+2*b[1]+c[1])/4,b[2]))
        pts=out
    return pts

def trace_outlines(path):
    bpy.ops.object.empty_add(type='IMAGE', location=(0,0,0))
    emp=bpy.context.active_object; emp.data=bpy.data.images.load(path)
    emp.empty_display_size=4.0
    for o in bpy.context.selected_objects: o.select_set(False)
    emp.select_set(True); bpy.context.view_layer.objects.active=emp
    before=set(bpy.data.objects)
    try:
        bpy.ops.grease_pencil.trace_image(target='NEW', threshold=0.5, turnpolicy='MINORITY')
    except Exception: traceback.print_exc()
    new=[o for o in bpy.data.objects if o not in before and o.type=='GREASEPENCIL']
    outs=[]
    if new:
        gp=new[0]; fr=gp.data.layers[0].frames[0]
        for s in fr.drawing.strokes:
            outs.append(([(p.position.x,p.position.y,p.position.z) for p in s.points], bool(s.cyclic)))
        bpy.data.objects.remove(gp, do_unlink=True)
    bpy.data.objects.remove(emp, do_unlink=True)
    return outs

def process(pl,c):
    return smooth(chaikin(pl,c,CHAIKIN_ITERS),c,SMOOTH_ITERS)

# --- GP object + PENCIL textured material ---
gp_data=bpy.data.grease_pencils_v3.new("BallBrushGP")
gp_obj=bpy.data.objects.new("BallBrush", gp_data)
bpy.context.collection.objects.link(gp_obj)
layer=gp_data.layers.new("pencil")

tex_img=bpy.data.images.load(TEX)
mat=bpy.data.materials.new("Pencil")
bpy.data.materials.create_gpencil_data(mat)
g=mat.grease_pencil
g.show_stroke=True
g.show_fill=False
g.stroke_style='TEXTURE'
g.stroke_image=tex_img
g.mode='LINE'
g.alignment_mode='PATH'
g.mix_stroke_factor=1.0            # show texture, not flat color
g.color=(0.12,0.11,0.10,1.0)
try: g.texture_scale=(6.0,1.0)     # repeat grain ~6x around the loop
except Exception: traceback.print_exc()
gp_data.materials.append(mat)
print("[BR] material: stroke_style=%s mode=%s align=%s" % (g.stroke_style,g.mode,g.alignment_mode))

def add_frame(sf, processed):
    fr=layer.frames.new(sf); d=fr.drawing
    d.add_strokes([len(pl) for pl,_ in processed])
    for si,(pl,cyc) in enumerate(processed):
        st=d.strokes[si]; st.cyclic=cyc; st.material_index=0
        try: st.start_cap='ROUND'; st.end_cap='ROUND'
        except Exception: pass
        n=len(pl)
        for pi,pos in enumerate(pl):
            p=st.points[pi]; p.position=pos
            p.radius=STROKE_RADIUS*(0.9+0.1*math.sin(pi/n*2*math.pi*2))
            p.opacity=1.0

for i,path in enumerate(SRC):
    outs=trace_outlines(path)
    proc=[(process(pl,c),c) for pl,c in outs]
    add_frame(1+i*SPACING, proc)
    print("[BR] frame %d: %d strokes, %d pts" % (i,len(proc),sum(len(pl) for pl,_ in proc)))

# --- camera + paper ---
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
# Standard view transform: true flat values for 2D/NPR (AgX lifts+desaturates darks)
try: sc.view_settings.view_transform='Standard'
except Exception: traceback.print_exc()
sc.render.resolution_x=sc.render.resolution_y=RENDER_PX
for i in range(len(SRC)):
    sc.frame_set(1+i*SPACING)
    sc.render.filepath=os.path.join(OUT,f"brush_{i:02d}.png")
    bpy.ops.render.render(write_still=True)
print("[BR] rendered",len(SRC),"frames -> gp_brush/")
print("[BR] DONE")
