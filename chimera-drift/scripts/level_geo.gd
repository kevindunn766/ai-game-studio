extends RefCounted
class_name LevelGeo

# Mesh builders for themed level geometry, using the same loft toolkit as the
# ship generator. Props are revolved profiles with per-vertex noise displacement
# (lumpy, and unique per instance via a seed offset). The tunnel arch is lofted
# between two cross-sections so it can narrow and widen along its length.
# Grey-box geometry only (Governing Rule 2).

static var _noise: FastNoiseLite = null

static func _surf_noise() -> FastNoiseLite:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		_noise.frequency = 1.4
	return _noise

# ---------------------------------------------------------------------------
# Prop ORIGIN convention (Kevin): a planted prop's origin sits a little ABOVE its
# bottom (ANCHOR_FRAC of its height), NOT exactly on the bottom -- so when it's
# placed with the origin on the ground it embeds slightly instead of resting on
# the surface (which floats on the smallest bump / slope). Applied to every
# ground-planted builder; the ceiling stalactite uses _anchor_top (embeds into the
# ceiling). Free-floating rocks/asteroids and the spanning girder keep a centred
# origin, so they are NOT re-anchored.
# ---------------------------------------------------------------------------
const ANCHOR_FRAC := 0.08

static func _anchor_bottom(mesh: ArrayMesh, frac: float) -> ArrayMesh:
	if mesh == null or mesh.get_surface_count() == 0:
		return mesh
	var box := mesh.get_aabb()
	if box.size.y <= 0.0:
		return mesh
	return _shift_y(mesh, -(box.position.y + frac * box.size.y))

static func _anchor_top(mesh: ArrayMesh, frac: float) -> ArrayMesh:
	if mesh == null or mesh.get_surface_count() == 0:
		return mesh
	var box := mesh.get_aabb()
	if box.size.y <= 0.0:
		return mesh
	return _shift_y(mesh, -(box.position.y + box.size.y - frac * box.size.y))

# Shift every vertex in Y by `dy`, preserving normals / uv / colour / material.
static func _shift_y(mesh: ArrayMesh, dy: float) -> ArrayMesh:
	var out := ArrayMesh.new()
	for si in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in range(verts.size()):
			verts[i] = verts[i] + Vector3(0.0, dy, 0.0)
		arrays[Mesh.ARRAY_VERTEX] = verts
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var m: Material = mesh.surface_get_material(si)
		if m != null:
			out.surface_set_material(si, m)
	return out

