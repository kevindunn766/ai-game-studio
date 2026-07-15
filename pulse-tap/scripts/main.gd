extends Node2D

# Pulse Tap — a sound-free rhythm game. A ring shrinks continuously from the
# edge of the screen toward a fixed target ring at the center; tap the
# instant the two align. Tapping early/late, or letting the ring pass
# through without tapping at all, costs a strike. No other game in the
# studio is built around "wait for the right moment in a repeating cycle."

const TARGET_RADIUS := 110.0
const PULSE_START_RADIUS := 340.0
const TOLERANCE := 16.0
const BASE_SHRINK_SPEED := 140.0
const SHRINK_SPEED_GROWTH := 6.0
const MAX_SHRINK_SPEED := 420.0
const MAX_STRIKES := 3
const SAVE_PATH := "user://pulsetap_highscore.cfg"
const CIRCLE_SEGMENTS := 40

# Novelty twist: an occasional "double" cycle tints the target ring a
# distinct magenta and is worth 2x score if hit — a bonus-round mechanism
# (the whole cycle is marked, not a separate object), distinct from the
# studio's more common pickup-object bonuses.
const DOUBLE_CYCLE_CHANCE := 0.2
const DOUBLE_CYCLE_COLOR := Color(0.9, 0.25, 0.75, 1.0)
const NORMAL_TARGET_COLOR := Color(0.93, 0.76, 0.15, 1.0)

@onready var target_ring: Line2D = $TargetRing
@onready var pulse_ring: Line2D = $PulseRing
@onready var score_label: Label = $ScoreLabel
@onready var strikes_label: Label = $StrikesLabel
@onready var miss_flash_label: Label = $MissFlashLabel
@onready var ready_overlay: ColorRect = $ReadyOverlay
@onready var game_over_overlay: ColorRect = $GameOverOverlay
@onready var game_over_score_label: Label = $GameOverOverlay/GameOverScore

var pulse_radius: float = PULSE_START_RADIUS
var shrink_speed: float = BASE_SHRINK_SPEED
var resolved_this_cycle: bool = false
var is_double_cycle: bool = false
var miss_flash_timer: float = 0.0

var score: int = 0
var high_score: int = 0
var strikes: int = MAX_STRIKES
var game_over: bool = false
var game_started: bool = false


func _ready() -> void:
	target_ring.points = _circle_points(TARGET_RADIUS)
	_load_high_score()
	_start_game()


func _circle_points(radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(CIRCLE_SEGMENTS):
		var a: float = i * TAU / CIRCLE_SEGMENTS
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts


func _start_game() -> void:
	shrink_speed = BASE_SHRINK_SPEED
	score = 0
	strikes = MAX_STRIKES
	game_over = false
	game_started = false
	score_label.text = "0"
	_update_strikes_label()
	miss_flash_label.visible = false
	game_over_overlay.visible = false
	ready_overlay.visible = true
	_start_new_cycle()


func _start_new_cycle() -> void:
	pulse_radius = PULSE_START_RADIUS
	resolved_this_cycle = false
	is_double_cycle = randf() < DOUBLE_CYCLE_CHANCE
	target_ring.default_color = DOUBLE_CYCLE_COLOR if is_double_cycle else NORMAL_TARGET_COLOR
	pulse_ring.points = _circle_points(pulse_radius)


func _process(delta: float) -> void:
	if miss_flash_timer > 0.0:
		miss_flash_timer -= delta
		if miss_flash_timer <= 0.0:
			miss_flash_label.visible = false

	if game_over or not game_started:
		return

	pulse_radius -= shrink_speed * delta
	pulse_ring.points = _circle_points(max(pulse_radius, 0.0))

	if pulse_radius <= 0.0:
		if not resolved_this_cycle:
			_register_miss("MISS!")
		_start_new_cycle()


func _input(event: InputEvent) -> void:
	var tapped := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped = true
	elif event is InputEventScreenTouch and event.pressed:
		tapped = true
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		tapped = true

	if not tapped:
		return

	if not game_started:
		game_started = true
		ready_overlay.visible = false
		return
	if game_over:
		_start_game()
		return

	_on_tap_action()


func _on_tap_action() -> void:
	if resolved_this_cycle:
		return

	if abs(pulse_radius - TARGET_RADIUS) <= TOLERANCE:
		score += 2 if is_double_cycle else 1
		score_label.text = str(score)
		shrink_speed = min(MAX_SHRINK_SPEED, BASE_SHRINK_SPEED + score * SHRINK_SPEED_GROWTH)
		_start_new_cycle()
	else:
		resolved_this_cycle = true
		_register_miss("MISS!")


func _register_miss(reason: String) -> void:
	strikes -= 1
	_update_strikes_label()
	miss_flash_label.text = reason
	miss_flash_label.visible = true
	miss_flash_timer = 0.9
	if strikes <= 0:
		_trigger_game_over()


func _update_strikes_label() -> void:
	var s := ""
	for i in range(strikes):
		s += "*"
		if i < strikes - 1:
			s += " "
	strikes_label.text = s


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
