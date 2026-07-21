class_name GameManager
extends Node3D

signal food_eaten(score: int)
signal game_over(final_score: int)

enum GameState { SPLASH, MENU, PLAYING, GAME_OVER }
static var skip_menu_on_ready: bool = false

var game_state: GameState = GameState.SPLASH
var is_paused: bool = false
var _pause_button: Control
var _pause_layer: CanvasLayer
var _splash_layer: CanvasLayer
var _title_layer: CanvasLayer
var _mute_button: Button = null
const SETTINGS_PATH := "user://snake3d_settings.cfg"
var _title_time_rows: Array = []
var _title_length_rows: Array = []
var _go_leaderboard_layer: CanvasLayer
var _go_time_rows: Array = []
var _go_length_rows: Array = []
var _recap_labels: Array = []
var _enemies_killed_count: int = 0
var _new_high_score_this_run: bool = false
var _new_high_score_label: Label

# After a run ends, hold on the leaderboard/recap for this long before any tap
# is allowed to move on (to the restart transition) -- so the player actually
# sees their result instead of a stray tap skipping straight past it. The
# "[ RESET ]" prompt stays hidden until the lockout lifts, as the visual cue.
const GAME_OVER_TAP_LOCKOUT_MS := 3000
var _game_over_shown_ms: int = 0

const MENU_CAMERA_BASE_YAW := 45.0
var _camera_crane_pivot: Node3D

# Third-person chase camera used for the title-screen attract mode: its own
# SpringArm3D rig (separate from the gameplay isometric crane) that tracks
# behind the wandering demo snake's current travel direction.
const THIRD_PERSON_TURN_SPEED := 4.0
var _third_person_pivot: Node3D
var _third_person_camera: Camera3D

# Title-screen "attract mode": the snake wanders on its own, avoiding
# self-collision and obstacles where possible (never actually "dies" --
# collisions just mean it holds still for that tick). Reset back to a clean
# spawn at the origin the moment real gameplay starts (see snake.gd::
# reset_to_spawn) so the demo's wandering never affects where the real run
# begins.
const MENU_SNAKE_STEP_INTERVAL := 0.22
var _menu_snake_step_timer: float = 0.0

# Tilt-shift is dialed up while on the title screen for a stronger "miniature
# diorama" photography look, then restored to the gameplay-tuned values the
# moment the run starts.
const TILT_SHIFT_NORMAL_FOCUS_WIDTH := 0.10
const TILT_SHIFT_NORMAL_MAX_BLUR := 5.0
const TILT_SHIFT_MENU_FOCUS_WIDTH := 0.05
const TILT_SHIFT_MENU_MAX_BLUR := 7.0
var _tilt_shift_material: ShaderMaterial

# Hit feedback: screen flash + camera shake, shared by every "player took
# damage" path (segment shrink, death). Camera reference is cached once at
# _ready() since _start_death() later reparents the same node out from under
# SpringArm3D -- the object reference stays valid across that move.
var _camera3d: Camera3D
var _hit_flash_rect: ColorRect
var _hit_flash_tween: Tween
var _shake_time: float = 0.0
var _shake_duration: float = 0.25
var _shake_amount: float = 0.0

const LEADERBOARD_PATH := "user://snake3d_leaderboard.cfg"
const LEADERBOARD_SIZE := 5

var best_times: Array = []
var best_lengths: Array = []
var _max_segment_count: int = 3

const LEVEL_BIOMES := ["neon", "desert", "glacier", "mountain", "crystal_cave", "volcanic"]
const LEVEL_GOALS := [
	{"segments": 8, "duration": 15.0},
	{"segments": 10, "duration": 18.0},
	{"segments": 12, "duration": 20.0},
	{"segments": 14, "duration": 22.0},
	{"segments": 16, "duration": 25.0},
	{"segments": 18, "duration": 28.0},
]
const LEVEL_PROGRESS_PATH := "user://snake3d_levelprogress.cfg"

var current_level: int = 0
var is_new_game_plus: bool = false
var per_level_best_score: Array = []
var _level_start_score: int = 0
var _level_goal_timer: float = 0.0
var _level_label: Label = null

@export var initial_speed: float = 0.18
@export var speed_increment: float = 0.015
@export var speed_increase_interval: int = 5
@export var initial_food_count: int = 5

@onready var food: Node3D = $Food
@onready var snake: Node3D = $Snake
@onready var floor_manager: Node3D = $FloorManager

var snake_ref: Node3D:
	get: return snake
var food_ref: Node3D:
	get: return food

var score: int = 0
var high_score: int = 0
var current_speed: float = 0.0
var food_eaten_count: int = 0
var is_game_over: bool = false
var rng: RandomNumberGenerator

var all_foods: Array = []
var is_dying: bool = false
var _death_queue: Array = []
var _death_timer: float = 0.0
var _death_direction: Vector3 = Vector3.ZERO

var _bullets: Array = []
var _player_bullets: Array = []
var _player_turret_fire_timer: float = 0.0
var _play_time: float = 0.0
var _decay_timer: float = 0.0
var _turret_fire_timer: float = 0.0
var _food_relocate_timer: float = 0.0
var _timer_label: Label = null
const JoystickScript := preload("res://scripts/touch_joystick.gd")
var _joystick: Control = null

const HIGH_SCORE_PATH := "user://snake3d_highscore.cfg"
const DEATH_INTERVAL: float = 0.08
const PowerUpScript := preload("res://scripts/power_up.gd")
const EnemyScript := preload("res://scripts/enemy_snake.gd")
const SPEED_RAMP_DURATION: float = 30.0

# Every segment mounts a little turret (snake.gd), so a longer snake fires more
# bullets at once each volley -- keeping segments is what keeps the firepower up.
const PLAYER_TURRET_FIRE_INTERVAL: float = 2.0
const PLAYER_BULLET_SPEED: float = 11.0
const PLAYER_BULLET_RANGE: float = 14.0

const ENEMY_TYPES := ["stealer", "boxer", "thief", "hoarder", "turret_head"]
const ALL_ENEMY_TYPES := ["stealer", "boxer", "thief", "hoarder", "turret_head", "speedster", "burrower", "frost_wisp", "rock_golem", "shard_wraith", "magma_serpent"]
const BIOME_ENEMY := {
	"neon": "speedster",
	"desert": "burrower",
	"glacier": "frost_wisp",
	"mountain": "rock_golem",
	"crystal_cave": "shard_wraith",
	"volcanic": "magma_serpent",
}
const ENEMY_CHECK_INTERVAL: float = 6.0
const ENEMY_CAP_PER_TYPE: int = 1
const ENEMY_SPAWN_GRACE_PERIOD: float = 15.0
const ENEMY_HOARDER_POWERS := ["rainbow", "yellow", "blue"]

var enemy_spawn_chance: Dictionary = {}
var enemy_segment_count: Dictionary = {}
var enemy_snakes: Array = []
var _enemy_spawn_timer: float = 0.0

var _speed_ramp_food_count: int = -1

const POWER_UP_TYPES := ["rainbow", "yellow", "red", "blue"]
# Global bonus power-ups: not biome-exclusive, spawn alongside the original 4 in every biome.
const BONUS_POWER_UP_TYPES := ["laser", "scatter", "nova"]
const ALL_POWER_UP_TYPES := ["rainbow", "yellow", "red", "blue", "neon_speed", "mirage", "ice_shield", "boulder_burst", "crystal_growth", "magma_trail", "laser", "scatter", "nova"]
const BIOME_POWER_UP := {
	"neon": "neon_speed",
	"desert": "mirage",
	"glacier": "ice_shield",
	"mountain": "boulder_burst",
	"crystal_cave": "crystal_growth",
	"volcanic": "magma_trail",
}
const BIOME_POWER_UP_DURATION := {
	"neon_speed": 6.0,
	"mirage": 7.0,
	"ice_shield": 4.0,
	"magma_trail": 8.0,
}
const MAGMA_TRAIL_TILE_LIFETIME := 4.0

const POWER_UP_CHECK_INTERVAL: float = 3.0
const RAINBOW_DURATION: float = 5.0
const YELLOW_DURATION: float = 9.0
const SPIKE_DURATION: float = 9.0
const BONUS_FOOD_LIFETIME: float = 8.0

var power_up_chance: Dictionary = {}
var active_power_ups: Dictionary = {}
var _power_up_spawn_timer: float = 0.0

var bonus_foods: Array = []
var _bonus_food_expiry: Dictionary = {}

var is_invincible: bool = false
var _invincible_timer: float = 0.0
var is_yellow_mode: bool = false
var _yellow_timer: float = 0.0
var is_spike_mode: bool = false
var _spike_timer: float = 0.0

var is_speed_boost: bool = false
var _speed_boost_timer: float = 0.0
var is_cloaked: bool = false
var _cloak_timer: float = 0.0
var is_shielded: bool = false
var _shield_timer: float = 0.0
var _shield_visual: Node3D = null
var is_magma_mode: bool = false
var _magma_mode_timer: float = 0.0
var _magma_trail: Dictionary = {}
var _enemy_magma_trail: Dictionary = {}

const LASER_DURATION: float = 5.0
const LASER_RANGE: int = 12
const LASER_TICK_INTERVAL: float = 0.15
var is_laser_mode: bool = false
var _laser_timer: float = 0.0
var _laser_tick_timer: float = 0.0
var _laser_visual: MeshInstance3D = null

const SCATTER_SEGMENTS_PER_TIER: int = 6

const NOVA_RADIUS: int = 4

# HUD active-power-up tray (see _build_powerup_tray_ui / _update_powerup_tray):
# one entry per timed effect, `get(prop)`/`get(timer_prop)` read the matching
# state var by name each frame. Instant effects (red/boulder/crystal/scatter/
# nova) have no ongoing timer, so they're not listed here. The "max" values for
# neon_speed/mirage/ice_shield/magma_trail are duplicated from
# BIOME_POWER_UP_DURATION (dictionary lookups aren't foldable into a const
# array literal) -- keep them in sync if those durations ever change.
const POWERUP_TRAY_CONFIG := [
	{"prop": "is_invincible", "timer_prop": "_invincible_timer", "max": RAINBOW_DURATION, "color": Color(1.0, 1.0, 1.0, 1.0)},
	{"prop": "is_yellow_mode", "timer_prop": "_yellow_timer", "max": YELLOW_DURATION, "color": Color(1.0, 0.85, 0.1, 1.0)},
	{"prop": "is_spike_mode", "timer_prop": "_spike_timer", "max": SPIKE_DURATION, "color": Color(0.1, 0.55, 1.0, 1.0)},
	{"prop": "is_speed_boost", "timer_prop": "_speed_boost_timer", "max": 6.0, "color": Color(0.2, 1.0, 1.0, 1.0)},
	{"prop": "is_cloaked", "timer_prop": "_cloak_timer", "max": 7.0, "color": Color(0.85, 0.75, 0.5, 1.0)},
	{"prop": "is_shielded", "timer_prop": "_shield_timer", "max": 4.0, "color": Color(0.7, 0.9, 1.0, 1.0)},
	{"prop": "is_magma_mode", "timer_prop": "_magma_mode_timer", "max": 8.0, "color": Color(1.0, 0.35, 0.05, 1.0)},
	{"prop": "is_laser_mode", "timer_prop": "_laser_timer", "max": LASER_DURATION, "color": Color(0.4, 1.0, 1.0, 1.0)},
]

# --- Dynamic difficulty adjustment (DDA) ------------------------------------
# The game rubber-bands to the player's recent success so a struggling child
# gets an easier ride and a thriving one gets pushed harder. `difficulty` is a
# single 0..1 dial (0 = easiest, 1 = hardest) persisted across runs. At each
# death we score the finished run (food score + survival time) and compare it to
# the average of the last few runs: steadily worse runs step the dial down
# toward the easy floor, steadily better runs step it up toward the hard
# ceiling, and a noise band in the middle leaves it alone. Every spawn/fire knob
# below just lerps between an EASY endpoint (dial 0) and a HARD endpoint (dial
# 1), so clamping the dial to [0,1] is exactly the "respective min/max" the
# design asks for. Note: this eases the things that work AGAINST the player
# (enemy/environment turrets, enemy count) and boosts the things that HELP the
# player (food, power-ups) -- the player's own segment turrets are deliberately
# left untouched, since slowing those would make an "easier" run harder.
const DIFFICULTY_PATH := "user://snake3d_difficulty.cfg"
const DDA_DEFAULT := 0.4          # start slightly below neutral (audience: children)
const DDA_STEP := 0.12            # per-run nudge; ~5 steady runs span floor<->ceiling
const DDA_DEAD_ZONE := 0.15       # +/-15% band around the baseline reads as "no change"
const DDA_HISTORY_SIZE := 5       # runs averaged to form the comparison baseline
const DDA_TIME_WEIGHT := 0.1      # survival-time contribution: 1 perf point per 10s

# Knob endpoints: value at the easy floor (dial 0) -> hard ceiling (dial 1).
const DDA_FOOD_BONUS_EASY := 3.0        # extra foods kept on the board when easiest
const DDA_FOOD_BONUS_HARD := -1.0       # fewer when hardest (target still clamps >= 1)
const DDA_POWERUP_MULT_EASY := 1.7      # power-up spawn-chance multiplier
const DDA_POWERUP_MULT_HARD := 0.6
const DDA_POWERUP_INTERVAL_EASY := 2.2  # seconds between power-up spawn checks
const DDA_POWERUP_INTERVAL_HARD := 3.6
const DDA_ENV_TURRET_INTERVAL_EASY := 6.5  # seconds between environment turret volleys
const DDA_ENV_TURRET_INTERVAL_HARD := 2.8
const DDA_ENEMY_TURRET_SCALE_EASY := 1.7   # multiplier on enemy turret-head fire interval
const DDA_ENEMY_TURRET_SCALE_HARD := 0.85
const DDA_ENEMY_MULT_EASY := 0.5        # enemy spawn-chance multiplier
const DDA_ENEMY_MULT_HARD := 1.5
const DDA_ENEMY_INTERVAL_EASY := 8.5    # seconds between enemy spawn checks
const DDA_ENEMY_INTERVAL_HARD := 4.5
const DDA_ENEMY_GRACE_EASY := 22.0      # first enemy can't spawn before this many seconds
const DDA_ENEMY_GRACE_HARD := 12.0

var difficulty: float = DDA_DEFAULT
var _dda_history: Array = []
# Computed once per run in _apply_difficulty() from `difficulty`:
var _dda_food_bonus: int = 0
var _dda_powerup_mult: float = 1.0
var _dda_powerup_interval: float = POWER_UP_CHECK_INTERVAL
var _dda_env_turret_interval: float = 4.0
var _dda_enemy_turret_scale: float = 1.0
var _dda_enemy_mult: float = 1.0
var _dda_enemy_interval: float = ENEMY_CHECK_INTERVAL
var _dda_enemy_grace: float = ENEMY_SPAWN_GRACE_PERIOD


