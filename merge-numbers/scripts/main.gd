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

# Novelty twist: a rare Star wildcard tile merges with ANY neighbor it
# touches (doubling that neighbor's value), not just an equal one — a
# controlled-chaos escape valve generic 2048 clones don't have.
const WILDCARD := -1
const WILDCARD_CHANCE := 0.08
const WILDCARD_COLOR := Color(0.55, 0.4, 0.75, 1.0)

# Structural addition: frozen cells. As the score crosses fixed milestones,
# a patch of ice permanently locks one empty cell — it never moves, never
# merges, and blocks tiles from sliding through it, splitting a row/column
# into independent segments on either side. This changes the board's
# topology over a run instead of just adding another tile type to merge.
const FROZEN := -2
const FROZEN_COLOR := Color(0.4, 0.48, 0.55, 1.0)
const MAX_FROZEN := 3
const FREEZE_SCORE_INTERVAL := 300

# Studio Palette v1 (see COLOR_SYSTEM.md). The old palette was a hand-copied
# 2048 ramp that jumped between color families partway through (128 reset
# back to a lighter gold after 64's deep red). Rebuilt as one continuous
# Munsell-style ramp: hue drifts warm-to-red, saturation climbs, value dips
# slightly, all in lockstep with tile power — so higher tiles always read as
# "more intense," never as an arbitrary swatch swap.
const EMPTY_CELL_COLOR := Color(0.82, 0.78, 0.72, 1.0)
const TILE_RAMP_STEPS := 11
const TILE_HUE_START := 0.135
const TILE_HUE_END := 0.0
const TILE_SAT_START := 0.25
const TILE_SAT_END := 0.82
const TILE_VAL_START := 0.95
const TILE_VAL_END := 0.78


func _tile_color(value: int) -> Color:
	if value == FROZEN:
		return FROZEN_COLOR
	if value == WILDCARD:
		return WILDCARD_COLOR
	if value <= 0:
		return EMPTY_CELL_COLOR
	var power: int = int(round(log(value) / log(2)))
	var t: float = clamp(float(power - 1) / float(TILE_RAMP_STEPS - 1), 0.0, 1.0)
	var hue: float = lerp(TILE_HUE_START, TILE_HUE_END, t)
	var sat: float = lerp(TILE_SAT_START, TILE_SAT_END, t)
	var val: float = lerp(TILE_VAL_START, TILE_VAL_END, t)
	return Color.from_hsv(hue, sat, val, 1.0)


func _readable_text_color(bg: Color) -> Color:
	# Outline/text role (COLOR_SYSTEM.md): pick near-black or near-white based
	# on the tile's actual luminance so labels never rely on a theme default
	# that may not contrast with a light, low-chroma background.
	var luminance: float = 0.299 * bg.r + 0.587 * bg.g + 0.114 * bg.b
	return Color(0.08, 0.08, 0.08, 1.0) if luminance > 0.55 else Color(0.95, 0.95, 0.95, 1.0)

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
var next_freeze_score: int = FREEZE_SCORE_INTERVAL


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
			cell.color = EMPTY_CELL_COLOR
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
	next_freeze_score = FREEZE_SCORE_INTERVAL
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
	var roll := randf()
	if roll < WILDCARD_CHANCE:
		grid[cell.y][cell.x] = WILDCARD
	elif roll < WILDCARD_CHANCE + 0.1:
		grid[cell.y][cell.x] = 4
	else:
		grid[cell.y][cell.x] = 2


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
			tile.color = _tile_color(value)
			tile_container.add_child(tile)

			var label := Label.new()
			if value == FROZEN:
				label.text = "❄"
			elif value == WILDCARD:
				label.text = "★"
			else:
				label.text = str(value)
			label.size = Vector2(CELL_SIZE, CELL_SIZE)
			label.position = _cell_position(x, y)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", 40 if value < 100 else 32)
			label.add_theme_color_override("font_color", _readable_text_color(tile.color))
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


func _can_merge(a: int, b: int) -> bool:
	if a == FROZEN or b == FROZEN:
		return false
	return a == b or a == WILDCARD or b == WILDCARD


func _merge_result(a: int, b: int) -> int:
	if a == WILDCARD and b == WILDCARD:
		return 4
	if a == WILDCARD:
		return b * 2
	if b == WILDCARD:
		return a * 2
	return a * 2


func _process_line(line: Array) -> Dictionary:
	var vals := []
	for v in line:
		if v != 0:
			vals.append(v)

	var merged := []
	var gained := 0
	var i := 0
	while i < vals.size():
		if i + 1 < vals.size() and _can_merge(vals[i], vals[i + 1]):
			var new_val: int = _merge_result(vals[i], vals[i + 1])
			merged.append(new_val)
			gained += new_val
			i += 2
		else:
			merged.append(vals[i])
			i += 1
	while merged.size() < line.size():
		merged.append(0)

	return {"line": merged, "score": gained}


func _process_line_with_barriers(line: Array) -> Dictionary:
	var result_line: Array = line.duplicate()
	var total_gain := 0
	var segment_start := 0
	for i in range(line.size() + 1):
		var at_end: bool = i == line.size()
		var is_frozen: bool = (not at_end) and line[i] == FROZEN
		if at_end or is_frozen:
			var seg_len: int = i - segment_start
			if seg_len > 0:
				var segment: Array = line.slice(segment_start, i)
				var processed: Dictionary = _process_line(segment)
				var processed_line: Array = processed["line"]
				for k in range(seg_len):
					result_line[segment_start + k] = processed_line[k]
				total_gain += processed["score"]
			segment_start = i + 1
	return {"line": result_line, "score": total_gain}


func _frozen_count() -> int:
	var count := 0
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			if grid[y][x] == FROZEN:
				count += 1
	return count


func _freeze_random_cell() -> bool:
	var empties := []
	for y in range(GRID_SIZE):
		for x in range(GRID_SIZE):
			if grid[y][x] == 0:
				empties.append(Vector2i(x, y))
	if empties.is_empty():
		return false
	var cell: Vector2i = empties[randi() % empties.size()]
	grid[cell.y][cell.x] = FROZEN
	return true


func _process_freeze_threshold() -> void:
	while score >= next_freeze_score and _frozen_count() < MAX_FROZEN:
		if not _freeze_random_cell():
			break
		next_freeze_score += FREEZE_SCORE_INTERVAL


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
			var result: Dictionary = _process_line_with_barriers(row)
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
			var result: Dictionary = _process_line_with_barriers(col)
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
		_process_freeze_threshold()
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
			if grid[y][x] == WILDCARD:
				return false
			if x + 1 < GRID_SIZE and _can_merge(grid[y][x], grid[y][x + 1]):
				return false
			if y + 1 < GRID_SIZE and _can_merge(grid[y][x], grid[y + 1][x]):
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
