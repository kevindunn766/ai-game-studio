extends RefCounted
class_name BeautyShipDresser

# Dresses a procedurally-generated ship hull for the POST-LEVEL BEAUTY SHOT.
#
# The gameplay hull (ShipHullGenerator) is deliberately grey-box; this is the
# separate SHOWCASE layer the beauty shot renders. It takes a freshly-generated
# hull and:
#   - re-materials every part with the glossy_hull shader (sky-reflecting metal
#     that procedurally stamps panel seams / rivets / wear), tinted to the part's
#     own ColorAid colour, cockpit parts get the glossy_cockpit glass shader;
#   - scatters twinkling nav-lamps (a MultiMesh using sparkle_lamp) across the
#     silhouette, with a few real OmniLight3Ds so lamps actually light the hull.
#
# Nothing here touches the gameplay ship — the beauty shot generates its own
# hull instance and hands it to dress().

const HULL_SHADER := preload("res://shaders/glossy_hull.gdshader")
const GLASS_SHADER := preload("res://shaders/glossy_cockpit.gdshader")
const LAMP_SHADER := preload("res://shaders/sparkle_lamp.gdshader")
const AttachmentBuilder := preload("res://scripts/attachment_builder.gd")
const MountUtil := preload("res://scripts/mount_util.gd")
const GreebleBuilder := preload("res://scripts/greeble_builder.gd")

# Role indices into the ColorAid `colors` array (see ShipHullGenerator: 0 body,
# 1 wings, 2 engines/fins, 3 cockpit, 4 nose/pods, 5 greeble).
const ROLE_COCKPIT := 3
const ATTACH_SCALE := 0.4      # matches Ship.attachment_scale

# ---------------------------------------------------------------------------
# Apply the glossy presentation materials + lamps to `hull`.
#   colors  : the ColorAid scheme from ShipHullGenerator.generate()
#   accent  : sky/theme accent colour (drives the fresnel rim + lamp tint)
#   rng     : deterministic per-shot rng (lamp phases, detail seeds)
# ---------------------------------------------------------------------------
static func dress(hull: Node3D, colors: Array, accent: Color, rng: RandomNumberGenerator) -> void:
	# Per-ship rust chance: ~28% of showcased ships are oxidised on their edges.
	var rust: float = rng.randf_range(0.5, 0.95) if rng.randf() < 0.28 else 0.0

	var parts: Array = []
	_collect_mesh_instances(hull, parts)
	var has_cockpit: bool = false
	var body: MeshInstance3D = null
	var body_vol: float = -1.0
	for mi_v in parts:
		var mi: MeshInstance3D = mi_v
		var role: int = _role_of(mi, colors)
		if role == ROLE_COCKPIT:
			has_cockpit = true
			_apply_glass(mi, accent)
		else:
			_apply_glossy(mi, _part_color(mi), accent, rng, rust)
			var vol: float = mi.mesh.get_aabb().get_volume()
			if vol > body_vol:
				body_vol = vol
				body = mi

	# Mechanical greeble detail (dishes / trusses / antennas) on the body.
	if body != null:
		_scatter_greebles(body, _part_color(body), rng)

	var verts: Array = _gather_verts(parts)
	# Every showcased ship gets glinting glass: if this roll had no cockpit part,
	# add a small canopy bubble at the front-top so the hero glass always shows.
	if not has_cockpit and not verts.is_empty():
		_add_canopy(hull, verts, accent)
	_scatter_lamps(hull, verts, accent, rng)

# Render the run's ACCUMULATED loadout on the showcase ship: bolt each kept piece
# on as a glossy attachment greeble at the matching gameplay mount, so the shown
# ship reflects the parts the player has drafted. Added under `ship_root` (a
# sibling of the hull, unscaled) at the normalized mount positions -- exactly how
# grow_ship places them in-game. Capped at the mount count, like the real ship.
static func attach_loadout(ship_root: Node3D, pieces: Array, aabb: AABB, scale: float, accent: Color, rng: RandomNumberGenerator) -> void:
	var mounts: Array = MountUtil.positions_centered(aabb, scale)   # hull is centred on ship_root
	var n: int = mini(pieces.size(), mounts.size())
	for i in range(n):
		var p: Dictionary = pieces[i]
		var color: Color = p.get("color", Color(0.7, 0.75, 0.85))
		var outward: Vector3 = MountUtil.DIRECTIONS[i]
		var att: Node3D = AttachmentBuilder.build(p.get("kind", "cosmetic"), color, ATTACH_SCALE, outward)
		att.position = mounts[i]
		var mis: Array = []
		_collect_mesh_instances(att, mis)
		for mi_v in mis:
			var mi: MeshInstance3D = mi_v
			_apply_glossy(mi, color, accent, rng)
		ship_root.add_child(att)

