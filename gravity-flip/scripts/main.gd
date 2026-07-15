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

@onready var player: ColorRect = $Player
@onready var obstacles_container: Node2D = $ObstaclesContainer
@onready var score_label: Label = $ScoreLabel
@onready var ready_overlay: ColorRect = $ReadyOverlay
@onready var game_over_overlay: ColorRect = $GameOverOverlay
@onready var game_over_score_label: Label = $GameOverOverlay/GameOverScore

var player_y: float = CORRIDOR_MID
var vel_y: float = 0.0
var gravity_dir: int = 1

var world_offset: float = 0.0
var next_spawn_world_x: float = 600.0
var obstacles: Array = []

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

	player_y = CORRIDOR_MID
	vel_y = 0.0
	gravity_dir = 1
	world_offset = 0.0
	next_spawn_world_x = 600.0
	score = 0
	game_over = false
	game_started = false
	score_label.text = "0"
	game_over_overlay.visible = false
	ready_overlay.visible = true
	player.position = Vector2(PLAYER_X - PLAYER_SIZE / 2.0, player_y - PLAYER_SIZE / 2.0)


func _process(delta: float) -> void:
	if game_over or not game_started:
		return

	var scroll_speed: float = min(MAX_SCROLL_SPEED, BASE_SCROLL_SPEED + score * SCROLL_SPEED_GROWTH)
	world_offset += scroll_speed * delta

	vel_y += gravity_dir * GRAVITY * delta
	vel_y = clamp(vel_y, -MAX_FALL_SPEED, MAX_FALL_SPEED)
	player_y += vel_y * delta
	player_y = clamp(player_y, CEILING_Y + PLAYER_SIZE / 2.0, FLOOR_Y - PLAYER_SIZE / 2.0)
	player.position = Vector2(PLAYER_X - PLAYER_SIZE / 2.0, player_y - PLAYER_SIZE / 2.0)

	_update_spawning()
	_update_obstacles()


func _update_spawning() -> void:
	while next_spawn_world_x - world_offset < SPAWN_LOOKAHEAD:
		_spawn_obstacle(next_spawn_world_x)
		var spacing: float = max(MIN_SPACING, BASE_SPACING - score * SPACING_DECAY)
		next_spawn_world_x += spacing


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

		if not o["passed"] and screen_x + OBSTACLE_WIDTH < PLAYER_X - PLAYER_SIZE / 2.0:
			o["passed"] = true
			score += 1
			score_label.text = str(score)

		if _check_collision(o, screen_x):
			_trigger_game_over()

		if screen_x + OBSTACLE_WIDTH < -50.0:
			o["node"].queue_free()
		else:
			still.append(o)
	obstacles = still


func _check_collision(o: Dictionary, screen_x: float) -> bool:
	var player_left: float = PLAYER_X - PLAYER_SIZE / 2.0
	var player_right: float = PLAYER_X + PLAYER_SIZE / 2.0
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
