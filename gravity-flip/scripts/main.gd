extends Node2D

# Gravity Flip — a one-button endless dodge runner. The world scrolls past
# at a fixed X; tap/space flips which way gravity pulls the player. Time the
# flip to be on the open side (ceiling gap vs floor gap) of each obstacle.
# One hit ends the run — the genre's defining instant-fail convention,
# deliberately different from the 3-strike pattern used elsewhere in the
# studio.

const CEILING_Y := 80.0
const FLOOR_Y := 460.0
const CORRIDOR_MID := (CEILING_Y + FLOOR_Y) / 2.0

const PLAYER_X := 150.0
const PLAYER_SIZE := 40.0
const GRAVITY := 1800.0
const FLIP_KICK := 320.0
const MAX_FALL_SPEED := 900.0

const OBSTACLE_WIDTH := 60.0
const HALF_HEIGHT := (FLOOR_Y - CEILING_Y) / 2.0
const BASE_SPACING := 340.0
const MIN_SPACING := 220.0
const SPACING_DECAY := 3.0
const SPAWN_LOOKAHEAD := 700.0
const BASE_SCROLL_SPEED := 220.0
const MAX_SCROLL_SPEED := 500.0
const SCROLL_SPEED_GROWTH := 4.0

const SAVE_PATH := "user://gravityflip_highscore.cfg"
const OBSTACLE_COLOR := Color(0.95, 0.32, 0.12, 1.0)

# Novelty twist: floating coins collectible anywhere in the corridor for
# bonus score — a collectible-pickup mechanism (the natural fit for an
# endless runner), kept separate from the obstacle-pass count so it never
# distorts the difficulty ramp (which still scales off obstacles cleared).
const COIN_RADIUS := 14.0
const COIN_SCORE := 2
const COIN_SPACING := 260.0
const COIN_SPAWN_CHANCE := 0.6
const COIN_COLOR := Color(0.93, 0.76, 0.15, 1.0)

# Structural addition: a rotating gravity axis. Gravity no longer pulls
# along a fixed vertical line — its axis slowly oscillates a few degrees
# off true vertical (a sine sweep, not a one-off event), which does two
# things: it slightly scales the vertical pull (cos of the tilt) and it
# sways the player's effective X position within a bounded range. Dodge
# timing now depends on where the rotating axis currently has the player
# sitting in X, not just their Y position in the corridor.
const GRAVITY_TILT_MAX := deg_to_rad(20)
const GRAVITY_TILT_PERIOD := 6.0
const LATERAL_MAX := 30.0

@onready var player: ColorRect = $Player
@onready var gravity_arrow: Polygon2D = $Player/GravityArrow
@onready var obstacles_container: Node2D = $ObstaclesContainer
@onready var coins_container: Node2D = $CoinsContainer
@onready var score_label: Label = $ScoreLabel
@onready var ready_overlay: ColorRect = $ReadyOverlay
@onready var game_over_overlay: ColorRect = $GameOverOverlay
@onready var game_over_score_label: Label = $GameOverOverlay/GameOverScore

var player_y: float = CORRIDOR_MID
var vel_y: float = 0.0
var gravity_dir: int = 1
var gravity_tilt_time: float = 0.0
var gravity_angle: float = 0.0
var lateral_offset: float = 0.0
var effective_player_x: float = PLAYER_X

var world_offset: float = 0.0
var next_spawn_world_x: float = 600.0
var next_coin_world_x: float = 850.0
var obstacles: Array = []
var coins: Array = []
var coin_score: int = 0

var score: int = 0
var high_score: int = 0
var game_over: bool = false
var game_started: bool = false


func _ready() -> void:
	_load_high_score()
	_start_game()


func _start_game() -> void:
	for o in obstacles:
		if is_instance_valid(o["node"]):
			o["node"].queue_free()
	obstacles.clear()
	for c in coins:
		if is_instance_valid(c["node"]):
			c["node"].queue_free()
	coins.clear()

	player_y = CORRIDOR_MID
	vel_y = 0.0
	gravity_dir = 1
	gravity_tilt_time = 0.0
	gravity_angle = 0.0
	lateral_offset = 0.0
	effective_player_x = PLAYER_X
	world_offset = 0.0
	next_spawn_world_x = 600.0
	next_coin_world_x = 850.0
	score = 0
	coin_score = 0
	game_over = false
	game_started = false
	score_label.text = "0"
	game_over_overlay.visible = false
	ready_overlay.visible = true
	player.position = Vector2(effective_player_x - PLAYER_SIZE / 2.0, player_y - PLAYER_SIZE / 2.0)
	gravity_arrow.rotation = 0.0


func _total_score() -> int:
	return score + coin_score


