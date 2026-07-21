extends Node3D

# Kindling foundation: a TREADMILL world. The player piece sits fixed at the origin
# and never moves; the whole world scrolls past it (per the brief). Built here:
#  - a fixed player placeholder at origin
#  - the isometric spring-arm camera rig from Snake_3d (yaw pivot -> spring arm -> ortho cam)
#  - the Chimera-Drift-style grid streamer, keyed off a scroll offset (world_streamer.gd)
#  - the subtle tilt-shift overlay from Snake_3d
# Input scrolls the WORLD (WASD/arrows), camera-relative; the player stays put.

const WorldStreamer := preload("res://scripts/world_streamer.gd")
const CameraControllerScript := preload("res://scripts/camera_controller.gd")
const GroundTiler := preload("res://scripts/ground_tiler.gd")
const GroundHeight := preload("res://scripts/ground_height.gd")
const BurnTrail := preload("res://scripts/burn_trail.gd")
const TiltShiftShader := preload("res://shaders/tilt_shift.gdshader")

const FLAME_SIZE: float = 0.4           # flame edge in render units (also the burn-trail width)

# Perceived (on-screen) scroll speed in render units/second. The content-space scroll
# rate is this divided by world_size, so the flame crosses the screen at the SAME rate
# no matter how far the world has shrunk -- constant perceived speed for the whole game.
const SCREEN_SCROLL_SPEED: float = 1.6

# Each object burned shrinks the world by this factor of its CURRENT size. Multiplicative
# so world_size keeps shrinking across many layers without ever hitting zero -- the scale
# voyage (grass -> weeds -> ... -> buildings) needs to go far past a single 100% change.
const SHRINK_PER_BURN: float = 0.97
const HIT_SQUASH_TIME: float = 0.15     # seconds to squash a hit object's height to 10%

var _world: Node3D          # content container -- scrolled to -scroll each frame (the treadmill belt)
var _player: Node3D         # fixed at origin, never translated
var _camera: Camera3D
var _streamer: Node
var _ground: Node
var _height: RefCounted
var _trail: Node
var _cam_ctrl: Node
var _scroll: Vector2 = Vector2.ZERO   # accumulated scroll offset = world's position in content space

# The single "world size number": the whole world (floor + objects) is scaled by it, and
# object tiers are gated by it (which scale layer is currently spawning). Starts at 1.0
# and shrinks per burn.
var _world_size: float = 1.0
var _points: int = 0
var _tilt_mat: ShaderMaterial


func _ready() -> void:
	_build_environment()
	_build_player()
	_build_camera_rig()
	_build_world_and_streamer()
	_build_tilt_shift()


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	# Warm sky so the sky-sourced AMBIENT light lifts the world out of grey: very light
	# yellow overhead grading to warm orange along the horizon (both hemispheres share the
	# orange horizon so the whole horizon band is warm, not green).
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(1.0, 0.96, 0.78)      # very light yellow, overhead
	sky_mat.sky_horizon_color = Color(0.98, 0.55, 0.22) # warm orange, along the horizon
	sky_mat.ground_horizon_color = Color(0.98, 0.55, 0.22)
	sky_mat.ground_bottom_color = Color(0.50, 0.38, 0.26)  # warm low fill (was green)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	# Filmic instead of AGX -- AGX heavily desaturates, greying out the greens.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -40.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)


func _build_player() -> void:
	_player = Node3D.new()
	_player.name = "Player"
	add_child(_player)
	# Placeholder flame piece at the origin -- sized to sit among layer-1 plants.
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(FLAME_SIZE, FLAME_SIZE, FLAME_SIZE)
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.08)
	mat.emission_energy_multiplier = 0.5
	mi.material_override = mat
	mi.position.y = FLAME_SIZE * 0.5
	_player.add_child(mi)
	# No sensing Area3D: the plants are GPU-instanced (no per-plant nodes to collide with),
	# so burning is a distance check against this fixed flame -- see WorldStreamer.process_burn,
	# driven from _process below.


# Snake_3d's isometric camera angle: a yaw pivot (45deg) -> a boom (pitch
# -35.264deg) -> orthographic Camera3D at the boom's tip. NO SpringArm3D / no
# collision node -- fires don't bump against things. The camera sits at the exact
# offset the spring arm produced at full extension (probed: local +Z * 20).
func _build_camera_rig() -> void:
	var pivot := Node3D.new()
	pivot.name = "CameraCranePivot"
	pivot.rotation_degrees = Vector3(0.0, 45.0, 0.0)
	_player.add_child(pivot)

	var boom := Node3D.new()
	boom.name = "CameraBoom"
	boom.rotation_degrees = Vector3(-35.264, 0.0, 0.0)
	pivot.add_child(boom)

	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 2.5
	_camera.position = Vector3(0.0, 0.0, 20.0)
	boom.add_child(_camera)
	_camera.current = true


