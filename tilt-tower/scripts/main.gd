extends Node2D

# Tilt Tower — the studio's first game built on real physics simulation
# (RigidBody2D) instead of scripted/deterministic logic. Tilt the platform
# (A/D, arrows, or drag) to keep falling blocks balanced; physics handles
# the stacking, sliding, and toppling emergently. Lose 3 blocks off the
# platform and the run ends. Score is seconds survived.

const MAX_TILT := deg_to_rad(35)
const TILT_SPEED := 1.8
const DRAG_SENSITIVITY := 0.006
const SHAPE_MIN_SIZE := 30.0
const SHAPE_MAX_SIZE := 55.0
const SPAWN_INTERVAL_START := 1.7
const SPAWN_INTERVAL_MIN := 0.7
const SPAWN_INTERVAL_DECAY := 0.01
const FALL_Y_THRESHOLD := 1000.0
const MAX_STRIKES := 3
const SPAWN_X_RANGE := 140.0
const SAVE_PATH := "user://tilttower_highscore.cfg"

const SHAPE_PALETTE := [
	Color(0.95, 0.6, 0.25, 1.0),
	Color(0.35, 0.75, 0.55, 1.0),
	Color(0.4, 0.65, 0.95, 1.0),
	Color(0.85, 0.4, 0.75, 1.0),
]

@onready var platform: AnimatableBody2D = $Platform
@onready var shapes_container: Node2D = $ShapesContainer
@onready var score_label: Label = $ScoreLabel
@onready var strikes_label: Label = $StrikesLabel
@onready var ready_overlay: ColorRect = $ReadyOverlay
@onready var game_over_overlay: ColorRect = $GameOverOverlay
@onready var game_over_score_label: Label = $GameOverOverlay/GameOverScore

var tilt: float = 0.0
var strikes: int = MAX_STRIKES
var time_survived: float = 0.0
var score: int = 0
var high_score: int = 0
var game_over: bool = false
var game_started: bool = false
var spawn_timer: float = 0.0
var spawn_interval: float = SPAWN_INTERVAL_START
var shapes: Array = []
var color_cycle: int = 0


func _ready() -> void:
	_load_high_score()
	_start_game()


func _start_game() -> void:
	for s in shapes:
		if is_instance_valid(s):
			s.queue_free()
	shapes.clear()
	tilt = 0.0
	platform.rotation = 0.0
	strikes = MAX_STRIKES
	time_survived = 0.0
	score = 0
	game_over = false
	game_started = false
	spawn_timer = 0.6
	spawn_interval = SPAWN_INTERVAL_START
	score_label.text = "0s"
	_update_strikes_label()
	game_over_overlay.visible = false
	ready_overlay.visible = true


func _physics_process(delta: float) -> void:
	if game_over or not game_started:
		return

	var dir := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir += 1.0
	tilt = clamp(tilt + dir * TILT_SPEED * delta, -MAX_TILT, MAX_TILT)
	platform.rotation = tilt

	time_survived += delta
	score = int(floor(time_survived))
	score_label.text = "%ds" % score

	spawn_timer -= delta
	if spawn_timer <= 0.0:
		_spawn_shape()
		spawn_interval = max(SPAWN_INTERVAL_MIN, spawn_interval - SPAWN_INTERVAL_DECAY)
		spawn_timer = spawn_interval

	var still_tracked: Array = []
	for s in shapes:
		if not is_instance_valid(s):
			continue
		if s.global_position.y > FALL_Y_THRESHOLD:
			s.queue_free()
			_on_shape_lost()
		else:
			still_tracked.append(s)
	shapes = still_tracked


func _spawn_shape() -> void:
	var size := Vector2(randf_range(SHAPE_MIN_SIZE, SHAPE_MAX_SIZE), randf_range(SHAPE_MIN_SIZE, SHAPE_MAX_SIZE))
	var x: float = platform.position.x + randf_range(-SPAWN_X_RANGE, SPAWN_X_RANGE)

	var body := RigidBody2D.new()
	body.position = Vector2(x, 60.0)

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

	var visual := Polygon2D.new()
	var hw: float = size.x / 2.0
	var hh: float = size.y / 2.0
	visual.polygon = PackedVector2Array([Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)])
	visual.color = SHAPE_PALETTE[color_cycle % SHAPE_PALETTE.size()]
	color_cycle += 1
	body.add_child(visual)

	shapes_container.add_child(body)
	shapes.append(body)


func _on_shape_lost() -> void:
	strikes -= 1
	_update_strikes_label()
	if strikes <= 0:
		_trigger_game_over()


func _update_strikes_label() -> void:
	var s := ""
	for i in range(strikes):
		s += "*"
		if i < strikes - 1:
			s += " "
	strikes_label.text = s


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_tap()
	elif event is InputEventScreenTouch and event.pressed:
		_on_tap()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_on_tap()
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and game_started and not game_over:
		tilt = clamp(tilt + event.relative.x * DRAG_SENSITIVITY, -MAX_TILT, MAX_TILT)
	elif event is InputEventScreenDrag and game_started and not game_over:
		tilt = clamp(tilt + event.relative.x * DRAG_SENSITIVITY, -MAX_TILT, MAX_TILT)


func _on_tap() -> void:
	if not game_started:
		game_started = true
		ready_overlay.visible = false
		return
	if game_over:
		_start_game()


func _trigger_game_over() -> void:
	game_over = true
	if score > high_score:
		high_score = score
		_save_high_score()
	game_over_score_label.text = "Survived: %ds  Best: %ds" % [score, high_score]
	game_over_overlay.visible = true


func _load_high_score() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		high_score = int(cfg.get_value("scores", "high_score", 0))


func _save_high_score() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("scores", "high_score", high_score)
	cfg.save(SAVE_PATH)
