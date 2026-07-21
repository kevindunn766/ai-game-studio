extends Node3D

# The end-of-level BOSS (Star Fox style). Slides in from off-screen, then KEEPS
# PACE ahead of the player (the player keeps flying) -- sitting `LEAD` units in
# front, easing toward the player's x/y and sliding in a strafe pattern while
# firing volleys. The player must destroy its glowing WEAK POINTS; the armored
# hull just eats stray shots (no weak-point behind it). When the last weak point
# pops, it plays a death sequence and emits `defeated` (LevelDirector wins).

const BossBuilder := preload("res://scripts/boss_builder.gd")
const WeakPoint := preload("res://scripts/boss_weakpoint.gd")
const Combat := preload("res://scripts/combat.gd")
const PROJECTILE := preload("res://scripts/projectile.gd")
const EXPLOSION := preload("res://scripts/explosion.gd")

signal defeated

const LEAD: float = 34.0            # how far ahead of the ship the boss holds
const SLIDE_IN: float = 1.7         # seconds to slide into the arena
const FOLLOW_RATE: float = 1.2      # how fast the boss re-centres on the player x/y
const STRAFE_X: float = 9.0
const STRAFE_Y: float = 4.5
const WEAK_HEALTH: float = 16.0

var ship: Node3D = null
var world: Node3D = null            # where shots + explosions are parented (world space)
var primary: Color = Color(0.5, 0.45, 0.55)
var accent: Color = Color(1.0, 0.45, 0.2)

var boss_seed: int = -1             # set by the director from the biome (deterministic per biome)
var viewpoint: String = ""          # set by the director; tunes how far ahead the boss holds
var _lead: float = LEAD
var _weak: Array = []
var _center: Vector2 = Vector2.ZERO
var _ent_x: float = 0.0             # slide-in offset, in SCREEN axes (camera right/up)
var _ent_y: float = 55.0
var _phase: String = "slidein"
var _t: float = 0.0
var _slide_t: float = 0.0
var _fire_cd: float = 1.6
var _dying: bool = false

var sector: int = 1                 # player progress -> difficulty (set by the director)
var tier: int = 0                   # 0 normal, 1 SUPER (every 8), 2 ULTRA (final boss)
var _kind: String = "core_arms"     # archetype -> attack pattern
var _shot_bonus: int = 0            # extra shots per volley (tier)
var _volley: int = 0               # volley counter (ultra cycles archetypes)
var _wp_health: float = WEAK_HEALTH
var _shot_damage: float = 7.0
var _shot_speed: float = 30.0
var _fire_scale: float = 1.0        # <1 = faster volleys (higher sectors)
var _weak_total: float = 1.0        # initial sum of weak-point health (for the HUD bar)
var _spin: float = 0.0             # ring archetype spin accumulator

# Called by LevelDirector BEFORE adding to the tree.
func setup(ship_node: Node3D, world_node: Node3D, primary_col: Color, accent_col: Color) -> void:
	ship = ship_node
	world = world_node
	primary = primary_col
	accent = accent_col

func _ready() -> void:
	Sfx.play("boss_warn")               # ominous entrance sting
	# Overhead views (ortho, zoomed out) want the boss closer + more centred so it
	# reads as a big presence rather than a speck far up-screen.
	match viewpoint:
		"topdown":
			_lead = 16.0
		"isometric":
			_lead = 24.0
		_:
			_lead = LEAD

	var rng := RandomNumberGenerator.new()
	if boss_seed >= 0:
		rng.seed = boss_seed          # same biome -> same boss
	else:
		rng.randomize()
	# SUPER / ULTRA bosses run hotter colours so they read as a threat at a glance.
	if tier == 1:
		accent = accent.lerp(Color(1.0, 0.55, 0.1), 0.5)     # molten gold
	elif tier == 2:
		accent = accent.lerp(Color(1.0, 0.12, 0.1), 0.6)     # menacing crimson

	var built: Dictionary = BossBuilder.build(rng, primary, accent)
	_kind = built.get("kind", "core_arms")
	# Bigger, meaner silhouette per tier. Scale the HULL (not `self`, whose basis is
	# rebuilt by look_at every frame) and the weak points to match.
	var size_mult: float = [1.0, 1.4, 1.8][tier]
	(built.hull as Node3D).scale = Vector3.ONE * size_mult
	add_child(built.hull)

	# Difficulty scales with player progress (sector). Clamped so late stages get
	# meaningfully tougher without becoming impossible.
	var d: float = clampf(float(sector), 1.0, 12.0)
	_wp_health = 13.0 + (d - 1.0) * 3.5          # 13 (s1) -> ~51 (s12)
	_shot_damage = 6.0 + (d - 1.0) * 1.3
	_shot_speed = 28.0 + (d - 1.0) * 2.2
	_fire_scale = maxf(0.45, 1.0 - (d - 1.0) * 0.07)   # volleys get faster

	# Tier multipliers stack on top of the sector scaling.
	_wp_health *= [1.0, 1.7, 2.6][tier]
	_shot_damage *= [1.0, 1.25, 1.5][tier]
	_shot_speed *= [1.0, 1.1, 1.2][tier]
	_fire_scale *= [1.0, 0.85, 0.7][tier]         # super/ultra fire faster
	_shot_bonus = tier * 2                        # +2 / +4 shots per volley

	for anchor_v in built.anchors:
		var anchor: Vector3 = anchor_v
		var wp := WeakPoint.new()
		wp.accent = accent
		wp.max_health = _wp_health
		wp.health = _wp_health
		wp.position = anchor * size_mult
		wp.scale = Vector3.ONE * size_mult
		wp.destroyed.connect(_on_weak_destroyed)
		add_child(wp)
		_weak.append(wp)
	_weak_total = maxf(1.0, _wp_health * float(_weak.size()))

	# Slide in from a random off-screen SCREEN edge (top / left / right).
	var e: Vector2 = [Vector2(0, 58), Vector2(-78, 12), Vector2(78, 12)][rng.randi() % 3]
	_ent_x = e.x
	_ent_y = e.y
	if ship != null and is_instance_valid(ship):
		_center = Vector2(ship.global_position.x, ship.global_position.y)
		position = Vector3(_center.x, _center.y + 40.0, ship.global_position.z - _lead)

