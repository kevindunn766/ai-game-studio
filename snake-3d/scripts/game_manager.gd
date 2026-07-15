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

	var score_label: Label3D = get_node_or_null("ScoreLabel")
	if score_label:
		score_label.text = "0"

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

	current_speed -= delta
	if current_speed > 0.0:
		return

	current_speed = _get_current_speed()
	if not snake.step():
		_trigger_game_over()
		return

	var head := snake.segments.front() as Vector3

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
