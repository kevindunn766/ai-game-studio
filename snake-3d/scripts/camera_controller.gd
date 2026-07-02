class_name CameraController extends Camera3D

@export var target: Node3D
@export var base_distance: float = 13.5
@export var growth_per_segment: float = 0.4
@export var smooth: float = 5.0
@export var pivot_height: float = 2.0
@export var height: float = 0.8
@export var look_ahead: float = 3.0

var _pivot: Node3D
var _spring: SpringArm3D
var _initialized: bool = false


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

	position = Vector3(0.0, height, 0.0)
	_initialized = true

	current = true


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
	_spring.spring_length = clamp(
		lerp(_spring.spring_length, desired, clamp(delta * smooth, 0.0, 1.0)),
		base_distance,
		base_distance + 99.0 * growth_per_segment
	)

	look_at(head + back * look_ahead, Vector3.UP)