func _ready() -> void:
	_ensure_action("move_up", [KEY_W, KEY_UP])
	_ensure_action("move_down", [KEY_S, KEY_DOWN])
	_ensure_action("move_left", [KEY_A, KEY_LEFT])
	_ensure_action("move_right", [KEY_D, KEY_RIGHT])
	_ensure_action("restart_game", [KEY_R])

	process_mode = Node.PROCESS_MODE_ALWAYS
	rng = RandomNumberGenerator.new()
	rng.randomize()
	high_score = _load_high_score()
	_load_difficulty()
	_apply_difficulty()
	current_speed = initial_speed
	if snake:
		snake.move_duration = initial_speed * 0.92
		_camera_crane_pivot = snake.get_node_or_null("Seg0/CameraCranePivot")
		_camera3d = snake.get_node_or_null("Seg0/CameraCranePivot/SpringArm3D/Camera3D") as Camera3D
		_third_person_pivot = snake.get_node_or_null("Seg0/ThirdPersonPivot") as Node3D
		_third_person_camera = snake.get_node_or_null("Seg0/ThirdPersonPivot/ThirdPersonSpringArm3D/ThirdPersonCamera3D") as Camera3D

	for t in ALL_POWER_UP_TYPES:
		power_up_chance[t] = rng.randf_range(0.06, 0.45)

	for t in ALL_ENEMY_TYPES:
		enemy_spawn_chance[t] = rng.randf_range(0.05, 0.3)
		# turret_head is a stationary single-block emplacement, not a body of
		# segments -- keep it a 1-hit kill rather than randomizing its length.
		enemy_segment_count[t] = 1 if t == "turret_head" else rng.randi_range(2, 6)

	var score_label: Label3D = get_node_or_null("ScoreLabel")
	if score_label:
		score_label.text = "0"

	var game_over_overlay: Node3D = get_node_or_null("GameOverOverlay")
	if game_over_overlay:
		game_over_overlay.visible = false

	_load_level_progress()
	current_level = 0
	_level_start_score = 0
	_level_goal_timer = 0.0
	if floor_manager:
		floor_manager.biome = LEVEL_BIOMES[current_level]
	_build_level_ui()
	_build_powerup_tray_ui()
	_build_hit_flash_ui()
	_build_pause_ui()
	_build_touch_controls()

	all_foods.append(food)
	_spawn_food_at(food)
	_refresh_food_pool()
	_timer_label = get_node_or_null("/root/Main/TimerLayer/TimerLabel") as Label

	_load_leaderboard()
	_load_settings()
	_build_title_ui()
	_build_gameover_leaderboard_ui()
	_refresh_leaderboard_ui()
	_build_splash_ui()

	var tilt_shift_rect := get_node_or_null("TiltShiftLayer/TiltShiftRect") as ColorRect
	if tilt_shift_rect:
		_tilt_shift_material = tilt_shift_rect.material as ShaderMaterial

	if skip_menu_on_ready:
		skip_menu_on_ready = false
		game_state = GameState.PLAYING
		_title_layer.visible = false
		_splash_layer.visible = false
		Chiptune.music_enabled = true
		_apply_gameplay_camera_state()
		# Restart came in through the transition curtain: this fresh scene opens
		# fully black (the level is already loaded), then plays the RUN beat
		# (snakes sweep across) followed by REVEAL (fade out). is_transitioning
		# freezes the new run and blocks input until the reveal completes.
		if _play_run_on_ready:
			_play_run_on_ready = false
			_build_transition_curtain(true)
			is_transitioning = true
			_transition_phase = TransitionPhase.RUN
			_transition_time = 0.0
	elif _splash_is_ready():
		game_state = GameState.SPLASH
		if floor_manager:
			floor_manager.menu_showcase_mode = true
		_start_splash_playback()
	else:
		# No splash frames available -- skip straight to the title screen
		# rather than getting stuck on a black layer.
		_splash_layer.visible = false
		game_state = GameState.MENU
		if floor_manager:
			floor_manager.menu_showcase_mode = true
		Chiptune.music_enabled = true
		_apply_menu_camera_state()


func _ensure_action(name: String, keys: Array) -> void:
	if InputMap.has_action(name):
		return
	InputMap.add_action(name)
	for k in keys:
		var e := InputEventKey.new()
		e.keycode = k
		InputMap.action_add_event(name, e)


# No-op on desktop (Input.vibrate_handheld only does anything on Android/iOS),
# so this is safe to call unconditionally from anywhere without a platform
# check. Kept to the handful of meaningful moments (power-ups, high score,
# level up, taking a hit, death) rather than frequent events like eating --
# buzzing on every single food pickup would be more annoying than useful.
func _haptic(duration_ms: int) -> void:
	Input.vibrate_handheld(duration_ms)


func _unhandled_input(event: InputEvent) -> void:
	if game_state == GameState.SPLASH:
		if (event is InputEventScreenTouch and event.pressed) or Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("restart_game"):
			_finish_splash()
		return

	# The transition curtain owns the screen: swallow every input until it lifts.
	if is_transitioning:
		return

	if is_paused:
		# Swallow everything else while paused (a touch that misses a pause-menu
		# button should not fall through to movement/joystick handling below).
		# Android's back button and desktop Escape both map to ui_cancel, so
		# that's a free "resume" shortcut matching platform convention.
		if Input.is_action_just_pressed("ui_cancel"):
			_toggle_pause(false)
		return

	if Input.is_action_just_pressed("restart_game"):
		if not _game_over_input_locked():
			restart()
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			if game_state == GameState.PLAYING and not is_game_over and not is_dying and _joystick:
				_joystick.begin_touch(event.index, event.position)
			return
		if _joystick:
			_joystick.end_touch(event.index)
		if game_state == GameState.MENU:
			_begin_menu_to_game_transition()
		elif (is_game_over or is_dying) and not _game_over_input_locked():
			restart()
		return

	if event is InputEventScreenDrag:
		if _joystick:
			_joystick.update_touch(event.index, event.position)
		return

	if game_state == GameState.MENU:
		if Input.is_action_just_pressed("ui_accept"):
			_begin_menu_to_game_transition()
		return

	if is_game_over or is_dying:
		if Input.is_action_just_pressed("ui_accept") and not _game_over_input_locked():
			restart()
		return

	if Input.is_action_just_pressed("ui_cancel"):
		_toggle_pause(true)
		return

	if Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("ui_up"):
		snake.set_direction(Vector3.FORWARD)
	elif Input.is_action_just_pressed("move_down") or Input.is_action_just_pressed("ui_down"):
		snake.set_direction(Vector3.BACK)
	elif Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("ui_left"):
		snake.set_direction(Vector3.LEFT)
	elif Input.is_action_just_pressed("move_right") or Input.is_action_just_pressed("ui_right"):
		snake.set_direction(Vector3.RIGHT)


func _touch_direction_pressed(dir: Vector3) -> void:
	if game_state != GameState.PLAYING or is_game_over or is_dying:
		return
	snake.set_direction(dir)


func _process(delta: float) -> void:
	if is_paused:
		return

	# A transition curtain (see the Transition curtain section) is up: drive its
	# fade + crawling snakes and freeze everything else, so the run behind it
	# doesn't advance a single step until the reveal finishes and input reopens.
	if is_transitioning:
		_tick_transition(delta)
		return

	# Bullets always keep animating/homing/expiring, even while dying or on the
	# game-over screen -- previously these ticks lived below the state checks
	# below, so any bullet in flight the instant death started would just hang
	# frozen in place for the rest of the run (never popped, never removed).
	_tick_bullets(delta)
	_tick_player_bullets(delta)
	_tick_camera_shake(delta)

	if game_state == GameState.SPLASH:
		_tick_splash(delta)
		return

	if game_state == GameState.MENU:
		_tick_menu_camera_drift(delta)
		return

	if game_state != GameState.PLAYING:
		return

	if is_dying:
		_death_timer -= delta
		if _death_timer <= 0.0:
			_destroy_next_segment()
		return

	if is_game_over:
		return

	_play_time += delta
	if _timer_label:
		_timer_label.text = "%d:%02d" % [int(_play_time / 60), int(_play_time) % 60]

	if _speed_ramp_food_count < 0 and _play_time >= SPEED_RAMP_DURATION:
		_speed_ramp_food_count = food_eaten_count

	_food_relocate_timer += delta
	if _food_relocate_timer >= 5.0:
		_food_relocate_timer = 0.0
		_relocate_distant_food()

	_decay_timer += delta
	if _decay_timer >= 20.0:
		_decay_timer = 0.0
		_shrink_snake()

	_turret_fire_timer += delta
	if _turret_fire_timer >= _dda_env_turret_interval:
		_turret_fire_timer = 0.0
		_fire_turrets()

	_player_turret_fire_timer += delta
	if _player_turret_fire_timer >= PLAYER_TURRET_FIRE_INTERVAL:
		_player_turret_fire_timer = 0.0
		_fire_player_turrets()

	_tick_power_up_effects(delta)
	_tick_laser(delta)
	_power_up_spawn_timer += delta
	if _power_up_spawn_timer >= _dda_powerup_interval:
		_power_up_spawn_timer = 0.0
		_update_power_up_spawns()
	_tick_bonus_foods(delta)
	_tick_magma_trail(delta)
	_tick_enemy_magma_trail(delta)
	if is_shielded and _shield_visual and is_instance_valid(_shield_visual):
		var head_node := snake.get_node_or_null("Seg0") as Node3D
		if head_node:
			_shield_visual.global_position = head_node.global_position

	_enemy_spawn_timer += delta
	if _enemy_spawn_timer >= _dda_enemy_interval and _play_time >= _dda_enemy_grace:
		_enemy_spawn_timer = 0.0
		_update_enemy_spawns()
	for e in enemy_snakes:
		if is_instance_valid(e) and e.consume_fire_ready():
			_spawn_bullet(Vector3(e.segments[0].x, 0.5, e.segments[0].z))

	_tick_level_goal(delta)
	_update_powerup_tray()

	current_speed -= delta
	if current_speed > 0.0:
		return

	current_speed = _get_current_speed()
	snake.move_duration = current_speed * 0.92
	if not snake.step():
		_start_death()
		return

	_max_segment_count = maxi(_max_segment_count, snake.segments.size())

	if is_magma_mode and snake.segments.size() > 1:
		_drop_magma_trail(snake.segments[1])

	var head := snake.segments.front() as Vector3

	if floor_manager and floor_manager.has_method("is_tile_obstacle_at"):
		if floor_manager.is_tile_obstacle_at(head):
			if is_spike_mode:
				floor_manager.destroy_obstacle_at_grid(int(round(head.x)), int(round(head.z)))
			else:
				_start_death()
				return

	_check_player_vs_enemies(head)
	if is_game_over:
		return

	if _enemy_magma_trail.has(head) and not is_invincible and not is_shielded:
		Chiptune.play_sfx("hit")
		_haptic(40)
		_shrink_snake()

	for _f in all_foods:
		var f := _f as Node3D
		if not is_instance_valid(f):
			continue
		if Vector2(head.x - f.global_position.x, head.z - f.global_position.z).length_squared() < 0.25:
			score += 1
			food_eaten_count += 1
			Chiptune.play_sfx("eat")
			_spawn_particle_burst(f.global_position, Color(1.0, 0.14, 0.14), 10)
			if score > high_score:
				high_score = score
				_save_high_score()
				Chiptune.play_sfx("high_score")
				_haptic(50)
				_new_high_score_this_run = true
			food_eaten.emit(score)
			snake.grow(2 if is_yellow_mode else 1)
			_spawn_food_at(f)
			_refresh_food_pool()
			if food_eaten_count % speed_increase_interval == 0 and _speed_ramp_food_count < 0:
				current_speed = max(0.06, current_speed - speed_increment)
			break

	_check_power_up_pickups(head)
	_check_bonus_food_pickups(head)
	_step_enemy_snakes()


func _on_food_eaten(_pts: int) -> void:
	pass


func _on_game_over(final: int) -> void:
	is_game_over = true
	game_over.emit(final)


func _get_target_food_count() -> int:
	var seg_count := 0
	if snake:
		for child in snake.get_children():
			if child.name.begins_with("Seg"):
				seg_count += 1
	return maxi(1, initial_food_count - seg_count / 5 + _dda_food_bonus)


func _make_food_node() -> Node3D:
	var f: Node3D = food.duplicate()
	for child in f.get_children():
		f.remove_child(child)
		child.free()
	return f


func _refresh_food_pool() -> void:
	var target := _get_target_food_count()
	while all_foods.size() < target:
		var f := _make_food_node()
		f.name = "FoodExtra%d" % all_foods.size()
		all_foods.append(f)
		add_child(f)
		_spawn_food_at(f)
	while all_foods.size() > target:
		var f := all_foods.pop_back() as Node3D
		if is_instance_valid(f) and f != food:
			if f.has_method("pop_out_and_free"):
				f.pop_out_and_free()
			else:
				f.queue_free()


func _spawn_food_at(f: Node3D) -> void:
	if not snake or snake.segments.is_empty():
		return
	var head := snake.segments.front() as Vector3
	var occupied: Dictionary = {}
	for seg: Vector3 in snake.segments:
		occupied[Vector3i(int(round(seg.x)), 0, int(round(seg.z)))] = true
	for _attempt in range(40):
		var ox := rng.randi_range(-10, 10)
		var oz := rng.randi_range(-10, 10)
		if ox == 0 and oz == 0:
			continue
		var gx := int(round(head.x)) + ox
		var gz := int(round(head.z)) + oz
		if occupied.has(Vector3i(gx, 0, gz)):
			continue
		if floor_manager and floor_manager.is_tile_obstacle_at_grid(gx, gz):
			continue
		f.global_position = Vector3(float(gx), 0.45, float(gz))
		if f.has_method("pop_in"):
			f.pop_in()
		return
	f.global_position = Vector3(head.x + 3.0, 0.45, head.z + 3.0)
	if f.has_method("pop_in"):
		f.pop_in()


func _start_death() -> void:
	is_dying = true
	is_game_over = true
	_death_direction = snake.get_direction()
	Chiptune.play_sfx("death")
	_haptic(80)
	if _pause_button:
		_pause_button.visible = false
	_flash_hit()
	_trigger_camera_shake(0.35, 0.4)

	# Brief cinematic slow-mo on the death impact -- ignores time_scale itself
	# (so the dip/recovery timing stays consistent) while everything else in
	# the game, including the segment-destruction animation below, plays out
	# at the temporarily reduced speed.
	Engine.time_scale = 0.35
	var time_tw := create_tween()
	time_tw.set_ignore_time_scale(true)
	time_tw.tween_interval(0.35)
	time_tw.tween_property(Engine, "time_scale", 1.0, 0.5)

	var cam := get_node_or_null("Snake/Seg0/CameraCranePivot/SpringArm3D/Camera3D") as Camera3D
	if cam:
		var saved := cam.global_transform
		cam.get_parent().remove_child(cam)
		add_child(cam)
		cam.global_transform = saved

	_death_queue.clear()
	for i in range(snake.segments.size()):
		var seg := snake.get_node_or_null("Seg%d" % i) as Node3D
		if seg:
			_death_queue.append(seg)

	_death_timer = 0.0


func _destroy_next_segment() -> void:
	if _death_queue.is_empty():
		_finish_death()
		return

	var seg := _death_queue.pop_front() as Node3D
	if is_instance_valid(seg):
		var mesh := seg.get_node_or_null("Mesh") as MeshInstance3D
		if mesh:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(1.0, 0.15, 0.0, 1.0)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.3, 0.0)
			mat.emission_energy_multiplier = 3.0
			mesh.material_override = mat

		var target := seg.global_position + _death_direction
		var tw := create_tween().set_parallel(true)
		tw.tween_property(seg, "global_position", target, DEATH_INTERVAL * 0.85)
		tw.tween_property(seg, "scale", Vector3.ZERO, DEATH_INTERVAL * 0.85)

	_death_timer = DEATH_INTERVAL


