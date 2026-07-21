"""Probe GP v3 material texture-stroke API on 4.5."""
import bpy
mat = bpy.data.materials.new("T")
try:
    bpy.data.materials.create_gpencil_data(mat)
except Exception as e:
    print("create_gpencil_data err:", e)
g = mat.grease_pencil
attrs = [a for a in dir(g) if not a.startswith("_")]
print("[GPMAT] all attrs:", attrs)
keys = ("stroke", "texture", "mode", "style", "image", "mix", "pixel", "align", "pattern")
print("[GPMAT] relevant:")
for a in attrs:
    if any(k in a.lower() for k in keys):
        try:
            print(f"    {a} = {getattr(g, a)!r}")
        except Exception as e:
            print(f"    {a} (unreadable: {e})")
# enum options for stroke_style / mode
for prop in ("stroke_style", "mode", "alignment_mode"):
    if hasattr(g, prop):
        rna = g.bl_rna.properties.get(prop)
        if rna and hasattr(rna, "enum_items"):
            print(f"[GPMAT] {prop} options:", [e.identifier for e in rna.enum_items])
print("[GPMAT] DONE")
