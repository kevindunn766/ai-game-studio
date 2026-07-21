extends RefCounted

# Frond plant builder, ported from Chimera Drift (level_geo.gd::frond) and made CUTE
# for Kindling. Self-contained static funcs, no class_name (preload-const per the
# headless rule). Returns an ArrayMesh with its ORIGIN AT THE BASE (grows up from y=0),
# so the burn effect (squash height to 10%) stays planted on the ground.
#
# A frond is a splined stalk (parabolic bend + spiral curl) tapering to a tip, with
# parabolic leaf-blades spaced up the spline at golden-angle azimuths. Length + leaf
# count are random per instance (seed). Vertex COLOR.r carries a 0-at-base..1-at-tip
# sway weight (for a future wiggle shader); albedo comes from the material, so render
# these with a plain material (vertex_color_use_as_albedo OFF).
#
# CUTE MODIFICATION (Kindling-only): everything is intentionally rounded and slightly
# wider than Chimera's frond -- fatter blades and stalk (CUTE_WIDTH), rounded/domed
# blade tips instead of sharp points (elliptical taper), and a rounder stalk.

# --- Cute knobs (tune these to taste) ------------------------------------------------
const CUTE_WIDTH: float = 1.35     # blades + stalk are this much wider than Chimera's
const STALK_SIDES: int = 8         # rounder stalk tube (Chimera used 6)
# -------------------------------------------------------------------------------------


static func build(scale: float, seed: float) -> ArrayMesh:
	return build_stalk(scale, seed).mesh


static func frond(scale: float, seed: float) -> ArrayMesh:
	return build(scale, seed)


