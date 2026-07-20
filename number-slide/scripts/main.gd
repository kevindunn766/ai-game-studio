extends Node2D

# Number Slide — a classic sliding tile puzzle (the "15-puzzle" mechanic,
# public domain and generic enough that no single commercial product owns
# it). Slide numbered tiles into the one empty slot to put them back in
# order, 1 through 15. A pure planning puzzle with no timer and no
# reflexes, using the same shared-move-budget fail state established by
# Color Sort: solving refills moves, and the puzzle gets more scrambled
# each time, so efficient solving is what keeps a run alive.
#
# Puzzles are generated solvability-by-construction: start from the solved
# board and make N random legal slides from it, so the result is always
# reachable back to solved (the standard technique for this genre, and the
# same one already used by Color Sort and Flashlight Maze).

const GRID_SIZE := 4
const NUM_TILES := GRID_SIZE * GRID_SIZE
const TILE_SIZE := 110.0
const TILE_GAP := 8.0
const GRID_TOP := 280.0
const BASE_SHUFFLE_MOVES := 30
const MAX_SHUFFLE_MOVES := 150
const SHUFFLE_STEP := 10
const STARTING_MOVES := 80
const MOVE_BONUS_PER_SOLVE := 25
const SAVE_PATH := "user://numberslide_highscore.cfg"

const TILE_COLOR := Color(0.3, 0.42, 0.62, 1.0)
const EMPTY_COLOR := Color(0.16, 0.17, 0.21, 1.0)

# Novel element: Locked Tile. A rare numbered tile is fixed in place for
# the puzzle's first few moves (counted across the whole puzzle, not just
# moves touching it) — it can't be the target of a slide even when
# adjacent to the blank, forcing the player to route around wherever it
# currently sits. Reuses the studio's locked/frozen motif (Merge Numbers'
# frozen cells, Color Sort's locked tube) in a new genre.
const LOCKED_TILE_CHANCE_PER_PUZZLE := 0.3
const LOCK_DURATION_MOVES := 5
const LOCKED_TILE_COLOR := Color(0.55, 0.45, 0.15, 1.0)
var locked_tile_value: int = -1
var locked_moves_remaining: int = 0

@onready var tiles_container: Node2D = $TilesContainer
@onready var score_label: Label = $ScoreLabel
@onready var moves_label: Label = $MovesLabel
@onready var ready_overlay: ColorRect = $ReadyOverlay
@onready var game_over_overlay: ColorRect = $GameOverOverlay
@onready var game_over_score_label: Label = $GameOverOverlay/GameOverScore

var board: Array = []
var blank_index: int = NUM_TILES - 1
var tile_rects: Array = []
var tile_labels: Array = []

var solved_count: int = 0
var high_score: int = 0
var moves: int = STARTING_MOVES
var game_over: bool = false
var game_started: bool = false


func _ready() -> void:
	var grid_width: float = GRID_SIZE * TILE_SIZE + (GRID_SIZE - 1) * TILE_GAP
	var left: float = (540.0 - grid_width) / 2.0
	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			var r := ColorRect.new()
			r.size = Vector2(TILE_SIZE, TILE_SIZE)
			r.position = Vector2(left + col * (TILE_SIZE + TILE_GAP), GRID_TOP + row * (TILE_SIZE + TILE_GAP))
			tiles_container.add_child(r)
			tile_rects.append(r)

			var lbl := Label.new()
			lbl.size = Vector2(TILE_SIZE, TILE_SIZE)
			lbl.position = r.position
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			lbl.add_theme_font_size_override("font_size", 40)
			lbl.add_theme_color_override("font_color", Color(0.97, 0.97, 0.95, 1.0))
			tiles_container.add_child(lbl)
			tile_labels.append(lbl)
	_load_high_score()
	_start_game()


func _solved_board() -> Array:
	var b: Array = []
	for i in range(1, NUM_TILES):
		b.append(i)
	b.append(0)
	return b


