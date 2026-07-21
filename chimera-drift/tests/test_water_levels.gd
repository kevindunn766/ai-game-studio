extends Node

# Verifies the water-level logic (2026-07-19):
#  - top-down OCEAN surface -> dead-flat terrain + the ocean water shader, structures off;
#    non-ocean biomes and non-topdown ocean keep the normal heightmap.
#  - UNDERWATER open-volume detection (director) toggles the underwater treatment; other
#    open-volume biomes / other shape families don't.

const Surface := preload("res://scripts/level_surface.gd")
const Canyon := preload("res://scripts/level_canyon.gd")
const LevelDirector := preload("res://scripts/level_director.gd")
const OCEAN_SHADER := preload("res://shaders/ocean.gdshader")

class ShipStub extends Node3D:
	var ship_visual_radius: float = 1.0

var _fail: int = 0

func _ok(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: "), msg)
	if not cond:
		_fail += 1

func _make_surface(biome: String, viewpoint: String, structure: String) -> Node3D:
	var ship := ShipStub.new()
	add_child(ship)
	var gen: Node3D = Surface.new()
	gen.ship_path = ship.get_path()
	add_child(gen)
	gen.configure({})                     # no feature words -> only structures could scatter
	gen.configure_enemies({})
	gen.configure_mines(0.0)
	gen.configure_hazards({})
	gen.configure_gravity(false)
	gen.configure_viewpoint(viewpoint)
	gen.configure_structure(structure)
	gen.configure_theme({"biome": biome, "floor": Color(0.05, 0.18, 0.3), "walls": Color(0.4, 0.5, 0.6), "accent": Color(0.5, 0.8, 0.95), "features": {}, "dressing": []})
	gen.configure_state({})
	gen.configure_cliff({"enabled": false})
	gen.start()
	return gen

func _ready() -> void:
	print("=== water levels test ===")

	# --- Ocean, top-down: flat + water shader + no structures ---
	var ocean := _make_surface("Ocean Surface", "topdown", "mountains")
	_ok(ocean._ocean_flat, "top-down Ocean Surface flags _ocean_flat")
	_ok(ocean._terrain_height(7.0, -50.0) == 0.0, "ocean terrain height is dead flat (0)")
	var mat = _any_tile_material(ocean)
	_ok(mat is ShaderMaterial and (mat as ShaderMaterial).shader == OCEAN_SHADER, "ocean tiles use the water shader")
	_ok(_scatter_total(ocean) == 0, "no structure features on the open ocean")

	# --- Ocean but NOT top-down: keeps the heightmap ---
	var ocean_3p := _make_surface("Ocean Surface", "thirdperson", "flat")
	_ok(not ocean_3p._ocean_flat, "ocean in a non-topdown view keeps the normal terrain")

	# --- Non-ocean, top-down: normal heightmap (not flat) ---
	var desert := _make_surface("Meteor-Cratered Plains", "topdown", "mountains")
	_ok(not desert._ocean_flat, "a non-ocean top-down biome is not flagged ocean")
	_ok(_any_tile_material(desert) is StandardMaterial3D, "non-ocean tiles use the normal terrain material")

	# --- Underwater detection (director, pure method -- not added to tree). Submerged biomes
	# are Surface/Canyon/Corridor in the CSV, so detection is by biome word, not shape family. ---
	var dir = LevelDirector.new()
	_ok(dir._is_underwater({"biome": "Underwater"}), "Underwater biome -> underwater")
	_ok(dir._is_underwater({"biome": "Kelp Forest Open Water"}), "Kelp forest -> underwater")
	_ok(dir._is_underwater({"biome": "Coral Reef Tunnels"}), "Coral reef tunnels -> underwater")
	_ok(dir._is_underwater({"biome": "Sunken Temple Ruins"}), "Sunken temple -> underwater")
	_ok(not dir._is_underwater({"biome": "Ocean Surface"}), "Ocean SURFACE (above water) is NOT underwater")
	_ok(not dir._is_underwater({"biome": "Asteroid Belt"}), "a dry biome is NOT underwater")
	dir.free()

	# --- forced preview rolls (the hotkey path) land on the exact level ---
	var lv: Dictionary = LevelSeed.roll_new_level(null, "Ocean Surface", "topdown")
	_ok(lv.get("biome") == "Ocean Surface" and lv.get("viewpoint") == "topdown", "force -> Ocean Surface top-down")
	var uw: Dictionary = LevelSeed.roll_new_level(null, "Underwater", "")
	_ok(uw.get("biome") == "Underwater", "force -> Underwater biome")

	# --- canyon cliffside: iso/3-4 drop the gorge walls (flat floor + cliff), others keep them ---
	var can_iso := _make_canyon("isometric")
	_ok(can_iso._cliffside and _relief(can_iso) < 8.0, "iso canyon is a cliff landscape (gorge walls dropped, floor flat)")
	var can_3p := _make_canyon("thirdperson")
	_ok(not can_3p._cliffside and _relief(can_3p) > 12.0, "third-person canyon keeps its gorge walls")

	print("=== %s ===" % ("ALL PASS" if _fail == 0 else "%d FAILURES" % _fail))
	get_tree().quit(_fail)

func _make_canyon(viewpoint: String) -> Node3D:
	var ship := ShipStub.new()
	add_child(ship)
	var gen: Node3D = Canyon.new()
	gen.ship_path = ship.get_path()
	add_child(gen)
	gen.configure({})
	gen.configure_enemies({})
	gen.configure_mines(0.0)
	gen.configure_hazards({})
	gen.configure_gravity(true)
	gen.configure_viewpoint(viewpoint)
	gen.configure_structure("canyon")
	gen.configure_theme({"biome": "Sunken Temple Ruins", "floor": Color(0.4, 0.4, 0.45), "walls": Color(0.5, 0.5, 0.55), "accent": Color(0.6, 0.7, 0.5), "features": {}, "dressing": []})
	gen.configure_state({})
	gen.configure_cliff({"enabled": true})
	gen.start()
	return gen

# Max vertical relief of the terrain across a lateral sweep at a fixed depth: small = flat
# floor (cliffside), large = gorge walls present.
func _relief(gen: Node3D) -> float:
	var lo: float = 1e9
	var hi: float = -1e9
	for i in range(60):
		var x: float = -80.0 + 160.0 * float(i) / 59.0
		var h: float = gen._terrain_height(x, -80.0)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	return hi - lo

func _any_tile_material(gen: Node3D):
	for key in gen._terrain_tiles.keys():
		return gen._terrain_tiles[key][0].material_override
	return null

func _scatter_total(gen: Node3D) -> int:
	var n: int = 0
	for key in gen._terrain_tiles.keys():
		n += gen._terrain_tiles[key][2].size()
	return n