func _process(delta: float) -> void:
	if _dying or ship == null or not is_instance_valid(ship):
		return
	_t += delta

	# Screen axes of the ACTIVE camera, so the boss reads in ANY view (its weak
	# points face the camera and it strafes across the screen, not into it).
	var cam := get_viewport().get_camera_3d()
	var cam_right := Vector3.RIGHT
	var cam_up := Vector3.UP
	if cam != null:
		cam_right = cam.global_transform.basis.x
		cam_up = cam.global_transform.basis.y

	# Keep pace: hold LEAD ahead of the ship (z exact), ease toward its x/y.
	var target_c := Vector2(ship.global_position.x, ship.global_position.y)
	_center = _center.lerp(target_c, clampf(FOLLOW_RATE * delta, 0.0, 1.0))
	var base := Vector3(_center.x, _center.y, ship.global_position.z - _lead)
	var strafe := cam_right * (sin(_t * 0.9) * STRAFE_X) + cam_up * (sin(_t * 0.7 + 1.1) * STRAFE_Y)
	var combat := base + strafe

	if _phase == "slidein":
		_slide_t += delta
		var b: float = smoothstep(0.0, 1.0, _slide_t / SLIDE_IN)
		var ent := cam_right * _ent_x + cam_up * _ent_y
		global_position = combat + ent * (1.0 - b)
		if _slide_t >= SLIDE_IN:
			_phase = "combat"
	else:
		global_position = combat

	# Face the active camera so the weak points + hull profile are always visible.
	# The ring archetype spins continuously (its spokes sweep); others roll gently.
	if cam != null:
		_face_camera(cam.global_position)
		if _kind == "ring":
			_spin += delta * 1.3
			rotate_object_local(Vector3(0, 0, 1), _spin)
		else:
			rotate_object_local(Vector3(0, 0, 1), deg_to_rad(7.0) * sin(_t * 0.8))

	if _phase == "combat":
		_fire_cd -= delta
		if _fire_cd <= 0.0 and ship.alive:
			_attack()
			_fire_cd = _fire_interval()

# Orient so the boss's +Z (front, where the weak points + profile are) points at
# the camera -- look_at aims -Z at the target, so aim it at the point BEHIND us.
func _face_camera(cam_pos: Vector3) -> void:
	var n: Vector3 = cam_pos - global_position
	if n.length() < 0.1:
		return
	n = n.normalized()
	var up: Vector3 = Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	look_at(global_position - n, up)

# Fraction of the boss's original weak-point health still standing (for the HUD).
func health_fraction() -> float:
	if _weak_total <= 0.0:
		return 0.0
	var cur: float = 0.0
	for wp in _weak:
		if is_instance_valid(wp):
			cur += (wp as Node).health
	return clampf(cur / _weak_total, 0.0, 1.0)

func is_active() -> bool:
	return not _dying

# Seconds between volleys -- per-archetype base, sped up by difficulty (_fire_scale).
func _fire_interval() -> float:
	var base: float
	match _kind:
		"wall":
			base = randf_range(2.0, 2.8)
		"ring":
			base = randf_range(1.6, 2.3)
		_:
			base = randf_range(1.3, 2.0)
	return base * _fire_scale

# Record key for the persistent best-time table: distinguishes each boss TYPE
# (archetype) and tier -> "Core"/"Wall"/"Ring", "Super Core"/…, "Ultra".
func record_key() -> String:
	var t: String = {"core_arms": "Core", "wall": "Wall", "ring": "Ring"}.get(_kind, "Core")
	match tier:
		2:
			return "Ultra"
		1:
			return "Super " + t
		_:
			return t