# --- greeble detail --------------------------------------------------------
# Scatter mechanical greebles (satellite dishes / scaffolding / antennas) over the
# body, sampled onto its vertices and oriented to the surface normal so they stand
# off the hull. Skips near-underside faces (detail reads better on top / flanks).
static func _scatter_greebles(body: MeshInstance3D, color: Color, rng: RandomNumberGenerator) -> void:
	var arrays: Array = body.mesh.surface_get_arrays(0)
	if arrays.is_empty():
		return
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.size() == 0:
		return
	var norms_v: Variant = arrays[Mesh.ARRAY_NORMAL]
	var has_norms: bool = norms_v is PackedVector3Array and (norms_v as PackedVector3Array).size() == verts.size()
	var norms: PackedVector3Array = norms_v if has_norms else PackedVector3Array()

	var mat: StandardMaterial3D = _greeble_material(color)
	var half_w: float = body.mesh.get_aabb().size.x * 0.5
	var mid_thresh: float = maxf(0.05, half_w * 0.22)

	# Split candidates: near-midline TOP vertices (for antennas, which line the
	# ship's spine) vs. general top/flank vertices (for dishes + scaffolding).
	var mid_idx: Array = []
	var gen_idx: Array = []
	for vi in range(verts.size()):
		var n: Vector3 = norms[vi] if has_norms else Vector3.UP
		if n.length() < 0.01:
			n = Vector3.UP
		if n.normalized().y < -0.25:
			continue                              # skip undersides
		if absf(verts[vi].x) < mid_thresh and n.normalized().y > 0.1:
			mid_idx.append(vi)
		else:
			gen_idx.append(vi)

	# Antennas along the midline.
	var ant_n: int = mini(rng.randi_range(1, 3), mid_idx.size())
	for i in range(ant_n):
		var vi: int = mid_idx[rng.randi() % mid_idx.size()]
		_place_greeble(body, GreebleBuilder.ANTENNA, verts[vi], _norm_at(norms, has_norms, vi), rng, mat)

	# Dishes + scaffolding scattered over the rest.
	var other_n: int = mini(clampi(int(verts.size() / 70), 3, 7), gen_idx.size())
	for i in range(other_n):
		var vi2: int = gen_idx[rng.randi() % gen_idx.size()]
		var kind: int = GreebleBuilder.DISH if rng.randf() < 0.5 else GreebleBuilder.TRUSS
		_place_greeble(body, kind, verts[vi2], _norm_at(norms, has_norms, vi2), rng, mat)

static func _norm_at(norms: PackedVector3Array, has_norms: bool, vi: int) -> Vector3:
	var n: Vector3 = norms[vi] if has_norms else Vector3.UP
	if n.length() < 0.01:
		n = Vector3.UP
	return n.normalized()

static func _place_greeble(body: MeshInstance3D, kind: int, pos: Vector3, n: Vector3, rng: RandomNumberGenerator, mat: StandardMaterial3D) -> void:
	var s: float = rng.randf_range(0.28, 0.5)
	var g: Node3D = GreebleBuilder.build(kind, rng, s, mat)
	g.transform = Transform3D(_basis_from_normal(n), pos)
	body.add_child(g)

static func _greeble_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = _mature(color).darkened(0.2)   # darker metal detail
	m.metallic = 0.7
	m.roughness = 0.38
	return m

