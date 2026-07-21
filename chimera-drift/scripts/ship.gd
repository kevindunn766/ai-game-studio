extends Node3D

@export var forward_speed: float = 8.0
@export var steer_speed: float = 6.0          # max lateral/vertical steer speed (units/s)
# Big, heavy ship: steer velocity ramps in slowly (~0.7s to full), so the ship
# eases into a turn and coasts out of it rather than darting. This is the main
# "dreamy, no sudden turns" lever -- raise for a lighter/snappier feel.
@export var steer_accel: float = 9.0          # units/s^2
@export var growth_step: float = 0.15
@export var attachment_scale: float = 0.4

# Anti-unfair-crash soft stop: rather than crashing into geometry the player steers
# toward (esp. the ground / a wall hidden by the shallow camera), the ship HALTS a
# clearance short of it and bleeds that steer momentum. Only the steered axes (X/Y) are
# limited -- the forward auto-advance stays lethal (obstacles ahead are visible). Probed
# by a short raycast against the hazard layer each frame.
const HAZARD_COLLISION_LAYER: int = 4
@export var soft_stop_enabled: bool = true
@export var soft_clearance: float = 0.8       # stop this × ship_visual_radius short of geometry

# Combat zone (soft off-path leash): the streamed world follows the ship, but drifting far
# off the flight path fast can outrun the instancing. So a rate-limited anchor trails the
# ship; you roam freely within `zone_half_width` of it, but push past that and a SOFT
# push-back caps your outward speed to `zone_follow_speed` (the instancing catch-up rate)
# while an on-screen "Leaving Combat Zone" alarm flashes. It's not a wall -- keep pushing and
# the anchor (and the world) follows at that rate, and the alarm clears once you settle back
# inside. The director enables it per axis only where lateral streaming can lag (open ground
# / open volume); corridors have walls, so it's off there.
@export var zone_half_width: float = 14.0     # free-roam buffer around the anchor
@export var zone_follow_speed: float = 4.0    # anchor follow / capped outward speed past the buffer
@export var zone_spring: float = 4.0          # soft inward pull past the buffer (return-when-you-let-go)
var zone_limit_x: bool = false                # set per level by LevelDirector
var zone_limit_y: bool = false
var _zone_center: Vector2 = Vector2.ZERO
var leaving_zone: bool = false                # read by game_hud for the alarm

# Underside headlight aim: degrees FORWARD from straight-down (60 = mostly forward,
# angled down to wash the landscape ahead; 0 = straight down; 90 = horizontal).
@export var head_light_forward_deg: float = 60.0

# Visual banking: the hull (and its mount cluster) tilts into steering. Purely
# cosmetic -- the Pickup/Hazard Area3Ds are separate siblings and stay
# axis-aligned, so the collision hitbox never tilts, only the look. Slow easing
# so the roll settles gracefully into the turn.
@export var max_bank_deg: float = 24.0        # roll into lateral turns
@export var max_pitch_deg: float = 12.0       # nose pitch with vertical steering
@export var bank_sharpness: float = 2.5       # easing rate of the tilt (higher = snappier)

const SHIP_HALF_HEIGHT: float = 0.5
# How far in front of the ship's center its nearest point sits (world units) --
# fed to the x-ray shader so an occluder only counts if it's in front of THIS,
# never the ship's own parts. A little generous (hull ~1.1 + front mount/greeble).
const XRAY_FRONT_OFFSET: float = 2.0
# Hazard hitbox is fit to the visible hull, then shrunk a touch so you only crash
# on a clear overlap (forgiving near-misses) rather than on the fat old sphere.
const HITBOX_FORGIVENESS: float = 0.85

const ATTACHMENT_COLORS := [
	Color(0.9, 0.3, 0.3, 1.0),
	Color(0.3, 0.6, 0.9, 1.0),
	Color(0.3, 0.9, 0.4, 1.0),
	Color(0.9, 0.7, 0.2, 1.0),
	Color(0.7, 0.3, 0.9, 1.0),
	Color(0.3, 0.9, 0.9, 1.0),
]

const AttachmentBuilder := preload("res://scripts/attachment_builder.gd")
const PieceUtil := preload("res://scripts/piece_util.gd")
const MountUtil := preload("res://scripts/mount_util.gd")
const XRAY_SHADER := preload("res://shaders/xray_outline.gdshader")
const WINDOW_SHADER := preload("res://shaders/ship_windows.gdshader")
const MeshUtil := preload("res://scripts/mesh_util.gd")
const Combat := preload("res://scripts/combat.gd")
const PROJECTILE := preload("res://scripts/projectile.gd")
const VFX := preload("res://scripts/vfx.gd")

