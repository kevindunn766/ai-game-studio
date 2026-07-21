extends "res://scripts/enemy_base.gd"

# LEECH slow-damage hazard: it drops down from a tunnel ceiling at you, or leaps up
# at you from the landscape ("drop" / "leap" spawn modes). When the ship comes near
# it launches, homes onto the ship, latches on, and drains health (DOT) for a spell
# before letting go. Destroyable -- shoot it (in its dormant/launch phase) and it
# pops with the shared explosion VFX (via enemy_base._die).

const MeshUtil := preload("res://scripts/mesh_util.gd")

var spawn_mode: String = "drop"          # "drop" (from ceiling) | "leap" (from ground)
var dps: float = 11.0
var latch_duration: float = 3.0
var trigger_range: float = 10.0
var launch_speed: float = 15.0

var _state: String = "dormant"           # dormant -> launch -> latched
var _latch_t: float = 0.0
var _latch_offset: Vector3 = Vector3.ZERO
var _anchor: Vector3 = Vector3.ZERO
var _wob: float = 0.0

func _hurt_radius() -> float:
	return enemy_scale * 0.75

func _ready() -> void:
	max_health = 2.0
	health = 2.0
	trigger_range = enemy_scale * 10.0
	launch_speed = enemy_scale * 15.0
	_wob = randf_range(0.0, TAU)
	super._ready()
	_build_visual()

func post_spawn() -> void:
	_anchor = position

func _build_visual() -> void:
	var col: Color = accent.lerp(Color(0.75, 0.15, 0.35), 0.55)   # sickly danger tint
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 0.35
	mat.metallic = 0.1
	mat.roughness = 0.5

	# A squashed bulbous body...
	var body := SphereMesh.new()
	body.radius = enemy_scale * 0.5
	body.height = enemy_scale * 0.75
	var body_mi := MeshInstance3D.new()
	body_mi.mesh = MeshUtil.flat(body)
	body_mi.material_override = mat
	add_child(body_mi)

	# ...with a few little tendrils hanging toward the ship side (-? just downward).
	for i in range(3):
		var t := _cyl(enemy_scale * 0.07, enemy_scale * 0.5)
		var tm := MeshInstance3D.new()
		tm.mesh = MeshUtil.flat(t)
		tm.material_override = mat
		var a: float = TAU * float(i) / 3.0
		tm.position = Vector3(cos(a) * enemy_scale * 0.22, -enemy_scale * 0.4, sin(a) * enemy_scale * 0.22)
		add_child(tm)

func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r * 0.6
	c.height = h
	return c

func _process(delta: float) -> void:
	if not alive:
		return
	match _state:
		"dormant":
			_wob += delta * 2.0
			position.x = _anchor.x + sin(_wob) * 0.1 * enemy_scale
			if _should_trigger():
				_state = "launch"
		"launch":
			if ship == null or not is_instance_valid(ship) or not ship.alive:
				return
			var to: Vector3 = ship.global_position - global_position
			var d: float = to.length()
			if d <= enemy_scale * 1.2:
				_state = "latched"
				_latch_t = 0.0
				_latch_offset = (global_position - ship.global_position).limit_length(enemy_scale * 0.9)
			else:
				global_position += to.normalized() * launch_speed * delta
		"latched":
			if ship == null or not is_instance_valid(ship) or not ship.alive:
				_die()
				return
			global_position = ship.global_position + _latch_offset
			ship.take_dot(dps * delta)
			_latch_t += delta
			if _latch_t >= latch_duration:
				_die()          # releases and pops

# Trigger once the ship is within range AND on the side the leech comes from
# (below for a ceiling drop, above for a ground leap) -- so it lunges as you pass.
func _should_trigger() -> bool:
	if ship == null or not is_instance_valid(ship) or not ship.alive:
		return false
	if global_position.distance_to(ship.global_position) > trigger_range:
		return false
	var dy: float = ship.global_position.y - global_position.y
	if spawn_mode == "drop":
		return dy < 1.0            # ship is below the ceiling leech
	return dy > -1.0               # ship is above the ground leech