# Returns {"mesh": ArrayMesh, "tip": Vector3} -- the tip is the stalk's top point in the
# mesh's local (base-origin) space, so a flower head can be placed exactly on it.
# Optional shape params (defaults reproduce the original stalk exactly, so existing callers
# -- e.g. the small-weed tier -- are untouched):
#   radius_mul  - scales the stalk thickness (< 1 = thinner).
#   taper_floor - tip radius as a fraction of the base (0 = taper to a point; higher = less
#                 tapered / more uniform width, tip left open for a flower/umbel to cap).
#   curve_mul       - scales how far the stalk leans/arches (> 1 = arches over, "heavy").
#   leaf_width_mul  - scales blade width (< 1 = narrower / finer leaves).
static func build_stalk(scale: float, seed: float, radius_mul: float = 1.0, taper_floor: float = 0.0, curve_mul: float = 1.0, leaf_width_mul: float = 1.0) -> Dictionary:
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

	# CUTE: fatten every blade + the stalk.
	leaf_w *= CUTE_WIDTH
	base_r *= CUTE_WIDTH
	# CUTE: soften the necking so blades stay plump where they join the stalk.
	neck = lerpf(neck, 1.0, 0.4)

	var length: float = s * rng.randf_range(len_lo, len_hi)
	var leaf_nodes: int = rng.randi_range(nodes_lo, nodes_hi)
	var brad: float = s * base_r * radius_mul
	var curve_az: float = rng.randf_range(0.0, TAU)
	var curve_amt: float = rng.randf_range(curve_lo, curve_hi) * length * curve_mul
	var curl: float = rng.randf_range(curl_lo, curl_hi) * (1.0 if rng.randf() < 0.5 else -1.0)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Centerline samples: lean grows parabolically (t*t) while the lean azimuth spirals by
	# `curl` over the length -- the stem twists as it rises. The per-segment twist is CAPPED at
	# 30 degrees so it's always a gradual spiral, never a hard snap (the old pinch was a full
	# frame flip in one segment). The tube itself stays clean via the parallel-transport frame.
	var STALK_SEG := 14
	var MAX_SEG_TWIST: float = deg_to_rad(30.0)
	var pts: Array = []
	var stem_az: float = curve_az
	for i in range(STALK_SEG + 1):
		var t: float = float(i) / float(STALK_SEG)
		if i > 0:
			stem_az += clampf(curl / float(STALK_SEG), -MAX_SEG_TWIST, MAX_SEG_TWIST)
		var lean: float = curve_amt * t * t
		pts.append(Vector3(cos(stem_az) * lean, length * t, sin(stem_az) * lean))
	var tangents: Array = []
	for i in range(STALK_SEG + 1):
		var a: Vector3 = pts[max(i - 1, 0)]
		var b: Vector3 = pts[min(i + 1, STALK_SEG)]
		tangents.append((b - a).normalized())

	# Tapered tube. The final ring collapses to a point (radius 0) so the tip closes
	# to zero -- the degenerate tris there are skipped by _frond_tri.
	#
	# Rotation-minimizing (parallel-transport) frame: start with one perpendicular to the base
	# tangent, then rotate it by the MINIMAL turn between successive tangents. The old code
	# rebuilt the frame from a fixed up-vector each segment, which snapped 90 degrees when the
	# tangent crossed vertical -- twisting the tube so hard its edges pinched together. One
	# threaded frame keeps the tube untwisted along the whole arch.
	var up0: Vector3 = Vector3.UP
	if absf(tangents[0].dot(up0)) > 0.95:
		up0 = Vector3.RIGHT
	var fx: Vector3 = tangents[0].cross(up0).normalized()
	var rings: Array = []
	for i in range(STALK_SEG + 1):
		if i > 0:
			var axis: Vector3 = tangents[i - 1].cross(tangents[i])
			var sn: float = axis.length()
			if sn > 0.000001:
				fx = fx.rotated(axis / sn, atan2(sn, tangents[i - 1].dot(tangents[i])))
		fx = (fx - tangents[i] * fx.dot(tangents[i])).normalized()   # keep it perpendicular to the tangent
		var fy: Vector3 = tangents[i].cross(fx).normalized()
		var t: float = float(i) / float(STALK_SEG)
		var radius: float = brad * (1.0 - t * (1.0 - taper_floor))
		var ring: Array = []
		for j in range(STALK_SIDES):
			var a: float = TAU * float(j) / float(STALK_SIDES)
			ring.append(pts[i] + (fx * cos(a) + fy * sin(a)) * radius)
		rings.append(ring)
	for i in range(STALK_SEG):
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		var w0: float = float(i) / float(STALK_SEG)
		var w1: float = float(i + 1) / float(STALK_SEG)
		var cmid: Vector3 = (pts[i] + pts[i + 1]) * 0.5
		for j in range(STALK_SIDES):
			var j2: int = (j + 1) % STALK_SIDES
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
			var lw: float = s * leaf_w * rng.randf_range(0.85, 1.15) * leaf_width_mul
			var droop: float = rng.randf_range(droop_lo, droop_hi)
			_build_leaf(st, attach, leaf_up, leaf_side, leaf_norm, ll, lw, tt, neck, droop)

	return {"mesh": st.commit(), "tip": pts[STALK_SEG]}