# ---------------------------------------------------------------------------
# Tunnel arch: a smooth cave outline from (-W,0) over an apex (0,H) to (W,0),
# with near-vertical lower walls that curve into the ceiling.
# ---------------------------------------------------------------------------
static func arch_outline(half_width: float, height: float, samples: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(samples + 1):
		var t := float(i) / float(samples)
		var angle := PI * t
		pts.append(Vector2(-half_width * cos(angle), height * pow(sin(angle), 0.6)))
	return pts

# Loft a slice (contiguous index run) between two outlines (at z0 and z1) so the
# tunnel cross-section can differ end to end (narrow/widen). Normals point INWARD
# (toward `center`) because the player views these surfaces from inside the tube.
static func ribbon(outline0: PackedVector2Array, outline1: PackedVector2Array, from_i: int, to_i: int, z0: float, z1: float, center: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(from_i, to_i):
		var a0 := Vector3(outline0[i].x, outline0[i].y, z0)
		var b0 := Vector3(outline0[i + 1].x, outline0[i + 1].y, z0)
		var b1 := Vector3(outline1[i + 1].x, outline1[i + 1].y, z1)
		var a1 := Vector3(outline1[i].x, outline1[i].y, z1)
		_flat_toward(st, a0, b0, b1, center)
		_flat_toward(st, a0, b1, a1, center)
	return st.commit()

static func floor_strip(hw0: float, hw1: float, z0: float, z1: float, center: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(-hw0, 0, z0)
	var b := Vector3(hw0, 0, z0)
	var c := Vector3(hw1, 0, z1)
	var d := Vector3(-hw1, 0, z1)
	_flat_toward(st, a, c, b, center)
	_flat_toward(st, a, d, c, center)
	return st.commit()

# Flat face whose normal points TOWARD `center` (inward) -- for interior tube surfaces
# viewed from inside. The emitted WINDING is chosen to match that inward normal under
# Godot's convention (stored normal anti-parallel to cross(emitted), like BoxMesh), so a
# single-sided cull_back material shows the interior correctly lit. The old version always
# emitted one fixed winding, so on faces where the normal got flipped inward the winding no
# longer agreed with it -> those faces rendered inside-out (the "tunnel normals are wrong" bug).
static func _flat_toward(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, center: Vector3) -> void:
	var raw := (v1 - v0).cross(v2 - v0)
	if raw.length() < 0.000001:
		return
	var n := raw.normalized()
	var fc := (v0 + v1 + v2) / 3.0
	if n.dot(fc - center) > 0.0:   # pointing away from center -> flip inward
		n = -n
	# Want cross(emitted) anti-parallel to n. cross(v0,v1,v2)=raw, cross(v0,v2,v1)=-raw.
	if raw.dot(n) < 0.0:
		st.set_normal(n); st.add_vertex(v0)
		st.set_normal(n); st.add_vertex(v1)
		st.set_normal(n); st.add_vertex(v2)
	else:
		st.set_normal(n); st.add_vertex(v0)
		st.set_normal(n); st.add_vertex(v2)
		st.set_normal(n); st.add_vertex(v1)

# ---------------------------------------------------------------------------
# Props. `seed` offsets the surface noise so each instance is uniquely lumpy.
# ---------------------------------------------------------------------------
static func mushroom(scale: float, seed: float) -> ArrayMesh:
	var s := scale
	var profile: Array = [
		Vector2(0.0, 0.14 * s), Vector2(0.45 * s, 0.13 * s), Vector2(0.45 * s, 0.42 * s),
		Vector2(0.55 * s, 0.44 * s), Vector2(0.70 * s, 0.34 * s), Vector2(0.82 * s, 0.18 * s),
		Vector2(0.90 * s, 0.0),
	]
	return _anchor_bottom(_revolve(profile, 12, true, false, 0.06, seed), ANCHOR_FRAC)

static func stalagmite(scale: float, seed: float) -> ArrayMesh:
	var s := scale
	var profile: Array = [Vector2(0.0, 0.32 * s), Vector2(0.55 * s, 0.16 * s), Vector2(1.2 * s, 0.02 * s)]
	return _anchor_bottom(_revolve(profile, 9, true, false, 0.14, seed), ANCHOR_FRAC)

static func stalactite(scale: float, seed: float) -> ArrayMesh:
	var s := scale
	var profile: Array = [Vector2(0.0, 0.32 * s), Vector2(-0.55 * s, 0.16 * s), Vector2(-1.2 * s, 0.02 * s)]
	return _anchor_top(_revolve(profile, 9, true, false, 0.14, seed), ANCHOR_FRAC)

static func crystal(scale: float, seed: float) -> ArrayMesh:
	var s := scale
	var profile: Array = [Vector2(0.0, 0.28 * s), Vector2(0.62 * s, 0.28 * s), Vector2(1.0 * s, 0.04 * s)]
	return _anchor_bottom(_revolve(profile, 6, true, false, 0.05, seed), ANCHOR_FRAC)

# Blob: a parabolic dome (revolved semicircle) with noise multiplied into ALL
# axes of each vertex (uniform lumps, not radial-only like the revolve props).
# Flat bottom (sits on a surface). For spores / pods / egg clusters / barnacles.
static func blob(scale: float, seed: float) -> ArrayMesh:
	var nz := _surf_noise()
	var radius := 0.45 * scale
	var rings_v := 6
	var sides := 10
	var amp := 0.28
	var rings: Array = []
	for i in range(rings_v + 1):
		var t := float(i) / float(rings_v)
		var ang := t * PI * 0.5              # quarter arc -> dome
		var y := radius * sin(ang)
		var rad := radius * cos(ang)
		var ring: Array = []
		for j in range(sides):
			var a := TAU * float(j) / float(sides)
			var v := Vector3(cos(a) * rad, y, sin(a) * rad)
			var d := 1.0 + amp * nz.get_noise_3d(v.x * 2.5 + seed, v.y * 2.5, v.z * 2.5 + seed)
			ring.append(v * d)               # multiply ALL axes by the noise
		rings.append(ring)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0, radius * 0.4, 0)
	for k in range(rings_v):
		var r0: Array = rings[k]
		var r1: Array = rings[k + 1]
		for j in range(sides):
			var j2 := (j + 1) % sides
			_flat_face(st, r0[j], r0[j2], r1[j2], center)
			_flat_face(st, r0[j], r1[j2], r1[j], center)
	var base: Array = rings[0]               # flat bottom, faces down
	for j in range(sides):
		_flat_face_dir(st, Vector3.ZERO, base[j], base[(j + 1) % sides], Vector3.DOWN)
	return _anchor_bottom(st.commit(), ANCHOR_FRAC)

# Girder: an I-beam (top flange + bottom flange + web) extruded along Z, with a
# rough broken end -- the tip is carved concave to a noisy sphere surface (each
# end vertex recessed by sqrt(R^2 - r^2)-style depth + noise). Direct meshing,
# not CSG. For girders / cabling / wreckage / broken machinery / space junk.
static func girder(scale: float, seed: float) -> ArrayMesh:
	var nz := _surf_noise()
	var s := scale
	var length := 1.1 * s
	var fw := 0.22 * s     # flange half-width
	var ht := 0.26 * s     # half total height
	var ft := 0.09 * s     # flange thickness
	var wt := 0.06 * s     # web half-thickness
	var bite := 0.4 * s    # max broken-end depth
	var inner := ht - ft
	# I cross-section outline (12 pts).
	var o := PackedVector2Array([
		Vector2(-fw, ht), Vector2(fw, ht), Vector2(fw, inner), Vector2(wt, inner),
		Vector2(wt, -inner), Vector2(fw, -inner), Vector2(fw, -ht), Vector2(-fw, -ht),
		Vector2(-fw, -inner), Vector2(-wt, -inner), Vector2(-wt, inner), Vector2(-fw, inner)])
	# Ensure CCW so the per-edge outward normal (edge.y, -edge.x) points out.
	var area := 0.0
	for i in range(o.size()):
		var a := o[i]
		var b := o[(i + 1) % o.size()]
		area += a.x * b.y - b.x * a.y
	if area < 0.0:
		o.reverse()
	var m := o.size()
	var rmax := Vector2(fw, ht).length()
	var mid_z := length - bite
	var z_end := PackedFloat32Array()
	for i in range(m):
		var p := o[i]
		var depth := bite * clampf(1.0 - p.length() / rmax, 0.0, 1.0)
		depth *= 0.55 + 0.6 * ((nz.get_noise_2d(p.x * 10.0 + seed, p.y * 10.0) + 1.0) * 0.5)
		z_end.append(length - depth)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Side faces: straight beam (0 -> mid_z), then the broken region (mid_z -> end).
	for i in range(m):
		var i2 := (i + 1) % m
		var p0 := o[i]
		var p1 := o[i2]
		var e := p1 - p0
		var out2 := Vector2(e.y, -e.x)
		if out2.length() < 0.000001:
			continue
		var out_dir := Vector3(out2.x, out2.y, 0.0).normalized()
		var a0 := Vector3(p0.x, p0.y, 0.0)
		var a1 := Vector3(p1.x, p1.y, 0.0)
		var b0 := Vector3(p0.x, p0.y, mid_z)
		var b1 := Vector3(p1.x, p1.y, mid_z)
		var c0 := Vector3(p0.x, p0.y, z_end[i])
		var c1 := Vector3(p1.x, p1.y, z_end[i2])
		_flat_face_dir(st, a0, a1, b1, out_dir)
		_flat_face_dir(st, a0, b1, b0, out_dir)
		_flat_face_dir(st, b0, b1, c1, out_dir)
		_flat_face_dir(st, b0, c1, c0, out_dir)
	# Caps (I is non-convex -> proper polygon triangulation).
	var tris := Geometry2D.triangulate_polygon(o)
	for t in range(0, tris.size(), 3):
		var i0 := tris[t]
		var i1 := tris[t + 1]
		var i2c := tris[t + 2]
		_flat_face_dir(st, Vector3(o[i0].x, o[i0].y, 0.0), Vector3(o[i1].x, o[i1].y, 0.0),
			Vector3(o[i2c].x, o[i2c].y, 0.0), Vector3(0, 0, -1))   # start cap faces -Z
		_flat_face_dir(st, Vector3(o[i0].x, o[i0].y, z_end[i0]), Vector3(o[i1].x, o[i1].y, z_end[i1]),
			Vector3(o[i2c].x, o[i2c].y, z_end[i2c]), Vector3(0, 0, 1))   # broken end faces +Z
	return st.commit()

# Vent: an open box body (mouth faces +Y = outward from the surface), a flat
# rectangular flange frame around the mouth (a flattened 4-sided torus), and thin
# grill bars across it. Built from solid boxes (no see-through). A theme-colored
# particle system is attached at placement time (smoke up / sparks down).
static func vent(scale: float, seed: float) -> ArrayMesh:
	var s := scale
	var hw := 0.30 * s      # half mouth width (X)
	var hd := 0.24 * s      # half mouth depth (Z)
	var height := 0.34 * s  # protrudes +Y, mouth at the top
	var wt := 0.05 * s      # wall / bar thickness
	var fw := 0.10 * s      # flange width
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Body: box open at +Y -- floor plate + 4 walls (all solid, no see-through).
	_box_solid(st, Vector3(0, wt * 0.5, 0), Vector3(hw * 2, wt, hd * 2))
	_box_solid(st, Vector3(hw - wt * 0.5, height * 0.5, 0), Vector3(wt, height, hd * 2))
	_box_solid(st, Vector3(-hw + wt * 0.5, height * 0.5, 0), Vector3(wt, height, hd * 2))
	_box_solid(st, Vector3(0, height * 0.5, hd - wt * 0.5), Vector3(hw * 2, height, wt))
	_box_solid(st, Vector3(0, height * 0.5, -hd + wt * 0.5), Vector3(hw * 2, height, wt))

	# Flange frame at the mouth (four border bars = a flattened 4-sided torus).
	var oy := height
	var ohd := hd + fw
	var ft := wt * 1.2
	_box_solid(st, Vector3(hw + fw * 0.5, oy, 0), Vector3(fw, ft, ohd * 2))
	_box_solid(st, Vector3(-hw - fw * 0.5, oy, 0), Vector3(fw, ft, ohd * 2))
	_box_solid(st, Vector3(0, oy, hd + fw * 0.5), Vector3(hw * 2, ft, fw))
	_box_solid(st, Vector3(0, oy, -hd - fw * 0.5), Vector3(hw * 2, ft, fw))

	# Grill: thin bars across the mouth.
	var gy := height * 0.9
	for i in range(3):
		var zc: float = lerp(-hd * 0.55, hd * 0.55, float(i) / 2.0)
		_box_solid(st, Vector3(0, gy, zc), Vector3((hw - wt) * 2.0, wt, wt))
	return _anchor_bottom(st.commit(), ANCHOR_FRAC)

static func _box_solid(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	var c := center
	var v000 := c + Vector3(-h.x, -h.y, -h.z)
	var v100 := c + Vector3(h.x, -h.y, -h.z)
	var v110 := c + Vector3(h.x, h.y, -h.z)
	var v010 := c + Vector3(-h.x, h.y, -h.z)
	var v001 := c + Vector3(-h.x, -h.y, h.z)
	var v101 := c + Vector3(h.x, -h.y, h.z)
	var v111 := c + Vector3(h.x, h.y, h.z)
	var v011 := c + Vector3(-h.x, h.y, h.z)
	_quad(st, v101, v100, v110, v111, Vector3(1, 0, 0))
	_quad(st, v000, v001, v011, v010, Vector3(-1, 0, 0))
	_quad(st, v011, v111, v110, v010, Vector3(0, 1, 0))
	_quad(st, v000, v100, v101, v001, Vector3(0, -1, 0))
	_quad(st, v001, v101, v111, v011, Vector3(0, 0, 1))
	_quad(st, v100, v000, v010, v110, Vector3(0, 0, -1))

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out_dir: Vector3) -> void:
	_flat_face_dir(st, a, b, c, out_dir)
	_flat_face_dir(st, a, c, d, out_dir)

# Frond: a splined stalk (parabolic bend + spiral curl) tapering to a zero-width
# tip, with parabolic leaf-blades (also tapering to zero) spaced evenly up the
# spline at golden-angle azimuths. Length + leaf count are random per instance.
# Vertex COLOR.r carries a 0-at-base .. 1-at-tip sway weight for the wiggle shader.
static func frond(scale: float, seed: float) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed) * 2654435761 + 1
	var s := scale
	var variety: int = rng.randi() % 6

	# Per-variety parameter ranges (rolled below). Defaults = variety 0 (reed/kelp).
	var len_lo := 1.0;  var len_hi := 2.2         # stalk length
	var nodes_lo := 6;  var nodes_hi := 10        # number of leaf attach nodes
	var leaf_len := 0.60; var leaf_w := 0.15      # blade length / max width
	var droop_lo := 0.25; var droop_hi := 0.55    # blade arc, fraction of leaf_len
	var up_bias := 0.6; var out_bias := 0.75      # leaf points up vs. splays outward
	var curl_lo := 0.2; var curl_hi := 1.4        # spiral twist over the length
	var curve_lo := 0.18; var curve_hi := 0.55    # how far the tip leans
	var base_r := 0.05                            # stalk base radius
	var neck := 0.6                               # blade width at the join (fraction of max)
	var az_step := 2.399963                       # azimuth increment per node (golden angle)
	var pairs := false                            # two opposite leaves per node
	var t_lo := 0.12; var t_hi := 0.9             # first/last node position along the stalk
	var tip_shrink := 0.0                         # shrink leaflet length toward the tip
	match variety:
		0:                                        # reed / kelp -- tall thin blades, spiral
			pass
		1:                                        # bottlebrush -- opposite pairs rotating around
			nodes_lo = 6; nodes_hi = 9
			leaf_len = 0.42; leaf_w = 0.085
			droop_lo = 0.15; droop_hi = 0.32
			up_bias = 0.32; out_bias = 0.96
			curl_lo = 0.1; curl_hi = 0.5
			curve_lo = 0.1; curve_hi = 0.3
			pairs = true; az_step = 1.25; neck = 0.5
		2:                                        # vine / tendril -- long, very curly
			len_lo = 1.8; len_hi = 2.6
			nodes_lo = 3; nodes_hi = 6
			leaf_len = 0.4; leaf_w = 0.10
			droop_lo = 0.4; droop_hi = 0.7
			up_bias = 0.4; out_bias = 0.7
			curl_lo = 1.6; curl_hi = 3.2
			curve_lo = 0.4; curve_hi = 0.8
			base_r = 0.04; neck = 0.55
		3:                                        # broadleaf -- few wide drooping leaves
			len_lo = 0.9; len_hi = 1.5
			nodes_lo = 4; nodes_hi = 7
			leaf_len = 0.62; leaf_w = 0.30
			droop_lo = 0.35; droop_hi = 0.6
			up_bias = 0.5; out_bias = 0.85
			curl_lo = 0.2; curl_hi = 1.0
			neck = 0.65
		4:                                        # bushy grass -- many upright blades, low stalk
			len_lo = 0.8; len_hi = 1.4
			nodes_lo = 10; nodes_hi = 15
			leaf_len = 0.7; leaf_w = 0.11
			droop_lo = 0.1; droop_hi = 0.3
			up_bias = 0.9; out_bias = 0.45
			curl_lo = 0.1; curl_hi = 0.6
			curve_lo = 0.05; curve_hi = 0.2
			base_r = 0.045; t_lo = 0.05; t_hi = 0.78
		5:                                        # flat fern -- leaflets on two opposite sides,
			# in one plane (az_step 0, no twist), leaflets shrinking toward the arching tip.
			len_lo = 1.1; len_hi = 1.8
			nodes_lo = 8; nodes_hi = 13
			leaf_len = 0.5; leaf_w = 0.085
			droop_lo = 0.12; droop_hi = 0.3
			up_bias = 0.4; out_bias = 0.95
			curl_lo = 0.0; curl_hi = 0.12        # near-zero twist -> stays planar
			curve_lo = 0.22; curve_hi = 0.5      # whole frond arches over in its plane
			base_r = 0.045; neck = 0.45
			pairs = true; az_step = 0.0          # every pair on the SAME two sides
			t_lo = 0.08; t_hi = 0.94; tip_shrink = 0.45

	var length: float = s * rng.randf_range(len_lo, len_hi)
	var leaf_nodes: int = rng.randi_range(nodes_lo, nodes_hi)
	var brad: float = s * base_r
	var curve_az: float = rng.randf_range(0.0, TAU)
	var curve_amt: float = rng.randf_range(curve_lo, curve_hi) * length
	var curl: float = rng.randf_range(curl_lo, curl_hi) * (1.0 if rng.randf() < 0.5 else -1.0)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Centerline samples: lean grows parabolically (t*t) toward curve_az, and the
	# lean azimuth rotates with curl for a spiral.
	var STALK_SEG := 14
	var pts: Array = []
	for i in range(STALK_SEG + 1):
		var t: float = float(i) / float(STALK_SEG)
		var lean: float = curve_amt * t * t
		var az: float = curve_az + curl * t
		pts.append(Vector3(cos(az) * lean, length * t, sin(az) * lean))
	var tangents: Array = []
	for i in range(STALK_SEG + 1):
		var a: Vector3 = pts[max(i - 1, 0)]
		var b: Vector3 = pts[min(i + 1, STALK_SEG)]
		tangents.append((b - a).normalized())

	# Tapered tube. The final ring collapses to a point (radius 0) so the tip
	# closes to zero -- the degenerate tris there are skipped by _frond_tri.
	var SIDES := 6
	var rings: Array = []
	for i in range(STALK_SEG + 1):
		var t: float = float(i) / float(STALK_SEG)
		rings.append(_ring_around(pts[i], tangents[i], brad * (1.0 - t), SIDES))
	for i in range(STALK_SEG):
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		var w0: float = float(i) / float(STALK_SEG)
		var w1: float = float(i + 1) / float(STALK_SEG)
		var cmid: Vector3 = (pts[i] + pts[i + 1]) * 0.5
		for j in range(SIDES):
			var j2: int = (j + 1) % SIDES
			var out_dir: Vector3 = (r0[j] + r1[j]) * 0.5 - cmid   # radial outward
			_frond_quad(st, r0[j], r0[j2], r1[j2], r1[j], out_dir, w0, w0, w1, w1)

	# Leaves spaced along the stalk. `pairs` varieties emit two opposite leaves per
	# node; otherwise one leaf, its azimuth advancing by az_step (a spiral).
	for k in range(leaf_nodes):
		var tt: float = lerpf(t_lo, t_hi, float(k) / float(max(leaf_nodes - 1, 1)))
		var idx: int = int(round(tt * float(STALK_SEG)))
		var attach: Vector3 = pts[idx]
		var tan: Vector3 = tangents[idx]
		var base_az: float = curve_az + curl * tt + float(k) * az_step
		var count: int = 2 if pairs else 1
		for m in range(count):
			var az: float = base_az + float(m) * PI
			var radial: Vector3 = _perp_dir(tan, az)
			var leaf_up: Vector3 = (radial * out_bias + tan * up_bias).normalized()
			var leaf_side: Vector3 = tan.cross(leaf_up).normalized()
			if leaf_side.length() < 0.01:
				leaf_side = Vector3.RIGHT
			var leaf_norm: Vector3 = leaf_side.cross(leaf_up).normalized()
			var ll: float = s * leaf_len * rng.randf_range(0.85, 1.15) * (1.0 - tt * tip_shrink)
			var lw: float = s * leaf_w * rng.randf_range(0.85, 1.15)
			var droop: float = rng.randf_range(droop_lo, droop_hi)
			_build_leaf(st, attach, leaf_up, leaf_side, leaf_norm, ll, lw, tt, neck, droop)

	return _anchor_bottom(st.commit(), ANCHOR_FRAC)

# A ring of `sides` points in the plane perpendicular to `tangent`, centered on
# `center` at the given radius.
static func _ring_around(center: Vector3, tangent: Vector3, radius: float, sides: int) -> Array:
	var up: Vector3 = Vector3.UP
	if absf(tangent.dot(up)) > 0.95:
		up = Vector3.RIGHT
	var x: Vector3 = tangent.cross(up).normalized()
	var y: Vector3 = tangent.cross(x).normalized()
	var ring: Array = []
	for j in range(sides):
		var a: float = TAU * float(j) / float(sides)
		ring.append(center + (x * cos(a) + y * sin(a)) * radius)
	return ring

# A unit vector perpendicular to `tangent` at azimuth `az` around it.
static func _perp_dir(tangent: Vector3, az: float) -> Vector3:
	var up: Vector3 = Vector3.UP
	if absf(tangent.dot(up)) > 0.95:
		up = Vector3.RIGHT
	var x: Vector3 = tangent.cross(up).normalized()
	var y: Vector3 = tangent.cross(x).normalized()
	return (x * cos(az) + y * sin(az)).normalized()

# One parabolic leaf-blade. Width follows a parabolic taper to zero at the tip,
# AND necks in slightly where it joins the stalk (`neck` = width fraction at the
# base, ramping to full by l~0.22) so the blade doesn't meet the stalk at full
# width. The blade also arcs over (parabolic droop along -normal). Emitted with
# explicit front AND back faces (a genuine two-sided plane, not a double-sided
# material). `droop` is a fraction of leaf_len.
static func _build_leaf(st: SurfaceTool, base: Vector3, up: Vector3, side: Vector3, norm: Vector3, leaf_len: float, leaf_w: float, w_attach: float, neck: float, droop: float) -> void:
	var SEG: int = 6
	var pl_prev: Vector3 = Vector3.ZERO
	var pr_prev: Vector3 = Vector3.ZERO
	var w_prev: float = w_attach
	for i in range(SEG + 1):
		var l: float = float(i) / float(SEG)
		var necking: float = lerpf(neck, 1.0, smoothstep(0.0, 0.22, l))  # narrow at the join
		var half: float = leaf_w * 0.5 * (1.0 - l * l) * necking          # parabolic taper to 0 at tip
		var center: Vector3 = base + up * (leaf_len * l) - norm * (droop * leaf_len * l * l)
		var pl: Vector3 = center - side * half
		var pr: Vector3 = center + side * half
		var wv: float = clampf(w_attach + (1.0 - w_attach) * l * 0.4, 0.0, 1.0)
		if i > 0:
			_frond_quad(st, pl_prev, pr_prev, pr, pl, norm, w_prev, w_prev, wv, wv)     # front
			_frond_quad(st, pl, pr, pr_prev, pl_prev, -norm, wv, wv, w_prev, w_prev)    # back
		pl_prev = pl
		pr_prev = pr
		w_prev = wv

# Flat-shaded quad with per-vertex sway weight (in COLOR.r). Winding/normal match
# LevelGeo._flat_face_dir (reversed emit order for Godot's convention).
static func _frond_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out_dir: Vector3, wa: float, wb: float, wc: float, wd: float) -> void:
	_frond_tri(st, a, b, c, out_dir, wa, wb, wc)
	_frond_tri(st, a, c, d, out_dir, wa, wc, wd)

