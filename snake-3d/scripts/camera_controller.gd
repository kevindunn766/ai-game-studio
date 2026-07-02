class_name CameraController extends Camera3D

@export var target: Node3D
@export var base_distance: float = 14.0
@export var growth_per_segment: float = 0.4
@export var smooth: float = 4.0
@export var look_height: float = 1.5

# === Pure isometric basis (fixed world angles, NOT from snake direction) ===
@export var iso_elevation_deg: float = 35.264
@export var iso_azimuth_deg: float = 45.0

@export var tilt_fov: float = 32.0
@export var tilt_near: float = 0.1
@export var tilt_far: float = 150.0

var _head: Node3D
var _initialized: bool = false
var _current_dist: float = 0.0

func _ready() -> void:
	if not target:
		return

	_head = target.get_node_or_null("Seg0")
	if not is_instance_valid(_head):
		return

	_current_dist = base_distance
	_initialized = true

	current = true
	fov = tilt_fov
	near = tilt_near
	far = tilt_far

func _process(delta: float) -> void:
	if not _initialized or not is_instance_valid(_head) or not target:
		return

	var head_pos: Vector3 = target.global_position

	# Count segments for adaptive distance.
	var segs: int = 0
	for child in target.get_children():
		if child is Node3D and child.name.begins_with("Seg"):
			segs += 1
	var desired_dist: float = base_distance + segs * growth_per_segment
	_current_dist = lerp(_current_dist, desired_dist, clamp(delta * smooth, 0.0, 1.0))

	# ISOMETRIC TRANSFORM: fixed world basis, snake position is ONLY the anchor.
	var elev_rad: float = deg_to_rad(iso_elevation_deg)
	var azim_rad: float = deg_to_rad(iso_azimuth_deg)
	var dir_x: float = cos(elev_rad) * sin(azim_rad)
	var dir_y: float = sin(elev_rad)
	var dir_z: float = cos(elev_rad) * cos(azim_rad)
	var iso_dir: Vector3 = Vector3(dir_x, dir_y, dir_z).normalized()

	var cam_pos: Vector3 = head_pos + iso_dir * _current_dist
	global_position = global_position.lerp(cam_pos, clamp(delta * smooth, 0.0, 1.0))

	# Look target is offset upward from head, independent of snake rotation.
	var look_target: Vector3 = head_pos + Vector3.UP * look_height
	look_at(look_target, Vector3.UP)