# Basis whose local +Y points along `n` (a surface normal).
static func _basis_from_normal(n: Vector3) -> Basis:
	var y: Vector3 = n.normalized()
	var ref: Vector3 = Vector3.FORWARD if absf(y.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var x: Vector3 = ref.cross(y).normalized()
	var z: Vector3 = x.cross(y).normalized()
	return Basis(x, y, z)

# --- materials -------------------------------------------------------------
# Mature the raw ColorAid hues for the showcase: mute the saturation and deepen
# the value a touch, so the beauty-shot ship reads richer / less candy-bright than
# the in-game grey-box (gameplay colours are untouched -- this is presentation).
static func _mature(c: Color) -> Color:
	return Color.from_hsv(c.h, c.s * 0.58, clampf(c.v * 0.86, 0.05, 1.0), c.a)

static func _apply_glossy(mi: MeshInstance3D, base: Color, accent: Color, rng: RandomNumberGenerator, rust: float = 0.0) -> void:
	base = _mature(base)
	var sm := ShaderMaterial.new()
	sm.shader = HULL_SHADER
	sm.set_shader_parameter("albedo", base)
	sm.set_shader_parameter("rim_color", accent.lerp(Color.WHITE, 0.35))
	sm.set_shader_parameter("metallic", rng.randf_range(0.55, 0.8))
	sm.set_shader_parameter("roughness", rng.randf_range(0.2, 0.34))
	sm.set_shader_parameter("panel_scale", rng.randf_range(9.0, 16.0))   # finer grid
	sm.set_shader_parameter("detail_seed", rng.randf_range(0.0, 100.0))
	sm.set_shader_parameter("rust_amount", rust)
	mi.material_override = sm

static func _apply_glass(mi: MeshInstance3D, accent: Color) -> void:
	var gm := ShaderMaterial.new()
	gm.shader = GLASS_SHADER
	# Deep tinted glass that still reads as a LIT canopy (warm cabin glow + a
	# strong glint) rather than an opaque black dome against a dark sky.
	var tint: Color = _mature(_part_color(mi)).darkened(0.55).lerp(Color(0.04, 0.06, 0.12), 0.4)
	gm.set_shader_parameter("glass_tint", tint)
	gm.set_shader_parameter("fresnel_color", accent.lerp(Color.WHITE, 0.4))
	gm.set_shader_parameter("cabin_glow", 0.8)
	gm.set_shader_parameter("glint_strength", 2.3)
	mi.material_override = gm

# A fallback canopy bubble (front-top) for rolls with no cockpit part, so the
# hero glossy-glass feature is always present in the beauty shot.
static func _add_canopy(hull: Node3D, verts: Array, accent: Color) -> void:
	var anchor: Vector3 = _extreme(verts, Vector3(0.0, 0.6, -1.0).normalized())
	var ext: Vector3 = _extent(verts)
	var rad: float = clampf(minf(ext.x, ext.y) * 0.22, 0.05, 0.28)

	var mesh := SphereMesh.new()
	mesh.radius = rad
	mesh.height = rad
	mesh.is_hemisphere = true
	mesh.radial_segments = 22
	mesh.rings = 8

	# A lit glass blister: a deep blue-tinted canopy with a visible warm cabin
	# glow + a stronger glint, so it reads as a cockpit — not an opaque black ball.
	var gm := ShaderMaterial.new()
	gm.shader = GLASS_SHADER
	gm.set_shader_parameter("glass_tint", accent.lerp(Color(0.03, 0.05, 0.11), 0.55))
	gm.set_shader_parameter("fresnel_color", accent.lerp(Color.WHITE, 0.4))
	gm.set_shader_parameter("cabin_glow", 0.95)
	gm.set_shader_parameter("glint_strength", 2.4)

	var mi := MeshInstance3D.new()
	mi.name = "Canopy"
	mi.mesh = mesh
	mi.material_override = gm
	mi.scale = Vector3(1.0, 0.6, 1.15)                    # flatten into a canopy blister
	mi.position = anchor - Vector3(0.0, rad * 0.28, 0.0)  # sink slightly into the hull
	hull.add_child(mi)

# --- lamps -----------------------------------------------------------------
# Scatter twinkling nav-lamps at silhouette extremes + a few random surface
# points as one MultiMesh (one draw call), and add a few OmniLight3Ds so the
# brightest lamps actually cast light on the glossy hull.
static func _scatter_lamps(hull: Node3D, verts: Array, accent: Color, rng: RandomNumberGenerator) -> void:
	var pts: Array = _lamp_points(verts, rng)
	if pts.is_empty():
		return

	var lamp_color: Color = accent.lerp(Color(1.0, 0.95, 0.8), 0.4).lightened(0.2)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.34, 0.34)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = pts.size()
	for i in range(pts.size()):
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pts[i]))
		mm.set_instance_custom_data(i, Color(rng.randf(), 0.0, 0.0, 0.0))   # per-lamp twinkle phase

	var lamp_mat := ShaderMaterial.new()
	lamp_mat.shader = LAMP_SHADER
	lamp_mat.set_shader_parameter("lamp_color", lamp_color)
	lamp_mat.set_shader_parameter("intensity", 2.2)

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "NavLamps"
	mmi.multimesh = mm
	mmi.material_override = lamp_mat
	hull.add_child(mmi)

	# A few real point lights at the first (extreme) lamp points.
	var light_n: int = mini(3, pts.size())
	for i in range(light_n):
		var om := OmniLight3D.new()
		om.position = pts[i]
		om.light_color = lamp_color
		om.light_energy = 1.6
		om.omni_range = 2.2
		om.shadow_enabled = false
		hull.add_child(om)

