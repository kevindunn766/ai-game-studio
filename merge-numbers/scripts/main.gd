extends Node2D

# Merge Numbers — classic slide-and-merge puzzle. Swipe (or drag with the
# mouse) up/down/left/right, or use the arrow keys, to slide every tile in
# that direction. Matching tiles that collide merge into one.

const GRID_SIZE := 4
const CELL_SIZE := 110.0
const GRID_PADDING := 12.0
const GRID_TOP := 200.0
const SWIPE_THRESHOLD := 40.0
const SAVE_PATH := "user://mergenumbers_highscore.cfg"

const TILE_COLORS := {
	0: Color(0.8, 0.76, 0.7, 1.0),
	2: Color(0.93, 0.89, 0.82, 1.0),
	4: Color(0.93, 0.87, 0.71, 1.0),
	8: Color(0.95, 0.69, 0.47, 1.0),
	16: Color(0.96, 0.58, 0.39, 1.0),
	32: Color(0.96, 0.49, 0.37, 1.0),
	64: Color(0.96, 0.37, 0.23, 1.0),
	128: Color(0.93, 0.81, 0.45, 1.0),
	256: Color(0.93, 0.79, 0.35, 1.0),
	512: Color(0.93, 0.78, 0.25, 1.0),
	1024: Color(0.93, 0.76, 0.15, 1.0),
	2048: Color(0.93, 0.74, 0.05, 1.0),
}

@onready var grid_bg: Node2D = $GridBg
@onready var tile_container: Node2D = $TileContainer
@onready var score_label: Label = $ScoreLabel
@onready var game_over_overlay: ColorRect = $GameOverOverlay
@onready var game_over_score_label: Label = $GameOverOverlay/GameOverScore

var grid: Array = []
var score: int = 0
var high_score: int = 0
var game_over: bool = false
var drag_start: Vector2 = Vector2.INF


func _ready() -> void:
	_build_grid_background()
	_load_high_score()
	_start_game()


func _build_grid_background() -> void:
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var cell := ColorRect.new()
			cell.size = Vector2(CELL_SIZE, CELL_SIZE)
			cell.position = _cell_position(x, y)
			cell.color = TILE_COLORS[0]
			grid_bg.add_child(cell)


func _cell_position(x: int, y: int) -> Vector2:
	var origin_x: float = (540.0 - (GRID_SIZE * CELL_SIZE + (GRID_SIZE + 1) * GRID_PADDING)) / 2.0
	return Vector2(
		origin_x + GRID_PADDING + x * (CELL_SIZE + GRID_PADDING),
		GRID_TOP + GRID_PADDING + y * (CELL_SIZE + GRID_PADDING)
	)


func _start_game() -> void:
	grid = []
	for _y in range(GRID_SIZE):
		var row := []
		for _x in range(GRID_SIZE):
			row.append(0)
		grid.append(row)
	score = 0
	game_over = false
	score_label.text = "Score: 0"
	game_over_overlay.visible = false
	_spawn_random_tile()
	_spawn_random_tile()
	_redraw()


func _spawn_random_tile() -> void:
	var empties := []
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			if grid[y][x] == 0:
				empties.append(Vector2i(x, y))
	if empties.is_empty():
		return
	var cell: Vector2i = empties[randi() % empties.size()]
	grid[cell.y][cell.x] = 4 if randf() < 0.1 else 2


func _redraw() -> void:
	for child in tile_container.get_children():
		child.queue_free()

	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			var value: int = grid[y][x]
			if value == 0:
				continue
			var tile := ColorRect.new()
			tile.size = Vector2(CELL_SIZE, CELL_SIZE)
			tile.position = _cell_position(x, y)
			tile.color = TILE_COLORS.get(value, Color(0.2, 0.2, 0.2, 1.0))
			tile_container.add_child(tile)

			var label := Label.new()
			label.text = str(value)
			label.size = Vector2(CELL_SIZE, CELL_SIZE)
			label.position = _cell_position(x, y)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", 40 if value < 100 else 32)
			tile_container.add_child(label)


func _process(_delta: float) -> void:
	if game_over:
		if Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("ui_right") \
				or Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("ui_down") \
				or Input.is_action_just_pressed("ui_accept"):
			_start_game()
		return
	if Input.is_action_just_pressed("ui_left"):
		_move(-1, 0)
	elif Input.is_action_just_pressed("ui_right"):
		_move(1, 0)
	elif Input.is_action_just_pressed("ui_up"):
		_move(0, -1)
	elif Input.is_action_just_pressed("ui_down"):
		_move(0, 1)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			drag_start = event.position
		else:
			_handle_drag_end(event.position)
	elif event is InputEventScreenTouch:
		if event.pressed:
			drag_start = event.position
		else:
			_handle_drag_end(event.position)


func _handle_drag_end(end_pos: Vector2) -> void:
	if drag_start == Vector2.INF:
		return
	var delta: Vector2 = end_pos - drag_start
	drag_start = Vector2.INF

	if game_over:
		_start_game()
		return

	if delta.length() < SWIPE_THRESHOLD:
		return

	if abs(delta.x) > abs(delta.y):
		_move(1 if delta.x > 0 else -1, 0)
	else:
		_move(0, 1 if delta.y > 0 else -1)


func _process_line(line: Array) -> Dictionary:
	var vals := []
	for v in line:
		if v != 0:
			vals.append(v)

	var merged := []
	var gained := 0
	var i := 0
	while i < vals.size():
		if i + 1 < vals.size() and vals[i] == vals[i + 1]:
			var new_val: int = vals[i] * 2
			merged.append(new_val)
			gained += new_val
			i += 2
		else:
			merged.append(vals[i])
			i += 1
	while merged.size() < line.size():
		merged.append(0)

	return {"line": merged, "score": gained}


func _move(dx: int, dy: int) -> bool:
	var changed := false
	var total_gain := 0

	if dx != 0:
		for y in range(GRID_SIZE):
			var row := []
			for x in range(GRID_SIZE):
				row.append(grid[y][x])
			if dx == 1:
				row.reverse()
			var result: Dictionary = _process_line(row)
			var new_row: Array = result["line"]
			if dx == 1:
				new_row.reverse()
			for x in range(GRID_SIZE):
				if grid[y][x] != new_row[x]:
					changed = true
				grid[y][x] = new_row[x]
			total_gain += result["score"]
	else:
		for x in range(GRID_SIZE):
			var col := []
			for y in range(GRID_SIZE):
				col.append(grid[y][x])
			if dy == 1:
				col.reverse()
			var result: Dictionary = _process_line(col)
			var new_col: Array = result["line"]
			if dy == 1:
				new_col.reverse()
			for y in range(GRID_SIZE):
				if grid[y][x] != new_col[y]:
					changed = true
				grid[y][x] = new_col[y]
			total_gain += result["score"]

	if changed:
		score += total_gain
		score_label.text = "Score: %d" % score
		_spawn_random_tile()
		_redraw()
		if _no_moves_available():
			_trigger_game_over()

	return changed


func _no_moves_available() -> bool:
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			if grid[y][x] == 0:
				return false
			if x + 1 < GRID_SIZE and grid[y][x] == grid[y][x + 1]:
				return false
			if y + 1 < GRID_SIZE and grid[y][x] == grid[y + 1][x]:
				return false
	return true


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
