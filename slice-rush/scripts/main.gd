extends Node2D

# Slice Rush — a drag-to-slice reflex game (deferred back in round 1's
# research notes as "Fruit-slice... good candidate"). Shapes toss upward
# from the bottom in an arc and fall back down under gravity; drag a
# continuous stroke through them to slice. A free-form continuous drag
# through moving, physically-arcing targets — distinct from Loop It's
# drag-trace (which connects fixed grid dots in order) and from every
# discrete-tap game in the studio.

const GRAVITY := 900.0
const RADIUS := 34.0
const BOMB_CHANCE := 0.16
const BASE_SPAWN_INTERVAL := 1.05
const MIN_SPAWN_INTERVAL := 0.5
const SPAWN_INTERVAL_DECAY := 0.02
const MAX_STRIKES := 3
const LAUNCH_Y := 940.0
const LAUNCH_VX_RANGE := 110.0
const LAUNCH_VY_MIN := -780.0
const LAUNCH_VY_MAX := -920.0
const FALL_Y_LIMIT := 1010.0
const SAVE_PATH := "user://slicerush_highscore.cfg"

const BOMB_COLOR := Color(0.12, 0.12, 0.14, 1.0)
const TRAIL_LIFE := 0.18

const SHAPE_HUE_STEPS := 6
const SHAPE_SATURATION := 0.7
const SHAPE_VALUE := 0.9

@onready var shapes_container: Node2D = $ShapesContainer
@onready var trail_line: Line2D = $TrailLine
@onready var score_label: Label = $ScoreLabel
@onready var strikes_label: Label = $StrikesLabel
@onready var ready_overlay: ColorRect = $ReadyOverlay
@onready var game_over_overlay: ColorRect = $GameOverOverlay
@onready var game_over_score_label: Label = $GameOverOverlay/GameOverScore

var shapes: Array = []
var trail_points: Array = []
var last_drag_pos: Vector2 = Vector2.INF
var spawn_timer: float = 0.0
var spawn_interval: float = BASE_SPAWN_INTERVAL
var color_cycle: int = 0

var score: int = 0
var high_score: int = 0
var strikes: int = MAX_STRIKES
var game_over: bool = false
var game_started: bool = false


func _ready() -> void:
	_load_high_score()
	_start_game()


func _start_game() -> void:
	for s in shapes:
		if is_instance_valid(s["node"]):
			s["node"].queue_free()
	shapes.clear()
	trail_points.clear()
	trail_line.points = PackedVector2Array()
	last_drag_pos = Vector2.INF
	spawn_timer = 0.5
	spawn_interval = BASE_SPAWN_INTERVAL
	score = 0
	strikes = MAX_STRIKES
	game_over = false
	game_started = false
	score_label.text = "0"
	_update_strikes_label()
	game_over_overlay.visible = false
	ready_overlay.visible = true


func _circle_points(radius: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a: float = i * TAU / segments
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts


func _spawn_shape() -> void:
	var is_bomb: bool = randf() < BOMB_CHANCE
	var x: float = randf_range(120.0, 420.0)
	var vel := Vector2(randf_range(-LAUNCH_VX_RANGE, LAUNCH_VX_RANGE), randf_range(LAUNCH_VY_MAX, LAUNCH_VY_MIN))

	var node := Polygon2D.new()
	node.polygon = _circle_points(RADIUS, 20)
	if is_bomb:
		node.color = BOMB_COLOR
	else:
		var hue: float = fmod(float(color_cycle) / float(SHAPE_HUE_STEPS), 1.0)
		node.color = Color.from_hsv(hue, SHAPE_SATURATION, SHAPE_VALUE, 1.0)
		color_cycle += 1
	node.position = Vector2(x, LAUNCH_Y)
	shapes_container.add_child(node)

	shapes.append({"pos": Vector2(x, LAUNCH_Y), "vel": vel, "is_bomb": is_bomb, "node": node, "sliced": false})


func _process(delta: float) -> void:
	_update_trail(delta)

	if game_over or not game_started:
		return

	spawn_timer -= delta
	if spawn_timer <= 0.0:
		_spawn_shape()
		spawn_interval = max(MIN_SPAWN_INTERVAL, spawn_interval - SPAWN_INTERVAL_DECAY)
		spawn_timer = spawn_interval

	var still: Array = []
	for s in shapes:
		s["vel"].y += GRAVITY * delta
		s["pos"] += s["vel"] * delta
		s["node"].position = s["pos"]

		if s["pos"].y > FALL_Y_LIMIT:
			s["node"].queue_free()
			if not s["is_bomb"]:
				_on_miss()
			if game_over:
				return
		else:
			still.append(s)
	shapes = still


func _update_trail(delta: float) -> void:
	var still: Array = []
	for p in trail_points:
		p["life"] -= delta
		if p["life"] > 0.0:
			still.append(p)
	trail_points = still
	var pts := PackedVector2Array()
	for p in trail_points:
		pts.append(p["pos"])
	trail_line.points = pts


func _input(event: InputEvent) -> void:
	var pos: Vector2
	var pressed := false
	var released := false
	var dragging := false

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventScreenTouch:
		pos = event.position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		pos = event.position
		dragging = true
	elif event is InputEventScreenDrag:
		pos = event.position
		dragging = true
	else:
		return

	if pressed:
		if not game_started:
			game_started = true
			ready_overlay.visible = false
			return
		if game_over:
			_start_game()
			return
		last_drag_pos = pos
		return

	if released:
		last_drag_pos = Vector2.INF
		return

	if dragging:
		if not game_started or game_over:
			return
		trail_points.append({"pos": pos, "life": TRAIL_LIFE})
		if last_drag_pos != Vector2.INF:
			_check_slice(last_drag_pos, pos)
		last_drag_pos = pos


func _check_slice(from: Vector2, to: Vector2) -> void:
	var hit: Array = []
	for s in shapes.duplicate():
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(s["pos"], from, to)
		if s["pos"].distance_to(closest) <= RADIUS:
			hit.append(s)

	for s in hit:
		_slice_shape(s)
		if game_over:
			return


func _slice_shape(s: Dictionary) -> void:
	if is_instance_valid(s["node"]):
		s["node"].queue_free()
	shapes.erase(s)

	if s["is_bomb"]:
		_trigger_game_over()
		return

	score += 1
	score_label.text = str(score)


func _on_miss() -> void:
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
