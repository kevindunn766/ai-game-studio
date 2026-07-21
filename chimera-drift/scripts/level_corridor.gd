extends Node3D

# Themed streaming corridor. Visuals are a parabolic cave arch (LevelGeo) tinted
# by the resolved LevelTheme; feature props and stalagmite/stalactite dressing
# are themed prop meshes scattered with noise. Collision stays simple boundary
# bodies (floor/walls/ceiling) so the gameplay we already tuned is unchanged.
# Prop instancing is throttled to a per-frame cap so a dense level never spikes.

@export var ship_path: NodePath
@export var segment_spacing: float = 6.0
# Camera-visibility streaming window (2026-07-19): build ONLY this far ahead (just past the
# fogged horizon + off-camera padding), free everything past build_behind -- not the whole
# level. Scenery scales in/out at the edges so the tight window never pops. See StreamWindow.
@export var build_ahead: float = 112.0
@export var build_behind: float = 30.0
@export var fade_ahead: float = 24.0
@export var fade_behind: float = 18.0
@export var base_half_width: float = 5.5   # wider tube -> more room left/right
# Tall enough that the ship flies in the open middle with clear air to the
# lethal floor and ceiling (see LevelDirector._configure_ship_flight).
@export var wall_height: float = 13.0
@export var surface_thickness: float = 1.0
@export var props_per_density: float = 2.5        # cut from 5 (2026-07-19 perf)
@export var enemies_per_density: float = 3.0      # restored (Kevin: bring enemy numbers back)
@export var max_active_enemies: int = 12          # generous cap -- still bounds runaway spawns
@export var cave_wobble_amplitude: float = 1.5
@export var arch_gap_segments: int = 3
@export var pillar_interval_segments: int = 3
# The tunnel cross-section opens up as the level progresses (level geometry only --
# the ship flies free, so wider walls simply mean more room before the lethal
# boundary). 1.0 = off; 1.7 = 70% larger by widen_full distance.
@export var widen_factor: float = 1.7
@export var widen_start: float = 20.0
@export var widen_full: float = 200.0

# The ship spawns at z=0 and flies toward -z. Nothing lethal may exist in this
# opening stretch or the player crashes before they can react.
const SAFE_START_DIST: float = 24.0
const HAZARD_LAYER: int = 4
const ARCH_SAMPLES: int = 16
const MAX_SEGMENTS_PER_FRAME: int = 2
const MAX_PROPS_PER_FRAME: int = 6           # per-frame upper limit on prop instancing
const EnemySpawner := preload("res://scripts/enemy_spawner.gd")
const MineField := preload("res://scripts/mine_field.gd")
const HazardSpawner := preload("res://scripts/hazard_spawner.gd")
const FROND_SHADER := preload("res://shaders/frond_wiggle.gdshader")
const Hazard := preload("res://scripts/hazard.gd")
const StreamWindow := preload("res://scripts/stream_window.gd")

# Fallback palette if no theme was configured (should not happen in-game).
const DEFAULT_THEME := {
	"walls": Color(0.6, 0.6, 0.65), "walls2": Color(0.5, 0.5, 0.55),
	"floor": Color(0.4, 0.4, 0.45), "accent": Color(0.7, 0.5, 0.3),
	"pillar": Color(0.55, 0.55, 0.6), "fog": Color(0.3, 0.3, 0.35),
	"features": {}, "dressing": [],
}

# Which physical tunnel surfaces exist for a given viewpoint (whichever would
# occlude that viewpoint's camera is omitted). Floor is never omitted.
const VIEWPOINT_SURFACES := {
	"thirdperson": ["floor", "left", "right", "ceiling"],
	"sidescroll": ["floor", "left", "ceiling"],
	"topdown": ["floor", "left", "right"],
	"threequarter": ["floor", "left", "right"],
	"isometric": ["floor", "left"],
}

@onready var ship: Node3D = get_node(ship_path)

var theme: Dictionary = DEFAULT_THEME
var feature_words: Dictionary = {}
var enemy_words: Dictionary = {}
var mines_density: float = 0.0
var hazards: Dictionary = {}
var current_viewpoint: String = "thirdperson"
var current_structure: String = "smooth"
var level_state: Dictionary = {}        # per-level scatter/geometry personality (LevelSeed.roll_state)
var noise := FastNoiseLite.new()        # patch field: placement + size falloff
var width_noise := FastNoiseLite.new()  # low-freq tunnel breathing (narrow/widen)
# Per-level non-uniform scale per scattered-prop shape (tall/wide/squat varies by
# level). Pillars are excluded -- they must span floor-to-ceiling.
var prop_scales: Dictionary = {}
const SCALED_PROPS := ["mushroom", "crystal", "blob", "girder", "stalagmite", "stalactite", "rock"]