# All part vertices in hull-local space (subsampled), shared by the canopy +
# lamp placement so both read off the same silhouette.
static func _gather_verts(parts: Array) -> Array:
	var verts: Array = []
	for mi_v in parts:
		var mi: MeshInstance3D = mi_v
		var arrays: Array = mi.mesh.surface_get_arrays(0)
		if arrays.is_empty():
			continue
		var vv: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var step: int = maxi(1, int(vv.size() / 40))   # subsample dense parts
		for i in range(0, vv.size(), step):
			verts.append(mi.transform * vv[i])
	return verts

# Pick lamp anchor points: silhouette extremes first (nose, tail, wingtips, top)
# then a few random surface vertices.
static func _lamp_points(verts: Array, rng: RandomNumberGenerator) -> Array:
	if verts.is_empty():
		return []

	var pts: Array = []
	pts.append(_extreme(verts, Vector3(0, 0, -1)))   # nose
	pts.append(_extreme(verts, Vector3(0, 0, 1)))    # tail
	pts.append(_extreme(verts, Vector3(1, 0, 0)))    # right
	pts.append(_extreme(verts, Vector3(-1, 0, 0)))   # left
	pts.append(_extreme(verts, Vector3(0, 1, 0)))    # top
	for _i in range(3):
		pts.append(verts[rng.randi_range(0, verts.size() - 1)])
	return pts

static func _extent(verts: Array) -> Vector3:
	var lo: Vector3 = verts[0]
	var hi: Vector3 = verts[0]
	for v_ in verts:
		var v: Vector3 = v_
		lo = Vector3(minf(lo.x, v.x), minf(lo.y, v.y), minf(lo.z, v.z))
		hi = Vector3(maxf(hi.x, v.x), maxf(hi.y, v.y), maxf(hi.z, v.z))
	return hi - lo

static func _extreme(verts: Array, dir: Vector3) -> Vector3:
	var best: Vector3 = verts[0]
	var best_d: float = best.dot(dir)
	for v_ in verts:
		var v: Vector3 = v_
		var d: float = v.dot(dir)
		if d > best_d:
			best_d = d
			best = v
	return best

# --- helpers ---------------------------------------------------------------
static func _collect_mesh_instances(node: Node, out: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child, out)

static func _part_color(mi: MeshInstance3D) -> Color:
	var mat: Material = mi.mesh.surface_get_material(0)
	if mat is StandardMaterial3D:
		return (mat as StandardMaterial3D).albedo_color
	return Color(0.6, 0.62, 0.66)

static func _role_of(mi: MeshInstance3D, colors: Array) -> int:
	var c: Color = _part_color(mi)
	for i in range(colors.size()):
		var ci: Color = colors[i]
		if _close(c, ci):
			return i
	return -1

static func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 1e-4 and absf(a.g - b.g) < 1e-4 and absf(a.b - b.b) < 1e-4
