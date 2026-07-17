extends Node2D

# Pattern Echo — a pure short-term-memory game. Watch an escalating
# sequence of panel flashes, then repeat it back by tapping in the same
# order. No reflex/timing pressure during the watch phase at all — the
# only game in the studio with that pacing (Loop It and Color Sort are
# untimed-per-move planning puzzles, but neither is a memorize-then-recall
# game).

const NUM_PANELS := 4
const FLASH_DURATION := 0.5
const FLASH_GAP := 0.25
const MAX_STRIKES := 3
const SAVE_PATH := "user://patternecho_highscore.cfg"

const BASE_COLORS := [
	Color(0.5, 0.12, 0.12, 1.0),
	Color(0.12, 0.3, 0.55, 1.0),
	Color(0.55, 0.45, 0.1, 1.0),
	Color(0.15, 0.4, 0.2, 1.0),
]

@onready var panels: Array = [$Panel0, $Panel1, $Panel2, $Panel3]
@onready var score_label: Label = $ScoreLabel
@onready var strikes_label: Label = $StrikesLabel
@onready var status_label: Label = $StatusLabel
@onready var ready_overlay: ColorRect = $ReadyOverlay
@onready var game_over_overlay: ColorRect = $GameOverOverlay
@onready var game_over_score_label: Label = $GameOverOverlay/GameOverScore

var sequence: Array = []
var player_progress: int = 0
var showing_sequence: bool = false
var flashing: bool = false
var show_index: int = 0
var show_timer: float = 0.0

var score: int = 0
var high_score: int = 0
var strikes: int = MAX_STRIKES
var game_over: bool = false
var game_started: bool = false


func _ready() -> void:
	for i in range(NUM_PANELS):
		panels[i].color = BASE_COLORS[i]
	_load_high_score()
	_start_game()


func _lit_color(i: int) -> Color:
	return BASE_COLORS[i].lerp(Color(1, 1, 1, 1), 0.55)


func _start_game() -> void:
	sequence.clear()
	player_progress = 0
	showing_sequence = false
	score = 0
	strikes = MAX_STRIKES
	game_over = false
	game_started = false
	score_label.text = "0"
	_update_strikes_label()
	status_label.text = "WATCH"
	game_over_overlay.visible = false
	ready_overlay.visible = true
	for i in range(NUM_PANELS):
		panels[i].color = BASE_COLORS[i]


func _next_round() -> void:
	sequence.append(randi() % NUM_PANELS)
	player_progress = 0
	_begin_showing_sequence()


func _begin_showing_sequence() -> void:
	showing_sequence = true
	flashing = false
	show_index = 0
	show_timer = FLASH_GAP
	status_label.text = "WATCH"
	for i in range(NUM_PANELS):
		panels[i].color = BASE_COLORS[i]


func _process(delta: float) -> void:
	if not game_started or game_over:
		return

	if showing_sequence:
		show_timer -= delta
		if show_timer <= 0.0:
			if flashing:
				panels[sequence[show_index]].color = BASE_COLORS[sequence[show_index]]
				flashing = false
				show_index += 1
				if show_index >= sequence.size():
					showing_sequence = false
					status_label.text = "YOUR TURN"
				else:
					show_timer = FLASH_GAP
			else:
				panels[sequence[show_index]].color = _lit_color(sequence[show_index])
				flashing = true
				show_timer = FLASH_DURATION


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
		_next_round()
		return
	if game_over:
		_start_game()
		return

	if showing_sequence:
		return

	for i in range(NUM_PANELS):
		if panels[i].get_global_rect().has_point(pos):
			_on_panel_tapped(i)
			return


func _on_panel_tapped(i: int) -> void:
	if i == sequence[player_progress]:
		player_progress += 1
		if player_progress >= sequence.size():
			score = sequence.size()
			score_label.text = str(score)
			_next_round()
	else:
		_on_mistake()


func _on_mistake() -> void:
	strikes -= 1
	_update_strikes_label()
	if strikes <= 0:
		_trigger_game_over()
	else:
		_begin_showing_sequence()


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