var segments: Array = []
var spawned_props: Array = []
var spawned_enemies: Array = []
var pillars: Array = []
var pending_props: Array = []
var next_segment_z: float = 0.0
var segment_index: int = 0
var cave_width_offset: float = 0.0
var active: bool = false

func configure(rolled_feature_words: Dictionary) -> void:
	feature_words = rolled_feature_words

func configure_enemies(rolled_enemy_words: Dictionary) -> void:
	enemy_words = rolled_enemy_words

func configure_mines(density: float) -> void:
	mines_density = density

func configure_hazards(rolled_hazards: Dictionary) -> void:
	hazards = rolled_hazards

func configure_gravity(_on: bool) -> void:
	pass   # gravity affects open-volume debris only; corridors have no drifting debris

func configure_viewpoint(viewpoint_name: String) -> void:
	current_viewpoint = viewpoint_name

func configure_structure(structure_type: String) -> void:
	current_structure = structure_type

func configure_cliff(_cfg: Dictionary) -> void:
	pass   # cliffs are a Surface-family backdrop; corridors are enclosed tunnels

func configure_state(state: Dictionary) -> void:
	level_state = state
	widen_factor = state.get("widen_factor", widen_factor)   # per-level tunnel opening rate

# A navigable pickup point at z: inside the tube cross-section, biased toward the
# central core so it's reachable from the ship's mid-tube spawn line.
func reachable_point(z: float, rng: RandomNumberGenerator) -> Vector3:
	var sc: Vector2 = _tunnel_scale(z)   # (half_width, height)
	var x: float = rng.randf_range(-sc.x * 0.5, sc.x * 0.5)
	var y: float = rng.randf_range(sc.y * 0.35, sc.y * 0.65)
	return Vector3(x, y, z)

func configure_theme(level_theme: Dictionary) -> void:
	theme = level_theme

func clear() -> void:
	active = false
	for entry in segments:
		for node in entry[0]:
			if is_instance_valid(node):
				node.queue_free()
		for node in entry[1]:
			if is_instance_valid(node):
				node.queue_free()
	segments.clear()
	for entry in spawned_props:
		if is_instance_valid(entry[0]):
			entry[0].queue_free()
		if is_instance_valid(entry[1]):
			entry[1].queue_free()
	spawned_props.clear()
	for entry in spawned_enemies:
		if is_instance_valid(entry[0]):
			entry[0].queue_free()
	spawned_enemies.clear()
	for entry in pillars:
		if is_instance_valid(entry[0]):
			entry[0].queue_free()
		if is_instance_valid(entry[1]):
			entry[1].queue_free()
	pillars.clear()
	pending_props.clear()
	next_segment_z = 0.0
	segment_index = 0
	cave_width_offset = 0.0

var _ahead_dist: float = 80.0   # effective build distance in front (perf-scaled in start())

func start() -> void:
	active = true
	_ahead_dist = build_ahead * PerfProfile.view_distance_scale
	noise.seed = hash(theme.get("biome", "x"))
	noise.frequency = 0.18                 # patch scale (clusters of props)
	width_noise.seed = noise.seed + 7
	width_noise.frequency = 0.02           # slow breathing over the tunnel length
	# Each scattered prop shape gets its own per-level non-uniform scale (Y varies
	# widest so a shape can be tall one level, squat the next).
	prop_scales = {}
	for s in SCALED_PROPS:
		prop_scales[s] = Vector3(randf_range(0.75, 1.4), randf_range(0.6, 1.9), randf_range(0.75, 1.4))
	# Initial fill: only up to the visible window, not the whole level.
	while next_segment_z > -_ahead_dist:
		_spawn_segment()

