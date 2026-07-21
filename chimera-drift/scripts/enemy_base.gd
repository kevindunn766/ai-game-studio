extends Area3D

# Shared base for the two flying-enemy categories (dumb radial swarmers +
# smart ship-pipeline dogfighters). The root IS the hurtbox: an Area3D on
# LAYER_ENEMY so player shots can hit it and the ship's CombatDetector registers
# contact. Subclasses call super._ready() first (sets up the hurtbox), then build
# their own visual + AI. Fields are assigned by EnemySpawner BEFORE add_child, so
# they're valid by _ready.

const Combat := preload("res://scripts/combat.gd")
const PROJECTILE := preload("res://scripts/projectile.gd")
const PowerUp := preload("res://scripts/power_up.gd")
const EXPLOSION := preload("res://scripts/explosion.gd")
const VFX := preload("res://scripts/vfx.gd")

# --- Assigned by the spawner before the node enters the tree ----------------
var ship: Node3D = null
var world: Node3D = null                 # where drops + this enemy's shots are added (the generator)
var theme: Dictionary = {}
var accent: Color = Color(0.9, 0.3, 0.3, 1.0)
var enemy_scale: float = 1.0
var max_health: float = 3.0
var health: float = 3.0

# What this enemy drops on death (an effect string understood by power_up.gd).
var drop_effect: String = ""
var drop_kind: String = "cosmetic"       # greeble silhouette if the drop grows the ship
var drop_grows_ship: bool = false        # true -> the drop also fills a ship mount (permanent piece)

# Enemy weapon tuning (subclasses that shoot read these).
var shot_damage: float = 8.0
var shot_speed: float = 26.0
var fire_interval: float = 1.6
var fire_range: float = 70.0

var alive: bool = true

func _ready() -> void:
	collision_layer = Combat.LAYER_ENEMY
	collision_mask = 0
	monitoring = false                   # detected BY others; doesn't detect
	monitorable = true
	add_to_group(Combat.GROUP_ENEMY_HURTBOX)
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = _hurt_radius()
	cs.shape = sph
	add_child(cs)
	if _wants_trail():
		_setup_trail()

# Overridden per subclass to fit its silhouette.
func _hurt_radius() -> float:
	return enemy_scale * 1.0

# Only the flying enemies leave a trail (mines/stationary hazards override this to false
# -- a world-space trail on something that doesn't move is just a puff cloud).
func _wants_trail() -> bool:
	return false

# A faint glowing motion trail (lightweight world-space particles, themed to the enemy's
# accent) so a moving enemy reads as a live threat. Skipped on the lowest perf tier.
func _setup_trail() -> void:
	if PerfProfile.particle_scale <= 0.0:
		return
	var amount: int = maxi(3, int(round(9.0 * PerfProfile.particle_scale)))
	var col := Color(accent.r, accent.g, accent.b, 0.5)
	add_child(VFX.trail(col, 0.11 * enemy_scale, amount, 0.4, Vector3.ZERO, 0.0, true))

func take_hit(amount: float) -> void:
	if not alive:
		return
	health -= amount
	if health <= 0.0:
		_die()
	else:
		Sfx.play("enemy_hit", 1.0, 0.12)

func _die() -> void:
	if not alive:
		return
	alive = false
	Combat.player_kills += 1         # tallied per level for the win-screen stats
	Sfx.play("enemy_down", 1.0, 0.1)
	_spawn_explosion(0.85)          # every enemy death bursts flash + smoke
	_spawn_drop()
	queue_free()

# Spawn the shared flash+smoke VFX at this enemy's position, parented to world so
# it outlives the (about-to-free) enemy. size scales the blast (mines pass bigger).
func _spawn_explosion(size: float) -> void:
	if world == null or not is_instance_valid(world):
		return
	var ex := EXPLOSION.new()
	ex.accent = accent
	ex.scale_ref = maxf(enemy_scale, 0.6) * size
	world.add_child(ex)
	ex.global_position = global_position

# Spawn this enemy's death drop into world space (the generator), where the ship's
# PickupDetector can collect it exactly like a streamed power-up.
func _spawn_drop() -> void:
	if drop_effect == "" or world == null or not is_instance_valid(world):
		return
	var p: Area3D = PowerUp.new()
	p.effect = drop_effect
	p.kind = drop_kind
	p.grows_ship = drop_grows_ship
	p.attach_color = accent
	p.ship = ship
	world.add_child(p)
	p.global_position = global_position

# Fire one shot toward the player, with a little inaccuracy so aim reads "weak".
func _fire_at_player(inaccuracy: float = 0.06) -> void:
	if world == null or ship == null or not is_instance_valid(ship) or not ship.alive:
		return
	var dir: Vector3 = ship.global_position - global_position
	if dir.length() < 0.001:
		return
	dir = dir.normalized()
	dir += Vector3(randf_range(-inaccuracy, inaccuracy), randf_range(-inaccuracy, inaccuracy), randf_range(-inaccuracy, inaccuracy))
	dir = dir.normalized()
	var pr: Area3D = PROJECTILE.new()
	pr.team = Combat.TEAM_ENEMY
	pr.damage = shot_damage
	pr.velocity = dir * shot_speed
	pr.color = Color(1.0, 0.4, 0.25, 1.0)
	pr.radius = 0.16 * maxf(enemy_scale, 1.0)   # small bolt (was 0.26)
	world.add_child(pr)
	pr.global_position = global_position + dir * (_hurt_radius() + 0.4)

func _player_in_range() -> bool:
	if ship == null or not is_instance_valid(ship) or not ship.alive:
		return false
	return global_position.distance_to(ship.global_position) <= fire_range
