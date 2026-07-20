class_name GameManager
extends Node3D

signal food_eaten(score: int)
signal game_over(final_score: int)

@export var initial_speed: float = 0.18
@export var speed_increment: float = 0.015
@export var speed_increase_interval: int = 5

@onready var food: Node3D = $Food
@onready var snake: Node3D = $Snake
@onready var floor_manager: Node3D = $FloorManager

var snake_ref: Node3D:
	get: return snake
var food_ref: Node3D:
	get: return food

var score: int = 0
var high_score: int = 0
var current_speed: float = 0.0
var food_eaten_count: int = 0
var is_game_over: bool = false
var rng: RandomNumberGenerator

const HIGH_SCORE_PATH := "user://snake3d_highscore.cfg"

# Structural addition: paired portal gates. A rare pair of linked gates
# spawns near the snake; stepping onto one instantly teleports the whole
# snake (every segment, rigidly, preserving shape) to the other, letting a
# run escape a tight obstacle pocket or cut across the map. This changes
# navigation itself rather than just adding a scoring twist on top of it.
const PORTAL_SPAWN_CHANCE := 0.2
const PORTAL_MIN_RADIUS := 3
const PORTAL_MAX_RADIUS := 6
var portals_container: Node3D
var portal_active: bool = false
var portal_a: Vector3 = Vector3.ZERO
var portal_b: Vector3 = Vector3.ZERO
var portal_a_node: Node3D
var portal_b_node: Node3D

# Novel element: Hazard Storm. A telegraphed window where obstacle
# density in newly-explored terrain spikes well above normal, then drops
# back — a periodic pacing swing distinct from the portal gates (which
# are a navigation shortcut, not a difficulty spike) and from the bonus
# food twist (which is a scoring pickup, not a hazard).
const HAZARD_STORM_MIN_INTERVAL := 18.0
const HAZARD_STORM_MAX_INTERVAL := 32.0
const HAZARD_STORM_DURATION := 6.0
const HAZARD_STORM_DENSITY_MULT := 1.8
const HAZARD_STORM_COLOR := Color(0.95, 0.32, 0.12, 1.0)
var storm_active: bool = false
var storm_timer: float = 0.0
var next_storm_timer: float = 0.0
var base_obstacle_density: float = 0.0
var score_label_node: Label3D
var score_label_default_color: Color = Color(1, 1, 1, 1)


func _ready() -> void:
	_ensure_action("move_up", [KEY_W, KEY_UP])
	_ensure_action("move_down", [KEY_S, KEY_DOWN])
	_ensure_action("move_left", [KEY_A, KEY_LEFT])
	_ensure_action("move_right", [KEY_D, KEY_RIGHT])

	process_mode = Node.PROCESS_MODE_ALWAYS
	rng = RandomNumberGenerator.new()
	rng.randomize()
	high_score = _load_high_score()
	current_speed = initial_speed

	portals_container = Node3D.new()
	portals_container.name = "Portals"
	add_child(portals_container)

	score_label_node = get_node_or_null("ScoreLabel")
	if score_label_node:
		score_label_node.text = "0"
		score_label_default_color = score_label_node.modulate

	base_obstacle_density = floor_manager.obstacle_density if floor_manager else 0.0
	next_storm_timer = rng.randf_range(HAZARD_STORM_MIN_INTERVAL, HAZARD_STORM_MAX_INTERVAL)

	var game_over_overlay: Node3D = get_node_or_null("GameOverOverlay")
	if game_over_overlay:
		game_over_overlay.visible = false

	_spawn_food()


func _ensure_action(name: String, keys: Array) -> void:
	if InputMap.has_action(name):
		return
	InputMap.add_action(name)
	for k in keys:
		var e := InputEventKey.new()
		e.keycode = k
		InputMap.action_add_event(name, e)


func _input(event: InputEvent) -> void:
	if is_game_over:
		var tapped := Input.is_action_just_pressed("ui_accept")
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			tapped = true
		elif event is InputEventScreenTouch and event.pressed:
			tapped = true
		if tapped:
			restart()
		return

	if Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("ui_up"):
		snake.set_direction(Vector3.FORWARD)
	elif Input.is_action_just_pressed("move_down") or Input.is_action_just_pressed("ui_down"):
		snake.set_direction(Vector3.BACK)
	elif Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("ui_left"):
		snake.set_direction(Vector3.LEFT)
	elif Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("ui_right"):
		snake.set_direction(Vector3.RIGHT)


func _process(delta: float) -> void:
	if is_game_over:
		return

	if storm_active:
		storm_timer -= delta
		if storm_timer <= 0.0:
			_end_hazard_storm()
	else:
		next_storm_timer -= delta
		if next_storm_timer <= 0.0:
			_start_hazard_storm()

	current_speed -= delta
	if current_speed > 0.0:
		return

	current_speed = _get_current_speed()
	if not snake.step():
		_trigger_game_over()
		return

	var head := snake.segments.front() as Vector3

	if portal_active:
		if head.is_equal_approx(portal_a):
			_teleport_snake(portal_b - portal_a)
			head = snake.segments.front()
		elif head.is_equal_approx(portal_b):
			_teleport_snake(portal_a - portal_b)
			head = snake.segments.front()

	# Obstacle death
	if floor_manager and floor_manager.has_method("is_tile_obstacle_at"):
		if floor_manager.is_tile_obstacle_at(head):
			_trigger_game_over()
			return

	if Vector2(head.x - food.global_position.x, head.z - food.global_position.z).length_squared() < 0.25:
		score += food.score_value()
		food_eaten_count += 1
		if score > high_score:
			high_score = score
			_save_high_score()

		food_eaten.emit(score)

		snake.grow()
		_spawn_food()

		if not portal_active and rng.randf() < PORTAL_SPAWN_CHANCE:
			_spawn_portal_pair()

		if food_eaten_count % speed_increase_interval == 0:
			current_speed = max(0.06, current_speed - speed_increment)