# Engine jet exhaust (lightweight world-space trail off the ship's rear). Base values at
# ship_visual_radius = 1.0; _refresh_exhaust scales them as the ship grows.
const EXHAUST_REAR: float = 1.0           # local +Z (behind) offset of the nozzle
const EXHAUST_SIZE: float = 0.16          # billboard size -- kept small
const EXHAUST_COLOR := Color(0.55, 0.85, 1.0, 0.8)
var _exhaust: CPUParticles3D = null

# --- Combat tuning ---------------------------------------------------------
const MAX_HEALTH: float = 100.0
const HURT_IFRAME: float = 0.45           # brief invulnerability after any hit
const CONTACT_DAMAGE: float = 16.0        # flying into an enemy body
const SHOT_DAMAGE: float = 1.0            # per player bullet
const SHOT_SPEED: float = 60.0
const AIM_RANGE: float = 120.0            # reticle aim-ray reach along the fire line (world units)
const BASE_FIRE_INTERVAL: float = 0.32    # seconds/shot at fire_rate_mult = 1
const FIRE_RATE_STEP: float = 0.35        # permanent rate-of-fire upgrade increment
const FIRE_RATE_MAX: float = 3.0
const WEAPON_TIER_MAX: int = 4            # 1 single, 2 double, 3 triple, 4 spread
const WEAPON_TIER_DURATION: float = 11.0  # temporary buff decays after this with no top-up
const SHIELD_PER_PIECE: float = 40.0
const AFTERBURNER_MULT: float = 2.1
const AFTERBURNER_DURATION: float = 1.6
const AFTERBURNER_COOLDOWN: float = 4.0
const SHOT_COLOR := Color(0.6, 0.95, 1.0, 1.0)

signal crashed(distance_traveled: float)
signal health_changed(health: float, max_health: float, shield: float, shield_capacity: float)

var ship_visual_radius: float = 1.0
# World velocity this frame (forward + steering), tracked from the position delta.
# Meteorites read it to decide bump-vs-crash by closing speed.
var velocity: Vector3 = Vector3.ZERO
# Current steer speed on each axis (x lateral, y vertical). Ramps toward the input
# target and coasts on release -- this is what gives the ship inertia, and it also
# drives the hull's visual bank/pitch so the tilt tracks real momentum.
var steer_velocity: Vector2 = Vector2.ZERO
var attachments_collected: int = 0
var filled_mounts: int = 0
# Eligible pieces (cosmetic parts + permanent upgrades) collected THIS level, in
# pickup order. The beauty-shot draft menu picks one of these to keep forever.
# Cleared on reset(); appended by note_collected_piece() as pickups are grabbed.
# Re-applied permanent pieces (apply_permanent_loadout) are NOT recorded here.
var collected_pieces: Array = []
var speed_boost_multiplier: float = 1.0
# True while a magnet power-up is active: uncollected pickups sense this and
# drift toward the ship (see power_up.gd). Purely a pull assist -- no physics on
# the ship itself.
var magnet_active: bool = false
var alive: bool = true

# --- Combat state ----------------------------------------------------------
var health: float = MAX_HEALTH
var shield: float = 0.0                    # current absorbed-damage buffer
var shield_capacity: float = 0.0           # max shield collected this life
var weapon_tier: int = 1                   # 1..WEAPON_TIER_MAX (temporary, decays)
var weapon_tier_time: float = 0.0          # countdown until tier decays a step
var fire_rate_mult: float = 1.0            # permanent rate-of-fire (from smart drops)
var owns_afterburner: bool = false         # unlocked by a smart drop
var _fire_cd: float = 0.0
var _hurt_cd: float = 0.0
var _ab_cd: float = 0.0

# Free-flight movement -- NO bounding envelope. The player can fly anywhere on the
# axes a viewpoint makes usable; the lethal level geometry (walls/floor/ceiling)
# is the only boundary. Per-viewpoint AXIS LOCKS pin the "pointless" axis rather
# than clamp it: side-scroll locks depth (X), top-down locks height (Y). Set per
# level by LevelDirector.
var steer_x_locked: bool = false      # true -> X pinned to 0 (side-scroll depth)
var steer_y_locked: bool = false      # true -> Y pinned to flight_spawn_y (top-down height)
# Where the ship spawns; also the pinned value when Y is locked. LevelDirector
# sets this high enough that the ship starts in clear air above the lethal ground.
var flight_spawn_y: float = 3.0

# The procedurally generated base hull for this run (see ShipHullGenerator).
# Rolled once from RunManager's seed, persists across death-retries, re-rolled
# only when a new run starts (menu).
var hull_instance: Node3D = null
var hull_colors: Array = []
var hull_spec: Dictionary = {}
# Shared x-ray outline material (a next_pass on every hull/attachment mesh) so the
# ship's silhouette shows through occluders; its color is set per level to the
# level theme. One material -> updating the uniform recolors the whole ship.
var _xray_mat: ShaderMaterial = null
# Center of the fitted hazard hitbox (hull-local, at base radius); scaled with
# ship_visual_radius as attachments grow.
var hazard_hitbox_offset: Vector3 = Vector3.ZERO