func _build_world_and_streamer() -> void:
	_world = Node3D.new()
	_world.name = "World"
	add_child(_world)

	# Shared ground height field -- the ground shader displaces from it and objects sample
	# it on the CPU so they sit on the surface (never floating or buried).
	_height = GroundHeight.new()

	_streamer = WorldStreamer.new()
	_streamer.name = "WorldStreamer"
	(_streamer as Node).set("world_root", _world)
	(_streamer as Node).set("height_field", _height)
	add_child(_streamer)
	_streamer.call("start", _scroll, _world_size)

	# Coarse ground LOD (separate from the object cells; tiles grow as we zoom out).
	_ground = GroundTiler.new()
	_ground.name = "GroundTiler"
	(_ground as Node).set("world_root", _world)
	(_ground as Node).set("height_field", _height)
	add_child(_ground)
	_ground.call("update", _scroll, _world_size)

	# Burn trail -- scorch marks dropped along the flame's path, under the world so they
	# scroll + scale with it.
	_trail = BurnTrail.new()
	_trail.name = "BurnTrail"
	(_trail as Node).set("world_root", _world)
	(_trail as Node).set("height_field", _height)
	add_child(_trail)

	_cam_ctrl = CameraControllerScript.new()
	_cam_ctrl.name = "CameraController"
	_cam_ctrl.set("camera", _camera)
	_cam_ctrl.set("streamer", _streamer)
	_cam_ctrl.set("player", _player)
	add_child(_cam_ctrl)


func _build_tilt_shift() -> void:
	# A fullscreen quad in front of the camera runs the depth-based tilt-shift (spatial
	# shader -> can read the scene depth). The shader forces it fullscreen in the vertex
	# stage; extra_cull_margin keeps it from ever being frustum-culled.
	var mat := ShaderMaterial.new()
	mat.shader = TiltShiftShader
	# The visible ortho/iso strip only spans ~3.5 m of depth, so the sharp band + falloff
	# must be small or nothing ever blurs. Sharp near the focal plane, blur toward the
	# top/bottom edges (the miniature-diorama look).
	mat.set_shader_parameter("focus_half_width", 0.35)
	mat.set_shader_parameter("blur_falloff", 1.3)
	mat.set_shader_parameter("max_blur", 2.5)
	mat.render_priority = 100                    # draw after the scene
	_tilt_mat = mat

	var quad := MeshInstance3D.new()
	quad.name = "TiltShift"
	var qm := QuadMesh.new()
	qm.size = Vector2(2.0, 2.0)                   # verts at +/-1 -> fullscreen in the shader
	quad.mesh = qm
	quad.material_override = mat
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.extra_cull_margin = 16384.0
	_camera.add_child(quad)
	quad.position = Vector3(0.0, 0.0, -1.0)       # in front of the camera (culling only)
	_update_tilt_shift()


# The focal plane sits at the player's depth (camera -> player). Constant with the fixed
# camera, but set here so it reflects the live camera transform.
func _update_tilt_shift() -> void:
	if _tilt_mat == null or _camera == null:
		return
	_tilt_mat.set_shader_parameter("focus_distance", _camera.global_position.distance_to(_player.global_position))


func _process(delta: float) -> void:
	# Treadmill: input scrolls the WORLD (camera-relative), the player stays fixed.
	var input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		input.y += 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		input.x += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		input.x -= 1.0

	if input != Vector2.ZERO:
		# Content-space scroll rate = perceived rate / world_size, so on-screen speed
		# (which is content rate * world_size) stays constant as the world shrinks.
		var content_speed: float = SCREEN_SCROLL_SPEED / maxf(_world_size, 0.0001)
		_scroll += _camera_relative(input.normalized()) * content_speed * delta

	# The world slides opposite to the accumulated scroll, so content moves past the
	# fixed player. The single world-size number scales the whole belt (floor + objects)
	# about the player; the scroll offset is scaled with it so the content point under
	# the player stays under the player as the world shrinks. Streaming stays in
	# content space (keyed off the scroll offset), gated by world_size for which tier spawns.
	_world.scale = Vector3(_world_size, _world_size, _world_size)
	_world.position = Vector3(-_scroll.x, 0.0, -_scroll.y) * _world_size
	_streamer.call("update_stream", _scroll, _world_size)
	_ground.call("update", _scroll, _world_size)
	_trail.call("update", _scroll, _world_size, FLAME_SIZE, delta)
	_update_tilt_shift()

	# Burning: the flame is fixed at the origin, so instead of collision the streamer
	# distance-checks each nearby plant against the scroll position. Each CURRENT-tier plant
	# consumed scores a point and shrinks the world by one burn (applied next frame).
	var burned: int = _streamer.call("process_burn", _scroll, _world_size, FLAME_SIZE * 0.5, delta)
	if burned > 0:
		_points += burned
		_world_size *= pow(SHRINK_PER_BURN, float(burned))


# Map screen input (x=right, y=up) to a world XZ direction using the camera's
# orientation, so W scrolls the world "up the screen" under the tilted iso camera.
func _camera_relative(input: Vector2) -> Vector2:
	var fwd: Vector3 = -_camera.global_transform.basis.z
	fwd.y = 0.0
	var right: Vector3 = _camera.global_transform.basis.x
	right.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	var world: Vector3 = right.normalized() * input.x + fwd.normalized() * input.y
	return Vector2(world.x, world.z)
