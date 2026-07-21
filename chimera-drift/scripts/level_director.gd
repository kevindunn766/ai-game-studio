extends Node

signal level_won(distance_traveled: float)

@export var ship_path: NodePath
@export var corridor_generator_path: NodePath
@export var surface_generator_path: NodePath
@export var open_volume_generator_path: NodePath
@export var canyon_generator_path: NodePath
@export var pillared_generator_path: NodePath
@export var power_up_streamer_path: NodePath
@export var sun_light_path: NodePath
@export var level_target_distance: float = 200.0
@export var beauty_shot_duration: float = 5.0

@onready var ship: Node3D = get_node(ship_path)
@onready var corridor_generator = get_node(corridor_generator_path)
@onready var surface_generator = get_node(surface_generator_path)
@onready var open_volume_generator = get_node(open_volume_generator_path)
@onready var canyon_generator = get_node(canyon_generator_path)
@onready var pillared_generator = get_node(pillared_generator_path)
@onready var power_up_streamer = get_node(power_up_streamer_path)
@onready var sun_light: DirectionalLight3D = get_node_or_null(sun_light_path)

const SkyDirector := preload("res://scripts/sky_director.gd")
const UNDERWATER_POST := preload("res://shaders/underwater_post.gdshader")
const Combat := preload("res://scripts/combat.gd")
const BEAUTY_SHOT_SCENE := preload("res://scenes/BeautyShot.tscn")
const GiantObstacleSpawner := preload("res://scripts/giant_obstacle_spawner.gd")
const BossScript := preload("res://scripts/boss.gd")

var _giant_spawner: Node3D = null
var _boss: Node3D = null          # the end-of-level boss (spawned at target distance)
var _theme: Dictionary = {}       # this level's resolved theme (for boss colours)

# SUBMERGED biomes get the full underwater treatment: a murky blue background instead of the
# sky, plus the full-screen post pass (blue tint + god rays + caustics + refractive-rainbow /
# fuzzy edges). These are Surface/Canyon/Corridor levels in the CSV (NOT open volume, which is
# space), so it's keyword-matched on the biome word regardless of shape family. The ocean
# *surface* (seen from above) is explicitly excluded -- that's the reflective flat water plane.
const SUBMERGED_KEYWORDS := ["underwater", "kelp", "jellyfish", "reef", "coral", "sunken", "submarine", "aquatic", "shallows", "abyss"]
var _underwater_overlay: CanvasLayer = null

# Captured at boot so non-sky (corridor) levels can restore the scene's default
# key light instead of inheriting a previous sky level's sun orientation.
var _default_light_basis: Basis = Basis.IDENTITY
var _default_light_color: Color = Color.WHITE
var _default_light_energy: float = 1.0

const CAMERA_RELATIVE_PATHS := {
	"thirdperson": "ThirdPersonPivot/ThirdPersonSpringArm3D/ThirdPersonCamera3D",
	"sidescroll": "SideScrollPivot/SideScrollCamera3D",
	"isometric": "IsometricPivot/IsometricCamera3D",
	"topdown": "TopDownPivot/TopDownCamera3D",
	"threequarter": "ThreeQuarterPivot/ThreeQuarterCamera3D",
}

var rolled_level: Dictionary = {}
var active_generator: Node = null
var level_in_progress: bool = false
var world_env: WorldEnvironment = null

# Win-screen stat tracking: which sector this is (counts real new levels, not
# retries) and when the current level started (for the elapsed-time stat).
var _sector: int = 0
var _level_start_ms: int = 0
var _boss_start_ms: int = 0
# Captured on boss defeat so the win screen can show this segment's boss result.
var _last_boss_time: float = 0.0
var _last_boss_key: String = ""
var _last_boss_record: bool = false

# Debug PREVIEW: jump straight to a specific showcase level so you don't have to reroll for
# ages to find it. Keys (while playing): 1 = Ocean Surface top-down (reflective water),
# 2 = Underwater, 3 = Kelp Forest underwater, 0 = back to random rolls. Empty = normal random.
var _force_biome: String = ""
var _force_view: String = ""
const PREVIEW_KEYS := {
	KEY_1: ["Ocean Surface", "topdown"],
	KEY_2: ["Underwater", ""],
	KEY_3: ["Kelp Forest Open Water", ""],
}

