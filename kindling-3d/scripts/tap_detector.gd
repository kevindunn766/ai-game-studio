class_name TapDetector extends RefCounted

# Pure, stateless classification helpers -- pulled out of
# kindling_manager.gd's _unhandled_input so double-tap-to-jump logic is
# headlessly testable without synthesizing real InputEventScreenTouch/Drag
# events. See tests/test_double_tap_detection.gd.

const TAP_MAX_DURATION_MS := 220
const TAP_MAX_MOVE_PX := 24.0
const DOUBLE_TAP_WINDOW_MS := 320
const DOUBLE_TAP_MAX_DIST_PX := 60.0


# A "tap" is a short touch that never drags far -- catches a drag-out-and
# -snap-back release, not just a small raw down-to-up delta.
static func is_tap(duration_ms: int, max_drag_px: float) -> bool:
	return duration_ms <= TAP_MAX_DURATION_MS and max_drag_px <= TAP_MAX_MOVE_PX


# Whether the current qualifying tap completes a double-tap against the
# previous one. prev_tap_time_ms < 0 means "no pending tap".
static func is_double_tap(prev_tap_time_ms: int, prev_tap_pos: Vector2, cur_time_ms: int, cur_pos: Vector2) -> bool:
	if prev_tap_time_ms < 0:
		return false
	var dt: int = cur_time_ms - prev_tap_time_ms
	if dt < 0 or dt > DOUBLE_TAP_WINDOW_MS:
		return false
	return cur_pos.distance_to(prev_tap_pos) <= DOUBLE_TAP_MAX_DIST_PX