# Local tunnel cross-section size at z: half-width and height, both >= their base
# (breathes wider, never below the safe navigable core -- the ship's clamp sits
# at the base, so a narrow spot is tight but always passable).
func _tunnel_scale(z: float) -> Vector2:
	var n: float = (width_noise.get_noise_2d(z, 0.0) + 1.0) * 0.5   # 0..1
	# Per-level state varies how much the tunnel breathes and its base width.
	var amp: float = (0.85 if current_structure == "cave" else 0.5) * level_state.get("tunnel_breath", 1.0)
	var grow: float = _progress_widen(-z)
	var tw: float = level_state.get("tunnel_width", 1.0)
	var hw: float = base_half_width * tw * ship.ship_visual_radius * (1.0 + amp * n) * grow
	var h: float = wall_height * (1.0 + amp * 0.6 * n) * grow
	return Vector2(hw, h)

# Smooth 1.0 -> widen_factor ramp over the [widen_start, widen_full] distance.
func _progress_widen(distance: float) -> float:
	if widen_factor <= 1.0:
		return 1.0
	var span: float = maxf(1.0, widen_full - widen_start)
	var t: float = clampf((distance - widen_start) / span, 0.0, 1.0)
	return 1.0 + (widen_factor - 1.0) * t

func _process(_delta: float) -> void:
	if not active:
		return
	# Share the ship's world position with every frond's wiggle shader (one global
	# update per frame; each frond ramps its own sway by distance to this point).
	RenderingServer.global_shader_parameter_set("frond_player_pos", ship.global_position)
	var spawned_this_frame: int = 0
	while next_segment_z > ship.position.z - _ahead_dist and spawned_this_frame < MAX_SEGMENTS_PER_FRAME:
		_spawn_segment()
		spawned_this_frame += 1
	_drain_pending_props()
	_recycle_old_segments()
	_recycle_old_props()
	_recycle_old_enemies()
	_recycle_old_pillars()
	_apply_edge_shrink()

# Scenery scales in at the frontier and OUT as it recedes past the ship (props + pillars);
# tunnel segments are left alone (would leave gaps). In the deep views (corridor is
# third-person) props+pillars ALSO scale down + cull with camera distance so the tube's
# scenery doesn't draw far into the distance (see StreamWindow.camera_factor).
func _apply_edge_shrink() -> void:
	var sz: float = ship.position.z
	var deep: bool = current_viewpoint == "thirdperson" or current_viewpoint == "threequarter"
	var cam := get_viewport().get_camera_3d() if deep else null
	var cp: Vector3 = cam.global_position if cam != null else Vector3.ZERO
	var cb: float = _ahead_dist * StreamWindow.CULL_BEGIN_FRAC
	var ce: float = _ahead_dist * StreamWindow.CULL_END_FRAC if cam != null else -1.0
	for e in spawned_props:
		StreamWindow.apply(e[0], e[2], sz, _ahead_dist, build_behind, fade_ahead, fade_behind, cp, cb, ce)
	for e in pillars:
		StreamWindow.apply(e[0], e[2], sz, _ahead_dist, build_behind, fade_ahead, fade_behind, cp, cb, ce)

