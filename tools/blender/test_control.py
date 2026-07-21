"""Headless control smoke-test for Blender 4.5.
Run: blender --background --python test_control.py
Proves: scene edit -> procedural mesh -> export glb -> render png -> clean exit.
"""
import bpy
import os
import math

OUT = os.path.dirname(os.path.abspath(__file__))

def log(msg):
    print(f"[CTL] {msg}")

# --- 1. Clean scene ---------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
log("scene cleared")

# --- 2. Procedural mesh: a faceted gem via ico sphere + bevel ---------------
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=1.0)
gem = bpy.context.active_object
gem.name = "TestGem"

# flatten normals to faceted look, add a subtle twist via simple deform
mod = gem.modifiers.new("Bevel", 'BEVEL')
mod.width = 0.08
mod.segments = 2

# apply modifier so vertex count reflects real geometry
bpy.ops.object.modifier_apply(modifier=mod.name)
vcount = len(gem.data.vertices)
fcount = len(gem.data.polygons)
log(f"mesh built: {vcount} verts, {fcount} faces")

# --- 3. Material (emberish) -------------------------------------------------
mat = bpy.data.materials.new("Ember")
mat.use_nodes = True
bsdf = mat.node_tree.nodes.get("Principled BSDF")
bsdf.inputs["Base Color"].default_value = (0.9, 0.35, 0.08, 1.0)
bsdf.inputs["Emission Color"].default_value = (1.0, 0.4, 0.1, 1.0)
bsdf.inputs["Emission Strength"].default_value = 2.0
gem.data.materials.append(mat)
log("material applied")

# --- 4. Camera + light for the render --------------------------------------
bpy.ops.object.camera_add(location=(3, -3, 2), rotation=(math.radians(63), 0, math.radians(46)))
cam = bpy.context.active_object
bpy.context.scene.camera = cam

bpy.ops.object.light_add(type='SUN', location=(4, -2, 5))
bpy.context.active_object.data.energy = 3.0

# --- 5. Export glb ----------------------------------------------------------
glb_path = os.path.join(OUT, "test_gem.glb")
bpy.ops.export_scene.gltf(filepath=glb_path, export_format='GLB', use_selection=False)
log(f"exported glb: {os.path.exists(glb_path)} ({os.path.getsize(glb_path)} bytes)")

# --- 6. Render a thumbnail --------------------------------------------------
scene = bpy.context.scene
scene.render.engine = 'BLENDER_EEVEE_NEXT'
scene.render.resolution_x = 256
scene.render.resolution_y = 256
scene.render.film_transparent = False
scene.world = bpy.data.worlds.new("W")
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.03, 0.03, 0.05, 1)
png_path = os.path.join(OUT, "test_gem.png")
scene.render.filepath = png_path
bpy.ops.render.render(write_still=True)
log(f"rendered png: {os.path.exists(png_path)}")

log("DONE")
