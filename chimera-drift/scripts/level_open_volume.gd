extends Node3D

@export var ship_path: NodePath
@export var segment_spacing: float = 12.0
# Camera-visibility streaming window (2026-07-19): build ONLY this far ahead (just past the
# fogged horizon + off-camera padding), free everything past build_behind -- not the whole
# level. Scenery scales in/out at the edges so the tight window never pops. See StreamWindow.
@export var build_ahead: float = 112.0
@export var build_behind: float = 30.0
@export var fade_ahead: float = 24.0
@export var fade_behind: float = 18.0
@export var volume_radius: float = 19.0   # 3D content radius around the ship (ring follows the ship's x/y)
@export var props_per_density: float = 2.5        # cut from 5 (2026-07-19 perf)
@export var enemies_per_density: float = 3.0      # restored (Kevin: bring enemy numbers back)
@export var max_active_enemies: int = 12          # generous cap -- still bounds runaway spawns

const HAZARD_LAYER: int = 4
const StreamWindow := preload("res://scripts/stream_window.gd")
const EnemySpawner := preload("res://scripts/enemy_spawner.gd")
const MineField := preload("res://scripts/mine_field.gd")
const HazardSpawner := preload("res://scripts/hazard_spawner.gd")
const METEORITE_SCRIPT := preload("res://scripts/meteorite.gd")
const Hazard := preload("res://scripts/hazard.gd")
const MeshUtil := preload("res://scripts/mesh_util.gd")

# Rocky-sounding objects become drifting physics meteorites (asteroids) in open space
# rather than static hazard props -- keyword-matched so any biome's rocky objects
# (asteroids, meteor shards, rock chunks, debris, ...) qualify.
const ROCKY_KEYWORDS := ["rock", "asteroid", "meteor", "chunk", "boulder", "ore", "debris",
	"fragment", "comet", "regolith", "impact", "ejecta", "iron", "flotsam", "junk", "husk", "hulk"]

func _is_rocky(word: String) -> bool:
	var w: String = word.to_lower()
	for kw in ROCKY_KEYWORDS:
		if w.find(kw) != -1:
			return true
	return false

# Hazard-free opening runway (see level_corridor.gd) -- the ship spawns at z=0.
const SAFE_START_DIST: float = 24.0

@onready var ship: Node3D = get_node(ship_path)

const FEATURE_COLORS := {
	"mushrooms": Color(0.7, 0.3, 0.5, 1.0),
	"rocks": Color(0.5, 0.5, 0.5, 1.0),
	"crystals": Color(0.3, 0.7, 0.9, 1.0),
	"coral": Color(0.9, 0.4, 0.3, 1.0),
	"wreckage": Color(0.4, 0.35, 0.3, 1.0),
	"vents": Color(0.8, 0.5, 0.1, 1.0),
	"spores": Color(0.6, 0.8, 0.3, 1.0),
	"ice spires": Color(0.7, 0.9, 1.0, 1.0),
	"bone piles": Color(0.85, 0.8, 0.7, 1.0),
	"cabling": Color(0.2, 0.2, 0.2, 1.0),
}

const ASTEROID_COLOR := Color(0.42, 0.38, 0.34, 1.0)

# Structure Type density multiplier for the generic feature-word props --
# asteroid_field reads as denser/rockier, open_space reads as mostly empty.
const STRUCTURE_DENSITY_MULTIPLIER := {
	"asteroid_field": 1.8,
	"open_space": 0.25,
}

var theme: Dictionary = {}
var feature_words: Dictionary = {}
var enemy_words: Dictionary = {}
var mines_density: float = 0.0
var hazards: Dictionary = {}
var gravity_on: bool = false          # rolled per biome -> drifting (0) vs falling (1) debris
var current_structure: String = "field"
var current_viewpoint: String = "thirdperson"
var level_state: Dictionary = {}        # per-level scatter/geometry personality (LevelSeed.roll_state)
var spawned_props: Array = []
var spawned_enemies: Array = []
var spawned_meteorites: Array = []
var next_segment_z: float = 0.0
var active: bool = false

func configure(rolled_feature_words: Dictionary) -> void:
	feature_words = rolled_feature_words

