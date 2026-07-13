class_name KindlingManager extends Node3D

const JoystickScript := preload("res://scripts/touch_joystick.gd")
const HudBarScript := preload("res://scripts/hud_bar.gd")

@onready var flame: Flame = $Flame
@onready var growth_controller: GrowthController = $GrowthController

var _joystick: Control = null
var _is_dead: bool = false

# Per-touch-index bookkeeping for double-tap classification -- see
# tap_detector.gd for the pure classification logic this drives.
var _touch_down_time: Dictionary = {}  # index -> int (ms)
var _touch_down_pos: Dictionary = {}   # index -> Vector2
var _touch_max_drag: Dictionary = {}   # index -> float
var _last_tap_time: int = -1
var _last_tap_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_joystick = JoystickScript.new()
	layer.add_child(_joystick)
	_joystick.camera = get_viewport().get_camera_3d()
	_joystick.direction_changed.connect(_on_direction_changed)

	var hud_bar: Control = HudBarScript.new()
	hud_bar.growth_controller = growth_controller
	layer.add_child(hud_bar)

	growth_controller.grow_tick.connect(_on_grow_tick)
	flame.set_scale_factor(growth_controller.flame_scale)
	flame.hazard_hit.connect(_on_hazard_hit)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_down_time[event.index] = Time.get_ticks_msec()
			_touch_down_pos[event.index] = event.position
			_touch_max_drag[event.index] = 0.0
			if _joystick:
				_joystick.begin_touch(event.index, event.position)
			return
		_handle_touch_release(event.index, event.position)
		if _joystick:
			_joystick.end_touch(event.index)
		return

	if event is InputEventScreenDrag:
		if _touch_down_pos.has(event.index):
			var drag_dist: float = event.position.distance_to(_touch_down_pos[event.index])
			if drag_dist > _touch_max_drag.get(event.index, 0.0):
				_touch_max_drag[event.index] = drag_dist
		if _joystick:
			_joystick.update_touch(event.index, event.position)
		return


func _handle_touch_release(index: int, release_pos: Vector2) -> void:
	var down_time: int = _touch_down_time.get(index, -1)
	var max_drag: float = _touch_max_drag.get(index, 0.0)
	_touch_down_time.erase(index)
	_touch_down_pos.erase(index)
	_touch_max_drag.erase(index)

	if down_time < 0:
		return
	var duration: int = Time.get_ticks_msec() - down_time
	if not TapDetector.is_tap(duration, max_drag):
		_last_tap_time = -1  # a real drag/long-press breaks a pending sequence
		return

	var now: int = Time.get_ticks_msec()
	if TapDetector.is_double_tap(_last_tap_time, _last_tap_pos, now, release_pos):
		_last_tap_time = -1  # consume -- no triple-tap chaining
		flame.jump()
	else:
		_last_tap_time = now
		_last_tap_pos = release_pos


func _on_direction_changed(dir: Vector3) -> void:
	flame.set_move_direction(dir)


func _on_grow_tick(new_scale: float) -> void:
	flame.set_scale_factor(new_scale)


func _on_hazard_hit(hazard: Hazard) -> void:
	growth_controller.subtract_growth(hazard.shrink_amount)


# Called by DousingThreat on a lethal overlap. Minimal M2 death flow: a full
# scene reload. The brief's actual target flow ("Death returns to menu/
# leaderboard, score = highest tier reached + total Growth Points") needs a
# menu/leaderboard system that's out of scope for this milestone -- reload is
# a deliberate placeholder, not the intended final behavior.
func trigger_death() -> void:
	if _is_dead:
		return
	_is_dead = true
	get_tree().reload_current_scene()
