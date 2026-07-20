extends Node2D

# Orb Burst — an aim-and-launch match game. Tap where you want to shoot;
# the orb flies straight there (bouncing off side walls) and snaps into
# the nearest open slot in a staggered grid above. 3+ connected orbs of
# the same color pop, and anything left disconnected from the ceiling
# drops away as a bonus. Distinct control (aim + commit a shot) and
# distinct objective (clear a shrinking-headroom cluster) from every
# other game in the studio.

const GRID_COLS := 8
const ORB_RADIUS := 28.0
const ROW_HEIGHT := ORB_RADIUS * 1.75
const GRID_TOP := 90.0
const NUM_COLORS := 5
const INITIAL_ROWS := 5
const DANGER_ROW := 13
const SHOTS_PER_DROP := 5
const POP_SCORE_PER_ORB := 10
const DROP_SCORE_PER_ORB := 15

const LAUNCHER_POS := Vector2(270.0, 860.0)
const FIRE_SPEED := 620.0
const AIM_MIN := -PI * 0.94
const AIM_MAX := -PI * 0.06

const SAVE_PATH := "user://orbburst_highscore.cfg"

const ORB_HUE_STEPS := NUM_COLORS
const ORB_SATURATION := 0.72
const ORB_VALUE := 0.9
const LAUNCHER_COLOR := Color(0.7, 0.72, 0.78, 1.0)

@onready var grid_container: Node2D = $GridContainer
@onready var launcher: Polygon2D = $Launcher
@onready var travel_orb: Polygon2D = $TravelOrb
@onready var score_label: Label = $ScoreLabel
@onready var ready_overlay: ColorRect = $ReadyOverlay
@onready var game_over_overlay: ColorRect = $GameOverOverlay
@onready var game_over_score_label: Label = $GameOverOverlay/GameOverScore

var grid: Dictionary = {}
var grid_left: float = 0.0
var traveling_active: bool = false
var travel_pos: Vector2 = Vector2.ZERO
var travel_vel: Vector2 = Vector2.ZERO
var travel_color: int = 0
var next_color: int = 0
var shots_fired: int = 0

var score: int = 0
var high_score: int = 0
var game_over: bool = false
var game_started: bool = false


func _ready() -> void:
	grid_left = (540.0 - GRID_COLS * ORB_RADIUS * 2.0) / 2.0
	launcher.polygon = _circle_points(20.0, 14)
	launcher.color = LAUNCHER_COLOR
	launcher.position = LAUNCHER_POS
	_load_high_score()
	_start_game()


