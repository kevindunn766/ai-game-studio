extends RefCounted
class_name ShipHullGenerator

# Procedural ship-hull generator. Rolled once per run (see RunManager), kept
# through death-retries, re-rolled only on returning to the menu.
#
# HARD-SURFACE + MODULAR. A ship is a crisp core BODY plus independently-rolled
# ADD-ONS (nose, cockpit, engines, wings, fins, greeble). This is deliberately
# NOT a single swept loft -- that only ever made smooth elongated blobs. Here
# boxy/faceted bodies dominate, round forms are a minority and always broken up
# by add-ons, and proportions vary widely (wide deltas, tall blocks, cubes), so
# the fleet reads as varied built machines with no bias toward any one shape.
#
# Honors the design description: start from a box/primitive, insert edge loops
# and scale their cross-sections (in/out, occasionally large), scale end faces
# (crisp wedges), bevel edges (chamfered/faceted profiles), swept spline wings
# with optional cylinder/box tip pods, plus torus/saucer/cone/prism forms.
# Round surfaces smooth-shaded; boxy/faceted surfaces flat-shaded (crisp edges).
# Colors are an analogous ColorAid scheme mapped across the parts.
#
# Grey-box geometry only; no shaders/particles (Governing Rule 2).

enum Body { BOXY, DELTA, BLOCKY, PRISM, ROUND, SAUCER, TORUS, TRIANGLE, CROSS }

# Weighted so boxy/angular forms dominate and round forms stay a minority.
const BODY_WEIGHTS := {
	Body.BOXY: 24, Body.DELTA: 18, Body.BLOCKY: 15, Body.PRISM: 13,
	Body.TRIANGLE: 12, Body.CROSS: 10, Body.ROUND: 9, Body.SAUCER: 7, Body.TORUS: 5,
}

const TARGET_LONGEST: float = 2.2   # baked hull normalized to this extent

