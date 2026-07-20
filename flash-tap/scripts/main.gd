extends Node2D

# Flash Tap — a pure reflex reaction game. One panel in a 3x3 grid lights
# up at a time; tap it before it fades. Tapping any dark panel while one
# is lit costs a strike, and letting the lit one fade untapped also costs
# a strike. Speed ramps up with score. No memory or planning involved at
# all — the only game in the studio built around raw single-target reflex
# speed (Pulse Tap is timing-a-ring, Target Throw is aim/power).

const GRID_SIZE := 3
const NUM_PANELS := GRID_SIZE * GRID_SIZE
const PANEL_SIZE := 120.0
const PANEL_GAP := 30.0
const GRID_TOP := 320.0
const BASE_LIGHT_DURATION := 1.0
const MIN_LIGHT_DURATION := 0.35
const LIGHT_DURATION_STEP := 0.03
const GAP_DURATION := 0.35
const MAX_STRIKES := 3
const SAVE_PATH := "user://flashtap_highscore.cfg"

const DARK_COLOR := Color(0.28, 0.29, 0.34, 1.0)
const LIT_COLOR := Color(0.95, 0.76, 0.15, 1.0)

# Novel element: Decoy Panel. Sometimes a second panel lights up (a dim
# violet, clearly distinct from the bright gold true target) at the same
# time — tapping it is a mistake, same as tapping any other dark panel.
# No new scoring/strike logic needed: the existing "tapped panel isn't
# lit_index" branch already treats it as a wrong tap. Purely a
# discrimination challenge layered on the existing reflex mechanic.
const DECOY_CHANCE := 0.2
const DECOY_COLOR := Color(0.75, 0.35, 0.85, 1.0)
var decoy_index: int = -1

@onready var panels_container: Node2D = $PanelsContainer
@onready var score_label: Label = $ScoreLabel
@onready var strikes_label: Label = $StrikesLabel
@onready var ready_overlay: ColorRect = $ReadyOverlay
@onready var game_over_overlay: ColorRect = $GameOverOverlay
@onready var game_over_score_label: Label = $GameOverOverlay/GameOverScore

var panels: Array = []
var lit_index: int = -1
var state: String = "gap"
var state_timer: float = 0.0

var score: int = 0
var high_score: int = 0
var strikes: int = MAX_STRIKES
var game_over: bool = false
var game_started: bool = false


func _ready() -> void:
	var grid_width: float = GRID_SIZE * PANEL_SIZE + (GRID_SIZE - 1) * PANEL_GAP
	var left: float = (540.0 - grid_width) / 2.0
	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			var p := ColorRect.new()
			p.size = Vector2(PANEL_SIZE, PANEL_SIZE)
			p.position = Vector2(left + col * (PANEL_SIZE + PANEL_GAP), GRID_TOP + row * (PANEL_SIZE + PANEL_GAP))
			p.color = DARK_COLOR
			panels_container.add_child(p)
			panels.append(p)
	_load_high_score()
	_start_game()


func _light_duration() -> float:
	return clampf(BASE_LIGHT_DURATION - score * LIGHT_DURATION_STEP, MIN_LIGHT_DURATION, BASE_LIGHT_DURATION)


func _start_game() -> void:
	score = 0
	strikes = MAX_STRIKES
	game_over = false
	game_started = false
	score_label.text = "0"
	_update_strikes_label()
	game_over_overlay.visible = false
	ready_overlay.visible = true
	for p in panels:
		p.color = DARK_COLOR
	lit_index = -1
	decoy_index = -1
	state = "gap"
	state_timer = GAP_DURATION


func _process(delta: float) -> void:
	if not game_started or game_over:
		return

	state_timer -= delta
	if state_timer <= 0.0:
		if state == "gap":
			_light_random_panel()
		else:
			_on_miss()


func _light_random_panel() -> void:
	lit_index = randi() % NUM_PANELS
	panels[lit_index].color = LIT_COLOR
	state = "lit"
	state_timer = _light_duration()

	decoy_index = -1
	if NUM_PANELS > 1 and randf() < DECOY_CHANCE:
		var candidates: Array = []
		for i in range(NUM_PANELS):
			if i != lit_index:
				candidates.append(i)
		decoy_index = candidates[randi() % candidates.size()]
		panels[decoy_index].color = DECOY_COLOR


func _clear_lit_panel() -> void:
	if lit_index >= 0:
		panels[lit_index].color = DARK_COLOR
	if decoy_index >= 0:
		panels[decoy_index].color = DARK_COLOR
	lit_index = -1
	decoy_index = -1
	state = "gap"
	state_timer = GAP_DURATION


func _on_miss() -> void:
	_clear_lit_panel()
	_apply_strike()


func _apply_strike() -> void:
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

	for i in range(panels.size()):
		if panels[i].get_global_rect().has_point(pos):
			_on_panel_tapped(i)
			return


func _on_panel_tapped(i: int) -> void:
	if state == "lit" and i == lit_index:
		score += 1
		score_label.text = str(score)
		_clear_lit_panel()
	elif state == "lit" and i != lit_index:
		_apply_strike()
	# Tapping during the gap phase (nothing lit) is ignored — no penalty.


func _trigger_game_over() -> void:
	game_over = true
	_clear_lit_panel()
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
