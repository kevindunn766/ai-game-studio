# Procedural plant-geometry generator ("frond system"), ported from
# chimera-drift's LevelGeo.frond and retooled for Kindling. The plant WORKHORSE
# per the design brief -- one system spanning grass -> weeds -> flowers ->
# small plants -> bushes -> trees. Everything is real flat-shaded 3D geometry.
#
# No class_name on purpose (a fresh class_name global doesn't resolve headless);
# callers preload this script as a const. Sizes are real-world metres.
#
# Vertex data: COLOR carries the actual albedo colour (per-instance tint + the
# green->dry-ochre blade gradient), and the base-to-tip SWAY WEIGHT (0 at the
# grounded base .. 1 at the tip) is baked into UV.y for a future wiggle shader.
# (The chimera version stored the weight in COLOR.r; moved here so COLOR can be
# real colour.) Render grass with a material that has vertex_color_use_as_albedo.
#
# THE STEM-ZERO RULE (Kevin's design): stem length 0 makes GRASS -- with no
# stalk, blades emit straight out of the ground. stem length > 0 grows a stalk
# with leaves along it (the classic frond).

const DRY_OCHRE := Color(0.60, 0.50, 0.24)   # dry greyish-yellow-brown blade tip

# scale     : overall size in metres.
# seed      : deterministic RNG seed.
# stem_length: <0 roll a stalk (classic frond); ==0 GRASS (blades from ground);
#              >0 explicit stalk length in metres.
# thickness : 0 -> flat two-sided blades (the LIGHTWEIGHT / far-LOD form);
#             >0 -> blades get a raised centre ridge (triangular-prism cross
#             section) so they read as solid up close (the NEAR-LOD form). Does
#             NOT touch the RNG stream, so the same seed makes the same clump
#             layout flat or thick -- that's what lets grass_lod() pair them.
static func build(scale: float, seed: float, stem_length: float = -1.0, thickness: float = 0.0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed) * 2654435761 + 1
	var s := scale
	var variety: int = rng.randi() % 6

	var len_lo := 1.0;  var len_hi := 2.2
	var nodes_lo := 6;  var nodes_hi := 10
	var leaf_len := 0.60; var leaf_w := 0.15
	var droop_lo := 0.25; var droop_hi := 0.55
	var up_bias := 0.6; var out_bias := 0.75
	var curl_lo := 0.2; var curl_hi := 1.4
	var curve_lo := 0.18; var curve_hi := 0.55
	var base_r := 0.05
	var neck := 0.6
	var az_step := 2.399963
	var pairs := false
	var t_lo := 0.12; var t_hi := 0.9
	var tip_shrink := 0.0
	match variety:
		0:
			pass
		1:
			nodes_lo = 6; nodes_hi = 9
			leaf_len = 0.42; leaf_w = 0.085
			droop_lo = 0.15; droop_hi = 0.32
			up_bias = 0.32; out_bias = 0.96
			curl_lo = 0.1; curl_hi = 0.5
			curve_lo = 0.1; curve_hi = 0.3
			pairs = true; az_step = 1.25; neck = 0.5
		2:
			len_lo = 1.8; len_hi = 2.6
			nodes_lo = 3; nodes_hi = 6
			leaf_len = 0.4; leaf_w = 0.10
			droop_lo = 0.4; droop_hi = 0.7
			up_bias = 0.4; out_bias = 0.7
			curl_lo = 1.6; curl_hi = 3.2
			curve_lo = 0.4; curve_hi = 0.8
			base_r = 0.04; neck = 0.55
		3:
			len_lo = 0.9; len_hi = 1.5
			nodes_lo = 4; nodes_hi = 7
			leaf_len = 0.62; leaf_w = 0.30
			droop_lo = 0.35; droop_hi = 0.6
			up_bias = 0.5; out_bias = 0.85
			curl_lo = 0.2; curl_hi = 1.0
			neck = 0.65
		4:
			len_lo = 0.8; len_hi = 1.4
			nodes_lo = 10; nodes_hi = 15
			leaf_len = 0.7; leaf_w = 0.11
			droop_lo = 0.1; droop_hi = 0.3
			up_bias = 0.9; out_bias = 0.45
			curl_lo = 0.1; curl_hi = 0.6
			curve_lo = 0.05; curve_hi = 0.2
			base_r = 0.045; t_lo = 0.05; t_hi = 0.78
		5:
			len_lo = 1.1; len_hi = 1.8
			nodes_lo = 8; nodes_hi = 13
			leaf_len = 0.5; leaf_w = 0.085
			droop_lo = 0.12; droop_hi = 0.3
			up_bias = 0.4; out_bias = 0.95
			curl_lo = 0.0; curl_hi = 0.12
			curve_lo = 0.22; curve_hi = 0.5
			base_r = 0.045; neck = 0.45
			pairs = true; az_step = 0.0
			t_lo = 0.08; t_hi = 0.94; tip_shrink = 0.45

	var length: float
	if stem_length >= 0.0:
		length = stem_length
	else:
		length = s * rng.randf_range(len_lo, len_hi)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# --- THE STEM-ZERO RULE: grass, plus its dispersed child tufts ---
	if length <= 0.0:
		_build_grass_clump(st, rng, s, thickness)
		return st.commit()

	# --- classic frond: leaning/spiralling tapered stalk with leaves ---
	var stalk_col := Color(0.28, 0.33, 0.14)
	var leaf_nodes: int = rng.randi_range(nodes_lo, nodes_hi)
	var brad: float = s * base_r
	var curve_az: float = rng.randf_range(0.0, TAU)
	var curve_amt: float = rng.randf_range(curve_lo, curve_hi) * length
	var curl: float = rng.randf_range(curl_lo, curl_hi) * (1.0 if rng.randf() < 0.5 else -1.0)

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
			var out_dir: Vector3 = (r0[j] + r1[j]) * 0.5 - cmid
			_frond_quad(st, r0[j], r0[j2], r1[j2], r1[j], out_dir,
				stalk_col, stalk_col, stalk_col, stalk_col, w0, w0, w1, w1)

	var lbase := Color(0.16, 0.40, 0.13)
	var ltip := Color(0.30, 0.55, 0.20)
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
			_build_leaf(st, attach, leaf_up, leaf_side, leaf_norm, ll, lw, tt, neck, droop, lbase, ltip, thickness)

	return st.commit()