func _ready() -> void:
	_ensure_world_environment()
	_ensure_underwater_overlay()
	_giant_spawner = GiantObstacleSpawner.new()
	_giant_spawner.name = "GiantObstacles"
	add_child(_giant_spawner)
	if sun_light != null:
		_default_light_basis = sun_light.transform.basis
		_default_light_color = sun_light.light_color
		_default_light_energy = sun_light.light_energy
	ship.crashed.connect(_on_ship_crashed)
	print("[preview] hotkeys -> 1: Ocean Surface (top-down water)  2: Underwater  3: Kelp underwater  0: random")
	_start_new_level()

func _process(_delta: float) -> void:
	if ship.alive and level_in_progress:
		var distance: float = -ship.position.z
		# Reaching the target no longer instantly wins -- it summons the boss. The
		# level is only cleared once the boss is defeated (see _on_boss_defeated).
		if distance >= level_target_distance and _boss == null:
			_start_boss()

func retry_level() -> void:
	_build_level()

func _start_new_level() -> void:
	_sector += 1
	Profile.record_sector(_sector)   # deepest level reached (best "game")
	rolled_level = LevelSeed.roll_new_level(null, _force_biome, _force_view)
	print("Level seed rolled: ", rolled_level)
	_build_level()

# Debug preview hotkeys: force a showcase level (or return to random) and rebuild now.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var code: int = event.keycode
	if PREVIEW_KEYS.has(code):
		_force_biome = PREVIEW_KEYS[code][0]
		_force_view = PREVIEW_KEYS[code][1]
		print("[preview] forcing level: ", _force_biome, " ", _force_view)
		ship.alive = true
		_start_new_level()
	elif code == KEY_0:
		_force_biome = ""
		_force_view = ""
		print("[preview] back to random levels")
		ship.alive = true
		_start_new_level()

func _build_level() -> void:
	# Clear ALL generators (not just the previously-active one) so a shape-family
	# change between levels can't leave stale geometry from whichever shape was active.
	corridor_generator.clear()
	surface_generator.clear()
	open_volume_generator.clear()
	canyon_generator.clear()
	pillared_generator.clear()
	if _boss != null and is_instance_valid(_boss):
		_boss.queue_free()
	_boss = null

	match rolled_level.shape_family:
		LevelSeed.ShapeFamily.CORRIDOR:
			active_generator = corridor_generator
		LevelSeed.ShapeFamily.SURFACE:
			active_generator = surface_generator
		LevelSeed.ShapeFamily.OPEN_VOLUME:
			active_generator = open_volume_generator
		LevelSeed.ShapeFamily.CANYON:
			active_generator = canyon_generator
		LevelSeed.ShapeFamily.PILLARED:
			active_generator = pillared_generator

	# Configure the ship's spawn/flight envelope BEFORE reset() so it spawns in
	# open space (never inside the floor) for the rolled shape family.
	_configure_ship_flight(rolled_level.shape_family)
	_configure_ship_steering(rolled_level.viewpoint)
	_configure_ship_zone(rolled_level.shape_family)
	ship.reset()
	ship.apply_permanent_loadout(RunManager.permanent_pieces)   # re-bolt the kept draft pieces
	Combat.player_kills = 0                 # fresh per-level tally for the win stats
	_level_start_ms = Time.get_ticks_msec()
	level_in_progress = true

	var theme: Dictionary = LevelTheme.resolve(rolled_level)
	_theme = theme
	# Recolor the ship's x-ray silhouette to this level's theme accent.
	ship.set_theme_color(theme.get("accent", Color(0.5, 0.8, 1.0)))
	active_generator.configure(rolled_level.feature_words)
	active_generator.configure_enemies(rolled_level.enemy_words)
	active_generator.configure_mines(rolled_level.get("mines", 0.0))
	active_generator.configure_hazards(rolled_level.get("hazards", {}))
	active_generator.configure_gravity(rolled_level.get("gravity", true))
	active_generator.configure_viewpoint(rolled_level.viewpoint)
	active_generator.configure_structure(rolled_level.structure_type)
	active_generator.configure_theme(theme)
	active_generator.configure_state(rolled_level.get("state", {}))
	active_generator.configure_cliff(rolled_level.get("cliff", {}))
	active_generator.start()

	# Stream power-ups through the whole level (started AFTER the generator so it
	# can query the active generator's now-configured navigable envelope).
	power_up_streamer.clear()
	power_up_streamer.configure(active_generator, theme)
	power_up_streamer.start()

	# Roll this level's giant landmark obstacle (may be none). After start() so the
	# generator's terrain is configured for ground placement.
	_giant_spawner.build(active_generator, theme, rolled_level)

	_activate_viewpoint(rolled_level.viewpoint)
	_configure_environment(rolled_level, theme)

