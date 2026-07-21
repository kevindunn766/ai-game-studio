"""Isolate where roundness dies: raw trace vs +chaikin vs +chaikin+smooth.
Renders 3 thin solid-line outlines. Run: blender --background --python diag_round.py
"""
import bpy, os, math, traceback

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "gp_src", "ball_00.png")
OUT = os.path.join(HERE, "diag"); os.makedirs(OUT, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)

def chaikin(pts,cyclic,iters):
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

def smooth(pts,cyclic,iters):
    for _ in range(iters):
        n=len(pts); out=[]
        for i in range(n):
            if not cyclic and (i==0 or i==n-1): out.append(pts[i]); continue
            a,b,c=pts[(i-1)%n],pts[i],pts[(i+1)%n]
            out.append(((a[0]+2*b[0]+c[0])/4,(a[1]+2*b[1]+c[1])/4,b[2]))
        pts=out
    return pts

# --- trace ---
bpy.ops.object.empty_add(type='IMAGE', location=(0,0,0))
emp=bpy.context.active_object; emp.data=bpy.data.images.load(SRC); emp.empty_display_size=4.0
before=set(bpy.data.objects)
bpy.ops.grease_pencil.trace_image(target='NEW', threshold=0.5, turnpolicy='MINORITY')
gp=[o for o in bpy.data.objects if o not in before and o.type=='GREASEPENCIL'][0]
fr=gp.data.layers[0].frames[0]
raw=[]
for s in fr.drawing.strokes:
    raw.append(([(p.position.x,p.position.y,p.position.z) for p in s.points], bool(s.cyclic)))
bpy.data.objects.remove(gp, do_unlink=True); bpy.data.objects.remove(emp, do_unlink=True)

# report the OUTER stroke (largest) point coords
outer = max(raw, key=lambda r: len(r[0]))
pl0 = outer[0]
print(f"[DIAG] raw strokes: {len(raw)}, outer pts: {len(pl0)}, cyclic={outer[1]}")
xs=[p[0] for p in pl0]; ys=[p[1] for p in pl0]
print(f"[DIAG] outer bbox x[{min(xs):.2f},{max(xs):.2f}] y[{min(ys):.2f},{max(ys):.2f}] "
      f"w={max(xs)-min(xs):.2f} h={max(ys)-min(ys):.2f}")
# distance of each point from centroid -> if round, ~constant
cx=sum(xs)/len(xs); cy=sum(ys)/len(ys)
rads=[math.hypot(p[0]-cx,p[1]-cy) for p in pl0]
print(f"[DIAG] centroid-radius min={min(rads):.3f} max={max(rads):.3f} "
      f"mean={sum(rads)/len(rads):.3f}  (round => min~max)")
print("[DIAG] first 8 pts:", [(round(p[0],2),round(p[1],2)) for p in pl0[:8]])

def build_and_render(name, processed):
    d=bpy.data.grease_pencils_v3.new("G_"+name)
    o=bpy.data.objects.new("O_"+name, d); bpy.context.collection.objects.link(o)
    lyr=d.layers.new("l"); frm=lyr.frames.new(1)
    mat=bpy.data.materials.new("m_"+name); bpy.data.materials.create_gpencil_data(mat)
    mat.grease_pencil.show_stroke=True; mat.grease_pencil.show_fill=False
    mat.grease_pencil.color=(0.05,0.05,0.05,1); d.materials.append(mat)
    dr=frm.drawing; dr.add_strokes([len(pl) for pl,_ in processed])
    for si,(pl,cyc) in enumerate(processed):
        st=dr.strokes[si]; st.cyclic=cyc; st.material_index=0
        for pi,pos in enumerate(pl):
            st.points[pi].position=pos; st.points[pi].radius=0.02; st.points[pi].opacity=1
    # camera fit
    axs=[p[0] for pl,_ in processed for p in pl]; ays=[p[1] for pl,_ in processed for p in pl]
    ccx=(min(axs)+max(axs))/2; ccy=(min(ays)+max(ays))/2
    span=max(max(axs)-min(axs),max(ays)-min(ays))*1.3
    cam=bpy.data.objects.get("CAM")
    if not cam:
        bpy.ops.object.camera_add(location=(ccx,ccy,10)); cam=bpy.context.active_object; cam.name="CAM"
        cam.data.type='ORTHO'
    cam.location=(ccx,ccy,10); cam.data.ortho_scale=max(span,1.0)
    bpy.context.scene.camera=cam
    if not bpy.context.scene.world:
        w=bpy.data.worlds.new("W"); w.use_nodes=True
        w.node_tree.nodes["Background"].inputs[0].default_value=(1,1,1,1); bpy.context.scene.world=w
    sc=bpy.context.scene; sc.render.engine='BLENDER_EEVEE_NEXT'
    try: sc.view_settings.view_transform='Standard'
    except Exception: pass
    sc.render.resolution_x=sc.render.resolution_y=400
    sc.render.filepath=os.path.join(OUT,name+".png")
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(o, do_unlink=True)
    print("[DIAG] rendered", name)

build_and_render("a_raw",       [(pl,c) for pl,c in raw])
build_and_render("b_chaikin",   [(chaikin(pl,c,4),c) for pl,c in raw])
build_and_render("c_smoothed",  [(smooth(chaikin(pl,c,4),c,3),c) for pl,c in raw])
print("[DIAG] DONE")