# Build a camera-distance LOD grass clump: a THICK near mesh (solid blades) that
# swaps to the FLAT lightweight mesh past `near_dist`, via Godot's built-in
# visibility_range, with a soft fade at the boundary. Same seed -> identical
# clump layout at both LODs, so the swap is invisible except for the thickness.
# Caller owns the shared material (set it on both once, or pass it here).
static func grass_lod(scale: float, seed: float, mat: Material = null, near_dist: float = 6.0) -> MeshInstance3D:
	var fade: float = near_dist * 0.2
	var near_mi := MeshInstance3D.new()
	near_mi.mesh = build(scale, seed, 0.0, 0.9)          # thick, solid blades up close
	near_mi.visibility_range_end = near_dist
	near_mi.visibility_range_end_margin = fade
	near_mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if mat:
		near_mi.material_override = mat
	var far_mi := MeshInstance3D.new()
	far_mi.mesh = build(scale, seed, 0.0, 0.0)           # flat, lightweight far LOD
	far_mi.visibility_range_begin = near_dist
	far_mi.visibility_range_begin_margin = fade
	far_mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if mat:
		far_mi.material_override = mat
	near_mi.add_child(far_mi)
	return near_mi

# A grass "instance" is a clump: one main tuft at the origin plus a handful of
# smaller, randomly-rotated child tufts dispersed around it -- all in one mesh.
# Each clump gets its own slightly-different green (per-instance tint).
static func _build_grass_clump(st: SurfaceTool, rng: RandomNumberGenerator, s: float, thickness: float) -> void:
	# Per-clump species so a scattered field mixes fine lawn, tall meadow, dry
	# olive, and broad lush grass rather than one uniform look.
	var species: int = rng.randi() % 4
	var base_green: Color
	var dry_chance: float
	var len_mult: float = 1.0
	var width_mult: float = 1.0
	var density_mult: float = 1.0
	match species:
		0:  # fresh lawn
			base_green = Color(0.20, 0.44, 0.15)
			dry_chance = rng.randf_range(0.10, 0.30)
		1:  # tall meadow -- taller, finer, drier tips
			base_green = Color(0.24, 0.42, 0.14)
			dry_chance = rng.randf_range(0.30, 0.55)
			len_mult = rng.randf_range(1.25, 1.6); width_mult = 0.8; density_mult = 0.9
		2:  # dry / olive
			base_green = Color(0.34, 0.38, 0.14)
			dry_chance = rng.randf_range(0.50, 0.80)
			len_mult = rng.randf_range(0.9, 1.2)
		_:  # broad, lush
			base_green = Color(0.16, 0.42, 0.16)
			dry_chance = rng.randf_range(0.08, 0.25)
			width_mult = rng.randf_range(1.3, 1.7); density_mult = 1.15; len_mult = 0.9
	base_green = _jitter(base_green, rng, 0.05)

	_emit_tuft(st, rng, s, Vector3.ZERO, 1.0, base_green, 0.0, dry_chance, thickness, len_mult, width_mult, density_mult)

	var children: int = rng.randi_range(2, 5)
	for c in range(children):
		var cang: float = rng.randf() * TAU
		var cdist: float = s * rng.randf_range(0.12, 0.42)
		var coff := Vector3(cos(cang) * cdist, 0.0, sin(cang) * cdist)
		var cscale: float = rng.randf_range(0.35, 0.62)
		var cgreen := _jitter(base_green, rng, 0.05)
		_emit_tuft(st, rng, s, coff, cscale, cgreen, rng.randf() * TAU, dry_chance, thickness, len_mult, width_mult, density_mult)

