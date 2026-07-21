extends Node

# Verifies the soft combat-zone leash MATH (mirrors ship._zone_axis_x + _handle_steering
# exactly): holding a direction gets soft-capped to the follow speed and never runs away,
# the alarm (leaving) raises past the buffer, and releasing returns the ship inside so the
# alarm clears. (The wiring -- reset/director/HUD -- is covered by the clean boot.)

const HALF := 14.0
const FOLLOW := 4.0
const SPRING := 4.0
const STEER := 6.0
const ACCEL := 9.0
const DT := 1.0 / 60.0

var pos := 0.0
var vel := 0.0
var center := 0.0

func _step(input: float) -> bool:
	vel = move_toward(vel, input * STEER, ACCEL * DT)   # _handle_steering
	pos += vel * DT                                     # integrate position
	var off := pos - center                             # --- mirror ship._zone_axis_x ---
	var leaving := false
	if absf(off) > HALF:
		leaving = true
		if signf(vel) == signf(off) and absf(vel) > FOLLOW:
			vel = signf(off) * FOLLOW
		vel -= signf(off) * SPRING * (absf(off) - HALF) * DT
	center = move_toward(center, pos, FOLLOW * DT)
	return leaving

var _fail := 0
func _ok(c: bool, m: String) -> void:
	print(("  PASS: " if c else "  FAIL: "), m)
	if not c: _fail += 1

func _ready() -> void:
	print("=== combat zone leash test ===")

	# Hold RIGHT for 10s.
	var max_off := 0.0
	var raised := false
	var pos_at_start_of_last_sec := 0.0
	for f in range(600):
		if f == 540:
			pos_at_start_of_last_sec = pos
		var lv := _step(1.0)
		raised = raised or lv
		max_off = maxf(max_off, absf(pos - center))
	var speed_while_leashed := (pos - pos_at_start_of_last_sec) / 1.0   # units/sec over the last second

	_ok(raised, "alarm raises when pushing past the buffer")
	_ok(max_off < HALF * 1.5, "ship never runs far past the buffer (bounded ~zone_half, was %.1f)" % max_off)
	_ok(absf(speed_while_leashed - FOLLOW) < 1.2, "sustained outward speed capped ~follow_speed (%.1f vs %.1f), not steer_speed %.1f" % [speed_while_leashed, FOLLOW, STEER])

	# Release for 5s -> should settle back inside and clear.
	var cleared := false
	for f in range(300):
		var lv := _step(0.0)
		if not lv:
			cleared = true
	_ok(cleared, "releasing input returns the ship inside -> alarm clears")

	print("=== %s ===" % ("ALL PASS" if _fail == 0 else "%d FAILURES" % _fail))
	get_tree().quit(_fail)
