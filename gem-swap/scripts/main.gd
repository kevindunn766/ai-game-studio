extends Node2D

# Gem Swap — a classic match-3: tap a gem, tap an adjacent gem to swap
# them. The swap only sticks if it lines up 3+ of a color somewhere on
# the board; otherwise it silently reverts. A tap-swap-adjacent input
# grammar distinct from every other grid game in the studio — Merge
# Numbers slides the whole board in one direction, Color Sort pours
# between tubes, Number Slide only moves a tile into the single empty
# slot. This is the only game where you pick exactly two cells and trade
# their contents.
#
# Note: boards are generated to avoid any pre-existing match, the
# standard approach for this genre, but a full deadlock check (no legal
# move anywhere on the board) isn't implemented — same documented scope
# boundary as Color Sort's unproven-solvability puzzles. Rare in practice
# on a 7x7 board with 5 colors.

const GRID_SIZE := 7
const NUM_COLORS := 5
const EMPTY := -1

const CELL_SIZE := 64.0
const CELL_GAP := 6.0
const GRID_TOP := 280.0

const STARTING_MOVES := 30
const MOVE_BONUS_PER_SWAP := 3
const SCORE_PER_GEM := 10
const SAVE_PATH := "user://gemswap_highscore.cfg"

const GEM_SATURATION := 0.7
const GEM_VALUE := 0.88
const SELECTED_COLOR := Color(0.97, 0.97, 0.95, 1.0)

@onready var grid_container: Node2D = $GridContainer
@onready var score_label: Label = $ScoreLabel
@onready var moves_label: Label = $MovesLabel
@onready var ready_overlay: ColorRect = $ReadyOverlay
@onready var game_over_overlay: ColorRect = $GameOverOverlay
@onready var game_over_score_label: Label = $GameOverOverlay/GameOverScore

var grid: Array = []
var gem_nodes: Array = []
var selected: Vector2i = Vector2i(-1, -1)
var grid_left: float = 0.0

var score: int = 0
var high_score: int = 0
var moves: int = STARTING_MOVES
var game_over: bool = false
var game_started: bool = false


func _ready() -> void:
	grid_left = (540.0 - GRID_SIZE * CELL_SIZE - (GRID_SIZE - 1) * CELL_GAP) / 2.0
	_load_high_score()
	_start_game()


func _gem_color(id: int) -> Color:
	var hue: float = float(id) / float(NUM_COLORS)
	return Color.from_hsv(hue, GEM_SATURATION, GEM_VALUE, 1.0)


func _start_game() -> void:
	score = 0
	moves = STARTING_MOVES
	game_over = false
	game_started = false
	selected = Vector2i(-1, -1)
	score_label.text = "Score: 0"
	moves_label.text = "Moves: %d" % moves
	game_over_overlay.visible = false
	ready_overlay.visible = true
	_generate_board()
	_redraw_board()


func _random_color_avoiding_match(row: int, col: int) -> int:
	while true:
		var c: int = randi() % NUM_COLORS
		var left_match: bool = col >= 2 and grid[row][col - 1] == c and grid[row][col - 2] == c
		var up_match: bool = row >= 2 and grid[row - 1][col] == c and grid[row - 2][col] == c
		if not left_match and not up_match:
			return c
	return 0


func _generate_board() -> void:
	grid.clear()
	for row in range(GRID_SIZE):
		var line: Array = []
		for col in range(GRID_SIZE):
			line.append(0)
		grid.append(line)
	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			grid[row][col] = _random_color_avoiding_match(row, col)


func _cell_position(row: int, col: int) -> Vector2:
	return Vector2(grid_left + col * (CELL_SIZE + CELL_GAP), GRID_TOP + row * (CELL_SIZE + CELL_GAP))


func _redraw_board() -> void:
	for c in grid_container.get_children():
		c.queue_free()
	gem_nodes.clear()

	for row in range(GRID_SIZE):
		var node_row: Array = []
		for col in range(GRID_SIZE):
			var rect := ColorRect.new()
			rect.size = Vector2(CELL_SIZE, CELL_SIZE)
			rect.position = _cell_position(row, col)
			var value: int = grid[row][col]
			rect.color = SELECTED_COLOR if Vector2i(col, row) == selected else _gem_color(value)
			grid_container.add_child(rect)
			node_row.append(rect)
		gem_nodes.append(node_row)