# One grass tuft: dense, mostly-upright blades whose lean and droop grow
# PARABOLICALLY with radius -- the inner blades stand up, the outer blades
# rotate outward and down toward the ground (like a real tuft splaying at its
# edges). Per-blade length/width/droop/colour all jitter so instances differ.
static func _emit_tuft(st: SurfaceTool, rng: RandomNumberGenerator, s: float,
		center: Vector3, tuft_scale: float, green: Color, yaw: float, dry_chance: float, thickness: float,
		len_mult: float = 1.0, width_mult: float = 1.0, density_mult: float = 1.0) -> void:
	var blades: int = maxi(6, int(round(rng.randf_range(22.0, 36.0) * tuft_scale * density_mult)))
	var max_clump: float = s * tuft_scale * 0.20        # wider footprint -> origins spread out
	var jit: float = s * tuft_scale * 0.035             # extra per-blade base scatter
	var az: float = yaw + rng.randf() * TAU
	for k in range(blades):
		az += 2.399963 + rng.randf_range(-0.3, 0.3)     # golden-angle spread + jitter
		var rn: float = sqrt(rng.randf())               # 0 centre .. 1 outer edge (area-uniform -> spread)
		var clump_r: float = max_clump * rn
		var attach: Vector3 = center + Vector3(
			cos(az) * clump_r + rng.randf_range(-jit, jit), 0.0,
			sin(az) * clump_r + rng.randf_range(-jit, jit))
		# Parabolic (rn*rn) outward-and-down for the edge blades: centre points
		# straight up, the rim tips over toward the ground and away from centre.
		var up_component: float = lerpf(0.98, -0.12, rn * rn)
		var out_component: float = lerpf(0.10, 0.95, rn)
		var radial: Vector3 = _perp_dir(Vector3.UP, az)
		var leaf_up: Vector3 = (radial * out_component + Vector3.UP * up_component).normalized()
		var leaf_side: Vector3 = Vector3.UP.cross(leaf_up).normalized()
		if leaf_side.length() < 0.01:
			leaf_side = Vector3.RIGHT
		var leaf_norm: Vector3 = leaf_side.cross(leaf_up).normalized()
		var ll: float = s * tuft_scale * rng.randf_range(0.55, 0.95) * (1.0 - 0.15 * rn) * len_mult
		var lw: float = s * tuft_scale * rng.randf_range(0.035, 0.06) * width_mult
		var droop: float = lerpf(0.04, 0.30, rn * rn) * rng.randf_range(0.7, 1.2)  # less droop, parabolic
		var base_col: Color = _jitter(green, rng, 0.05)
		var tip_col: Color
		if rng.randf() < dry_chance:
			tip_col = _jitter(DRY_OCHRE, rng, 0.05)                    # dries to ochre at the tip
		else:
			tip_col = _jitter(green.lerp(Color(0.45, 0.60, 0.25), 0.3), rng, 0.04)  # slightly lighter green
		_build_leaf(st, attach, leaf_up, leaf_side, leaf_norm, ll, lw, 0.0, 0.5, droop, base_col, tip_col, thickness)

