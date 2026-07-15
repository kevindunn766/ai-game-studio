extends Node2D

# Chop Chain — tap left or right to chop the trunk from that side. If the
# bottom segment has a branch on the side you tap, it hits you. Otherwise
# you chop it away and move to that side. A shrinking timer forces you to
# keep tapping. Golden segments (no branch) are a bonus: they refill a
# chunk of your timer and are worth extra score, rewarding a clean run.

const NONE := 0
const LEFT := 1
const RIGHT := 2

const CENTER_X := 270.0
const TRUNK_WIDTH := 220.0
const SEGMENT_HEIGHT := 90.0
const CHOP_LINE_Y := 800.0
const BRANCH_LEN := 150.0
const PLAYER_SIZE := Vector2(70.0, 90.0)
const PLAYER_OFFSET_X := 130.0

const NUM_VISIBLE := 8
const GENERATE_BATCH := 10
const LOW_WATER := 4

const BASE_TIME_LIMIT := 1.6
const MIN_TIME_LIMIT := 0.55
const TIME_DECAY := 0.03

const GOLD_CHANCE := 0.18
const GOLD_BONUS_SCORE := 2
const GOLD_BONUS_TIME := 0.45

const TIMER_BAR_MAX_WIDTH := 500.0
const SAVE_PATH := "user://chopchain_highscore.cfg"

# Studio Palette v1 (see COLOR_SYSTEM.md). Trunk stays a low-chroma neutral
# earth tone (it's not a signal, it's scenery). The branch is the hazard, so
# it gets the danger family (warm red-orange) instead of green — green
# reads as "safe" and was fighting the player's split-second read. The
# player token is magenta, the one hue not already used by trunk (brown),
# branch (red-orange), ground (green), or sky (blue), so it never blends in.
# Golden segments reuse the reward-accent gold used elsewhere in the studio.
const TRUNK_COLORS := [Color(0.45, 0.3, 0.18, 1.0), Color(0.52, 0.36, 0.21, 1.0)]
const BRANCH_COLOR := Color(0.95, 0.32, 0.12, 1.0)
const PLAYER_COLOR := Color(0.86, 0.24, 0.62, 1.0)
const GOLD_COLOR := Color(0.93, 0.76, 0.15, 1.0)

@onready var trunk_container: Node2D = $TrunkContainer
@onready var score_label: Label = $ScoreLabel
@onready var timer_bar_fill: ColorRect = $TimerBarFill
@onready var game_over_overlay: ColorRect = $GameOverOverlay
@onready var game_over_score_label: Label = $GameOverOverlay/GameOverScore
@onready var ready_overlay: ColorRect = $ReadyOverlay

var segments: Array = []
var player_side: int = LEFT
var player_rect: ColorRect = null

var score: int = 0
var high_score: int = 0
var time_limit: float = BASE_TIME_LIMIT
var time_left: float = BASE_TIME_LIMIT
var game_over: bool = false
var game_started: bool = false


func _ready() -> void:
	_load_high_score()
	_start_game()


func _start_game() -> void:
	segments.clear()
	_generate_segments(NUM_VISIBLE + GENERATE_BATCH)
	player_side = LEFT
	score = 0
	time_limit = BASE_TIME_LIMIT
	time_left = time_limit
	game_over = false
	game_started = false
	score_label.text = "0"
	game_over_overlay.visible = false
	ready_overlay.visible = true
	_redraw()


func _generate_segments(count: int) -> void:
	for _i in range(count):
		var roll := randf()
		var side := NONE
		if roll < 0.25:
			side = LEFT
		elif roll < 0.5:
			side = RIGHT
		var golden: bool = side == NONE and randf() < GOLD_CHANCE
		segments.append({"side": side, "golden": golden})


func _redraw() -> void:
	for child in trunk_container.get_children():
		child.queue_free()

	var visible_count: int = min(NUM_VISIBLE, segments.size())
	for i in range(visible_count):
		var y: float = CHOP_LINE_Y - float(i + 1) * SEGMENT_HEIGHT
		var seg: Dictionary = segments[i]

		var trunk_rect := ColorRect.new()
		trunk_rect.size = Vector2(TRUNK_WIDTH, SEGMENT_HEIGHT)
		trunk_rect.position = Vector2(CENTER_X - TRUNK_WIDTH / 2.0, y)
		trunk_rect.color = GOLD_COLOR if seg["golden"] else TRUNK_COLORS[i % TRUNK_COLORS.size()]
		trunk_container.add_child(trunk_rect)

		var side: int = seg["side"]
		if side != NONE:
			var branch_rect := ColorRect.new()
			branch_rect.size = Vector2(BRANCH_LEN, SEGMENT_HEIGHT * 0.7)
			var branch_y: float = y + SEGMENT_HEIGHT * 0.15
			if side == LEFT:
				branch_rect.position = Vector2(CENTER_X - TRUNK_WIDTH / 2.0 - BRANCH_LEN, branch_y)
			else:
				branch_rect.position = Vector2(CENTER_X + TRUNK_WIDTH / 2.0, branch_y)
			branch_rect.color = BRANCH_COLOR
			trunk_container.add_child(branch_rect)

	if player_rect == null:
		player_rect = ColorRect.new()
		player_rect.size = PLAYER_SIZE
		player_rect.color = PLAYER_COLOR
		add_child(player_rect)
	var player_x: float = CENTER_X - PLAYER_OFFSET_X - PLAYER_SIZE.x / 2.0 if player_side == LEFT else CENTER_X + PLAYER_OFFSET_X - PLAYER_SIZE.x / 2.0
	player_rect.position = Vector2(player_x, CHOP_LINE_Y - PLAYER_SIZE.y)


func _process(delta: float) -> void:
	if game_over or not game_started:
		return
	time_left -= delta
	var ratio: float = clamp(time_left / time_limit, 0.0, 1.0)
	timer_bar_fill.size.x = TIMER_BAR_MAX_WIDTH * ratio
	if time_left <= 0.0:
		_trigger_game_over()


func _input(event: InputEvent) -> void:
	var side := NONE
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_LEFT or event.keycode == KEY_A:
			side = LEFT
		elif event.keycode == KEY_RIGHT or event.keycode == KEY_D:
			side = RIGHT
		elif event.keycode == KEY_SPACE:
			side = player_side
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		side = LEFT if event.position.x < CENTER_X else RIGHT
	elif event is InputEventScreenTouch and event.pressed:
		side = LEFT if event.position.x < CENTER_X else RIGHT

	if side == NONE:
		return

	if game_over:
		_start_game()
		return

	if not game_started:
		game_started = true
		ready_overlay.visible = false
		return

	_chop(side)


func _chop(side: int) -> void:
	if segments.is_empty():
		return
	var bottom: Dictionary = segments[0]
	if bottom["side"] == side:
		player_side = side
		_trigger_game_over()
		return

	segments.pop_front()
	player_side = side
	score += 1
	time_limit = max(MIN_TIME_LIMIT, BASE_TIME_LIMIT - score * TIME_DECAY)
	time_left = time_limit

	if bottom["golden"]:
		score += GOLD_BONUS_SCORE
		time_left = min(time_left + GOLD_BONUS_TIME, BASE_TIME_LIMIT)

	score_label.text = str(score)

	if segments.size() < NUM_VISIBLE + LOW_WATER:
		_generate_segments(GENERATE_BATCH)

	_redraw()


func _trigger_game_over() -> void:
	game_over = true
	_redraw()
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