# Per-shape spawn height. No bounding envelope -- free flight, bounded only by the
# lethal level geometry (see Ship._handle_steering). Every shape spawns the ship in
# clear air ABOVE its lethal floor so it never starts inside the ground: Corridor
# mid-tube, Surface a few units over the ground, Open Volume at center (no ground).
func _configure_ship_flight(shape_family: int) -> void:
	match shape_family:
		LevelSeed.ShapeFamily.CORRIDOR:
			ship.flight_spawn_y = corridor_generator.wall_height * 0.5
		LevelSeed.ShapeFamily.SURFACE:
			ship.flight_spawn_y = 3.0
		LevelSeed.ShapeFamily.CANYON:
			ship.flight_spawn_y = 3.0     # in clear air over the gorge floor (walls ramp in over the safe start)
		LevelSeed.ShapeFamily.PILLARED:
			ship.flight_spawn_y = 3.0     # over the flat-ish floor; pillars are kept out of the safe start
		LevelSeed.ShapeFamily.OPEN_VOLUME:
			ship.flight_spawn_y = 0.0

# Per-view axis locks (binary -- free or locked, no partial tracks). Only the
# "pointless" axis for a view is locked; every free axis is unbounded. Reset to
# free every level so a lock never carries into another view.
#   Third-person / Isometric / 3-4 : X free, Y free.
#   Top-down                       : Y locked (height is pointless overhead).
#   Side-scroll                    : X locked (depth is pointless side-on).
func _configure_ship_steering(viewpoint: String) -> void:
	ship.steer_x_locked = false
	ship.steer_y_locked = false
	match viewpoint:
		"topdown":
			ship.steer_y_locked = true
		"sidescroll":
			ship.steer_x_locked = true

# Enable the soft combat-zone leash only on the free axes where the streamed world follows
# the ship laterally and can lag if you race off: X on open ground (surface/canyon/pillared),
# X+Y in open volume (its content ring follows both). Corridors are wall-bounded -> off.
func _configure_ship_zone(shape_family: int) -> void:
	ship.zone_limit_x = false
	ship.zone_limit_y = false
	match shape_family:
		LevelSeed.ShapeFamily.SURFACE, LevelSeed.ShapeFamily.CANYON, LevelSeed.ShapeFamily.PILLARED:
			ship.zone_limit_x = not ship.steer_x_locked
		LevelSeed.ShapeFamily.OPEN_VOLUME:
			ship.zone_limit_x = not ship.steer_x_locked
			ship.zone_limit_y = not ship.steer_y_locked

# Themed fog hides distant spawn-in. Only needed where geometry appears close to
# camera in depth -- third-person (and later first-person); the orthographic /
# high-angle views don't reveal pop-in the same way, so fog stays off there.
func _ensure_world_environment() -> void:
	world_env = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.52, 0.58)
	env.ambient_light_energy = 0.6
	world_env.environment = env
	add_child(world_env)

# Full-screen underwater post-process overlay: a CanvasLayer holding a full-rect ColorRect
# with the underwater shader. Built once, hidden; toggled per level. Its layer sits BELOW
# the HUD (HUD is layer 10 in Main.tscn) so the health/reticle UI isn't distorted.
func _ensure_underwater_overlay() -> void:
	_underwater_overlay = CanvasLayer.new()
	_underwater_overlay.layer = 1
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = UNDERWATER_POST
	rect.material = mat
	_underwater_overlay.add_child(rect)
	_underwater_overlay.visible = false
	add_child(_underwater_overlay)

