# Procedural mesh helpers for INSTAR body parts.
# No class_name (headless-safe); use via `const MeshBuilder = preload(...)`.
# All faces are FLAT-shaded with winding matching Godot's convention
# (stored normal = -cross(v1-v0, v2-v0)), per docs/godot-procedural-meshes.md.
extends RefCounted

# Emit one flat-shaded triangle, oriented outward from a LOCAL interior ref point.
# Order-INDEPENDENT: the outward normal is chosen from the ref point, then the emitted
# winding is chosen to satisfy Godot's convention (stored normal == -cross(winding),
# i.e. cross(emitted)·normal < 0) REGARDLESS of the caller's input vertex order.
# (The studio helper this derives from only held when callers pre-wound outward; when
#  the ref-flip triggered it left winding reversed -> inside-out. Verified numerically.)
static func _flat_face(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, ref_point: Vector3) -> void:
	var raw := (v1 - v0).cross(v2 - v0)
	if raw.length() < 1e-8:
		return
	var n := raw.normalized()
	if n.dot((v0 + v1 + v2) / 3.0 - ref_point) < 0.0:
		n = -n
	if raw.dot(n) > 0.0:
		# raw is parallel to the outward normal -> reverse winding so cross(emitted)·n < 0.
		st.set_normal(n); st.add_vertex(v0)
		st.set_normal(n); st.add_vertex(v2)
		st.set_normal(n); st.add_vertex(v1)
	else:
		# raw is anti-parallel to the outward normal -> keep winding.
		st.set_normal(n); st.add_vertex(v0)
		st.set_normal(n); st.add_vertex(v1)
		st.set_normal(n); st.add_vertex(v2)

static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ref_point: Vector3) -> void:
	_flat_face(st, a, b, c, ref_point)
	_flat_face(st, a, c, d, ref_point)

# A body segment whose cross-section is a PARABOLA: y = height * (1 - u*u),
# u in [-1, 1] across the width. Flat bottom (y=0), extruded along Z, capped.
# Local: length along Z, width along X, arch up in +Y, centered at origin.
static func parabolic_segment(half_width: float, height: float, length: float, arc_steps: int = 12) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var interior := Vector3(0.0, height * 0.35, 0.0)
	var zf := -length * 0.5
	var zb := length * 0.5
	var ring := PackedVector3Array()
	for i in range(arc_steps + 1):
		var u: float = -1.0 + 2.0 * float(i) / float(arc_steps)
		ring.append(Vector3(u * half_width, height * (1.0 - u * u), 0.0))
	# Arch side walls (front ring -> back ring).
	for i in range(arc_steps):
		var p0: Vector3 = ring[i]
		var p1: Vector3 = ring[i + 1]
		_quad(st,
			Vector3(p0.x, p0.y, zf), Vector3(p1.x, p1.y, zf),
			Vector3(p1.x, p1.y, zb), Vector3(p0.x, p0.y, zb),
			interior)
	# End caps (parabola area fans).
	var cf := Vector3(0.0, 0.0, zf)
	var cb := Vector3(0.0, 0.0, zb)
	for i in range(arc_steps):
		var p0: Vector3 = ring[i]
		var p1: Vector3 = ring[i + 1]
		_flat_face(st, cf, Vector3(p0.x, p0.y, zf), Vector3(p1.x, p1.y, zf), interior)
		_flat_face(st, cb, Vector3(p1.x, p1.y, zb), Vector3(p0.x, p0.y, zb), interior)
	# Flat bottom.
	_quad(st,
		Vector3(ring[0].x, 0.0, zf), Vector3(ring[arc_steps].x, 0.0, zf),
		Vector3(ring[arc_steps].x, 0.0, zb), Vector3(ring[0].x, 0.0, zb),
		interior)
	return st.commit()

