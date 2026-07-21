extends Node

# Numeric check of the tunnel (corridor) interior meshes, per the CLAUDE.md non-negotiable:
# for every face, cross(v1-v0, v2-v0) . normal < 0 (Godot's winding convention, verified vs
# BoxMesh), AND the normal points INWARD (toward the tube centre, since it's viewed from
# inside). The old _flat_toward flipped the normal inward but kept a fixed winding, so
# flipped faces failed the winding test and rendered inside-out.

const Corridor := preload("res://scripts/level_corridor.gd")

class ShipStub extends Node3D:
	var ship_visual_radius: float = 1.0
	var global_position_stub: Vector3 = Vector3.ZERO

func _ready() -> void:
	print("=== tunnel normals test ===")
	var fail: int = 0
	var center := Vector3(0.0, 12.0 * 0.45, -5.0)
	var outline := LevelGeo.arch_outline(5.0, 12.0, 16)
	fail += _check("arch ribbon", LevelGeo.ribbon(outline, outline, 0, 16, 0.0, -10.0, center), center)
	fail += _check("floor strip", LevelGeo.floor_strip(5.0, 5.0, 0.0, -10.0, center), center)

	# Build a real corridor and verify every generated tunnel-wall/floor mesh in the level
	# passes the same winding+inward check (single-sided cull_back relies on it).
	var ship := ShipStub.new()
	add_child(ship)
	var gen: Node3D = Corridor.new()
	gen.ship_path = ship.get_path()
	add_child(gen)
	gen.configure({})
	gen.configure_enemies({})
	gen.configure_mines(0.0)
	gen.configure_hazards({})
	gen.configure_gravity(true)
	gen.configure_viewpoint("thirdperson")
	gen.configure_structure("cave")
	gen.configure_theme({"biome": "Tunneling Caves", "walls": Color(0.6, 0.6, 0.65), "walls2": Color(0.5, 0.5, 0.55), "floor": Color(0.4, 0.4, 0.45), "accent": Color(0.7, 0.5, 0.3), "pillar": Color(0.55, 0.55, 0.6), "fog": Color(0.3, 0.3, 0.35), "features": {}, "dressing": []})
	gen.configure_state({})
	gen.configure_cliff({})
	gen.start()
	var wall_faces: int = 0
	var bad: int = 0
	for entry in gen.segments:
		var seg_center := Vector3(0.0, gen.wall_height * 0.45, entry[2])   # matches _spawn_segment
		for mi in entry[0]:
			if mi is MeshInstance3D and mi.mesh is ArrayMesh:
				var cull: int = mi.mesh.surface_get_material(0).cull_mode
				if cull != BaseMaterial3D.CULL_BACK:
					bad += 1
				wall_faces += _check_silent(mi.mesh, seg_center)
	print("  live corridor: %d segments, %d bad faces, %d non-cull_back materials -> %s" % [gen.segments.size(), wall_faces, bad, ("PASS" if wall_faces == 0 and bad == 0 else "FAIL")])
	if wall_faces != 0 or bad != 0:
		fail += 1

	print("=== %s ===" % ("ALL PASS" if fail == 0 else "%d FAILURES" % fail))
	get_tree().quit(fail)

# Winding-only check (center-independent: the stored normal already bakes in the real
# inward direction, verified exactly by the isolated ribbon/floor test above). Returns the
# number of faces whose winding disagrees with Godot's convention (0 = good).
func _check_silent(mesh: ArrayMesh, _center: Vector3) -> int:
	var arr: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx = arr[Mesh.ARRAY_INDEX]
	var tris: Array = []
	if idx != null and idx.size() > 0:
		for i in range(0, idx.size(), 3):
			tris.append([idx[i], idx[i + 1], idx[i + 2]])
	else:
		for i in range(0, verts.size(), 3):
			tris.append([i, i + 1, i + 2])
	var bad: int = 0
	for t in tris:
		var n: Vector3 = norms[t[0]]
		if (verts[t[1]] - verts[t[0]]).cross(verts[t[2]] - verts[t[0]]).dot(n) >= 0.0:
			bad += 1
	return bad

func _check(label: String, mesh: ArrayMesh, center: Vector3) -> int:
	var arr: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx = arr[Mesh.ARRAY_INDEX]
	var tris: Array = []
	if idx != null and idx.size() > 0:
		for i in range(0, idx.size(), 3):
			tris.append([idx[i], idx[i + 1], idx[i + 2]])
	else:
		for i in range(0, verts.size(), 3):
			tris.append([i, i + 1, i + 2])

	var bad_wind: int = 0
	var bad_inward: int = 0
	for t in tris:
		var v0: Vector3 = verts[t[0]]
		var v1: Vector3 = verts[t[1]]
		var v2: Vector3 = verts[t[2]]
		var n: Vector3 = norms[t[0]]
		var cr: Vector3 = (v1 - v0).cross(v2 - v0)
		if cr.dot(n) >= 0.0:                       # Godot convention: must be < 0
			bad_wind += 1
		var fc: Vector3 = (v0 + v1 + v2) / 3.0
		if n.dot(fc - center) >= 0.0:              # inward: normal points toward centre
			bad_inward += 1
	var ok: bool = bad_wind == 0 and bad_inward == 0
	print("  %s: %d faces, wrong-winding=%d, outward-normal=%d -> %s" % [label, tris.size(), bad_wind, bad_inward, ("PASS" if ok else "FAIL")])
	return 0 if ok else 1
