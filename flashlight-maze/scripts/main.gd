extends Node2D

# Flashlight Maze — a fog-of-war exploration game. Unlike Snake 3D (fully
# visible grid, continuous auto-move), this is a partial-information
# puzzle: only a small radius around the player is ever revealed (and it
# stays revealed once seen), so finding the exit means actually exploring
# and remembering the layout, not just reacting.

const CELL_SIZE := 40.0
const GRID_TOP := 200.0
const VISION_RADIUS := 2
const BASE_GRID_SIZE := 7
const MAX_GRID_SIZE := 11
const GRID_GROWTH_INTERVAL := 2
const TIME_PER_CELL := 0.7
const MIN_TIME_PER_CELL := 0.4
const TIME_DECAY_PER_SCORE := 0.01
const MAX_STRIKES := 3
const SWIPE_THRESHOLD := 30.0
const TIMER_BAR_MAX_WIDTH := 500.0
const SAVE_PATH := "user://flashlightmaze_highscore.cfg"

const WALL_COLOR := Color(0.32, 0.34, 0.4, 1.0)
const FOG_COLOR := Color(0.05, 0.05, 0.06, 1.0)
const FLOOR_COLOR := Color(0.82, 0.8, 0.78, 1.0)
const EXIT_COLOR := Color(0.2, 0.75, 0.4, 1.0)
const TORCH_COLOR := Color(0.93, 0.76, 0.15, 1.0)

# Novelty twist: an occasional torch pickup widens the vision radius for
# the rest of the current maze — a utility power-up, distinct from the
# studio's more common score bonuses.
const TORCH_CHANCE := 0.5
const TORCH_VISION_BOOST := 1

@onready var maze_container: Node2D = $MazeContainer
@onready var player_token: Polygon2D = $PlayerToken
@onready var score_label: Label = $ScoreLabel
@onready var strikes_label: Label = $StrikesLabel
@onready var timer_bar_fill: ColorRect = $TimerBarFill
@onready var miss_flash_label: Label = $MissFlashLabel
@onready var ready_overlay: ColorRect = $ReadyOverlay
@onready var game_over_overlay: ColorRect = $GameOverOverlay
@onready var game_over_score_label: Label = $GameOverOverlay/GameOverScore

var grid_size: int = BASE_GRID_SIZE
var walls_open: Dictionary = {}
var revealed: Dictionary = {}
var player_cell: Vector2i = Vector2i.ZERO
var exit_cell: Vector2i = Vector2i.ZERO
var torch_cell: Vector2i = Vector2i(-1, -1)
var vision_bonus: int = 0
var drag_start: Vector2 = Vector2.INF
var miss_flash_timer: float = 0.0

var score: int = 0
var high_score: int = 0
var strikes: int = MAX_STRIKES
var time_limit: float = 1.0
var time_left: float = 1.0
var game_over: bool = false
var game_started: bool = false


func _ready() -> void:
	_load_high_score()
	_start_game()


func _start_game() -> void:
	grid_size = BASE_GRID_SIZE
	score = 0
	strikes = MAX_STRIKES
	game_over = false
	game_started = false
	score_label.text = "0"
	_update_strikes_label()
	game_over_overlay.visible = false
	ready_overlay.visible = true
	_generate_new_maze()


func _generate_new_maze() -> void:
	_generate_maze(grid_size, grid_size)
	player_cell = Vector2i.ZERO
	exit_cell = Vector2i(grid_size - 1, grid_size - 1)
	vision_bonus = 0
	torch_cell = Vector2i(-1, -1)
	if randf() < TORCH_CHANCE:
		var candidate: Vector2i = Vector2i(randi() % grid_size, randi() % grid_size)
		if candidate != Vector2i.ZERO and candidate != exit_cell:
			torch_cell = candidate
	revealed.clear()
	_reveal_around(player_cell)

	var per_cell_time: float = max(MIN_TIME_PER_CELL, TIME_PER_CELL - score * TIME_DECAY_PER_SCORE)
	time_limit = grid_size * grid_size * per_cell_time
	time_left = time_limit

	_redraw()


