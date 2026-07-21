"""Capability exploration for headless Blender 4.5.
Each experiment is isolated in try/except and renders a labelled PNG so results
are visually verifiable. Prints an [OK]/[FAIL] line per capability.

Run: blender --background --python explore_caps.py
"""
import bpy
import os
import math
import traceback

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "caps")
os.makedirs(OUT, exist_ok=True)
RESULTS = []


def log(tag, msg):
    print(f"[CAP:{tag}] {msg}")


def fresh_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def setup_stage(cam_loc=(4, -4, 3), cam_rot=(63, 0, 46), bg=(0.04, 0.04, 0.06)):
    bpy.ops.object.camera_add(location=cam_loc,
                              rotation=tuple(math.radians(a) for a in cam_rot))
    bpy.context.scene.camera = bpy.context.active_object
    bpy.ops.object.light_add(type='SUN', location=(4, -3, 8))
    bpy.context.active_object.data.energy = 4.0
    w = bpy.data.worlds.new("W")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (*bg, 1)
    bpy.context.scene.world = w


def render(name, engine='BLENDER_EEVEE_NEXT', samples=None):
    sc = bpy.context.scene
    sc.render.engine = engine
    if engine == 'CYCLES' and samples:
        sc.cycles.samples = samples
    sc.render.resolution_x = 256
    sc.render.resolution_y = 256
    path = os.path.join(OUT, f"{name}.png")
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return os.path.exists(path)


def run(tag, fn):
    try:
        fresh_scene()
        detail = fn()
        RESULTS.append((tag, True, detail))
        log(tag, f"OK - {detail}")
    except Exception:
        RESULTS.append((tag, False, "see traceback"))
        log(tag, "FAIL\n" + traceback.format_exc())


# --- 1. Modifier stack ------------------------------------------------------
def exp_modifiers():
    bpy.ops.mesh.primitive_cube_add()
    o = bpy.context.active_object
    o.modifiers.new("Bevel", 'BEVEL').width = 0.1
    sub = o.modifiers.new("Subsurf", 'SUBSURF'); sub.levels = 2; sub.render_levels = 2
    arr = o.modifiers.new("Array", 'ARRAY'); arr.count = 3; arr.relative_offset_displace[0] = 1.5
    deg = o.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
    v = len(deg.vertices)
    setup_stage(cam_loc=(7, -6, 4))
    ok = render("01_modifiers")
    return f"bevel+subsurf(2)+array(3) -> {v} eval verts, render={ok}"


# --- 2. Geometry Nodes (procedural scatter) --------------------------------
def exp_geonodes():
    bpy.ops.mesh.primitive_plane_add(size=6)
    plane = bpy.context.active_object
    mod = plane.modifiers.new("GN", 'NODES')
    ng = bpy.data.node_groups.new("Scatter", 'GeometryNodeTree')
    mod.node_group = ng
    ng.interface.new_socket("Geometry", in_out='INPUT', socket_type='NodeSocketGeometry')
    ng.interface.new_socket("Geometry", in_out='OUTPUT', socket_type='NodeSocketGeometry')
    nds = ng.nodes
    gin = nds.new("NodeGroupInput"); gin.location = (-600, 0)
    gout = nds.new("NodeGroupOutput"); gout.location = (600, 0)
    dist = nds.new("GeometryNodeDistributePointsOnFaces"); dist.location = (-350, 0)
    dist.inputs["Density"].default_value = 8.0
    cone = nds.new("GeometryNodeMeshCone"); cone.location = (-350, -250)
    cone.inputs["Radius Bottom"].default_value = 0.15
    cone.inputs["Depth"].default_value = 0.6
    inst = nds.new("GeometryNodeInstanceOnPoints"); inst.location = (0, 0)
    real = nds.new("GeometryNodeRealizeInstances"); real.location = (300, 0)
    lk = ng.links.new
    lk(gin.outputs[0], dist.inputs["Mesh"])
    lk(dist.outputs["Points"], inst.inputs["Points"])
    lk(cone.outputs["Mesh"], inst.inputs["Instance"])
    lk(inst.outputs["Instances"], real.inputs["Geometry"])
    lk(real.outputs["Geometry"], gout.inputs[0])
    ev = plane.evaluated_get(bpy.context.evaluated_depsgraph_get())
    m = ev.to_mesh()
    v = len(m.vertices)
    setup_stage(cam_loc=(6, -6, 5))
    ok = render("02_geonodes")
    return f"distribute+instance cones -> {v} realized verts, render={ok}"


