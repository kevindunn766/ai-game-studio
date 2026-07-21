class_name CameraController extends Camera3D

@export var snake: Node3D
@export var floor_manager: Node3D

const PROXIMITY_SCAN_RADIUS: int = 5
const PROXIMITY_ZOOM_BOOST: float = 6.0

func _ready() -> void:
	current = true
	projection = PROJECTION_ORTHOGONAL
	size = 5.0
	if not snake:
		snake = get_node_or_null("../../../..") as Node3D
	if not floor_manager:
		floor_manager = get_node_or_null("/root/Main/FloorManager") as Node3D

func _process(delta: float) -> void:
	if not snake:
		return
	var seg_count := 0
	for child in snake.get_children():
		if child is Node3D and child.name.begins_with("Seg"):
			seg_count += 1
	var target_size: float = clamp(float(seg_count + 4), 5.0, 40.0)
	target_size = clamp(target_size + _proximity_boost() * PROXIMITY_ZOOM_BOOST, 5.0, 46.0)
	size = lerp(size, target_size, clamp(delta * 4.0, 0.0, 1.0))


# 0..1 based on how close the nearest obstacle is to the snake's head.
# Nudges the camera out a bit when danger is nearby — most noticeable early
# in a run when the snake is short and the segment-count zoom alone would
# otherwise stay tight right up until the obstacle is on top of you.
func _proximity_boost() -> float:
	if not floor_manager or not floor_manager.has_method("is_tile_obstacle_at_grid"):
		return 0.0
	var head := snake.get_node_or_null("Seg0") as Node3D
	if not head:
		return 0.0
	var hx := int(round(head.global_position.x))
	var hz := int(round(head.global_position.z))
	var closest := PROXIMITY_SCAN_RADIUS + 1
	for dx in range(-PROXIMITY_SCAN_RADIUS, PROXIMITY_SCAN_RADIUS + 1):
		for dz in range(-PROXIMITY_SCAN_RADIUS, PROXIMITY_SCAN_RADIUS + 1):
			if dx == 0 and dz == 0:
				continue
			var dist := maxi(absi(dx), absi(dz))
			if dist >= closest:
				continue
			if floor_manager.is_tile_obstacle_at_grid(hx + dx, hz + dz):
				closest = dist
	if closest > PROXIMITY_SCAN_RADIUS:
		return 0.0
	return 1.0 - float(closest - 1) / float(PROXIMITY_SCAN_RADIUS)
