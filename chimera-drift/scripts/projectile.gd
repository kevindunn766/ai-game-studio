extends Area3D

# A bullet, shared by the player and enemies (team decides its layer/mask + who it
# can hit). Built entirely in code -- the spawner sets team/damage/velocity/color
# as fields, then add_child()s it and sets global_position.
#
# Player shots (team PLAYER) monitor for enemy hurtboxes and damage them on
# contact. Enemy shots (team ENEMY) don't monitor anything -- the ship's
# CombatDetector is what detects THEM and applies damage to the player.

const Combat := preload("res://scripts/combat.gd")

var team: int = Combat.TEAM_PLAYER
var damage: float = 1.0
var velocity: Vector3 = Vector3.ZERO      # world units/sec
var color: Color = Color(0.6, 0.9, 1.0, 1.0)
var radius: float = 0.14                   # small bolt (was 0.22)
var life: float = 2.6                     # seconds before it self-frees

# Player shots gently curve toward a nearby, roughly-ahead enemy so a near-miss still
# connects (Kevin). Enemy shots stay straight. Deliberately SUBTLE -- dialed back from a
# strong lock-on (3.0 rad/s / 45 range / ~46 deg cone) to a light nudge: only tighten-aimed
# shots at close range get corrected, so you still have to aim.
@export var homing_rate: float = 1.2      # rad/s the bolt can turn toward a target (0 = off)
@export var homing_range: float = 24.0    # only seeks enemies within this
const HOMING_CONE: float = 0.85           # cos of the seek half-angle (~32 deg) -> only well-aimed shots

var _age: float = 0.0
var _mi: MeshInstance3D = null            # the bolt visual (re-aimed as it curves)

func _ready() -> void:
	var is_player: bool = team == Combat.TEAM_PLAYER
	monitoring = is_player                 # only player shots need to detect targets
	monitorable = true
	if is_player:
		collision_layer = Combat.LAYER_PLAYER_SHOT
		collision_mask = Combat.LAYER_ENEMY
		add_to_group(Combat.GROUP_PLAYER_SHOT)
		area_entered.connect(_on_area_entered)
	else:
		collision_layer = Combat.LAYER_ENEMY_SHOT
		collision_mask = 0                 # the ship detects us, not vice-versa
		add_to_group(Combat.GROUP_ENEMY_SHOT)

	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = radius
	cs.shape = sph
	add_child(cs)

	# Small low-poly PRISM bolt (a rectangular prism -- 24 verts) instead of the old
	# ~2k-vert SphereMesh. Thin cross-section, elongated along travel, pointed down its
	# velocity so it reads as a bolt from any firing direction.
	var box := BoxMesh.new()
	box.size = Vector3(radius, radius, radius * 3.0)
	_mi = MeshInstance3D.new()
	var mi := _mi
	mi.mesh = box
	if velocity.length() > 0.001:
		var up: Vector3 = Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT
		mi.transform = Transform3D().looking_at(velocity, up)   # local -Z faces travel
	var mat := StandardMaterial3D.new()
	var glow: Color = color.lightened(0.3)
	mat.albedo_color = glow
	mat.emission_enabled = true
	mat.emission = glow
	mat.emission_energy_multiplier = 1.2
	mi.material_override = mat
	add_child(mi)

func _process(delta: float) -> void:
	if team == Combat.TEAM_PLAYER and homing_rate > 0.0:
		_home(delta)
	position += velocity * delta
	_age += delta
	if _age >= life:
		queue_free()

# Curve the bolt slightly toward the nearest roughly-ahead enemy, capped at homing_rate
# rad/s (keeps the speed constant). Re-aims the visual to match.
func _home(delta: float) -> void:
	var speed: float = velocity.length()
	if speed < 0.001:
		return
	var cur: Vector3 = velocity / speed
	var target: Node3D = _nearest_enemy(cur)
	if target == null:
		return
	var to_t: Vector3 = target.global_position - global_position
	var d: float = to_t.length()
	if d < 0.01:
		return
	var desired: Vector3 = to_t / d
	var ang: float = cur.angle_to(desired)
	if ang < 0.0001:
		return
	var new_dir: Vector3 = cur.slerp(desired, minf(1.0, (homing_rate * delta) / ang))
	velocity = new_dir * speed
	if _mi != null:
		var up: Vector3 = Vector3.UP if absf(new_dir.y) < 0.99 else Vector3.RIGHT
		_mi.transform = Transform3D().looking_at(new_dir, up)

# Nearest enemy/mine hurtbox within homing_range that sits within the seek cone ahead of
# the bolt's current heading (so it nudges toward targets you roughly aimed at, not behind).
func _nearest_enemy(cur: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d: float = homing_range
	for e in get_tree().get_nodes_in_group(Combat.GROUP_ENEMY_HURTBOX):
		if not is_instance_valid(e):
			continue
		var to_e: Vector3 = e.global_position - global_position
		var d: float = to_e.length()
		if d < 0.01 or d > best_d:
			continue
		if cur.dot(to_e / d) < HOMING_CONE:
			continue
		best_d = d
		best = e
	return best

func _on_area_entered(area: Area3D) -> void:
	if area.is_in_group(Combat.GROUP_ENEMY_HURTBOX) and area.has_method("take_hit"):
		area.take_hit(damage)
		queue_free()