# A cute flower head to cap a stalk: a shallow ring of rounded petals splaying up-and-out
# around a small domed centre. Built with its ORIGIN AT THE BASE (the attach point) so it
# sits directly on a stalk tip. One surface -> one material (colour comes from the
# material, like the plants), so it recolours cleanly when burnt.
static func build_flower_head(scale: float, seed: float) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed) * 40503 + 7
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var r: float = scale * 0.22 * rng.randf_range(0.9, 1.15)   # flower radius
	var petals: int = rng.randi_range(5, 7)
	var tilt: float = deg_to_rad(rng.randf_range(30.0, 48.0))  # petals lift off horizontal
	var az0: float = rng.randf_range(0.0, TAU)

	# Domed centre (a shallow cone of triangles, apex slightly up).
	var cr: float = r * 0.42
	var apex := Vector3(0.0, r * 0.28, 0.0)
	var CSEG := 8
	for i in range(CSEG):
		var a0: float = TAU * float(i) / float(CSEG)
		var a1: float = TAU * float(i + 1) / float(CSEG)
		var p0 := Vector3(cos(a0) * cr, 0.0, sin(a0) * cr)
		var p1 := Vector3(cos(a1) * cr, 0.0, sin(a1) * cr)
		_frond_tri(st, apex, p0, p1, Vector3.UP, 1.0, 1.0, 1.0)

	# Petals: rounded, plump little blades radiating around the centre.
	for m in range(petals):
		var az: float = az0 + TAU * float(m) / float(petals)
		var radial := Vector3(cos(az), 0.0, sin(az))
		var up: Vector3 = (radial * cos(tilt) + Vector3.UP * sin(tilt)).normalized()
		var side := Vector3(-sin(az), 0.0, cos(az))
		var norm: Vector3 = side.cross(up).normalized()
		var base := Vector3(radial.x * cr * 0.6, r * 0.12, radial.z * cr * 0.6)
		_build_leaf(st, base, up, side, norm, r, r * 0.85, 0.0, 0.85, 0.12)

	return st.commit()


# A butterfly-weed flower cluster: a shallow DOME (umbel) of many tiny florets merged into one
# mesh. Origin at the umbel base so it sits on a stem tip. Rendered with the (orange) flower
# material.
static func build_umbel(scale: float, seed: float) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed) * 26417 + 3
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = rng.randi_range(20, 30)
	var dome_r: float = scale * 0.24
	for i in range(n):
		var v: float = rng.randf()
		var az: float = rng.randf() * TAU
		var rr: float = sqrt(v) * dome_r
		var h: float = dome_r * 0.45 * (1.0 - v)                 # higher toward the centre -> dome
		_tiny_floret(st, Vector3(cos(az) * rr, h, sin(az) * rr), scale * 0.085, rng.randf() * TAU)
	return st.commit()


# A cheap little 5-petal floret (5 flat triangles) for packing umbels densely -- reads as a
# small flower from the game camera at a fraction of a full flower head's geometry.
static func _tiny_floret(st: SurfaceTool, center: Vector3, r: float, rot: float) -> void:
	var petals: int = 5
	for p in range(petals):
		var a: float = rot + TAU * float(p) / float(petals)
		var tip: Vector3 = center + Vector3(cos(a) * r, r * 0.28, sin(a) * r)
		var b0: Vector3 = center + Vector3(cos(a - 0.42) * r * 0.30, 0.0, sin(a - 0.42) * r * 0.30)
		var b1: Vector3 = center + Vector3(cos(a + 0.42) * r * 0.30, 0.0, sin(a + 0.42) * r * 0.30)
		_frond_tri(st, b0, tip, b1, Vector3.UP, 1.0, 1.0, 1.0)


# A butterfly weed: a clump of several splayed stems (each a slender frond stalk with leaves),
# every stem capped with an orange flower umbel. Returns TWO merged meshes so the streamer can
# render green stems + orange umbels with their own materials -- the same split as the single
# stalk + flower head, just clustered:  {"mesh": stems+leaves, "flower_mesh": umbels}.
static func build_butterfly_weed(scale: float, seed: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed) * 15731 + 5
	var stems := SurfaceTool.new()
	stems.begin(Mesh.PRIMITIVE_TRIANGLES)
	var umbels := SurfaceTool.new()
	umbels.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_stems: int = rng.randi_range(5, 7)
	for i in range(n_stems):
		# Thin, barely-tapered reed-like stems. ~40% of them arch over as if flower-heavy.
		var arches: bool = rng.randf() < 0.4
		var curve_mul: float = rng.randf_range(2.2, 3.4) if arches else rng.randf_range(0.5, 1.1)
		var stalk: Dictionary = build_stalk(scale * rng.randf_range(0.75, 1.0), float(hash(Vector2i(int(seed), i * 2 + 1))), 0.6, 0.38, curve_mul)
		var az: float = rng.randf() * TAU
		var out := Vector3(cos(az), 0.0, sin(az))
		var rad: float = scale * rng.randf_range(0.08, 0.34)     # a little space between stem bases
		var lean: float = rng.randf_range(0.02, 0.16)            # slight outward splay at the base
		var axis: Vector3 = Vector3.UP.cross(out).normalized()
		if axis.length() < 0.01:
			axis = Vector3.RIGHT
		var xf := Transform3D(Basis(axis, lean), out * rad)
		stems.append_from(stalk.mesh, 0, xf)
		var umbel: ArrayMesh = build_umbel(scale, float(hash(Vector2i(int(seed), i * 2 + 2))))
		umbels.append_from(umbel, 0, Transform3D(Basis(), xf * (stalk.tip as Vector3)))
	return {"mesh": stems.commit(), "flower_mesh": umbels.commit()}