static func _frond_tri(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, out_dir: Vector3, w0: float, w1: float, w2: float) -> void:
	var raw: Vector3 = (v1 - v0).cross(v2 - v0)
	if raw.length() < 0.000001:
		return
	var n: Vector3 = raw.normalized()
	var b: Vector3 = v1
	var c: Vector3 = v2
	var wb: float = w1
	var wc: float = w2
	if n.dot(out_dir) < 0.0:
		n = -n
		var tv: Vector3 = b
		b = c
		c = tv
		var tw: float = wb
		wb = wc
		wc = tw
	# Reversed winding (v0, v2, v1) to match Godot's convention.
	st.set_color(Color(w0, 0.0, 0.0)); st.set_normal(n); st.add_vertex(v0)
	st.set_color(Color(wc, 0.0, 0.0)); st.set_normal(n); st.add_vertex(c)
	st.set_color(Color(wb, 0.0, 0.0)); st.set_normal(n); st.add_vertex(b)

# The I cross-section outline used by both the direct and CSG girders.
static func girder_outline(scale: float) -> PackedVector2Array:
	var s := scale
	var fw := 0.22 * s
	var ht := 0.26 * s
	var ft := 0.09 * s
	var wt := 0.06 * s
	var inner := ht - ft
	return PackedVector2Array([
		Vector2(-fw, ht), Vector2(fw, ht), Vector2(fw, inner), Vector2(wt, inner),
		Vector2(wt, -inner), Vector2(fw, -inner), Vector2(fw, -ht), Vector2(-fw, -ht),
		Vector2(-fw, -inner), Vector2(-wt, -inner), Vector2(-wt, inner), Vector2(-fw, inner)])

