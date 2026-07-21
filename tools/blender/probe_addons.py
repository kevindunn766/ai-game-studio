"""Probe + enable add-ons headlessly. Run: blender --background --python probe_addons.py"""
import bpy
import addon_utils
import traceback

print("[ADDON] Blender", bpy.app.version_string)

# --- what's available (module name -> display name) ---
mods = sorted(addon_utils.modules(), key=lambda m: m.__name__)
print(f"[ADDON] {len(mods)} add-ons discovered. Rigging/animation-related:")
KEY = ("rig", "anim", "node", "pose", "bone", "skel")
for m in mods:
    name = m.__name__
    disp = m.bl_info.get("name", "?")
    if any(k in name.lower() or k in disp.lower() for k in KEY):
        enabled = addon_utils.check(name)[1]
        print(f"    {'[on] ' if enabled else '[off]'} {name:35s} :: {disp}")

# --- demonstrate enabling a bundled scripted-rig add-on: Rigify ---
print("\n[ADDON] attempting to enable Rigify...")
candidates = ["rigify", "bl_ext.blender_org.rigify", "bl_ext.system.rigify"]
enabled_mod = None
for c in candidates:
    try:
        bpy.ops.preferences.addon_enable(module=c)
        if addon_utils.check(c)[1]:
            enabled_mod = c
            break
    except Exception:
        pass

if enabled_mod:
    print(f"[ADDON] ENABLED: {enabled_mod}")
    # prove the API is live
    has_metarig = hasattr(bpy.ops.object, "armature_human_metarig_add") or \
                  "rigify" in dir(bpy.types.Scene)
    try:
        bpy.ops.object.armature_human_metarig_add()
        arm = bpy.context.active_object
        print(f"[ADDON] Rigify metarig created: {arm.name}, "
              f"{len(arm.data.bones)} bones -> scripted rigging is live")
    except Exception:
        print("[ADDON] metarig op not found under this name (still enabled):")
        traceback.print_exc()
else:
    print("[ADDON] Rigify module not found under known names")

# --- show the install entry point (not run, just report) ---
print("\n[ADDON] to install a NEW add-on from file, the call is:")
print("    bpy.ops.preferences.addon_install(filepath='C:/path/to/addon.zip')")
print("    bpy.ops.preferences.addon_enable(module='<module_name>')")
print("[ADDON] DONE")
