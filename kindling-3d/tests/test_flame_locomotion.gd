extends SceneTree

var _failures: int = 0


func _init() -> void:
	_test_climb_arc_height_flat_target()
	_test_climb_arc_height_scales_with_structure_height()
	_test_sample_history_empty()
	_test_sample_history_before_range_clamps()
	_test_sample_history_after_range_clamps()
	_test_sample_history_interpolates()

	if _failures == 0:
		print("ALL PASS")
	else:
		print("%d FAILURE(S)" % _failures)
	quit(1 if _failures > 0 else 0)


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("FAIL: ", msg)


func _test_climb_arc_height_flat_target() -> void:
	# A Fuel target (or no target at all) has no "height" concept -- the
	# caller passes 0.0, and the arc should stay at the plain jump_height.
	var h: float = Flame.climb_arc_height(0.6, 0.0, 0.5)
	_assert(is_equal_approx(h, 0.6), "flat target should not add any climb bonus, got %f" % h)


func _test_climb_arc_height_scales_with_structure_height() -> void:
	# house height = 5.0m, climb_height_fraction = 0.5 -> +2.5m on top of base
	var h: float = Flame.climb_arc_height(0.6, 5.0, 0.5)
	_assert(is_equal_approx(h, 3.1), "climb arc should be base + height*fraction, got %f" % h)

	# taller structure (district, 10.0m) should arc higher than a shorter one (shed, 2.0m)
	var shed_h: float = Flame.climb_arc_height(0.6, 2.0, 0.5)
	var district_h: float = Flame.climb_arc_height(0.6, 10.0, 0.5)
	_assert(district_h > shed_h, "taller structures should produce a taller climb arc")


func _test_sample_history_empty() -> void:
	var v: Vector3 = Flame.sample_history([], 5.0)
	_assert(v == Vector3.ZERO, "empty history should return a safe zero vector, not crash")


func _test_sample_history_before_range_clamps() -> void:
	var history: Array[Dictionary] = [
		{"t": 10.0, "pos": Vector3(1, 0, 0)},
		{"t": 11.0, "pos": Vector3(2, 0, 0)},
	]
	var v: Vector3 = Flame.sample_history(history, 5.0)
	_assert(v == Vector3(1, 0, 0), "sampling before the oldest entry should clamp to it, got %s" % v)


func _test_sample_history_after_range_clamps() -> void:
	var history: Array[Dictionary] = [
		{"t": 10.0, "pos": Vector3(1, 0, 0)},
		{"t": 11.0, "pos": Vector3(2, 0, 0)},
	]
	var v: Vector3 = Flame.sample_history(history, 999.0)
	_assert(v == Vector3(2, 0, 0), "sampling past the newest entry should clamp to it, got %s" % v)


func _test_sample_history_interpolates() -> void:
	var history: Array[Dictionary] = [
		{"t": 10.0, "pos": Vector3(0, 0, 0)},
		{"t": 12.0, "pos": Vector3(10, 0, 0)},
	]
	var v: Vector3 = Flame.sample_history(history, 11.0)
	_assert(v.is_equal_approx(Vector3(5, 0, 0)), "midpoint sample should linearly interpolate, got %s" % v)