# A quarter of a sphere: flat bottom (y=0) and flat back (z=0), rounded dome.
# `round_z` = -1.0 rounds toward -Z (a head/nose), +1.0 rounds toward +Z (a tail).
# Centered so the flat back sits at local z=0 and the flat bottom at local y=0.
static func quarter_sphere(radius: float, round_z: float, lat_steps: int = 8, lon_steps: int = 10) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3.ZERO
	# Dome surface: phi 0(top)->PI/2(equator), ang 0..PI (one z-side, both x-sides).
	for a in range(lat_steps):
		var phi0: float = PI * 0.5 * float(a) / float(lat_steps)
		var phi1: float = PI * 0.5 * float(a + 1) / float(lat_steps)
		for b in range(lon_steps):
			var an0: float = PI * float(b) / float(lon_steps)
			var an1: float = PI * float(b + 1) / float(lon_steps)
			var v00 := _sph(radius, phi0, an0, round_z)
			var v01 := _sph(radius, phi0, an1, round_z)
			var v10 := _sph(radius, phi1, an0, round_z)
			var v11 := _sph(radius, phi1, an1, round_z)
			_quad(st, v00, v01, v11, v10, center)
	# Flat bottom cap (equator half-disk, y=0).
	var bottom_ref := Vector3(0.0, radius, 0.0)
	for b in range(lon_steps):
		var an0: float = PI * float(b) / float(lon_steps)
		var an1: float = PI * float(b + 1) / float(lon_steps)
		_flat_face(st, center, _sph(radius, PI * 0.5, an0, round_z), _sph(radius, PI * 0.5, an1, round_z), bottom_ref)
	# Flat back cap (z=0 half-disk in the x-y plane).
	var back_ref := Vector3(0.0, radius * 0.3, round_z * radius)
	for k in range(lon_steps):
		var be0: float = PI * float(k) / float(lon_steps)
		var be1: float = PI * float(k + 1) / float(lon_steps)
		var pa := Vector3(radius * cos(be0), radius * sin(be0), 0.0)
		var pb := Vector3(radius * cos(be1), radius * sin(be1), 0.0)
		_flat_face(st, center, pa, pb, back_ref)
	return st.commit()

static func _sph(radius: float, phi: float, ang: float, round_z: float) -> Vector3:
	var r_ring: float = radius * sin(phi)
	return Vector3(r_ring * cos(ang), radius * cos(phi), round_z * r_ring * sin(ang))

# A leg segment: a solid tapered tube along +Y (base radius r0 at y=0 -> tip radius r1 at y=height),
# capped both ends. Traced cross-section = a circle (legs are round). Aim/scale it between two joints.
static func tapered_tube(r0: float, r1: float, height: float = 1.0, sides: int = 7) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cb := Vector3(0.0, 0.0, 0.0)
	var ct := Vector3(0.0, height, 0.0)
	for s in range(sides):
		var a0: float = TAU * float(s) / float(sides)
		var a1: float = TAU * float(s + 1) / float(sides)
		var b0 := Vector3(cos(a0) * r0, 0.0, sin(a0) * r0)
		var b1 := Vector3(cos(a1) * r0, 0.0, sin(a1) * r0)
		var t0 := Vector3(cos(a0) * r1, height, sin(a0) * r1)
		var t1 := Vector3(cos(a1) * r1, height, sin(a1) * r1)
		var ref_axis := Vector3(0.0, height * 0.5, 0.0)
		_quad(st, b0, b1, t1, t0, ref_axis)
		_flat_face(st, cb, b1, b0, ct)      # bottom cap (normal down)
		_flat_face(st, ct, t0, t1, cb)      # top cap (normal up)
	return st.commit()

