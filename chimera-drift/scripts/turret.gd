extends "res://scripts/enemy_base.gd"

# STATIONARY enemy -- a turret. A rooted pedestal with a head + barrel that tracks
# the player and fires on a cadence (reuses enemy_base's projectile). It never moves.
# Destroyable: shoot it and it pops with the shared explosion VFX (enemy_base._die).
# Themed to the level accent with a danger tint, like the flying enemies.

const MeshUtil := preload("res://scripts/mesh_util.gd")

var _head: Node3D = null
var _height: float = 1.1
var _fire_cd: float = 1.0

func _hurt_radius() -> float:
	return enemy_scale * 1.1

func _ready() -> void:
	max_health = 5.0
	health = 5.0
	_height = enemy_scale * 1.1
	fire_interval = randf_range(1.3, 2.2)
	fire_range = enemy_scale * 60.0
	shot_damage = 7.0
	shot_speed = 30.0
	super._ready()
	# Lift the hurtbox to the turret's mid-height (enemy_base centers it at the base).
	for c in get_children():
		if c is CollisionShape3D:
			c.position = Vector3(0, _height * 0.55, 0)
	_build()

func _build() -> void:
	var col: Color = accent.lerp(Color(0.85, 0.2, 0.2), 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.metallic = 0.35
	mat.roughness = 0.5

	# Pedestal (wide, short) rooted at the base.
	var ped := CylinderMesh.new()
	ped.top_radius = enemy_scale * 0.42
	ped.bottom_radius = enemy_scale * 0.55
	ped.height = _height * 0.5
	var ped_mi := MeshInstance3D.new()
	ped_mi.mesh = MeshUtil.flat(ped)
	ped_mi.material_override = mat
	ped_mi.position = Vector3(0, _height * 0.25, 0)
	add_child(ped_mi)

	# Head (yaws/pitches to face the ship) with a forward barrel along its local -Z.
	_head = Node3D.new()
	_head.position = Vector3(0, _height, 0)
	add_child(_head)

	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(enemy_scale * 0.7, enemy_scale * 0.55, enemy_scale * 0.7)
	var head_mi := MeshInstance3D.new()
	head_mi.mesh = MeshUtil.flat(head_mesh)
	head_mi.material_override = mat
	_head.add_child(head_mi)

	var barrel := CylinderMesh.new()
	barrel.top_radius = enemy_scale * 0.13
	barrel.bottom_radius = enemy_scale * 0.16
	barrel.height = enemy_scale * 0.9
	var barrel_mi := MeshInstance3D.new()
	barrel_mi.mesh = MeshUtil.flat(barrel)
	barrel_mi.material_override = mat
	barrel_mi.rotation = Vector3(deg_to_rad(90), 0, 0)              # lay the cylinder along -Z
	barrel_mi.position = Vector3(0, 0, -enemy_scale * 0.55)
	_head.add_child(barrel_mi)

func _process(delta: float) -> void:
	if not alive:
		return
	if ship == null or not is_instance_valid(ship) or not ship.alive:
		return
	# Aim the head at the ship (fresh look_at each frame -> no accumulated drift). Pick
	# a safe up vector when the ship is nearly straight above/below.
	var to: Vector3 = ship.global_position - _head.global_position
	if to.length() > 0.05:
		var up: Vector3 = Vector3.UP if absf(to.normalized().y) < 0.98 else Vector3.FORWARD
		_head.look_at(ship.global_position, up)

	_fire_cd -= delta
	if _fire_cd <= 0.0 and _player_in_range():
		_fire_at_player(0.04)
		_fire_cd = fire_interval