func _generate_maze(w: int, h: int) -> void:
	walls_open.clear()
	for y in range(h):
		for x in range(w):
			walls_open[Vector2i(x, y)] = {"N": false, "E": false, "S": false, "W": false}

	var dirs := [
		{"name": "N", "dx": 0, "dy": -1, "opp": "S"},
		{"name": "E", "dx": 1, "dy": 0, "opp": "W"},
		{"name": "S", "dx": 0, "dy": 1, "opp": "N"},
		{"name": "W", "dx": -1, "dy": 0, "opp": "E"},
	]

	var visited: Dictionary = {}
	var start := Vector2i(0, 0)
	visited[start] = true
	var stack: Array = [start]

	while not stack.is_empty():
		var current: Vector2i = stack.back()
		var candidates: Array = []
		for d in dirs:
			var n: Vector2i = current + Vector2i(d["dx"], d["dy"])
			if n.x >= 0 and n.x < w and n.y >= 0 and n.y < h and not visited.has(n):
				candidates.append({"cell": n, "dir": d})

		if candidates.is_empty():
			stack.pop_back()
			continue

		var choice: Dictionary = candidates[randi() % candidates.size()]
		var n: Vector2i = choice["cell"]
		var d: Dictionary = choice["dir"]
		walls_open[current][d["name"]] = true
		walls_open[n][d["opp"]] = true
		visited[n] = true
		stack.append(n)


func _reveal_around(cell: Vector2i) -> void:
	# A circular reveal (not a square) actually matches "flashlight" — a
	# square vision radius was a leftover implementation shortcut.
	var radius: int = VISION_RADIUS + vision_bonus
	var radius_sq: float = (radius + 0.5) * (radius + 0.5)
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > radius_sq:
				continue
			var c := cell + Vector2i(dx, dy)
			if c.x >= 0 and c.x < grid_size and c.y >= 0 and c.y < grid_size:
				revealed[c] = true


func _grid_origin_x() -> float:
	return (540.0 - grid_size * CELL_SIZE) / 2.0


func _redraw() -> void:
	for c in maze_container.get_children():
		c.queue_free()

	var origin_x: float = _grid_origin_x()
	for y in range(grid_size):
		for x in range(grid_size):
			var cell := Vector2i(x, y)
			var px: float = origin_x + x * CELL_SIZE
			var py: float = GRID_TOP + y * CELL_SIZE
			var is_revealed: bool = revealed.get(cell, false)

			var bg := ColorRect.new()
			bg.size = Vector2(CELL_SIZE - 2.0, CELL_SIZE - 2.0)
			bg.position = Vector2(px + 1.0, py + 1.0)
			if not is_revealed:
				bg.color = FOG_COLOR
			elif cell == exit_cell:
				bg.color = EXIT_COLOR
			else:
				bg.color = FLOOR_COLOR
			maze_container.add_child(bg)

			if is_revealed and cell == torch_cell:
				var torch := Polygon2D.new()
				var cx: float = px + CELL_SIZE / 2.0
				var cy: float = py + CELL_SIZE / 2.0
				var r: float = CELL_SIZE * 0.28
				torch.polygon = PackedVector2Array([
					Vector2(cx, cy - r), Vector2(cx + r, cy), Vector2(cx, cy + r), Vector2(cx - r, cy)
				])
				torch.color = TORCH_COLOR
				maze_container.add_child(torch)

			if is_revealed:
				var w: Dictionary = walls_open[cell]
				var t := 4.0
				if not w["N"]:
					_add_wall(Vector2(px, py), Vector2(CELL_SIZE, t))
				if not w["W"]:
					_add_wall(Vector2(px, py), Vector2(t, CELL_SIZE))
				if not w["S"]:
					_add_wall(Vector2(px, py + CELL_SIZE - t), Vector2(CELL_SIZE, t))
				if not w["E"]:
					_add_wall(Vector2(px + CELL_SIZE - t, py), Vector2(t, CELL_SIZE))

	player_token.position = Vector2(
		origin_x + player_cell.x * CELL_SIZE + CELL_SIZE / 2.0,
		GRID_TOP + player_cell.y * CELL_SIZE + CELL_SIZE / 2.0
	)