func _is_underwater(rl: Dictionary) -> bool:
	var b: String = rl.get("biome", "").to_lower()
	if b.find("ocean surface") != -1 or b.find("lily") != -1:
		return false   # the water SURFACE (above), handled by the reflective flat plane
	for kw in SUBMERGED_KEYWORDS:
		if b.find(kw) != -1:
			return true
	return false

# Turn the underwater look on/off for this level: the post overlay, and a murky blue
# water volume (BG_COLOR) in place of the star sky so it reads as being submerged.
func _apply_underwater(env: Environment, rl: Dictionary, theme: Dictionary) -> void:
	var underwater: bool = _is_underwater(rl)
	if _underwater_overlay != null:
		_underwater_overlay.visible = underwater
	if not underwater:
		return
	var murk: Color = theme.get("fog", Color(0.06, 0.22, 0.34))
	env.background_mode = Environment.BG_COLOR
	env.sky = null
	env.background_color = murk
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = theme.get("accent", Color(0.4, 0.7, 0.95)).lerp(murk, 0.4)
	env.ambient_light_energy = 0.7
	# Denser, closer fog -> the murky "you can't see far underwater" feel.
	env.fog_light_color = murk
	env.fog_depth_begin = env.fog_depth_end * 0.15
	_restore_sun()

# Per-level environment: a procedural SKY where the horizon/background is visible
# (Surface + Open Volume, per SkyDirector's gate), otherwise the flat fog
# background that Corridor has always used. Depth fog (third-person pop-in
# mitigation) is kept in both cases, tinted to the theme.
func _configure_environment(rl: Dictionary, theme: Dictionary) -> void:
	var env: Environment = world_env.environment
	var viewpoint: String = rl.get("viewpoint", "thirdperson")
	var fog: Color = theme.get("fog", Color(0.2, 0.2, 0.25))
	var cfg: Dictionary = SkyDirector.build(rl, theme, PerfProfile.sky_quality, PerfProfile.sky_radiance_size())

	if cfg.get("use_sky", false):
		env.background_mode = Environment.BG_SKY
		env.sky = cfg.sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = cfg.get("ambient_energy", 1.0)
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		_orient_sun(cfg)
	else:
		env.background_mode = Environment.BG_COLOR
		env.sky = null
		env.background_color = fog
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.5, 0.52, 0.58)
		env.ambient_light_energy = 0.6
		_restore_sun()

	# Depth fog on EVERY view (not just third-person): geometry now streams past the
	# fog horizon, so it spawns fully faded and eases in -- nothing pops into the
	# frustum. Fog affects geometry only (fog_sky_affect = 0), so the procedural sky
	# stays crisp behind it. Deep space fades a touch darker toward the void.
	var in_space: bool = rl.get("shape_family", 0) == 2
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = fog if not in_space else fog.darkened(0.4)
	env.fog_sky_affect = 0.0
	# Fog end is derived from the active generator's ACTUAL per-tier build distance
	# (build_ahead x PerfProfile.view_distance_scale) minus an off-camera margin, so the
	# streamed frontier is ALWAYS fully fogged before it's built -- on every perf tier,
	# not just ULTRA. (Hardcoding 100u used to leave un-fogged pop-in on the MEDIUM/LOW
	# tiers, where build_ahead scales down to ~56u.) The generators build laterally to
	# this same distance, so the terrain's side edges fall past the fog horizon too and
	# never show a hard cull line.
	var ahead: float = 112.0 * PerfProfile.view_distance_scale
	if active_generator != null and "build_ahead" in active_generator:
		ahead = active_generator.build_ahead * PerfProfile.view_distance_scale
	var fog_end: float = maxf(24.0, ahead - 12.0)   # keep a fully-fogged band before the build edge
	env.fog_depth_begin = fog_end * 0.28
	env.fog_depth_end = fog_end
	env.fog_depth_curve = 0.7
	env.fog_density = 1.0

	_apply_underwater(env, rl, theme)
	_configure_head_light(theme, cfg)

