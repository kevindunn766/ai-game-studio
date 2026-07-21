extends RigidBody3D
class_name Meteorite

# A drifting asteroid with microgravity physics. Floats with near-zero damping,
# bumps other meteorites, and reacts to the ship by CLOSING SPEED along the
# contact normal: a glancing/gentle touch nudges the rock off in a direction
# (and the player survives); a fast head-on slam crashes the ship.
#
# Shooting a meteorite calls shatter() -- built here, wired to the weapon when the
# Battle system exists. Fragmenting is two tiers: LARGE -> MEDIUM -> SMALL -> pop.

enum Size { SMALL, MEDIUM, LARGE }

const METEORITE_LAYER: int = 16              # own physics layer (not the ship/hazard layers)
const CRASH_CLOSING_SPEED: float = 6.0       # closing speed (along contact normal) that crashes the ship
const NUDGE_COOLDOWN: float = 0.4            # min seconds between nudges (avoids per-frame re-hits)
const FRAGMENTS: int = 3

var size_class: int = Size.MEDIUM
var body_radius: float = 0.5
var ship: Node3D = null
var spawner: Node = null
var _cooldown: float = 0.0

static func size_scale(sz: int, base: float) -> float:
	match sz:
		Size.SMALL:
			return base * 0.4
		Size.MEDIUM:
			return base * 0.8
		_:
			return base * 1.4

func setup(sz: int, at_position: Vector3, base: float, ship_ref: Node3D, spawner_ref: Node, color: Color, initial_vel: Vector3 = Vector3.ZERO) -> void:
	size_class = sz
	ship = ship_ref
	spawner = spawner_ref
	var s: float = size_scale(sz, base)
	body_radius = s * 0.45
	position = at_position

	# Microgravity drift: no gravity, barely any damping, some mass by volume.
	gravity_scale = 0.0
	linear_damp = 0.04
	angular_damp = 0.03
	mass = maxf(0.2, pow(s, 3.0) * 2.0)
	collision_layer = METEORITE_LAYER
	collision_mask = METEORITE_LAYER          # meteorites bump each other, nothing else

	var mi := MeshInstance3D.new()
	mi.mesh = LevelGeo.asteroid(s, randf() * 900.0)
	var matl := StandardMaterial3D.new()
	matl.albedo_color = color
	matl.roughness = 0.9
	mi.material_override = matl
	mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	add_child(mi)

	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = body_radius
	cs.shape = sph
	add_child(cs)

	# Slow initial drift + gentle tumble.
	linear_velocity = initial_vel + Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 0.4
	angular_velocity = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 0.5

func _physics_process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
	if ship == null or not ship.alive or _cooldown > 0.0:
		return
	var to_me: Vector3 = global_position - ship.global_position
	var contact_dist: float = body_radius + ship.ship_visual_radius * 0.6
	if to_me.length() > contact_dist:
		return
	var normal: Vector3 = to_me.normalized()
	if normal.length() < 0.5:
		normal = Vector3.FORWARD
	# Closing speed of the ship relative to this rock, along the contact normal.
	var closing: float = (ship.velocity - linear_velocity).dot(normal)
	if closing > CRASH_CLOSING_SPEED:
		ship.crash()
		return
	# Gentle/glancing: shove the rock off in the contact direction (slow drift) + a
	# bit of spin. dv is capped so it always reads as a microgravity nudge.
	var dv: float = clampf(absf(closing) * 0.5, 0.4, 3.0)
	apply_central_impulse(normal * dv * mass)
	apply_torque_impulse(Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 0.15 * mass)
	_cooldown = NUDGE_COOLDOWN

# Break up (called by the weapon once Battle exists). Two tiers then gone:
# LARGE spawns MEDIUM, MEDIUM spawns SMALL, SMALL just pops.
func shatter() -> void:
	if size_class == Size.SMALL:
		_pop()
		return
	var next: int = size_class - 1
	if spawner != null and spawner.has_method("spawn_meteorite"):
		for i in range(FRAGMENTS):
			var dir: Vector3 = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
			var frag_vel: Vector3 = linear_velocity + dir * randf_range(1.5, 3.0)
			var frag_pos: Vector3 = global_position + dir * body_radius * 0.6
			spawner.spawn_meteorite(next, frag_pos, frag_vel)
	_pop()

func _pop() -> void:
	# Grey-box: a themed particle burst can hook in here later.
	queue_free()
