class_name CameraController extends Camera3D

@export var flame: Node3D

# Calibrated against flame_scale as a real-world size in meters (see
# growth_controller.gd's BAND_TABLE comment) -- Camera3D.size is the ortho
# view's vertical extent in world units/meters.
#
# MIN_SIZE/BASE_SIZE bumped (was 0.4/0.35) after discovering the tighter
# framing left almost no visible margin beyond the flame's own passive
# ignite radius (~0.11-0.14m at match-scale) -- anything that spawned that
# close got auto-consumed almost the instant it appeared, so the old view
# was mostly showing that self-cleared dead zone with barely any buffer of
# actual unburned fuel around its edge. A wider ~0.7m view gives a real ring
# of visible, un-eaten fuel outside that dead zone.
#
# MAX_SIZE raised (was 30.0) once all 9 bands existed -- 30 was set back when
# only Bands 1-3 (max scale 0.6m) were built and genuinely was "generous for
# future bands," but never got revisited once Band 9 pushed flame_scale up to
# 140m; at the old cap the camera would've stopped zooming out around Band 6
# while the flame kept growing, leaving it larger than its own view by Band
# 9. flame.gd's movement speed is now also derived directly from
# target_size_for_scale(), so this constant governs pacing as well as
# framing -- keep both in mind if retuning it.
const BASE_SIZE: float = 0.6
const SIZE_PER_SCALE_UNIT: float = 4.0
const MIN_SIZE: float = 0.7
const MAX_SIZE: float = 600.0


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
