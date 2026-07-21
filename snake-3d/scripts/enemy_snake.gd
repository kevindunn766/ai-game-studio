class_name EnemySnake extends Node3D

var behavior: String = "stealer"  # "stealer" | "boxer" | "thief" | "hoarder" | "turret_head"
var segments: Array = []
var direction: Vector3 = Vector3.FORWARD
var persistent_power: String = ""  # for "hoarder": "rainbow" | "yellow" | "blue"
var grow_pending: int = 0

var head_material: StandardMaterial3D
var body_material: StandardMaterial3D

var _fire_timer: float = 0.0
const FIRE_INTERVAL := 3.2
# Difficulty scales the turret-head cadence: >1 slows fire (easier), <1 speeds
# it up (harder). Set by GameManager at spawn from its current difficulty dial.
var fire_interval_scale: float = 1.0

# "burrower" (desert): cycles hidden/frozen underground and surfaced/aggressive.
var is_burrowed: bool = false
var _burrow_timer: float = 0.0
const BURROW_DURATION := 4.0
const SURFACE_DURATION := 5.0

# "frost_wisp" (glacier): only re-aims every other tick, sliding straight between.
var _slide_counter: int = 0

# "rock_golem" (mountain): moves every other tick (slow), smashes through obstacles.
var _golem_tick_counter: int = 0


func setup(start_pos: Vector3, behavior_in: String, power_in: String = "", segment_count: int = 3) -> void:
	behavior = behavior_in
	persistent_power = power_in
	if behavior == "turret_head":
		segments = [start_pos]
	else:
		segments = [start_pos]
		for i in range(1, maxi(1, segment_count)):
			segments.append(start_pos - Vector3.FORWARD * i)
	direction = Vector3.FORWARD
	_setup_materials()
	_rebuild_visual()


# One "hit" removes a single tail segment (mirrors the player's own
# _shrink_snake) instead of an instant kill -- longer enemies survive more
# hits. Returns true once the enemy has nothing left and should actually die.
func take_hit() -> bool:
	segments.pop_back()
	if segments.is_empty():
		return true
	_rebuild_visual()
	return false


func _process(delta: float) -> void:
	if persistent_power == "rainbow":
		var hue := fmod(Time.get_ticks_msec() / 1000.0 * 0.6, 1.0)
		var c := Color.from_hsv(hue, 0.85, 1.0, 1.0)
		head_material.albedo_color = c
		head_material.emission = c
		body_material.albedo_color = c
		body_material.emission = c
	if behavior == "turret_head":
		_fire_timer += delta
	if behavior == "burrower":
		_burrow_timer += delta
		var cycle_len := BURROW_DURATION if is_burrowed else SURFACE_DURATION
		if _burrow_timer >= cycle_len:
			_burrow_timer = 0.0
			is_burrowed = not is_burrowed
			visible = not is_burrowed


func consume_fire_ready() -> bool:
	if behavior != "turret_head":
		return false
	if _fire_timer >= FIRE_INTERVAL * fire_interval_scale:
		_fire_timer = 0.0
		return true
	return false


func should_move_this_tick() -> bool:
	if behavior != "rock_golem":
		return true
	_golem_tick_counter += 1
	return _golem_tick_counter % 2 == 0


func should_recompute_direction() -> bool:
	if behavior != "frost_wisp":
		return true
	_slide_counter += 1
	return _slide_counter % 2 == 1


func _setup_materials() -> void:
	var head_color := _behavior_color(true)
	var body_color := _behavior_color(false)

	head_material = StandardMaterial3D.new()
	head_material.albedo_color = head_color
	head_material.emission_enabled = true
	head_material.emission = head_color
	head_material.emission_energy_multiplier = 1.0
	head_material.roughness = 0.3

	body_material = StandardMaterial3D.new()
	body_material.albedo_color = body_color
	body_material.emission_enabled = true
	body_material.emission = body_color
	body_material.emission_energy_multiplier = 0.6
	body_material.roughness = 0.4