# ---------------------------------------------------------------------------
# Public entry point. Returns { hull: Node3D, aabb: AABB, colors, spec }.
# ---------------------------------------------------------------------------
static func generate(rng: RandomNumberGenerator) -> Dictionary:
	var spec := _roll_spec(rng)
	var colors: Array = ColorAid.analogous_scheme(rng, 6)
	var hull := Node3D.new()
	var acc := {"bounds": AABB(), "have": false}

	# --- Core body ---------------------------------------------------------
	var body := _build_body(spec, rng)   # {mesh, half_w, half_h, front_z, tail_z}
	_add_part(hull, body.mesh, colors[0], Transform3D.IDENTITY, acc)

	var half_w: float = body.half_w
	var half_h: float = body.half_h
	var front_z: float = body.front_z
	var tail_z: float = body.tail_z

	# --- Nose piece (crisp pointed wedge/cone) -----------------------------
	if spec.nose:
		var nose_len: float = rng.randf_range(0.4, 0.9)
		var nose := _cone_mesh(half_h * rng.randf_range(0.5, 0.9), half_w * rng.randf_range(0.6, 1.0), nose_len, spec.body != Body.BOXY and spec.body != Body.BLOCKY)
		var xf := Transform3D(Basis.IDENTITY, Vector3(0, 0, front_z - nose_len * 0.5))
		_add_part(hull, nose, colors[4], xf, acc)

	# --- Cockpit bump (box or dome, top-front) -----------------------------
	if spec.cockpit:
		var cw: float = half_w * rng.randf_range(0.4, 0.7)
		var ch: float = half_h * rng.randf_range(0.5, 0.9)
		var cl: float = (tail_z - front_z) * rng.randf_range(0.22, 0.4)
		var cz: float = lerp(front_z, tail_z, rng.randf_range(0.28, 0.5))
		var cockpit: ArrayMesh
		if rng.randf() < 0.5:
			cockpit = _dome_mesh(maxf(cw, ch))
		else:
			cockpit = _box_mesh(Vector3(cw * 2.0, ch * 2.0, cl))
		_add_part(hull, cockpit, colors[3], Transform3D(Basis.IDENTITY, Vector3(0, half_h * 0.8, cz)), acc)

	# --- Engine blocks / nozzles at the tail (mirrored) --------------------
	if spec.engines > 0:
		var er: float = half_h * rng.randf_range(0.35, 0.6)
		var elen: float = rng.randf_range(0.35, 0.7)
		var spread: float = half_w * 0.55
		for i in range(spec.engines):
			var ex: float = 0.0
			if spec.engines > 1:
				ex = lerp(-spread, spread, float(i) / float(spec.engines - 1))
			var eng := _cylinder_mesh(er, elen, true)
			_add_part(hull, eng, colors[2], Transform3D(Basis.IDENTITY, Vector3(ex, -half_h * 0.15, tail_z + elen * 0.4)), acc)

	# --- Wings (swept spline, mirrored, optional tip pods) -----------------
	if spec.wings:
		var wing := _build_wing(spec, rng)
		var wz: float = lerp(front_z, tail_z, rng.randf_range(0.45, 0.75))
		var xf_r := Transform3D(Basis.IDENTITY, Vector3(half_w * 0.85, 0.0, wz))
		_add_part(hull, wing.mesh, colors[1], xf_r, acc)
		if spec.wingtip_pod != "":
			_add_pod(hull, spec, colors[4], xf_r * Transform3D(Basis.IDENTITY, wing.tip), wing, acc)
		if spec.mirror_x:
			var mb := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
			var xf_l := Transform3D(mb, Vector3(-half_w * 0.85, 0.0, wz))
			_add_part(hull, wing.mesh, colors[1], xf_l, acc)
			if spec.wingtip_pod != "":
				_add_pod(hull, spec, colors[4], xf_l * Transform3D(Basis.IDENTITY, wing.tip), wing, acc)

	# --- Fins (vertical tail and/or radial) --------------------------------
	if spec.fin_count > 0:
		for i in range(spec.fin_count):
			var fin := _build_wing(spec, rng, true)
			var basis: Basis
			var offset: Vector3
			if spec.fin_radial:
				var ang: float = TAU * float(i) / float(spec.fin_count) + spec.fin_phase
				basis = Basis(Vector3(0, 0, 1), ang)
				offset = basis * Vector3(maxf(half_w, half_h) * 0.9, 0, tail_z - 0.2)
			else:
				# Vertical tail fin(s): rotate the wing up onto the Y axis.
				basis = Basis(Vector3(0, 0, 1), PI * 0.5)
				var fx: float = 0.0 if spec.fin_count == 1 else lerp(-half_w * 0.6, half_w * 0.6, float(i) / float(spec.fin_count - 1))
				offset = Vector3(fx, half_h * 0.7, tail_z - 0.25)
			_add_part(hull, fin.mesh, colors[2], Transform3D(basis, offset), acc)

	# Greeble surface boxes removed (Kevin, 2026-07-20 -- they didn't look good).
	# spec.greeble is still rolled in _roll_spec so the rest of the seed is unchanged;
	# we just no longer build the boxes here (this was the last step, so nothing after
	# it shifts).

	return {"hull": hull, "aabb": acc.bounds, "colors": colors, "spec": spec}

