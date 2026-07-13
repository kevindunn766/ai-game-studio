extends SceneTree

var _failures: int = 0


func _init() -> void:
	_test_monotonic_increase()
	_test_clamped_at_min()
	_test_clamped_at_max()

	if _failures == 0:
		print("ALL PASS")
	else:
		print("%d FAILURE(S)" % _failures)
	quit(1 if _failures > 0 else 0)


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("FAIL: ", msg)


func _test_monotonic_increase() -> void:
	var prev: float = CameraController.target_size_for_scale(1.0)
	for s in [1.5, 2.0, 3.0, 4.0]:
		var cur: float = CameraController.target_size_for_scale(s)
		_assert(cur >= prev, "target size should not decrease as flame_scale grows (%f -> %f)" % [prev, cur])
		prev = cur


func _test_clamped_at_min() -> void:
	var s: float = CameraController.target_size_for_scale(0.0)
	_assert(s == CameraController.MIN_SIZE, "should clamp to MIN_SIZE for tiny/zero scale")


func _test_clamped_at_max() -> void:
	var s: float = CameraController.target_size_for_scale(1000.0)
	_assert(s == CameraController.MAX_SIZE, "should clamp to MAX_SIZE for huge scale")