# A Queen-Anne's-Lace COMPOUND umbel: a wide, nearly FLAT disc of small floret clusters
# (umbellets) on rays -- the lacy white flower head. Origin at the base so it sits on a tip.
static func build_qal_umbel(scale: float, seed: float) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed) * 22079 + 9
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var disc_r: float = scale * 0.34
	var n_rays: int = rng.randi_range(12, 18)             # umbellets around the disc
	for j in range(n_rays):
		var az: float = TAU * float(j) / float(n_rays) + rng.randf_range(-0.12, 0.12)
		var rr: float = disc_r * rng.randf_range(0.28, 1.0)
		var cx: float = cos(az) * rr
		var cz: float = sin(az) * rr
		# Flat-TOPPED but shallowly domed so it reads with vertical presence under the tilted
		# iso camera (dead-flat foreshortens to a thin streak). Centre raised, rim low.
		var h: float = disc_r * 0.32 * (1.0 - rr / disc_r)
		var m: int = rng.randi_range(6, 10)                  # florets per umbellet
		for k in range(m):
			var a2: float = rng.randf() * TAU
			var r2: float = scale * 0.05 * sqrt(rng.randf())
			_tiny_floret(st, Vector3(cx + cos(a2) * r2, h + r2 * 0.5, cz + sin(a2) * r2), scale * 0.05, rng.randf() * TAU)
	return st.commit()


# Queen Anne's Lace: one to three tall, slender, barely-tapered stems, each capped with a wide
# flat white lacy umbel. Same two-mesh split as the other flowering weeds (stems + umbels).
static func build_queen_annes_lace(scale: float, seed: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed) * 49297 + 11
	var stems := SurfaceTool.new()
	stems.begin(Mesh.PRIMITIVE_TRIANGLES)
	var umbels := SurfaceTool.new()
	umbels.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_stems: int = rng.randi_range(1, 3)
	for i in range(n_stems):
		# Tall, thin, nearly straight -- a gentle curve, a couple lean over slightly.
		var curve_mul: float = rng.randf_range(1.4, 2.4) if rng.randf() < 0.35 else rng.randf_range(0.3, 0.8)
		var stalk: Dictionary = build_stalk(scale * rng.randf_range(0.9, 1.1), float(hash(Vector2i(int(seed), i * 2 + 1))), 0.18, 0.5, curve_mul, 0.32)
		var az: float = rng.randf() * TAU
		var out := Vector3(cos(az), 0.0, sin(az))
		var rad: float = scale * rng.randf_range(0.0, 0.1)
		var lean: float = rng.randf_range(0.0, 0.1)
		var axis: Vector3 = Vector3.UP.cross(out).normalized()
		if axis.length() < 0.01:
			axis = Vector3.RIGHT
		var xf := Transform3D(Basis(axis, lean), out * rad)
		stems.append_from(stalk.mesh, 0, xf)
		var umbel: ArrayMesh = build_qal_umbel(scale, float(hash(Vector2i(int(seed), i * 2 + 2))))
		umbels.append_from(umbel, 0, Transform3D(Basis(), xf * (stalk.tip as Vector3)))
	return {"mesh": stems.commit(), "flower_mesh": umbels.commit()}


