extends Node2D

# Chroma Mix — a color-theory puzzle grown directly out of the studio's
# color-systems research. Tap 1-3 primary paints (Red/Yellow/Blue) to mix
# them, then hit MIX to match the target swatch. Follows the classic
# Itten/RYB pigment wheel: primary pairs make the secondaries, and all
# three together make a neutral brown (real pigment-mixing lore, not an
# arbitrary color pick). Three wrong mixes end the run.

const RED := Color(0.86, 0.18, 0.18, 1.0)
const YELLOW := Color(0.95, 0.82, 0.15, 1.0)
const BLUE := Color(0.16, 0.42, 0.82, 1.0)
const ORANGE := Color(0.85, 0.45, 0.12, 1.0)
const GREEN := Color(0.2, 0.55, 0.28, 1.0)
const PURPLE := Color(0.5, 0.22, 0.65, 1.0)
const BROWN := Color(0.42, 0.3, 0.18, 1.0)
const EMPTY_MIX := Color(0.85, 0.85, 0.85, 1.0)

const ALL_KEYS := ["0", "1", "2", "01", "12", "02", "012"]

const BASE_TIME := 3.2
const MIN_TIME := 1.4
const TIME_DECAY := 0.06
const MAX_STRIKES := 3
const TIMER_BAR_MAX_WIDTH := 500.0
const SAVE_PATH := "user://chromamix_highscore.cfg"

# Novelty twist: a rare wildcard round shows up regardless of the selected
# paints — tapping MIX while it's active is an automatic free pass. A
# resource/escape-hatch mechanism, distinct from the studio's more common
# "bonus points" pickups.
const WILDCARD_CHANCE := 0.15

@onready var source_nodes: Array = [$Source0, $Source1, $Source2]
@onready var source_borders: Array = [$Source0Border, $Source1Border, $Source2Border]
@onready var mix_button: ColorRect = $MixButton
@onready var mix_well: ColorRect = $MixWell
@onready var target_swatch: ColorRect = $TargetSwatch
@onready var target_label: Label = $TargetLabel
@onready var score_label: Label = $ScoreLabel
@onready var strikes_label: Label = $StrikesLabel
@onready var timer_bar_fill: ColorRect = $TimerBarFill
@onready var ready_overlay: ColorRect = $ReadyOverlay
@onready var game_over_overlay: ColorRect = $GameOverOverlay
@onready var game_over_score_label: Label = $GameOverOverlay/GameOverScore
@onready var miss_flash_label: Label = $MissFlashLabel
@onready var wildcard_label: Label = $WildcardLabel

var selected: Array = [false, false, false]
var target_key: String = "0"
var wildcard_available: bool = false
var score: int = 0
var high_score: int = 0
var strikes: int = MAX_STRIKES
var time_limit: float = BASE_TIME
var time_left: float = BASE_TIME
var game_over: bool = false
var game_started: bool = false
var miss_flash_timer: float = 0.0


func _ready() -> void:
	_load_high_score()
	_start_game()


func _start_game() -> void:
	score = 0
	strikes = MAX_STRIKES
	game_over = false
	game_started = false
	score_label.text = "Score: 0"
	_update_strikes_label()
	wildcard_available = false
	wildcard_label.visible = false
	game_over_overlay.visible = false
	ready_overlay.visible = true
	_new_round()


func _new_round() -> void:
	target_key = ALL_KEYS[randi() % ALL_KEYS.size()]
	var result: Dictionary = _mix_result(target_key)
	target_swatch.color = result["color"]
	target_label.text = "Match: %s" % result["name"]
	wildcard_available = randf() < WILDCARD_CHANCE
	wildcard_label.visible = wildcard_available
	selected = [false, false, false]
	_update_source_borders()
	mix_well.color = EMPTY_MIX
	time_limit = max(MIN_TIME, BASE_TIME - score * TIME_DECAY)
	time_left = time_limit


func _mix_result(key: String) -> Dictionary:
	match key:
		"0":
			return {"color": RED, "name": "RED"}
		"1":
			return {"color": YELLOW, "name": "YELLOW"}
		"2":
			return {"color": BLUE, "name": "BLUE"}
		"01":
			return {"color": ORANGE, "name": "ORANGE"}
		"12":
			return {"color": GREEN, "name": "GREEN"}
		"02":
			return {"color": PURPLE, "name": "PURPLE"}
		"012":
			return {"color": BROWN, "name": "BROWN"}
		_:
			return {"color": EMPTY_MIX, "name": ""}


func _selection_key() -> String:
	var s := ""
	for i in range(3):
		if selected[i]:
			s += str(i)
	return s


func _process(delta: float) -> void:
	if miss_flash_timer > 0.0:
		miss_flash_timer -= delta
		if miss_flash_timer <= 0.0:
			miss_flash_label.visible = false

	if game_over or not game_started:
		return
	time_left -= delta
	var ratio: float = clamp(time_left / time_limit, 0.0, 1.0)
	timer_bar_fill.size.x = TIMER_BAR_MAX_WIDTH * ratio
	if time_left <= 0.0:
		_on_miss("TOO SLOW!")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event.keycode)
		return

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

	for i in range(3):
		if source_nodes[i].get_global_rect().has_point(pos):
			_toggle_source(i)
			return
	if mix_button.get_global_rect().has_point(pos):
		_submit()


func _handle_key(keycode: int) -> void:
	if not game_started:
		game_started = true
		ready_overlay.visible = false
		return
	if game_over:
		_start_game()
		return
	if keycode == KEY_1:
		_toggle_source(0)
	elif keycode == KEY_2:
		_toggle_source(1)
	elif keycode == KEY_3:
		_toggle_source(2)
	elif keycode == KEY_ENTER or keycode == KEY_SPACE or keycode == KEY_KP_ENTER:
		_submit()


func _toggle_source(i: int) -> void:
	selected[i] = not selected[i]
	_update_source_borders()
	var key: String = _selection_key()
	mix_well.color = _mix_result(key)["color"] if key != "" else EMPTY_MIX


func _update_source_borders() -> void:
	for i in range(3):
		source_borders[i].visible = selected[i]


func _submit() -> void:
	if wildcard_available:
		wildcard_available = false
		wildcard_label.visible = false
		score += 1
		score_label.text = "Score: %d" % score
		_new_round()
		return

	var key: String = _selection_key()
	if key == "":
		return
	if key == target_key:
		score += 1
		score_label.text = "Score: %d" % score
		_new_round()
	else:
		_on_miss("WRONG MIX!")


func _on_miss(reason: String) -> void:
	strikes -= 1
	_update_strikes_label()
	miss_flash_label.text = reason
	miss_flash_label.visible = true
	miss_flash_timer = 0.9
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
