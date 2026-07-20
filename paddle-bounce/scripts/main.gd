extends Node2D

# Paddle Bounce — a Breakout-style brick clearer, the studio's first game
# built around a controlled paddle deflecting a bouncing ball. Distinct
# input grammar (continuous paddle positioning) and distinct objective
# (clear a shrinking field of targets by ricochet) from every other game
# in the studio — Tilt Tower is real emergent RigidBody2D physics letting
# blocks rest/topple; this is a deterministic kinematic bounce, chosen so
# the exact reflection angle off the paddle is precise and testable
# rather than emergent.

const PADDLE_Y := 880.0
const PADDLE_WIDTH := 110.0
const PADDLE_HEIGHT := 22.0
const PADDLE_KEY_SPEED := 480.0
const PADDLE_DRAG_SENSITIVITY := 1.0

const BALL_RADIUS := 10.0
const BASE_BALL_SPEED := 380.0
const BALL_SPEED_GROWTH := 12.0
const MAX_BALL_SPEED := 620.0

const BRICK_COLS := 7
const BASE_BRICK_ROWS := 4
const MAX_BRICK_ROWS := 7
const BRICK_HEIGHT := 30.0
const BRICK_TOP := 140.0
const BRICK_GAP := 6.0
const BRICK_SIDE_MARGIN := 20.0

const MAX_STRIKES := 3
const SAVE_PATH := "user://paddlebounce_highscore.cfg"

const PADDLE_COLOR := Color(0.2, 0.75, 0.95, 1.0)
const BALL_COLOR := Color(0.95, 0.76, 0.15, 1.0)
const BRICK_HUE_STEPS := 6
const BRICK_SATURATION := 0.62
const BRICK_VALUE := 0.85

@onready var bricks_container: Node2D = $BricksContainer
@onready var paddle: ColorRect = $Paddle
@onready var ball: Polygon2D = $Ball
@onready var score_label: Label = $ScoreLabel
@onready var strikes_label: Label = $StrikesLabel
@onready var ready_overlay: ColorRect = $ReadyOverlay
@onready var game_over_overlay: ColorRect = $GameOverOverlay
@onready var game_over_score_label: Label = $GameOverOverlay/GameOverScore

var paddle_x: float = 270.0
var ball_pos: Vector2 = Vector2.ZERO
var ball_vel: Vector2 = Vector2.ZERO
var ball_attached: bool = true
var bricks: Array = []
var round_number: int = 0

var score: int = 0
var high_score: int = 0
var strikes: int = MAX_STRIKES
var game_over: bool = false
var game_started: bool = false


func _ready() -> void:
	ball.polygon = _circle_points(BALL_RADIUS, 16)
	ball.color = BALL_COLOR
	paddle.color = PADDLE_COLOR
	_load_high_score()
	_start_game()