func _spawn_segment() -> void:
	var surfaces: Array = VIEWPOINT_SURFACES.get(current_viewpoint, VIEWPOINT_SURFACES["thirdperson"]).duplicate()
	if current_structure == "canyon":
		surfaces.erase("ceiling")
	var has_ceiling: bool = "ceiling" in surfaces
	if current_structure == "arched" and has_ceiling:
		has_ceiling = (segment_index % arch_gap_segments != 0)

	var include_left: bool = "left" in surfaces
	var include_right: bool = "right" in surfaces
	var z0: float = next_segment_z
	var z1: float = next_segment_z - segment_spacing

	# Cross-section breathes along the length: different arch at each end.
	var s0: Vector2 = _tunnel_scale(z0)
	var s1: Vector2 = _tunnel_scale(z1)
	var sc: Vector2 = _tunnel_scale(next_segment_z - segment_spacing * 0.5)
	var half_width: float = sc.x
	var height: float = sc.y

	var visuals: Array = []
	var bodies: Array = []

	# --- Themed parabolic arch visual (narrowing/widening) ---
	# Interior surfaces face inward (toward this point), viewed from inside.
	var tunnel_center := Vector3(0, height * 0.45, (z0 + z1) * 0.5)
	var outline0 := LevelGeo.arch_outline(s0.x, s0.y, ARCH_SAMPLES)
	var outline1 := LevelGeo.arch_outline(s1.x, s1.y, ARCH_SAMPLES)
	for mesh in _tunnel_ribbons(outline0, outline1, include_left, has_ceiling, include_right, z0, z1, tunnel_center):
		# Single-sided (cull_back): the ribbons now have correct inward normals + winding,
		# so the interior renders lit correctly and the (occluded) outer side is culled.
		# Corridor is third-person-only -- you're always inside the tube -- so no back faces
		# are ever needed. (CLAUDE.md: don't use double-sided to hide winding.)
		var wall_mi := _mesh_instance(mesh, theme.walls, false)
		add_child(wall_mi)
		visuals.append(wall_mi)
	if "floor" in surfaces:
		var floor_mi := _mesh_instance(LevelGeo.floor_strip(s0.x, s1.x, z0, z1, tunnel_center), theme.floor, false)
		add_child(floor_mi)
		visuals.append(floor_mi)

	# --- Collision: a trimesh of each wall/ceiling/floor surface, so the lethal
	# boundary follows the actual curved arch mesh (not a straight bounding box). ---
	for v in visuals:
		var body := Hazard.trimesh_body(v.mesh, v.transform)
		add_child(body)
		bodies.append(body)

	segments.append([visuals, bodies, next_segment_z])

	# Keep the spawn runway clear of anything lethal.
	if next_segment_z <= -SAFE_START_DIST:
		_queue_feature_props(half_width)
		_queue_dressing(half_width, height, has_ceiling)
		_spawn_enemies(half_width, height)
		_spawn_mines()
		_spawn_hazards()
		_maybe_spawn_spanning_girder(half_width, height)
		if current_structure == "pillared" and segment_index % pillar_interval_segments == 0:
			_spawn_pillar(half_width, height)
	segment_index += 1
	next_segment_z -= segment_spacing

# Build contiguous ribbons of the arch for the included wall/ceiling ranges
# (left ~ first 30%, ceiling ~ middle 40%, right ~ last 30%).
func _tunnel_ribbons(outline0: PackedVector2Array, outline1: PackedVector2Array, inc_left: bool, inc_ceil: bool, inc_right: bool, z0: float, z1: float, center: Vector3) -> Array:
	var i_left: int = int(ARCH_SAMPLES * 0.3)
	var i_right: int = int(ARCH_SAMPLES * 0.7)
	var parts: Array = [
		[0, i_left, inc_left], [i_left, i_right, inc_ceil], [i_right, ARCH_SAMPLES, inc_right],
	]
	var meshes: Array = []
	var run_start: int = -1
	var run_end: int = -1
	for p in parts:
		if p[2]:
			if run_start == -1:
				run_start = p[0]
			run_end = p[1]
		elif run_start != -1:
			meshes.append(LevelGeo.ribbon(outline0, outline1, run_start, run_end, z0, z1, center))
			run_start = -1
	if run_start != -1:
		meshes.append(LevelGeo.ribbon(outline0, outline1, run_start, run_end, z0, z1, center))
	return meshes

# --- Feature props: patch distribution where one noise field controls both
# placement (gaps between patches) and size (big in patch centre, small at the
# edge), so props read as natural patches. --------------------------------
func _queue_feature_props(half_width: float) -> void:
	for word in feature_words.keys():
		var style: Dictionary = theme.features.get(word, {"color": theme.accent, "shape": "rock"})
		# A severed run-girder doesn't scatter -- it only spans a canyon/cavern
		# with both ends buried (see _maybe_spawn_spanning_girder).
		if style.shape == "girder" and RunManager.girder_severed:
			continue
		var density: float = feature_words[word]
		var attempts: int = int(round(density * props_per_density * 4.0 * level_state.get("density", 1.0)))
		var st_scale: float = level_state.get("feature_scale", 1.0)
		for i in range(attempts):
			var x: float = randf_range(-half_width * 0.9, half_width * 0.9)
			var z: float = next_segment_z + randf_range(-segment_spacing * 0.5, segment_spacing * 0.5)
			var patch: float = (noise.get_noise_2d(x, z) + 1.0) * 0.5   # 0..1 patch field
			if patch < 0.5:
				continue                                                # gaps between patches
			var falloff: float = smoothstep(0.5, 0.9, patch)            # 0 edge .. 1 centre
			if randf() > 0.15 + 0.85 * falloff:
				continue                                                # denser toward centre
			var scale: float = ship.ship_visual_radius * (0.25 + falloff * 1.5) * st_scale  # small edge, big centre
			pending_props.append({
				"shape": style.shape, "color": style.color, "scale": scale,
				"pos": Vector3(x, 0.0, z), "normal": Vector3.UP, "up_bias": 1.0, "seg_z": next_segment_z,
			})