# ---------------------------------------------------------------------------
# Attribute roll
# ---------------------------------------------------------------------------
static func _roll_spec(rng: RandomNumberGenerator) -> Dictionary:
	var symmetric: bool = rng.randf() < 0.8
	var body: int = _weighted_pick(BODY_WEIGHTS, rng)

	var spec := {
		"symmetric": symmetric,
		"mirror_x": symmetric,
		"body": body,
		"amplify": 2.6 if rng.randf() < 0.18 else 1.0,   # occasional extremes
		"nose": false,
		"cockpit": false,
		"engines": 0,
		"wings": false,
		"wingtip_pod": "",
		"fin_count": 0,
		"fin_radial": false,
		"fin_phase": rng.randf_range(0.0, TAU),
		"greeble": 0,
		"torus_inner": rng.randf_range(0.45, 0.7),
		"torus_outer": rng.randf_range(1.0, 1.25),
	}

	# Add-on loadout, biased per body so each archetype reads distinct but every
	# ship still gets silhouette-breaking pieces (never a bare shaft).
	spec.nose = rng.randf() < (0.75 if body in [Body.BOXY, Body.DELTA, Body.ROUND, Body.PRISM, Body.TRIANGLE] else 0.3)
	spec.cockpit = rng.randf() < 0.55
	spec.engines = rng.randi_range(0, 3)
	match body:
		Body.ROUND:
			# Round bodies MUST be broken up so they never read phallic.
			spec.wings = true
			spec.fin_count = rng.randi_range(1, 3)
			spec.fin_radial = rng.randf() < 0.4
		Body.BOXY, Body.DELTA:
			spec.wings = rng.randf() < 0.65
			if rng.randf() < 0.5:
				spec.fin_count = rng.randi_range(1, 2)
		Body.PRISM:
			spec.wings = rng.randf() < 0.4
			spec.fin_count = rng.randi_range(0, 3)
			spec.fin_radial = rng.randf() < 0.5
		Body.BLOCKY:
			spec.wings = rng.randf() < 0.35
			spec.greeble += rng.randi_range(3, 7)
		Body.TRIANGLE:
			spec.wings = rng.randf() < 0.5
			spec.fin_count = rng.randi_range(0, 2)
		Body.CROSS:
			# Already a 4-armed plus -- keep add-ons sparse so the cross reads.
			spec.wings = rng.randf() < 0.2
			spec.fin_count = 0
			spec.nose = rng.randf() < 0.6
		Body.SAUCER:
			spec.cockpit = true
			spec.fin_count = 0
		Body.TORUS:
			spec.nose = false
			spec.engines = 0   # no rod skewered through the ring
			spec.greeble = 0
			spec.cockpit = rng.randf() < 0.3

	if spec.wings and rng.randf() < 0.4:
		spec.wingtip_pod = "cylinder" if rng.randf() < 0.5 else "box"
	spec.greeble += (rng.randi_range(0, 4) if rng.randf() < 0.5 else 0)
	if not symmetric:
		spec.greeble += 1  # asymmetric ships get an off-center lump
	return spec

static func _weighted_pick(weights: Dictionary, rng: RandomNumberGenerator) -> int:
	var total := 0
	for k in weights:
		total += weights[k]
	var roll := rng.randi_range(0, total - 1)
	for k in weights:
		roll -= weights[k]
		if roll < 0:
			return k
	return weights.keys()[0]

