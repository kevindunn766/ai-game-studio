class_name HudBar extends Control

var growth_controller: GrowthController

var _bg: ColorRect
var _fill: ColorRect
var _pulse_tween: Tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	offset_top = 40
	offset_left = 60
	offset_right = -60
	offset_bottom = 68
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_bg = ColorRect.new()
	_bg.color = Color(0.1, 0.08, 0.06, 0.85)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_fill = ColorRect.new()
	_fill.color = Color(1.0, 0.5, 0.1, 0.9)
	_fill.position = Vector2(2, 2)
	_fill.size = Vector2(0, 24)
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fill)

	if not growth_controller:
		growth_controller = get_tree().current_scene.get_node_or_null("GrowthController") as GrowthController
	if growth_controller:
		growth_controller.phase_changed.connect(_on_phase_changed)
		growth_controller.band_changed.connect(_on_band_changed)
		growth_controller.grow_tick.connect(_on_grow_tick)
		if growth_controller.phase == GrowthController.Phase.CHARGE:
			_start_charge_pulse()


func _on_phase_changed(new_phase: GrowthController.Phase) -> void:
	if new_phase == GrowthController.Phase.CHARGE:
		_start_charge_pulse()
	else:
		_stop_charge_pulse()
		_set_fill_frac(0.0)


func _on_grow_tick(_new_scale: float) -> void:
	if growth_controller.phase == GrowthController.Phase.GROW:
		_set_fill_frac(growth_controller.grow_progress())


func _on_band_changed(_new_band_index: int) -> void:
	_set_fill_frac(0.0)
	# "Bar collapses into one larger bar" -- a squash-and-pop punch, not a
	# data-model event; the new band's larger charge_target/grow_target is
	# already live by the time this signal fires.
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.15, 0.55), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_fill_frac(frac: float) -> void:
	var full_width: float = maxf(0.0, size.x - 4.0)
	_fill.size.x = full_width * clampf(frac, 0.0, 1.0)


func _start_charge_pulse() -> void:
	if _pulse_tween and _pulse_tween.is_running():
		return
	_bg.modulate = Color(1, 1, 1, 1)
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.tween_property(_bg, "modulate", Color(1.5, 1.35, 1.1, 1.0), 0.35)
	_pulse_tween.tween_property(_bg, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.35)


func _stop_charge_pulse() -> void:
	if _pulse_tween:
		_pulse_tween.kill()
	_bg.modulate = Color(1, 1, 1, 1)
