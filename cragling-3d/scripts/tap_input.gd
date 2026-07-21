extends Node

# Raycasts a press/release against the wall's collision body and routes it
# to one of Climber's four entry points based on direction (above/below the
# climber) and gesture (quick tap / double tap / press-and-hold):
#
#   Above the climber:
#     single tap  -> normal climb (Climber.start_climb_to)
#     double tap  -> gap jump, a dynamic lunge past the normal single-move
#                    reach (Climber.start_gap_jump)
#   Below the climber:
#     quick tap (released before HOLD_THRESHOLD) -> single discrete rappel
#       move, same as before (Climber.start_rappel_to)
#     press-and-hold -> continuous full-limb rope slide that keeps
#       descending for as long as the press is held
#       (Climber.start_continuous_slide / stop_continuous_slide)
#
# Single-tap-above is deliberately committed after a short delay
# (DOUBLE_TAP_WINDOW) rather than firing immediately, so a fast second tap
# can still be recognized as a double-tap instead of both actions firing --
# the standard trade-off any double-tap gesture makes (a small, barely
# perceptible latency on every single tap above). Below doesn't need this:
# tap-vs-hold is resolved in real time by how long the press is actually
# held, not by waiting to see if a second press follows.

const DOUBLE_TAP_WINDOW: float = 0.28
const HOLD_THRESHOLD: float = 0.16
const DOUBLE_TAP_MAX_DIST: float = 60.0

@export var camera_path: NodePath
@export var climber_path: NodePath

var _camera: Camera3D
var _climber: Climber

var _pressed: bool = false
var _press_id: int = 0
var _press_world_pos: Vector3 = Vector3.ZERO
var _press_below: bool = false

var _last_above_tap_time: float = -10.0
var _last_above_tap_screen_pos: Vector2 = Vector2.ZERO
var _pending_single_id: int = 0


func _ready() -> void:
	_camera = get_node(camera_path) as Camera3D
	_climber = get_node(climber_path) as Climber


func _unhandled_input(event: InputEvent) -> void:
	# Only InputEventScreenTouch, deliberately -- the project sets
	# pointing/emulate_touch_from_mouse=true (so desktop mouse testing still
	# works), which makes Godot synthesize a matching InputEventScreenTouch
	# for every InputEventMouseButton. Handling both types here double-fired
	# every single gesture (confirmed by logging event.get_class(): one
	# physical click delivered a touch press+release AND a mouse
	# press+release), which was the real cause of gestures firing multiple
	# times in a cascade -- not a bug in the gesture logic itself.
	var screen_pos: Vector2
	var pressed: bool
	if event is InputEventScreenTouch:
		screen_pos = event.position
		pressed = event.pressed
	else:
		return
	if pressed:
		_on_press(screen_pos)
	else:
		_on_release(screen_pos)


func _on_press(screen_pos: Vector2) -> void:
	if not _camera or not _climber:
		return
	var hit = _raycast(screen_pos)
	if hit == null:
		return

	_pressed = true
	_press_id += 1
	_press_world_pos = hit
	_press_below = _climber.is_point_below(hit)

	if _press_below:
		var my_id := _press_id
		await get_tree().create_timer(HOLD_THRESHOLD).timeout
		if _pressed and _press_id == my_id:
			_climber.start_continuous_slide()


func _on_release(screen_pos: Vector2) -> void:
	if not _pressed:
		return
	_pressed = false

	if _climber.is_sliding():
		_climber.stop_continuous_slide()
		return

	if _press_below:
		# Released before HOLD_THRESHOLD fired, so the slide never
		# started -- a quick tap, same single discrete rappel as before.
		# Note: the tap position itself has already done its only job
		# (is_point_below routed us here); the rappel doesn't use it.
		_climber.start_rappel_to()
		return

	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_above_tap_time < DOUBLE_TAP_WINDOW and screen_pos.distance_to(_last_above_tap_screen_pos) < DOUBLE_TAP_MAX_DIST:
		_pending_single_id += 1 # cancels the first tap's deferred climb below
		_last_above_tap_time = -10.0
		_climber.start_gap_jump(_press_world_pos)
		return

	_last_above_tap_time = now
	_last_above_tap_screen_pos = screen_pos
	var my_single_id := _pending_single_id
	await get_tree().create_timer(DOUBLE_TAP_WINDOW).timeout
	if _pending_single_id == my_single_id:
		_climber.start_climb_to(_press_world_pos)


func _raycast(screen_pos: Vector2):
	var from := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	var to := from + dir * 200.0
	var space_state := _camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var result := space_state.intersect_ray(query)
	if result.has("position"):
		return result["position"]
	return null