# Build a CSG tree for a per-run girder: a straight I-beam (extruded toward -Z)
# with 1-3 rough sphere bites subtracted. Returned NOT in the tree -- the caller
# adds it, waits a couple frames, bakes ONCE, frees it, then bends the baked mesh
# (CSGPolygon PATH mode bakes empty, so bending is a post-bake vertex deform).
# `bites`: array of {z: 0..1 along length, offset: Vector2 sideways, radius}.
static func girder_length(scale: float, length_mult: float) -> float:
	return 1.4 * scale * length_mult

static func build_girder_csg(scale: float, length_mult: float, bites: Array) -> CSGCombiner3D:
	var length := girder_length(scale, length_mult)
	var combiner := CSGCombiner3D.new()
	var beam := CSGPolygon3D.new()
	beam.polygon = girder_outline(scale)
	beam.mode = CSGPolygon3D.MODE_DEPTH
	beam.depth = length
	combiner.add_child(beam)

	for bite in bites:
		var sph := CSGSphere3D.new()
		sph.radius = bite.radius
		sph.radial_segments = 7   # faceted -> rough bite
		sph.rings = 4
		sph.operation = CSGShape3D.OPERATION_SUBTRACTION
		# MODE_DEPTH extrudes toward -Z, so bites live in [0, -length].
		sph.position = Vector3(bite.offset.x, bite.offset.y, -bite.z * length)
		combiner.add_child(sph)
	return combiner