func _add_wall(pos: Vector2, size: Vector2) -> void:
	var wall := ColorRect.new()
	wall.position = pos
	wall.size = size
	wall.color = WALL_COLOR
	maze_container.add_child(wall)


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
		_on_timeout()


func _dir_for(dx: int, dy: int) -> String:
	if dy == -1:
		return "N"
	if dy == 1:
		return "S"
	if dx == -1:
		return "W"
	if dx == 1:
		return "E"
	return ""


func _try_move(dx: int, dy: int) -> void:
	if game_over or not game_started:
		return
	var dir_name: String = _dir_for(dx, dy)
	if dir_name == "" or not walls_open[player_cell][dir_name]:
		return

	player_cell += Vector2i(dx, dy)
	if player_cell == torch_cell:
		vision_bonus += TORCH_VISION_BOOST
		torch_cell = Vector2i(-1, -1)
	_reveal_around(player_cell)
	if player_cell == exit_cell:
		_on_maze_solved()
	_redraw()


func _on_maze_solved() -> void:
	score += 1
	score_label.text = str(score)
	if score % GRID_GROWTH_INTERVAL == 0:
		grid_size = min(MAX_GRID_SIZE, grid_size + 1)
	_generate_new_maze()


func _on_timeout() -> void:
	strikes -= 1
	_update_strikes_label()
	miss_flash_label.text = "TIME'S UP!"
	miss_flash_label.visible = true
	miss_flash_timer = 0.9
	if strikes <= 0:
		_trigger_game_over()
	else:
		_generate_new_maze()


func _update_strikes_label() -> void:
	var s := ""
	for i in range(strikes):
		s += "*"
		if i < strikes - 1:
			s += " "
	strikes_label.text = s


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if not game_started:
			game_started = true
			ready_overlay.visible = false
			return
		if game_over:
			_start_game()
			return
		if event.keycode == KEY_W or event.keycode == KEY_UP:
			_try_move(0, -1)
		elif event.keycode == KEY_S or event.keycode == KEY_DOWN:
			_try_move(0, 1)
		elif event.keycode == KEY_A or event.keycode == KEY_LEFT:
			_try_move(-1, 0)
		elif event.keycode == KEY_D or event.keycode == KEY_RIGHT:
			_try_move(1, 0)
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			drag_start = event.position
		else:
			_handle_release(event.position)
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			drag_start = event.position
		else:
			_handle_release(event.position)


func _handle_release(end_pos: Vector2) -> void:
	if drag_start == Vector2.INF:
		return
	var delta: Vector2 = end_pos - drag_start
	drag_start = Vector2.INF

	if not game_started:
		game_started = true
		ready_overlay.visible = false
		return
	if game_over:
		_start_game()
		return

	if delta.length() < SWIPE_THRESHOLD:
		return

	if abs(delta.x) > abs(delta.y):
		_try_move(1 if delta.x > 0 else -1, 0)
	else:
		_try_move(0, 1 if delta.y > 0 else -1)


func _trigger_game_over() -> void:
	game_over = true
	if score > high_score:
		high_score = score
		_save_high_score()
	game_over_score_label.text = "Solved: %d  Best: %d" % [score, high_score]
	game_over_overlay.visible = true


func _load_high_score() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		high_score = int(cfg.get_value("scores", "high_score", 0))


func _save_high_score() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("scores", "high_score", high_score)
	cfg.save(SAVE_PATH)
