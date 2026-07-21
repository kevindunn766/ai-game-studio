extends Node

# Diagnoses the pickup camera jerk: runs the real game, samples the active camera's
# per-frame movement, triggers grow_ship() at a known frame, and prints the camera move
# spanning that frame vs the baseline. A single-frame spike >> baseline == an un-smoothed jerk.

var _main: Node
var _ship: Node
var _f: int = 0
var _prev := Vector3.ZERO
var _deltas: Array = []
const GROW_AT := 70

func _ready() -> void:
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	_ship = _main.get_node("Ship")

func _process(_dt: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	_ship.set("alive", true)
	var p: Vector3 = cam.global_position
	if _f > 0:
		_deltas.append((p - _prev).length())
	_prev = p
	_f += 1
	if _f == GROW_AT:
		_ship.call("grow_ship", "cosmetic", Color.WHITE)
	if _f >= GROW_AT + 18:
		_report()
		get_tree().quit(0)

func _report() -> void:
	var gi: int = GROW_AT - 1                       # delta[gi] spans the grow frame
	var base: float = 0.0
	var n: int = 0
	for i in range(15, gi - 2):
		base += _deltas[i]
		n += 1
	base = base / maxi(1, n)
	print("=== camera jerk probe ===")
	print("baseline per-frame camera move = %.4f" % base)
	for i in range(gi - 2, mini(_deltas.size(), gi + 14)):
		print("  d[%d] = %.4f%s" % [i, _deltas[i], ("   <-- grow_ship here" if i == gi else "")])
	# Peak per-frame move over the ease window vs baseline: a constant-rate glide stays ~1x.
	var peak: float = 0.0
	for i in range(gi, mini(_deltas.size(), gi + 12)):
		peak = maxf(peak, _deltas[i])
	var ratio: float = peak / maxf(0.0001, base)
	var ok: bool = ratio < 2.0
	print("peak/baseline over the ease window = %.1fx  -> %s" % [ratio, ("PASS (smooth glide)" if ok else "FAIL (jerk)")])
	print("=== %s ===" % ("ALL PASS" if ok else "FAILURE"))
	get_tree().quit(0 if ok else 1)