static func _jitter(c: Color, rng: RandomNumberGenerator, amt: float) -> Color:
	return Color(
		clampf(c.r + rng.randf_range(-amt, amt), 0.0, 1.0),
		clampf(c.g + rng.randf_range(-amt, amt), 0.0, 1.0),
		clampf(c.b + rng.randf_range(-amt, amt), 0.0, 1.0))

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

static func _perp_dir(tangent: Vector3, az: float) -> Vector3:
	var up: Vector3 = Vector3.UP
	if absf(tangent.dot(up)) > 0.95:
		up = Vector3.RIGHT
	var x: Vector3 = tangent.cross(up).normalized()
	var y: Vector3 = tangent.cross(x).normalized()
	return (x * cos(az) + y * sin(az)).normalized()

# One parabolic leaf-blade with a per-vertex albedo gradient base_col->tip_col
# and the sway weight baked into UV.y. Explicit front AND back faces.
static func _build_leaf(st: SurfaceTool, base: Vector3, up: Vector3, side: Vector3, norm: Vector3,
		leaf_len: float, leaf_w: float, w_attach: float, neck: float, droop: float,
		base_col: Color, tip_col: Color, thickness: float = 0.0, round_profile: bool = false) -> void:
	var SEG: int = 6
	var pl_prev: Vector3 = Vector3.ZERO
	var pr_prev: Vector3 = Vector3.ZERO
	var pc_prev: Vector3 = Vector3.ZERO
	var w_prev: float = w_attach
	var col_prev: Color = base_col
	# Facet out-dirs for the thick (triangular-prism) blade.
	var out_l: Vector3 = (norm - side).normalized()
	var out_r: Vector3 = (norm + side).normalized()
	for i in range(SEG + 1):
		var l: float = float(i) / float(SEG)
		# Pointed blade tapers to a tip; a round profile (clover leaflet) is
		# obovate -- narrow at the join, widest past the middle, blunt round tip.
		var half: float
		if round_profile:
			half = leaf_w * 0.5 * (0.2 + 0.8 * smoothstep(0.0, 0.3, l)) * (1.0 - 0.55 * smoothstep(0.7, 1.0, l))
		else:
			var necking: float = lerpf(neck, 1.0, smoothstep(0.0, 0.22, l))
			half = leaf_w * 0.5 * (1.0 - l * l) * necking
		var center: Vector3 = base + up * (leaf_len * l) - norm * (droop * leaf_len * l * l)
		var pl: Vector3 = center - side * half
		var pr: Vector3 = center + side * half
		var pc: Vector3 = center + norm * (half * thickness)   # raised centre ridge (thick only)
		var wv: float = clampf(w_attach + (1.0 - w_attach) * l * 0.4, 0.0, 1.0)
		var col: Color = base_col.lerp(tip_col, l)
		if i > 0:
			if thickness <= 0.0:
				# Flat two-sided blade (lightweight / far LOD).
				_frond_quad(st, pl_prev, pr_prev, pr, pl, norm, col_prev, col_prev, col, col, w_prev, w_prev, wv, wv)
				_frond_quad(st, pl, pr, pr_prev, pl_prev, -norm, col, col, col_prev, col_prev, wv, wv, w_prev, w_prev)
			else:
				# Solid triangular-prism blade: left facet, right facet, underside.
				_frond_quad(st, pl_prev, pc_prev, pc, pl, out_l, col_prev, col_prev, col, col, w_prev, w_prev, wv, wv)
				_frond_quad(st, pc_prev, pr_prev, pr, pc, out_r, col_prev, col_prev, col, col, w_prev, w_prev, wv, wv)
				_frond_quad(st, pr_prev, pl_prev, pl, pr, -norm, col_prev, col_prev, col, col, w_prev, w_prev, wv, wv)
		pl_prev = pl
		pr_prev = pr
		pc_prev = pc
		w_prev = wv
		col_prev = col