func _are_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return abs(a.x - b.x) + abs(a.y - b.y) == 1


func _find_all_matches() -> Dictionary:
	var matches: Dictionary = {}

	for row in range(GRID_SIZE):
		var run_start := 0
		for col in range(1, GRID_SIZE + 1):
			var same: bool = col < GRID_SIZE and grid[row][col] == grid[row][run_start] and grid[row][run_start] != EMPTY
			if not same:
				if col - run_start >= 3:
					for c in range(run_start, col):
						matches[Vector2i(c, row)] = true
				run_start = col

	for col in range(GRID_SIZE):
		var run_start := 0
		for row in range(1, GRID_SIZE + 1):
			var same: bool = row < GRID_SIZE and grid[row][col] == grid[run_start][col] and grid[run_start][col] != EMPTY
			if not same:
				if row - run_start >= 3:
					for r in range(run_start, row):
						matches[Vector2i(col, r)] = true
				run_start = row

	return matches


func _try_swap(a: Vector2i, b: Vector2i) -> bool:
	if not _are_adjacent(a, b):
		return false

	var tmp: int = grid[a.y][a.x]
	grid[a.y][a.x] = grid[b.y][b.x]
	grid[b.y][b.x] = tmp

	var matches: Dictionary = _find_all_matches()
	if matches.is_empty():
		var tmp2: int = grid[a.y][a.x]
		grid[a.y][a.x] = grid[b.y][b.x]
		grid[b.y][b.x] = tmp2
		return false

	moves -= 1
	moves_label.text = "Moves: %d" % moves
	score += MOVE_BONUS_PER_SWAP
	_process_clears()
	return true


func _process_clears() -> void:
	while true:
		var matches: Dictionary = _find_all_matches()
		if matches.is_empty():
			break
		for cell in matches.keys():
			grid[cell.y][cell.x] = EMPTY
		score += matches.size() * SCORE_PER_GEM
		_apply_gravity()
		_refill_empties()
	score_label.text = "Score: %d" % score


func _apply_gravity() -> void:
	for col in range(GRID_SIZE):
		var stack: Array = []
		for row in range(GRID_SIZE):
			if grid[row][col] != EMPTY:
				stack.append(grid[row][col])
		var empty_count: int = GRID_SIZE - stack.size()
		for row in range(GRID_SIZE):
			if row < empty_count:
				grid[row][col] = EMPTY
			else:
				grid[row][col] = stack[row - empty_count]


func _refill_empties() -> void:
	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			if grid[row][col] == EMPTY:
				grid[row][col] = randi() % NUM_COLORS


func _cell_at(pos: Vector2) -> Vector2i:
	if pos.y < GRID_TOP:
		return Vector2i(-1, -1)
	var col: int = int((pos.x - grid_left) / (CELL_SIZE + CELL_GAP))
	var row: int = int((pos.y - GRID_TOP) / (CELL_SIZE + CELL_GAP))
	if col < 0 or col >= GRID_SIZE or row < 0 or row >= GRID_SIZE:
		return Vector2i(-1, -1)
	var local_x: float = pos.x - grid_left - col * (CELL_SIZE + CELL_GAP)
	var local_y: float = pos.y - GRID_TOP - row * (CELL_SIZE + CELL_GAP)
	if local_x > CELL_SIZE or local_y > CELL_SIZE:
		return Vector2i(-1, -1)
	return Vector2i(col, row)


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

	var cell: Vector2i = _cell_at(pos)
	if cell == Vector2i(-1, -1):
		return
	_on_cell_tapped(cell)


func _on_cell_tapped(cell: Vector2i) -> void:
	if selected == Vector2i(-1, -1):
		selected = cell
		_redraw_board()
		return

	if cell == selected:
		selected = Vector2i(-1, -1)
		_redraw_board()
		return

	if _are_adjacent(selected, cell):
		_try_swap(selected, cell)
		selected = Vector2i(-1, -1)
		_redraw_board()
		if moves <= 0:
			_trigger_game_over()
	else:
		selected = cell
		_redraw_board()


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