func _finish_death() -> void:
	is_dying = false
	game_state = GameState.GAME_OVER
	Engine.time_scale = 1.0
	var overlay: Node3D = get_node_or_null("GameOverOverlay")
	if overlay:
		overlay.visible = true
		var sc := overlay.get_node_or_null("GameOverScore") as Label3D
		if sc:
			sc.text = "Score: %d  |  Best: %d" % [score, high_score]
		# Hold the leaderboard: taps are ignored for GAME_OVER_TAP_LOCKOUT_MS,
		# and the "[ RESET ]" prompt stays hidden until then as the cue that
		# tapping now advances.
		var reset_prompt := overlay.get_node_or_null("GameOverRestart") as Label3D
		if reset_prompt:
			reset_prompt.visible = false
			get_tree().create_timer(GAME_OVER_TAP_LOCKOUT_MS / 1000.0).timeout.connect(
				func() -> void:
					if is_instance_valid(reset_prompt):
						reset_prompt.visible = true
			)
	_game_over_shown_ms = Time.get_ticks_msec()

	_update_difficulty(score, _play_time)
	var ranks := _record_run(_play_time, _max_segment_count)
	_refresh_leaderboard_ui(ranks.time_rank, ranks.length_rank)
	if _go_leaderboard_layer:
		_go_leaderboard_layer.visible = true
	_show_recap()

	if _new_high_score_this_run and _new_high_score_label:
		_show_new_high_score_flourish()

	game_over.emit(score)


func _show_new_high_score_flourish() -> void:
	_new_high_score_label.visible = true
	_new_high_score_label.pivot_offset = _new_high_score_label.size * 0.5
	_new_high_score_label.scale = Vector2.ONE * 0.3
	_new_high_score_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var hs_tw := create_tween()
	hs_tw.tween_interval(0.3)
	hs_tw.set_parallel(true)
	hs_tw.tween_property(_new_high_score_label, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	hs_tw.tween_property(_new_high_score_label, "modulate:a", 1.0, 0.25)
	hs_tw.chain().tween_callback(_pulse_new_high_score_label)


func _pulse_new_high_score_label() -> void:
	var pulse := create_tween()
	pulse.set_loops()
	pulse.tween_property(_new_high_score_label, "modulate", Color(1.0, 0.85, 0.2, 1.0), 0.5)
	pulse.tween_property(_new_high_score_label, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.5)


func _tick_level_goal(delta: float) -> void:
	var level_score := score - _level_start_score
	if is_new_game_plus:
		if level_score > per_level_best_score[current_level]:
			_advance_level()
	else:
		var goal: Dictionary = LEVEL_GOALS[current_level]
		if snake and snake.segments.size() >= int(goal.segments):
			_level_goal_timer += delta
			if _level_goal_timer >= float(goal.duration):
				_advance_level()
		else:
			_level_goal_timer = 0.0
	_update_level_label()


func _advance_level() -> void:
	var level_score := score - _level_start_score
	if level_score > per_level_best_score[current_level]:
		per_level_best_score[current_level] = level_score
		_save_level_progress()

	current_level += 1
	if current_level >= LEVEL_BIOMES.size():
		current_level = 0
		if not is_new_game_plus:
			is_new_game_plus = true
			_save_level_progress()
			_show_win_banner()

	_level_start_score = score
	_level_goal_timer = 0.0
	if floor_manager:
		floor_manager.biome = LEVEL_BIOMES[current_level]
	Chiptune.play_sfx("level_up")
	_haptic(60)
	_show_level_banner(true)
	_update_level_label()


const POWERUP_TRAY_ICON_SIZE := 56.0
const POWERUP_TRAY_GAP := 10.0

var _powerup_tray_slots: Array = []

func _build_powerup_tray_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PowerUpTrayLayer"
	layer.layer = 13
	add_child(layer)

	var container := HBoxContainer.new()
	container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	container.offset_left = -32.0 - POWERUP_TRAY_ICON_SIZE * 8 - POWERUP_TRAY_GAP * 7
	container.offset_right = -32.0
	container.offset_top = 76.0
	container.offset_bottom = 76.0 + POWERUP_TRAY_ICON_SIZE + 14.0
	container.add_theme_constant_override("separation", int(POWERUP_TRAY_GAP))
	container.alignment = BoxContainer.ALIGNMENT_END
	layer.add_child(container)

	# One reusable slot per possible simultaneous effect -- config list defined
	# in _update_powerup_tray. Built once, just shown/hidden and refilled.
	for i in range(8):
		var slot := VBoxContainer.new()
		slot.visible = false
		slot.custom_minimum_size = Vector2(POWERUP_TRAY_ICON_SIZE, POWERUP_TRAY_ICON_SIZE + 14.0)

		var icon := ColorRect.new()
		icon.custom_minimum_size = Vector2(POWERUP_TRAY_ICON_SIZE, POWERUP_TRAY_ICON_SIZE)
		icon.color = Color(1, 1, 1, 1)
		slot.add_child(icon)

		var bar_bg := ColorRect.new()
		bar_bg.custom_minimum_size = Vector2(POWERUP_TRAY_ICON_SIZE, 8.0)
		bar_bg.color = Color(0.0, 0.0, 0.0, 0.6)
		slot.add_child(bar_bg)

		var bar_fill := ColorRect.new()
		bar_fill.custom_minimum_size = Vector2(POWERUP_TRAY_ICON_SIZE, 8.0)
		bar_fill.color = Color(1, 1, 1, 1)
		bar_fill.set_anchors_preset(Control.PRESET_TOP_LEFT)
		bar_bg.add_child(bar_fill)

		container.add_child(slot)
		_powerup_tray_slots.append({"root": slot, "icon": icon, "fill": bar_fill})


func _update_powerup_tray() -> void:
	if _powerup_tray_slots.is_empty():
		return
	var active: Array = []
	for entry in POWERUP_TRAY_CONFIG:
		if get(entry.prop):
			var remaining: float = get(entry.timer_prop)
			active.append({"color": entry.color, "frac": clampf(remaining / entry.max, 0.0, 1.0)})

	for i in range(_powerup_tray_slots.size()):
		var slot: Dictionary = _powerup_tray_slots[i]
		if i < active.size():
			var a: Dictionary = active[i]
			slot.root.visible = true
			(slot.icon as ColorRect).color = a.color
			var fill := slot.fill as ColorRect
			fill.size = Vector2(POWERUP_TRAY_ICON_SIZE * a.frac, 8.0)
			fill.color = a.color
		else:
			slot.root.visible = false


func _build_level_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "LevelLayer"
	layer.layer = 12
	add_child(layer)

	_level_label = Label.new()
	_level_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_level_label.offset_left = 32
	_level_label.offset_top = 28
	_level_label.offset_right = 776
	_level_label.offset_bottom = 132
	# Safety net, not a design choice: this text is runtime-built (level name,
	# biome name, live stats) and its width was never verified against the
	# custom pixel font's actual glyph metrics on a real device. Wrap instead
	# of silently clipping off-screen if it ever runs wider than expected.
	_level_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_level_label.add_theme_font_size_override("font_size", 26)
	_level_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	_level_label.add_theme_constant_override("outline_size", 6)
	_level_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	layer.add_child(_level_label)
	_update_level_label()


func _update_level_label() -> void:
	if not _level_label:
		return
	var biome_name := _biome_display_name(LEVEL_BIOMES[current_level])
	var prefix := "NG+ " if is_new_game_plus else ""
	var header := "%sLEVEL %d/%d: %s" % [prefix, current_level + 1, LEVEL_BIOMES.size(), biome_name]

	if is_new_game_plus:
		var level_score := score - _level_start_score
		var best: int = per_level_best_score[current_level]
		_level_label.text = "%s\nbeat best: %d/%d" % [header, level_score, best]
	else:
		var goal: Dictionary = LEVEL_GOALS[current_level]
		var seg_count: int = snake.segments.size() if snake else 0
		_level_label.text = "%s\n%d/%d segments · %.0f/%.0fs" % [header, seg_count, int(goal.segments), _level_goal_timer, float(goal.duration)]


func _load_level_progress() -> void:
	is_new_game_plus = false
	per_level_best_score = []
	for i in range(LEVEL_BIOMES.size()):
		per_level_best_score.append(0)
	if not FileAccess.file_exists(LEVEL_PROGRESS_PATH):
		return
	var f := FileAccess.open(LEVEL_PROGRESS_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var data = JSON.parse_string(txt)
	if typeof(data) == TYPE_DICTIONARY:
		is_new_game_plus = data.get("ng_plus", false)
		var loaded_scores = data.get("best_scores", [])
		for i in range(mini(loaded_scores.size(), per_level_best_score.size())):
			per_level_best_score[i] = loaded_scores[i]


func _save_level_progress() -> void:
	var f := FileAccess.open(LEVEL_PROGRESS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"ng_plus": is_new_game_plus, "best_scores": per_level_best_score}))
	f.close()


func _relocate_distant_food() -> void:
	if not snake or snake.segments.is_empty():
		return
	var head := snake.segments.front() as Vector3
	for _f in all_foods:
		var f := _f as Node3D
		if not is_instance_valid(f):
			continue
		var dx: float = f.global_position.x - head.x
		var dz: float = f.global_position.z - head.z
		if dx * dx + dz * dz > 144.0:
			_spawn_food_at(f)


func _shrink_snake() -> void:
	if not snake:
		return
	var segs = snake.get("segments")
	if segs == null:
		return
	if segs.size() <= 1:
		_start_death()
		return

	# Only for the "shrunk but still alive" case -- _start_death() above
	# triggers its own (bigger) flash/shake, don't double up on the same hit.
	_flash_hit()
	_trigger_camera_shake(0.15, 0.2)

	var tail_node := snake.get_node_or_null("Seg%d" % (segs.size() - 1)) as Node3D
	if tail_node and is_instance_valid(tail_node):
		var tail_mat: Material = null
		var tail_mesh := tail_node.get_node_or_null("Mesh") as MeshInstance3D
		if tail_mesh:
			tail_mat = tail_mesh.get_surface_override_material(0)
		_spawn_shrink_ghost(tail_node.global_position, tail_mat)

	segs.pop_back()
	snake.call("_segments_changed")


func _spawn_shrink_ghost(at: Vector3, mat: Material) -> void:
	var ghost := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.85, 0.85, 0.85)
	ghost.mesh = gm
	if mat:
		ghost.material_override = mat
	else:
		var gmat := StandardMaterial3D.new()
		gmat.albedo_color = Color(0.05, 0.65, 0.22, 1.0)
		gmat.emission_enabled = true
		gmat.emission = Color(0.05, 0.65, 0.22)
		gmat.emission_energy_multiplier = 1.5
		ghost.material_override = gmat
	add_child(ghost)
	ghost.global_position = at

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ghost, "scale", Vector3.ZERO, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(ghost, "global_position", at + Vector3(0, -0.4, 0), 0.22)
	tw.chain().tween_callback(ghost.queue_free)


func _fire_turrets() -> void:
	if _play_time < 20.0:
		return
	if not floor_manager or not snake:
		return
	var head := snake.get_node_or_null("Seg0") as Node3D
	if not head:
		return
	var positions = floor_manager.get_turret_positions()
	var nearby: Array = []
	for pos in positions:
		var tp := pos as Vector3
		if head.global_position.distance_to(tp) <= 18.0:
			nearby.append(tp)
	nearby.shuffle()
	var fire_count := mini(2, nearby.size())
	for i in range(fire_count):
		_spawn_bullet(nearby[i])


func _spawn_bullet(from: Vector3) -> void:
	var b := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.3
	b.mesh = sm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(1.0, 0.8, 0.1, 1.0)
	bmat.emission_enabled = true
	bmat.emission = Color(1.0, 0.7, 0.0)
	bmat.emission_energy_multiplier = 4.0
	b.material_override = bmat
	b.global_position = from
	b.scale = Vector3.ZERO
	add_child(b)
	_bullets.append(b)
	var tw := create_tween()
	tw.tween_property(b, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_spawn_particle_burst(from, Color(1.0, 0.7, 0.0), 8)
	Chiptune.play_sfx("turret_fire")


func _tick_bullets(delta: float) -> void:
	if _bullets.is_empty() or not snake:
		return
	var head := snake.get_node_or_null("Seg0") as Node3D
	if not head:
		return
	var to_remove: Array = []
	for _b in _bullets:
		# Check validity on the untyped reference BEFORE casting -- casting an
		# already fully-deallocated (not just queue_free-pending) object with
		# `as` throws "Trying to cast a freed object", which happening here
		# would abort this whole loop before it ever reaches the to_remove
		# cleanup below, permanently jamming every bullet behind it in the array.
		if not is_instance_valid(_b):
			to_remove.append(_b)
			continue
		var b := _b as MeshInstance3D
		var life: float = b.get_meta("life", 0.0)
		life += delta
		b.set_meta("life", life)
		if life > 6.0:
			_destroy_bullet_on_impact(b)
			to_remove.append(_b)
			continue
		var pos_before: Vector3 = b.global_position
		var diff := head.global_position - pos_before
		if diff.length() < 0.5:
			_destroy_bullet_on_impact(b)
			to_remove.append(_b)
			# Only apply the hit if the player is actually still alive and playing --
			# a bullet finishing its flight during/after death should still visibly
			# vanish instead of freezing, but shouldn't re-trigger shrink/death logic.
			if game_state == GameState.PLAYING and not is_dying and not is_invincible and not is_shielded:
				Chiptune.play_sfx("hit")
				_haptic(40)
				_shrink_snake()
			continue
		b.global_position = pos_before + diff.normalized() * 10.0 * delta
		if b.global_position.distance_squared_to(pos_before) < 0.0001:
			_destroy_bullet_on_impact(b)
			to_remove.append(_b)
	for _b in to_remove:
		_bullets.erase(_b)


# Hides and frees a bullet immediately and synchronously, in whatever frame
# calls this -- no tween, no deferred callback, nothing else has to run later
# for this bullet to actually disappear. Used for every bullet exit path
# (hit, timed-out, lost its target) across every bullet source: environment
# turrets, enemy turret-heads, and player segment turrets alike.
func _destroy_bullet_on_impact(b: MeshInstance3D) -> void:
	if not is_instance_valid(b):
		return
	b.visible = false
	# Pull it out of the tree immediately rather than relying solely on
	# `visible` + a deferred queue_free -- a detached node is unambiguously
	# not rendered this frame, no matter what.
	var parent := b.get_parent()
	if parent:
		parent.remove_child(b)
	b.queue_free()


# Every current segment with a turret takes a shot at its own nearest enemy
# (if any is in range) once per volley -- more segments kept alive means more
# simultaneous bullets, not a faster individual fire rate.
func _fire_player_turrets() -> void:
	if enemy_snakes.is_empty() or not snake:
		return
	for seg_pos: Vector3 in snake.segments:
		var target := _nearest_enemy(seg_pos)
		if target:
			_spawn_player_bullet(Vector3(seg_pos.x, 0.5, seg_pos.z), target)


func _nearest_enemy(from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_dist := PLAYER_BULLET_RANGE * PLAYER_BULLET_RANGE
	for e in enemy_snakes:
		if not is_instance_valid(e):
			continue
		if e.behavior == "burrower" and e.is_burrowed:
			continue
		var d: float = (e.segments[0] as Vector3).distance_squared_to(from)
		if d < best_dist:
			best_dist = d
			best = e
	return best


func _spawn_player_bullet(from: Vector3, target: Node3D) -> void:
	var b := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.13
	sm.height = 0.26
	b.mesh = sm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.1, 1.0, 0.4, 1.0)
	bmat.emission_enabled = true
	bmat.emission = Color(0.05, 0.9, 0.3)
	bmat.emission_energy_multiplier = 4.0
	b.material_override = bmat
	b.global_position = from
	b.scale = Vector3.ZERO
	b.set_meta("target", target)
	add_child(b)
	_player_bullets.append(b)
	var tw := create_tween()
	tw.tween_property(b, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_spawn_particle_burst(from, Color(0.1, 1.0, 0.4), 8)
	Chiptune.play_sfx("player_shot")


func _tick_player_bullets(delta: float) -> void:
	if _player_bullets.is_empty():
		return
	var to_remove: Array = []
	for _b in _player_bullets:
		# Check validity on the untyped reference BEFORE casting -- see the
		# matching comment in _tick_bullets for why.
		if not is_instance_valid(_b):
			to_remove.append(_b)
			continue
		var b := _b as MeshInstance3D
		var life: float = b.get_meta("life", 0.0)
		life += delta
		b.set_meta("life", life)
		if life > 3.0:
			_destroy_bullet_on_impact(b)
			to_remove.append(_b)
			continue

		# is_instance_valid() alone isn't enough here: queue_free() defers actual
		# deallocation, so a bullet whose target was just killed by a sibling
		# bullet in the same volley would still see it as "valid" for another
		# frame or two and keep homing on its last (now frozen forever) position
		# instead of noticing it's gone. enemy_snakes.erase() in _kill_enemy is
		# synchronous, so checking membership there catches it immediately.
		# Retrieved untyped on purpose -- assigning straight into a
		# `Node3D`-typed variable makes Godot validate the reference at
		# assignment time, and if the stored enemy was already fully freed
		# (not just queue_free-pending) that assignment itself throws "Trying
		# to assign invalid previously freed instance", before we ever reach
		# the is_instance_valid() check below.
		var target = b.get_meta("target", null)
		if not target or not is_instance_valid(target) or not enemy_snakes.has(target):
			target = _nearest_enemy(b.global_position)
			if not target:
				_destroy_bullet_on_impact(b)
				to_remove.append(_b)
				continue
			b.set_meta("target", target)

		var thead: Vector3 = target.segments[0]
		var target_pos := Vector3(thead.x, 0.5, thead.z)
		var pos_before: Vector3 = b.global_position
		var diff := target_pos - pos_before
		if diff.length() < 0.5:
			_destroy_bullet_on_impact(b)
			to_remove.append(_b)
			_damage_enemy(target, true)
			continue
		b.global_position = pos_before + diff.normalized() * PLAYER_BULLET_SPEED * delta
		if b.global_position.distance_squared_to(pos_before) < 0.0001:
			_destroy_bullet_on_impact(b)
			to_remove.append(_b)
	for _b in to_remove:
		_player_bullets.erase(_b)


# Small one-shot GPUParticles3D burst reused for food pickups, turret muzzle
# flashes, and enemy kills -- shares one draw call shape (a tiny billboarded
# quad), only the process material/color differ per call.
func _spawn_particle_burst(pos: Vector3, color: Color, count: int = 10) -> void:
	var particles := GPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.amount = count
	particles.lifetime = 0.45
	particles.explosiveness = 1.0
	particles.randomness = 0.5

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.14, 0.14)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.2
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mesh.material = mat
	particles.draw_pass_1 = mesh

	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0, 1, 0)
	proc.spread = 180.0
	proc.initial_velocity_min = 1.5
	proc.initial_velocity_max = 3.2
	proc.gravity = Vector3(0, -3.5, 0)
	proc.scale_min = 0.5
	proc.scale_max = 1.1
	proc.color = color
	particles.process_material = proc

	add_child(particles)
	particles.global_position = pos
	particles.emitting = true
	get_tree().create_timer(particles.lifetime + 0.3).timeout.connect(particles.queue_free)


