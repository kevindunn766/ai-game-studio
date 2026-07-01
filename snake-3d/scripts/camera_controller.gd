class_name CameraController extends Camera3D

@export var target: Node3D
@export var height: float = 13.5
@export var distance: float = 13.5
@export var look_ahead: float = 3.0
@export var smooth: float = 5.0

var _current_target: Vector3 = Vector3.ZERO


func _ready() -> void:
	if target:
		_current_target = target.global_position


func _process(delta: float) -> void:
	if not target:
		return

	var head: Vector3 = target.global_position
	var dir: Vector3 = Vector3.ZERO
	if target.has_method("get_direction"):
		dir = target.get_direction()

	var desired: Vector3 = head + Vector3(0.0, height, distance) + dir * look_ahead
	_current_target = global_position.lerp(desired, clamp(delta * smooth, 0.0, 1.0))
	global_position = _current_target

	# Keep looking slightly ahead of the snake head.
	var look_target: Vector3 = head + dir * 2.0
	look_at(look_target, Vector3.UP)
