extends RefCounted

# Flat (faceted) shading everywhere -- Kevin, 2026-07-17. Converts any mesh into a
# flat-shaded ArrayMesh: un-indexes the triangles and gives each one its own face
# normal, so nothing is smooth-shaded. Preserves per-vertex COLOR + UV, and carries
# the source's surface material (some meshes set the material on the surface, not
# via material_override).
#
# The organic LevelGeo meshes are already flat (explicit per-face normals); this is
# for the smooth ones: terrain, Godot primitives (Sphere/Cylinder/Torus/...), the
# CSG-baked girder, and the ship hull's round parts.
#
# Normal from winding: Godot's convention is that the outward normal is ANTI-parallel
# to cross(v1-v0, v2-v0) (verified vs BoxMesh/SphereMesh in CLAUDE.md), so use the
# NEGATED cross -- otherwise every face lights inside-out.

static func flat(source: Mesh) -> Mesh:
	if source == null or source.get_surface_count() == 0:
		return source
	var a: Array = source.surface_get_arrays(0)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	if verts.size() == 0:
		return source
	var src_uv = a[Mesh.ARRAY_TEX_UV]
	var src_col = a[Mesh.ARRAY_COLOR]
	var src_idx = a[Mesh.ARRAY_INDEX]
	var has_uv: bool = src_uv is PackedVector2Array and src_uv.size() == verts.size()
	var has_col: bool = src_col is PackedColorArray and src_col.size() == verts.size()

	var idx: PackedInt32Array
	if src_idx is PackedInt32Array and src_idx.size() > 0:
		idx = src_idx
	else:
		idx = PackedInt32Array()
		idx.resize(verts.size())
		for i in range(verts.size()):
			idx[i] = i

	var ov := PackedVector3Array()
	var on := PackedVector3Array()
	var ouv := PackedVector2Array()
	var ocol := PackedColorArray()
	var t: int = 0
	while t <= idx.size() - 3:
		var i0: int = idx[t]
		var i1: int = idx[t + 1]
		var i2: int = idx[t + 2]
		var v0: Vector3 = verts[i0]
		var v1: Vector3 = verts[i1]
		var v2: Vector3 = verts[i2]
		var n: Vector3 = -(v1 - v0).cross(v2 - v0)
		if n.length() < 1e-9:
			n = Vector3.UP
		n = n.normalized()
		ov.append(v0); ov.append(v1); ov.append(v2)
		on.append(n); on.append(n); on.append(n)
		if has_uv:
			ouv.append(src_uv[i0]); ouv.append(src_uv[i1]); ouv.append(src_uv[i2])
		if has_col:
			ocol.append(src_col[i0]); ocol.append(src_col[i1]); ocol.append(src_col[i2])
		t += 3

	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = ov
	out[Mesh.ARRAY_NORMAL] = on
	if has_uv:
		out[Mesh.ARRAY_TEX_UV] = ouv
	if has_col:
		out[Mesh.ARRAY_COLOR] = ocol

	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	var srcmat: Material = source.surface_get_material(0)
	if srcmat != null:
		m.surface_set_material(0, srcmat)
	return m