# Loft a traced half cross-section `outline` (x in [0..], y anywhere) through a series of rings,
# ring k scaled by (sx[k], sy[k]) and placed at z = zs[k]. Mirrored across X=0 (perfect symmetry)
# and capped at both ends -> a closed solid. This is the code form of the three-view trace: the
# `outline` is the FRONT view; `sx`/`sy`/`zs` come from the TOP (width) and SIDE (height) traces.
static func loft_closed(outline: Array, sx: PackedFloat32Array, sy: PackedFloat32Array, zs: PackedFloat32Array, edge_lo: int = -1, edge_hi: int = -1, scallop: PackedFloat32Array = PackedFloat32Array()) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pn: int = outline.size()
	var rn: int = zs.size()
	var rings: Array[PackedVector3Array] = []
	for k in range(rn):
		var sc: float = scallop[k] if k < scallop.size() else 0.0   # epimeron lobe at ring k
		var ring := PackedVector3Array()
		for i in range(pn):
			var p: Vector2 = outline[i]
			var ex: float = (1.0 + sc) if (edge_lo >= 0 and i >= edge_lo and i <= edge_hi) else 1.0
			ring.append(Vector3(p.x * sx[k] * ex, p.y * sy[k], zs[k]))
		rings.append(ring)
	for k in range(rn - 1):
		var zc: float = (zs[k] + zs[k + 1]) * 0.5
		var ref_axis := Vector3(0.0, (sy[k] + sy[k + 1]) * 0.5 * 0.3, zc)
		for i in range(pn - 1):
			_mirror_quad(st, rings[k][i], rings[k][i + 1], rings[k + 1][i + 1], rings[k + 1][i], ref_axis)
	for capk in [0, rn - 1]:
		var ring: PackedVector3Array = rings[capk]
		var zc: float = zs[capk]
		var ctr := Vector3(0.0, sy[capk] * 0.18, zc)
		var ref_cap := Vector3(0.0, sy[capk] * 0.3, zc + (0.05 if capk == 0 else -0.05))
		for i in range(pn - 1):
			_mirror_tri(st, ctr, ring[i], ring[i + 1], ref_cap)
	return st.commit()

# The pleon + pleotelson as ONE smooth lofted tail: the plate cross-section tapers from the
# front size to a blunt rounded tip, with `grooves` shallow transverse dips marking the pleonites
# (so the tail reads segmented without telescoping into a screw). Front is capped; the tip closes.
static func tail_loft(front_hw: float, front_h: float, length: float, epimeron: float = 0.3, grooves: int = 5, groove_depth: float = 0.05, steps: int = 30) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pn: int = _PLATE_OUTLINE.size()
	var rings: Array[PackedVector3Array] = []
	for j in range(steps + 1):
		var s: float = float(j) / float(steps)
		var z: float = s * length
		var taper: float
		if s < 0.72:
			taper = lerp(1.0, 0.5, s / 0.72)                       # gentle linear taper
		else:
			var u: float = (s - 0.72) / 0.28
			taper = 0.5 * sqrt(max(1.0 - u * u, 0.0))              # round down to a blunt tip
		var g: float = 1.0
		for k in range(grooves):                                    # transverse pleonite grooves
			var gs: float = float(k + 1) / float(grooves + 1)
			var dd: float = (s - gs) / 0.03
			g -= groove_depth * exp(-0.5 * dd * dd)
		var hw: float = front_hw * taper * g
		var h: float = front_h * taper * g
		var epi: float = epimeron * taper
		var ring := PackedVector3Array()
		for i in range(pn):
			var pr: Vector2 = _PLATE_OUTLINE[i]
			var py: float = pr.y * epi if pr.y < 0.0 else pr.y
			ring.append(Vector3(pr.x * hw, py * h, z))
		rings.append(ring)
	for j in range(steps):
		var zc: float = (rings[j][0].z + rings[j + 1][0].z) * 0.5
		var ref_axis := Vector3(0.0, front_h * 0.2, zc)
		for i in range(pn - 1):
			_mirror_quad(st, rings[j][i], rings[j][i + 1], rings[j + 1][i + 1], rings[j + 1][i], ref_axis)
	# Front cap (the back tip auto-closes as taper -> 0).
	var ring0: PackedVector3Array = rings[0]
	var ctr := Vector3(0.0, front_h * 0.16, 0.0)
	var ref_cap := Vector3(0.0, front_h * 0.25, 0.1)
	for i in range(pn - 1):
		_mirror_tri(st, ctr, ring0[i], ring0[i + 1], ref_cap)
	return st.commit()

# Emit a quad AND its mirror across the X=0 plane (mirror-modifier style).
# ref_point must lie on the mirror plane (x=0) so both halves orient consistently.
# The order-independent _flat_face handles the reflected half's winding automatically.
static func _mirror_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ref_point: Vector3) -> void:
	_quad(st, a, b, c, d, ref_point)
	var m := Vector3(-1.0, 1.0, 1.0)
	_quad(st, a * m, b * m, c * m, d * m, ref_point)