func _behavior_color(is_head: bool) -> Color:
	if behavior == "hoarder":
		match persistent_power:
			"rainbow":
				return Color(1.0, 1.0, 1.0, 1.0)
			"yellow":
				return Color(1.0, 0.85, 0.15, 1.0)
			"blue":
				return Color(0.1, 0.55, 1.0, 1.0)
	match behavior:
		"stealer":
			return Color(1.0, 0.55, 0.1, 1.0) if is_head else Color(0.8, 0.4, 0.05, 1.0)
		"boxer":
			return Color(0.7, 0.2, 0.9, 1.0) if is_head else Color(0.5, 0.15, 0.65, 1.0)
		"thief":
			return Color(1.0, 0.2, 0.6, 1.0) if is_head else Color(0.75, 0.1, 0.45, 1.0)
		"turret_head":
			return Color(0.85, 0.15, 0.15, 1.0)
		"speedster":
			return Color(0.2, 1.0, 1.0, 1.0) if is_head else Color(0.1, 0.75, 0.75, 1.0)
		"burrower":
			return Color(0.82, 0.6, 0.3, 1.0) if is_head else Color(0.62, 0.44, 0.2, 1.0)
		"frost_wisp":
			return Color(0.75, 0.92, 1.0, 1.0) if is_head else Color(0.55, 0.78, 0.92, 1.0)
		"rock_golem":
			return Color(0.55, 0.5, 0.45, 1.0) if is_head else Color(0.4, 0.36, 0.32, 1.0)
		"shard_wraith":
			return Color(0.75, 0.3, 0.95, 1.0) if is_head else Color(0.5, 0.15, 0.7, 1.0)
		"magma_serpent":
			return Color(1.0, 0.35, 0.05, 1.0) if is_head else Color(0.75, 0.2, 0.02, 1.0)
		_:
			return Color(0.6, 0.6, 0.6, 1.0)


func _rebuild_visual() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()

	for idx in range(segments.size()):
		var node := Node3D.new()
		node.name = "Seg%d" % idx
		node.position = segments[idx]

		var mesh_node := MeshInstance3D.new()
		mesh_node.name = "Mesh"
		var m := BoxMesh.new()
		var sz := 0.85 if idx == 0 else 0.75
		m.size = Vector3(sz, sz, sz)
		mesh_node.mesh = m
		mesh_node.set_surface_override_material(0, head_material if idx == 0 else body_material)
		node.add_child(mesh_node)
		add_child(node)

		if idx == 0 and behavior == "turret_head":
			var turret := MeshInstance3D.new()
			turret.name = "Turret"
			var tm := BoxMesh.new()
			tm.size = Vector3(0.3, 0.3, 0.3)
			turret.mesh = tm
			var tmat := StandardMaterial3D.new()
			tmat.albedo_color = Color(1.0, 0.15, 0.15, 1.0)
			tmat.emission_enabled = true
			tmat.emission = Color(1.0, 0.1, 0.1)
			tmat.emission_energy_multiplier = 2.5
			turret.material_override = tmat
			turret.position = Vector3(0.0, 0.5, 0.0)
			node.add_child(turret)


func choose_direction(target: Vector3, is_blocked: Callable) -> void:
	var head: Vector3 = segments[0]
	var candidates := [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]
	var opposite := -direction
	var safe_best: Vector3 = direction
	var safe_best_dist := INF
	var any_best: Vector3 = direction
	var any_best_dist := INF
	for d: Vector3 in candidates:
		if d == opposite and segments.size() > 1:
			continue
		var next_pos: Vector3 = head + d
		var dist: float = next_pos.distance_squared_to(target)
		if dist < any_best_dist:
			any_best_dist = dist
			any_best = d
		if dist < safe_best_dist and not (is_blocked.call(next_pos) as bool):
			safe_best_dist = dist
			safe_best = d
	direction = safe_best if safe_best_dist < INF else any_best


func advance() -> void:
	var new_head: Vector3 = segments[0] + direction
	segments.push_front(new_head)
	if grow_pending > 0:
		grow_pending -= 1
	else:
		segments.pop_back()
	_rebuild_visual()
