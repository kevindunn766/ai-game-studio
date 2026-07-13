extends SceneTree

var _failures: int = 0


func _init() -> void:
	_test_quick_low_drag_is_tap()
	_test_slow_release_is_not_tap()
	_test_far_drag_is_not_tap()
	_test_drag_out_and_snap_back_is_not_tap()
	_test_two_quick_close_taps_is_double_tap()
	_test_single_tap_is_not_double_tap()
	_test_taps_too_far_apart_in_time_not_double_tap()
	_test_taps_too_far_apart_in_space_not_double_tap()
	_test_no_pending_tap_is_not_double_tap()

	if _failures == 0:
		print("ALL PASS")
	else:
		print("%d FAILURE(S)" % _failures)
	quit(1 if _failures > 0 else 0)


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("FAIL: ", msg)


func _test_quick_low_drag_is_tap() -> void:
	_assert(TapDetector.is_tap(80, 5.0), "quick low-drag release should be a tap")


func _test_slow_release_is_not_tap() -> void:
	_assert(not TapDetector.is_tap(400, 5.0), "slow release should not be a tap")


func _test_far_drag_is_not_tap() -> void:
	_assert(not TapDetector.is_tap(80, 50.0), "far-dragged release should not be a tap")


func _test_drag_out_and_snap_back_is_not_tap() -> void:
	# Simulates a finger that dragged out 40px then snapped back near the
	# start before release -- max_drag_px catches this even though the final
	# down-to-up delta would look small.
	_assert(not TapDetector.is_tap(80, 40.0), "a drag-out-and-snap-back should not classify as a tap")


func _test_two_quick_close_taps_is_double_tap() -> void:
	_assert(TapDetector.is_double_tap(1000, Vector2(100, 100), 1150, Vector2(110, 105)), "two quick close taps should be a double-tap")


func _test_single_tap_is_not_double_tap() -> void:
	_assert(not TapDetector.is_double_tap(-1, Vector2.ZERO, 1000, Vector2(100, 100)), "a single tap (no pending tap) should not be a double-tap")


func _test_taps_too_far_apart_in_time_not_double_tap() -> void:
	_assert(not TapDetector.is_double_tap(1000, Vector2(100, 100), 1500, Vector2(100, 100)), "taps more than the window apart should not be a double-tap")


func _test_taps_too_far_apart_in_space_not_double_tap() -> void:
	_assert(not TapDetector.is_double_tap(1000, Vector2(100, 100), 1150, Vector2(300, 300)), "taps too far apart in space should not be a double-tap")


func _test_no_pending_tap_is_not_double_tap() -> void:
	_assert(not TapDetector.is_double_tap(-1, Vector2.ZERO, 500, Vector2(50, 50)), "negative prev_tap_time_ms means no pending tap")