# --- Stalagmite / stalactite dressing (patch-distributed too) --------------
func _queue_dressing(half_width: float, height: float, has_ceiling: bool) -> void:
	for d in theme.get("dressing", []):
		var on_ceiling: bool = d.shape == "stalactite"
		if on_ceiling and not has_ceiling:
			continue
		for i in range(4):
			var x: float = randf_range(-half_width * 0.85, half_width * 0.85)
			var z: float = next_segment_z + randf_range(-segment_spacing * 0.5, segment_spacing * 0.5)
			var patch: float = (noise.get_noise_2d(x + 100.0, z) + 1.0) * 0.5
			if patch < 0.5:
				continue
			var falloff: float = smoothstep(0.5, 0.9, patch)
			if randf() > 0.2 + 0.8 * falloff:
				continue
			var scale: float = ship.ship_visual_radius * (0.5 + 1.1 * falloff)
			var y: float = height if on_ceiling else 0.0
			pending_props.append({
				"shape": d.shape, "color": d.color, "scale": scale,
				"pos": Vector3(x, y, z), "normal": Vector3.UP, "up_bias": 1.0, "seg_z": next_segment_z,
			})

# Instance up to MAX_PROPS_PER_FRAME queued props this frame, each with its own
# lumpy mesh, jittered color, and a normal-aligned (up-biased) randomized transform.
func _drain_pending_props() -> void:
	var made: int = 0
	while pending_props.size() > 0 and made < MAX_PROPS_PER_FRAME:
		var spec: Dictionary = pending_props.pop_front()
		var visual := MeshInstance3D.new()
		if spec.shape == "girder":
			if RunManager.girder_mesh == null:
				continue   # baked once per run; skip until it's ready (run start only)
			visual.mesh = RunManager.girder_mesh   # shared per-run baked mesh
		else:
			visual.mesh = _prop_mesh(spec.shape, spec.scale, randf() * 500.0)
		if spec.shape == "frond":
			visual.material_override = _frond_material(_jitter_color(spec.color))
		else:
			visual.material_override = _prop_material(_jitter_color(spec.color), spec.shape == "girder")
		var extra: Vector3 = prop_scales.get(spec.shape, Vector3.ONE)
		visual.transform = _instance_transform(spec.pos, spec.normal, spec.up_bias, extra)
		add_child(visual)
		if spec.shape == "vent":
			_attach_vent_exhaust(visual, spec.scale * RunManager.vent_scale)
		# Fronds are pass-through plant decoration (like the surface foliage) -- no
		# collision. Every other prop gets a trimesh matching its own lumpy mesh.
		var body: StaticBody3D = null
		if spec.shape != "frond":
			body = Hazard.trimesh_body(visual.mesh, visual.transform)
			add_child(body)
		spawned_props.append([visual, body, spec.seg_z])
		made += 1