func _update_power_up_spawns() -> void:
	var eligible: Array = POWER_UP_TYPES.duplicate()
	eligible.append_array(BONUS_POWER_UP_TYPES)
	var biome_extra: String = BIOME_POWER_UP.get(floor_manager.biome, "") if floor_manager else ""
	if biome_extra != "" and not eligible.has(biome_extra):
		eligible.append(biome_extra)
	for t in eligible:
		if active_power_ups.has(t) and is_instance_valid(active_power_ups[t]):
			continue
		if rng.randf() < clampf(power_up_chance[t] * _dda_powerup_mult, 0.0, 0.95):
			_spawn_power_up(t)


func _spawn_power_up(ptype: String) -> void:
	if not snake or snake.segments.is_empty():
		return
	var head := snake.segments.front() as Vector3
	var occupied: Dictionary = {}
	for seg: Vector3 in snake.segments:
		occupied[Vector3i(int(round(seg.x)), 0, int(round(seg.z)))] = true
	for _attempt in range(40):
		var ox := rng.randi_range(-10, 10)
		var oz := rng.randi_range(-10, 10)
		if ox == 0 and oz == 0:
			continue
		var gx := int(round(head.x)) + ox
		var gz := int(round(head.z)) + oz
		if occupied.has(Vector3i(gx, 0, gz)):
			continue
		if floor_manager and floor_manager.is_tile_obstacle_at_grid(gx, gz):
			continue
		var p: Node3D = PowerUpScript.new()
		p.ptype = ptype
		add_child(p)
		p.global_position = Vector3(float(gx), 0.3, float(gz))
		active_power_ups[ptype] = p
		return


func _check_power_up_pickups(head: Vector3) -> void:
	for ptype in active_power_ups.keys().duplicate():
		var p := active_power_ups[ptype] as Node3D
		if not is_instance_valid(p):
			active_power_ups.erase(ptype)
			continue
		if Vector2(head.x - p.global_position.x, head.z - p.global_position.z).length_squared() < 0.25:
			_apply_power_up_effect(ptype, p.global_position)
			if p.has_method("pop_out_and_free"):
				p.pop_out_and_free()
			else:
				p.queue_free()
			active_power_ups.erase(ptype)


func _apply_power_up_effect(ptype: String, at: Vector3) -> void:
	Chiptune.play_sfx("powerup_" + ptype)
	_haptic(30)
	match ptype:
		"rainbow":
			is_invincible = true
			_invincible_timer = RAINBOW_DURATION
			snake.set_rainbow_mode(true)
		"yellow":
			is_yellow_mode = true
			_yellow_timer = YELLOW_DURATION
			snake.set_sphere_mode(true)
		"blue":
			is_spike_mode = true
			_spike_timer = SPIKE_DURATION
			snake.set_spike_mode(true)
		"red":
			_spawn_bonus_food_burst(at)
		"neon_speed":
			is_speed_boost = true
			_speed_boost_timer = BIOME_POWER_UP_DURATION["neon_speed"]
		"mirage":
			is_cloaked = true
			_cloak_timer = BIOME_POWER_UP_DURATION["mirage"]
		"ice_shield":
			is_shielded = true
			_shield_timer = BIOME_POWER_UP_DURATION["ice_shield"]
			_add_shield_visual()
		"boulder_burst":
			_boulder_burst(at)
		"crystal_growth":
			snake.grow(5)
		"magma_trail":
			is_magma_mode = true
			_magma_mode_timer = BIOME_POWER_UP_DURATION["magma_trail"]
		"laser":
			is_laser_mode = true
			_laser_timer = LASER_DURATION
			_add_laser_visual()
		"scatter":
			_fire_scatter_shot()
		"nova":
			_nova_blast(at)


func _tick_power_up_effects(delta: float) -> void:
	if is_invincible:
		_invincible_timer -= delta
		if _invincible_timer <= 0.0:
			is_invincible = false
			snake.set_rainbow_mode(false)
	if is_yellow_mode:
		_yellow_timer -= delta
		if _yellow_timer <= 0.0:
			is_yellow_mode = false
			snake.set_sphere_mode(false)
	if is_spike_mode:
		_spike_timer -= delta
		if _spike_timer <= 0.0:
			is_spike_mode = false
			snake.set_spike_mode(false)
	if is_speed_boost:
		_speed_boost_timer -= delta
		if _speed_boost_timer <= 0.0:
			is_speed_boost = false
	if is_cloaked:
		_cloak_timer -= delta
		if _cloak_timer <= 0.0:
			is_cloaked = false
	if is_shielded:
		_shield_timer -= delta
		if _shield_timer <= 0.0:
			is_shielded = false
			_remove_shield_visual()
	if is_magma_mode:
		_magma_mode_timer -= delta
		if _magma_mode_timer <= 0.0:
			is_magma_mode = false
	if is_laser_mode:
		_laser_timer -= delta
		if _laser_timer <= 0.0:
			is_laser_mode = false
			_remove_laser_visual()


func _add_shield_visual() -> void:
	if _shield_visual and is_instance_valid(_shield_visual):
		return
	var sphere := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.65
	sm.height = 1.3
	sphere.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.85, 1.0, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.8, 1.0)
	mat.emission_energy_multiplier = 1.2
	sphere.material_override = mat
	add_child(sphere)
	_shield_visual = sphere


func _remove_shield_visual() -> void:
	if _shield_visual and is_instance_valid(_shield_visual):
		_shield_visual.queue_free()
	_shield_visual = null


func _boulder_burst(at: Vector3) -> void:
	if not floor_manager:
		return
	var cx := int(round(at.x))
	var cz := int(round(at.z))
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			if dx * dx + dz * dz > 4:
				continue
			var gx := cx + dx
			var gz := cz + dz
			if floor_manager.is_tile_obstacle_at_grid(gx, gz):
				floor_manager.destroy_obstacle_at_grid(gx, gz)


# Instant nova: destroys every obstacle and kills every enemy snake within
# NOVA_RADIUS of the player, in one shot -- the "everything" version of the
# boulder burst above, not biome-locked, bigger radius, hits enemies too.
func _nova_blast(at: Vector3) -> void:
	var cx := int(round(at.x))
	var cz := int(round(at.z))
	if floor_manager:
		for dx in range(-NOVA_RADIUS, NOVA_RADIUS + 1):
			for dz in range(-NOVA_RADIUS, NOVA_RADIUS + 1):
				if dx * dx + dz * dz > NOVA_RADIUS * NOVA_RADIUS:
					continue
				var gx := cx + dx
				var gz := cz + dz
				if floor_manager.is_tile_obstacle_at_grid(gx, gz):
					floor_manager.destroy_obstacle_at_grid(gx, gz)
	var radius_sq := float(NOVA_RADIUS * NOVA_RADIUS)
	for e in enemy_snakes.duplicate():
		if not is_instance_valid(e):
			continue
		for seg: Vector3 in e.segments:
			if Vector2(seg.x - at.x, seg.z - at.z).length_squared() <= radius_sq:
				_damage_enemy(e, true)
				break
	_spawn_particle_burst(at, Color(1.0, 0.55, 0.15), 24)


# Fires at up to N distinct nearest enemies at once (N scales with current
# segment count, 1-4) rather than one bullet homing to a single target --
# the "scatter" read on the existing turret-fire system.
func _fire_scatter_shot() -> void:
	if not snake or snake.segments.is_empty():
		return
	var head := snake.segments.front() as Vector3
	# Always show something happened, even with no enemies around to actually
	# shoot at -- otherwise this power-up is silent and looks like it did
	# nothing at all when the run happens to be enemy-free at the moment.
	_spawn_particle_burst(Vector3(head.x, 0.5, head.z), Color(1.0, 0.55, 0.1), 18)
	Chiptune.play_sfx("player_shot")

	var count := clampi(1 + int(snake.segments.size() / SCATTER_SEGMENTS_PER_TIER), 1, 4)
	var targets := _nearest_enemies(head, count)
	for t in targets:
		_spawn_player_bullet(Vector3(head.x, 0.5, head.z), t)


func _nearest_enemies(from: Vector3, max_count: int) -> Array:
	var candidates: Array = []
	for e in enemy_snakes:
		if not is_instance_valid(e):
			continue
		if e.behavior == "burrower" and e.is_burrowed:
			continue
		candidates.append(e)
	candidates.sort_custom(func(a, b): return (a.segments[0] as Vector3).distance_squared_to(from) < (b.segments[0] as Vector3).distance_squared_to(from))
	return candidates.slice(0, mini(max_count, candidates.size()))


# Continuously scans a line of grid cells ahead of the head (along the
# current movement direction) while the laser power-up is active: the beam
# stops at -- and destroys -- the first obstacle it reaches, and kills any
# enemy snake segment caught anywhere along its current length.
func _tick_laser(delta: float) -> void:
	if not is_laser_mode or not snake or snake.segments.is_empty():
		return
	var head := snake.segments.front() as Vector3
	var dir: Vector3 = snake.get_direction()
	var length := 0.6
	var hit_grid: Vector2i = Vector2i.ZERO
	var hit_obstacle := false
	for i in range(1, LASER_RANGE + 1):
		var gx := int(round(head.x + dir.x * i))
		var gz := int(round(head.z + dir.z * i))
		if floor_manager and floor_manager.is_tile_obstacle_at_grid(gx, gz):
			hit_obstacle = true
			hit_grid = Vector2i(gx, gz)
			length = float(i) - 0.5
			break
		length = float(i)
	_update_laser_visual(head, dir, length)

	_laser_tick_timer += delta
	if _laser_tick_timer < LASER_TICK_INTERVAL:
		return
	_laser_tick_timer = 0.0

	if hit_obstacle and floor_manager:
		floor_manager.destroy_obstacle_at_grid(hit_grid.x, hit_grid.y)
	for e in enemy_snakes.duplicate():
		if not is_instance_valid(e):
			continue
		if e.behavior == "burrower" and e.is_burrowed:
			continue
		for seg: Vector3 in e.segments:
			if _point_in_beam(seg, head, dir, length):
				_damage_enemy(e, true)
				break


func _point_in_beam(pos: Vector3, origin: Vector3, dir: Vector3, length: float) -> bool:
	var rel := pos - origin
	var forward := rel.dot(dir)
	if forward < 0.4 or forward > length + 0.4:
		return false
	var perp := rel - dir * forward
	return perp.length_squared() < 0.3


func _add_laser_visual() -> void:
	if _laser_visual and is_instance_valid(_laser_visual):
		return
	var beam := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.22, 0.22, 1.0)
	beam.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.4, 1.0, 1.0, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.3, 1.0, 1.0)
	mat.emission_energy_multiplier = 3.0
	beam.material_override = mat
	add_child(beam)
	_laser_visual = beam

	# Continuous sparkle trail along the beam so it's clearly visible even when
	# it isn't currently touching an obstacle or enemy -- a child of the beam
	# mesh so it automatically inherits the beam's per-frame position/rotation/
	# length (the beam's own scale.z stretches this emitter's local emission
	# box the same way it stretches the mesh), no separate per-frame update
	# needed, and it gets cleaned up for free when the beam is freed.
	var particles := GPUParticles3D.new()
	particles.emitting = true
	particles.amount = 24
	particles.lifetime = 0.35
	particles.local_coords = false
	var pmesh := QuadMesh.new()
	pmesh.size = Vector2(0.1, 0.1)
	var pmat := StandardMaterial3D.new()
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pmat.albedo_color = Color(0.6, 1.0, 1.0, 1.0)
	pmat.emission_enabled = true
	pmat.emission = Color(0.5, 1.0, 1.0)
	pmat.emission_energy_multiplier = 2.5
	pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pmesh.material = pmat
	particles.draw_pass_1 = pmesh
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(0.11, 0.11, 0.5)
	proc.direction = Vector3(0, 1, 0)
	proc.spread = 50.0
	proc.initial_velocity_min = 0.3
	proc.initial_velocity_max = 0.9
	proc.gravity = Vector3.ZERO
	proc.scale_min = 0.6
	proc.scale_max = 1.2
	proc.color = Color(0.6, 1.0, 1.0)
	particles.process_material = proc
	beam.add_child(particles)