static func rock(scale: float, seed: float) -> ArrayMesh:
	var s := scale
	var profile: Array = [
		Vector2(-0.42 * s, 0.02 * s), Vector2(-0.2 * s, 0.34 * s), Vector2(0.05 * s, 0.42 * s),
		Vector2(0.28 * s, 0.3 * s), Vector2(0.44 * s, 0.05 * s),
	]
	return _anchor_bottom(_revolve(profile, 7, true, true, 0.3, seed), ANCHOR_FRAC)

# Asteroid: a closed, faceted lumpy sphere (two-octave noise on all axes -- big
# bulges + finer chunk). Floats free (no flat base). For drifting meteorites.
static func asteroid(scale: float, seed: float) -> ArrayMesh:
	var nz := _surf_noise()
	var radius := 0.5 * scale
	var rings_v := 8
	var sides := 10
	var amp := 0.34
	var rings: Array = []
	for i in range(rings_v + 1):
		var t := float(i) / float(rings_v)
		var phi := t * PI                          # north pole (0) .. south pole (PI)
		var y := radius * cos(phi)
		var rad := radius * sin(phi)
		var ring: Array = []
		for j in range(sides):
			var a := TAU * float(j) / float(sides)
			var v := Vector3(cos(a) * rad, y, sin(a) * rad)
			var n1: float = nz.get_noise_3d(v.x * 2.0 + seed, v.y * 2.0, v.z * 2.0 + seed)
			var n2: float = nz.get_noise_3d(v.x * 5.0 + seed * 1.7, v.y * 5.0, v.z * 5.0)
			var d: float = 1.0 + amp * n1 + amp * 0.4 * n2
			ring.append(v * d)
		rings.append(ring)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3.ZERO
	for k in range(rings_v):
		var r0: Array = rings[k]
		var r1: Array = rings[k + 1]
		for j in range(sides):
			var j2 := (j + 1) % sides
			_flat_face(st, r0[j], r0[j2], r1[j2], center)     # pole faces collapse -> skipped
			_flat_face(st, r0[j], r1[j2], r1[j], center)
	return st.commit()

