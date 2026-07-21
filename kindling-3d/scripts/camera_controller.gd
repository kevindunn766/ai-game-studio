extends Node

# Camera sizing, brought over from Snake_3d's camera_controller: the orthographic
# camera's `size` (zoom) eases toward a target, zooming OUT with the size of things.
# Snake zoomed on the snake's segment count + a proximity boost near obstacles; here,
# per the brief ("zooms out with the size of the player/objects as the player
# approaches things"), it zooms out based on the size of scattered objects near the
# fixed player, which the treadmill scrolls toward it. Kept subtle (small `size_gain`).

# The scale voyage is driven by world_size (main.gd scales the whole world), NOT by the
# camera -- the camera stays fixed so the flame holds a constant on-screen size and the
# world's shrinking is what reads as growth. Approach-zoom is off (size_gain 0) for this
# pass; it can come back subtly later.
@export var base_size: float = 2.5         # resting orthographic size (matches the rig)
@export var scan_radius: float = 7.0       # how near an object must be to influence zoom
@export var size_gain: float = 0.0         # OFF for now (was Snake's subtle approach-zoom)
@export var max_size: float = 2.5
@export var ease_speed: float = 4.0

var camera: Camera3D = null
var streamer: Node = null                  # WorldStreamer
var player: Node3D = null


func _process(delta: float) -> void:
	if camera == null:
		return
	var target: float = base_size
	if streamer != null and streamer.has_method("approach_influence"):
		var center: Vector3 = player.global_position if player != null else Vector3.ZERO
		target += streamer.approach_influence(center, scan_radius) * size_gain
	target = clampf(target, base_size, max_size)
	camera.size = lerpf(camera.size, target, clampf(delta * ease_speed, 0.0, 1.0))