func _remove_laser_visual() -> void:
	if _laser_visual and is_instance_valid(_laser_visual):
		_laser_visual.queue_free()
	_laser_visual = null


func _update_laser_visual(head: Vector3, dir: Vector3, length: float) -> void:
	if not _laser_visual or not is_instance_valid(_laser_visual):
		return
	_laser_visual.scale = Vector3(1.0, 1.0, length)
	_laser_visual.global_position = Vector3(head.x, 0.5, head.z) + dir * (length * 0.5)
	_laser_visual.basis = Basis(Quaternion(Vector3.BACK, dir))


func _drop_magma_trail(pos: Vector3) -> void:
	if _magma_trail.has(pos):
		_magma_trail[pos]["time"] = MAGMA_TRAIL_TILE_LIFETIME
		return
	var mark := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 0.04, 0.7)
	mark.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.05, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.25, 0.0)
	mat.emission_energy_multiplier = 2.0
	mark.material_override = mat
	add_child(mark)
	mark.global_position = Vector3(pos.x, 0.28, pos.z)
	_magma_trail[pos] = {"time": MAGMA_TRAIL_TILE_LIFETIME, "node": mark}


func _tick_magma_trail(delta: float) -> void:
	if _magma_trail.is_empty():
		return
	var expired: Array = []
	for pos in _magma_trail:
		var entry: Dictionary = _magma_trail[pos]
		entry["time"] -= delta
		if entry["time"] <= 0.0:
			expired.append(pos)
	for pos in expired:
		var entry: Dictionary = _magma_trail[pos]
		var node := entry.get("node") as Node3D
		if is_instance_valid(node):
			node.queue_free()
		_magma_trail.erase(pos)


func _drop_enemy_magma_trail(pos: Vector3) -> void:
	if _enemy_magma_trail.has(pos):
		_enemy_magma_trail[pos]["time"] = MAGMA_TRAIL_TILE_LIFETIME
		return
	var mark := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 0.04, 0.7)
	mark.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.15, 0.35, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.1, 0.3)
	mat.emission_energy_multiplier = 2.0
	mark.material_override = mat
	add_child(mark)
	mark.global_position = Vector3(pos.x, 0.28, pos.z)
	_enemy_magma_trail[pos] = {"time": MAGMA_TRAIL_TILE_LIFETIME, "node": mark}


func _tick_enemy_magma_trail(delta: float) -> void:
	if _enemy_magma_trail.is_empty():
		return
	var expired: Array = []
	for pos in _enemy_magma_trail:
		var entry: Dictionary = _enemy_magma_trail[pos]
		entry["time"] -= delta
		if entry["time"] <= 0.0:
			expired.append(pos)
	for pos in expired:
		var entry: Dictionary = _enemy_magma_trail[pos]
		var node := entry.get("node") as Node3D
		if is_instance_valid(node):
			node.queue_free()
		_enemy_magma_trail.erase(pos)


func _spawn_bonus_food_burst(origin: Vector3) -> void:
	for i in range(4):
		var f := _make_food_node()
		f.name = "BonusFood%d" % randi()
		var placed := false
		for _attempt in range(20):
			var ox := rng.randi_range(-2, 2)
			var oz := rng.randi_range(-2, 2)
			var gx := int(round(origin.x)) + ox
			var gz := int(round(origin.z)) + oz
			if floor_manager and floor_manager.is_tile_obstacle_at_grid(gx, gz):
				continue
			f.global_position = Vector3(float(gx), 0.45, float(gz))
			placed = true
			break
		if not placed:
			f.global_position = origin
		add_child(f)
		if f.has_method("pop_in"):
			f.pop_in()
		bonus_foods.append(f)
		_bonus_food_expiry[f] = BONUS_FOOD_LIFETIME


func _tick_bonus_foods(delta: float) -> void:
	if bonus_foods.is_empty():
		return
	var to_remove: Array = []
	for _f in bonus_foods:
		var f := _f as Node3D
		if not is_instance_valid(f):
			to_remove.append(_f)
			continue
		var remaining: float = _bonus_food_expiry.get(f, 0.0) - delta
		_bonus_food_expiry[f] = remaining
		if remaining <= 0.0:
			if f.has_method("pop_out_and_free"):
				f.pop_out_and_free()
			else:
				f.queue_free()
			to_remove.append(_f)
	for _f in to_remove:
		bonus_foods.erase(_f)
		_bonus_food_expiry.erase(_f)


func _check_bonus_food_pickups(head: Vector3) -> void:
	if bonus_foods.is_empty():
		return
	var eaten: Array = []
	for _f in bonus_foods:
		var f := _f as Node3D
		if not is_instance_valid(f):
			continue
		if Vector2(head.x - f.global_position.x, head.z - f.global_position.z).length_squared() < 0.25:
			score += 1
			food_eaten_count += 1
			Chiptune.play_sfx("eat")
			_spawn_particle_burst(f.global_position, Color(1.0, 0.14, 0.14), 10)
			if score > high_score:
				high_score = score
				_save_high_score()
				Chiptune.play_sfx("high_score")
				_haptic(50)
				_new_high_score_this_run = true
			food_eaten.emit(score)
			snake.grow(2 if is_yellow_mode else 1)
			eaten.append(f)
	for f in eaten:
		if f.has_method("pop_out_and_free"):
			f.pop_out_and_free()
		else:
			f.queue_free()
		bonus_foods.erase(f)
		_bonus_food_expiry.erase(f)


func _check_player_vs_enemies(head: Vector3) -> void:
	for e in enemy_snakes.duplicate():
		if not is_instance_valid(e):
			enemy_snakes.erase(e)
			continue
		if e.behavior == "burrower" and e.is_burrowed:
			continue
		if head in e.segments:
			if is_spike_mode or is_shielded:
				_damage_enemy(e, true)
			else:
				_start_death()
				return


func _update_enemy_spawns() -> void:
	var eligible: Array = ENEMY_TYPES.duplicate()
	var biome_extra: String = BIOME_ENEMY.get(floor_manager.biome, "") if floor_manager else ""
	if biome_extra != "" and not eligible.has(biome_extra):
		eligible.append(biome_extra)
	for t in eligible:
		var count := 0
		for e in enemy_snakes:
			if is_instance_valid(e) and e.behavior == t:
				count += 1
		if count >= ENEMY_CAP_PER_TYPE:
			continue
		if rng.randf() < clampf(enemy_spawn_chance[t] * _dda_enemy_mult, 0.0, 0.95):
			_spawn_enemy(t)


func _spawn_enemy(behavior: String) -> void:
	if not snake or snake.segments.is_empty():
		return
	var head := snake.segments.front() as Vector3
	var occupied: Dictionary = {}
	for seg: Vector3 in snake.segments:
		occupied[seg] = true
	for e in enemy_snakes:
		if is_instance_valid(e):
			for seg: Vector3 in e.segments:
				occupied[seg] = true

	for _attempt in range(40):
		var ox := rng.randi_range(-14, 14)
		var oz := rng.randi_range(-14, 14)
		if ox * ox + oz * oz < 64:
			continue
		var gx := int(round(head.x)) + ox
		var gz := int(round(head.z)) + oz
		var pos := Vector3(float(gx), 0.0, float(gz))
		if occupied.has(pos):
			continue
		if floor_manager and floor_manager.is_tile_obstacle_at_grid(gx, gz):
			continue

		var power := ""
		if behavior == "hoarder":
			power = ENEMY_HOARDER_POWERS[rng.randi_range(0, ENEMY_HOARDER_POWERS.size() - 1)]

		var enemy: Node3D = EnemyScript.new()
		enemy.fire_interval_scale = _dda_enemy_turret_scale
		add_child(enemy)
		enemy.setup(pos, behavior, power, enemy_segment_count.get(behavior, 3))
		enemy_snakes.append(enemy)
		return


func _step_enemy_snakes() -> void:
	if enemy_snakes.is_empty() or is_cloaked:
		return
	var player_head := snake.segments.front() as Vector3
	var player_dir: Vector3 = snake.get_direction()

	var occupied: Dictionary = {}
	for seg: Vector3 in snake.segments:
		occupied[seg] = true
	for e in enemy_snakes:
		if is_instance_valid(e) and not (e.behavior == "burrower" and e.is_burrowed):
			for seg: Vector3 in e.segments:
				occupied[seg] = true

	for e in enemy_snakes.duplicate():
		if not is_instance_valid(e):
			enemy_snakes.erase(e)
			continue
		if e.behavior == "burrower" and e.is_burrowed:
			continue
		if not e.should_move_this_tick():
			continue

		if e.should_recompute_direction():
			var target: Vector3 = _enemy_target(e, player_head, player_dir)
			e.choose_direction(target, _make_enemy_blocked_check(e, occupied))

		if not _resolve_enemy_move(e, occupied):
			continue

		if e.behavior == "speedster":
			var target2: Vector3 = _enemy_target(e, player_head, player_dir)
			e.choose_direction(target2, _make_enemy_blocked_check(e, occupied))
			_resolve_enemy_move(e, occupied)


func _enemy_target(e: Node3D, player_head: Vector3, player_dir: Vector3) -> Vector3:
	if e.behavior == "stealer":
		return _nearest_food_near_player(e.segments[0])
	elif e.behavior == "thief":
		return _nearest_active_powerup(e.segments[0])
	elif e.behavior == "boxer":
		return player_head + player_dir * 3.0
	elif e.behavior == "shard_wraith":
		return player_head + Vector3(rng.randf_range(-3.0, 3.0), 0.0, rng.randf_range(-3.0, 3.0))
	return player_head


func _make_enemy_blocked_check(e: Node3D, occupied: Dictionary) -> Callable:
	var fm := floor_manager
	var is_golem: bool = e.behavior == "rock_golem"
	return func(pos: Vector3) -> bool:
		if fm and fm.is_tile_obstacle_at_grid(int(round(pos.x)), int(round(pos.z))):
			return not is_golem
		return occupied.has(pos) or _magma_trail.has(pos)


func _resolve_enemy_move(e: Node3D, occupied: Dictionary) -> bool:
	var next_head: Vector3 = e.segments[0] + e.direction
	var fm := floor_manager
	var gx := int(round(next_head.x))
	var gz := int(round(next_head.z))
	var fatal := false
	if fm and fm.is_tile_obstacle_at_grid(gx, gz):
		if e.behavior == "rock_golem":
			fm.destroy_obstacle_at_grid(gx, gz)
		else:
			fatal = true
	elif occupied.has(next_head):
		fatal = true
	elif _magma_trail.has(next_head):
		fatal = true

	if fatal:
		_kill_enemy(e, true)
		return false

	e.advance()
	for seg: Vector3 in e.segments:
		occupied[seg] = true

	if e.behavior == "stealer":
		_enemy_try_steal_food(e)
	elif e.behavior == "thief":
		_enemy_try_steal_powerup(e)
	elif e.behavior == "magma_serpent" and e.segments.size() > 1:
		_drop_enemy_magma_trail(e.segments[1])
	return true


func _nearest_food_near_player(from: Vector3) -> Vector3:
	var player_head := snake.segments.front() as Vector3
	var best: Vector3 = player_head
	var best_dist := INF
	for _f in all_foods:
		var f := _f as Node3D
		if not is_instance_valid(f):
			continue
		var fpos: Vector3 = f.global_position
		if fpos.distance_squared_to(player_head) > 64.0:
			continue
		var d: float = fpos.distance_squared_to(from)
		if d < best_dist:
			best_dist = d
			best = fpos
	return best


func _nearest_active_powerup(from: Vector3) -> Vector3:
	var best: Vector3 = snake.segments.front() as Vector3
	var best_dist := INF
	for ptype in active_power_ups:
		var p := active_power_ups[ptype] as Node3D
		if not is_instance_valid(p):
			continue
		var d: float = p.global_position.distance_squared_to(from)
		if d < best_dist:
			best_dist = d
			best = p.global_position
	return best


func _enemy_try_steal_food(e: Node3D) -> void:
	var ehead: Vector3 = e.segments[0]
	for _f in all_foods:
		var f := _f as Node3D
		if not is_instance_valid(f):
			continue
		if Vector2(ehead.x - f.global_position.x, ehead.z - f.global_position.z).length_squared() < 0.25:
			e.grow_pending += 1
			Chiptune.play_sfx("steal")
			_spawn_food_at(f)
			_refresh_food_pool()
			return


func _enemy_try_steal_powerup(e: Node3D) -> void:
	var ehead: Vector3 = e.segments[0]
	for ptype in active_power_ups.keys().duplicate():
		var p := active_power_ups[ptype] as Node3D
		if not is_instance_valid(p):
			active_power_ups.erase(ptype)
			continue
		if Vector2(ehead.x - p.global_position.x, ehead.z - p.global_position.z).length_squared() < 0.25:
			e.grow_pending += 1
			Chiptune.play_sfx("steal")
			if p.has_method("pop_out_and_free"):
				p.pop_out_and_free()
			else:
				p.queue_free()
			active_power_ups.erase(ptype)
			return


func _kill_enemy(e: Node3D, reward: bool) -> void:
	if not is_instance_valid(e):
		return
	var pos: Vector3 = e.segments[0] if not e.segments.is_empty() else e.global_position
	Chiptune.play_sfx("enemy_down")
	_spawn_enemy_debris(pos)
	_spawn_particle_burst(pos, Color(0.85, 0.85, 0.9), 14)
	enemy_snakes.erase(e)
	e.queue_free()
	_enemies_killed_count += 1
	if reward:
		_spawn_bonus_food_burst(pos)


# Player-inflicted hit (contact, bullet, laser, nova): removes one enemy
# segment rather than killing outright, so a longer enemy survives more
# hits. Only forwards to the full _kill_enemy (debris/reward/score) once the
# enemy actually runs out of segments. Environmental enemy deaths (running
# into an obstacle, itself, or another snake in _resolve_enemy_move) are not
# routed through here -- those are AI failures, not a "hit received".
func _damage_enemy(e: Node3D, reward: bool) -> void:
	if not is_instance_valid(e):
		return
	if e.take_hit():
		_kill_enemy(e, reward)
		return
	Chiptune.play_sfx("hit")
	_spawn_particle_burst(e.segments[0] as Vector3, Color(0.85, 0.85, 0.9), 6)