# Holed asteroid: a chunky, irregular torus -- a big rock with a clear passage
# through the middle you can fly through. Lumpiness displaces the tube radius only
# (radial from the tube's core circle), so the central hole stays open. Faceted,
# flat normals facing away from the core circle (inner hole surface faces inward).
static func holed_asteroid(scale: float, seed: float) -> ArrayMesh:
	var nz := _surf_noise()
	var R := 0.5 * scale        # major radius (hole centre -> tube centre)
	var r := 0.22 * scale       # tube radius; hole radius ~= R - r = 0.28 * scale
	var uN := 14                # segments around the ring
	var vN := 10                # segments around the tube
	var amp := 0.42
	var grid: Array = []
	var centers: Array = []
	for i in range(uN):
		var u := TAU * float(i) / float(uN)
		var cu := cos(u)
		var su := sin(u)
		var tube_center := Vector3(R * cu, R * su, 0.0)
		centers.append(tube_center)
		var uvar: float = nz.get_noise_2d(u * 1.3 + seed, seed * 0.5)   # chunky thickness around the ring
		var ring: Array = []
		for k in range(vN):
			var v := TAU * float(k) / float(vN)
			var cv := cos(v)
			var outward := Vector3(cu * cv, su * cv, sin(v))            # unit, radial from tube core
			var p0 := tube_center + outward * r
			var n1: float = nz.get_noise_3d(p0.x * 2.4 + seed, p0.y * 2.4, p0.z * 2.4 + seed)
			var n2: float = nz.get_noise_3d(p0.x * 6.0 + seed * 1.7, p0.y * 6.0, p0.z * 6.0)
			var bulge: float = amp * n1 + amp * 0.5 * n2 + amp * 0.8 * uvar
			if cv < 0.0:
				bulge = minf(bulge, 0.0)                                # inner rim: never bulge into the hole
			var d: float = maxf(1.0 + bulge, 0.35)
			ring.append(tube_center + outward * (r * d))
		grid.append(ring)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(uN):
		var i2 := (i + 1) % uN
		var mid_center: Vector3 = (centers[i] + centers[i2]) * 0.5
		var ra: Array = grid[i]
		var rb: Array = grid[i2]
		for k in range(vN):
			var k2 := (k + 1) % vN
			var out_dir_a: Vector3 = (ra[k] + rb[k] + rb[k2]) / 3.0 - mid_center
			_flat_face_dir(st, ra[k], rb[k], rb[k2], out_dir_a)
			var out_dir_b: Vector3 = (ra[k] + rb[k2] + ra[k2]) / 3.0 - mid_center
			_flat_face_dir(st, ra[k], rb[k2], ra[k2], out_dir_b)
	return st.commit()