# ---------------------------------------------------------------------------
# Core body. Returns { mesh, half_w, half_h, front_z, tail_z }.
# ---------------------------------------------------------------------------
static func _build_body(spec: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var body: int = spec.body
	if body == Body.TORUS:
		var mesh := _torus_mesh(spec.torus_outer, (spec.torus_outer - spec.torus_inner) * 0.5, 24, 14)
		return {"mesh": mesh, "half_w": spec.torus_outer, "half_h": (spec.torus_outer - spec.torus_inner) * 0.5, "front_z": -spec.torus_outer * 0.3, "tail_z": spec.torus_outer * 0.3}
	if body == Body.SAUCER:
		return _build_saucer(rng)

	# Loft-based bodies: pick a cross-section, base half-extents, length, and
	# station scales (edge loops + end-face scaling), flat-shaded unless round.
	var sides: int
	var smooth: bool
	match body:
		Body.PRISM:
			sides = [5, 6, 8][rng.randi_range(0, 2)]
			smooth = false
		Body.ROUND:
			sides = rng.randi_range(16, 22)
			smooth = true
		Body.TRIANGLE:
			sides = 3
			smooth = false
		Body.CROSS:
			sides = -1   # plus-shaped cross-section (see _plus_profile)
			smooth = false
		_:  # BOXY, DELTA, BLOCKY
			sides = 4
			smooth = false

	# Bevel (chamfer) the sharpest corners -- the angular cross-sections (box + tri).
	# Kevin: bias hard toward beveled so the sharpest hull corners read chamfered.
	var profile: PackedVector2Array
	if body == Body.CROSS:
		profile = _plus_profile(rng)
	else:
		var bevel: float = 0.0
		if (sides == 3 or sides == 4) and rng.randf() < 0.85:
			bevel = clampf(rng.randf_range(0.1, 0.3) * spec.amplify, 0.0, 0.45)
		profile = _profile(sides, bevel)

	var length: float
	var base_w: float
	var base_h: float
	var nose_scale: float   # front end-face scale (crisp wedge)
	var tail_scale: float
	match body:
		Body.DELTA:
			length = rng.randf_range(1.9, 2.6)
			base_w = rng.randf_range(1.2, 1.8)
			base_h = rng.randf_range(0.22, 0.36)
			nose_scale = rng.randf_range(0.1, 0.22)
			tail_scale = rng.randf_range(0.85, 1.05)
		Body.BLOCKY:
			length = rng.randf_range(1.2, 1.8)
			base_w = rng.randf_range(0.85, 1.15)
			base_h = rng.randf_range(0.7, 1.0)
			nose_scale = rng.randf_range(0.6, 0.95)
			tail_scale = rng.randf_range(0.7, 1.0)
		Body.ROUND:
			length = rng.randf_range(1.7, 2.4)
			base_w = rng.randf_range(0.7, 1.0)
			base_h = base_w * rng.randf_range(0.5, 0.72)
			nose_scale = rng.randf_range(0.28, 0.5)
			tail_scale = rng.randf_range(0.6, 0.9)
		Body.PRISM:
			length = rng.randf_range(1.6, 2.4)
			base_w = rng.randf_range(0.6, 0.95)
			base_h = base_w * rng.randf_range(0.6, 1.0)
			nose_scale = rng.randf_range(0.3, 0.7)
			tail_scale = rng.randf_range(0.7, 1.0)
		Body.TRIANGLE:
			length = rng.randf_range(1.7, 2.5)
			base_w = rng.randf_range(0.7, 1.15)
			base_h = base_w * rng.randf_range(0.7, 1.0)
			nose_scale = rng.randf_range(0.18, 0.6)
			tail_scale = rng.randf_range(0.8, 1.05)
		Body.CROSS:
			length = rng.randf_range(1.7, 2.5)
			base_w = rng.randf_range(1.0, 1.45)
			base_h = base_w                       # symmetric plus (X == Y span)
			nose_scale = rng.randf_range(0.5, 0.9)
			tail_scale = rng.randf_range(0.7, 1.0)
		_:  # BOXY
			length = rng.randf_range(1.6, 2.5)
			base_w = rng.randf_range(0.7, 1.1)
			base_h = rng.randf_range(0.45, 0.85)
			nose_scale = rng.randf_range(0.35, 0.7)
			tail_scale = rng.randf_range(0.75, 1.05)

	var stations := _body_stations(length, base_w, base_h, nose_scale, tail_scale, spec, rng)
	var mesh := _loft_stations(profile, stations, smooth)
	return {
		"mesh": mesh,
		"half_w": base_w * 0.5,
		"half_h": base_h * 0.5,
		"front_z": -length * 0.5,
		"tail_z": length * 0.5,
	}

# Stations tail(+z)->nose(-z): base cross-section scaled by end-face scales,
# then edge loops inserted/scaled (subtle, occasionally large).
static func _body_stations(length: float, base_w: float, base_h: float, nose_scale: float, tail_scale: float, spec: Dictionary, rng: RandomNumberGenerator) -> Array:
	var n := 6
	var stations: Array = []
	for i in range(n):
		var t := float(i) / float(n - 1)              # 0=tail .. 1=nose
		var face: float = lerp(tail_scale, nose_scale, smoothstep(0.15, 1.0, t))
		var jx := 1.0 + rng.randf_range(-0.04, 0.04)
		var jy := 1.0 + rng.randf_range(-0.04, 0.04)
		stations.append({
			"z": lerp(length * 0.5, -length * 0.5, t),
			"sx": base_w * 0.5 * face * jx,
			"sy": base_h * 0.5 * face * jy,
		})

	# Edge loops: pick loops, scale their cross-section in/out or bevel-insert.
	var loops := int(round(rng.randf_range(0.0, 2.5) * spec.amplify))
	for _i in range(loops):
		if stations.size() < 3:
			break
		var idx := rng.randi_range(1, stations.size() - 2)
		var factor := rng.randf_range(0.78, 1.28)
		if rng.randf() < 0.15:
			factor = rng.randf_range(0.45, 1.7)
		if rng.randf() < 0.5:
			var s: Dictionary = stations[idx]
			s.sx *= factor
			s.sy *= factor
		else:
			var base: Dictionary = stations[idx]
			var a: Dictionary = base.duplicate()
			var b: Dictionary = base.duplicate()
			var dz := length * 0.02
			a.z += dz
			b.z -= dz
			a.sx *= factor
			a.sy *= factor
			b.sx *= factor
			b.sy *= factor
			stations[idx] = a
			stations.insert(idx + 1, b)

	_finalize_stations(stations, length)
	return stations

static func _finalize_stations(stations: Array, length: float) -> void:
	stations.sort_custom(func(a, b): return a.z > b.z)
	var min_gap := length * 0.005
	var i := stations.size() - 1
	while i > 0:
		if abs(stations[i].z - stations[i - 1].z) < min_gap:
			stations.remove_at(i)
		i -= 1
	for s in stations:
		s.sx = maxf(s.sx, 0.02)
		s.sy = maxf(s.sy, 0.02)

static func _build_saucer(rng: RandomNumberGenerator) -> Dictionary:
	var sides := rng.randi_range(18, 26)
	var profile := _profile(sides, 0.0)
	var radius := rng.randf_range(1.0, 1.4)
	var thick := radius * rng.randf_range(0.16, 0.28)
	var n := 7
	var stations: Array = []
	for i in range(n):
		var t := float(i) / float(n - 1)
		var disc: float = sin(PI * clampf(t, 0.03, 0.97))
		stations.append({"z": lerp(thick, -thick, t), "sx": radius * (0.35 + 0.65 * disc), "sy": radius * (0.35 + 0.65 * disc)})
	# Flatten Y after the fact so it reads as a disc, not a sphere.
	var mesh := _loft_stations(profile, stations, true, 0.32)
	return {"mesh": mesh, "half_w": radius, "half_h": radius * 0.32 * 0.5, "front_z": -thick, "tail_z": thick}

# ---------------------------------------------------------------------------
# Cross-section profiles (unit polygon in XY, ~[-0.5, 0.5])
# ---------------------------------------------------------------------------
static func _profile(sides: int, bevel: float) -> PackedVector2Array:
	var raw := PackedVector2Array()
	if sides == 4:
		var h := 0.5
		raw.append(Vector2(-h, -h)); raw.append(Vector2(h, -h))
		raw.append(Vector2(h, h)); raw.append(Vector2(-h, h))
	else:
		# Odd polygons (triangle, pentagon) point UP with a flat bottom; even
		# polygons keep the original orientation (flat top/bottom).
		var off: float = PI * 0.5 if sides % 2 == 1 else 0.0
		for i in range(sides):
			var a := TAU * float(i) / float(sides) + off
			raw.append(Vector2(cos(a) * 0.5, sin(a) * 0.5))
	if bevel <= 0.001:
		return raw
	return _chamfer(raw, bevel)

# Chamfer every corner of a polygon: replace each vertex with two points set back
# along its two edges. Works for any convex-ish cross-section (box, triangle, ...).
static func _chamfer(poly: PackedVector2Array, b: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	for i in range(n):
		var cur: Vector2 = poly[i]
		var to_prev: Vector2 = poly[(i - 1 + n) % n] - cur
		var to_next: Vector2 = poly[(i + 1) % n] - cur
		out.append(cur + to_prev.normalized() * minf(b, to_prev.length() * 0.45))
		out.append(cur + to_next.normalized() * minf(b, to_next.length() * 0.45))
	return out

# Plus / cross-shaped cross-section (12 points), for the CROSS body. `w` is the
# arm half-width; arms reach the unit half-extent (±0.5).
static func _plus_profile(rng: RandomNumberGenerator) -> PackedVector2Array:
	var w: float = rng.randf_range(0.16, 0.26)
	var e := 0.5
	return PackedVector2Array([
		Vector2(w, -e), Vector2(w, -w), Vector2(e, -w), Vector2(e, w),
		Vector2(w, w), Vector2(w, e), Vector2(-w, e), Vector2(-w, w),
		Vector2(-e, w), Vector2(-e, -w), Vector2(-w, -w), Vector2(-w, -e),
	])

# ---------------------------------------------------------------------------
# Wing / fin: swept, tapered, thin airfoil lofted along its span (X). Smooth.
# ---------------------------------------------------------------------------
static func _build_wing(spec: Dictionary, rng: RandomNumberGenerator, slim := false) -> Dictionary:
	var span: float = (0.4 if slim else rng.randf_range(0.7, 1.3))
	var root_chord: float = rng.randf_range(0.6, 1.0)
	var tip_chord: float = root_chord * rng.randf_range(0.2, 0.55)
	var thickness: float = (0.06 if slim else rng.randf_range(0.07, 0.14))
	var sweep: float = rng.randf_range(-0.35, 0.6) * root_chord
	var round_amt: float = rng.randf_range(0.3, 1.0)
	var rings: Array = []
	var tip_z: float = 0.0
	for i in range(5):
		var t := float(i) / 4.0
		var x: float = lerp(0.0, span, t)
		var chord: float = lerp(root_chord, tip_chord, pow(t, lerp(1.0, 2.0, round_amt)))
		var zc: float = sweep * pow(t, 1.2)
		var th: float = thickness * (1.0 - 0.6 * t)
		tip_z = zc
		rings.append([
			Vector3(x, 0.0, zc + chord * 0.5), Vector3(x, th * 0.5, zc),
			Vector3(x, 0.0, zc - chord * 0.5), Vector3(x, -th * 0.5, zc),
		])
	return {"mesh": _loft_rings(rings, true, true, true), "tip": Vector3(span, 0.0, tip_z), "tip_chord": tip_chord, "thickness": thickness}

static func _add_pod(hull: Node3D, spec: Dictionary, color: Color, xf: Transform3D, wing: Dictionary, acc: Dictionary) -> void:
	var mesh: ArrayMesh
	if spec.wingtip_pod == "cylinder":
		mesh = _cylinder_mesh(wing.thickness * 1.4, wing.tip_chord * 1.7, true)
	else:
		mesh = _box_mesh(Vector3(wing.thickness * 2.4, wing.thickness * 2.4, wing.tip_chord * 1.5))
	_add_part(hull, mesh, color, xf, acc)

# ---------------------------------------------------------------------------
# Primitive mesh helpers
# ---------------------------------------------------------------------------
static func _box_mesh(size: Vector3) -> ArrayMesh:
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	var sq: Array = [Vector3(-hx, -hy, 0), Vector3(hx, -hy, 0), Vector3(hx, hy, 0), Vector3(-hx, hy, 0)]
	var r0: Array = []
	var r1: Array = []
	for p in sq:
		r0.append(p + Vector3(0, 0, -hz))
		r1.append(p + Vector3(0, 0, hz))
	return _loft_rings([r0, r1], true, true, false)

static func _cylinder_mesh(radius: float, height: float, smooth: bool) -> ArrayMesh:
	var sides := 16 if smooth else 8
	var r0: Array = []
	var r1: Array = []
	for i in range(sides):
		var a := TAU * float(i) / float(sides)
		r0.append(Vector3(cos(a) * radius, sin(a) * radius, -height * 0.5))
		r1.append(Vector3(cos(a) * radius, sin(a) * radius, height * 0.5))
	return _loft_rings([r0, r1], true, true, smooth)

# Cone/pyramid nose: ring of `sides` tapering to a point at -Z (front).
static func _cone_mesh(half_h: float, half_w: float, length: float, smooth: bool) -> ArrayMesh:
	var sides := 16 if smooth else 4
	var base: Array = []
	var tip: Array = []
	for i in range(sides):
		var a := TAU * float(i) / float(sides)
		base.append(Vector3(cos(a) * half_w, sin(a) * half_h, length * 0.5))
		tip.append(Vector3(0, 0, -length * 0.5))
	return _loft_rings([base, tip], true, false, smooth)

static func _dome_mesh(radius: float) -> ArrayMesh:
	var rings_h := 4
	var seg := 12
	var rings: Array = []
	for j in range(rings_h + 1):
		var phi := (PI * 0.5) * float(j) / float(rings_h)  # 0..90 deg
		var y := sin(phi) * radius
		var rr := cos(phi) * radius
		var ring: Array = []
		for i in range(seg):
			var a := TAU * float(i) / float(seg)
			ring.append(Vector3(cos(a) * rr, y, sin(a) * rr))
		rings.append(ring)
	return _loft_rings(rings, true, false, true)

# ---------------------------------------------------------------------------
# Lofts
# ---------------------------------------------------------------------------
static func _loft_stations(profile: PackedVector2Array, stations: Array, smooth: bool, y_flatten := 1.0) -> ArrayMesh:
	var rings: Array = []
	for s in stations:
		var ring: Array = []
		for p in profile:
			ring.append(Vector3(p.x * s.sx, p.y * s.sy * y_flatten, s.z))
		rings.append(ring)
	return _loft_rings(rings, true, true, smooth)

# Generic loft. FLAT-SHADED: every face's normal is the true perpendicular to its
# own plane (set on all three vertices, no generate_normals() smoothing), pointed
# outward against a PER-RING-LOCAL reference (each ring's own center for sides,
# the local axis direction for caps). `smooth` is ignored -- grey-box is faceted.
static func _loft_rings(rings: Array, cap_first: bool, cap_last: bool, _smooth: bool) -> ArrayMesh:
	var ring_centers: Array = []
	for ring in rings:
		ring_centers.append(_ring_center(ring))
	var m: int = rings[0].size()
	var n_rings: int = rings.size()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(n_rings - 1):
		var r0: Array = rings[k]
		var r1: Array = rings[k + 1]
		var lc: Vector3 = (ring_centers[k] + ring_centers[k + 1]) * 0.5
		for i in range(m):
			var i2 := (i + 1) % m
			_flat_face(st, r0[i], r0[i2], r1[i2], lc)
			_flat_face(st, r0[i], r1[i2], r1[i], lc)
	if cap_first:
		var dir0: Vector3 = _cap_dir(ring_centers, 0, 1, Vector3(0, 0, -1))
		for i in range(m):
			_flat_face_dir(st, rings[0][i], rings[0][(i + 1) % m], ring_centers[0], dir0)
	if cap_last:
		var li := n_rings - 1
		var dir_l: Vector3 = _cap_dir(ring_centers, li, li - 1, Vector3(0, 0, 1))
		var last: Array = rings[li]
		for i in range(m):
			_flat_face_dir(st, last[i], last[(i + 1) % m], ring_centers[li], dir_l)
	return st.commit()

static func _ring_center(ring: Array) -> Vector3:
	var c := Vector3.ZERO
	for p in ring:
		c += p
	return c / float(ring.size())

# Emit one flat triangle: normal = true perpendicular to the face, pointed
# outward (away from ref_point), same normal on all three vertices; winding
# flipped to match so single-sided culling shows the outer face.
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

static func _cap_dir(centers: Array, at: int, toward: int, fallback: Vector3) -> Vector3:
	var d: Vector3 = centers[at] - centers[toward]
	if d.length() < 0.00001:
		return fallback
	return d.normalized()

# Orient a triangle outward from a reference POINT (side faces: the local center).
static func _tri_ref(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out_ref: Vector3) -> void:
	if (b - a).cross(c - a).dot(((a + b + c) / 3.0) - out_ref) > 0.0:
		var t := b
		b = c
		c = t
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)

# Orient a triangle outward along a reference DIRECTION (caps: the axis dir).
static func _tri_dir(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out_dir: Vector3) -> void:
	if (b - a).cross(c - a).dot(out_dir) > 0.0:
		var t := b
		b = c
		c = t
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)