# --- 3. Armature: rig + auto-skin + pose deform ----------------------------
def exp_rigging():
    # tall cylinder as a "limb"
    bpy.ops.mesh.primitive_cylinder_add(radius=0.4, depth=4, location=(0, 0, 2))
    limb = bpy.context.active_object
    limb.modifiers.new("Sub", 'SUBSURF').levels = 1
    # loopcuts for deformation: use subdivide in edit mode
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.subdivide(number_cuts=8)
    bpy.ops.object.mode_set(mode='OBJECT')
    # 2-bone armature
    bpy.ops.object.armature_add(location=(0, 0, 0))
    arm = bpy.context.active_object
    bpy.ops.object.mode_set(mode='EDIT')
    eb = arm.data.edit_bones
    root = eb[0]; root.head = (0, 0, 0); root.tail = (0, 0, 2)
    upper = eb.new("Upper"); upper.head = (0, 0, 2); upper.tail = (0, 0, 4)
    upper.parent = root
    bpy.ops.object.mode_set(mode='OBJECT')
    # skin with automatic weights
    limb.select_set(True); arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type='ARMATURE_AUTO')
    # pose: bend the upper bone
    bpy.ops.object.mode_set(mode='POSE')
    pb = arm.pose.bones["Upper"]
    pb.rotation_mode = 'XYZ'
    pb.rotation_euler = (math.radians(55), 0, 0)
    bpy.ops.object.mode_set(mode='OBJECT')
    ngroups = len(limb.vertex_groups)
    setup_stage(cam_loc=(7, -7, 3), cam_rot=(72, 0, 46))
    ok = render("03_rigging")
    return f"2-bone rig, auto-weights({ngroups} groups), 55deg bend, render={ok}"


# --- 4. Procedural material + BAKE to texture (Cycles) ---------------------
def exp_bake():
    bpy.ops.mesh.primitive_uv_sphere_add()
    o = bpy.context.active_object
    bpy.ops.object.shade_smooth()
    # smart uv unwrap
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project()
    bpy.ops.object.mode_set(mode='OBJECT')
    # procedural noise-driven material
    mat = bpy.data.materials.new("Proc"); mat.use_nodes = True
    nt = mat.node_tree; bsdf = nt.nodes["Principled BSDF"]
    noise = nt.nodes.new("ShaderNodeTexNoise"); noise.inputs["Scale"].default_value = 6.0
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.05, 0.02, 0.0, 1)
    ramp.color_ramp.elements[1].color = (1.0, 0.5, 0.1, 1)
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    o.data.materials.append(mat)
    # bake target image + image node
    img = bpy.data.images.new("Baked", 512, 512)
    node_img = nt.nodes.new("ShaderNodeTexImage"); node_img.image = img
    node_img.select = True; nt.nodes.active = node_img
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 8
    sc.cycles.bake_type = 'DIFFUSE'
    sc.render.bake.use_pass_direct = False
    sc.render.bake.use_pass_indirect = False
    bpy.ops.object.bake(type='DIFFUSE')
    bake_path = os.path.join(OUT, "04_baked_texture.png")
    img.filepath_raw = bake_path; img.file_format = 'PNG'; img.save()
    setup_stage()
    ok = render("04_bake_scene")
    return f"smart-uv + noise->ramp baked to 512 tex ({os.path.exists(bake_path)}), render={ok}"


# --- 5. Rigid body physics bake --------------------------------------------
def exp_physics():
    # ground
    bpy.ops.mesh.primitive_plane_add(size=12)
    ground = bpy.context.active_object
    bpy.ops.rigidbody.object_add(); ground.rigid_body.type = 'PASSIVE'
    # falling cubes
    import mathutils
    for i in range(6):
        x = (i % 3 - 1) * 1.2
        y = (i // 3) * 1.2
        bpy.ops.mesh.primitive_cube_add(size=0.8, location=(x, y, 3 + i * 0.9))
        c = bpy.context.active_object
        bpy.ops.rigidbody.object_add(); c.rigid_body.type = 'ACTIVE'
    sc = bpy.context.scene
    sc.rigidbody_world.point_cache.frame_end = 60
    sc.frame_set(1)
    # step the sim forward so the cache accumulates
    for f in range(1, 55):
        sc.frame_set(f)
    setup_stage(cam_loc=(8, -8, 5))
    ok = render("05_physics")
    z_positions = [round(o.matrix_world.translation.z, 2)
                   for o in bpy.data.objects if o.name.startswith("Cube")]
    return f"6 cubes dropped 54 frames, rest Z={z_positions}, render={ok}"


run("modifiers", exp_modifiers)
run("geonodes", exp_geonodes)
run("rigging", exp_rigging)
run("bake", exp_bake)
run("physics", exp_physics)

print("\n===== CAPABILITY SUMMARY =====")
for tag, ok, detail in RESULTS:
    print(f"  {'[OK]  ' if ok else '[FAIL]'} {tag:12s} {detail}")
print("[CAP] DONE")
