class_name TouchJoystick extends Control

signal direction_changed(dir: Vector3)

@export var base_radius: float = 100.0
@export var knob_radius: float = 44.0
@export var deadzone_ratio: float = 0.18
@export var camera: Camera3D

var _touch_index: int = -1
var _anchor: Vector2 = Vector2.ZERO
var _current_dir: Vector3 = Vector3.ZERO

# Screen-space vectors that world RIGHT/FORWARD currently project to under
# the fixed isometric camera. Defaults to a non-rotated top-down mapping and
# gets replaced with the camera's real projection in _refresh_screen_basis().
var _screen_right: Vector2 = Vector2(1, 0)
var _screen_forward: Vector2 = Vector2(0, 1)

var _base_visual: Panel
var _knob_visual: Panel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_base_visual = _make_circle(base_radius * 2.0, Color(1.0, 1.0, 1.0, 0.16))
	add_child(_base_visual)

	_knob_visual = _make_circle(knob_radius * 2.0, Color(1.0, 1.0, 1.0, 0.38))
	add_child(_knob_visual)

	visible = false


func _make_circle(diameter: float, color: Color) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(diameter, diameter)
	p.size = Vector2(diameter, diameter)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(diameter / 2.0))
	style.set_border_width_all(3)
	style.border_color = Color(1.0, 1.0, 1.0, 0.4)
	p.add_theme_stylebox_override("panel", style)
	return p


func begin_touch(touch_index: int, pos: Vector2) -> void:
	_touch_index = touch_index
	_anchor = pos
	_current_dir = Vector3.ZERO
	visible = true
	_base_visual.position = _anchor - _base_visual.size * 0.5
	_knob_visual.position = _anchor - _knob_visual.size * 0.5
	_refresh_screen_basis()


# Re-derives, from the live camera, which screen vector world RIGHT and world
# FORWARD currently project to. Recomputed fresh at the start of every touch
# (nothing here is cached across playthroughs) so the mapping always matches
# whatever the fixed isometric camera is actually showing.
func _refresh_screen_basis() -> void:
	if not camera or not is_instance_valid(camera):
		return
	var origin_screen: Vector2 = camera.unproject_position(Vector3.ZERO)
	var right_screen: Vector2 = camera.unproject_position(Vector3.RIGHT) - origin_screen
	var forward_screen: Vector2 = camera.unproject_position(Vector3.FORWARD) - origin_screen
	if right_screen.length_squared() > 0.0001:
		_screen_right = right_screen
	if forward_screen.length_squared() > 0.0001:
		_screen_forward = forward_screen


func update_touch(touch_index: int, pos: Vector2) -> void:
	if touch_index != _touch_index:
		return
	var delta: Vector2 = pos - _anchor
	var clamped: Vector2 = delta.limit_length(base_radius)
	_knob_visual.position = _anchor + clamped - _knob_visual.size * 0.5

	if delta.length() < base_radius * deadzone_ratio:
		if _current_dir != Vector3.ZERO:
			_current_dir = Vector3.ZERO
			direction_changed.emit(_current_dir)
		return

	var new_dir: Vector3 = _direction_for_delta(delta)
	if new_dir != _current_dir:
		_current_dir = new_dir
		direction_changed.emit(new_dir)


# Inverts the screen-space basis (world RIGHT/FORWARD projected through the
# fixed isometric camera) to recover a continuous world-space direction from
# the raw screen drag. This is the same camera-relative technique snake-3d's
# joystick uses, generalized from a discrete 4-way Voronoi split (appropriate
# there since snake moves on a grid) to a continuous analog angle, since
# Kindling's flame free-roams rather than snapping to grid axes.
func _direction_for_delta(delta: Vector2) -> Vector3:
	var det: float = _screen_right.x * _screen_forward.y - _screen_right.y * _screen_forward.x
	if absf(det) < 0.0001:
		return Vector3.ZERO
	var a: float = (delta.x * _screen_forward.y - delta.y * _screen_forward.x) / det
	var b: float = (_screen_right.x * delta.y - _screen_right.y * delta.x) / det
	var world: Vector3 = Vector3.RIGHT * a + Vector3.FORWARD * b
	if world.length_squared() < 0.0001:
		return Vector3.ZERO
	return world.normalized()


func end_touch(touch_index: int) -> void:
	if touch_index != _touch_index:
		return
	_touch_index = -1
	visible = false
