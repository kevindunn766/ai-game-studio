extends Node

# Leak/load probe on the streaming itself (no rendering, fast). Drives a DENSE canyon level
# forward for a long flight and samples the generator's live child count. If it plateaus,
# streaming/culling frees what it spawns (no leak); the plateau value is the steady-state
# object load a dense level carries (the thing to optimize if it's high).

const Canyon := preload("res://scripts/level_canyon.gd")

class ShipStub extends Node3D:
	var ship_visual_radius: float = 1.0

var _gen: Node3D
var _ship: ShipStub
var _f: int = 0
var _samples: Array = []

func _ready() -> void:
	_ship = ShipStub.new()
	add_child(_ship)
	_gen = Canyon.new()
	_gen.ship_path = _ship.get_path()
	add_child(_gen)
	# A dense-ish level: 4 feature words at high density (like the probe's canyon).
	_gen.configure({"a": 0.6, "b": 0.6, "c": 0.6, "d": 0.5})
	_gen.configure_enemies({})
	_gen.configure_mines(0.0)
	_gen.configure_hazards({})
	_gen.configure_gravity(true)
	_gen.configure_viewpoint("isometric")
	_gen.configure_structure("canyon")
	_gen.configure_theme({"biome": "Sewer Drainage Tunnels", "floor": Color(0.4, 0.4, 0.45), "walls": Color(0.5, 0.5, 0.55), "accent": Color(0.6, 0.7, 0.5), "features": {}, "dressing": []})
	_gen.configure_state({"density": 1.2})
	_gen.configure_cliff({"enabled": false})
	_gen.start()
	print("=== stream bounded probe (dense canyon) ===")

func _process(_dt: float) -> void:
	_ship.position.z -= 1.2               # fly forward so streaming churns
	_f += 1
	if _f % 200 == 0:
		var n: int = _count(_gen)
		_samples.append(n)
		print("  f=%4d  z=%5.0f  gen children (recursive)=%5d  props=%d" % [_f, -_ship.position.z, n, _prop_count()])
	if _f >= 2000:
		_report()
		get_tree().quit(0)

func _count(n: Node) -> int:
	var c: int = n.get_child_count()
	for ch in n.get_children():
		c += _count(ch)
	return c

func _prop_count() -> int:
	var n: int = 0
	for key in _gen._terrain_tiles.keys():
		n += _gen._terrain_tiles[key][2].size()
	return n

func _report() -> void:
	var first: int = _samples[1] if _samples.size() > 1 else _samples[0]
	var last: int = _samples[_samples.size() - 1]
	var leaked: bool = last > first * 1.4
	print("  -> %s. samples=%s" % [("LEAK (grew >1.4x after warmup)" if leaked else "BOUNDED"), str(_samples)])
	print("=== done ===")