func _spawn_enemy_debris(at: Vector3) -> void:
	var color := Color(0.85, 0.85, 0.9, 1.0)
	for i in range(6):
		var chunk := MeshInstance3D.new()
		var cm := BoxMesh.new()
		var s := rng.randf_range(0.14, 0.26)
		cm.size = Vector3(s, s, s)
		chunk.mesh = cm

		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 2.0
		chunk.material_override = mat
		chunk.global_position = at
		add_child(chunk)

		var dir := Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(0.3, 1.0),
			rng.randf_range(-1.0, 1.0)
		).normalized()
		var target := at + dir * rng.randf_range(0.7, 1.4)

		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(chunk, "global_position", target, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(chunk, "scale", Vector3.ZERO, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		get_tree().create_timer(0.45).timeout.connect(chunk.queue_free)


func _get_current_speed() -> float:
	var effective_food_count := food_eaten_count
	if _speed_ramp_food_count >= 0:
		effective_food_count = _speed_ramp_food_count
	var base_speed: float = max(0.06, initial_speed - (effective_food_count / speed_increase_interval) * speed_increment)
	if is_speed_boost:
		base_speed *= 0.6
	return base_speed


func _trigger_game_over() -> void:
	set_process_input(false)
	_on_game_over(score)


func _game_over_input_locked() -> bool:
	# True while a just-ended run should hold on the leaderboard: through the
	# death animation (leaderboard not up yet) and for the lockout window after
	# it appears. False during normal play, so the R-key restart still works
	# mid-run.
	if is_dying:
		return true
	if is_game_over:
		return Time.get_ticks_msec() - _game_over_shown_ms < GAME_OVER_TAP_LOCKOUT_MS
	return false


func restart() -> void:
	Engine.time_scale = 1.0
	# Don't reload straight away: play the "cover" half of the transition curtain
	# (fade to black while the iso snakes sweep in) and only reload once the
	# screen is fully black. The reloaded scene plays the "reveal" half from
	# _ready(). If a transition is already running, ignore the repeat.
	if is_transitioning:
		return
	_build_transition_curtain(false)
	is_transitioning = true
	_transition_phase = TransitionPhase.COVER
	_transition_time = 0.0
	_transition_cover_action = CoverAction.RELOAD


func _build_pause_ui() -> void:
	var btn_layer := CanvasLayer.new()
	btn_layer.name = "PauseButtonLayer"
	btn_layer.layer = 13
	add_child(btn_layer)

	_pause_button = Button.new()
	_pause_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_pause_button.offset_left = -100.0
	_pause_button.offset_top = -100.0
	_pause_button.offset_right = -36.0
	_pause_button.offset_bottom = -36.0
	_pause_button.text = ""
	_pause_button.flat = true
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	btn_style.set_corner_radius_all(12)
	_pause_button.add_theme_stylebox_override("normal", btn_style)
	_pause_button.add_theme_stylebox_override("hover", btn_style)
	_pause_button.add_theme_stylebox_override("pressed", btn_style)
	_pause_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_pause_button.pressed.connect(_on_pause_button_pressed)
	_pause_button.visible = false
	btn_layer.add_child(_pause_button)

	for bar_offset in [18.0, 36.0]:
		var bar := ColorRect.new()
		bar.color = Color(1.0, 1.0, 1.0, 0.9)
		bar.set_anchors_preset(Control.PRESET_CENTER_LEFT)
		bar.offset_left = bar_offset
		bar.offset_top = -14.0
		bar.offset_right = bar_offset + 8.0
		bar.offset_bottom = 14.0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pause_button.add_child(bar)

	_pause_layer = CanvasLayer.new()
	_pause_layer.name = "PauseLayer"
	_pause_layer.layer = 40
	_pause_layer.visible = false
	add_child(_pause_layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_layer.add_child(root)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.02, 0.04, 0.88)
	root.add_child(bg)

	var title := Label.new()
	title.text = "PAUSED"
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 640
	title.offset_bottom = 720
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	root.add_child(title)

	var resume_btn := _make_pause_menu_button("RESUME", 800.0)
	resume_btn.pressed.connect(_on_resume_button_pressed)
	root.add_child(resume_btn)

	var restart_btn := _make_pause_menu_button("RESTART", 920.0)
	restart_btn.pressed.connect(restart)
	root.add_child(restart_btn)

	var quit_btn := _make_pause_menu_button("QUIT", 1040.0)
	quit_btn.pressed.connect(_on_quit_button_pressed)
	root.add_child(quit_btn)


func _make_pause_menu_button(label_text: String, y: float) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.set_anchors_preset(Control.PRESET_TOP_WIDE)
	btn.offset_left = 240.0
	btn.offset_right = -240.0
	btn.offset_top = y
	btn.offset_bottom = y + 90.0
	btn.add_theme_font_size_override("font_size", 26)
	return btn


func _on_pause_button_pressed() -> void:
	print("[pause-debug] BUTTON PRESSED")
	_toggle_pause(true)


func _on_resume_button_pressed() -> void:
	_toggle_pause(false)


func _on_quit_button_pressed() -> void:
	get_tree().quit()


func _toggle_pause(paused: bool) -> void:
	if paused and game_state != GameState.PLAYING:
		return
	is_paused = paused
	if _pause_layer:
		_pause_layer.visible = paused


func _build_hit_flash_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HitFlashLayer"
	layer.layer = 14
	add_child(layer)

	_hit_flash_rect = ColorRect.new()
	_hit_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hit_flash_rect.color = Color(1.0, 0.05, 0.05, 0.0)
	_hit_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hit_flash_rect)


func _flash_hit() -> void:
	if not _hit_flash_rect:
		return
	if _hit_flash_tween and _hit_flash_tween.is_valid():
		_hit_flash_tween.kill()
	_hit_flash_rect.color.a = 0.4
	_hit_flash_tween = create_tween()
	_hit_flash_tween.tween_property(_hit_flash_rect, "color:a", 0.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _trigger_camera_shake(amount: float, duration: float = 0.25) -> void:
	_shake_amount = amount
	_shake_duration = duration
	_shake_time = duration


func _tick_camera_shake(delta: float) -> void:
	if not _camera3d or _shake_time <= 0.0:
		return
	_shake_time -= delta
	if _shake_time <= 0.0:
		_camera3d.h_offset = 0.0
		_camera3d.v_offset = 0.0
		return
	var falloff := _shake_time / _shake_duration
	_camera3d.h_offset = rng.randf_range(-1.0, 1.0) * _shake_amount * falloff
	_camera3d.v_offset = rng.randf_range(-1.0, 1.0) * _shake_amount * falloff


func _tick_menu_camera_drift(delta: float) -> void:
	_tick_third_person_menu_camera(delta)
	_tick_menu_snake_wander(delta)


# Orients the third-person rig's pivot so its forward (-Z) faces the demo
# snake's current travel direction -- the SpringArm3D child (pitched down
# slightly, zero extra yaw) then automatically settles the camera behind
# that direction, looking forward along it. Slerped rather than snapped so
# a turn during the wander doesn't jump-cut the shot.
func _tick_third_person_menu_camera(delta: float) -> void:
	if not _third_person_pivot or not snake or snake.segments.is_empty():
		return
	var dir: Vector3 = snake.get_direction()
	if dir == Vector3.ZERO:
		return
	var target_basis: Basis = Basis.looking_at(dir, Vector3.UP)
	var t: float = clamp(delta * THIRD_PERSON_TURN_SPEED, 0.0, 1.0)
	var xform: Transform3D = _third_person_pivot.global_transform
	xform.basis = xform.basis.slerp(target_basis, t)
	_third_person_pivot.global_transform = xform


# Lets the snake amble around on its own for the title-screen "attract mode"
# instead of just sitting there. Picks a random direction that won't
# immediately hit itself or an obstacle where possible; if every direction is
# blocked, step() just quietly no-ops for that tick rather than "dying" --
# there's no game-over handling wired up for MENU state, deliberately.
func _tick_menu_snake_wander(delta: float) -> void:
	if not snake or snake.segments.is_empty():
		return
	_menu_snake_step_timer += delta
	if _menu_snake_step_timer < MENU_SNAKE_STEP_INTERVAL:
		return
	_menu_snake_step_timer = 0.0

	var current_dir: Vector3 = snake.get_direction()
	var head: Vector3 = snake.segments.front()
	var occupied: Dictionary = {}
	for seg: Vector3 in snake.segments:
		occupied[seg] = true

	var candidates: Array = [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]
	candidates.shuffle()
	for d in candidates:
		if d == -current_dir and snake.segments.size() > 1:
			continue
		var next: Vector3 = head + d
		if occupied.has(next):
			continue
		if floor_manager and floor_manager.has_method("is_tile_obstacle_at") and floor_manager.is_tile_obstacle_at(next):
			continue
		snake.set_direction(d)
		break

	snake.step()


func _apply_menu_camera_state() -> void:
	if _third_person_camera:
		_third_person_camera.current = true
	if _tilt_shift_material:
		_tilt_shift_material.set_shader_parameter("focus_half_width", TILT_SHIFT_MENU_FOCUS_WIDTH)
		_tilt_shift_material.set_shader_parameter("max_blur", TILT_SHIFT_MENU_MAX_BLUR)


func _apply_gameplay_camera_state() -> void:
	if _camera3d:
		_camera3d.current = true
	if _tilt_shift_material:
		_tilt_shift_material.set_shader_parameter("focus_half_width", TILT_SHIFT_NORMAL_FOCUS_WIDTH)
		_tilt_shift_material.set_shader_parameter("max_blur", TILT_SHIFT_NORMAL_MAX_BLUR)


func _start_game() -> void:
	game_state = GameState.PLAYING
	if _title_layer:
		_title_layer.visible = false
	if _camera_crane_pivot:
		_camera_crane_pivot.rotation_degrees.y = MENU_CAMERA_BASE_YAW
	if _pause_button:
		_pause_button.visible = true
	if snake:
		snake.reset_to_spawn()
	if floor_manager:
		floor_manager.reset_to_gameplay()
	_apply_gameplay_camera_state()
	Chiptune.play_sfx("start")
	_show_level_banner(false)


func _build_touch_controls() -> void:
	var layer := CanvasLayer.new()
	layer.name = "TouchControlsLayer"
	layer.layer = 25
	add_child(layer)

	_joystick = JoystickScript.new()
	layer.add_child(_joystick)
	_joystick.camera = get_viewport().get_camera_3d()
	_joystick.direction_changed.connect(_touch_direction_pressed)


func _show_level_banner(is_level_up: bool) -> void:
	if not floor_manager:
		return
	var biome_id: String = floor_manager.biome

	var layer := CanvasLayer.new()
	layer.layer = 15
	add_child(layer)

	var title_text := "LEVEL %d/%d: %s" % [current_level + 1, LEVEL_BIOMES.size(), _biome_display_name(biome_id)]
	if is_new_game_plus:
		title_text = "NG+ " + title_text

	var label := Label.new()
	label.text = title_text
	label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	label.offset_left = 24
	label.offset_right = -24
	label.offset_top = 72
	label.offset_bottom = 210
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Safety net: this text includes the biome name and NG+ prefix, both
	# runtime-built and never verified against the pixel font's real glyph
	# width on-device -- wrap instead of clipping off-screen if it runs wide.
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.add_theme_font_size_override("font_size", 40)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	layer.add_child(label)

	var sub_label: Label = null
	if is_level_up:
		sub_label = Label.new()
		sub_label.text = "LEVEL UP!"
		sub_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
		sub_label.offset_top = 216
		sub_label.offset_bottom = 262
		sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub_label.add_theme_font_size_override("font_size", 26)
		sub_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
		sub_label.add_theme_constant_override("outline_size", 6)
		sub_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
		layer.add_child(sub_label)

	var tw := create_tween()
	tw.tween_interval(2.5)
	tw.tween_property(label, "modulate:a", 0.0, 1.0)
	if sub_label:
		tw.parallel().tween_property(sub_label, "modulate:a", 0.0, 1.0)
	tw.tween_callback(layer.queue_free)


func _show_win_banner() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 16
	add_child(layer)

	var label := Label.new()
	label.text = "ALL LEVELS CLEARED\nNEW GAME PLUS UNLOCKED"
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.offset_left = -400
	label.offset_right = 400
	label.offset_top = -80
	label.offset_bottom = 80
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 42)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
	label.add_theme_constant_override("outline_size", 10)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	layer.add_child(label)

	var tw := create_tween()
	tw.tween_interval(3.5)
	tw.tween_property(label, "modulate:a", 0.0, 1.2)
	tw.tween_callback(layer.queue_free)


func _biome_display_name(biome_id: String) -> String:
	match biome_id:
		"desert":
			return "DESERT"
		"glacier":
			return "GLACIER"
		"mountain":
			return "MOUNTAIN"
		"crystal_cave":
			return "CRYSTAL CAVE"
		"volcanic":
			return "VOLCANIC"
		_:
			return "NEON"


func _load_high_score() -> int:
	if not FileAccess.file_exists(HIGH_SCORE_PATH):
		return 0
	var f := FileAccess.open(HIGH_SCORE_PATH, FileAccess.READ)
	if f == null:
		return 0
	var txt := f.get_as_text().strip_edges()
	f.close()
	if txt.is_empty():
		return 0
	return int(txt)


func _save_high_score() -> void:
	var f := FileAccess.open(HIGH_SCORE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(str(high_score))
	f.close()


func _load_leaderboard() -> void:
	best_times = []
	best_lengths = []
	if not FileAccess.file_exists(LEADERBOARD_PATH):
		return
	var f := FileAccess.open(LEADERBOARD_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var data = JSON.parse_string(txt)
	if typeof(data) == TYPE_DICTIONARY:
		best_times = data.get("times", [])
		best_lengths = data.get("lengths", [])


func _save_leaderboard() -> void:
	var f := FileAccess.open(LEADERBOARD_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"times": best_times, "lengths": best_lengths}))
	f.close()


func _dda_lerp(easy_val: float, hard_val: float) -> float:
	return lerpf(easy_val, hard_val, clampf(difficulty, 0.0, 1.0))


func _load_difficulty() -> void:
	difficulty = DDA_DEFAULT
	_dda_history = []
	if not FileAccess.file_exists(DIFFICULTY_PATH):
		return
	var f := FileAccess.open(DIFFICULTY_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) == TYPE_DICTIONARY:
		difficulty = clampf(float(data.get("difficulty", DDA_DEFAULT)), 0.0, 1.0)
		var hist = data.get("history", [])
		if typeof(hist) == TYPE_ARRAY:
			for v in hist:
				_dda_history.append(float(v))


func _save_difficulty() -> void:
	var f := FileAccess.open(DIFFICULTY_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"difficulty": difficulty, "history": _dda_history}))
	f.close()


# Resolve `difficulty` (0..1) into the concrete per-run spawn/fire knobs. Called
# once in _ready() -- a run reloads the whole scene, so these stay fixed for the
# duration of a run and only shift on the next launch after _update_difficulty().
func _apply_difficulty() -> void:
	_dda_food_bonus = int(round(_dda_lerp(DDA_FOOD_BONUS_EASY, DDA_FOOD_BONUS_HARD)))
	_dda_powerup_mult = _dda_lerp(DDA_POWERUP_MULT_EASY, DDA_POWERUP_MULT_HARD)
	_dda_powerup_interval = _dda_lerp(DDA_POWERUP_INTERVAL_EASY, DDA_POWERUP_INTERVAL_HARD)
	_dda_env_turret_interval = _dda_lerp(DDA_ENV_TURRET_INTERVAL_EASY, DDA_ENV_TURRET_INTERVAL_HARD)
	_dda_enemy_turret_scale = _dda_lerp(DDA_ENEMY_TURRET_SCALE_EASY, DDA_ENEMY_TURRET_SCALE_HARD)
	_dda_enemy_mult = _dda_lerp(DDA_ENEMY_MULT_EASY, DDA_ENEMY_MULT_HARD)
	_dda_enemy_interval = _dda_lerp(DDA_ENEMY_INTERVAL_EASY, DDA_ENEMY_INTERVAL_HARD)
	_dda_enemy_grace = _dda_lerp(DDA_ENEMY_GRACE_EASY, DDA_ENEMY_GRACE_HARD)


