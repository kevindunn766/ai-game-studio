extends Control

# On-screen TOUCH controls for mobile playtesting: a floating left-side virtual
# joystick (analog steering) + FIRE and BOOST buttons on the right. It drives the
# EXISTING input actions (steer_left/right/up/down, fire, afterburner) via
# Input.action_press/release, so the ship needs no changes. Shown only when a
# touchscreen is available; game_hud toggles it on/off with the ship's alive state.

const STEER_R := "steer_right"
const STEER_L := "steer_left"
const STEER_U := "steer_up"
const STEER_D := "steer_down"

@export var stick_radius: float = 130.0
@export var button_radius: float = 82.0
@export var dead_zone: float = 0.14

var _avail: bool = false
var _stick_touch: int = -1
var _stick_center: Vector2 = Vector2.ZERO
var _stick_pos: Vector2 = Vector2.ZERO
var _fire_touch: int = -1
var _ab_touch: int = -1
var _accent: Color = Color(0.55, 0.8, 1.0)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # never eat GUI clicks; touch via _input
	_avail = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") \
		or bool(ProjectSettings.get_setting("input_devices/pointing/emulate_touch_from_mouse", false))
	set_active(_avail)

# Called by game_hud: only active (visible + listening) while the ship is flying.
func set_active(on: bool) -> void:
	var a: bool = on and _avail
	visible = a
	set_process_input(a)
	if not a:
		_release_all()
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_on_press(t.index, t.position)
		else:
			_on_release(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_touch:
			_stick_pos = d.position
			_update_steer()
			queue_redraw()

func _on_press(idx: int, pos: Vector2) -> void:
	if pos.distance_to(_fire_center()) <= button_radius * 1.15:
		_fire_touch = idx
		Input.action_press("fire")
	elif pos.distance_to(_boost_center()) <= button_radius * 1.15:
		_ab_touch = idx
		Input.action_press("afterburner")
	elif pos.x < _vp().x * 0.55 and _stick_touch == -1:
		_stick_touch = idx
		_stick_center = pos
		_stick_pos = pos
		_update_steer()
	queue_redraw()

func _on_release(idx: int) -> void:
	if idx == _stick_touch:
		_stick_touch = -1
		_release_steer()
	elif idx == _fire_touch:
		_fire_touch = -1
		Input.action_release("fire")
	elif idx == _ab_touch:
		_ab_touch = -1
		Input.action_release("afterburner")
	queue_redraw()

func _update_steer() -> void:
	var off: Vector2 = _stick_pos - _stick_center
	if off.length() > stick_radius:
		off = off.normalized() * stick_radius
		_stick_pos = _stick_center + off
	var v: Vector2 = off / stick_radius            # -1..1, screen space (y is DOWN)
	if v.length() < dead_zone:
		_release_steer()
		return
	_axis(STEER_R, maxf(v.x, 0.0))
	_axis(STEER_L, maxf(-v.x, 0.0))
	_axis(STEER_U, maxf(-v.y, 0.0))                # screen-up is negative y
	_axis(STEER_D, maxf(v.y, 0.0))

func _axis(action: String, strength: float) -> void:
	if strength > 0.05:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)

func _release_steer() -> void:
	for a in [STEER_R, STEER_L, STEER_U, STEER_D]:
		Input.action_release(a)

func _release_all() -> void:
	_release_steer()
	Input.action_release("fire")
	Input.action_release("afterburner")
	_stick_touch = -1
	_fire_touch = -1
	_ab_touch = -1

# --- layout + drawing ------------------------------------------------------
# A Control under a CanvasLayer doesn't reliably report the viewport size, so all
# positions key off get_viewport_rect() (base 1280x720 under canvas_items stretch).
func _vp() -> Vector2:
	return get_viewport_rect().size

func _fire_center() -> Vector2:
	var s := _vp()
	return Vector2(s.x - button_radius - 70.0, s.y - button_radius - 80.0)

func _boost_center() -> Vector2:
	var s := _vp()
	return Vector2(s.x - button_radius - 70.0 - button_radius * 2.5, s.y - button_radius - 55.0)

func _draw() -> void:
	if _stick_touch != -1:
		draw_circle(_stick_center, stick_radius, Color(1, 1, 1, 0.06))
		draw_arc(_stick_center, stick_radius, 0.0, TAU, 48, Color(_accent.r, _accent.g, _accent.b, 0.5), 3.0, true)
		draw_circle(_stick_pos, stick_radius * 0.4, Color(_accent.r, _accent.g, _accent.b, 0.55))
	else:
		var hint := Vector2(stick_radius + 70.0, _vp().y - stick_radius - 70.0)
		draw_arc(hint, stick_radius, 0.0, TAU, 48, Color(1, 1, 1, 0.1), 2.0, true)
		draw_arc(hint, stick_radius * 0.4, 0.0, TAU, 32, Color(1, 1, 1, 0.14), 2.0, true)
	_draw_button(_fire_center(), "FIRE", _fire_touch != -1, Color(1.0, 0.5, 0.4))
	_draw_button(_boost_center(), "BOOST", _ab_touch != -1, _accent)

func _draw_button(c: Vector2, label: String, pressed: bool, col: Color) -> void:
	draw_circle(c, button_radius, Color(col.r, col.g, col.b, 0.35 if pressed else 0.14))
	draw_arc(c, button_radius, 0.0, TAU, 40, Color(col.r, col.g, col.b, 0.75), 3.0, true)
	var font: Font = UITheme.FONT
	var fs := 13
	var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, c + Vector2(-w * 0.5, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.92))
