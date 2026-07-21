# Headless winding verification (docs/godot-procedural-meshes.md, best-practice #7).
# Compares per-face cross(v1-v0,v2-v0)·normal sign against Godot primitives.
# A correct mesh shows ALL faces < 0. Run:
#   godot --headless --script res://verify_winding.gd
extends SceneTree

const MeshBuilder = preload("res://scripts/mesh_builder.gd")

func _sign_report(label: String, arrays: Array) -> bool:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var tris: int = int(idx.size() / 3) if idx.size() > 0 else int(v.size() / 3)
	var pos: int = 0
	var neg: int = 0
	for t in range(tris):
		var a: int = idx[t * 3] if idx.size() > 0 else t * 3
		var b: int = idx[t * 3 + 1] if idx.size() > 0 else t * 3 + 1
		var c: int = idx[t * 3 + 2] if idx.size() > 0 else t * 3 + 2
		var d: float = (v[b] - v[a]).cross(v[c] - v[a]).dot(n[a] + n[b] + n[c])
		if d > 0.0:
			pos += 1
		elif d < 0.0:
			neg += 1
	print("%-22s cross*normal>0:%d  <0:%d  (want all <0)" % [label, pos, neg])
	return pos == 0

func _initialize() -> void:
	var ok := true
	_sign_report("BoxMesh (reference)", BoxMesh.new().get_mesh_arrays())
	_sign_report("SphereMesh (reference)", SphereMesh.new().get_mesh_arrays())
	var para: ArrayMesh = MeshBuilder.parabolic_segment(0.45, 0.4, 0.5, 16)
	ok = _sign_report("parabolic_segment", para.surface_get_arrays(0)) and ok
	var plate: ArrayMesh = MeshBuilder.body_plate(0.34, 0.45, 0.4, 1.0, 0.1)
	ok = _sign_report("body_plate", plate.surface_get_arrays(0)) and ok
	var tloft: ArrayMesh = MeshBuilder.tail_loft(0.4, 0.38, 0.72, 0.32, 5, 0.05)
	ok = _sign_report("tail_loft", tloft.surface_get_arrays(0)) and ok
	var outline: Array[Vector2] = [Vector2(0, 1), Vector2(0.7, 0.7), Vector2(1.05, 0.2), Vector2(0.95, -0.1), Vector2(0.4, -0.12), Vector2(0, -0.1)]
	var lc: ArrayMesh = MeshBuilder.loft_closed(outline, PackedFloat32Array([0.3, 0.5, 0.5, 0.3]), PackedFloat32Array([0.4, 0.58, 0.55, 0.3]), PackedFloat32Array([-0.2, -0.05, 0.1, 0.25]))
	ok = _sign_report("loft_closed", lc.surface_get_arrays(0)) and ok
	var tube: ArrayMesh = MeshBuilder.tapered_tube(0.05, 0.03, 1.0, 7)
	ok = _sign_report("tapered_tube", tube.surface_get_arrays(0)) and ok
	var head: ArrayMesh = MeshBuilder.quarter_sphere(0.4, -1.0, 12, 14)
	ok = _sign_report("quarter_sphere(-Z)", head.surface_get_arrays(0)) and ok
	var tail: ArrayMesh = MeshBuilder.quarter_sphere(0.3, 1.0, 10, 12)
	ok = _sign_report("quarter_sphere(+Z)", tail.surface_get_arrays(0)) and ok
	var seg_outline: Array[Vector2] = [Vector2(0.0, 1.0), Vector2(0.30, 0.985), Vector2(0.56, 0.94), Vector2(0.77, 0.86), Vector2(0.92, 0.72), Vector2(1.02, 0.53), Vector2(1.06, 0.33), Vector2(1.03, 0.13), Vector2(0.90, -0.05)]
	var fplate: ArrayMesh = MeshBuilder.formed_plate(seg_outline, 0.5, 0.42, 0.34)
	ok = _sign_report("formed_plate", fplate.surface_get_arrays(0)) and ok
	print("RESULT: %s" % ("ALL CORRECT" if ok else "WINDING FAULT"))
	quit()
