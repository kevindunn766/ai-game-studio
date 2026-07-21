extends "res://scripts/enemy_base.gd"

# GRASPER slow-damage hazard: a tentacle / vine rooted to a surface (floor or
# terrain) that sways idly, then leans toward and grasps at the ship when it comes
# within reach, draining health (DOT) while the ship stays close. Destroyable --
# shoot it and it pops (enemy_base._die). Built as a chain of tapering segments so
# it writhes; a traveling sine drives the sway, biased toward the ship when grasping.

const MeshUtil := preload("res://scripts/mesh_util.gd")

const SEGMENTS: int = 7

var dps: float = 8.0
var grasp_range: float = 5.0
var length: float = 4.0

var _segs: Array = []                    # segment Node3Ds (chained), root..tip
var _seg_len: float = 0.6
var _t: float = 0.0
var _sway_amp: float = 0.18
var _sway_speed: float = 2.2
var _grasp: float = 0.0                  # 0 idle .. 1 fully reaching toward ship

func _hurt_radius() -> float:
	return length * 0.55

func _ready() -> void:
	max_health = 4.0
	health = 4.0
	length = enemy_scale * 4.0
	grasp_range = enemy_scale * 4.5
	_seg_len = length / float(SEGMENTS)
	_sway_amp = randf_range(0.12, 0.24)
	_sway_speed = randf_range(1.8, 2.8)
	_t = randf_range(0.0, TAU)
	super._ready()
	# Lift the hurtbox sphere up to the tentacle's mid-height so shots along its
	# body register (enemy_base centers it at the root by default).
	for c in get_children():
		if c is CollisionShape3D:
			c.position = Vector3(0, length * 0.5, 0)
	_build_tentacle()

func _build_tentacle() -> void:
	var col: Color = accent.lerp(Color(0.25, 0.55, 0.3), 0.5)   # vine-ish, theme-biased
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.metallic = 0.05
	mat.roughness = 0.7

	var parent: Node3D = self
	for i in range(SEGMENTS):
		var seg := Node3D.new()
		seg.position = Vector3(0, 0.0 if i == 0 else _seg_len, 0)   # stack tip-to-base
		parent.add_child(seg)
		var taper: float = 1.0 - float(i) / float(SEGMENTS) * 0.6
		var mesh := _cyl(enemy_scale * 0.22 * taper, _seg_len * 1.02)
		var mi := MeshInstance3D.new()
		mi.mesh = MeshUtil.flat(mesh)
		mi.material_override = mat
		mi.position = Vector3(0, _seg_len * 0.5, 0)
		seg.add_child(mi)
		_segs.append(seg)
		parent = seg
	# A little grasping bulb at the tip.
	var tip := SphereMesh.new()
	tip.radius = enemy_scale * 0.22
	tip.height = enemy_scale * 0.4
	var tip_mi := MeshInstance3D.new()
	tip_mi.mesh = MeshUtil.flat(tip)
	tip_mi.material_override = mat
	tip_mi.position = Vector3(0, _seg_len, 0)
	parent.add_child(tip_mi)

func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r * 0.7
	c.bottom_radius = r
	c.height = h
	return c

func _process(delta: float) -> void:
	if not alive:
		return
	_t += delta * _sway_speed

	var reaching: bool = false
	var toward_local := Vector3.ZERO
	if ship != null and is_instance_valid(ship) and ship.alive:
		var head: Vector3 = global_position + Vector3(0, length * 0.75, 0)
		if head.distance_to(ship.global_position) <= grasp_range:
			reaching = true
			ship.take_dot(dps * delta)
			# Direction to the ship expressed in the grasper's local frame, so the
			# whole tentacle leans that way.
			toward_local = global_transform.basis.inverse() * (ship.global_position - global_position).normalized()
	_grasp = move_toward(_grasp, 1.0 if reaching else 0.0, delta * 2.0)

	# Writhe: a traveling wave along the chain, plus a lean toward the ship while grasping.
	for i in range(_segs.size()):
		var phase: float = _t - float(i) * 0.5
		var sway_x: float = sin(phase) * _sway_amp
		var sway_z: float = cos(phase * 0.8) * _sway_amp * 0.6
		var lean_x: float = toward_local.x * _grasp * 0.35
		var lean_z: float = toward_local.z * _grasp * 0.35
		_segs[i].rotation = Vector3(sway_z + lean_z, 0.0, -(sway_x + lean_x))