static func _idx_tri_ref(st: SurfaceTool, ia: int, ib: int, ic: int, pos: Array, out_ref: Vector3) -> void:
	var a: Vector3 = pos[ia]
	var b: Vector3 = pos[ib]
	var c: Vector3 = pos[ic]
	if (b - a).cross(c - a).dot(((a + b + c) / 3.0) - out_ref) > 0.0:
		st.add_index(ia); st.add_index(ic); st.add_index(ib)
	else:
		st.add_index(ia); st.add_index(ib); st.add_index(ic)

static func _idx_tri_dir(st: SurfaceTool, ia: int, ib: int, ic: int, pos: Array, out_dir: Vector3) -> void:
	var a: Vector3 = pos[ia]
	var b: Vector3 = pos[ib]
	var c: Vector3 = pos[ic]
	if (b - a).cross(c - a).dot(out_dir) > 0.0:
		st.add_index(ia); st.add_index(ic); st.add_index(ib)
	else:
		st.add_index(ia); st.add_index(ib); st.add_index(ic)

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, center: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.dot(((a + b + c) / 3.0) - center) < 0.0:
		var tmp := b
		b = c
		c = tmp
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)

static func _idx_tri(st: SurfaceTool, ia: int, ib: int, ic: int, pos: Array, center: Vector3) -> void:
	var a: Vector3 = pos[ia]
	var b: Vector3 = pos[ib]
	var c: Vector3 = pos[ic]
	var n := (b - a).cross(c - a)
	if n.dot(((a + b + c) / 3.0) - center) > 0.0:
		st.add_index(ia); st.add_index(ic); st.add_index(ib)
	else:
		st.add_index(ia); st.add_index(ib); st.add_index(ic)

