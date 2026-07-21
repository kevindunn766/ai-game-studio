extends "res://scripts/enemy_base.gd"

# A mine: a simple flat DISK with a glowing center on both the top and bottom that
# matches the level color theme. Spawned in formations (see mine_field.gd) -- lines
# (vertical/horizontal/diagonal), rings, diamonds. Disks face the travel axis (their
# flat faces point +/-Z) so a formation reads as a wall of glowing coins the player
# flies into.
#
# It damages the player, enemies, AND other mines: shooting one (or touching it)
# detonates it, which chain-detonates nearby mines (shoot one in a ring -> the whole
# ring goes) and destroys/damages any enemies caught in the blast. Detonation plays
# the shared flash+smoke explosion VFX.

const MeshUtil := preload("res://scripts/mesh_util.gd")

const GROUP_MINE := "mine"
const CHAIN_DELAY: float = 0.05           # ripple time between a mine and its neighbours
const BLAST_PLAYER_DAMAGE: float = 26.0
const BLAST_ENEMY_DAMAGE: float = 999.0   # enemies caught in a blast are destroyed

var _disk_radius: float = 0.9
var _trigger_radius: float = 1.4          # proximity that sets it off
var _blast_radius: float = 3.4            # how far the explosion reaches
var _chain_radius: float = 3.0            # how far it detonates other mines
var _glow_mat: StandardMaterial3D = null
var _pulse: float = 0.0
var _pending: bool = false                # queued to chain-detonate

func _hurt_radius() -> float:
	return _disk_radius

func _ready() -> void:
	max_health = 1.0
	health = 1.0
	_disk_radius = enemy_scale * 0.6
	_trigger_radius = _disk_radius + enemy_scale * 0.7
	_blast_radius = enemy_scale * 3.4
	_chain_radius = enemy_scale * 3.2
	super._ready()
	add_to_group(GROUP_MINE)
	_build_disk()

func configure_chain(chain_radius: float) -> void:
	# The field sets this to just over the formation spacing so a detonation only
	# reaches its immediate neighbours -> the blast ripples along the formation.
	_chain_radius = chain_radius

func _build_disk() -> void:
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = theme.get("walls", Color(0.3, 0.3, 0.34))
	body_mat.metallic = 0.4
	body_mat.roughness = 0.5

	var h: float = _disk_radius * 0.35
	# Disk body, axis rotated from +Y to +Z so the flat faces point along travel.
	var body := CylinderMesh.new()
	body.top_radius = _disk_radius
	body.bottom_radius = _disk_radius
	body.height = h
	var body_mi := MeshInstance3D.new()
	body_mi.mesh = MeshUtil.flat(body)
	body_mi.material_override = body_mat
	body_mi.rotation = Vector3(deg_to_rad(90), 0, 0)
	add_child(body_mi)

	# Glowing centers on both faces, themed to the level accent.
	_glow_mat = StandardMaterial3D.new()
	var glow: Color = accent.lightened(0.25)
	_glow_mat.albedo_color = glow
	_glow_mat.emission_enabled = true
	_glow_mat.emission = glow
	_glow_mat.emission_energy_multiplier = 1.1
	for sign_z in [1.0, -1.0]:
		var eye := CylinderMesh.new()
		eye.top_radius = _disk_radius * 0.4
		eye.bottom_radius = _disk_radius * 0.4
		eye.height = _disk_radius * 0.12
		var eye_mi := MeshInstance3D.new()
		eye_mi.mesh = MeshUtil.flat(eye)
		eye_mi.material_override = _glow_mat
		eye_mi.rotation = Vector3(deg_to_rad(90), 0, 0)
		eye_mi.position = Vector3(0, 0, sign_z * (h * 0.5 + _disk_radius * 0.06))
		add_child(eye_mi)

func _process(delta: float) -> void:
	if not alive:
		return
	# Gentle glow pulse so mines read as "live".
	_pulse += delta * 3.0
	if _glow_mat != null:
		_glow_mat.emission_energy_multiplier = 0.8 + 0.5 * (sin(_pulse) * 0.5 + 0.5)
	# Proximity trigger: the ship gets too close -> it goes off.
	if ship != null and is_instance_valid(ship) and ship.alive:
		if global_position.distance_to(ship.global_position) <= _trigger_radius:
			explode()

# Overrides enemy_base._die: a mine detonates instead of dropping a pickup.
func _die() -> void:
	explode()

func explode() -> void:
	if not alive:
		return
	alive = false
	_spawn_explosion(1.5)
	_blast()
	queue_free()

# Queued detonation from a neighbour's blast, after a short ripple delay.
func chain_detonate(delay: float) -> void:
	if _pending or not alive:
		return
	_pending = true
	await get_tree().create_timer(delay).timeout
	if is_instance_valid(self) and alive:
		explode()

func _blast() -> void:
	var here: Vector3 = global_position
	# The player, if caught in the blast.
	if ship != null and is_instance_valid(ship) and ship.alive and ship.has_method("take_damage"):
		if here.distance_to(ship.global_position) <= _blast_radius:
			ship.take_damage(BLAST_PLAYER_DAMAGE)
	# Nearby mines chain; nearby enemies are destroyed.
	for n in get_tree().get_nodes_in_group(Combat.GROUP_ENEMY_HURTBOX):
		if n == self or not is_instance_valid(n):
			continue
		var d: float = here.distance_to(n.global_position)
		if n.is_in_group(GROUP_MINE):
			if d <= _chain_radius and n.has_method("chain_detonate"):
				n.chain_detonate(CHAIN_DELAY)
		elif d <= _blast_radius and n.has_method("take_hit"):
			n.take_hit(BLAST_ENEMY_DAMAGE)