func configure_enemies(rolled_enemy_words: Dictionary) -> void:
	enemy_words = rolled_enemy_words

func configure_mines(density: float) -> void:
	mines_density = density

func configure_hazards(rolled_hazards: Dictionary) -> void:
	hazards = rolled_hazards

func configure_gravity(on: bool) -> void:
	gravity_on = on

func configure_viewpoint(viewpoint_name: String) -> void:
	# Open Volume geometry is view-agnostic EXCEPT the big holed fly-through
	# asteroids, which need a depth axis to align with the hole (see _maybe_spawn_holed).
	current_viewpoint = viewpoint_name

func configure_theme(level_theme: Dictionary) -> void:
	theme = level_theme

func _feature_color(word: String) -> Color:
	if theme.has("features") and theme.features.has(word):
		return theme.features[word].color
	return FEATURE_COLORS.get(word, Color(0.6, 0.6, 0.6, 1.0))

func configure_structure(structure_type: String) -> void:
	current_structure = structure_type

func configure_cliff(_cfg: Dictionary) -> void:
	pass   # cliffs are a Surface-family backdrop; open volume has no ground/cliff

func configure_state(state: Dictionary) -> void:
	level_state = state

# A navigable pickup point at z: within the inner half of the ring (the ship
# spawns at the center and flies fully free here), so pickups are always in reach.
func reachable_point(z: float, rng: RandomNumberGenerator) -> Vector3:
	var radius: float = volume_radius * ship.ship_visual_radius * level_state.get("ring_radius", 1.0)
	var angle: float = rng.randf_range(0.0, TAU)
	var r: float = rng.randf_range(0.0, radius * 0.5)
	return Vector3(ship.position.x + cos(angle) * r, ship.position.y + sin(angle) * r, z)

func clear() -> void:
	active = false
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
	for m in spawned_meteorites:
		if is_instance_valid(m):
			m.queue_free()
	spawned_meteorites.clear()
	next_segment_z = 0.0

var _ahead_dist: float = 80.0   # effective build distance in front (perf-scaled in start())

func start() -> void:
	active = true
	_ahead_dist = build_ahead * PerfProfile.view_distance_scale
	# Initial fill: only up to the visible window, not the whole level.
	while next_segment_z > -_ahead_dist:
		_spawn_segment()

func _process(_delta: float) -> void:
	if not active:
		return
	while next_segment_z > ship.position.z - _ahead_dist:
		_spawn_segment()
	_recycle_old_props()
	_recycle_old_enemies()
	_recycle_old_meteorites()
	_apply_edge_shrink()

# Space debris props scale in at the frontier and OUT as they drift behind; enemies/
# meteorites (moving physics) are left to distance-recycle. In the deep views (third-person
# / 3-4) props ALSO scale down + cull with camera distance so debris doesn't draw far into
# the distance (see StreamWindow.camera_factor).
func _apply_edge_shrink() -> void:
	var sz: float = ship.position.z
	var deep: bool = current_viewpoint == "thirdperson" or current_viewpoint == "threequarter"
	var cam := get_viewport().get_camera_3d() if deep else null
	var cp: Vector3 = cam.global_position if cam != null else Vector3.ZERO
	var cb: float = _ahead_dist * StreamWindow.CULL_BEGIN_FRAC
	var ce: float = _ahead_dist * StreamWindow.CULL_END_FRAC if cam != null else -1.0
	for e in spawned_props:
		StreamWindow.apply(e[0], e[2], sz, _ahead_dist, build_behind, fade_ahead, fade_behind, cp, cb, ce)

func _spawn_segment() -> void:
	var radius: float = volume_radius * ship.ship_visual_radius * level_state.get("ring_radius", 1.0)
	var density_multiplier: float = STRUCTURE_DENSITY_MULTIPLIER.get(current_structure, 1.0) * level_state.get("density", 1.0)
	# Keep the spawn runway clear of anything lethal.
	if next_segment_z <= -SAFE_START_DIST:
		for word in feature_words.keys():
			var density: float = feature_words[word]
			if _is_rocky(word):
				_scatter_meteorites(word, density, density_multiplier, radius)
			else:
				_scatter_props(word, density, density_multiplier, radius)
		_maybe_spawn_holed(radius)
		_spawn_enemies(radius)
		_spawn_mines()
		_spawn_hazards()
	next_segment_z -= segment_spacing

