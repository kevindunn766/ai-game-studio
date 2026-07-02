class_name CameraController extends Camera3D

@export var target: Node3D
@export var distance: float = 14.0
@export var height: float = 10.0
@export var growth_per_segment: float = 0.4
@export var smooth: float = 4.0
@export var pivot_height: float = 2.0
@export var look_height: float = 2.5

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

	_current_dist = distance
	# Place camera at the tip of the spring arm so it actually looks
	# down the arm at the snake instead of sitting at the pivot joint.
	position = Vector3(0.0, 0.0, -_current_dist)
	_initialized = true

	current = true
	fov = 32.0
	near = 0.1
	far = 150.0

func _process(delta: float) -> void:
	if not _initialized or not target or not _pivot or not _spring:
		return

	var head: Vector3 = target.global_position
	var dir: Vector3 = Vector3.ZERO
	if target.has_method("get_direction"):
		dir = target.get_direction()
	var back: Vector3 = -dir.normalized() if dir != Vector3.ZERO else Vector3.BACK

	# Adaptive transform 1: pivot translates above snake head.
	_pivot.global_position = head + Vector3(0.0, pivot_height, 0.0)
	# Fixed isometric pivot: crane arm always faces the same world diagonal,
	# so the camera looks at the snake from a true isometric angle regardless of direction.
	var iso_dir: Vector3 = Vector3(0.612, 0.0, 0.612).normalized()
	_pivot.look_at(_pivot.global_position + iso_dir * distance, Vector3.UP)

	# Adaptive transform 3: spring length grows with body length.
	var segs: int = 0
	for child in target.get_children():
		if child is Node3D and child.name.begins_with("Seg"):
			segs += 1
	var desired_dist: float = distance + segs * growth_per_segment
	_current_dist = lerp(_current_dist, desired_dist, clamp(delta * smooth, 0.0, 1.0))
	_spring.spring_length = _current_dist
	position = Vector3(0.0, 0.0, -_current_dist)

	# Set spring arm to isometric angle.
	_spring.rotation = Vector3(deg_to_rad(35.264), 0.0, 0.0)

	# Elevated look target through inherited crane-arm transform.
	look_at(head + Vector3.UP * look_height, Vector3.UP)


