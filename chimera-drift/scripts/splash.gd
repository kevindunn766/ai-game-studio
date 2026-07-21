extends Node3D

# ============================================================================
# Chimera Drift — BOOT SPLASH
# Shows the studio graphic (HOTBED GAMES, shared from Snake 3D) as a poster in the
# centre of the screen while a RANDOMLY-ROLLED chimera ship zooms in from the top,
# accelerating down + toward the camera and blasting off the bottom of the frame.
# Holds a beat, then hands off to the title screen. Skippable with any input.
# ============================================================================

const ShipHullGeneratorS := preload("res://scripts/ship_hull_generator.gd")
const Dresser := preload("res://scripts/beauty_ship_dresser.gd")
const StreakShader := preload("res://shaders/speed_streak.gdshader")
const LOGO := preload("res://assets/hotbed_games.png")
const STING := preload("res://assets/splash_sting.ogg")

const DURATION := 3.6        # total splash length (seconds)
const ZOOM_START := 0.35     # when the ship enters
const ZOOM_TIME := 1.85      # how long the fly-through takes
const LOGO_FADE := 0.6       # studio graphic fade-in
const SHIP_SCALE := 1.8      # extra size so the fly-through reads big
const LOGO_Z := -42.0        # poster sits well BEHIND the ship's whole path

# Ship path (in the camera's -Z space), always IN FRONT of the poster: it enters
# high near the top and rushes down + toward the viewer, exiting off the bottom.
const Y_START := 13.0
const Y_END := -9.0
const Z_START := -26.0
const Z_END := -3.0

var _t: float = 0.0
var _ship_root: Node3D = null
var _logo: Sprite3D = null
var _streaks: CPUParticles3D = null
var _accent: Color = Color(0.5, 0.8, 1.0)
var _done: bool = false

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_accent = _roll_accent(rng)
	_build_environment()
	_build_logo()
	_build_ship(rng)
	_build_streaks()
	_build_overlay()
	_play_sting()
	if "--capture" in OS.get_cmdline_user_args():
		_capture_seq()

# The studio-logo audio sting (shared from Snake 3D).
func _play_sting() -> void:
	var p := AudioStreamPlayer.new()
	p.stream = STING
	p.volume_db = -3.0
	add_child(p)
	p.play()

func _process(delta: float) -> void:
	_t += delta
	_animate_logo()
	_animate_ship()
	if not _done and _t >= DURATION:
		_go_to_title()

func _unhandled_input(event: InputEvent) -> void:
	# Any key / click / tap skips to the title.
	if event is InputEventKey and event.pressed and not event.echo:
		_go_to_title()
	elif event is InputEventMouseButton and event.pressed:
		_go_to_title()
	elif event is InputEventScreenTouch and event.pressed:
		_go_to_title()

func _go_to_title() -> void:
	if _done:
		return
	_done = true
	get_tree().change_scene_to_file("res://scenes/Title.tscn")

# --- studio graphic (a 3D poster so the ship can pass in FRONT of it) --------
func _build_logo() -> void:
	_logo = Sprite3D.new()
	_logo.texture = LOGO
	_logo.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST   # crisp pixels
	_logo.pixel_size = 0.043
	_logo.position = Vector3(0.0, 0.0, LOGO_Z)
	_logo.modulate = Color(1, 1, 1, 0.0)                          # faded in by _animate_logo
	add_child(_logo)

func _animate_logo() -> void:
	if _logo != null:
		_logo.modulate.a = clampf(_t / LOGO_FADE, 0.0, 1.0)

# --- the randomly-rolled ship ----------------------------------------------
func _build_ship(rng: RandomNumberGenerator) -> void:
	_ship_root = Node3D.new()
	_ship_root.name = "ShipRoot"
	_ship_root.visible = false                                    # hidden until it enters
	add_child(_ship_root)

	var result: Dictionary = ShipHullGeneratorS.generate(rng)
	var hull: Node3D = result.hull
	var aabb: AABB = result.aabb
	var longest: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	var k: float = (ShipHullGeneratorS.TARGET_LONGEST / longest) if longest > 0.0 else 1.0
	hull.scale = Vector3.ONE * k
	hull.position = -(aabb.position + aabb.size * 0.5) * k
	_ship_root.add_child(hull)
	Dresser.dress(hull, result.colors, _accent, rng)
	_ship_root.scale = Vector3.ONE * SHIP_SCALE