@onready var pickup_detector: Area3D = $PickupDetector
@onready var hazard_detector: Area3D = $HazardDetector
@onready var combat_detector: Area3D = $CombatDetector
@onready var head_light: SpotLight3D = $HeadLight
@onready var mounts: Node3D = $Mounts

func _ready() -> void:
	pickup_detector.add_to_group("ship_pickup_detector")
	hazard_detector.body_entered.connect(_on_hazard_body_entered)
	combat_detector.area_entered.connect(_on_combat_area_entered)
	RunManager.run_started.connect(_on_run_started)
	_aim_head_light()
	_build_hull()
	_setup_exhaust()

# Underside headlight: sits at the belly and aims `head_light_forward_deg` forward
# from straight-down so it washes the landscape ahead. It's parented to the Ship node
# (which never banks -- only the hull/mounts do), so the beam stays steady in turns.
func _aim_head_light() -> void:
	head_light.position = Vector3(0.0, -0.3, -0.3)
	head_light.rotation_degrees = Vector3(-(90.0 - head_light_forward_deg), 0.0, 0.0)

# Per-level headlight: brightness scaled to the scene darkness (dark levels get a
# strong beam, bright daylight a subtle one), tinted toward the level theme, with
# shadows only on capable hardware. Called by LevelDirector after it configures the
# environment.
func configure_head_light(energy: float, color: Color, shadows: bool) -> void:
	head_light.light_energy = energy
	head_light.light_color = color
	head_light.shadow_enabled = shadows

# Engine jets: one small world-space exhaust emitter off the rear (+Z) that trails a thin
# plume as the ship flies. Created once (skipped on the lowest perf tier); _refresh_exhaust
# keeps its nozzle offset + particle size tracking ship_visual_radius as the ship grows.
func _setup_exhaust() -> void:
	if PerfProfile.particle_scale <= 0.0:
		return
	var amount: int = maxi(4, int(round(14.0 * PerfProfile.particle_scale)))
	_exhaust = VFX.trail(EXHAUST_COLOR, EXHAUST_SIZE, amount, 0.32, Vector3(0, 0, 1), 3.0, true)
	add_child(_exhaust)
	_refresh_exhaust()

func _refresh_exhaust() -> void:
	if _exhaust == null:
		return
	var r: float = ship_visual_radius
	_exhaust.position = Vector3(0.0, 0.0, EXHAUST_REAR * r)
	_exhaust.scale_amount_min = 0.8 * r
	_exhaust.scale_amount_max = 1.15 * r

func _on_run_started(_seed: int) -> void:
	# A brand-new run (from the menu) re-rolls the hull.
	_build_hull()

# Generate the run's hull and swap it in. The generator returns a Node3D of
# MeshInstance3D parts (deterministic direct meshing -- no CSG bake, so nothing
# to await). Governing Rule 6: camera framing stays driven off ship_visual_radius,
# never inherited from a scaled parent -- the hull is a sibling visual, not a
# parent of the camera rigs, and normalization scales only the hull node.
func _build_hull() -> void:
	if hull_instance != null and is_instance_valid(hull_instance):
		hull_instance.queue_free()
		hull_instance = null

	var rng: RandomNumberGenerator = RunManager.make_hull_rng()
	var result: Dictionary = ShipHullGenerator.generate(rng)
	hull_instance = result.hull
	hull_instance.name = "Hull"

	# Normalize every shape to a consistent envelope so camera framing and level
	# scaling (which key off ship_visual_radius = 1.0 baseline) don't need
	# retuning per rolled shape.
	var aabb: AABB = result.aabb
	var longest: float = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
	var scale_k: float = (ShipHullGenerator.TARGET_LONGEST / longest) if longest > 0.0 else 1.0
	hull_instance.scale = Vector3.ONE * scale_k

	add_child(hull_instance)
	# Fit the hazard hitbox to THIS hull (slender/flat) so you only crash when the
	# visible ship overlaps geometry -- see _fit_hazard_hitbox.
	_fit_hazard_hitbox(aabb, scale_k)
	hull_colors = result.colors
	hull_spec = result.spec
	_flatten_meshes(hull_instance)   # flat-shade the hull's round parts too
	_apply_hull_detail(hull_instance)   # tiny windows (shader)
	_apply_xray(hull_instance)
	_place_mounts(aabb, scale_k)     # snug the 6 mounts onto THIS hull's surface