func _prop_material(color: Color, metallic: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.5 if metallic else 0.75
	mat.metallic = 0.5 if metallic else 0.05
	return mat

# Fronds use the wiggle shader: it sways them toward the tip when the ship comes
# close (reading the shared `frond_player_pos` global set each frame). A random
# per-instance phase keeps a patch of fronds from swaying in lockstep.
func _frond_material(color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = FROND_SHADER
	mat.set_shader_parameter("albedo", color)
	mat.set_shader_parameter("phase", randf() * TAU)
	return mat

# Themed exhaust for a vent. The vent's open face is local +Y; its world-space
# direction decides the behavior: pointing up -> slow buoyant SMOKE in the fog
# color; pointing down -> fast falling SPARKS/SLIME in the accent color. Particles
# run in world coords so gravity stays vertical regardless of the vent's tilt.
func _attach_vent_exhaust(vent: MeshInstance3D, mesh_scale: float) -> void:
	# Particle budget scales with the detected perf tier (0 on the lowest tier).
	var pscale: float = PerfProfile.particle_scale
	if pscale <= 0.0:
		return
	var mouth_dir: Vector3 = vent.transform.basis.y.normalized()
	var points_up: bool = mouth_dir.y >= 0.0
	var fog: Color = theme.get("fog", Color(0.4, 0.4, 0.45))
	var accent: Color = theme.get("accent", Color(0.7, 0.6, 0.4))

	var p := CPUParticles3D.new()
	p.position = Vector3(0.0, 0.34 * mesh_scale, 0.0)   # emit from the mouth
	p.local_coords = false                              # world sim -> vertical gravity
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.12 * mesh_scale, 0.02, 0.10 * mesh_scale)
	p.direction = Vector3(0.0, 1.0, 0.0)                # local +Y -> out the mouth
	p.scale_amount_min = 0.7                            # slight per-particle size variance
	p.scale_amount_max = 1.3
	p.amount = maxi(1, int(round(18.0 * pscale)))
	if points_up:
		p.lifetime = 2.4
		p.spread = 12.0
		p.initial_velocity_min = 0.4
		p.initial_velocity_max = 0.9
		p.gravity = Vector3(0.0, 0.6, 0.0)              # buoyant rise
		var smoke: Color = fog.lerp(Color.WHITE, 0.2)
		smoke.a = 0.32
		p.mesh = _vent_particle_quad(smoke, false, 0.12 * mesh_scale)
	else:
		p.amount = maxi(1, int(round(12.0 * pscale)))
		p.lifetime = 1.0
		p.spread = 22.0
		p.initial_velocity_min = 1.4
		p.initial_velocity_max = 2.8
		p.gravity = Vector3(0.0, -6.0, 0.0)             # sparks/slime fall
		var spark: Color = accent.lerp(Color.WHITE, 0.35)
		spark.a = 0.35
		p.mesh = _vent_particle_quad(spark, true, 0.04 * mesh_scale)
	vent.add_child(p)

# Billboard quad for vent particles. Size is set on the mesh directly (in world
# units) so it's deterministic; scale_amount only adds slight variance. Color lives
# on the material albedo (one color per vent). Smoke is alpha-blended and soft;
# sparks are additive so they read as hot bright bits.
func _vent_particle_quad(col: Color, additive: bool, size: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = col
	m.cull_mode = BaseMaterial3D.CULL_DISABLED          # billboard has no meaningful backface
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	q.material = m
	return q

# A severed run-girder spans a canyon/cavern channel with BOTH ends buried in the
# side walls (nothing floats). Only on canyon/cave structures that rolled a
# girder feature word, and not in top-down (a horizontal span can't be dodged
# with the height axis locked).
func _maybe_spawn_spanning_girder(half_width: float, height: float) -> void:
	if RunManager.girder_mesh == null or not RunManager.girder_severed:
		return
	if current_structure != "canyon" and current_structure != "cave":
		return
	if current_viewpoint == "topdown":
		return
	var g_color := Color(0.5, 0.52, 0.56)
	var has_girder := false
	for word in feature_words.keys():
		var st: Dictionary = theme.features.get(word, {})
		if st.get("shape", "") == "girder":
			has_girder = true
			g_color = st.color
			break
	if not has_girder or randf() > 0.18:
		return

	var g_scale: float = RunManager.girder_spec.scale
	var g_len: float = LevelGeo.girder_length(g_scale, RunManager.girder_spec.length_mult)
	var span: float = half_width * 2.0 + 3.0 * g_scale   # wider than the tunnel -> ends in the walls
	var pos := Vector3(0.0, randf_range(height * 0.35, height * 0.65),
		next_segment_z + randf_range(-segment_spacing * 0.3, segment_spacing * 0.3))

	var visual := MeshInstance3D.new()
	visual.mesh = RunManager.girder_mesh
	visual.material_override = _prop_material(_jitter_color(g_color), true)
	# Girder length runs along local -Z; rotate to span world X, scaled to `span`.
	var basis := Basis(Vector3.UP, PI * 0.5).scaled(Vector3(1.0, 1.0, span / g_len))
	basis = basis.rotated(Vector3(0, 0, 1), randf_range(-0.12, 0.12))   # slight sag/tilt
	visual.transform = Transform3D(basis, pos)
	add_child(visual)

	# Trimesh of the actual (scaled/rotated) girder mesh -- collision spans the beam
	# exactly, instead of a straight bounding box wider than the visible girder.
	var body := Hazard.trimesh_body(RunManager.girder_mesh, visual.transform)
	add_child(body)
	spawned_props.append([visual, body, next_segment_z])

func _prop_mesh(shape: String, scale: float, seed: float) -> ArrayMesh:
	match shape:
		"mushroom":
			return LevelGeo.mushroom(scale, seed)
		"crystal":
			return LevelGeo.crystal(scale, seed)
		"blob":
			return LevelGeo.blob(scale, seed)
		"vent":
			return LevelGeo.vent(scale * RunManager.vent_scale, seed)
		"frond":
			return LevelGeo.frond(scale, seed)
		"girder":
			return LevelGeo.girder(scale, seed)
		"stalagmite":
			return LevelGeo.stalagmite(scale, seed)
		"stalactite":
			return LevelGeo.stalactite(scale, seed)
		_:
			return LevelGeo.rock(scale, seed)

# Orient a prop to its surface normal (blended toward up by up_bias), with a
# slight random tilt, random yaw, and non-uniform x/y/z scale. `extra_scale`
# applies an additional per-axis scale in the prop's local space (e.g. the
# per-level blob tall/wide/squat scale) -- Y is the prop's up axis.
func _instance_transform(pos: Vector3, normal: Vector3, up_bias: float, extra_scale: Vector3 = Vector3.ONE) -> Transform3D:
	var up: Vector3 = normal.lerp(Vector3.UP, up_bias).normalized()
	up = (up + Vector3(randf_range(-0.12, 0.12), 0.0, randf_range(-0.12, 0.12))).normalized()
	var ref: Vector3 = Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD
	var x_axis: Vector3 = ref.cross(up).normalized()
	# Right-handed basis (det +1): x_axis x up = z_axis. Using up x x_axis here
	# instead makes a reflection, which flips every prop's winding inside-out.
	var z_axis: Vector3 = x_axis.cross(up).normalized()
	var basis := Basis(x_axis, up, z_axis).rotated(up, randf() * TAU)
	var jitter := Vector3(randf_range(0.82, 1.2), randf_range(0.9, 1.2), randf_range(0.82, 1.2))
	basis = basis.scaled(jitter * extra_scale)
	return Transform3D(basis, pos)

func _jitter_color(c: Color) -> Color:
	var j: float = randf_range(-0.06, 0.06)
	return Color(clampf(c.r + j, 0.0, 1.0), clampf(c.g + j, 0.0, 1.0), clampf(c.b + j, 0.0, 1.0))

func _spawn_pillar(half_width: float, height: float) -> void:
	var pillar_radius: float = ship.ship_visual_radius * 0.6
	var lane_x: float = randf_range(-half_width * 0.6, half_width * 0.6)
	var pillar_pos := Vector3(lane_x, 0.0, next_segment_z)
	var visual := _mesh_instance(LevelGeo.pillar(pillar_radius, height, randf() * 500.0), _jitter_color(theme.pillar), false)
	visual.position = pillar_pos
	visual.rotation.y = randf() * TAU
	visual.scale = Vector3(randf_range(0.9, 1.15), randf_range(0.9, 1.1), randf_range(0.9, 1.15))
	add_child(visual)
	# Trimesh of the waisted pillar mesh (at the visual's transform) instead of a
	# straight cylinder -- collision follows the real silhouette.
	var body := Hazard.trimesh_body(visual.mesh, visual.transform)
	add_child(body)
	pillars.append([visual, body, next_segment_z])

	# Columns host the same feature props (e.g. mushrooms) up their length,
	# aligned to the column's outward normal (biased up).
	for word in feature_words.keys():
		var style: Dictionary = theme.features.get(word, {"color": theme.accent, "shape": "rock"})
		if style.shape != "mushroom":
			continue
		for i in range(4):
			var h: float = randf_range(height * 0.2, height * 0.85)
			var ang: float = randf_range(0.0, TAU)
			var scale: float = ship.ship_visual_radius * 0.4
			var pos := pillar_pos + Vector3(cos(ang) * pillar_radius, h, sin(ang) * pillar_radius)
			var normal := Vector3(cos(ang), 0.0, sin(ang))
			pending_props.append({"shape": "mushroom", "color": style.color, "scale": scale, "pos": pos, "normal": normal, "up_bias": 0.4, "seg_z": next_segment_z})

func _spawn_enemies(half_width: float, height: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for kind in enemy_words.keys():
		var density: float = enemy_words[kind]
		var count: int = int(round(density * enemies_per_density))
		for i in range(count):
			if spawned_enemies.size() >= max_active_enemies:
				return                                       # cap concurrent moving threats
			var enemy_scale: float = ship.ship_visual_radius
			var lane_x: float = randf_range(-half_width * 0.5, half_width * 0.5)
			var at_position := Vector3(lane_x, randf_range(height * 0.3, height * 0.7), next_segment_z + randf_range(-segment_spacing * 0.3, segment_spacing * 0.3))
			var enemy: Area3D = EnemySpawner.create(kind, ship, theme, feature_words, enemy_scale, rng)
			enemy.world = self
			add_child(enemy)
			enemy.position = at_position
			if enemy.has_method("post_spawn"):
				enemy.post_spawn()
			spawned_enemies.append([enemy, next_segment_z])

# --- Helpers ---------------------------------------------------------------
func _mesh_instance(mesh: ArrayMesh, color: Color, double_sided: bool) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.75
	mat.metallic = 0.05
	if double_sided:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi

func _recycle_old_segments() -> void:
	var behind: float = build_behind
	while segments.size() > 0 and segments[0][2] > ship.position.z + behind:
		var entry = segments.pop_front()
		for node in entry[0]:
			node.queue_free()
		for node in entry[1]:
			node.queue_free()

func _recycle_old_props() -> void:
	var behind: float = build_behind
	var i: int = 0
	while i < spawned_props.size():
		if spawned_props[i][2] > ship.position.z + behind:
			spawned_props[i][0].queue_free()
			if is_instance_valid(spawned_props[i][1]):   # fronds have no collision body
				spawned_props[i][1].queue_free()
			spawned_props.remove_at(i)
		else:
			i += 1

func _recycle_old_enemies() -> void:
	var behind: float = build_behind
	var i: int = 0
	while i < spawned_enemies.size():
		var e = spawned_enemies[i][0]
		if not is_instance_valid(e):        # self-freed on death / mine detonation
			spawned_enemies.remove_at(i)
		elif spawned_enemies[i][1] > ship.position.z + behind:
			e.queue_free()
			spawned_enemies.remove_at(i)
		else:
			i += 1

# Occasionally lay a mine formation (line / ring / diamond) at a navigable point.
func _spawn_mines() -> void:
	if mines_density <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if rng.randf() > mines_density:
		return
	var z: float = next_segment_z + rng.randf_range(-segment_spacing * 0.3, segment_spacing * 0.3)
	var center: Vector3 = reachable_point(z, rng)
	for m in MineField.build(center, ship.ship_visual_radius, theme, ship, self, rng):
		spawned_enemies.append([m, next_segment_z])

# Slow-damage hazards, placed for the tube: fields in the flyable core, leeches at
# the ceiling (they drop on you), graspers rooted on the floor.
func _spawn_hazards() -> void:
	if hazards.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var sc: float = ship.ship_visual_radius
	for kind in hazards.keys():
		if rng.randf() > hazards[kind]:
			continue
		var z: float = next_segment_z + rng.randf_range(-segment_spacing * 0.3, segment_spacing * 0.3)
		var scl: Vector2 = _tunnel_scale(z)          # (half_width, height)
		var pos: Vector3
		var opts: Dictionary = {}
		match kind:
			"leech":
				pos = Vector3(rng.randf_range(-scl.x * 0.5, scl.x * 0.5), scl.y * 0.92, z)
				opts = {"mode": "drop"}
			"grasper", "turret", "push":
				pos = Vector3(rng.randf_range(-scl.x * 0.5, scl.x * 0.5), 0.4, z)
			_:
				pos = reachable_point(z, rng)
		var h: Node3D = HazardSpawner.create(kind, ship, theme, sc, opts, rng)
		if h == null:
			continue
		if "world" in h:                     # enemy_base hazards need it for the death VFX
			h.world = self
		add_child(h)
		h.position = pos
		if h.has_method("post_spawn"):
			h.post_spawn()
		spawned_enemies.append([h, next_segment_z])

func _recycle_old_pillars() -> void:
	var behind: float = build_behind
	var i: int = 0
	while i < pillars.size():
		if pillars[i][2] > ship.position.z + behind:
			pillars[i][0].queue_free()
			pillars[i][1].queue_free()
			pillars.remove_at(i)
		else:
			i += 1