# The ship headlight, tuned to this level: energy scaled to scene darkness (bright
# beam at night / in tunnels, subtle in daylight where the sun dominates), color
# tinted toward the level theme, shadows only on capable hardware (spot shadows over
# streamed trimesh terrain are the main cost).
func _configure_head_light(theme: Dictionary, cfg: Dictionary) -> void:
	var accent: Color = theme.get("accent", Color(0.9, 0.95, 1.0))
	var beam: Color = Color(0.9, 0.94, 1.0).lerp(accent, 0.35)
	var energy: float
	if not cfg.get("use_sky", false):
		energy = 6.5                      # corridor / flat-fog tunnels: dim, want the beam
	else:
		match cfg.get("tod", ""):
			"night":
				energy = 9.0
			"sunset":
				energy = 5.0
			"day":
				energy = 2.5              # sun dominates -> subtle
			_:
				energy = 4.0              # open-volume space (no landscape, harmless)
	var shadows: bool = PerfProfile.sky_quality >= 2
	ship.configure_head_light(energy, beam, shadows)

# Orient the key light so the shader's LIGHT0 (and the scene lighting) match the
# sky's rolled sun. DirectionalLight travels along its local -Z, so aim -Z along
# the sun's travel direction (= -sun_toward).
func _orient_sun(cfg: Dictionary) -> void:
	if sun_light == null:
		return
	var toward: Vector3 = cfg.get("sun_toward", Vector3(0.3, 0.7, 0.4)).normalized()
	var up: Vector3 = Vector3.UP if absf(toward.y) < 0.95 else Vector3.FORWARD
	sun_light.look_at(sun_light.global_position - toward, up)
	sun_light.light_color = cfg.get("sun_color", Color.WHITE)
	sun_light.light_energy = cfg.get("sun_energy", 1.0)
	sun_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY

func _restore_sun() -> void:
	if sun_light == null:
		return
	sun_light.transform.basis = _default_light_basis
	sun_light.light_color = _default_light_color
	sun_light.light_energy = _default_light_energy

func _on_ship_crashed(_distance_traveled: float) -> void:
	level_in_progress = false

# Summon the end-of-level boss. The player keeps flying; the boss slides in and
# keeps pace ahead. Beating it (all weak points destroyed) clears the stage.
# The live boss (for the HUD health bar), or null when no boss is active.
func active_boss() -> Node3D:
	if _boss != null and is_instance_valid(_boss) and _boss.is_active():
		return _boss
	return null

# Boss tier for this level: 2 = ULTRA (the single final base-game level, all biomes
# seen), 1 = SUPER (every 8th level), 0 = normal. Super continues into NG+; the ultra
# fires once (there is no "end" of the endless NG+).
func _boss_tier() -> int:
	if rolled_level.get("final_biome", false):
		return 2
	if _sector % 8 == 0:
		return 1
	return 0

func _start_boss() -> void:
	var primary: Color = _theme.get("walls2", Color(0.5, 0.45, 0.55))
	var accent: Color = _theme.get("accent", Color(1.0, 0.45, 0.2))
	var world: Node3D = ship.get_parent() as Node3D
	var boss := BossScript.new()
	boss.name = "Boss"
	# In NG+ the level has no biome -> roll a fresh random boss each time (endless
	# archetype variety); otherwise the boss is seeded per-biome (consistent).
	if rolled_level.get("ng_plus", false):
		boss.boss_seed = -1
	else:
		boss.boss_seed = abs(hash(str(rolled_level.get("biome", "")) + "|boss"))
	boss.viewpoint = rolled_level.get("viewpoint", "")
	boss.sector = _sector                                                     # difficulty scales with progress
	boss.tier = _boss_tier()                                                  # normal / super / ultra
	boss.setup(ship, world, primary, accent)
	boss.defeated.connect(_on_boss_defeated)
	add_child(boss)
	_boss = boss
	_boss_start_ms = Time.get_ticks_msec()

func _on_boss_defeated() -> void:
	# Record this boss fight's time (against its TYPE) before the boss is cleared.
	if is_instance_valid(_boss) and _boss.has_method("record_key"):
		_last_boss_time = float(Time.get_ticks_msec() - _boss_start_ms) / 1000.0
		_last_boss_key = _boss.record_key()
		_last_boss_record = Profile.record_boss_time(_last_boss_key, _last_boss_time)
	_boss = null
	if level_in_progress:
		_win_level()

