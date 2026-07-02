class_name CameraController extends Camera3D

@export var target: Node3D
@export var base_distance: float = 14.0
@export var growth_per_segment: float = 0.4
@export var smooth: float = 4.0
@export var pivot_height: float = 3.0
@export var look_ahead: float = 2.5

@export var tilt_fov: float = 32.0
@export var tilt_near: float = 0.1
@export var tilt_far: float = 150.0

var _pivot: Node3D
var _spring: SpringArm3D
var _initialized: bool = false
var _current_dist: float = 0.0


func _ready() -> void:
	if not target:
		return

	var seg0: Node3D = target.get_node_or_null("Seg0")
	if not is_instance_valid(seg0):
		return

	_pivot = seg0.get_node_or_null("CameraCranePivot")
	_spring = _pivot.get_node_or_null("SpringArm3D") if _pivot else null
	if not is_instance_valid(_spring):
		return

	position = Vector3(0.0, 0.0, 0.0)
	rotation = Vector3(-1.05, 0.0, 0.0)
	_current_dist = base_distance
	_initialized = true

	current = true
	fov = tilt_fov
	near = tilt_near
	far = tilt_far


func _process(delta: float) -> void:
	if not _initialized or not target or not _pivot or not _spring:
		return

	var head: Vector3 = target.global_position
	var dir: Vector3 = Vector3.ZERO
	if target.has_method("get_direction"):
		dir = target.get_direction()
	var back: Vector3 = -dir if dir != Vector3.ZERO else Vector3.BACK

	_pivot.global_position = head + Vector3(0.0, pivot_height, 0.0)
	_pivot.look_at(_pivot.global_position + back, Vector3.UP)

	var segs: int = 0
	for child: Node in target.get_children():
		if child is Node3D and child.name.begins_with("Seg"):
			segs += 1

	var desired: float = base_distance + segs * growth_per_segment
	_current_dist = lerp(_current_dist, desired, clamp(delta * smooth, 0.0, 1.0))
	_spring.spring_length = _current_dist