# A bush: a WOODY, heavily-bifurcating twig skeleton. A few thin branches rise from the ground
# and fork repeatedly, thinning as they go; small dark-green oval leaves grow ONLY at the outer
# terminal tips, never on the interior twigs. Returns TWO meshes -- woody branches + leaves --
# so the streamer renders them with their own materials (brown / dark green).
static func build_bush(scale: float, seed: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(seed) * 61403 + 17
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaf_size: float = scale * 0.06
	var n_main: int = rng.randi_range(3, 5)
	for i in range(n_main):
		var az: float = TAU * float(i) / float(n_main) + rng.randf_range(-0.35, 0.35)
		var el: float = deg_to_rad(rng.randf_range(52.0, 82.0))       # rise from the ground, up-and-out
		var dir := Vector3(cos(az) * cos(el), sin(el), sin(az) * cos(el))
		# Full branch-length budget (children/tips stay exactly as tuned), but the main branch's
		# OWN drawn segment is short (draw_mul) -> only the lower branch is pulled in, canopy drops.
		_bush_branch(wood, leaves, Vector3.ZERO, dir, scale * rng.randf_range(0.5, 0.7), scale * 0.022, 4, leaf_size, rng, rng.randf_range(0.42, 0.58))
	return {"mesh": wood.commit(), "flower_mesh": leaves.commit()}


# One recursive twig: a thin tapering segment that bifurcates into 2-3 thinner children. Leaves
# are added ONLY at the terminal tips (depth 0) -- the outer shell -- so interior twigs stay bare.
static func _bush_branch(wood: SurfaceTool, leaves: SurfaceTool, start: Vector3, dir: Vector3, length: float, radius: float, depth: int, leaf_size: float, rng: RandomNumberGenerator, draw_mul: float = 1.0) -> void:
	# `length` is the budget the CHILDREN inherit (keeps upper layers unchanged); `seg_len` is
	# how far THIS branch is actually drawn. draw_mul < 1 shortens only this (lower) branch.
	var seg_len: float = length * draw_mul
	var seg: int = 3
	var pts: Array = []
	var wob: float = seg_len * 0.06
	for s in range(seg + 1):
		var t: float = float(s) / float(seg)
		var p: Vector3 = start + dir * (seg_len * t)
		if s > 0:
			p += Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.3, 0.1), rng.randf_range(-1.0, 1.0)) * wob * t
		pts.append(p)
	for s in range(seg):
		var ra: float = radius * (1.0 - float(s) / float(seg) * 0.45)
		var rb: float = radius * (1.0 - float(s + 1) / float(seg) * 0.45)
		_twig_segment(wood, pts[s], pts[s + 1], ra, rb)
	var tip: Vector3 = pts[seg]
	var tip_dir: Vector3 = (pts[seg] - pts[seg - 1]).normalized()
	if depth <= 0:
		# Terminal twiglet: a little tuft of small oval leaves fanning off the tip.
		var m: int = rng.randi_range(3, 5)
		for i in range(m):
			var ldir: Vector3 = _spread_dir(tip_dir, deg_to_rad(rng.randf_range(12.0, 62.0)), rng.randf() * TAU)
			_oval_leaf(leaves, tip, ldir, leaf_size * rng.randf_range(0.8, 1.25))
		return
	# The LAST growth (depth 1) bursts into MANY short leafy twiglets; deeper levels fork normally.
	var rapid: bool = depth <= 1
	var nc: int = rng.randi_range(5, 8) if rapid else rng.randi_range(2, 3)
	var cone_lo: float = 22.0 if rapid else 18.0
	var cone_hi: float = 60.0 if rapid else 44.0
	for c in range(nc):
		var cdir: Vector3 = _spread_dir(tip_dir, deg_to_rad(rng.randf_range(cone_lo, cone_hi)), rng.randf() * TAU)
		var lmul: float = rng.randf_range(0.22, 0.4) if rapid else rng.randf_range(0.6, 0.8)
		# Shorten the drawn length of every structural branch to pull the whole skeleton in, but
		# leave the smallest TERMINAL twiglets (the next depth == 0) at full length.
		var child_draw: float = 1.0 if (depth - 1) <= 0 else rng.randf_range(0.42, 0.56)
		_bush_branch(wood, leaves, tip, cdir, length * lmul, radius * 0.66, depth - 1, leaf_size, rng, child_draw)


