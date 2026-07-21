class_name TouchJoystick extends Control

signal direction_changed(dir: Vector3)

@export var base_radius: float = 100.0
@export var knob_radius: float = 44.0
@export var deadzone_ratio: float = 0.18
@export var sector_hysteresis_deg: float = 14.0
@export var camera: Camera3D

const _WORLD_DIRS := [Vector3.RIGHT, Vector3.BACK, Vector3.FORWARD, Vector3.LEFT]

var _touch_index: int = -1
var _anchor: Vector2 = Vector2.ZERO
var _current_dir: Vector3 = Vector3.ZERO

# Screen-space angle each world direction currently projects to (0=right,
# 90=down, ±180=left). Defaults to a non-rotated top-down mapping and gets
# replaced with the camera's real projection in _refresh_direction_angles().
var _dir_angles: Dictionary = {
	Vector3.RIGHT: 0.0,
	Vector3.BACK: 90.0,
	Vector3.FORWARD: -90.0,
	Vector3.LEFT: 180.0,
}

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
	_refresh_direction_angles()


# Re-derives, from the live camera, which screen angle each of the four
# world-grid directions currently projects to. Recomputed fresh at the start
# of every touch (nothing here is cached across playthroughs or gestures) so
# the mapping always matches whatever the fixed isometric camera is actually
# showing, and can't drift or go stale after a restart.
func _refresh_direction_angles() -> void:
	if not camera or not is_instance_valid(camera):
		return
	var origin_screen: Vector2 = camera.unproject_position(Vector3.ZERO)
	for dir in _WORLD_DIRS:
		var offset_screen: Vector2 = camera.unproject_position(dir)
		var screen_delta: Vector2 = offset_screen - origin_screen
		if screen_delta.length_squared() > 0.0001:
			_dir_angles[dir] = rad_to_deg(screen_delta.angle())


func update_touch(touch_index: int, pos: Vector2) -> void:
	if touch_index != _touch_index:
		return
	var delta: Vector2 = pos - _anchor
	var clamped: Vector2 = delta.limit_length(base_radius)
	_knob_visual.position = _anchor + clamped - _knob_visual.size * 0.5

	if delta.length() < base_radius * deadzone_ratio:
		_current_dir = Vector3.ZERO
		return

	var new_dir: Vector3 = _direction_for_delta(delta)
	if new_dir != _current_dir:
		_current_dir = new_dir
		direction_changed.emit(new_dir)


# Picks whichever of the four world directions currently projects closest
# (on screen) to the touch angle -- a Voronoi-style split around whatever the
# camera's real projected axis angles are, rather than assuming a fixed
# top-down "+" cross. This is what makes the stick track the isometric
# camera's rotated view instead of the raw world axes. The currently-held
# direction gets a few extra degrees of hysteresis so small wobble near a
# sector boundary doesn't flicker between two directions.
func _direction_for_delta(delta: Vector2) -> Vector3:
	var angle_deg: float = rad_to_deg(delta.angle())  # 0=right, 90=down, ±180=left (screen space)
	var best_dir: Vector3 = _WORLD_DIRS[0]
	var best_diff: float = INF
	for dir in _WORLD_DIRS:
		var diff: float = absf(wrapf(angle_deg - float(_dir_angles[dir]), -180.0, 180.0))
		if dir == _current_dir:
			diff = maxf(0.0, diff - sector_hysteresis_deg)
		if diff < best_diff:
			best_diff = diff
			best_dir = dir
	return best_dir


func end_touch(touch_index: int) -> void:
	if touch_index != _touch_index:
		return
	_touch_index = -1
	visible = false