# Emit a triangle AND its mirror across X=0 (ref_point must be on x=0).
static func _mirror_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ref_point: Vector3) -> void:
	_flat_face(st, a, b, c, ref_point)
	var m := Vector3(-1.0, 1.0, 1.0)
	_flat_face(st, a * m, b * m, c * m, ref_point)

# Half cross-section OUTLINE (closed), normalized to (x/half_width, y/height): traced from the
# top ridge, out over the dome, down the flank, out+down into the EPIMERON flap (the pronounced
# side edge that hangs toward the legs), then back UNDER the belly to the bottom center. Mirrored
# across X=0 it is a closed cross-section — convex domed top, hanging side flaps, concave belly.
const _PLATE_OUTLINE: Array[Vector2] = [
	Vector2(0.00, 1.00),    # 0  top ridge (top mirror seam)
	Vector2(0.36, 0.96),    # 1
	Vector2(0.66, 0.84),    # 2
	Vector2(0.87, 0.62),    # 3
	Vector2(1.00, 0.36),    # 4  shoulder
	Vector2(1.09, 0.12),    # 5
	Vector2(1.12, -0.08),   # 6  epimeron flares out
	Vector2(1.00, -0.28),   # 7  epimeron tip (hangs down toward the legs)
	Vector2(0.70, -0.24),   # 8  under the flap
	Vector2(0.37, -0.18),   # 9  belly
	Vector2(0.00, -0.14),   # 10 belly center (bottom mirror seam)
]

# A single dorsal plate, mirror-symmetric, with hanging EPIMERAL side flaps.
#   - side-to-side: the outline above (dome + flared hanging epimeron + concave belly)
#   - head-to-tail: a near-linear ramp; the FRONT edge is smaller and tucks under the plate ahead.
#     The ramp is applied MORE on the flanks than the top ridge (`front_h_side` < `front_h_center`),
#     so the dorsal midline stays smooth (a thin groove) while the flanks show the overlap step.
# `epimeron` scales how far the side flap hangs (1 = full pereonite flap, ~0.3 = small pleon flap).
static func body_plate(length: float, half_width: float, height: float, epimeron: float = 1.0, epimeron_sweep: float = 0.0, front_h_center: float = 0.98, front_h_side: float = 0.88, front_w: float = 0.96, len_steps: int = 8) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pn: int = _PLATE_OUTLINE.size()
	var rings: Array[PackedVector3Array] = []
	for j in range(len_steps + 1):
		var w: float = float(j) / float(len_steps)                     # 0 front .. 1 back
		var z: float = lerp(-length * 0.5, length * 0.5, w)
		var lw: float = front_w + (1.0 - front_w) * w
		var ring := PackedVector3Array()
		for i in range(pn):
			var pr: Vector2 = _PLATE_OUTLINE[i]
			var t: float = clamp(absf(pr.x), 0.0, 1.0)                 # 0 ridge .. 1 side edge
			var fh: float = lerp(front_h_center, front_h_side, t)
			var lh: float = fh + (1.0 - fh) * w                        # per-column height ramp
			var py: float = pr.y * epimeron if pr.y < 0.0 else pr.y    # scale only the hanging flap
			var pz: float = z + (epimeron_sweep * (-pr.y) * length if pr.y < 0.0 else 0.0)  # flap sweeps back
			ring.append(Vector3(pr.x * half_width * lw, py * height * lh, pz))
		rings.append(ring)
	# Swept outer surface (both halves).
	for j in range(len_steps):
		var zc: float = (rings[j][0].z + rings[j + 1][0].z) * 0.5
		var ref_axis := Vector3(0.0, height * 0.25, zc)
		for i in range(pn - 1):
			_mirror_quad(st, rings[j][i], rings[j][i + 1], rings[j + 1][i + 1], rings[j + 1][i], ref_axis)
	# Front + rear caps: fan the closed cross-section from its axis.
	for capj in [0, len_steps]:
		var ring: PackedVector3Array = rings[capj]
		var zc: float = ring[0].z
		var ctr := Vector3(0.0, height * 0.16, zc)
		var ref_cap := Vector3(0.0, height * 0.25, zc + (0.1 if capj == 0 else -0.1))
		for i in range(pn - 1):
			_mirror_tri(st, ctr, ring[i], ring[i + 1], ref_cap)
	return st.commit()