# Rock column: narrow-waisted (hourglass) silhouette + lumpy surface.
static func pillar(radius: float, height: float, seed: float) -> ArrayMesh:
	var profile: Array = []
	var samples := 9
	for i in range(samples + 1):
		var t := float(i) / float(samples)
		var waist := 1.0 - 0.45 * sin(PI * t)              # narrow in the middle
		var lump := 1.0 + 0.14 * sin(t * 9.0 + seed)       # gentle vertical lumps
		profile.append(Vector2(t * height, radius * waist * lump))
	return _anchor_bottom(_revolve(profile, 10, true, true, 0.22, seed), ANCHOR_FRAC)

# Revolve a (y, radius) profile around Y. FLAT-SHADED: each face gets its own
# normal, computed as the true perpendicular to that face's plane and set on all
# three of its vertices (no generate_normals(), which would smooth/average across
# shared vertices and produce non-perpendicular normals). Correct for round AND
# non-round cross-sections. Per-vertex radial noise displacement makes it lumpy.
static func _revolve(profile: Array, sides: int, cap_bottom: bool, cap_top: bool, noise_amp: float, seed: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nz := _surf_noise()
	var count: int = profile.size()

	var rings: Array = []
	var centers: Array = []
	for j in range(count):
		var py: float = profile[j].x
		var prad: float = profile[j].y
		var ring: Array = []
		for i in range(sides):
			var a := TAU * float(i) / float(sides)
			var vx: float = cos(a) * prad
			var vz: float = sin(a) * prad
			var d: float = 1.0
			if noise_amp > 0.0:
				d = 1.0 + noise_amp * nz.get_noise_3d(vx + seed, py, vz + seed)
			ring.append(Vector3(vx * d, py, vz * d))
		rings.append(ring)
		centers.append(Vector3(0, py, 0))

	for k in range(count - 1):
		var r0: Array = rings[k]
		var r1: Array = rings[k + 1]
		var lc: Vector3 = (centers[k] + centers[k + 1]) * 0.5
		for i in range(sides):
			var i2 := (i + 1) % sides
			_flat_face(st, r0[i], r0[i2], r1[i2], lc)
			_flat_face(st, r0[i], r1[i2], r1[i], lc)

	if cap_bottom:
		var base: Array = rings[0]
		var cb := Vector3(0, profile[0].x, 0)
		for i in range(sides):
			_flat_face_dir(st, cb, base[i], base[(i + 1) % sides], Vector3.DOWN)
	if cap_top:
		var top: Array = rings[count - 1]
		var ct := Vector3(0, profile[count - 1].x, 0)
		for i in range(sides):
			_flat_face_dir(st, ct, top[i], top[(i + 1) % sides], Vector3.UP)

	return st.commit()

# Emit one flat triangle: normal = true perpendicular to the face, pointed
# outward (away from ref_point), same normal on all three vertices, and the
# winding flipped to match so single-sided culling shows the outer face.
static func _flat_face(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, ref_point: Vector3) -> void:
	var raw := (v1 - v0).cross(v2 - v0)
	if raw.length() < 0.000001:
		return  # skip degenerate (zero-area) triangle -- e.g. a cone/tip fan
	var n := raw.normalized()
	var fc := (v0 + v1 + v2) / 3.0
	if n.dot(fc - ref_point) < 0.0:
		n = -n
		var t := v1
		v1 = v2
		v2 = t
	# Reversed winding to match Godot's convention (stored normal = -cross of the
	# emitted winding, like BoxMesh/SphereMesh) so single-sided culling shows the
	# OUTER face. The normal `n` stays outward.
	st.set_normal(n); st.add_vertex(v0)
	st.set_normal(n); st.add_vertex(v2)
	st.set_normal(n); st.add_vertex(v1)

static func _flat_face_dir(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, out_dir: Vector3) -> void:
	var raw := (v1 - v0).cross(v2 - v0)
	if raw.length() < 0.000001:
		return
	var n := raw.normalized()
	if n.dot(out_dir) < 0.0:
		n = -n
		var t := v1
		v1 = v2
		v2 = t
	# Reversed winding to match Godot's convention (stored normal = -cross of the
	# emitted winding, like BoxMesh/SphereMesh) so single-sided culling shows the
	# OUTER face. The normal `n` stays outward.
	st.set_normal(n); st.add_vertex(v0)
	st.set_normal(n); st.add_vertex(v2)
	st.set_normal(n); st.add_vertex(v1)