# Position the 6 mount markers on the hull's actual AABB surface (per-hull), so
# collected parts bolt on snug instead of floating at fixed offsets. Outward
# orientation comes from MountUtil.DIRECTIONS in grow_ship.
func _place_mounts(aabb: AABB, scale_k: float) -> void:
	var centre: Vector3 = MountUtil.center(aabb, scale_k)
	var pc: Array = MountUtil.positions_centered(aabb, scale_k)
	var count: int = mini(mounts.get_child_count(), pc.size())
	for i in range(count):
		var m: Node3D = mounts.get_child(i)
		m.position = centre + pc[i]

# Dress the hull with detail: a shader that stamps lots of tiny windows across the
# body's lateral sides. (The scattered greeble nubs were removed -- they didn't read
# well; the windows carry the surface detail.)
func _apply_hull_detail(root: Node) -> void:
	var parts: Array = []
	_collect_mesh_instances(root, parts)
	if parts.is_empty():
		return
	# Windows go on the BODY only -- the largest part by mesh volume -- and the shader
	# further limits them to that part's vertical lateral (X-facing) sides.
	var body: MeshInstance3D = parts[0]
	var best: float = -1.0
	for mi in parts:
		var vol: float = mi.mesh.get_aabb().get_volume()
		if vol > best:
			best = vol
			body = mi
	_apply_windows(body)

func _collect_mesh_instances(node: Node, out: Array) -> void:
	if node is MeshInstance3D and node.mesh != null:
		out.append(node)
	for child in node.get_children():
		_collect_mesh_instances(child, out)

# Replace a part's material with the window shader, carrying its albedo across.
func _apply_windows(mi: MeshInstance3D) -> void:
	var base := Color(0.6, 0.6, 0.65)
	var srcmat: Material = mi.mesh.surface_get_material(0)
	if srcmat is StandardMaterial3D:
		base = (srcmat as StandardMaterial3D).albedo_color
	var sm := ShaderMaterial.new()
	sm.shader = WINDOW_SHADER
	sm.set_shader_parameter("albedo", base)
	sm.set_shader_parameter("metallic", 0.25)
	sm.set_shader_parameter("roughness", 0.5)
	mi.material_override = sm

