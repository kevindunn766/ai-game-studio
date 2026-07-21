extends Node3D

# PUSHING hazard: a rooted vent/geyser that periodically ERUPTS and shoves the ship
# away from it (up + outward) while the ship is in range. It doesn't damage -- it
# knocks you off course (potentially into a wall or another hazard). The eruption is
# telegraphed: particles only stream during the active window, so you can time it.
# Environmental -- not destroyable (like the field hazard).
#
# Fields set by the spawner before add_child: accent, scale_ref, ship.

var accent: Color = Color(0.8, 0.85, 0.9, 1.0)
var scale_ref: float = 1.0
var ship: Node3D = null
var variant: String = "geyser"      # "geyser" (erupting) | "waterfall" (continuous cascade)

var _radius: float = 4.5
var _strength: float = 15.0
var _erupt_dur: float = 1.0
var _cooldown: float = 1.6
var _t: float = 0.0
var _erupting: bool = false
var _particles: CPUParticles3D = null

func _ready() -> void:
	if variant == "waterfall":
		_radius = scale_ref * 4.0
		_strength = scale_ref * 12.0
		_build_waterfall()
		return
	_radius = scale_ref * 4.5
	_strength = scale_ref * 15.0
	_erupt_dur = randf_range(0.8, 1.3)
	_cooldown = randf_range(1.3, 2.2)
	_t = randf_range(0.0, _erupt_dur + _cooldown)     # desync multiple vents
	_build_vent()
	_build_plume()

# A continuous cascade of water that shoves the ship down + away (off course, toward
# the open side / into obstacles). No erupt cycle -- it's always falling.
func _build_waterfall() -> void:
	var top: float = scale_ref * 7.0
	var p := CPUParticles3D.new()
	p.emitting = true
	p.one_shot = false
	p.amount = 60
	p.lifetime = 1.4
	p.position = Vector3(0, top, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.4 * scale_ref, 0.4 * scale_ref, _radius * 0.7)
	p.direction = Vector3(0, -1, 0)
	p.spread = 8.0
	p.gravity = Vector3(0, -20.0, 0)
	p.initial_velocity_min = 4.0 * scale_ref
	p.initial_velocity_max = 7.0 * scale_ref
	p.scale_amount_min = 0.5 * scale_ref
	p.scale_amount_max = 1.2 * scale_ref
	var pale: Color = accent.lerp(Color(0.95, 0.98, 1.0), 0.7)
	var q := QuadMesh.new()
	q.size = Vector2(0.8 * scale_ref, 1.6 * scale_ref)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	q.material = mat
	p.mesh = q
	p.color = pale
	var g := Gradient.new()
	g.set_color(0, Color(pale.r, pale.g, pale.b, 0.85))
	g.set_color(1, Color(pale.r, pale.g, pale.b, 0.0))
	p.color_ramp = g
	add_child(p)
	_particles = p

func _build_vent() -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = scale_ref * 0.5
	cone.bottom_radius = scale_ref * 0.75
	cone.height = scale_ref * 0.7
	var mi := MeshInstance3D.new()
	mi.mesh = cone
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.16, 0.18)
	mat.metallic = 0.3
	mat.roughness = 0.6
	mi.material_override = mat
	mi.position = Vector3(0, scale_ref * 0.35, 0)
	add_child(mi)

func _build_plume() -> void:
	var p := CPUParticles3D.new()
	p.emitting = false                                # only streams during an eruption
	p.one_shot = false
	p.amount = 40
	p.lifetime = 0.9
	p.explosiveness = 0.1
	p.position = Vector3(0, scale_ref * 0.6, 0)
	p.spread = 22.0
	p.direction = Vector3(0, 1, 0)
	p.gravity = Vector3(0, -2.0, 0)
	p.initial_velocity_min = 8.0 * scale_ref
	p.initial_velocity_max = 13.0 * scale_ref
	p.scale_amount_min = 0.8 * scale_ref
	p.scale_amount_max = 1.6 * scale_ref
	var col: Color = accent.lerp(Color(0.9, 0.95, 1.0), 0.5)      # pale, steamy
	p.color = col
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, 0.0))
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	g.add_point(0.25, Color(col.r, col.g, col.b, 0.6))
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.9 * scale_ref, 0.9 * scale_ref)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	q.material = mat
	p.mesh = q
	_particles = p
	add_child(p)

func _process(delta: float) -> void:
	if variant == "waterfall":
		if ship == null or not is_instance_valid(ship) or not ship.alive:
			return
		if global_position.distance_to(ship.global_position) <= _radius and ship.has_method("apply_push"):
			var d: Vector3 = ship.global_position - global_position
			d.y = 0.0                                   # horizontal shove away from the cascade...
			d = Vector3.RIGHT if d.length() < 0.05 else d.normalized()
			d = (d + Vector3.DOWN * 0.8).normalized()   # ...and down, like water hammering you
			ship.apply_push(d * _strength * delta)
		return
	_t += delta
	var phase: float = fmod(_t, _erupt_dur + _cooldown)
	var now_erupt: bool = phase < _erupt_dur
	if now_erupt != _erupting:
		_erupting = now_erupt
		if _particles != null:
			_particles.emitting = _erupting

	if not _erupting or ship == null or not is_instance_valid(ship) or not ship.alive:
		return
	if global_position.distance_to(ship.global_position) <= _radius and ship.has_method("apply_push"):
		var dir: Vector3 = ship.global_position - global_position
		dir = Vector3.UP if dir.length() < 0.05 else dir.normalized()
		dir = (dir + Vector3.UP * 0.6).normalized()   # bias the shove upward, like a geyser
		ship.apply_push(dir * _strength * delta)