static func _frond_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out_dir: Vector3,
		ca: Color, cb: Color, cc: Color, cd: Color, wa: float, wb: float, wc: float, wd: float) -> void:
	_frond_tri(st, a, b, c, out_dir, ca, cb, cc, wa, wb, wc)
	_frond_tri(st, a, c, d, out_dir, ca, cc, cd, wa, wc, wd)

# Flat-shaded triangle: per-vertex albedo in COLOR, sway weight in UV.y. Winding
# reversed (v0, v2, v1) to match Godot's convention (outward normal anti-parallel
# to cross(v1-v0, v2-v0) -- CLAUDE.md mesh rule); face normal flipped to out_dir.
static func _frond_tri(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, out_dir: Vector3,
		c0: Color, c1: Color, c2: Color, w0: float, w1: float, w2: float) -> void:
	var raw: Vector3 = (v1 - v0).cross(v2 - v0)
	if raw.length() < 0.000001:
		return
	var n: Vector3 = raw.normalized()
	var b: Vector3 = v1
	var c: Vector3 = v2
	var cb: Color = c1
	var cc: Color = c2
	var wb: float = w1
	var wc: float = w2
	if n.dot(out_dir) < 0.0:
		n = -n
		var tv: Vector3 = b; b = c; c = tv
		var tc: Color = cb; cb = cc; cc = tc
		var tw: float = wb; wb = wc; wc = tw
	st.set_color(c0); st.set_uv(Vector2(0.0, w0)); st.set_normal(n); st.add_vertex(v0)
	st.set_color(cc); st.set_uv(Vector2(0.0, wc)); st.set_normal(n); st.add_vertex(c)
	st.set_color(cb); st.set_uv(Vector2(0.0, wb)); st.set_normal(n); st.add_vertex(b)


# ============================ CLOVER =======================================
# A low clover patch: several thin petioles rising from the ground, each topped
# with a trefoil of three rounded (obovate) leaflets. Same frond primitives --
# stem tubes + round-profile leaves. thickness feeds the near/far LOD like grass.
static func build_clover(scale: float, seed: float, thickness: float = 0.0) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed) * 2654435761 + 7
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Species tints so a patch mixes shamrock, bluish, and yellowing clover.
	var species: int = rng.randi() % 3
	var green: Color
	match species:
		0: green = Color(0.15, 0.45, 0.17)   # shamrock
		1: green = Color(0.14, 0.44, 0.24)   # bluish
		_: green = Color(0.26, 0.46, 0.15)   # yellowing
	green = _jitter(green, rng, 0.05)
	var petiole_col := Color(0.22, 0.40, 0.16)
	var petioles: int = rng.randi_range(6, 10)
	var az: float = rng.randf() * TAU
	for k in range(petioles):
		az += 2.399963 + rng.randf_range(-0.3, 0.3)
		var rn: float = sqrt(rng.randf())                    # 0 centre .. 1 rim
		var rr: float = scale * 0.20 * rn
		var base := Vector3(cos(az) * rr, 0.0, sin(az) * rr)
		var outw: Vector3 = _perp_dir(Vector3.UP, az)
		# Dome profile: centre petioles stand tall and upright, rim petioles lean
		# outward and are shorter, so the clump silhouette rounds off low at the edge.
		var up_c: float = lerpf(1.0, 0.35, rn * rn)
		var out_c: float = lerpf(0.10, 0.85, rn)
		var dir: Vector3 = (Vector3.UP * up_c + outw * out_c).normalized()
		var plen: float = scale * lerpf(0.72, 0.40, rn) * rng.randf_range(0.9, 1.1)
		var tip: Vector3 = base + dir * plen
		_build_tube(st, base, tip, scale * 0.014, scale * 0.010, petiole_col, 4)
		# Trefoil: three rounded leaflets splayed around the petiole tip.
		var lf_side: Vector3 = _perp_any(dir)
		var lf_norm: Vector3 = dir.cross(lf_side).normalized()
		var leaflets: int = 4 if rng.randf() < 0.05 else 3   # rare four-leaf clover
		var a0: float = rng.randf() * TAU
		for m in range(leaflets):
			var la: float = a0 + float(m) * TAU / float(leaflets)
			var outp: Vector3 = (lf_side * cos(la) + lf_norm * sin(la)).normalized()
			var leaf_up: Vector3 = (outp * 0.85 + dir * 0.5).normalized()
			var leaf_side: Vector3 = dir.cross(leaf_up).normalized()
			if leaf_side.length() < 0.01:
				leaf_side = _perp_any(leaf_up)
			var leaf_norm: Vector3 = leaf_side.cross(leaf_up).normalized()
			var ll: float = scale * rng.randf_range(0.17, 0.24)
			var lw: float = ll * rng.randf_range(0.85, 1.05)
			var bc: Color = _jitter(green, rng, 0.04)
			var tc: Color = _jitter(green.lerp(Color(0.32, 0.56, 0.26), 0.35), rng, 0.03)
			_build_leaf(st, tip, leaf_up, leaf_side, leaf_norm, ll, lw, 0.5, 0.5, 0.12, bc, tc, thickness, true)

	# Occasional white clover flower heads -- a globular puff of tiny florets on
	# a taller stem, rolling white -> faint pink.
	if rng.randf() < 0.45:
		var flowers: int = rng.randi_range(1, 2)
		for f in range(flowers):
			var faz: float = rng.randf() * TAU
			var fr: float = scale * 0.12 * sqrt(rng.randf())
			var fbase := Vector3(cos(faz) * fr, 0.0, sin(faz) * fr)
			var fdir: Vector3 = (Vector3.UP * 0.95 + _perp_dir(Vector3.UP, faz) * rng.randf_range(0.05, 0.2)).normalized()
			var fhead: Vector3 = fbase + fdir * scale * rng.randf_range(0.55, 0.85)
			_build_tube(st, fbase, fhead, scale * 0.012, scale * 0.010, petiole_col, 4)
			var pink: float = rng.randf()
			var fbc := Color(0.82, 0.84, 0.78)
			var ftc := Color(0.96, 0.94, 0.96).lerp(Color(0.95, 0.80, 0.85), pink * 0.5)
			_build_burst(st, rng, fhead, rng.randi_range(40, 60), false,
				scale * 0.05, scale * 0.10, scale * 0.010, scale * 0.018, fbc, ftc, thickness)
	return st.commit()