# Non-rocky feature words: the original static hazard props.
func _scatter_props(word: String, density: float, density_multiplier: float, radius: float) -> void:
	var count: int = int(round(density * props_per_density * density_multiplier))
	for i in range(count):
		var prop_scale: float = ship.ship_visual_radius * randf_range(0.3, 0.9) * level_state.get("feature_scale", 1.0)
		var prop_radius: float = prop_scale * 0.5
		var color: Color = _feature_color(word)
		# Small scattered props are always solid rocks (the small holed asteroids
		# were removed at Kevin's request 2026-07-17).
		var sm := SphereMesh.new()
		sm.radius = prop_radius
		sm.height = prop_radius * 2.0
		var mesh: Mesh = sm
		var prop := MeshInstance3D.new()
		prop.mesh = MeshUtil.flat(mesh)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		prop.material_override = mat
		var angle: float = randf_range(0.0, TAU)
		var dist: float = randf_range(radius * 0.15, radius)
		prop.position = Vector3(
			ship.position.x + cos(angle) * dist,
			ship.position.y + sin(angle) * dist,
			next_segment_z + randf_range(-segment_spacing * 0.5, segment_spacing * 0.5)
		)
		prop.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		add_child(prop)
		var prop_body := Hazard.trimesh_body(mesh, prop.transform)
		add_child(prop_body)
		spawned_props.append([prop, prop_body, next_segment_z])

# Rocky feature words: drifting physics meteorites. "micrometeorites" reads as a
# denser cloud of small rocks; others mix sizes with the odd large one.
func _scatter_meteorites(word: String, density: float, density_multiplier: float, radius: float) -> void:
	var count: int = int(round(density * props_per_density * density_multiplier))
	if word == "micrometeorites":
		count = int(round(float(count) * 1.6))
	for i in range(count):
		var sz: int = METEORITE_SCRIPT.Size.SMALL
		if word != "micrometeorites":
			var roll: float = randf()
			if roll < 0.15:
				sz = METEORITE_SCRIPT.Size.LARGE
			elif roll < 0.55:
				sz = METEORITE_SCRIPT.Size.MEDIUM
		var angle: float = randf_range(0.0, TAU)
		var dist: float = randf_range(radius * 0.15, radius)
		var pos := Vector3(
			ship.position.x + cos(angle) * dist,
			ship.position.y + sin(angle) * dist,
			next_segment_z + randf_range(-segment_spacing * 0.5, segment_spacing * 0.5)
		)
		var drift := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * randf_range(0.2, 1.0)
		spawn_meteorite(sz, pos, drift)

# Shared spawn used by both the scatter above and shatter() fragments.
func spawn_meteorite(size: int, pos: Vector3, base_vel: Vector3) -> void:
	var m := METEORITE_SCRIPT.new()
	add_child(m)
	m.setup(size, pos, ship.ship_visual_radius, ship, self, ASTEROID_COLOR, base_vel)
	if gravity_on:
		m.gravity_scale = 1.0        # Standard-gravity biome: debris falls instead of drifting
	spawned_meteorites.append(m)

# Big holed fly-through asteroids -- rare landmarks in asteroid fields. Static
# (too massive to drift), lethal on the solid ring, safe through the hole. The
# hole axis (local Z) faces roughly along the travel axis so the passage lines up
# with the player's path. Concave (holed) trimesh collision, not CSG.
func _maybe_spawn_holed(radius: float) -> void:
	# Top-down (Y locked) and side-scroll (X locked) can't move in the axis needed to
	# line the ship up with the hole, so a fly-through torus is impossible to traverse.
	if current_viewpoint == "topdown" or current_viewpoint == "sidescroll":
		return
	if current_structure != "asteroid_field" and current_structure != "holed_asteroids":
		return
	var chance: float = 0.45 if current_structure == "holed_asteroids" else 0.18
	if randf() > chance:
		return
	var s: float = ship.ship_visual_radius * randf_range(3.0, 5.0)
	var mesh: ArrayMesh = LevelGeo.holed_asteroid(s, randf() * 900.0)
	var angle: float = randf_range(0.0, TAU)
	var dist: float = randf_range(radius * 0.1, radius * 0.55)
	var pos := Vector3(ship.position.x + cos(angle) * dist, ship.position.y + sin(angle) * dist,
		next_segment_z + randf_range(-segment_spacing * 0.4, segment_spacing * 0.4))
	var rot := Vector3(randf_range(-0.25, 0.25), randf_range(-0.25, 0.25), randf_range(0.0, TAU))

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var matl := StandardMaterial3D.new()
	matl.albedo_color = ASTEROID_COLOR
	matl.roughness = 0.9
	mi.material_override = matl
	mi.position = pos
	mi.rotation = rot
	add_child(mi)

	var body := StaticBody3D.new()
	body.collision_layer = HAZARD_LAYER
	body.collision_mask = 0
	body.position = pos
	body.rotation = rot
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	add_child(body)
	spawned_props.append([mi, body, next_segment_z])

