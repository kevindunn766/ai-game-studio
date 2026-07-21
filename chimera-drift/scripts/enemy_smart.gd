extends "res://scripts/enemy_base.gd"

# SMART flying enemy: an actual procedural SHIP, built from the same pipeline the
# player's hull uses (ShipHullGenerator), recolored to the current level's theme
# so it reads as "this level's" fighter. It weakly dogfights -- eases toward the
# player to hold a standoff range, strafes on a sine, slowly turns to face, and
# fires leading-ish shots with loose aim. Killing one drops a PERMANENT ship piece
# (shield / rate-of-fire / afterburner) -- wired in EnemySpawner.

const ShipHull := preload("res://scripts/ship_hull_generator.gd")
const MeshUtil := preload("res://scripts/mesh_util.gd")

const SMART_SIZE: float = 1.15           # visual size relative to the player's hull envelope

var _hull: Node3D = null
var _radius: float = 1.2
var _standoff: float = 10.0
var _speed: float = 6.0
var _turn_rate: float = 1.6              # rad/sec toward facing the player (slow = "weak")
var _strafe_amp: float = 3.0
var _strafe_speed: float = 1.1
var _strafe_phase: float = 0.0
var _fire_cd: float = 1.5
var _size_jitter: float = 1.0            # random per-enemy size on top of SMART_SIZE
var _roll_speed: float = 0.0             # gentle barrel-roll for liveliness

func _hurt_radius() -> float:
	return _radius

func _wants_trail() -> bool:
	return true

func _ready() -> void:
	_size_jitter = randf_range(0.82, 1.25)
	_roll_speed = randf_range(-0.9, 0.9)
	_build_hull()
	_radius = maxf(ShipHull.TARGET_LONGEST * SMART_SIZE * enemy_scale * _size_jitter * 0.5, 0.6)
	super._ready()

	_standoff = enemy_scale * randf_range(7.0, 12.0)
	_speed = randf_range(5.0, 8.0)
	_turn_rate = randf_range(1.2, 2.2)
	_strafe_amp = enemy_scale * randf_range(2.0, 4.0)
	_strafe_speed = randf_range(0.8, 1.5)
	_strafe_phase = randf_range(0.0, TAU)
	fire_interval = randf_range(1.1, 2.0)
	shot_damage = 8.0
	shot_speed = 30.0

func _build_hull() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var result: Dictionary = ShipHull.generate(rng)
	_hull = result.hull
	var aabb: AABB = result.aabb
	var longest: float = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
	var scale_k: float = (ShipHull.TARGET_LONGEST / longest) if longest > 0.0 else 1.0
	_hull.scale = Vector3.ONE * scale_k * SMART_SIZE * enemy_scale * _size_jitter
	_recolor(_hull)
	_flatten(_hull)
	add_child(_hull)

# Retheme every hull part to the level accent (small per-part value spread so it
# still reads as a built ship, not a flat silhouette).
func _recolor(node: Node) -> void:
	var i: int = 0
	_recolor_walk(node, i)

func _recolor_walk(node: Node, i: int) -> int:
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		var v: float = 1.0 + (float(i % 3) - 1.0) * 0.18       # 0.82 / 1.0 / 1.18
		var c: Color = accent
		c.v = clampf(c.v * v, 0.08, 1.0)
		mat.albedo_color = c
		mat.metallic = 0.25
		mat.roughness = 0.55
		node.material_override = mat
		i += 1
	for child in node.get_children():
		i = _recolor_walk(child, i)
	return i

func _flatten(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		node.mesh = MeshUtil.flat(node.mesh)
	for child in node.get_children():
		_flatten(child)

func post_spawn() -> void:
	pass

func _process(delta: float) -> void:
	if not alive:
		return
	if ship == null or not is_instance_valid(ship):
		return

	var to_player: Vector3 = ship.global_position - global_position
	var dist: float = to_player.length()
	if dist < 0.001:
		return
	var dir: Vector3 = to_player / dist

	# Hold a standoff: close if too far, back off if too close.
	var along: Vector3 = Vector3.ZERO
	if dist > _standoff * 1.1:
		along = dir * _speed
	elif dist < _standoff * 0.8:
		along = -dir * _speed * 0.6

	# Strafe perpendicular to the line of sight (in the horizontal-ish plane).
	_strafe_phase += _strafe_speed * delta
	var side: Vector3 = dir.cross(Vector3.UP)
	if side.length() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized()
	var strafe: Vector3 = side * cos(_strafe_phase) * _strafe_amp

	position += (along + strafe) * delta

	# Slowly turn to face the player (nose is the hull's local -Z, which look_at
	# aims at the target). Interpolated so the turn feels heavy/weak. Both bases are
	# orthonormalized first -- Basis.slerp casts to a Quaternion, which rejects the
	# tiny non-orthonormal drift that accumulates from slerping every frame.
	var target_xf: Transform3D = global_transform.looking_at(ship.global_position, Vector3.UP)
	var current: Basis = global_transform.basis.orthonormalized()
	var target: Basis = target_xf.basis.orthonormalized()
	global_transform.basis = current.slerp(target, clampf(_turn_rate * delta, 0.0, 1.0))
	# Gentle barrel-roll of the hull (relative to the facing) for a bit of life.
	if _hull != null:
		_hull.rotation.z += _roll_speed * delta

	# Fire on a cadence when the player is in range.
	_fire_cd -= delta
	if _fire_cd <= 0.0 and _player_in_range():
		_fire_at_player(0.05)
		_fire_cd = fire_interval
