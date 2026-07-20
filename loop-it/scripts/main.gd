extends Node2D

# Loop It — a genuinely different genre for this studio: a drag-to-trace
# planning puzzle instead of a reaction/timing game. Draw one continuous
# line through every dot on the grid (up/down/left/right moves only, no
# revisiting a dot) before the timer runs out. Grid size grows with score.

const MIN_GRID := 3
const MAX_GRID := 6
const DOT_SPACING := 80.0
const DOT_RADIUS := 14.0
const HIT_RADIUS := 38.0
const GRID_TOP := 260.0
const BASE_TIME_PER_DOT := 1.3
const MIN_TIME_PER_DOT := 0.7
const TIME_DECAY_PER_SCORE := 0.02
const MAX_STRIKES := 3
const TIMER_BAR_MAX_WIDTH := 500.0
const SAVE_PATH := "user://loopit_highscore.cfg"

# Novelty twist: solving with time to spare is worth a bonus point — a
# skill-based scoring condition rather than a new object/pickup, rewarding
# players who plan the route instead of hunting for it dot-by-dot.
const SPEED_BONUS_TIME_FRACTION := 0.5
const SPEED_BONUS_SCORE := 1

const DOT_COLOR := Color(0.3, 0.32, 0.38, 1.0)
const DOT_VISITED_COLOR := Color(0.2, 0.55, 0.85, 1.0)

# Structural addition: wall dots. Some rounds block off a chunk of the
# grid entirely (rendered as square wall markers) — the line has to trace
# every REMAINING dot, and the playable shape changes round to round
# instead of always being the full rectangle. Solvability is guaranteed by
# construction (same technique as Color Sort/Number Slide): generate a
# full zigzag Hamiltonian ordering of the grid, then block a random-length
# SUFFIX of that ordering — removing the tail of a path always leaves the
# remaining prefix itself traceable in one continuous line.
const WALL_CHANCE_PER_ROUND := 0.6
const MAX_WALL_FRACTION := 0.3
const MIN_PLAYABLE_DOTS := 4
const WALL_COLOR := Color(0.75, 0.35, 0.25, 1.0)
const WALL_SIZE := 32.0

# Novel element: Bonus Dot finale. Some rounds mark one dot gold — finish
# your stroke there (visit it LAST) for bonus score. It's a pure order
# constraint layered on top of the existing "visit every dot" rule: no
# penalty for ignoring it, just an extra incentive to plan the route so
# the gold dot is the very last stop.
const FINALE_CHANCE := 0.35
const FINALE_BONUS_SCORE := 2
const FINALE_DOT_COLOR := Color(0.93, 0.76, 0.15, 1.0)
var finale_cell: Vector2i = Vector2i(-1, -1)

@onready var score_label: Label = $ScoreLabel
@onready var strikes_label: Label = $StrikesLabel
@onready var timer_bar_fill: ColorRect = $TimerBarFill
@onready var path_line: Line2D = $PathLine
@onready var dots_container: Node2D = $DotsContainer
@onready var ready_overlay: ColorRect = $ReadyOverlay
@onready var game_over_overlay: ColorRect = $GameOverOverlay
@onready var game_over_score_label: Label = $GameOverOverlay/GameOverScore
@onready var miss_flash_label: Label = $MissFlashLabel
@onready var bonus_flash_label: Label = $BonusFlashLabel
var bonus_flash_timer: float = 0.0

var grid_size: int = MIN_GRID
var dot_nodes: Dictionary = {}
var path: Array = []
var dragging: bool = false
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
	score = 0
	strikes = MAX_STRIKES
	game_over = false
	game_started = false
	score_label.text = "0"
	_update_strikes_label()
	bonus_flash_label.visible = false
	bonus_flash_timer = 0.0
	game_over_overlay.visible = false
	ready_overlay.visible = true
	_new_round()


func _generate_snake_order() -> Array:
	var order: Array = []
	var row_major: bool = randf() < 0.5
	for i in range(grid_size):
		var coords: Array = []
		for j in range(grid_size):
			coords.append(j)
		if i % 2 == 1:
			coords.reverse()
		for j in coords:
			if row_major:
				order.append(Vector2i(j, i))
			else:
				order.append(Vector2i(i, j))
	return order


func _new_round() -> void:
	grid_size = clamp(MIN_GRID + score / 3, MIN_GRID, MAX_GRID)
	path.clear()
	dragging = false
	path_line.points = PackedVector2Array()

	var order: Array = _generate_snake_order()
	var total: int = order.size()
	var wall_count := 0
	if randf() < WALL_CHANCE_PER_ROUND:
		wall_count = int(round(randf_range(0.1, MAX_WALL_FRACTION) * total))
	wall_count = min(wall_count, total - MIN_PLAYABLE_DOTS)

	var blocked_cells: Dictionary = {}
	for i in range(total - wall_count, total):
		blocked_cells[order[i]] = true

	_build_dots(blocked_cells)

	finale_cell = Vector2i(-1, -1)
	if dot_nodes.size() >= MIN_PLAYABLE_DOTS and randf() < FINALE_CHANCE:
		var keys: Array = dot_nodes.keys()
		finale_cell = keys[randi() % keys.size()]
		dot_nodes[finale_cell].color = FINALE_DOT_COLOR

	var num_dots: int = dot_nodes.size()
	var per_dot_time: float = max(MIN_TIME_PER_DOT, BASE_TIME_PER_DOT - score * TIME_DECAY_PER_SCORE)
	time_limit = num_dots * per_dot_time
	time_left = time_limit


