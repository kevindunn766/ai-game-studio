extends Node3D
class_name BeautyCameraDirector

# Cinematic camera for the post-level beauty shot. Owns one Camera3D and glides
# it through a looping SERIES of slow, graceful moves around the ship:
#   0 orbit      — sweep around the front quarter (rotate past the ship)
#   1 dolly-past — track low across the flank (pan past the ship)
#   2 crane      — rise up and tilt down over it (reveal)
#   3 zoom-out   — drift back, opening the frame to the skybox (slow zoom out)
#   4 push-in    — ease in close on the cockpit (show off the glint)
#
# Each shot is time-eased (smoothstep → zero velocity at both ends), and the
# camera pose is additionally exponential-smoothed so shot changes blend rather
# than cut. Framing distances scale off the ship radius (best-practices §2:
# position + look_at every frame, distances driven by an explicit scalar).

const POS_SMOOTH: float = 1.6      # camera position glide (1/time-constant)
const LOOK_SMOOTH: float = 2.2     # aim glide
const FOV_SMOOTH: float = 2.0

# Each shot: az/el in radians, r as a multiple of ship radius, fov degrees, dur s.
# az 0 = behind the ship (+Z); az = PI = in front of the nose (ship flies toward -Z).
var _shots: Array = [
	{"kind": "orbit", "az0": PI * 0.70, "az1": PI * 1.30, "el0": 0.22, "el1": 0.22, "r0": 2.6, "r1": 2.6, "fov": 42.0, "dur": 9.0},
	{"kind": "dolly", "az0": PI * 0.38, "az1": PI * 0.70, "el0": 0.10, "el1": 0.10, "r0": 2.3, "r1": 2.3, "fov": 40.0, "dur": 8.0},
	{"kind": "crane", "az0": PI * 1.12, "az1": PI * 1.12, "el0": 0.06, "el1": 0.70, "r0": 2.8, "r1": 2.8, "fov": 44.0, "dur": 8.0},
	{"kind": "zoom",  "az0": PI * 0.88, "az1": PI * 1.12, "el0": 0.26, "el1": 0.26, "r0": 2.4, "r1": 4.8, "fov": 46.0, "dur": 9.0},
	{"kind": "pushin","az0": PI * 0.96, "az1": PI * 0.96, "el0": 0.30, "el1": 0.34, "r0": 2.9, "r1": 1.7, "fov": 38.0, "dur": 8.0},
]

var _center: Vector3 = Vector3.ZERO
var _radius: float = 1.0
var _shot_i: int = 0
var _shot_t: float = 0.0
var _cam_pos: Vector3 = Vector3.ZERO
var _cam_look: Vector3 = Vector3.ZERO
var _cam_fov: float = 42.0
var _initialized: bool = false

var camera: Camera3D

func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "BeautyCamera"
	camera.fov = _cam_fov
	camera.near = 0.05
	camera.far = 4000.0
	add_child(camera)
	camera.make_current()

# Frame the ship: `center` is the hull centre in world space, `radius` its
# visual radius. Snaps the camera to the opening shot's start pose.
func set_target(center: Vector3, radius: float) -> void:
	_center = center
	_radius = maxf(radius, 0.2)
	var pose: Dictionary = _shot_pose(_shots[0], 0.0)
	_cam_pos = pose.pos
	_cam_look = pose.look
	_cam_fov = pose.fov
	_initialized = true
	if camera != null:
		camera.position = _cam_pos
		camera.look_at(_cam_look, Vector3.UP)
		camera.fov = _cam_fov

func _process(delta: float) -> void:
	if not _initialized or camera == null:
		return
	var shot: Dictionary = _shots[_shot_i]
	var dur: float = shot.dur
	_shot_t += delta
	var u: float = smoothstep(0.0, 1.0, clampf(_shot_t / dur, 0.0, 1.0))
	if _shot_t >= dur:
		_shot_i = (_shot_i + 1) % _shots.size()
		_shot_t = 0.0

	var pose: Dictionary = _shot_pose(shot, u)
	var tpos: Vector3 = pose.pos
	var tlook: Vector3 = pose.look
	var tfov: float = pose.fov
	var kp: float = 1.0 - exp(-POS_SMOOTH * delta)
	var kl: float = 1.0 - exp(-LOOK_SMOOTH * delta)
	var kf: float = 1.0 - exp(-FOV_SMOOTH * delta)
	_cam_pos = _cam_pos.lerp(tpos, kp)
	_cam_look = _cam_look.lerp(tlook, kl)
	_cam_fov = lerpf(_cam_fov, tfov, kf)

	camera.position = _cam_pos
	camera.look_at(_cam_look, Vector3.UP)
	camera.fov = _cam_fov

# Resolve a shot at eased parameter u∈[0,1] → { pos, look, fov } in world space.
func _shot_pose(shot: Dictionary, u: float) -> Dictionary:
	var az0: float = shot.az0
	var az1: float = shot.az1
	var el0: float = shot.el0
	var el1: float = shot.el1
	var r0: float = shot.r0
	var r1: float = shot.r1
	var fov: float = shot.fov
	var kind: String = shot.kind
	var az: float = lerpf(az0, az1, u)
	var el: float = lerpf(el0, el1, u)
	var r: float = lerpf(r0, r1, u) * _radius
	var pos: Vector3 = _center + _orbit_dir(az, el) * r
	# Push-in aims a little up-and-forward, onto the cockpit; the rest hold centre.
	var look: Vector3 = _center
	if kind == "pushin":
		look = _center + Vector3(0.0, 0.16, -0.2) * _radius
	return {"pos": pos, "look": look, "fov": fov}

# Unit direction from the ship centre out to the camera. az 0 = +Z (behind),
# az PI = -Z (front); el lifts toward +Y.
func _orbit_dir(az: float, el: float) -> Vector3:
	return Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)).normalized()
