class_name CameraController extends Camera3D

@export var target: Node3D
@export var distance: float = 13.5
@export var height: float = 13.5
@export var look_ahead: float = 3.0
@export var smooth: float = 5.0
@export var pivot_height: float = 2.0

var _pivot: Node3D
var _spring: SpringArm3D
var _current_offset: Vector3 = Vector3.ZERO


func _ready() -> void:
	if not target:
		return

	_pivot = Node3D.new()
	_pivot.name = "CameraCranePivot"
	target.add_child(_pivot)

	_spring = SpringArm3D.new()
	_spring.name = "SpringArm3D"
	_pivot.add_child(_spring)

	if get_parent() != _spring:
		var parent = get_parent()
		if parent:
			parent.remove_child(self)
		_spring.add_child(self)

	_spring.spring_length = distance
	_spring.collision_mask = 0

	_current_offset = _compute_crane_offset()
	global_position = target.global_position + _current_offset


func _process(delta: float) -> void:
	if not target or not _pivot or not _spring:
		return

	var head: Vector3 = target.global_position
	var dir: Vector3 = Vector3.ZERO
	if target.has_method("get_direction"):
		dir = target.get_direction()

	var back: Vector3 = -dir if dir != Vector3.ZERO else Vector3.BACK
	_pivot.global_position = head + Vector3(0.0, pivot_height, 0.0)
	_pivot.look_at(_pivot.global_position + back, Vector3.UP)

	var desired: Vector3 = _compute_crane_offset()
	_current_offset = _current_offset.lerp(desired, clamp(delta * smooth, 0.0, 1.0))
	global_position = head + _current_offset

	look_at(head + back * look_ahead, Vector3.UP)


func _compute_crane_offset() -> Vector3:
	var dir: Vector3 = Vector3.ZERO
	if target and target.has_method("get_direction"):
		dir = target.get_direction()
	var back: Vector3 = -dir if dir != Vector3.ZERO else Vector3.BACK
	return back * distance + Vector3(0.0, height, 0.0)
