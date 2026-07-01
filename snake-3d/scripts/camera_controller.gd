class_name CameraController extends Camera3D

@export var target: Node3D
@export var height: float = 13.5
@export var distance: float = 13.5
@export var look_ahead: float = 3.0
@export var smooth: float = 5.0

# Crane arm: attach to a pivot above/behind the snake so the orbit
# is centered on a standing-in-place pivot even when the snake turns.
@export var pivot_height: float = 2.0
@export var pivot_distance: float = 5.0

var _pivot: Node3D
var _current_offset: Vector3 = Vector3.ZERO


func _ready() -> void:
	_pivot = Node3D.new()
	_pivot.name = "CameraCranePivot"
	add_child(_pivot)

	if target:
		_current_offset = _compute_crane_offset()
		global_position = target.global_position + _current_offset


func _process(delta: float) -> void:
	if not _pivot or not target:
		return

	_pivot.global_position = target.global_position + Vector3(0.0, pivot_height, 0.0)
	_pivot.look_at(_pivot.global_position + Vector3.BACK, Vector3.UP)

	var desired: Vector3 = target.global_position + _compute_crane_offset()
	_current_offset = global_position - target.global_position
	_current_offset = _current_offset.lerp(desired - target.global_position, clamp(delta * smooth, 0.0, 1.0))
	global_position = target.global_position + _current_offset

	var head: Vector3 = target.global_position
	var dir: Vector3 = Vector3.ZERO
	if target.has_method("get_direction"):
		dir = target.get_direction()
	var look_target: Vector3 = head + dir * 2.0
	look_at(look_target, Vector3.UP)


func _compute_crane_offset() -> Vector3:
	var dir: Vector3 = Vector3.ZERO
	if target and target.has_method("get_direction"):
		dir = target.get_direction()
	var back: Vector3 = -dir if dir != Vector3.ZERO else Vector3.BACK
	return back * distance + Vector3(0.0, height, 0.0)