# ============================ DANDELION ====================================
# A basal rosette of splayed leaves + a bare scape topped with either a yellow
# flower (a dome burst of thin ray-petals) or a white seed puff (a full sphere
# of fine filaments). flower_kind: -1 random, 0 flower, 1 seed puff.
static func build_dandelion(scale: float, seed: float, thickness: float = 0.0, flower_kind: int = -1) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed) * 2654435761 + 13
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Basal rosette -- elongated leaves splayed low and outward.
	var leaf_green := Color(
		0.14 + rng.randf_range(-0.02, 0.04),
		0.36 + rng.randf_range(-0.05, 0.07),
		0.12 + rng.randf_range(-0.02, 0.03))
	var leaves: int = rng.randi_range(4, 7)
	var laz: float = rng.randf() * TAU
	for k in range(leaves):
		laz += 2.399963 + rng.randf_range(-0.3, 0.3)
		var base := Vector3(cos(laz) * scale * 0.03, 0.0, sin(laz) * scale * 0.03)
		var outw: Vector3 = _perp_dir(Vector3.UP, laz)
		var leaf_up: Vector3 = (outw * 0.92 + Vector3.UP * 0.26).normalized()   # low, splayed out
		var leaf_side: Vector3 = Vector3.UP.cross(leaf_up).normalized()
		if leaf_side.length() < 0.01:
			leaf_side = Vector3.RIGHT
		var leaf_norm: Vector3 = leaf_side.cross(leaf_up).normalized()
		var ll: float = scale * rng.randf_range(0.5, 0.8)
		var lw: float = scale * rng.randf_range(0.10, 0.16)
		var bc: Color = _jitter(leaf_green, rng, 0.04)
		var tc: Color = _jitter(leaf_green.lerp(Color(0.28, 0.50, 0.20), 0.3), rng, 0.03)
		_build_leaf(st, base, leaf_up, leaf_side, leaf_norm, ll, lw, 0.0, 0.5, 0.42, bc, tc, thickness)

	# Scape + head. Three forms: yellow flower, seed puff, unopened bud.
	var kind: int = flower_kind
	if kind < 0:
		var kr: float = rng.randf()
		kind = 0 if kr < 0.45 else (1 if kr < 0.80 else 2)   # flower / seed puff / bud
	# The live flower and the bud sit low; the stem elongates once it goes to
	# seed, so only the puff rides a tall scape.
	var scape_h: float = scale * (rng.randf_range(0.95, 1.5) if kind == 1 else rng.randf_range(0.40, 0.75))
	var head := Vector3(0.0, scape_h, 0.0)
	_build_tube(st, Vector3.ZERO, head, scale * 0.02, scale * 0.016, Color(0.30, 0.45, 0.16), 5)
	if kind == 0:
		# Yellow flower: a WIDE, DENSE dome of ray-petals splaying nearly to the
		# horizontal at the rim, colour rolling yellow -> orange per instance.
		var warm: float = rng.randf()
		var fbc := Color(0.85, 0.60, 0.05).lerp(Color(0.90, 0.42, 0.04), warm)
		var ftc := Color(0.98, 0.85, 0.15).lerp(Color(0.98, 0.58, 0.10), warm)
		_build_burst(st, rng, head, rng.randi_range(90, 130), true,
			scale * 0.16, scale * 0.30, scale * 0.022, scale * 0.040, fbc, ftc, thickness, -0.08)
	elif kind == 1:
		# Seed puff: a full sphere of fine near-white filaments.
		_build_burst(st, rng, head, rng.randi_range(72, 110), false,
			scale * 0.18, scale * 0.32, scale * 0.008, scale * 0.014,
			Color(0.90, 0.90, 0.85), Color(1.0, 1.0, 0.98), thickness)
	else:
		# Unopened bud: a tight, mostly-upright cluster of short green->yellow sepals.
		_build_burst(st, rng, head, rng.randi_range(26, 40), true,
			scale * 0.05, scale * 0.11, scale * 0.020, scale * 0.035,
			Color(0.28, 0.42, 0.12), Color(0.75, 0.72, 0.14), thickness, 0.75)
	return st.commit()