# Label for the HUD boss bar, by tier.
func hud_title() -> String:
	match tier:
		2:
			return "☠  F I N A L   B O S S  ☠"
		1:
			return "◈  SUPER BOSS  ◈"
		_:
			return "◈  B O S S  ◈"

# Pick + fire the attack for this boss's archetype. SUPER/ULTRA add a radial spray on
# top; ULTRA also cycles through all three archetype patterns volley to volley.
func _attack() -> void:
	if world == null or not is_instance_valid(world) or ship == null or not ship.alive:
		return
	var base: Vector3 = ship.global_position - global_position
	if base.length() < 0.5:
		return
	base = base.normalized()
	var cam := get_viewport().get_camera_3d()
	var cam_up: Vector3 = cam.global_transform.basis.y if cam != null else Vector3.UP

	var kind: String = _kind
	if tier == 2:
		kind = ["core_arms", "wall", "ring"][_volley % 3]   # ultra cycles patterns
	_volley += 1
	_fire_pattern(kind, base, cam_up)

	if tier >= 1:
		# extra radial spray layered over the archetype attack (super/ultra)
		_fire_ring(base, 6 + tier * 3, 0.5, _spin + 0.4)

func _fire_pattern(kind: String, base: Vector3, cam_up: Vector3) -> void:
	match kind:
		"wall":
			# a wide horizontal WALL of shots the player flies around (fan across screen)
			_fire_fan(base, 7 + _shot_bonus, 0.55, cam_up)
		"ring":
			# radial SPOKES around the aim axis, offset by the current spin -> a spiral
			_fire_ring(base, 10 + _shot_bonus, 0.30, _spin)
		_:
			# tight aimed BURST
			_fire_fan(base, 5 + _shot_bonus, 0.16, cam_up)

# Spread `count` shots evenly across +/- `half` radians around `axis`, centred on `base`.
func _fire_fan(base: Vector3, count: int, half: float, axis: Vector3) -> void:
	if count <= 1 or axis.length() < 0.001:
		_fire_shot(base)
		return
	var ax: Vector3 = axis.normalized()
	for i in range(count):
		var t: float = float(i) / float(count - 1) * 2.0 - 1.0   # -1 .. 1
		_fire_shot(base.rotated(ax, t * half))

# `count` shots each tilted `cone` off `base`, distributed around it (a ring/spiral).
func _fire_ring(base: Vector3, count: int, cone: float, phase: float) -> void:
	var perp: Vector3 = base.cross(Vector3.UP)
	if perp.length() < 0.01:
		perp = base.cross(Vector3.RIGHT)
	perp = perp.normalized()
	for i in range(count):
		var ang: float = phase + TAU * float(i) / float(count)
		var offaxis: Vector3 = perp.rotated(base, ang)
		_fire_shot(base.rotated(offaxis, cone))

func _fire_shot(dir: Vector3) -> void:
	var d: Vector3 = dir.normalized()
	var pr: Area3D = PROJECTILE.new()
	pr.team = Combat.TEAM_ENEMY
	pr.damage = _shot_damage
	pr.velocity = d * _shot_speed
	pr.color = accent.lerp(Color(1.0, 0.4, 0.2), 0.5)
	pr.radius = 0.3
	world.add_child(pr)
	pr.global_position = global_position + d * 4.0

func _on_weak_destroyed(wp: Node) -> void:
	Sfx.play("weak_pop", 1.0, 0.1)
	if is_instance_valid(wp):
		_spawn_explosion((wp as Node3D).global_position, 1.5)
	_weak.erase(wp)
	if _weak.is_empty():
		_die()

func _die() -> void:
	if _dying:
		return
	_dying = true
	Sfx.play("boss_die")
	_death_sequence()

func _death_sequence() -> void:
	# Bigger, longer detonation for super/ultra bosses.
	var bursts: int = 7 + tier * 5
	var spread: float = 6.0 + tier * 3.0
	var big: float = 4.5 + tier * 2.5
	for _i in range(bursts):
		var off := Vector3(randf_range(-spread, spread), randf_range(-spread * 0.7, spread * 0.75), randf_range(-2.0, 4.0))
		_spawn_explosion(global_position + off, randf_range(1.6, 2.8) * (1.0 + 0.4 * tier))
		await get_tree().create_timer(0.13).timeout
		if not is_instance_valid(self):
			return
	_spawn_explosion(global_position, big)
	defeated.emit()
	queue_free()

func _spawn_explosion(pos: Vector3, size: float) -> void:
	if world == null or not is_instance_valid(world):
		return
	var ex: Node3D = EXPLOSION.new()
	ex.accent = accent
	ex.scale_ref = size
	world.add_child(ex)
	ex.global_position = pos
