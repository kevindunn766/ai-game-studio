import bpy
rna = bpy.ops.grease_pencil.trace_image.get_rna_type()
print("[TR] trace_image params:")
for p in rna.properties:
    if p.identifier == "rna_type": continue
    extra = ""
    if hasattr(p, "default"):
        try: extra = f" default={p.default}"
        except Exception: pass
    print(f"    {p.identifier:16s} {p.type}{extra}")
print("[TR] DONE")