func _win_level() -> void:
	level_in_progress = false
	ship.alive = false
	# Records: fastest level clear, and (if this was the final base-game level) mark
	# the game BEATEN -> unlocks persistent New Game Plus for all future runs.
	var level_secs: float = float(Time.get_ticks_msec() - _level_start_ms) / 1000.0
	Profile.record_level_time(level_secs)
	if rolled_level.get("final_biome", false):
		Profile.mark_beaten()
	var distance: float = -ship.position.z
	level_won.emit(distance)
	await _run_beauty_shot(distance)
	_start_new_level()

# The post-level beauty shot: a hero render of the player's ship (its run seed)
# against a fresh space skybox with the just-won level's stats. Rendered in an
# ISOLATED SubViewport (own World3D) so its camera / sky / lights don't collide
# with the live game world, composited full-screen over the HUD, then torn down.
func _run_beauty_shot(distance: float) -> void:
	var overlay := CanvasLayer.new()
	overlay.layer = 20                      # above the HUD (layer 10)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.size = Vector2i(get_viewport().get_visible_rect().size)

	var pieces: Array = ship.collected_pieces.duplicate()
	var loadout: Array = RunManager.permanent_pieces.duplicate()   # parts kept so far
	var shot := BEAUTY_SHOT_SCENE.instantiate()
	shot.configure(RunManager.hull_seed, _win_stats(distance), pieces, loadout)   # set before it enters the tree
	vp.add_child(shot)
	container.add_child(vp)
	overlay.add_child(container)
	add_child(overlay)

	# Input-gated: wait for the player's draft pick (index into `pieces`, or -1 for
	# none), keep that piece permanently, then advance to the next stage.
	var idx: int = await shot.choice_made
	if idx >= 0 and idx < pieces.size():
		RunManager.permanent_pieces.append(pieces[idx])
	overlay.queue_free()

# Build the stat dict the beauty shot lays over the ship for the level just won.
func _win_stats(distance: float) -> Dictionary:
	var new_parts: int = ship.collected_pieces.size()   # eligible pieces this stage
	var kills: int = Combat.player_kills
	var elapsed: float = float(Time.get_ticks_msec() - _level_start_ms) / 1000.0
	var score: int = int(distance) * 10 + new_parts * 750 + kills * 250 + _sector * 1000
	var biome: String = rolled_level.get("modifier_word", "")
	var shape: String = rolled_level.get("shape_word", "Sector")
	var ng: bool = rolled_level.get("ng_plus", false)
	var title: String = ("NG+  SECTOR %d CLEARED" % _sector) if ng else ("SECTOR %d CLEARED" % _sector)
	# Boss-fight result for this segment (fastest per boss type is the NG+ time-attack).
	var boss_val: String = "%s  %s" % [_last_boss_key, _fmt_secs(_last_boss_time)]
	if _last_boss_record:
		boss_val += "  * NEW BEST!"
	return {
		"title": title,
		"score": score,
		"rows": [
			["SECTOR", ("%s %s" % [biome, shape]).strip_edges()],
			["DISTANCE", "%d m" % int(distance)],
			["NEW PARTS", str(new_parts)],
			["ENEMIES DOWNED", str(kills)],
			["BOSS", boss_val],
			["TIME", _fmt_time(elapsed)],
		],
		"footer": "PREPARING NEXT SECTOR…",
	}

func _fmt_time(seconds: float) -> String:
	var total: int = int(seconds)
	return "%d:%02d" % [total / 60, total % 60]

func _fmt_secs(seconds: float) -> String:
	return "%.1fs" % seconds

func _activate_viewpoint(viewpoint_name: String) -> void:
	var camera_rigs: Node3D = ship.get_node("CameraRigs")
	for cam_name in CAMERA_RELATIVE_PATHS.keys():
		var cam: Camera3D = camera_rigs.get_node(CAMERA_RELATIVE_PATHS[cam_name])
		cam.current = (cam_name == viewpoint_name)