# A short tapered tube (5-sided) from a (radius ra) to b (radius rb) -- one twig segment.
static func _twig_segment(st: SurfaceTool, a: Vector3, b: Vector3, ra: float, rb: float) -> void:
	var axis: Vector3 = b - a
	if axis.length() < 0.00001:
		return
	axis = axis.normalized()
	var ref: Vector3 = Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x: Vector3 = axis.cross(ref).normalized()
	var y: Vector3 = axis.cross(x).normalized()
	var sides: int = 5
	for j in range(sides):
		var a0: float = TAU * float(j) / float(sides)
		var a1: float = TAU * float(j + 1) / float(sides)
		var d0: Vector3 = x * cos(a0) + y * sin(a0)
		var d1: Vector3 = x * cos(a1) + y * sin(a1)
		_frond_quad(st, a + d0 * ra, a + d1 * ra, b + d1 * rb, b + d0 * rb, (d0 + d1) * 0.5, 0.0, 0.0, 0.0, 0.0)


# Tilt `dir` away from itself by `cone` radians, then roll `roll` around it -> a child direction.
static func _spread_dir(dir: Vector3, cone: float, roll: float) -> Vector3:
	var ref: Vector3 = Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var side: Vector3 = dir.cross(ref).normalized()
	var d: Vector3 = dir.rotated(side, cone)
	d = d.rotated(dir, roll)
	return d.normalized()


# A small flat oval leaf growing from `base` along `up` (a rounded, plump little blade).
static func _oval_leaf(st: SurfaceTool, base: Vector3, up: Vector3, size: float) -> void:
	var ref: Vector3 = Vector3.UP if absf(up.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var side: Vector3 = up.cross(ref).normalized()
	var norm: Vector3 = side.cross(up).normalized()
	_build_leaf(st, base, up, side, norm, size, size * 0.55, 0.0, 0.75, 0.15)


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


# One parabolic leaf-blade. CUTE: the width follows a ROUNDED (elliptical) taper so
# the blade ends in a domed tip instead of a sharp point, and necks in only slightly
# where it joins the stalk. The blade also arcs over (parabolic droop along -normal).
# Emitted with explicit front AND back faces (a genuine two-sided plane).
static func _build_leaf(st: SurfaceTool, base: Vector3, up: Vector3, side: Vector3, norm: Vector3, leaf_len: float, leaf_w: float, w_attach: float, neck: float, droop: float) -> void:
	var SEG: int = 8   # CUTE: a couple more segments so the rounded tip reads smoothly
	var pl_prev: Vector3 = Vector3.ZERO
	var pr_prev: Vector3 = Vector3.ZERO
	var w_prev: float = w_attach
	for i in range(SEG + 1):
		var l: float = float(i) / float(SEG)
		var necking: float = lerpf(neck, 1.0, smoothstep(0.0, 0.22, l))   # narrow at the join
		# CUTE rounded tip: sqrt(1 - l^2) is a semicircle -- full/plump through the
		# middle and curving to a domed point (vertical tangent) at the tip.
		var half: float = leaf_w * 0.5 * sqrt(maxf(0.0, 1.0 - l * l)) * necking
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
# Godot's convention (reversed emit order).
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