func _process(delta: float) -> void:
	if game_over or not game_started:
		return

	var scroll_speed: float = min(MAX_SCROLL_SPEED, BASE_SCROLL_SPEED + score * SCROLL_SPEED_GROWTH)
	world_offset += scroll_speed * delta

	gravity_tilt_time += delta
	var phase: float = sin(TAU * gravity_tilt_time / GRAVITY_TILT_PERIOD)
	gravity_angle = GRAVITY_TILT_MAX * phase
	lateral_offset = LATERAL_MAX * phase
	effective_player_x = PLAYER_X + lateral_offset

	vel_y += gravity_dir * GRAVITY * cos(gravity_angle) * delta
	vel_y = clamp(vel_y, -MAX_FALL_SPEED, MAX_FALL_SPEED)
	player_y += vel_y * delta
	player_y = clamp(player_y, CEILING_Y + PLAYER_SIZE / 2.0, FLOOR_Y - PLAYER_SIZE / 2.0)
	player.position = Vector2(effective_player_x - PLAYER_SIZE / 2.0, player_y - PLAYER_SIZE / 2.0)
	# QoL: the arrow always points the way gravity is currently pulling, so
	# a flip reads instantly instead of only being inferable from motion.
	gravity_arrow.rotation = gravity_angle if gravity_dir == 1 else PI - gravity_angle

	_update_spawning()
	_update_obstacles()
	_update_coin_spawning()
	_update_coins()


func _update_spawning() -> void:
	while next_spawn_world_x - world_offset < SPAWN_LOOKAHEAD:
		_spawn_obstacle(next_spawn_world_x)
		var spacing: float = max(MIN_SPACING, BASE_SPACING - score * SPACING_DECAY)
		next_spawn_world_x += spacing


func _update_coin_spawning() -> void:
	while next_coin_world_x - world_offset < SPAWN_LOOKAHEAD:
		if randf() < COIN_SPAWN_CHANCE:
			_spawn_coin(next_coin_world_x)
		next_coin_world_x += COIN_SPACING


func _spawn_coin(world_x: float) -> void:
	var y: float = randf_range(CEILING_Y + 40.0, FLOOR_Y - 40.0)
	var node := Polygon2D.new()
	node.polygon = _coin_circle_points(COIN_RADIUS)
	node.color = COIN_COLOR
	coins_container.add_child(node)
	coins.append({"world_x": world_x, "y": y, "node": node, "collected": false})


func _coin_circle_points(radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(12):
		var a: float = i * TAU / 12.0
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts


func _update_coins() -> void:
	var still: Array = []
	for c in coins:
		var screen_x: float = c["world_x"] - world_offset
		c["node"].position = Vector2(screen_x, c["y"])

		if not c["collected"]:
			var dist: float = Vector2(screen_x - effective_player_x, c["y"] - player_y).length()
			if dist < COIN_RADIUS + PLAYER_SIZE / 2.0:
				c["collected"] = true
				coin_score += COIN_SCORE
				score_label.text = str(_total_score())

		if c["collected"] or screen_x < -50.0:
			c["node"].queue_free()
		else:
			still.append(c)
	coins = still


func _spawn_obstacle(world_x: float) -> void:
	var side: String = "TOP" if randf() < 0.5 else "BOTTOM"
	var node := ColorRect.new()
	node.size = Vector2(OBSTACLE_WIDTH, HALF_HEIGHT)
	node.color = OBSTACLE_COLOR
	node.position.y = CEILING_Y if side == "TOP" else CORRIDOR_MID
	obstacles_container.add_child(node)
	obstacles.append({"world_x": world_x, "side": side, "node": node, "passed": false})


func _update_obstacles() -> void:
	var still: Array = []
	for o in obstacles:
		var screen_x: float = o["world_x"] - world_offset
		o["node"].position.x = screen_x

		if not o["passed"] and screen_x + OBSTACLE_WIDTH < effective_player_x - PLAYER_SIZE / 2.0:
			o["passed"] = true
			score += 1
			score_label.text = str(_total_score())

		if _check_collision(o, screen_x):
			_trigger_game_over()

		if screen_x + OBSTACLE_WIDTH < -50.0:
			o["node"].queue_free()
		else:
			still.append(o)
	obstacles = still


func _check_collision(o: Dictionary, screen_x: float) -> bool:
	var player_left: float = effective_player_x - PLAYER_SIZE / 2.0
	var player_right: float = effective_player_x + PLAYER_SIZE / 2.0
	var obstacle_right: float = screen_x + OBSTACLE_WIDTH
	if obstacle_right < player_left or screen_x > player_right:
		return false
	if o["side"] == "TOP":
		return player_y - PLAYER_SIZE / 2.0 <= CORRIDOR_MID
	else:
		return player_y + PLAYER_SIZE / 2.0 >= CORRIDOR_MID


func _input(event: InputEvent) -> void:
	var tapped := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped = true
	elif event is InputEventScreenTouch and event.pressed:
		tapped = true
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		tapped = true

	if not tapped:
		return

	if not game_started:
		game_started = true
		ready_overlay.visible = false
		return
	if game_over:
		_start_game()
		return

	gravity_dir *= -1
	vel_y = gravity_dir * FLIP_KICK


func _trigger_game_over() -> void:
	if game_over:
		return
	game_over = true
	var total: int = _total_score()
	if total > high_score:
		high_score = total
		_save_high_score()
	game_over_score_label.text = "Score: %d  Best: %d" % [total, high_score]
	game_over_overlay.visible = true


func _load_high_score() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		high_score = int(cfg.get_value("scores", "high_score", 0))


func _save_high_score() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("scores", "high_score", high_score)
	cfg.save(SAVE_PATH)