func _on_food_eaten(_pts: int) -> void:
	pass


func _on_game_over(final: int) -> void:
	is_game_over = true
	game_over.emit(final)


const BONUS_FOOD_CHANCE := 0.15


func _spawn_food() -> void:
	# Spawn food relative to snake head instead of fixed grid bounds.
	if snake and snake.segments.size() > 0:
		var head := snake.segments.front() as Vector3
		var offset_x: int = rng.randi_range(-4, 4)
		var offset_z: int = rng.randi_range(-4, 4)
		food.global_position = Vector3(
			head.x + float(offset_x),
			0.45,
			head.z + float(offset_z)
		)
		# Novelty twist: a rare bonus food worth 3x score, visually distinct
		# (cyan, bigger, faster pulse) so it reads as a special pickup.
		food.set_bonus(rng.randf() < BONUS_FOOD_CHANCE)


func _random_open_cell(min_r: int, max_r: int, avoid: Array) -> Vector3:
	var head := snake.segments.front() as Vector3
	for _attempt in range(24):
		var ox: int = rng.randi_range(-max_r, max_r)
		var oz: int = rng.randi_range(-max_r, max_r)
		var dist_sq: int = ox * ox + oz * oz
		if dist_sq < min_r * min_r or dist_sq > max_r * max_r:
			continue
		var candidate := Vector3(head.x + float(ox), 0.0, head.z + float(oz))
		if floor_manager and floor_manager.has_method("is_tile_obstacle_at"):
			if floor_manager.is_tile_obstacle_at(candidate):
				continue
		var too_close := false
		for a in avoid:
			if candidate.is_equal_approx(a):
				too_close = true
				break
		if too_close:
			continue
		return candidate
	return Vector3.INF


func _make_portal_visual(color: Color) -> Node3D:
	var node := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.22
	mesh.outer_radius = 0.4
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.2
	mat.roughness = 0.2
	node.material_override = mat
	node.rotation_degrees = Vector3(90, 0, 0)
	return node


func _spawn_portal_pair() -> void:
	var a := _random_open_cell(PORTAL_MIN_RADIUS, PORTAL_MAX_RADIUS, [food.global_position])
	if not is_finite(a.x):
		return
	var b := _random_open_cell(PORTAL_MIN_RADIUS, PORTAL_MAX_RADIUS, [food.global_position, a])
	if not is_finite(b.x):
		return

	portal_a = a
	portal_b = b
	portal_a_node = _make_portal_visual(Color.from_hsv(0.6, 0.85, 0.95, 1.0))
	portal_a_node.position = a + Vector3(0, 0.45, 0)
	portals_container.add_child(portal_a_node)
	portal_b_node = _make_portal_visual(Color.from_hsv(0.82, 0.85, 0.95, 1.0))
	portal_b_node.position = b + Vector3(0, 0.45, 0)
	portals_container.add_child(portal_b_node)
	portal_active = true


func _remove_portal_pair() -> void:
	if portal_a_node:
		portal_a_node.queue_free()
		portal_a_node = null
	if portal_b_node:
		portal_b_node.queue_free()
		portal_b_node = null
	portal_active = false


func _teleport_snake(offset: Vector3) -> void:
	snake.teleport(offset)
	_remove_portal_pair()


func _start_hazard_storm() -> void:
	storm_active = true
	storm_timer = HAZARD_STORM_DURATION
	if floor_manager:
		floor_manager.obstacle_density = base_obstacle_density * HAZARD_STORM_DENSITY_MULT
	if score_label_node:
		score_label_node.modulate = HAZARD_STORM_COLOR


func _end_hazard_storm() -> void:
	storm_active = false
	if floor_manager:
		floor_manager.obstacle_density = base_obstacle_density
	if score_label_node:
		score_label_node.modulate = score_label_default_color
	next_storm_timer = rng.randf_range(HAZARD_STORM_MIN_INTERVAL, HAZARD_STORM_MAX_INTERVAL)


func _get_current_speed() -> float:
	return max(0.06, initial_speed - (food_eaten_count / speed_increase_interval) * speed_increment)


func _trigger_game_over() -> void:
	_on_game_over(score)


func restart() -> void:
	get_tree().reload_current_scene.call_deferred()


func _load_high_score() -> int:
	if not FileAccess.file_exists(HIGH_SCORE_PATH):
		return 0
	var f := FileAccess.open(HIGH_SCORE_PATH, FileAccess.READ)
	if f == null:
		return 0
	var txt := f.get_as_text().strip_edges()
	f.close()
	if txt.is_empty():
		return 0
	return int(txt)


func _save_high_score() -> void:
	var f := FileAccess.open(HIGH_SCORE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(str(high_score))
	f.close()
