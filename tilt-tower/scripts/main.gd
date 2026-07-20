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

# Novelty twist: periodic "gust" events add an automatic extra tilt force
# the player has to react to and counter — a hazard/variety event, not a
# bonus pickup, so the platform itself keeps you on your toes over a long
# run instead of only ever getting harder via faster spawns.
const GUST_MIN_INTERVAL := 10.0
const GUST_MAX_INTERVAL := 18.0
const GUST_DURATION := 1.2
const GUST_FORCE := 1.4

# Structural addition: the platform can now translate horizontally, not
# just tilt in place. A single drag gesture drives both axes at once — its
# horizontal component still controls tilt, its vertical component now
# shifts the platform left/right — so the player can physically reposition
# the platform under a falling block instead of only ever rotating to
# slide things toward center. Keyboard gets a second key pair (W/S or
# Up/Down) since A/D and Left/Right are already claimed by tilt.
const PLATFORM_MOVE_SPEED := 220.0
const PLATFORM_DRAG_SENSITIVITY := 0.5
const PLATFORM_X_RANGE := 160.0

# Novel element: Heavy Blocks. A rare falling block is bigger, denser
# (real RigidBody2D mass, not just a bigger sprite), and tinted dark slate
# — real emergent physics variety fitting this game's identity as the
# studio's real-physics sandbox, rather than a scripted rule change.
const HEAVY_CHANCE := 0.15
const HEAVY_SIZE_MIN := 60.0
const HEAVY_SIZE_MAX := 85.0
const HEAVY_MASS := 4.0
const HEAVY_TINT := Color(0.25, 0.25, 0.28, 1.0)
const HEAVY_TINT_MIX := 0.55

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
@onready var gust_label: Label = $GustLabel

var tilt: float = 0.0
var gust_active: bool = false
var gust_timer: float = 0.0
var gust_dir: float = 0.0
var next_gust_timer: float = 0.0
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
var base_platform_x: float = 0.0
var platform_offset_x: float = 0.0


func _ready() -> void:
	base_platform_x = platform.position.x
	_load_high_score()
	_start_game()


func _start_game() -> void:
	for s in shapes:
		if is_instance_valid(s):
			s.queue_free()
	shapes.clear()
	tilt = 0.0
	platform.rotation = 0.0
	platform_offset_x = 0.0
	platform.position.x = base_platform_x
	strikes = MAX_STRIKES
	time_survived = 0.0
	score = 0
	game_over = false
	game_started = false
	spawn_timer = 0.6
	spawn_interval = SPAWN_INTERVAL_START
	gust_active = false
	gust_timer = 0.0
	next_gust_timer = randf_range(GUST_MIN_INTERVAL, GUST_MAX_INTERVAL)
	gust_label.visible = false
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

	var move_dir := 0.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move_dir -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move_dir += 1.0
	platform_offset_x = clamp(platform_offset_x + move_dir * PLATFORM_MOVE_SPEED * delta, -PLATFORM_X_RANGE, PLATFORM_X_RANGE)

	if gust_active:
		gust_timer -= delta
		tilt = clamp(tilt + gust_dir * GUST_FORCE * delta, -MAX_TILT, MAX_TILT)
		if gust_timer <= 0.0:
			gust_active = false
			gust_label.visible = false
	else:
		next_gust_timer -= delta
		if next_gust_timer <= 0.0:
			gust_active = true
			gust_timer = GUST_DURATION
			gust_dir = -1.0 if randf() < 0.5 else 1.0
			gust_label.visible = true
			next_gust_timer = randf_range(GUST_MIN_INTERVAL, GUST_MAX_INTERVAL)

	platform.rotation = tilt
	platform.position.x = base_platform_x + platform_offset_x

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


func _make_shape_body(size: Vector2, is_heavy: bool, base_color: Color) -> RigidBody2D:
	var body := RigidBody2D.new()

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	# Reduces tunneling through the thin platform at higher fall speeds.
	body.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	body.mass = HEAVY_MASS if is_heavy else 1.0
	body.set_meta("is_heavy", is_heavy)

	var visual := Polygon2D.new()
	var hw: float = size.x / 2.0
	var hh: float = size.y / 2.0
	visual.polygon = PackedVector2Array([Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)])
	visual.color = base_color.lerp(HEAVY_TINT, HEAVY_TINT_MIX) if is_heavy else base_color
	body.add_child(visual)

	return body


func _spawn_shape() -> void:
	var is_heavy: bool = randf() < HEAVY_CHANCE
	var size: Vector2
	if is_heavy:
		size = Vector2(randf_range(HEAVY_SIZE_MIN, HEAVY_SIZE_MAX), randf_range(HEAVY_SIZE_MIN, HEAVY_SIZE_MAX))
	else:
		size = Vector2(randf_range(SHAPE_MIN_SIZE, SHAPE_MAX_SIZE), randf_range(SHAPE_MIN_SIZE, SHAPE_MAX_SIZE))
	var x: float = platform.position.x + randf_range(-SPAWN_X_RANGE, SPAWN_X_RANGE)

	var base_color: Color = SHAPE_PALETTE[color_cycle % SHAPE_PALETTE.size()]
	color_cycle += 1
	var body: RigidBody2D = _make_shape_body(size, is_heavy, base_color)
	body.position = Vector2(x, 60.0)

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
		platform_offset_x = clamp(platform_offset_x + event.relative.y * PLATFORM_DRAG_SENSITIVITY, -PLATFORM_X_RANGE, PLATFORM_X_RANGE)
	elif event is InputEventScreenDrag and game_started and not game_over:
		tilt = clamp(tilt + event.relative.x * DRAG_SENSITIVITY, -MAX_TILT, MAX_TILT)
		platform_offset_x = clamp(platform_offset_x + event.relative.y * PLATFORM_DRAG_SENSITIVITY, -PLATFORM_X_RANGE, PLATFORM_X_RANGE)


func _on_tap() -> void:
	if not game_started:
		game_started = true
		ready_overlay.visible = false
		return
	if game_over:
		_start_game()


func _trigger_game_over() -> void:
	game_over = true
	# _physics_process stops tracking/pruning shapes once game_over is true,
	# but the physics engine itself doesn't know that — any blocks still on
	# screen would otherwise keep falling forever in the background. Freeze
	# them in place instead (also reads better than the tower silently
	# vanishing off-screen behind the overlay).
	for s in shapes:
		if is_instance_valid(s):
			s.freeze = true
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
