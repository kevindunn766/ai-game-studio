extends Node2D

# Target Throw — a Knife Hit-style precision game. The target spins on its
# own (the player never controls its rotation, unlike Spiral Drop where
# the player rotates the tower); tap to throw a knife straight up into it.
# Hit an empty spot = it sticks and rotates along with the target from
# then on. Hit a knife you already stuck = game over.

const TARGET_RADIUS := 130.0
const ANGLE_TOLERANCE := 0.32
const KNIVES_PER_ROUND := 6
const BASE_ROTATION_SPEED := 1.1
const ROTATION_SPEED_GROWTH := 0.12
const SAVE_PATH := "user://targetthrow_highscore.cfg"

const TARGET_COLOR := Color(0.4, 0.3, 0.22, 1.0)
const KNIFE_COLOR := Color(0.8, 0.82, 0.86, 1.0)

@onready var target: Node2D = $Target
@onready var target_circle: Polygon2D = $Target/TargetCircle
@onready var score_label: Label = $ScoreLabel
@onready var ready_overlay: ColorRect = $ReadyOverlay
@onready var game_over_overlay: ColorRect = $GameOverOverlay
@onready var game_over_score_label: Label = $GameOverOverlay/GameOverScore

var knives: Array = []
var knives_this_round: int = 0
var round_number: int = 0
var rotation_speed: float = BASE_ROTATION_SPEED

var score: int = 0
var high_score: int = 0
var game_over: bool = false
var game_started: bool = false


func _ready() -> void:
	target_circle.polygon = _circle_points(TARGET_RADIUS, 32)
	target_circle.color = TARGET_COLOR
	_load_high_score()
	_start_game()


func _circle_points(radius: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a: float = i * TAU / segments
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts


func _start_game() -> void:
	for k in knives:
		if is_instance_valid(k):
			k.queue_free()
	knives.clear()
	knives_this_round = 0
	round_number = 0
	rotation_speed = BASE_ROTATION_SPEED
	target.rotation = 0.0
	score = 0
	game_over = false
	game_started = false
	score_label.text = "0"
	game_over_overlay.visible = false
	ready_overlay.visible = true


func _process(delta: float) -> void:
	if game_over or not game_started:
		return
	target.rotation += rotation_speed * delta


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

	_throw_knife()


func _throw_knife() -> void:
	# The contact point (directly above the target's center, where the
	# thrown knife always lands) is fixed in world space. Converting it to
	# the target's local space via to_local() — rather than hand-deriving
	# the rotation math — means Godot's own transform system guarantees the
	# angle is correct regardless of which way rotation.y composes, instead
	# of risking the same kind of sign error Spiral Drop had.
	var contact_world: Vector2 = target.position + Vector2(0, -TARGET_RADIUS)
	var local_contact: Vector2 = target.to_local(contact_world)
	var new_angle: float = local_contact.angle()

	for k in knives:
		var existing_angle: float = k.position.angle()
		var diff: float = wrapf(new_angle - existing_angle, -PI, PI)
		if abs(diff) < ANGLE_TOLERANCE:
			_trigger_game_over()
			return

	var knife := Polygon2D.new()
	knife.position = local_contact.normalized() * (TARGET_RADIUS - 6.0)
	knife.rotation = new_angle + PI / 2.0
	knife.color = KNIFE_COLOR
	knife.polygon = PackedVector2Array([Vector2(0, -23), Vector2(-6, 7), Vector2(6, 7)])
	target.add_child(knife)
	knives.append(knife)

	score += 1
	score_label.text = str(score)
	knives_this_round += 1
	if knives_this_round >= KNIVES_PER_ROUND:
		_advance_round()


func _advance_round() -> void:
	for k in knives:
		k.queue_free()
	knives.clear()
	knives_this_round = 0
	round_number += 1
	rotation_speed = BASE_ROTATION_SPEED + round_number * ROTATION_SPEED_GROWTH


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
