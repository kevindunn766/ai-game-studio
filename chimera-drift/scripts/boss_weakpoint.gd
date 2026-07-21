extends Area3D

# A glowing VULNERABLE weak point on the boss -- the "shoot here" spot. It's an
# enemy hurtbox (LAYER_ENEMY, GROUP_ENEMY_HURTBOX) so player projectiles hit it
# and call take_hit(). Pulses/rotates; flashes on hit; emits `destroyed` when its
# health runs out. The boss mounts these at the builder's anchor positions and
# handles the pop VFX + boss-death check. No class_name (headless-safe).

const Combat := preload("res://scripts/combat.gd")

signal destroyed(weakpoint)

var max_health: float = 20.0
var health: float = 20.0
var accent: Color = Color(1.0, 0.45, 0.2)
var core_radius: float = 1.0
var alive: bool = true

var _core: MeshInstance3D = null
var _mat: StandardMaterial3D = null
var _t: float = 0.0
var _flash: float = 0.0

func _ready() -> void:
	collision_layer = Combat.LAYER_ENEMY
	collision_mask = 0
	monitoring = false
	monitorable = true
	add_to_group(Combat.GROUP_ENEMY_HURTBOX)

	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = core_radius * 1.15
	cs.shape = sph
	add_child(cs)

	var mesh := SphereMesh.new()
	mesh.radius = core_radius
	mesh.height = core_radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	_core = MeshInstance3D.new()
	_core.mesh = mesh
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = accent.lerp(Color.WHITE, 0.2)
	_mat.emission_enabled = true
	_mat.emission = accent
	_mat.emission_energy_multiplier = 2.0
	_core.material_override = _mat
	add_child(_core)

# Called by projectile.gd on a player-shot hit.
func take_hit(amount: float) -> void:
	if not alive:
		return
	health -= amount
	_flash = 1.0
	# shrink a touch as it takes damage, so weakening reads visually
	var frac: float = clampf(health / max_health, 0.0, 1.0)
	_core.scale = Vector3.ONE * (0.6 + 0.4 * frac)
	if health <= 0.0:
		alive = false
		destroyed.emit(self)
		queue_free()

func _process(delta: float) -> void:
	if not alive:
		return
	_t += delta
	_flash = maxf(0.0, _flash - delta * 3.0)
	var pulse: float = 1.8 + 0.9 * sin(_t * 4.5)
	_mat.emission_energy_multiplier = pulse + _flash * 5.0
	_core.rotate_y(delta * 1.6)