# A radiating burst of thin blades from `center` -- dandelion flower (dome) or
# seed puff (full sphere). Reuses _build_leaf for each petal/filament.
static func _build_burst(st: SurfaceTool, rng: RandomNumberGenerator, center: Vector3, count: int,
		dome_only: bool, len_lo: float, len_hi: float, w_lo: float, w_hi: float,
		base_col: Color, tip_col: Color, thickness: float, el_min: float = 0.2) -> void:
	for i in range(count):
		var a: float = rng.randf() * TAU
		var el: float = rng.randf_range(el_min, 1.5) if dome_only else asin(clampf(rng.randf_range(-0.9, 1.0), -1.0, 1.0))
		var dir := Vector3(cos(el) * cos(a), sin(el), cos(el) * sin(a)).normalized()
		var side: Vector3 = _perp_any(dir)
		var norm: Vector3 = dir.cross(side).normalized()
		var ll: float = rng.randf_range(len_lo, len_hi)
		var lw: float = rng.randf_range(w_lo, w_hi)
		_build_leaf(st, center, dir, side, norm, ll, lw, 0.0, 0.8, 0.03,
			_jitter(base_col, rng, 0.03), _jitter(tip_col, rng, 0.03), thickness)


# A straight tapered tube (petiole / scape) between two points. Sway weight
# ramps 0 at the ground base -> 0.5 at the tip.
static func _build_tube(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float, col: Color, sides: int) -> void:
	var tan: Vector3 = (b - a).normalized()
	var r0: Array = _ring_around(a, tan, ra, sides)
	var r1: Array = _ring_around(b, tan, rb, sides)
	var cmid: Vector3 = (a + b) * 0.5
	for j in range(sides):
		var j2: int = (j + 1) % sides
		var out_dir: Vector3 = (r0[j] + r1[j]) * 0.5 - cmid
		_frond_quad(st, r0[j], r0[j2], r1[j2], r1[j], out_dir, col, col, col, col, 0.0, 0.0, 0.5, 0.5)


# A single stable unit vector perpendicular to `dir`.
static func _perp_any(dir: Vector3) -> Vector3:
	var up: Vector3 = Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	return dir.cross(up).normalized()