func _grid_origin() -> Vector2:
	var total_w: float = (grid_size - 1) * DOT_SPACING
	return Vector2((540.0 - total_w) / 2.0, GRID_TOP)


func _dot_screen_pos(cell: Vector2i) -> Vector2:
	return _grid_origin() + Vector2(cell.x * DOT_SPACING, cell.y * DOT_SPACING)


func _build_dots(blocked_cells: Dictionary) -> void:
	for c in dots_container.get_children():
		c.queue_free()
	dot_nodes.clear()

	for y in range(grid_size):
		for x in range(grid_size):
			var cell := Vector2i(x, y)
			if blocked_cells.has(cell):
				var wall := Polygon2D.new()
				var hw: float = WALL_SIZE / 2.0
				wall.polygon = PackedVector2Array([Vector2(-hw, -hw), Vector2(hw, -hw), Vector2(hw, hw), Vector2(-hw, hw)])
				wall.position = _dot_screen_pos(cell)
				wall.color = WALL_COLOR
				dots_container.add_child(wall)
				continue

			var dot := Polygon2D.new()
			dot.polygon = _circle_points(DOT_RADIUS, 16)
			dot.position = _dot_screen_pos(cell)
			dot.color = DOT_COLOR
			dots_container.add_child(dot)
			dot_nodes[cell] = dot


func _circle_points(radius: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a: float = i * TAU / segments
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts


func _process(delta: float) -> void:
	if miss_flash_timer > 0.0:
		miss_flash_timer -= delta
		if miss_flash_timer <= 0.0:
			miss_flash_label.visible = false

	if bonus_flash_timer > 0.0:
		bonus_flash_timer -= delta
		if bonus_flash_timer <= 0.0:
			bonus_flash_label.visible = false

	if game_over or not game_started:
		return
	time_left -= delta
	var ratio: float = clamp(time_left / time_limit, 0.0, 1.0)
	timer_bar_fill.size.x = TIMER_BAR_MAX_WIDTH * ratio
	if time_left <= 0.0:
		_on_timeout()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_on_press(Vector2(-1000, -1000))
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_press(event.position)
		else:
			_on_release()
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			_on_press(event.position)
		else:
			_on_release()
		return

	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_on_drag(event.position)
		return

	if event is InputEventScreenDrag:
		_on_drag(event.position)


func _on_press(pos: Vector2) -> void:
	if not game_started:
		game_started = true
		ready_overlay.visible = false
		return
	if game_over:
		_start_game()
		return

	var cell: Vector2i = _nearest_dot(pos)
	if cell != Vector2i(-1, -1):
		dragging = true
		path = [cell]
		_mark_visited(cell)
		_redraw_path()


func _on_drag(pos: Vector2) -> void:
	if not dragging or game_over or not game_started:
		return
	var cell: Vector2i = _nearest_dot(pos)
	if cell == Vector2i(-1, -1):
		return
	if path.back() == cell or path.has(cell):
		return
	if not _is_adjacent(path.back(), cell):
		return

	path.append(cell)
	_mark_visited(cell)
	_redraw_path()

	if path.size() == dot_nodes.size():
		_on_round_won()


func _on_release() -> void:
	dragging = false
	if game_over or not game_started:
		return
	if path.size() > 0 and path.size() < dot_nodes.size():
		path.clear()
		_reset_dot_colors()
		_redraw_path()


func _nearest_dot(pos: Vector2) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d: float = HIT_RADIUS
	for cell in dot_nodes.keys():
		var d: float = dot_nodes[cell].position.distance_to(pos)
		if d <= best_d:
			best_d = d
			best = cell
	return best


func _is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return abs(a.x - b.x) + abs(a.y - b.y) == 1


func _mark_visited(cell: Vector2i) -> void:
	dot_nodes[cell].color = DOT_VISITED_COLOR


func _reset_dot_colors() -> void:
	for cell in dot_nodes.keys():
		dot_nodes[cell].color = DOT_COLOR


func _redraw_path() -> void:
	var pts := PackedVector2Array()
	for cell in path:
		pts.append(dot_nodes[cell].position)
	path_line.points = pts


func _on_round_won() -> void:
	score += 1
	var bonus_texts: Array = []
	if time_left >= time_limit * SPEED_BONUS_TIME_FRACTION:
		score += SPEED_BONUS_SCORE
		bonus_texts.append("SPEED +%d" % SPEED_BONUS_SCORE)
	if finale_cell != Vector2i(-1, -1) and not path.is_empty() and path.back() == finale_cell:
		score += FINALE_BONUS_SCORE
		bonus_texts.append("FINALE +%d" % FINALE_BONUS_SCORE)
	if not bonus_texts.is_empty():
		bonus_flash_label.text = " / ".join(bonus_texts)
		bonus_flash_label.visible = true
		bonus_flash_timer = 0.9
	score_label.text = str(score)
	_new_round()


func _on_timeout() -> void:
	strikes -= 1
	_update_strikes_label()
	miss_flash_label.text = "TIME UP!"
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