# ---------------------------------------------------------------------------
# Formed-plate SEGMENT (INSTAR isopod tergite). Per Kevin's direction: instead of a
# solid cross-section WEDGE, form a flat (j,k) plane INTO one curved armour plate — the
# three-view trace of a SINGLE segment — then SOLIDIFY it (inner offset + rim bridge)
# so the shell has real thickness. Built symmetric (the traced half-outline is mirrored
# into the full cross-section); flat per-face normals, winding to Godot convention (verified).
#   half_outline  : traced FRONT half cross-section, dorsal midline -> epimeron tip. OPEN
#                   arc (x = half-width frac, y = height frac). No belly — it's a plate/shell.
#   front_narrow  : TOP view — front edge width relative to the full back edge (tucks under).
#   proud         : SIDE view — rear cross-section sits proud so it overhangs the next plate.
#   epimeron_sweep: TOP view — the outer (epimeron) columns sweep backward to a pointed tip.
#   length_curve  : SIDE view — gentle convex dorsal arc along the plate's length (shingle bow).
#   thickness     : solidify — shell wall thickness.
static func formed_plate(half_outline: Array, half_width: float, height: float, length: float, len_steps: int = 6, front_narrow: float = 0.9, proud: float = 0.10, epimeron_sweep: float = 0.18, length_curve: float = 0.08, thickness: float = 0.03) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Mirror the traced half into a full symmetric cross-section: left tip .. midline .. right tip.
	var hn: int = half_outline.size()
	var full: Array = []
	for i in range(hn - 1, 0, -1):
		var pl: Vector2 = half_outline[i]
		full.append(Vector2(-pl.x, pl.y))
	for i in range(hn):
		full.append(half_outline[i])
	var kn: int = full.size()
	var sweepw: Array = []
	for k in range(kn):
		var pf: Vector2 = full[k]
		sweepw.append(clamp(absf(pf.x), 0.0, 1.0))     # 0 at dorsal midline, 1 at the epimeron
	# Form the flat plane into the outer shell surface (grid of rings j x columns k).
	var jn: int = len_steps + 1
	var outer: Array = []
	for j in range(jn):
		var t: float = float(j) / float(len_steps)     # 0 front .. 1 back
		var z0: float = lerp(-length * 0.5, length * 0.5, t)
		var wsc: float = lerp(front_narrow, 1.0, t)
		var psc: float = 1.0 + proud * t               # rear proud -> overhangs
		var yarc: float = length_curve * height * (1.0 - 4.0 * (t - 0.5) * (t - 0.5))  # convex tile bow
		var ring: Array = []
		for k in range(kn):
			var p: Vector2 = full[k]
			var sw: float = sweepw[k]
			var x: float = p.x * half_width * wsc * psc
			var y: float = p.y * height * psc + yarc
			var z: float = z0 + epimeron_sweep * sw * length
			ring.append(Vector3(x, y, z))
		outer.append(ring)
	# Averaged vertex normals for a clean solidify offset; ref BELOW the plate = cavity side.
	var ref_low := Vector3(0.0, -height * 1.2, 0.0)
	var vn: Array = []
	for j in range(jn):
		var rn: Array = []
		for k in range(kn):
			rn.append(Vector3.ZERO)
		vn.append(rn)
	for j in range(len_steps):
		for k in range(kn - 1):
			var a: Vector3 = outer[j][k]
			var b: Vector3 = outer[j][k + 1]
			var c: Vector3 = outer[j + 1][k + 1]
			var d: Vector3 = outer[j + 1][k]
			var raw: Vector3 = (b - a).cross(d - a)
			if raw.length() < 1e-9:
				continue
			var fn: Vector3 = raw.normalized()
			var ctr: Vector3 = (a + b + c + d) * 0.25
			if fn.dot(ctr - ref_low) < 0.0:
				fn = -fn
			vn[j][k] = (vn[j][k] as Vector3) + fn
			vn[j][k + 1] = (vn[j][k + 1] as Vector3) + fn
			vn[j + 1][k + 1] = (vn[j + 1][k + 1] as Vector3) + fn
			vn[j + 1][k] = (vn[j + 1][k] as Vector3) + fn
	for j in range(jn):
		for k in range(kn):
			var nv: Vector3 = vn[j][k]
			vn[j][k] = nv.normalized() if nv.length() > 1e-9 else Vector3.UP
	# Inner surface = outer pushed in along -vertex normal (the solidify wall).
	var inner: Array = []
	for j in range(jn):
		var ri: Array = []
		for k in range(kn):
			ri.append((outer[j][k] as Vector3) - (vn[j][k] as Vector3) * thickness)
		inner.append(ri)
	# Emit outer (outward-facing) + inner (cavity-facing) shells.
	for j in range(len_steps):
		for k in range(kn - 1):
			var oa: Vector3 = outer[j][k]
			var ob: Vector3 = outer[j][k + 1]
			var oc: Vector3 = outer[j + 1][k + 1]
			var od: Vector3 = outer[j + 1][k]
			_emit_tri(st, oa, ob, oc, _face_normal(oa, ob, oc, ref_low, false))
			_emit_tri(st, oa, oc, od, _face_normal(oa, oc, od, ref_low, false))
			var ia: Vector3 = inner[j][k]
			var ib: Vector3 = inner[j][k + 1]
			var ic: Vector3 = inner[j + 1][k + 1]
			var idd: Vector3 = inner[j + 1][k]
			_emit_tri(st, ia, ib, ic, _face_normal(ia, ib, ic, ref_low, true))
			_emit_tri(st, ia, ic, idd, _face_normal(ia, ic, idd, ref_low, true))
	# Bridge the open rims (front, back, both epimeron-tip edges) -> a closed solid.
	var ref_c := Vector3(0.0, height * 0.30, 0.0)
	for jb in [0, len_steps]:
		for k in range(kn - 1):
			_bridge_quad(st, outer[jb][k], outer[jb][k + 1], inner[jb][k + 1], inner[jb][k], ref_c)
	for kb in [0, kn - 1]:
		for j in range(len_steps):
			_bridge_quad(st, outer[j][kb], outer[j + 1][kb], inner[j + 1][kb], inner[j][kb], ref_c)
	return st.commit()

