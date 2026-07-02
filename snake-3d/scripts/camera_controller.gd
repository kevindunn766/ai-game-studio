class_name CameraController extends Camera3D

@export var target: Node3D
@export var distance: float = 14.0
@export var growth_per_segment: float = 0.4
@export var smooth: float = 4.0
@export var pivot_height: float = 2.0
@export var look_height: float = 2.5

var _initialized: bool = false
var _current_dist: float = 0.0

func _ready() -> void:
	if not target:
		return

	var seg0: Node3D = target.get_node_or_null("Seg0")
	if not is_instance_valid(seg0):
		return

	_current_dist = distance
	_initialized = true

	current = true
	fov = 32.0
	near = 0.1
	far = 150.0

func _process(delta: float) -> void:
	if not _initialized or not target:
		return

	var head: Vector3 = target.global_position
	var segs: int = 0
	for child in target.get_children():
		if child is Node3D and child.name.begins_with("Seg"):
			segs += 1
	var desired_dist: float = distance + segs * growth_per_segment
	_current_dist = lerp(_current_dist, desired_dist, clamp(delta * smooth, 0.0, 1.0))

	# Fixed isometric direction; pitch down 35.264°.
	var iso_dir: Vector3 = Vector3(0.612, 0.0, 0.612).normalized()
	var pitch_rad: float = deg_to_rad(35.264)
	var horizontal_dist: float = _current_dist * cos(pitch_rad)
	var vertical_gain: float = _current_dist * sin(pitch_rad)
	var offset: Vector3 = Vector3(
		iso_dir.x * horizontal_dist,
		pivot_height + vertical_gain,
		iso_dir.z * horizontal_dist
	)

	global_position = head + offset
	look_at(head + Vector3.UP * look_height, Vector3.UP)
