class_name CameraController extends Camera3D

@export var flame: Node3D

# Calibrated against flame_scale as a real-world size in meters (see
# growth_controller.gd's BAND_TABLE comment) -- Camera3D.size is the ortho
# view's vertical extent in world units/meters. MAX_SIZE stays generous for
# future bands beyond this milestone's scope.
#
# MIN_SIZE/BASE_SIZE bumped (was 0.4/0.35) after discovering the tighter
# framing left almost no visible margin beyond the flame's own passive
# ignite radius (~0.11-0.14m at match-scale) -- anything that spawned that
# close got auto-consumed almost the instant it appeared, so the old view
# was mostly showing that self-cleared dead zone with barely any buffer of
# actual unburned fuel around its edge. A wider ~0.7m view gives a real ring
# of visible, un-eaten fuel outside that dead zone.
const BASE_SIZE: float = 0.6
const SIZE_PER_SCALE_UNIT: float = 4.0
const MIN_SIZE: float = 0.7
const MAX_SIZE: float = 30.0


func _ready() -> void:
	current = true
	projection = PROJECTION_ORTHOGONAL
	if not flame:
		flame = get_node_or_null("../../..") as Node3D
	# Start exactly at the target for the flame's initial scale, not a bare
	# MIN_SIZE -- otherwise the camera visibly zooms on startup before the
	# player has burned anything, which would read as a false growth event.
	size = target_size_for_scale(flame.scale_factor if flame else 1.0)


func _process(delta: float) -> void:
	if not flame:
		return
	var target_size: float = target_size_for_scale(flame.scale_factor)
	size = lerp(size, target_size, clamp(delta * 4.0, 0.0, 1.0))


# Pure function so the target-size curve is headlessly testable without a
# live Camera3D/scene tree -- see tests/test_camera_target_size.gd.
static func target_size_for_scale(scale_factor: float) -> float:
	return clampf(BASE_SIZE + scale_factor * SIZE_PER_SCALE_UNIT, MIN_SIZE, MAX_SIZE)