static func _torus_mesh(major_r: float, minor_r: float, ring_sides: int, tube_sides: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	var centers: Array = []
	for j in range(ring_sides):
		var th := TAU * float(j) / float(ring_sides)
		var c := Vector3(cos(th) * major_r, sin(th) * major_r, 0)
		centers.append(c)
		var ring: Array = []
		for k in range(tube_sides):
			ring.append(_torus_point(c, th, minor_r, TAU * float(k) / float(tube_sides)))
		rings.append(ring)
	for j in range(ring_sides):
		var jn := (j + 1) % ring_sides
		var seg: Vector3 = (centers[j] + centers[jn]) * 0.5   # local outward ref
		var r0: Array = rings[j]
		var r1: Array = rings[jn]
		for k in range(tube_sides):
			var kn := (k + 1) % tube_sides
			_flat_face(st, r0[k], r1[k], r1[kn], seg)
			_flat_face(st, r0[k], r1[kn], r0[kn], seg)
	return st.commit()

static func _torus_point(center: Vector3, theta: float, minor_r: float, phi: float) -> Vector3:
	var radial := Vector3(cos(theta), sin(theta), 0)
	return center + radial * (cos(phi) * minor_r) + Vector3(0, 0, 1) * (sin(phi) * minor_r)

# ---------------------------------------------------------------------------
# Instance a part and fold its bounds into the running AABB.
# ---------------------------------------------------------------------------
static func _add_part(hull: Node3D, mesh: ArrayMesh, color: Color, xf: Transform3D, acc: Dictionary) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.5
	mat.metallic = 0.25
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = xf
	hull.add_child(mi)
	var world := _transform_aabb(xf, mesh.get_aabb())
	if not acc.have:
		acc.bounds = world
		acc.have = true
	else:
		acc.bounds = acc.bounds.merge(world)

static func _transform_aabb(xf: Transform3D, box: AABB) -> AABB:
	var result := AABB(xf * box.position, Vector3.ZERO)
	for i in range(1, 8):
		var corner := box.position + Vector3(
			box.size.x if (i & 1) else 0.0,
			box.size.y if (i & 2) else 0.0,
			box.size.z if (i & 4) else 0.0)
		result = result.expand(xf * corner)
	return result
