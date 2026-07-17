extends Node2D

# Anchor Drop — a physics puzzle built on order-of-operations rather than
# aim or timing. A weight hangs from several ropes; cutting a rope pulls
# the weight toward the average position of whichever ropes remain. The
# puzzle is choosing which ropes to cut, and in what order, so the LAST
# rope left is directly above the target zone — cutting it releases real
# gravity and the weight drops straight down.

const MARGIN := 40.0
const ANCHOR_Y := 140.0
const WEIGHT_START_Y := 220.0
const GROUND_CHECK_Y := 800.0
const GROUND_ZONE_HEIGHT := 100.0
const BUTTON_SIZE := Vector2(60.0, 46.0)
const BASE_ROPE_COUNT := 3
const MAX_ROPE_COUNT := 5
const ROPE_COUNT_GROWTH_INTERVAL := 3
const MAX_STRIKES := 3
const SAVE_PATH := "user://anchordrop_highscore.cfg"

const TARGET_COLOR := Color(0.2, 0.75, 0.4, 1.0)
const HAZARD_COLOR := Color(0.85, 0.2, 0.2, 1.0)
const ROPE_COLOR := Color(0.75, 0.7, 0.6, 1.0)
const BUTTON_COLOR := Color(0.35, 0.37, 0.42, 1.0)

@onready var weight: RigidBody2D = $Weight
@onready var ropes_container: Node2D = $RopesContainer
@onready var buttons_container: Node2D = $ButtonsContainer
@onready var ground_container: Node2D = $GroundContainer
@onready var score_label: Label = $ScoreLabel
@onready var strikes_label: Label = $StrikesLabel
@onready var ready_overlay: ColorRect = $ReadyOverlay
@onready var game_over_overlay: ColorRect = $GameOverOverlay
@onready var game_over_score_label: Label = $GameOverOverlay/GameOverScore

var anchors: Array = []
var rope_cut: Array = []
var rope_lines: Array = []
var cut_buttons: Array = []
var target_index: int = 0
var held: bool = true
var resolved: bool = false

var score: int = 0
var high_score: int = 0
var strikes: int = MAX_STRIKES
var game_over: bool = false
var game_started: bool = false


func _ready() -> void:
	_load_high_score()
	_start_game()


func _start_game() -> void:
	score = 0
	strikes = MAX_STRIKES
	game_over = false
	game_started = false
	score_label.text = "0"
	_update_strikes_label()
	game_over_overlay.visible = false
	ready_overlay.visible = true
	_new_round()


func _rope_count() -> int:
	return clampi(BASE_ROPE_COUNT + score / ROPE_COUNT_GROWTH_INTERVAL, BASE_ROPE_COUNT, MAX_ROPE_COUNT)


func _new_round() -> void:
	for l in rope_lines:
		l.queue_free()
	for b in cut_buttons:
		b.queue_free()
	for c in ground_container.get_children():
		c.queue_free()
	rope_lines.clear()
	cut_buttons.clear()

	var count: int = _rope_count()
	var slot_width: float = (540.0 - 2.0 * MARGIN) / count
	anchors.clear()
	for i in range(count):
		anchors.append(MARGIN + slot_width * (i + 0.5))
	rope_cut = []
	for _i in range(count):
		rope_cut.append(false)

	target_index = randi() % count

	for i in range(count):
		var zone := ColorRect.new()
		zone.size = Vector2(slot_width - 8.0, GROUND_ZONE_HEIGHT)
		zone.position = Vector2(anchors[i] - (slot_width - 8.0) / 2.0, GROUND_CHECK_Y + 20.0)
		zone.color = TARGET_COLOR if i == target_index else HAZARD_COLOR
		ground_container.add_child(zone)

		var line := Line2D.new()
		line.width = 4.0
		line.default_color = ROPE_COLOR
		ropes_container.add_child(line)
		rope_lines.append(line)

		var btn := ColorRect.new()
		btn.size = BUTTON_SIZE
		btn.position = Vector2(anchors[i] - BUTTON_SIZE.x / 2.0, ANCHOR_Y - BUTTON_SIZE.y - 10.0)
		btn.color = BUTTON_COLOR
		buttons_container.add_child(btn)
		cut_buttons.append(btn)

		var lbl := Label.new()
		lbl.text = "CUT"
		lbl.size = BUTTON_SIZE
		lbl.position = btn.position
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95, 1.0))
		buttons_container.add_child(lbl)

	held = true
	resolved = false
	weight.gravity_scale = 0.0
	weight.linear_velocity = Vector2.ZERO
	var avg: float = 0.0
	for a in anchors:
		avg += a
	avg /= anchors.size()
	weight.position = Vector2(avg, WEIGHT_START_Y)
	_update_rope_lines()


func _update_rope_lines() -> void:
	for i in range(anchors.size()):
		if not rope_cut[i]:
			rope_lines[i].points = PackedVector2Array([Vector2(anchors[i], ANCHOR_Y), weight.position])


func _physics_process(delta: float) -> void:
	if game_over or not game_started:
		return

	if held:
		var remaining: Array = []
		for i in range(anchors.size()):
			if not rope_cut[i]:
				remaining.append(anchors[i])
		if not remaining.is_empty():
			var avg: float = 0.0
			for a in remaining:
				avg += a
			avg /= remaining.size()
			weight.position.x = lerp(weight.position.x, avg, clamp(delta * 4.0, 0.0, 1.0))
		_update_rope_lines()
	else:
		if not resolved and weight.position.y >= GROUND_CHECK_Y:
			resolved = true
			_resolve_landing()


func _resolve_landing() -> void:
	var closest_index: int = 0
	var closest_dist: float = abs(weight.position.x - anchors[0])
	for i in range(1, anchors.size()):
		var d: float = abs(weight.position.x - anchors[i])
		if d < closest_dist:
			closest_dist = d
			closest_index = i

	if closest_index == target_index:
		score += 1
		score_label.text = str(score)
		_new_round()
	else:
		_on_hazard_hit()


func _on_hazard_hit() -> void:
	strikes -= 1
	_update_strikes_label()
	if strikes <= 0:
		_trigger_game_over()
	else:
		_new_round()


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
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
		pressed = true
	elif event is InputEventScreenTouch and event.pressed:
		pos = event.position
		pressed = true

	if not pressed:
		return

	if not game_started:
		game_started = true
		ready_overlay.visible = false
		return
	if game_over:
		_start_game()
		return

	for i in range(cut_buttons.size()):
		if cut_buttons[i].get_global_rect().has_point(pos):
			_cut_rope(i)
			return


func _cut_rope(i: int) -> void:
	if rope_cut[i] or not held:
		return
	rope_cut[i] = true
	rope_lines[i].visible = false
	cut_buttons[i].color = Color(0.2, 0.2, 0.22, 1.0)

	var remaining_count := 0
	for c in rope_cut:
		if not c:
			remaining_count += 1

	if remaining_count == 0:
		held = false
		weight.gravity_scale = 1.0


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