# Convert every MeshInstance in the subtree to flat (faceted) shading.
func _flatten_meshes(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		node.mesh = MeshUtil.flat(node.mesh)
	for child in node.get_children():
		_flatten_meshes(child)

# The shared x-ray material (lazily created).
func _xray_material() -> ShaderMaterial:
	if _xray_mat == null:
		_xray_mat = ShaderMaterial.new()
		_xray_mat.shader = XRAY_SHADER
		_xray_mat.render_priority = 2   # over other transparents (pickups etc.)
	return _xray_mat

# X-RAY OUTLINE DISABLED (Kevin, 2026-07-17). It applied a transparent additive
# next_pass to the ship, which read as a permanent see-through look. Disabled here
# so nothing is ever attached -> the ship renders fully solid. The occlusion shader
# (shaders/xray_outline.gdshader) + the plumbing below are left intact for a future
# fix; re-enable by restoring the next_pass assignment in this function.
func _apply_xray(_node: Node) -> void:
	return

# Recolor the x-ray outline to the current level's theme (called per level).
# No-op while the x-ray is disabled (the material is never created).
func set_theme_color(color: Color) -> void:
	if _xray_mat != null:
		_xray_mat.set_shader_parameter("xray_color", color)

# Replace the HazardDetector's fat default sphere with a box matching this rolled
# hull's normalized extents (the hull is long + flat, so a sphere crashed on
# near-misses, badly in the vertical). Only the HAZARD detector changes; the
# PickupDetector keeps its generous sphere so pickups stay easy to grab.
func _fit_hazard_hitbox(local_aabb: AABB, scale_k: float) -> void:
	var hazard_shape: CollisionShape3D = hazard_detector.get_node("CollisionShape3D")
	var box := BoxShape3D.new()
	box.size = local_aabb.size * scale_k * HITBOX_FORGIVENESS
	hazard_shape.shape = box
	hazard_hitbox_offset = (local_aabb.position + local_aabb.size * 0.5) * scale_k
	hazard_shape.position = hazard_hitbox_offset

func _process(delta: float) -> void:
	_update_xray_depth()
	if not alive:
		return
	var before: Vector3 = position
	position.z -= forward_speed * speed_boost_multiplier * delta
	_handle_steering(delta)
	_update_combat_zone(delta)
	_update_banking(delta)
	_handle_combat(delta)
	_update_aim()
	if delta > 0.0:
		velocity = (position - before) / delta

# Feed the x-ray shader the view-space Z of the ship's nearest point, so its
# occlusion test only fires for occluders in front of the whole ship (never the
# ship's own parts). Uses the currently-active camera.
func _update_xray_depth() -> void:
	if _xray_mat == null:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	var center_vz: float = (cam.global_transform.affine_inverse() * global_position).z
	_xray_mat.set_shader_parameter("ship_front_vz", center_vz + XRAY_FRONT_OFFSET)

# Central crash entry point (a lethal hazard, or a high-speed meteorite slam).
func crash() -> void:
	if not alive:
		return
	alive = false
	Sfx.play("death")
	crashed.emit(-position.z)

func _on_hazard_body_entered(_body: Node3D) -> void:
	crash()

# --- Combat ----------------------------------------------------------------
# Per-frame: decay timers, auto-fire while held, fire the temporary weapon-tier
# decay, and service the afterburner. Only runs while alive (called from _process).
func _handle_combat(delta: float) -> void:
	if _hurt_cd > 0.0:
		_hurt_cd = maxf(0.0, _hurt_cd - delta)
	if _ab_cd > 0.0:
		_ab_cd = maxf(0.0, _ab_cd - delta)

	# Temporary shooting buff decays back a step toward single fire after a lull.
	if weapon_tier > 1:
		weapon_tier_time -= delta
		if weapon_tier_time <= 0.0:
			weapon_tier -= 1
			weapon_tier_time = WEAPON_TIER_DURATION

	_fire_cd -= delta
	if _fire_cd <= 0.0 and Input.is_action_pressed("fire"):
		_fire_shot()
		_fire_cd = BASE_FIRE_INTERVAL / fire_rate_mult

	if owns_afterburner and _ab_cd <= 0.0 and Input.is_action_just_pressed("afterburner"):
		apply_speed_boost(AFTERBURNER_MULT, AFTERBURNER_DURATION)
		_ab_cd = AFTERBURNER_COOLDOWN
		Sfx.play("boost")

# --- Reticle aim (2026-07-19) ----------------------------------------------
# Ray-traced targeting for the angled views: the fire line is straight -Z (where shots
# actually go), so each frame we cast it against enemy + mine hurtboxes and cache the
# hit. game_hud lands the 3-4 / isometric reticle on `aim_point` when `aim_hit`, so the
# crosshair sits directly on the enemy/mine in the line of fire.
var aim_hit: bool = false
var aim_point: Vector3 = Vector3.ZERO
var aim_origin: Vector3 = Vector3.ZERO

# The world point shots spawn from (shared by _fire_shot and the aim ray so the
# reticle traces the exact path a bullet takes).
func _fire_origin() -> Vector3:
	return global_position + Vector3(0, 0, -1) * (ship_visual_radius * 1.2) + Vector3(0, 0.1, 0)

# Ray-trace the fire line against enemy + mine hurtboxes (LAYER_ENEMY, all Area3D) so the
# reticle can land directly on the first target the shot would reach. Areas only; ignores
# terrain/props (player shots pass through those too). Space state is queried the same way
# the ship's soft-clearance ray already does, from _process.
func _update_aim() -> void:
	aim_origin = _fire_origin()
	var space := get_world_3d().direct_space_state
	if space == null:
		aim_hit = false
		return
	var q := PhysicsRayQueryParameters3D.create(aim_origin, aim_origin + Vector3(0, 0, -1) * AIM_RANGE)
	q.collision_mask = Combat.LAYER_ENEMY
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit: Dictionary = space.intersect_ray(q)
	aim_hit = not hit.is_empty()
	if aim_hit:
		aim_point = hit.position

# Spawn the current weapon pattern's bullets into world space (the ship's parent),
# so they don't inherit the ship's motion/scaling. Always fired straight forward
# (-Z), the direction the ship flies.
func _fire_shot() -> void:
	var world: Node = get_parent()
	if world == null:
		return
	var forward := Vector3(0, 0, -1)
	var origin: Vector3 = _fire_origin()
	for a in _shot_angles():
		var dir: Vector3 = forward.rotated(Vector3.UP, a)
		var pr: Area3D = PROJECTILE.new()
		pr.team = Combat.TEAM_PLAYER
		pr.damage = SHOT_DAMAGE
		pr.velocity = dir * SHOT_SPEED
		pr.color = SHOT_COLOR
		world.add_child(pr)
		pr.global_position = origin
	Sfx.play("shoot", 1.0, 0.09)

# Horizontal fan angles (radians) for each weapon tier.
func _shot_angles() -> Array:
	match weapon_tier:
		2:
			return [deg_to_rad(-3.0), deg_to_rad(3.0)]
		3:
			return [0.0, deg_to_rad(-9.0), deg_to_rad(9.0)]
		4:
			return [deg_to_rad(-22.0), deg_to_rad(-11.0), 0.0, deg_to_rad(11.0), deg_to_rad(22.0)]
		_:
			return [0.0]

# Incoming damage. Shield absorbs first, then health. A short i-frame after any hit
# keeps overlapping contact from deleting the player in one frame.
func take_damage(amount: float) -> void:
	if not alive or _hurt_cd > 0.0 or amount <= 0.0:
		return
	var remaining: float = amount
	var had_shield: bool = shield > 0.0
	if shield > 0.0:
		var absorbed: float = minf(shield, remaining)
		shield -= absorbed
		remaining -= absorbed
	if remaining > 0.0:
		health -= remaining
	_hurt_cd = HURT_IFRAME
	health_changed.emit(health, MAX_HEALTH, shield, shield_capacity)
	if health <= 0.0:
		health = 0.0
		crash()
	elif remaining > 0.0:
		Sfx.play("hurt")
	elif had_shield:
		Sfx.play("shield")

# Slow, continuous damage from a hazard the ship is sitting inside (field cloud,
# latched leech, grasping tentacle). NOT gated by the combat i-frame -- callers pass
# a small per-frame amount (dps * delta), so it bleeds health steadily rather than
# in one gated chunk. Shield still soaks first.
func take_dot(amount: float) -> void:
	if not alive or amount <= 0.0:
		return
	var remaining: float = amount
	if shield > 0.0:
		var absorbed: float = minf(shield, remaining)
		shield -= absorbed
		remaining -= absorbed
	if remaining > 0.0:
		health -= remaining
	health_changed.emit(health, MAX_HEALTH, shield, shield_capacity)
	if health <= 0.0:
		health = 0.0
		crash()

# External displacement from a pushing hazard (geyser/vent blast). Shoves the ship
# by a per-frame delta, respecting the per-view axis locks (a locked axis can't be
# pushed off its pin). The lethal geometry still applies -- being shoved into a wall
# crashes you, which is the point.
func apply_push(delta_move: Vector3) -> void:
	if not alive:
		return
	if not steer_x_locked:
		position.x += delta_move.x
	if not steer_y_locked:
		position.y += delta_move.y
	position.z += delta_move.z

# The ship's CombatDetector overlaps an enemy shot (take damage + consume it) or an
# enemy body (contact damage).
func _on_combat_area_entered(area: Area3D) -> void:
	if not alive:
		return
	if area.is_in_group(Combat.GROUP_ENEMY_SHOT):
		take_damage(area.damage)
		area.queue_free()
	elif area.is_in_group(Combat.GROUP_ENEMY_HURTBOX):
		take_damage(CONTACT_DAMAGE)

# --- Upgrades collected from drops -----------------------------------------
# Temporary: bump the shooting tier a step (single->double->triple->spread) and
# refresh the decay timer.
func add_weapon_tier() -> void:
	weapon_tier = mini(WEAPON_TIER_MAX, weapon_tier + 1)
	weapon_tier_time = WEAPON_TIER_DURATION

# Permanent (this life): a shield plate raises capacity and tops the shield up.
func add_shield() -> void:
	shield_capacity += SHIELD_PER_PIECE
	shield = shield_capacity
	health_changed.emit(health, MAX_HEALTH, shield, shield_capacity)

# Permanent (this life): faster fire.
func upgrade_fire_rate() -> void:
	fire_rate_mult = minf(FIRE_RATE_MAX, fire_rate_mult + FIRE_RATE_STEP)

# Permanent (this life): unlock the player-triggered afterburner boost.
func unlock_afterburner() -> void:
	owns_afterburner = true

func afterburner_ready() -> bool:
	return owns_afterburner and _ab_cd <= 0.0

# Soft off-path leash (see the export block). Per zone-limited free axis: if the ship is
# more than zone_half_width beyond the trailing anchor, cap its OUTWARD steer velocity to
# zone_follow_speed and add a gentle inward spring (soft push-back, not a wall), and raise
# the alarm. The anchor always eases toward the ship at zone_follow_speed, so a determined
# player keeps moving (the world follows) and the alarm clears once they settle back inside.
func _update_combat_zone(delta: float) -> void:
	var lz: bool = false
	if zone_limit_x and not steer_x_locked:
		lz = _zone_axis_x(delta) or lz
	if zone_limit_y and not steer_y_locked:
		lz = _zone_axis_y(delta) or lz
	leaving_zone = lz

func _zone_axis_x(delta: float) -> bool:
	var off: float = position.x - _zone_center.x
	var leaving: bool = false
	if absf(off) > zone_half_width:
		leaving = true
		if signf(steer_velocity.x) == signf(off) and absf(steer_velocity.x) > zone_follow_speed:
			steer_velocity.x = signf(off) * zone_follow_speed          # cap outward speed
		steer_velocity.x -= signf(off) * zone_spring * (absf(off) - zone_half_width) * delta  # soft return
	_zone_center.x = move_toward(_zone_center.x, position.x, zone_follow_speed * delta)
	return leaving

func _zone_axis_y(delta: float) -> bool:
	var off: float = position.y - _zone_center.y
	var leaving: bool = false
	if absf(off) > zone_half_width:
		leaving = true
		if signf(steer_velocity.y) == signf(off) and absf(steer_velocity.y) > zone_follow_speed:
			steer_velocity.y = signf(off) * zone_follow_speed
		steer_velocity.y -= signf(off) * zone_spring * (absf(off) - zone_half_width) * delta
	_zone_center.y = move_toward(_zone_center.y, position.y, zone_follow_speed * delta)
	return leaving

func _handle_steering(delta: float) -> void:
	var input_x: float = Input.get_axis("steer_left", "steer_right")
	var input_y: float = Input.get_axis("steer_down", "steer_up")

	# Inertia: steer velocity ramps toward the input target (and toward zero on
	# release) instead of position snapping directly. Gives the ship weight.
	var target := Vector2(input_x, input_y) * steer_speed
	steer_velocity = steer_velocity.move_toward(target, steer_accel * delta)

	# X: free (unbounded) unless this viewpoint locks depth -> pin to center.
	if steer_x_locked:
		position.x = 0.0
		steer_velocity.x = 0.0
	else:
		var dx: float = _soft_axis_move(Vector3.RIGHT, steer_velocity.x * delta)
		position.x += dx
		if absf(dx) < absf(steer_velocity.x * delta) - 1e-5:
			steer_velocity.x = 0.0     # blocked by geometry -> stop pressing into it

	# Y: free (unbounded) unless locked -> pin to spawn height. Steering DOWN into the
	# ground (or up into a ceiling) now HALTS a clearance short instead of crashing.
	if steer_y_locked:
		position.y = flight_spawn_y
		steer_velocity.y = 0.0
	else:
		var dy: float = _soft_axis_move(Vector3.UP, steer_velocity.y * delta)
		position.y += dy
		if absf(dy) < absf(steer_velocity.y * delta) - 1e-5:
			steer_velocity.y = 0.0

# Allowed movement along `axis` (signed): the requested `move`, unless lethal geometry is
# within (move + clearance) ahead -- then clamped so the ship stops a clearance short of
# it (0 if already inside the clearance). Prevents steering into geometry the player often
# can't see behind the shallow camera; the HazardDetector stays as a backstop.
func _soft_axis_move(axis: Vector3, move: float) -> float:
	if not soft_stop_enabled or absf(move) < 1e-6:
		return move
	var clearance: float = ship_visual_radius * soft_clearance
	var dir: Vector3 = axis * signf(move)
	var space := get_world_3d().direct_space_state
	if space == null:
		return move
	var q := PhysicsRayQueryParameters3D.create(global_position, global_position + dir * (absf(move) + clearance))
	q.collision_mask = HAZARD_COLLISION_LAYER
	q.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return move
	var allowed: float = maxf(0.0, global_position.distance_to(hit.position) - clearance)
	return signf(move) * minf(absf(move), allowed)

# Roll the hull into lateral turns and pitch it with climb/dive, eased. Driven by
# normalized steer momentum so the tilt inherits the inertia (banks in as the ship
# accelerates sideways, levels out as it coasts to a stop). Cosmetic only.
func _update_banking(delta: float) -> void:
	if steer_speed <= 0.0:
		return
	var nx: float = clampf(steer_velocity.x / steer_speed, -1.0, 1.0)
	var ny: float = clampf(steer_velocity.y / steer_speed, -1.0, 1.0)
	var target_roll: float = deg_to_rad(-max_bank_deg) * nx
	var target_pitch: float = deg_to_rad(max_pitch_deg) * ny
	var t: float = 1.0 - exp(-bank_sharpness * delta)
	if hull_instance != null and is_instance_valid(hull_instance):
		hull_instance.rotation.z = lerp_angle(hull_instance.rotation.z, target_roll, t)
		hull_instance.rotation.x = lerp_angle(hull_instance.rotation.x, target_pitch, t)
	# Mounts bank with the hull so attachments stay visually fixed to it.
	mounts.rotation.z = lerp_angle(mounts.rotation.z, target_roll, t)
	mounts.rotation.x = lerp_angle(mounts.rotation.x, target_pitch, t)

# Fill the next empty mount with a themed greeble. `kind` selects the greeble
# silhouette (see AttachmentBuilder); `color` is the current level's theme color
# so a run's parts read as belonging to the levels they were picked up on.
# Growth caps naturally once every mount is filled.
func grow_ship(kind: String = "cosmetic", color: Color = Color(0.7, 0.7, 0.75, 1.0)) -> void:
	if filled_mounts >= mounts.get_child_count():
		return
	var mount: Node3D = mounts.get_child(filled_mounts)
	# Snug placement: the mount sits on the hull surface (set in _place_mounts); the
	# part splays outward along the canonical face normal (not the position, which
	# carries the hull's centre offset), so it emerges cleanly from the surface.
	var outward: Vector3 = MountUtil.DIRECTIONS[filled_mounts % MountUtil.DIRECTIONS.size()]
	var attachment: Node3D = AttachmentBuilder.build(kind, color, attachment_scale, outward)
	mount.add_child(attachment)
	_apply_xray(attachment)   # attachments show through occluders too

	attachments_collected += 1
	filled_mounts += 1
	ship_visual_radius = 1.0 + filled_mounts * growth_step
	_refresh_exhaust()   # jet grows / sits further back as the hull grows

	var detector_shape: CollisionShape3D = pickup_detector.get_node("CollisionShape3D")
	detector_shape.scale = Vector3.ONE * ship_visual_radius
	var hazard_shape: CollisionShape3D = hazard_detector.get_node("CollisionShape3D")
	hazard_shape.scale = Vector3.ONE * ship_visual_radius
	hazard_shape.position = hazard_hitbox_offset * ship_visual_radius
	var combat_shape: CollisionShape3D = combat_detector.get_node("CollisionShape3D")
	combat_shape.scale = Vector3.ONE * ship_visual_radius

# Record a just-collected pickup as a candidate PIECE for the end-of-level draft,
# if it's eligible (a cosmetic hull part or a permanent upgrade -- not a transient
# buff). Called by power_up on collect. The greeble/effect are applied elsewhere;
# this only logs the piece so the beauty-shot menu can offer it.
func note_collected_piece(kind: String, color: Color, effect: String, grows: bool) -> void:
	if PieceUtil.is_eligible(effect, grows):
		collected_pieces.append({"kind": kind, "color": color, "effect": effect})

# Re-establish the run's permanent loadout on the fresh ship (called each level
# after reset()): bolt on every kept piece and re-apply its permanent effect. This
# deterministically rebuilds the same ship + upgrades every stage from the kept
# list -- reset() zeroed everything first, so effects don't stack across stages.
# These are NOT re-recorded into collected_pieces (they're already permanent).
func apply_permanent_loadout(pieces: Array) -> void:
	for p_v in pieces:
		var p: Dictionary = p_v
		grow_ship(p.get("kind", "cosmetic"), p.get("color", Color(0.7, 0.7, 0.75)))
		match p.get("effect", ""):
			"shield":
				add_shield()
			"fire_rate":
				upgrade_fire_rate()
			"afterburner":
				unlock_afterburner()

func apply_speed_boost(multiplier: float, duration: float) -> void:
	speed_boost_multiplier = multiplier
	await get_tree().create_timer(duration).timeout
	speed_boost_multiplier = 1.0

func apply_magnet(duration: float) -> void:
	magnet_active = true
	await get_tree().create_timer(duration).timeout
	magnet_active = false

func reset() -> void:
	position = Vector3(0, flight_spawn_y, 0)
	alive = true
	speed_boost_multiplier = 1.0
	magnet_active = false
	steer_velocity = Vector2.ZERO
	_zone_center = Vector2(0.0, flight_spawn_y)   # anchor the combat zone on the spawn point
	leaving_zone = false
	filled_mounts = 0
	attachments_collected = 0
	collected_pieces.clear()
	ship_visual_radius = 1.0
	_refresh_exhaust()   # back to base size/offset for the fresh ship

	# Combat state resets with the ship on a retry (consistent with attachments
	# being cleared -- upgrades are "permanent" only within a single life).
	health = MAX_HEALTH
	shield = 0.0
	shield_capacity = 0.0
	weapon_tier = 1
	weapon_tier_time = 0.0
	fire_rate_mult = 1.0
	owns_afterburner = false
	_fire_cd = 0.0
	_hurt_cd = 0.0
	_ab_cd = 0.0
	health_changed.emit(health, MAX_HEALTH, shield, shield_capacity)

	# Level the hull out (a retry starts flat, not mid-bank).
	if hull_instance != null and is_instance_valid(hull_instance):
		hull_instance.rotation = Vector3.ZERO
	mounts.rotation = Vector3.ZERO

	for mount in mounts.get_children():
		for attachment in mount.get_children():
			attachment.queue_free()

	var detector_shape: CollisionShape3D = pickup_detector.get_node("CollisionShape3D")
	detector_shape.scale = Vector3.ONE
	var hazard_shape: CollisionShape3D = hazard_detector.get_node("CollisionShape3D")
	hazard_shape.scale = Vector3.ONE
	hazard_shape.position = hazard_hitbox_offset
	var combat_shape: CollisionShape3D = combat_detector.get_node("CollisionShape3D")
	combat_shape.scale = Vector3.ONE