# Called once at death with the finished run's score + survival time. Compares
# this run against the average of recent runs and nudges the persisted dial:
# steadily worse -> easier, steadily better -> harder, within the dead-zone band
# -> unchanged. Then records this run into the rolling history and saves.
func _update_difficulty(final_score: int, final_time: float) -> void:
	var perf := float(final_score) + final_time * DDA_TIME_WEIGHT
	if not _dda_history.is_empty():
		var baseline := 0.0
		for v in _dda_history:
			baseline += v
		baseline /= _dda_history.size()
		if perf < baseline * (1.0 - DDA_DEAD_ZONE):
			difficulty = clampf(difficulty - DDA_STEP, 0.0, 1.0)  # struggling -> ease off
		elif perf > baseline * (1.0 + DDA_DEAD_ZONE):
			difficulty = clampf(difficulty + DDA_STEP, 0.0, 1.0)  # thriving -> ramp up
	_dda_history.append(perf)
	while _dda_history.size() > DDA_HISTORY_SIZE:
		_dda_history.pop_front()
	_save_difficulty()


func _record_run(final_time: float, final_length: int) -> Dictionary:
	best_times.append(final_time)
	best_times.sort()
	best_times.reverse()
	var time_rank: int = best_times.find(final_time)
	if best_times.size() > LEADERBOARD_SIZE:
		best_times.resize(LEADERBOARD_SIZE)
	if time_rank >= LEADERBOARD_SIZE:
		time_rank = -1

	best_lengths.append(final_length)
	best_lengths.sort()
	best_lengths.reverse()
	var length_rank: int = best_lengths.find(final_length)
	if best_lengths.size() > LEADERBOARD_SIZE:
		best_lengths.resize(LEADERBOARD_SIZE)
	if length_rank >= LEADERBOARD_SIZE:
		length_rank = -1

	_save_leaderboard()
	return {"time_rank": time_rank, "length_rank": length_rank}


const SPLASH_FRAME_PATH := "res://assets/splash_frames/frame_%03d.png"
const SPLASH_FRAME_COUNT := 48
const SPLASH_FRAME_DURATION := 1.0 / 8.0  # source was resampled to 8fps
const SPLASH_AUDIO_PATH := "res://assets/splash_audio.ogg"

var _splash_frames: Array = []
var _splash_frame_index: int = 0
var _splash_frame_timer: float = 0.0
var _splash_texture_rect: TextureRect
var _splash_audio: AudioStreamPlayer

# Decorative crawling snakes in the letterboxed blank strip below the splash
# artwork -- a tiny separate 3D scene rendered into a SubViewport and shown
# via a TextureRect, not related to the real gameplay Snake at all.
const SPLASH_SNAKE_LANE_HEIGHT := 650.0
const SPLASH_SNAKE_SPEED := 1.2
const SPLASH_SNAKE_WRAP := 3.2
const SPLASH_SNAKE_SEGMENT_COUNT := 6
var _splash_snake_viewport: SubViewport
var _splash_snake_mover_left: Node3D
var _splash_snake_mover_right: Node3D

func _build_splash_ui() -> void:
	_splash_layer = CanvasLayer.new()
	_splash_layer.name = "SplashLayer"
	_splash_layer.layer = 30
	add_child(_splash_layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_splash_layer.add_child(root)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	for i in range(1, SPLASH_FRAME_COUNT + 1):
		var path := SPLASH_FRAME_PATH % i
		if not ResourceLoader.exists(path):
			break
		_splash_frames.append(load(path))
	if _splash_frames.is_empty():
		return

	_splash_texture_rect = TextureRect.new()
	_splash_texture_rect.texture = _splash_frames[0]
	_splash_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_splash_texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	# Frames are native 448x672 (2:3). Fit to height instead of width now --
	# the decorative snake lane below claims the bottom SPLASH_SNAKE_LANE_HEIGHT
	# px of the 1920-tall canvas, so the logo has to fit above it (1920 - 150
	# top margin - 650 lane = 1120px tall) rather than stretching full-width.
	# Width is derived from native aspect and centered horizontally.
	var art_height := 1920.0 - 150.0 - SPLASH_SNAKE_LANE_HEIGHT
	var art_width := art_height * (448.0 / 672.0)
	_splash_texture_rect.size = Vector2(art_width, art_height)
	_splash_texture_rect.position = Vector2((1080.0 - art_width) * 0.5, 150.0)
	_splash_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_splash_texture_rect)

	if ResourceLoader.exists(SPLASH_AUDIO_PATH):
		_splash_audio = AudioStreamPlayer.new()
		_splash_audio.stream = load(SPLASH_AUDIO_PATH)
		add_child(_splash_audio)

	_build_splash_decor_snakes(root)

	var skip_label := Label.new()
	skip_label.text = "TAP TO SKIP"
	skip_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	skip_label.offset_top = -96
	skip_label.offset_bottom = -46
	skip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skip_label.add_theme_font_size_override("font_size", 23)
	skip_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.0))
	skip_label.add_theme_constant_override("outline_size", 4)
	skip_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	root.add_child(skip_label)
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(skip_label, "modulate:a", 1.0, 0.6)


func _splash_is_ready() -> bool:
	return not _splash_frames.is_empty()


func _start_splash_playback() -> void:
	_splash_frame_index = 0
	_splash_frame_timer = 0.0
	if _splash_audio and _splash_audio.stream:
		_splash_audio.play()


func _tick_splash(delta: float) -> void:
	if _splash_frames.is_empty():
		_finish_splash()
		return
	# Clamp: the first frame or two after a cold app launch can carry a huge
	# real delta (still loading/importing assets while paying for that first
	# _process call), and the while-loop below would otherwise burn through
	# it in one shot -- fast-forwarding most of the splash away instantly
	# instead of playing at the intended 8fps. Confirmed on-device: without
	# this the splash finished in ~2.5s instead of 6s.
	delta = minf(delta, SPLASH_FRAME_DURATION)
	_tick_splash_decor_snakes(delta)
	_splash_frame_timer += delta
	while _splash_frame_timer >= SPLASH_FRAME_DURATION:
		_splash_frame_timer -= SPLASH_FRAME_DURATION
		_splash_frame_index += 1
		if _splash_frame_index >= _splash_frames.size():
			_finish_splash()
			return
		_splash_texture_rect.texture = _splash_frames[_splash_frame_index]


func _build_splash_decor_snakes(parent: Control) -> void:
	_splash_snake_viewport = SubViewport.new()
	_splash_snake_viewport.size = Vector2i(1080, int(SPLASH_SNAKE_LANE_HEIGHT))
	# A SubViewport shares its parent's World3D by default (own_world_3d ==
	# false) -- without this, the decorative camera below was rendering the
	# *entire real game world* (floor tiles, obstacles, food) from a stray
	# angle, which is what that colorful block/red-dot noise actually was,
	# not a transparency bug. This gives it a fully isolated scene containing
	# only the two decorative snakes.
	_splash_snake_viewport.own_world_3d = true
	# Not using transparent_bg: this project renders in GL Compatibility mode,
	# where transparent SubViewport backgrounds are unreliable on some mobile
	# GPUs. Opaque black reads identically here anyway since the splash's own
	# backdrop is solid black.
	_splash_snake_viewport.transparent_bg = false
	_splash_snake_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_splash_snake_viewport)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 1.0)
	env_node.environment = env
	_splash_snake_viewport.add_child(env_node)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = 2.6
	cam.position = Vector3(0.0, 0.0, 10.0)
	cam.current = true
	_splash_snake_viewport.add_child(cam)

	# Lead sign +1 = travels toward +X (rightward), so the head (front
	# segment) must sit at the leading edge and the tail trail behind it in
	# -X; -1 mirrors that for leftward travel.
	_splash_snake_mover_left = _make_decor_snake(Color(0.05, 0.9, 0.3, 1.0), -1)
	_splash_snake_mover_left.position = Vector3(SPLASH_SNAKE_WRAP, 0.65, 0.0)
	_splash_snake_viewport.add_child(_splash_snake_mover_left)

	_splash_snake_mover_right = _make_decor_snake(Color(0.2, 1.0, 1.0, 1.0), 1)
	_splash_snake_mover_right.position = Vector3(-SPLASH_SNAKE_WRAP, -0.65, 0.0)
	_splash_snake_viewport.add_child(_splash_snake_mover_right)

	var display := TextureRect.new()
	display.texture = _splash_snake_viewport.get_texture()
	display.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	display.offset_top = -SPLASH_SNAKE_LANE_HEIGHT
	display.offset_bottom = 0.0
	display.stretch_mode = TextureRect.STRETCH_SCALE
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(display)


func _make_decor_snake(color: Color, lead_sign: float) -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.6
	for i in range(SPLASH_SNAKE_SEGMENT_COUNT):
		var seg := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var sz := 1.3 if i == 0 else 1.0
		bm.size = Vector3(sz, sz, sz)
		seg.mesh = bm
		seg.material_override = mat
		seg.position = Vector3(-lead_sign * float(i) * 1.05, 0.0, 0.0)
		root.add_child(seg)
	return root


func _tick_splash_decor_snakes(delta: float) -> void:
	if _splash_snake_mover_left:
		_splash_snake_mover_left.position.x -= SPLASH_SNAKE_SPEED * delta
		if _splash_snake_mover_left.position.x < -SPLASH_SNAKE_WRAP:
			_splash_snake_mover_left.position.x = SPLASH_SNAKE_WRAP
	if _splash_snake_mover_right:
		_splash_snake_mover_right.position.x += SPLASH_SNAKE_SPEED * delta
		if _splash_snake_mover_right.position.x > SPLASH_SNAKE_WRAP:
			_splash_snake_mover_right.position.x = -SPLASH_SNAKE_WRAP


func _cleanup_splash_decor_snakes() -> void:
	if _splash_snake_viewport:
		_splash_snake_viewport.queue_free()
	_splash_snake_viewport = null
	_splash_snake_mover_left = null
	_splash_snake_mover_right = null


func _finish_splash() -> void:
	if game_state != GameState.SPLASH:
		return
	if _splash_audio and _splash_audio.playing:
		_splash_audio.stop()
	_splash_layer.visible = false
	game_state = GameState.MENU
	Chiptune.music_enabled = true
	_apply_menu_camera_state()
	_cleanup_splash_decor_snakes()


# --- Transition curtain -----------------------------------------------------
# A loading-screen wipe that reuses the splash's decorative-snake idea but in
# the gameplay isometric view: several snakes crawl diagonally across the whole
# screen, alternating direction lane by lane, on top of a black curtain that
# fades in then out. Shown at two moments -- menu -> gameplay start, and between
# playthroughs on restart -- to hide the game while it swaps/reloads. Input is
# refused and the run is frozen for the curtain's whole lifetime.
#
# The beats run in strict sequence so no visible animation ever overlaps the
# heavy load frame: COVER fades to black with the snakes parked off-screen; the
# level is loaded/swapped at full black; RUN then sweeps the snakes all the way
# across on full black as the loading beat; REVEAL fades back out once they've
# crossed. A run restart reloads the entire scene, so its transition is split:
# COVER runs in the old scene and triggers the reload at full black; the fresh
# scene's _ready() opens black and plays RUN + REVEAL. The menu -> gameplay case
# has no reload, so it runs COVER -> load -> RUN -> REVEAL in the same scene. All
# phases are driven analytically from _transition_time in _tick_transition (no
# tweens), which is what makes splitting them across the reload trivial.
enum TransitionPhase { NONE, COVER, RUN, REVEAL }
enum CoverAction { NONE, START_GAME, RELOAD }

const TRANSITION_LAYER := 60            # above every other CanvasLayer (pause is 40)
const TRANSITION_FADE_TIME := 0.45      # black fade-in / fade-out duration
const TRANSITION_RUN_TIME := 1.1        # full-black beat: snakes sweep the whole screen
const TRANSITION_SNAKE_LANES := 5       # parallel snakes; even lanes go one way, odd the other
const TRANSITION_SNAKE_SPAN := 26.0     # world-X half-travel; snakes sit off-screen at |x| = SPAN
const TRANSITION_SNAKE_LANE_SPACING := 5.2  # world-Z gap between lanes (widened for the bigger snakes)
const TRANSITION_CAM_SIZE := 22.0       # ortho height framing the sweep (tune for on-screen size)
const TRANSITION_SNAKE_SEGMENTS := 6
const TRANSITION_SNAKE_SEGMENT_SIZE := 2.0   # cube edge length; scaled up from the ~1.0 splash snakes
const TRANSITION_SNAKE_SEGMENT_SPACING := 2.05  # world-X gap between segment centers
# The snakes are LIT (not unshaded like the splash decor), so a directional key
# light + ambient fill give each cube face its own tone -- the shaded, 3D read
# the flat emissive splash snakes lacked. Emission is kept low so the lighting,
# not a flat glow, drives the per-face tone difference.
const TRANSITION_LIGHT_ANGLE := Vector3(-52.0, 34.0, 0.0)  # key-light pitch/yaw (deg)
const TRANSITION_LIGHT_ENERGY := 1.35
const TRANSITION_AMBIENT_COLOR := Color(0.42, 0.45, 0.58, 1.0)
const TRANSITION_AMBIENT_ENERGY := 0.4
const TRANSITION_SNAKE_EMISSION := 0.14
const TRANSITION_SNAKE_COLORS := [
	Color(0.05, 0.9, 0.3, 1.0),
	Color(0.2, 1.0, 1.0, 1.0),
	Color(1.0, 0.3, 0.6, 1.0),
	Color(1.0, 0.8, 0.15, 1.0),
	Color(0.6, 0.4, 1.0, 1.0),
]

var is_transitioning: bool = false
var _transition_phase: int = TransitionPhase.NONE
var _transition_cover_action: int = CoverAction.NONE
var _transition_time: float = 0.0
var _transition_layer: CanvasLayer = null
var _transition_root: Control = null
var _transition_viewport: SubViewport = null
var _transition_snakes: Array = []      # [{ "node": Node3D, "sign": float }]
# Set by restart() before a reload so the reloaded scene knows to open on black
# and play the RUN + REVEAL beats. Static because it has to survive the reload.
static var _play_run_on_ready: bool = false


func _begin_menu_to_game_transition() -> void:
	if is_transitioning or game_state != GameState.MENU:
		return
	_build_transition_curtain(false)
	is_transitioning = true
	_transition_phase = TransitionPhase.COVER
	_transition_time = 0.0
	_transition_cover_action = CoverAction.START_GAME


func _tick_transition(delta: float) -> void:
	# The transition itself is cheap, but the heavy work it hides -- the scene
	# reload (restart) or the floor reset/stream (menu start) -- lands as one
	# long frame at the black midpoint. Unclamped, that frame's giant delta
	# would jump _transition_time forward and teleport the snakes/fade on the
	# other side, which reads as a stutter. Clamping the step keeps the visible
	# animation smooth across the hitch (same trick as _tick_splash); the heavy
	# frame stays hidden behind full black. NOT a sign the curtain is heavy.
	_transition_time += minf(delta, 0.05)
	if _transition_phase == TransitionPhase.COVER:
		# Fade 0 -> 1 over FADE_TIME. The snakes stay parked off-screen so nothing
		# animates across the fade -- and the heavy load frame that lands the
		# instant we go fully black has no visible sweep to stutter.
		_set_curtain_alpha(clampf(_transition_time / TRANSITION_FADE_TIME, 0.0, 1.0))
		_update_transition_snakes(0.0)
		if _transition_time >= TRANSITION_FADE_TIME:
			_on_transition_covered()
	elif _transition_phase == TransitionPhase.RUN:
		# The level is already loaded/swapped underneath full black. Hold the
		# curtain opaque and sweep the snakes all the way across (progress 0 -> 1)
		# as the loading beat -- smooth, because the load is already done.
		_set_curtain_alpha(1.0)
		_update_transition_snakes(clampf(_transition_time / TRANSITION_RUN_TIME, 0.0, 1.0))
		if _transition_time >= TRANSITION_RUN_TIME:
			_transition_phase = TransitionPhase.REVEAL
			_transition_time = 0.0
	elif _transition_phase == TransitionPhase.REVEAL:
		# Snakes have crossed off-screen (progress 1); fade 1 -> 0 over FADE_TIME
		# to reveal the loaded level.
		_set_curtain_alpha(clampf(1.0 - _transition_time / TRANSITION_FADE_TIME, 0.0, 1.0))
		_update_transition_snakes(1.0)
		if _transition_time >= TRANSITION_FADE_TIME:
			_end_transition()