# Outward (or cavity-facing) flat normal for a tri, oriented via a reference point.
# toward_ref=false -> normal points AWAY from ref (outer shell / rim); true -> toward ref (inner shell).
static func _face_normal(a: Vector3, b: Vector3, c: Vector3, ref: Vector3, toward_ref: bool) -> Vector3:
	var raw: Vector3 = (b - a).cross(c - a)
	if raw.length() < 1e-12:
		return Vector3.UP
	var n: Vector3 = raw.normalized()
	var away: float = n.dot((a + b + c) / 3.0 - ref)
	if toward_ref and away > 0.0:
		n = -n
	elif not toward_ref and away < 0.0:
		n = -n
	return n

# Emit a flat tri with a KNOWN target normal; winding chosen to satisfy Godot's convention
# (cross(emitted)·normal < 0) regardless of input vertex order (like _flat_face, but the
# normal is given rather than derived from a ref point).
static func _emit_tri(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, n: Vector3) -> void:
	var raw: Vector3 = (v1 - v0).cross(v2 - v0)
	if raw.length() < 1e-12:
		return
	if raw.dot(n) > 0.0:
		var tmp: Vector3 = v1
		v1 = v2
		v2 = tmp
	st.set_normal(n); st.add_vertex(v0)
	st.set_normal(n); st.add_vertex(v1)
	st.set_normal(n); st.add_vertex(v2)

static func _bridge_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ref: Vector3) -> void:
	_emit_tri(st, a, b, c, _face_normal(a, b, c, ref, false))
	_emit_tri(st, a, c, d, _face_normal(a, c, d, ref, false))