func _spawn_enemies(radius: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for kind in enemy_words.keys():
		var density: float = enemy_words[kind]
		var count: int = int(round(density * enemies_per_density))
		for i in range(count):
			if spawned_enemies.size() >= max_active_enemies:
				return                                       # cap concurrent moving threats
			var enemy_scale: float = ship.ship_visual_radius
			var angle: float = randf_range(0.0, TAU)
			var dist: float = randf_range(radius * 0.15, radius * 0.85)
			var at_position := Vector3(
				cos(angle) * dist,
				sin(angle) * dist,
				next_segment_z + randf_range(-segment_spacing * 0.3, segment_spacing * 0.3)
			)
			var enemy: Area3D = EnemySpawner.create(kind, ship, theme, feature_words, enemy_scale, rng)
			enemy.world = self
			add_child(enemy)
			enemy.position = at_position
			if enemy.has_method("post_spawn"):
				enemy.post_spawn()
			spawned_enemies.append([enemy, next_segment_z])

func _recycle_old_props() -> void:
	var behind_distance: float = build_behind
	var i: int = 0
	while i < spawned_props.size():
		if spawned_props[i][2] > ship.position.z + behind_distance:
			spawned_props[i][0].queue_free()
			spawned_props[i][1].queue_free()
			spawned_props.remove_at(i)
		else:
			i += 1

func _recycle_old_meteorites() -> void:
	var behind_distance: float = build_behind
	var i: int = 0
	while i < spawned_meteorites.size():
		var m: Node = spawned_meteorites[i]
		if not is_instance_valid(m):
			spawned_meteorites.remove_at(i)          # e.g. shattered/popped
		elif m.global_position.z > ship.position.z + behind_distance:
			m.queue_free()
			spawned_meteorites.remove_at(i)
		else:
			i += 1

func _recycle_old_enemies() -> void:
	var behind_distance: float = build_behind
	var i: int = 0
	while i < spawned_enemies.size():
		var e = spawned_enemies[i][0]
		if not is_instance_valid(e):        # self-freed on death / mine detonation
			spawned_enemies.remove_at(i)
		elif spawned_enemies[i][1] > ship.position.z + behind_distance:
			e.queue_free()
			spawned_enemies.remove_at(i)
		else:
			i += 1

# Occasionally lay a mine formation (line / ring / diamond) within the ring volume.
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

# Open space supports drifting FIELD clouds only (they need no surface). Turrets are
# excluded here (Kevin, 2026-07-19 -- they read as ground-mounted and don't belong
# floating in the void); leeches/graspers/push are surface-rooted, also skipped.
func _spawn_hazards() -> void:
	if hazards.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for kind in hazards.keys():
		if kind != "field":
			continue
		if rng.randf() > hazards[kind]:
			continue
		var z: float = next_segment_z + rng.randf_range(-segment_spacing * 0.3, segment_spacing * 0.3)
		var pos: Vector3 = reachable_point(z, rng)
		var h: Node3D = HazardSpawner.create(kind, ship, theme, ship.ship_visual_radius, {}, rng)
		if h == null:
			continue
		if "world" in h:                     # enemy_base-derived hazards need it for the death VFX
			h.world = self
		add_child(h)
		h.position = pos
		spawned_enemies.append([h, next_segment_z])