func _animate_ship() -> void:
	if _ship_root == null:
		return
	var t01: float = (_t - ZOOM_START) / ZOOM_TIME
	if t01 <= 0.0 or t01 >= 1.0:
		_ship_root.visible = false
		return
	_ship_root.visible = true
	var y: float = lerpf(Y_START, Y_END, t01)                     # steady descent top -> bottom
	var z: float = lerpf(Z_START, Z_END, pow(t01, 1.5))           # accelerating zoom toward camera
	_ship_root.position = Vector3(0.0, y, z)
	# Nose toward the viewer, pitched down, with a stylish barrel roll.
	_ship_root.rotation = Vector3(deg_to_rad(-28.0), PI, _t * 2.2)

# --- warp streaks (only while the ship rushes past) -------------------------
func _build_streaks() -> void:
	var scale: float = maxf(float(PerfProfile.particle_scale), 0.4)
	_streaks = CPUParticles3D.new()
	_streaks.local_coords = false
	_streaks.emitting = false
	_streaks.amount = maxi(16, int(90.0 * scale))
	_streaks.lifetime = 0.7
	_streaks.preprocess = 0.7
	_streaks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_streaks.emission_box_extents = Vector3(10.0, 8.0, 8.0)
	_streaks.position = Vector3(0.0, 4.0, -18.0)
	_streaks.direction = Vector3(0.0, -1.0, 0.35)                 # rush downward past the viewer
	_streaks.spread = 6.0
	_streaks.initial_velocity_min = 55.0
	_streaks.initial_velocity_max = 95.0
	_streaks.gravity = Vector3.ZERO
	_streaks.scale_amount_min = 0.7
	_streaks.scale_amount_max = 1.5

	var q := QuadMesh.new()
	q.size = Vector2(0.12, 2.6)
	var mat := ShaderMaterial.new()
	mat.shader = StreakShader
	mat.set_shader_parameter("streak_color", _accent.lerp(Color.WHITE, 0.55))
	mat.set_shader_parameter("intensity", 1.6)
	q.material = mat
	_streaks.mesh = q

	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.add_point(0.2, Color(1, 1, 1, 1.0))
	g.add_point(0.8, Color(1, 1, 1, 1.0))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0.0))
	_streaks.color_ramp = g
	add_child(_streaks)
	_streaks.emitting = true

# --- environment / camera ---------------------------------------------------
func _build_environment() -> void:
	var cam := Camera3D.new()
	cam.fov = 55.0
	cam.current = true
	add_child(cam)                                               # at origin, looking -Z

	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.03, 0.04, 0.09)
	psm.sky_horizon_color = Color(0.06, 0.07, 0.13)
	psm.ground_bottom_color = Color(0.02, 0.02, 0.05)
	psm.ground_horizon_color = Color(0.05, 0.06, 0.11)
	sky.sky_material = psm

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.light_energy = 1.3
	key.light_color = Color(1, 0.98, 0.94)
	add_child(key)
	key.look_at_from_position(Vector3.ZERO, Vector3(-0.4, -0.6, -0.7), Vector3.UP)

	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.4
	fill.light_color = _accent.lerp(Color.WHITE, 0.3)
	add_child(fill)
	fill.look_at_from_position(Vector3.ZERO, Vector3(0.5, 0.3, -0.6), Vector3.UP)

# --- overlay: scanlines + skip hint -----------------------------------------
func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var hint := UITheme.label("PRESS ANY KEY TO SKIP", 11, Color(0.75, 0.82, 0.92, 0.7))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -38.0
	hint.offset_bottom = -18.0
	layer.add_child(hint)
	layer.add_child(UITheme.scanlines(0.12, 0.5))

func _roll_accent(rng: RandomNumberGenerator) -> Color:
	var hues := [Color(0.33, 0.85, 1.0), Color(1.0, 0.55, 0.2), Color(0.6, 0.9, 0.5),
		Color(1.0, 0.36, 0.62), Color(0.7, 0.6, 1.0), Color(1.0, 0.82, 0.34)]
	return hues[rng.randi() % hues.size()]

# --- verification capture ---------------------------------------------------
func _capture_seq() -> void:
	var stamps := [1.0, 1.6]                # mid-zoom + climax
	for i in range(stamps.size()):
		while _t < float(stamps[i]):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://_splash_%d.png" % i)
	print("SPLASH_CAPTURE done")
	get_tree().quit()