func _shuffle_moves_for(count: int) -> int:
	return clampi(BASE_SHUFFLE_MOVES + count * SHUFFLE_STEP, BASE_SHUFFLE_MOVES, MAX_SHUFFLE_MOVES)


func _neighbors(idx: int) -> Array:
	var result: Array = []
	var row: int = idx / GRID_SIZE
	var col: int = idx % GRID_SIZE
	if row > 0:
		result.append(idx - GRID_SIZE)
	if row < GRID_SIZE - 1:
		result.append(idx + GRID_SIZE)
	if col > 0:
		result.append(idx - 1)
	if col < GRID_SIZE - 1:
		result.append(idx + 1)
	return result


func _start_game() -> void:
	solved_count = 0
	moves = STARTING_MOVES
	game_over = false
	game_started = false
	score_label.text = "Solved: 0"
	moves_label.text = "Moves: %d" % moves
	game_over_overlay.visible = false
	ready_overlay.visible = true
	_generate_puzzle()


func _generate_puzzle() -> void:
	board = _solved_board()
	blank_index = NUM_TILES - 1
	var last_swapped := -1
	var shuffle_count: int = _shuffle_moves_for(solved_count)
	for _i in range(shuffle_count):
		var options: Array = _neighbors(blank_index)
		if options.size() > 1 and options.has(last_swapped):
			options.erase(last_swapped)
		var pick: int = options[randi() % options.size()]
		board[blank_index] = board[pick]
		board[pick] = 0
		last_swapped = blank_index
		blank_index = pick

	if randf() < LOCKED_TILE_CHANCE_PER_PUZZLE:
		locked_tile_value = 1 + randi() % (NUM_TILES - 1)
		locked_moves_remaining = LOCK_DURATION_MOVES
	else:
		locked_tile_value = -1
		locked_moves_remaining = 0

	_redraw_board()


func _redraw_board() -> void:
	for i in range(NUM_TILES):
		var value: int = board[i]
		if value == 0:
			tile_rects[i].color = EMPTY_COLOR
			tile_labels[i].text = ""
		else:
			tile_rects[i].color = LOCKED_TILE_COLOR if (locked_moves_remaining > 0 and value == locked_tile_value) else TILE_COLOR
			tile_labels[i].text = str(value)


func _is_solved() -> bool:
	return board == _solved_board()


func _tile_index_at(pos: Vector2) -> int:
	for i in range(NUM_TILES):
		if tile_rects[i].get_global_rect().has_point(pos):
			return i
	return -1


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

	var idx: int = _tile_index_at(pos)
	if idx != -1:
		_on_tile_tapped(idx)


func _on_tile_tapped(idx: int) -> void:
	if idx == blank_index:
		return
	if not _neighbors(blank_index).has(idx):
		return
	if locked_moves_remaining > 0 and board[idx] == locked_tile_value:
		return

	board[blank_index] = board[idx]
	board[idx] = 0
	blank_index = idx
	moves -= 1
	moves_label.text = "Moves: %d" % moves

	if locked_moves_remaining > 0:
		locked_moves_remaining -= 1
		if locked_moves_remaining <= 0:
			locked_tile_value = -1

	_redraw_board()

	if _is_solved():
		_on_puzzle_solved()
	elif moves <= 0:
		_trigger_game_over()


func _on_puzzle_solved() -> void:
	solved_count += 1
	score_label.text = "Solved: %d" % solved_count
	moves += MOVE_BONUS_PER_SOLVE
	moves_label.text = "Moves: %d" % moves
	_generate_puzzle()


func _trigger_game_over() -> void:
	game_over = true
	if solved_count > high_score:
		high_score = solved_count
		_save_high_score()
	game_over_score_label.text = "Solved: %d  Best: %d" % [solved_count, high_score]
	game_over_overlay.visible = true


func _load_high_score() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		high_score = int(cfg.get_value("scores", "high_score", 0))


func _save_high_score() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("scores", "high_score", high_score)
	cfg.save(SAVE_PATH)