func _circle_points(radius: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a: float = i * TAU / segments
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts


func _start_game() -> void:
	paddle_x = 270.0
	round_number = 0
	score = 0
	strikes = MAX_STRIKES
	game_over = false
	game_started = false
	score_label.text = "0"
	_update_strikes_label()
	game_over_overlay.visible = false
	ready_overlay.visible = true
	_generate_bricks()
	_attach_ball()
	_update_paddle_visual()


func _brick_rows() -> int:
	return clampi(BASE_BRICK_ROWS + round_number, BASE_BRICK_ROWS, MAX_BRICK_ROWS)


func _generate_bricks() -> void:
	for c in bricks_container.get_children():
		c.queue_free()
	bricks.clear()

	var rows: int = _brick_rows()
	var brick_width: float = (540.0 - 2.0 * BRICK_SIDE_MARGIN - (BRICK_COLS - 1) * BRICK_GAP) / float(BRICK_COLS)

	for row in range(rows):
		for col in range(BRICK_COLS):
			var x: float = BRICK_SIDE_MARGIN + col * (brick_width + BRICK_GAP)
			var y: float = BRICK_TOP + row * (BRICK_HEIGHT + BRICK_GAP)
			var rect := Rect2(Vector2(x, y), Vector2(brick_width, BRICK_HEIGHT))

			var node := ColorRect.new()
			node.position = rect.position
			node.size = rect.size
			var hue: float = fmod(float(row) / float(BRICK_HUE_STEPS), 1.0)
			node.color = Color.from_hsv(hue, BRICK_SATURATION, BRICK_VALUE, 1.0)
			bricks_container.add_child(node)

			bricks.append({"rect": rect, "node": node})


func _attach_ball() -> void:
	ball_attached = true
	ball_vel = Vector2.ZERO
	ball_pos = Vector2(paddle_x, PADDLE_Y - PADDLE_HEIGHT / 2.0 - BALL_RADIUS)
	ball.position = ball_pos


func _ball_speed() -> float:
	return min(MAX_BALL_SPEED, BASE_BALL_SPEED + round_number * BALL_SPEED_GROWTH)


func _launch_ball() -> void:
	ball_attached = false
	ball_vel = Vector2(randf_range(-0.35, 0.35), -1.0).normalized() * _ball_speed()


func _update_paddle_visual() -> void:
	paddle.position = Vector2(paddle_x - PADDLE_WIDTH / 2.0, PADDLE_Y - PADDLE_HEIGHT / 2.0)
	paddle.size = Vector2(PADDLE_WIDTH, PADDLE_HEIGHT)


func _reflect_off_paddle(hit_offset: float) -> Vector2:
	# hit_offset is -1 (left edge) .. 1 (right edge) of the paddle. Deflects
	# up to 60 degrees off straight-up based on where the ball landed.
	var clamped: float = clamp(hit_offset, -1.0, 1.0)
	var angle: float = clamped * deg_to_rad(60.0)
	var dir := Vector2(sin(angle), -cos(angle))
	return dir * _ball_speed()


func _find_brick_hit(ball_rect: Rect2) -> int:
	for i in range(bricks.size()):
		if bricks[i]["rect"].intersects(ball_rect):
			return i
	return -1


func _process(delta: float) -> void:
	if game_over or not game_started:
		return

	var dir := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir += 1.0
	paddle_x = clamp(paddle_x + dir * PADDLE_KEY_SPEED * delta, PADDLE_WIDTH / 2.0, 540.0 - PADDLE_WIDTH / 2.0)
	_update_paddle_visual()

	if ball_attached:
		ball_pos = Vector2(paddle_x, PADDLE_Y - PADDLE_HEIGHT / 2.0 - BALL_RADIUS)
		ball.position = ball_pos
		return

	_step_ball(delta)


func _step_ball(delta: float) -> void:
	ball_pos += ball_vel * delta

	if ball_pos.x - BALL_RADIUS < 0.0:
		ball_pos.x = BALL_RADIUS
		ball_vel.x = abs(ball_vel.x)
	elif ball_pos.x + BALL_RADIUS > 540.0:
		ball_pos.x = 540.0 - BALL_RADIUS
		ball_vel.x = -abs(ball_vel.x)

	if ball_pos.y - BALL_RADIUS < 0.0:
		ball_pos.y = BALL_RADIUS
		ball_vel.y = abs(ball_vel.y)

	var paddle_top: float = PADDLE_Y - PADDLE_HEIGHT / 2.0
	if ball_vel.y > 0.0 and ball_pos.y + BALL_RADIUS >= paddle_top and ball_pos.y - BALL_RADIUS <= PADDLE_Y + PADDLE_HEIGHT / 2.0:
		if ball_pos.x >= paddle_x - PADDLE_WIDTH / 2.0 and ball_pos.x <= paddle_x + PADDLE_WIDTH / 2.0:
			var offset: float = (ball_pos.x - paddle_x) / (PADDLE_WIDTH / 2.0)
			ball_vel = _reflect_off_paddle(offset)
			ball_pos.y = paddle_top - BALL_RADIUS

	var ball_rect := Rect2(ball_pos - Vector2(BALL_RADIUS, BALL_RADIUS), Vector2(BALL_RADIUS, BALL_RADIUS) * 2.0)
	var hit_index: int = _find_brick_hit(ball_rect)
	if hit_index != -1:
		_destroy_brick(hit_index)
		ball_vel.y = -ball_vel.y

	ball.position = ball_pos

	if ball_pos.y - BALL_RADIUS > 960.0:
		_on_ball_lost()


func _destroy_brick(index: int) -> void:
	var b: Dictionary = bricks[index]
	if is_instance_valid(b["node"]):
		b["node"].queue_free()
	bricks.remove_at(index)
	score += 1
	score_label.text = str(score)

	if bricks.is_empty():
		round_number += 1
		_generate_bricks()
		_attach_ball()


func _on_ball_lost() -> void:
	strikes -= 1
	_update_strikes_label()
	if strikes <= 0:
		_trigger_game_over()
	else:
		_attach_ball()


func _update_strikes_label() -> void:
	var s := ""
	for i in range(strikes):
		s += "*"
		if i < strikes - 1:
			s += " "
	strikes_label.text = s


func _input(event: InputEvent) -> void:
	var pos: Vector2
	var pressed := false
	var dragging := false

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
		pressed = event.pressed
	elif event is InputEventScreenTouch:
		pos = event.position
		pressed = event.pressed
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		pos = event.position
		dragging = true
	elif event is InputEventScreenDrag:
		pos = event.position
		dragging = true
	else:
		return

	if pressed:
		if not game_started:
			game_started = true
			ready_overlay.visible = false
			return
		if game_over:
			_start_game()
			return
		paddle_x = clamp(pos.x, PADDLE_WIDTH / 2.0, 540.0 - PADDLE_WIDTH / 2.0)
		if ball_attached:
			_launch_ball()
		return

	if dragging:
		if not game_started or game_over:
			return
		paddle_x = clamp(pos.x, PADDLE_WIDTH / 2.0, 540.0 - PADDLE_WIDTH / 2.0)


func _trigger_game_over() -> void:
	game_over = true
	if score > high_score:
		high_score = score
		_save_high_score()
	game_over_score_label.text = "Score: %d  Best: %d" % [score, high_score]
	game_over_overlay.visible = true


func _load_high_score() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		high_score = int(cfg.get_value("scores", "high_score", 0))


func _save_high_score() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("scores", "high_score", high_score)
	cfg.save(SAVE_PATH)