func _on_transition_covered() -> void:
	match _transition_cover_action:
		CoverAction.START_GAME:
			# Same scene: do the (now hidden) menu -> gameplay swap at full black,
			# then run the snakes across and reveal.
			_transition_cover_action = CoverAction.NONE
			_start_game()
			_transition_phase = TransitionPhase.RUN
			_transition_time = 0.0
		CoverAction.RELOAD:
			# Reload the scene at full black; the fresh _ready() opens black and
			# plays the RUN + REVEAL beats.
			_transition_cover_action = CoverAction.NONE
			_play_run_on_ready = true
			skip_menu_on_ready = true
			get_tree().reload_current_scene.call_deferred()


func _end_transition() -> void:
	is_transitioning = false
	_transition_phase = TransitionPhase.NONE
	_cleanup_transition_curtain()


func _set_curtain_alpha(a: float) -> void:
	if _transition_root:
		_transition_root.modulate.a = a


func _build_transition_curtain(start_black: bool) -> void:
	_transition_layer = CanvasLayer.new()
	_transition_layer.name = "TransitionLayer"
	_transition_layer.layer = TRANSITION_LAYER
	add_child(_transition_layer)

	_transition_root = Control.new()
	_transition_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP so a stray click can't fall through to any UI button beneath the
	# curtain (input is also gated by is_transitioning, this is belt-and-braces).
	_transition_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_transition_root.modulate.a = 1.0 if start_black else 0.0
	_transition_layer.add_child(_transition_root)

	# Solid black base -- also covers the one frame before the SubViewport's
	# first render lands in the TextureRect.
	var black := ColorRect.new()
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.color = Color(0.0, 0.0, 0.0, 1.0)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_root.add_child(black)

	# Isolated 3D scene (own World3D, same reasoning as the splash decor snakes:
	# otherwise the camera renders the real game world). Opaque black background
	# reads identically to the curtain here.
	_transition_viewport = SubViewport.new()
	_transition_viewport.size = Vector2i(1080, 1920)
	_transition_viewport.own_world_3d = true
	_transition_viewport.transparent_bg = false
	_transition_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_transition_viewport)

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 1.0)
	# Ambient fill so the faces turned away from the key light aren't pure black
	# -- keeps every side readable while still tonally distinct.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = TRANSITION_AMBIENT_COLOR
	env.ambient_light_energy = TRANSITION_AMBIENT_ENERGY
	env_node.environment = env
	_transition_viewport.add_child(env_node)

	# Directional key light: hits the cube faces at an angle so top / left / right
	# each catch a different amount of light -> the per-face tone the user wanted.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = TRANSITION_LIGHT_ANGLE
	key.light_energy = TRANSITION_LIGHT_ENERGY
	_transition_viewport.add_child(key)

	# Match the gameplay isometric crane: yaw 45, pitch -35.264, orthographic.
	# World-X motion projects to a screen diagonal under this rotation, which is
	# what makes the snakes read as crossing diagonally.
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.size = TRANSITION_CAM_SIZE
	var iso_basis := Basis.from_euler(Vector3(deg_to_rad(-35.264), deg_to_rad(45.0), 0.0))
	cam.transform = Transform3D(iso_basis, iso_basis * Vector3(0.0, 0.0, 30.0))
	cam.current = true
	_transition_viewport.add_child(cam)

	_transition_snakes.clear()
	var mid := (TRANSITION_SNAKE_LANES - 1) / 2.0
	for i in range(TRANSITION_SNAKE_LANES):
		# Even lanes travel toward +X, odd lanes toward -X -> alternating directions.
		var sgn := 1.0 if i % 2 == 0 else -1.0
		var col: Color = TRANSITION_SNAKE_COLORS[i % TRANSITION_SNAKE_COLORS.size()]
		# lead_sign = travel sign so the fatter head leads.
		var s := _make_transition_snake(col, sgn)
		s.position = Vector3(0.0, 0.0, (i - mid) * TRANSITION_SNAKE_LANE_SPACING)
		_transition_viewport.add_child(s)
		_transition_snakes.append({"node": s, "sign": sgn})

	var display := TextureRect.new()
	display.texture = _transition_viewport.get_texture()
	display.set_anchors_preset(Control.PRESET_FULL_RECT)
	display.stretch_mode = TextureRect.STRETCH_SCALE
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_root.add_child(display)

	# Seed positions off-screen at the start edge (progress 0) for both entry
	# points: COVER holds them here while it fades, and the RUN beat sweeps them
	# from here. start_black only controls the curtain's initial opacity.
	_update_transition_snakes(0.0)


# A bigger, LIT snake for the transition curtain -- unlike the flat unshaded
# splash decor snakes, this uses a normal lit material so the SubViewport's key
# light + ambient give every cube face its own tone. lead_sign points the head
# (index 0) in the travel direction; the body trails behind along -X * sign.
func _make_transition_snake(color: Color, lead_sign: float) -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.65
	mat.metallic = 0.0
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = TRANSITION_SNAKE_EMISSION
	for i in range(TRANSITION_SNAKE_SEGMENTS):
		var seg := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var sz := TRANSITION_SNAKE_SEGMENT_SIZE * (1.2 if i == 0 else 1.0)
		bm.size = Vector3(sz, sz, sz)
		seg.mesh = bm
		seg.material_override = mat
		seg.position = Vector3(-lead_sign * float(i) * TRANSITION_SNAKE_SEGMENT_SPACING, 0.0, 0.0)
		root.add_child(seg)
	return root


# progress 0 -> 1 walks every snake from one off-screen edge to the other along
# its own travel direction (sign): x = sign * SPAN * (2*progress - 1).
func _update_transition_snakes(progress: float) -> void:
	for entry in _transition_snakes:
		var node := entry["node"] as Node3D
		if is_instance_valid(node):
			node.position.x = float(entry["sign"]) * TRANSITION_SNAKE_SPAN * (2.0 * progress - 1.0)


func _cleanup_transition_curtain() -> void:
	if _transition_viewport:
		_transition_viewport.queue_free()
	if _transition_layer:
		_transition_layer.queue_free()
	_transition_viewport = null
	_transition_layer = null
	_transition_root = null
	_transition_snakes.clear()


func _build_title_ui() -> void:
	_title_layer = CanvasLayer.new()
	_title_layer.name = "TitleLayer"
	_title_layer.layer = 20
	add_child(_title_layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_layer.add_child(root)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.03, 0.05, 0.85)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var title := Label.new()
	title.text = "BATTLE\nBOA"
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_left = 24
	title.offset_right = -24
	title.offset_top = 100
	title.offset_bottom = 440
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 130)
	title.add_theme_constant_override("outline_size", 20)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	title.add_theme_color_override("font_color", Color(0.15, 1.0, 0.45, 1.0))
	root.add_child(title)

	var start_prompt := Label.new()
	start_prompt.text = "TAP OR PRESS ENTER TO START"
	start_prompt.set_anchors_preset(Control.PRESET_TOP_WIDE)
	start_prompt.offset_left = 24
	start_prompt.offset_right = -24
	start_prompt.offset_top = 460
	start_prompt.offset_bottom = 510
	start_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	start_prompt.add_theme_font_size_override("font_size", 30)
	start_prompt.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	root.add_child(start_prompt)
	# Breathing "press start" prompt -- a static label reads as inert; AAA
	# menus almost always pulse this to draw the eye without being distracting.
	var prompt_tw := create_tween()
	prompt_tw.set_loops()
	prompt_tw.tween_property(start_prompt, "modulate:a", 0.35, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	prompt_tw.tween_property(start_prompt, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var time_board := Control.new()
	time_board.set_anchors_preset(Control.PRESET_TOP_WIDE)
	time_board.offset_left = 80
	time_board.offset_right = -80
	time_board.offset_top = 580
	root.add_child(time_board)
	_title_time_rows = _build_board(time_board, "BEST TIME")

	var length_board := Control.new()
	length_board.set_anchors_preset(Control.PRESET_TOP_WIDE)
	length_board.offset_left = 80
	length_board.offset_right = -80
	length_board.offset_top = 940
	root.add_child(length_board)
	_title_length_rows = _build_board(length_board, "LONGEST SNAKE")

	_mute_button = Button.new()
	_mute_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_mute_button.offset_left = -206
	_mute_button.offset_top = 40
	_mute_button.offset_right = -40
	_mute_button.offset_bottom = 90
	_mute_button.focus_mode = Control.FOCUS_NONE
	_mute_button.add_theme_font_size_override("font_size", 20)
	var mute_style := StyleBoxFlat.new()
	mute_style.bg_color = Color(1.0, 1.0, 1.0, 0.14)
	mute_style.set_corner_radius_all(10)
	mute_style.set_border_width_all(2)
	mute_style.border_color = Color(1.0, 1.0, 1.0, 0.3)
	_mute_button.add_theme_stylebox_override("normal", mute_style)
	_mute_button.add_theme_stylebox_override("hover", mute_style)
	_mute_button.add_theme_stylebox_override("focus", mute_style)
	_mute_button.add_theme_stylebox_override("pressed", mute_style)
	_mute_button.pressed.connect(_toggle_mute)
	root.add_child(_mute_button)
	_update_mute_button_text()


func _toggle_mute() -> void:
	Chiptune.master_muted = not Chiptune.master_muted
	_save_settings()
	_update_mute_button_text()


func _update_mute_button_text() -> void:
	if _mute_button:
		_mute_button.text = "SFX: OFF" if Chiptune.master_muted else "SFX: ON"


func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var data = JSON.parse_string(txt)
	if typeof(data) == TYPE_DICTIONARY:
		Chiptune.master_muted = data.get("muted", false)


func _save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"muted": Chiptune.master_muted}))
	f.close()


func _build_gameover_leaderboard_ui() -> void:
	_go_leaderboard_layer = CanvasLayer.new()
	_go_leaderboard_layer.name = "GameOverLeaderboardLayer"
	_go_leaderboard_layer.layer = 21
	_go_leaderboard_layer.visible = false
	add_child(_go_leaderboard_layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_go_leaderboard_layer.add_child(root)

	var time_board := Control.new()
	time_board.set_anchors_preset(Control.PRESET_TOP_WIDE)
	time_board.offset_left = 80
	time_board.offset_right = -80
	time_board.offset_top = 360
	root.add_child(time_board)
	_go_time_rows = _build_board(time_board, "BEST TIME")

	var length_board := Control.new()
	length_board.set_anchors_preset(Control.PRESET_TOP_WIDE)
	length_board.offset_left = 80
	length_board.offset_right = -80
	length_board.offset_top = 730
	root.add_child(length_board)
	_go_length_rows = _build_board(length_board, "LONGEST SNAKE")

	_build_recap_ui(root)

	_new_high_score_label = Label.new()
	_new_high_score_label.text = "NEW HIGH SCORE!"
	_new_high_score_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_new_high_score_label.offset_top = 32
	_new_high_score_label.offset_bottom = 82
	_new_high_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_new_high_score_label.add_theme_font_size_override("font_size", 32)
	_new_high_score_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
	_new_high_score_label.add_theme_constant_override("outline_size", 6)
	_new_high_score_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	_new_high_score_label.visible = false
	root.add_child(_new_high_score_label)


const RECAP_LABEL_COUNT := 4
const RECAP_BASE_Y := 100.0    # y of the first recap line (leaderboard boards start at 360)
const RECAP_LINE_H := 44.0     # vertical spacing between recap lines

func _build_recap_ui(parent: Control) -> void:
	# Plain anchored labels laid out by hand -- NOT a VBoxContainer. _show_recap
	# animates each label's position for the slide-in, and a container re-sorts
	# its children every frame, overriding those positions and piling all four
	# lines on top of each other at y=0 (the overlap bug).
	for i in range(RECAP_LABEL_COUNT):
		var lbl := Label.new()
		lbl.set_anchors_preset(Control.PRESET_TOP_WIDE)
		var y := RECAP_BASE_Y + i * RECAP_LINE_H
		lbl.offset_top = y
		lbl.offset_bottom = y + RECAP_LINE_H
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 24)
		lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0, 1.0))
		lbl.add_theme_constant_override("outline_size", 5)
		lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
		lbl.modulate.a = 0.0
		parent.add_child(lbl)
		_recap_labels.append(lbl)


# AAA-style "mission recap" -- a quick stats summary staggered in one line at
# a time, instead of just a bare score number, right before the leaderboards.
func _show_recap() -> void:
	if _recap_labels.size() < RECAP_LABEL_COUNT:
		return
	var mins := int(_play_time) / 60
	var secs := int(_play_time) % 60
	var texts := [
		"SEGMENTS REACHED: %d" % _max_segment_count,
		"TIME SURVIVED: %d:%02d" % [mins, secs],
		"ENEMIES DEFEATED: %d" % _enemies_killed_count,
		"BIOME REACHED: %s" % _biome_display_name(LEVEL_BIOMES[current_level]),
	]
	for i in range(_recap_labels.size()):
		var lbl := _recap_labels[i] as Label
		lbl.text = texts[i]
		lbl.modulate.a = 0.0
		var base_y := RECAP_BASE_Y + i * RECAP_LINE_H
		lbl.position.y = base_y - 12.0
		var tw := create_tween()
		tw.tween_interval(0.15 * i)
		tw.set_parallel(true)
		tw.tween_property(lbl, "modulate:a", 1.0, 0.3)
		tw.tween_property(lbl, "position:y", base_y, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _build_board(parent: Control, board_title: String) -> Array:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_TOP_WIDE)
	box.add_theme_constant_override("separation", 8)
	parent.add_child(box)

	var header := Label.new()
	header.text = board_title
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 42)
	header.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	header.add_theme_constant_override("outline_size", 6)
	header.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	box.add_child(header)

	var rows: Array = []
	for i in range(LEADERBOARD_SIZE):
		var row := Label.new()
		row.text = "%d. --" % (i + 1)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_theme_font_size_override("font_size", 34)
		row.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6, 1.0))
		row.add_theme_constant_override("outline_size", 4)
		row.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
		box.add_child(row)
		rows.append(row)
	return rows


func _refresh_leaderboard_ui(highlight_time_rank: int = -1, highlight_length_rank: int = -1) -> void:
	_update_board_rows(_title_time_rows, best_times, true)
	_update_board_rows(_title_length_rows, best_lengths, false)
	_update_board_rows(_go_time_rows, best_times, true, highlight_time_rank)
	_update_board_rows(_go_length_rows, best_lengths, false, highlight_length_rank)


func _update_board_rows(rows: Array, values: Array, is_time: bool, highlight_rank: int = -1) -> void:
	for i in range(rows.size()):
		var row := rows[i] as Label
		if not row:
			continue
		if i < values.size():
			var val = values[i]
			if is_time:
				row.text = "%d. %d:%02d" % [i + 1, int(val) / 60, int(val) % 60]
			else:
				row.text = "%d. %d" % [i + 1, int(val)]
			row.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0) if i == highlight_rank else Color(0.85, 0.85, 0.9, 1.0))
		else:
			row.text = "%d. --" % (i + 1)
			row.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6, 1.0))