func _circle_points(radius: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a: float = i * TAU / segments
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts


func _orb_color(id: int) -> Color:
	var hue: float = fmod(float(id) / float(ORB_HUE_STEPS), 1.0)
	return Color.from_hsv(hue, ORB_SATURATION, ORB_VALUE, 1.0)


func _start_game() -> void:
	score = 0
	game_over = false
	game_started = false
	shots_fired = 0
	traveling_active = false
	travel_orb.visible = false
	score_label.text = "0"
	game_over_overlay.visible = false
	ready_overlay.visible = true
	_generate_initial_grid()
	next_color = randi() % NUM_COLORS
	_redraw_grid()


func _row_col_count(row: int) -> int:
	return GRID_COLS - 1 if row % 2 == 1 else GRID_COLS


func _generate_initial_grid() -> void:
	grid.clear()
	for row in range(INITIAL_ROWS):
		for col in range(_row_col_count(row)):
			grid[Vector2i(col, row)] = randi() % NUM_COLORS


func _cell_to_pixel(cell: Vector2i) -> Vector2:
	var x_off: float = ORB_RADIUS if cell.y % 2 == 1 else 0.0
	var x: float = grid_left + cell.x * (ORB_RADIUS * 2.0) + x_off + ORB_RADIUS
	var y: float = GRID_TOP + cell.y * ROW_HEIGHT + ORB_RADIUS
	return Vector2(x, y)


func _neighbors(cell: Vector2i) -> Array:
	var col: int = cell.x
	var row: int = cell.y
	var result: Array = [Vector2i(col - 1, row), Vector2i(col + 1, row)]
	if row % 2 == 0:
		result.append(Vector2i(col - 1, row - 1))
		result.append(Vector2i(col, row - 1))
		result.append(Vector2i(col - 1, row + 1))
		result.append(Vector2i(col, row + 1))
	else:
		result.append(Vector2i(col, row - 1))
		result.append(Vector2i(col + 1, row - 1))
		result.append(Vector2i(col, row + 1))
		result.append(Vector2i(col + 1, row + 1))
	return result


func _grid_cell_for_pixel(pos: Vector2) -> Vector2i:
	var approx_row: int = int(round((pos.y - GRID_TOP - ORB_RADIUS) / ROW_HEIGHT))
	var best_cell := Vector2i(0, max(approx_row, 0))
	var best_dist: float = INF
	for row in range(max(approx_row - 1, 0), approx_row + 2):
		var x_off: float = ORB_RADIUS if row % 2 == 1 else 0.0
		var approx_col: int = int(round((pos.x - grid_left - x_off - ORB_RADIUS) / (ORB_RADIUS * 2.0)))
		for col in range(approx_col - 1, approx_col + 2):
			var candidate := Vector2i(col, row)
			var d: float = _cell_to_pixel(candidate).distance_to(pos)
			if d < best_dist:
				best_dist = d
				best_cell = candidate
	return best_cell


func _nearest_empty_cell(start: Vector2i) -> Vector2i:
	if not grid.has(start):
		return start
	var visited: Dictionary = {start: true}
	var queue: Array = [start]
	var qi := 0
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		for n in _neighbors(cur):
			if visited.has(n):
				continue
			visited[n] = true
			if n.x >= 0 and n.y >= 0 and not grid.has(n):
				return n
			queue.append(n)
	return start


func _find_match_group(start: Vector2i) -> Array:
	if not grid.has(start):
		return []
	var color: int = grid[start]
	var visited: Dictionary = {start: true}
	var queue: Array = [start]
	var qi := 0
	var group: Array = [start]
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		for n in _neighbors(cur):
			if visited.has(n):
				continue
			visited[n] = true
			if grid.has(n) and grid[n] == color:
				group.append(n)
				queue.append(n)
	return group


func _find_floating_cells() -> Array:
	var reachable: Dictionary = {}
	var queue: Array = []
	for col in range(GRID_COLS):
		var c := Vector2i(col, 0)
		if grid.has(c):
			reachable[c] = true
			queue.append(c)
	var qi := 0
	while qi < queue.size():
		var cur: Vector2i = queue[qi]
		qi += 1
		for n in _neighbors(cur):
			if grid.has(n) and not reachable.has(n):
				reachable[n] = true
				queue.append(n)
	var floating: Array = []
	for cell in grid.keys():
		if not reachable.has(cell):
			floating.append(cell)
	return floating


func _redraw_grid() -> void:
	for c in grid_container.get_children():
		c.queue_free()
	for cell in grid.keys():
		var node := Polygon2D.new()
		node.polygon = _circle_points(ORB_RADIUS - 2.0, 16)
		node.position = _cell_to_pixel(cell)
		node.color = _orb_color(grid[cell])
		grid_container.add_child(node)


func _launch_orb(angle: float) -> void:
	traveling_active = true
	travel_pos = LAUNCHER_POS
	travel_vel = Vector2(cos(angle), sin(angle)) * FIRE_SPEED
	travel_color = next_color
	travel_orb.polygon = _circle_points(ORB_RADIUS - 2.0, 16)
	travel_orb.color = _orb_color(travel_color)
	travel_orb.position = travel_pos
	travel_orb.visible = true
	shots_fired += 1
	next_color = randi() % NUM_COLORS


func _process(delta: float) -> void:
	if game_over or not game_started or not traveling_active:
		return

	travel_pos += travel_vel * delta
	if travel_pos.x - ORB_RADIUS < 0.0:
		travel_pos.x = ORB_RADIUS
		travel_vel.x = abs(travel_vel.x)
	elif travel_pos.x + ORB_RADIUS > 540.0:
		travel_pos.x = 540.0 - ORB_RADIUS
		travel_vel.x = -abs(travel_vel.x)
	travel_orb.position = travel_pos

	var collided := travel_pos.y - ORB_RADIUS <= GRID_TOP
	if not collided:
		for cell in grid.keys():
			if travel_pos.distance_to(_cell_to_pixel(cell)) < ORB_RADIUS * 2.0:
				collided = true
				break

	if collided:
		_settle_travel_orb()


func _settle_travel_orb() -> void:
	traveling_active = false
	travel_orb.visible = false

	var snap_cell: Vector2i = _grid_cell_for_pixel(travel_pos)
	if grid.has(snap_cell):
		snap_cell = _nearest_empty_cell(snap_cell)
	grid[snap_cell] = travel_color

	var group: Array = _find_match_group(snap_cell)
	if group.size() >= 3:
		for c in group:
			grid.erase(c)
		score += group.size() * POP_SCORE_PER_ORB
		var floating: Array = _find_floating_cells()
		for c in floating:
			grid.erase(c)
		score += floating.size() * DROP_SCORE_PER_ORB
		score_label.text = str(score)

	if shots_fired % SHOTS_PER_DROP == 0:
		_shift_grid_down()

	_check_danger()
	_redraw_grid()


func _shift_grid_down() -> void:
	var new_grid: Dictionary = {}
	for cell in grid.keys():
		new_grid[Vector2i(cell.x, cell.y + 1)] = grid[cell]
	for col in range(GRID_COLS):
		new_grid[Vector2i(col, 0)] = randi() % NUM_COLORS
	grid = new_grid


func _check_danger() -> void:
	for cell in grid.keys():
		if cell.y >= DANGER_ROW:
			_trigger_game_over()
			return


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
	if traveling_active:
		return

	var angle: float = clamp((pos - LAUNCHER_POS).angle(), AIM_MIN, AIM_MAX)
	_launch_orb(angle)


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
