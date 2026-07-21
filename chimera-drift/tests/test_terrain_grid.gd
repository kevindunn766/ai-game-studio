extends Node

# Headless verification of the endless 2D terrain-tile streaming grid (2026-07-19).
# Drives a stub ship forward AND laterally through Surface / Canyon / Pillared and
# asserts the ground tiles: (1) surround the ship in every direction, (2) follow the
# ship's lateral path (new tiles appear on the side moved toward, old ones free),
# (3) stay bounded in count, and (4) keep correct face winding (normals point up).
#
# Run as a MAIN SCENE (so autoloads init first):
#   godot --headless res://tests/test_terrain_grid.tscn --quit-after 3

const Surface := preload("res://scripts/level_surface.gd")
const Canyon := preload("res://scripts/level_canyon.gd")
const Pillared := preload("res://scripts/level_pillared.gd")

class ShipStub extends Node3D:
	var ship_visual_radius: float = 1.0

var _fail: int = 0

func _ok(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: "), msg)
	if not cond:
		_fail += 1

func _ready() -> void:
	print("=== terrain grid streaming test ===")
	for entry in [["Surface", Surface], ["Canyon", Canyon], ["Pillared", Pillared]]:
		_run_case(entry[0], entry[1])
	print("=== %s ===" % ("ALL PASS" if _fail == 0 else "%d FAILURES" % _fail))
	get_tree().quit(_fail)

func _run_case(label: String, script: GDScript) -> void:
	print("-- ", label, " --")
	var ship := ShipStub.new()
	add_child(ship)
	var gen: Node3D = script.new()
	gen.ship_path = ship.get_path()   # @onready `ship` resolves from this on tree entry
	add_child(gen)
	# Minimal config: no props/enemies/hazards so only terrain streams.
	gen.configure({"rocks": 0.4})        # a feature word so props actually scatter
	gen.configure_enemies({})
	gen.configure_mines(0.0)
	gen.configure_hazards({})
	gen.configure_gravity(false)
	gen.configure_viewpoint("topdown")   # X free -> the case that exposed the old side edge
	gen.configure_structure("hills")
	gen.configure_theme({"floor": Color(0.4, 0.4, 0.45), "walls": Color(0.5, 0.5, 0.55), "accent": Color(0.7, 0.6, 0.4), "features": {"rocks": {"color": Color(0.5, 0.5, 0.5), "shape": "rock"}}, "dressing": []})
	gen.configure_state({})
	gen.configure_cliff({"enabled": false})
	gen.start()

	var ts: float = gen.terrain_tile_size
	var r: float = gen._ahead_dist

	# (1) tiles surround the ship in ALL directions at spawn (x=0,z=0).
	_ok(_has_tile_near(gen, Vector3(r * 0.7, 0, 0)), "tile exists to the +X of ship")
	_ok(_has_tile_near(gen, Vector3(-r * 0.7, 0, 0)), "tile exists to the -X of ship")
	_ok(_has_tile_near(gen, Vector3(0, 0, -r * 0.7)), "tile exists ahead (-Z) of ship")
	_ok(_count_beyond(gen, Vector3.ZERO, r + ts * 2.0) == 0, "no tile is built beyond the window radius")

	# (4) winding: sample one tile's mesh, average normal must point up.
	_ok(_avg_normal_up(gen), "terrain faces wind correctly (normals point up, not inside-out)")

	# (5) collision LOD: only the ring around the ship is lethal; distant tiles are visual-only.
	var ring: int = gen.terrain_collision_ring
	var max_bodies: int = (2 * ring + 1) * (2 * ring + 1)
	_ok(_tile_body(gen, Vector3.ZERO) != null, "the tile under the ship has a lethal body")
	_ok(_tile_body(gen, Vector3(r * 0.7, 0, 0)) == null, "a distant tile is visual-only (no wasted collision)")
	_ok(_count_bodies(gen) <= max_bodies, "collision bodies bounded to the ring (<= %d)" % max_bodies)

	# (2) drive forward + strafe far right; the ground must follow.
	var before: int = gen._terrain_tiles.size()
	for step in range(40):
		ship.position += Vector3(4.0, 0.0, -5.0)   # strafe +X while advancing -Z
		gen._update_terrain_grid(0)
	_ok(_has_tile_near(gen, ship.position + Vector3(r * 0.7, 0, 0)), "after strafing +X, ground still extends +X of ship")
	_ok(_has_tile_near(gen, ship.position + Vector3(-r * 0.7, 0, 0)), "after strafing +X, ground still extends -X of ship")
	_ok(_has_tile_near(gen, ship.position + Vector3(0, 0, -r * 0.7)), "after advancing, ground still extends ahead")
	# far-behind / far-left tiles from the START must have been freed.
	_ok(_count_beyond(gen, ship.position, r + ts * 2.0) == 0, "stale tiles freed once out of the window (memory bounded)")
	# collision followed the ship: still lethal under it, still bounded after moving.
	_ok(_tile_body(gen, ship.position) != null, "after moving, the tile under the ship is lethal again")
	_ok(_count_bodies(gen) <= max_bodies, "collision bodies still bounded after moving (<= %d)" % max_bodies)
	print("    lethal bodies: ", _count_bodies(gen), " of ", gen._terrain_tiles.size(), " tiles")
	# (3) count stays bounded (not accumulating).
	print("    tiles now: ", gen._terrain_tiles.size(), " (was ", before, ")")
	_ok(gen._terrain_tiles.size() < 400, "tile count bounded")

	# (6) THE FIX: scenery (props/structures) fills the window in ALL directions, not a
	# narrow forward lane -- so it doesn't "end" when you steer off the track. Objects
	# must exist far to the side of the ship (well past the old lane half-width).
	var scenery: int = _count_scatter(gen)
	var spread: float = _scatter_spread_x(gen)
	print("    scenery objects: ", scenery, "  max |x-ship.x|: ", "%.1f" % spread, "  (lane half-width was ", "%.1f" % gen._half_width, ")")
	_ok(scenery > 0, "scenery objects exist")
	_ok(spread > gen._half_width * 2.0, "scenery fills far beyond the old lane band (no lateral object edge)")
	_ok(scenery < 4000, "scenery object count stays bounded")

	# (7) camera-distance cull (deep views): with a third-person camera, distant scenery
	# scales down + hides while near scenery stays full-size.
	gen.current_viewpoint = "thirdperson"
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = ship.position + Vector3(0.0, 4.0, 8.0)   # behind + above, like the chase cam
	cam.current = true
	gen._apply_camera_cull()
	var ce: float = gen._ahead_dist * 0.82
	var far_hidden: bool = true
	var near_full: bool = true
	for key in gen._terrain_tiles.keys():
		for e in gen._terrain_tiles[key][2]:
			if not is_instance_valid(e[0]):
				continue
			var d: float = e[0].global_position.distance_to(cam.global_position)
			if d > ce + 8.0 and e[0].visible:
				far_hidden = false           # something far is still drawing
			if d < gen._ahead_dist * 0.4 and not e[0].visible:
				near_full = false            # something near got wrongly culled
	_ok(far_hidden, "distant scenery is culled (hidden) in third-person")
	_ok(near_full, "near scenery stays visible in third-person")
	cam.queue_free()

	gen.queue_free()
	ship.queue_free()

func _has_tile_near(gen: Node3D, world: Vector3) -> bool:
	var ts: float = gen.terrain_tile_size
	var ix: int = int(floor(world.x / ts))
	var iz: int = int(floor(world.z / ts))
	return gen._terrain_tiles.has("%d,%d" % [ix, iz])

# Count tiles whose centre is farther than `limit` (either axis) from `center`.
func _count_beyond(gen: Node3D, center: Vector3, limit: float) -> int:
	var ts: float = gen.terrain_tile_size
	var n: int = 0
	for key in gen._terrain_tiles.keys():
		var parts: PackedStringArray = key.split(",")
		var cx: float = (int(parts[0]) + 0.5) * ts
		var cz: float = (int(parts[1]) + 0.5) * ts
		if absf(cx - center.x) > limit or absf(cz - center.z) > limit:
			n += 1
	return n

func _tile_body(gen: Node3D, world: Vector3):
	var ts: float = gen.terrain_tile_size
	var key: String = "%d,%d" % [int(floor(world.x / ts)), int(floor(world.z / ts))]
	if not gen._terrain_tiles.has(key):
		return null
	return gen._terrain_tiles[key][1]

func _count_bodies(gen: Node3D) -> int:
	var n: int = 0
	for key in gen._terrain_tiles.keys():
		if gen._terrain_tiles[key][1] != null:
			n += 1
	return n

# Total scenery objects (props + structures) across all tiles.
func _count_scatter(gen: Node3D) -> int:
	var n: int = 0
	for key in gen._terrain_tiles.keys():
		n += gen._terrain_tiles[key][2].size()
	return n

# Farthest lateral distance of any scenery object from the ship's x.
func _scatter_spread_x(gen: Node3D) -> float:
	var m: float = 0.0
	for key in gen._terrain_tiles.keys():
		for e in gen._terrain_tiles[key][2]:
			if is_instance_valid(e[0]):
				m = maxf(m, absf(e[0].position.x - gen.ship.position.x))
	return m

func _avg_normal_up(gen: Node3D) -> bool:
	if gen._terrain_tiles.is_empty():
		return false
	var any_key = gen._terrain_tiles.keys()[0]
	var mi: MeshInstance3D = gen._terrain_tiles[any_key][0]
	var arrays: Array = mi.mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var sum := Vector3.ZERO
	for nrm in normals:
		sum += nrm
	return sum.normalized().y > 0.9
