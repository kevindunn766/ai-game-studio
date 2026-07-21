extends Node3D

# FIELD slow-damage hazard: a cloud of particles that either just hangs like a
# cloud of hot mist ("mist"), or plumes up from something like a volcano / hot vent
# ("vent"). While the ship is inside the cloud radius it takes slow damage-over-time.
# Environmental -- not shootable/destroyable. Streamed + recycled like props.
#
# "Hot" reads warm regardless of the biome: the level accent is pushed toward a
# fiery orange so a field always looks like heat haze (a deliberate choice; the
# mine glow, by contrast, stays pure theme color).

const HOT := Color(1.0, 0.45, 0.15, 1.0)

var accent: Color = Color(0.9, 0.5, 0.3, 1.0)
var scale_ref: float = 1.0
var variant: String = "mist"          # "mist" | "vent" | "lava"
var dps: float = 6.0
var ship: Node3D = null

var _radius: float = 4.0
var _push: float = 0.0                 # lava also shoves (a flow has momentum)

func _ready() -> void:
	_radius = scale_ref * 3.6
	var hot: Color = accent.lerp(HOT, 0.6)
	if variant == "vent":
		_build_vent_source(hot)
		_build_plume(hot)
	elif variant == "lava":
		dps = 10.0                                # a molten flow burns harder than mist
		_push = scale_ref * 7.0
		_build_lava()
	else:
		_build_mist(hot)

# A glowing molten flow: a low pool of bright lava with rising embers. Ignores the
# biome accent (lava is always molten orange/red) -- like the cliff lava particles.
func _build_lava() -> void:
	var molten := Color(1.0, 0.45, 0.1)
	var pool := _particles(molten, 0.55)
	pool.amount = 40
	pool.lifetime = 1.8
	pool.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	pool.emission_box_extents = Vector3(_radius * 0.9, 0.15 * scale_ref, _radius * 0.9)
	pool.spread = 40.0
	pool.gravity = Vector3(0, 0.3, 0)
	pool.initial_velocity_min = 0.1 * scale_ref
	pool.initial_velocity_max = 0.6 * scale_ref
	pool.scale_amount_min = 1.2 * scale_ref
	pool.scale_amount_max = 2.4 * scale_ref
	(pool.mesh.material as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	add_child(pool)
	var embers := _particles(Color(1.0, 0.7, 0.2), 0.8)
	embers.amount = 22
	embers.lifetime = 1.4
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	embers.emission_box_extents = Vector3(_radius * 0.7, 0.1 * scale_ref, _radius * 0.7)
	embers.direction = Vector3(0, 1, 0)
	embers.spread = 25.0
	embers.gravity = Vector3(0, -1.0, 0)
	embers.initial_velocity_min = 2.0 * scale_ref
	embers.initial_velocity_max = 4.5 * scale_ref
	embers.scale_amount_min = 0.3 * scale_ref
	embers.scale_amount_max = 0.7 * scale_ref
	(embers.mesh.material as StandardMaterial3D).blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	add_child(embers)

func _build_mist(col: Color) -> void:
	var p := _particles(col, 0.32)
	p.amount = 42
	p.lifetime = 2.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = _radius * 0.85
	p.spread = 180.0
	p.gravity = Vector3(0, 0.2, 0)
	p.initial_velocity_min = 0.15 * scale_ref
	p.initial_velocity_max = 0.8 * scale_ref
	p.scale_amount_min = 1.4 * scale_ref
	p.scale_amount_max = 2.6 * scale_ref
	add_child(p)

func _build_plume(col: Color) -> void:
	# A rising column from the vent at the base of the field.
	var p := _particles(col, 0.4)
	p.amount = 38
	p.lifetime = 2.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = _radius * 0.3
	p.position = Vector3(0, -_radius * 0.5, 0)
	p.spread = 35.0
	p.direction = Vector3(0, 1, 0)
	p.gravity = Vector3(0, 2.0, 0)
	p.initial_velocity_min = 2.0 * scale_ref
	p.initial_velocity_max = 5.0 * scale_ref
	p.scale_amount_min = 1.0 * scale_ref
	p.scale_amount_max = 2.2 * scale_ref
	add_child(p)

# A small dark cone as the actual vent/volcano mouth.
func _build_vent_source(col: Color) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = _radius * 0.28
	cone.bottom_radius = _radius * 0.55
	cone.height = _radius * 0.5
	var mi := MeshInstance3D.new()
	mi.mesh = cone
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.14, 0.13, 0.13)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 0.5
	mi.material_override = mat
	mi.position = Vector3(0, -_radius * 0.55, 0)
	add_child(mi)

func _particles(col: Color, alpha: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = true
	p.one_shot = false
	var q := QuadMesh.new()
	q.size = Vector2(1.0 * scale_ref, 1.0 * scale_ref)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	q.material = mat
	p.mesh = q
	p.color = Color(col.r, col.g, col.b, alpha)
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, 0.0))
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	# Fade in then out over life via 3 stops.
	g.add_point(0.35, Color(col.r, col.g, col.b, alpha))
	p.color_ramp = g
	return p

func _process(delta: float) -> void:
	if ship == null or not is_instance_valid(ship) or not ship.alive:
		return
	if global_position.distance_to(ship.global_position) <= _radius:
		if ship.has_method("take_dot"):
			ship.take_dot(dps * delta)
		# A lava flow also shoves you (down + away) -- both damage AND push, per design.
		if _push > 0.0 and ship.has_method("apply_push"):
			var d: Vector3 = ship.global_position - global_position
			d.y = 0.0
			d = Vector3.RIGHT if d.length() < 0.05 else d.normalized()
			d = (d + Vector3.DOWN * 0.5).normalized()
			ship.apply_push(d * _push * delta)
