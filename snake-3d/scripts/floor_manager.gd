class_name FloorManager extends Node3D

@export var snake: Node3D
@export var camera: Camera3D
@export var obstacle_density: float = 0.25
@export var tile_size: float = 0.9
@export var spawn_carve_radius: int = 8
@export var turret_cell_size: int = 7
@export var turret_candidate_radius: int = 2
@export var outline_margin: float = 0.035

const BIOME_IDS := ["neon", "desert", "glacier", "mountain", "crystal_cave", "volcanic"]
var biome: String = "neon"

# Exception to the normal streaming-radius optimization, for the title/menu
# backdrop only: build out a much bigger area so it fills the (much more
# zoomed-out) menu camera's frame, and show all 6 biomes at once as a pie of
# angular wedges around the spawn point rather than just the current level's
# single biome. MENU_SHOWCASE_RADIUS is a best-effort estimate tuned without
# being able to see an actual device screen -- treat it as a starting point,
# not a precisely-derived value, if it needs adjusting after real playtesting.
var menu_showcase_mode: bool = false
const MENU_SHOWCASE_RADIUS := 40

var active_tiles: Dictionary = {}
var obstacle_grid: Dictionary = {}
var destroyed_tiles: Dictionary = {}
var _last_footprint: Rect2i = Rect2i()
var _spawn_cell: Vector3i = Vector3i(0, 0, 0)

var _layout_noise: FastNoiseLite
var _corridor_noise: FastNoiseLite
var _detail_noise: FastNoiseLite
var _turret_positions: Dictionary = {}
var _debris_rng: RandomNumberGenerator

# Shared by every outline instance (unit box + inverted-hull/cull-front trick: an
# enlarged copy of a mesh with only its back faces rendered shows as a thin rim
# around the original's silhouette). The mesh is a plain unit cube reused via
# per-node `scale`, so adding outlines doesn't allocate new geometry per tile.
var _outline_unit_mesh: BoxMesh
var _neon_tile_outline_material: StandardMaterial3D


func _ready() -> void:
	_debris_rng = RandomNumberGenerator.new()
	_debris_rng.randomize()
	_init_noise()
	_init_outline_resources()
	# biome is set by GameManager (level progression) before the first _process()
	# tile spawn — do NOT call _update_tiles() here, or tiles would spawn with
	# whatever the default biome is before GameManager gets a chance to set it.
	var main := get_node_or_null("/root/Main")
	if main:
		if snake == null:
			snake = main.get_node_or_null("Snake")
	if snake:
		var sx := int(round(snake.position.x))
		var sz := int(round(snake.position.z))
		_spawn_cell = Vector3i(sx, 0, sz)


func _init_outline_resources() -> void:
	_outline_unit_mesh = BoxMesh.new()
	_outline_unit_mesh.size = Vector3.ONE

	_neon_tile_outline_material = StandardMaterial3D.new()
	_neon_tile_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_neon_tile_outline_material.cull_mode = BaseMaterial3D.CULL_FRONT
	_neon_tile_outline_material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	_neon_tile_outline_material.emission_enabled = true
	_neon_tile_outline_material.emission = Color(1.0, 1.0, 1.0)
	_neon_tile_outline_material.emission_energy_multiplier = 1.4


func _init_noise() -> void:
	# Large Voronoi cells (~20 tiles wide) give each cell a random value.
	# Negative cells = open BSP rooms, positive cells = wall zones.
	_layout_noise = FastNoiseLite.new()
	_layout_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	_layout_noise.frequency = 0.05
	_layout_noise.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE

	# Corridors: thin winding paths through wall zones where noise crosses zero.
	_corridor_noise = FastNoiseLite.new()
	_corridor_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_corridor_noise.frequency = 0.12

	# Detail: micro-variation within wall zones to avoid solid blocks.
	_detail_noise = FastNoiseLite.new()
	_detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_detail_noise.frequency = 0.25

	reseed()


# Rerolls the layout/corridor/detail noise seeds using _debris_rng (already
# randomized in _ready). Called once at startup and again on every new run
# (reset_to_gameplay) so the map layout differs each playthrough instead of
# reusing the same fixed seeds every time.
func reseed() -> void:
	_layout_noise.seed = _debris_rng.randi()
	_corridor_noise.seed = _debris_rng.randi()
	_detail_noise.seed = _debris_rng.randi()


func _process(_delta: float) -> void:
	_update_tiles()


# Hard reset out of menu showcase mode, back to the normal single-biome
# gameplay view. Just flipping menu_showcase_mode off isn't enough on its own
# -- the wedge-biome tiles already built during the showcase (which radiate
# from the spawn point, so the area right around spawn shows a jumble of
# several biomes meeting at a point) would otherwise just sit there until the
# much-smaller gameplay footprint happens to cull them, which might not even
# cover the spawn area at all. Instead, clear everything immediately and let
# the next _update_tiles() rebuild the (small) gameplay footprint from scratch
# with the run's actual single biome.
func reset_to_gameplay() -> void:
	menu_showcase_mode = false
	for key: Vector3i in active_tiles.keys().duplicate():
		var tile: Node3D = active_tiles[key]
		if is_instance_valid(tile):
			tile.queue_free()
	active_tiles.clear()
	obstacle_grid.clear()
	destroyed_tiles.clear()
	_turret_positions.clear()
	_last_footprint = Rect2i()
	# Fresh seeds each run so the obstacle layout differs every playthrough
	# instead of regenerating the same fixed map every time.
	reseed()


func _get_tile_radius() -> int:
	if menu_showcase_mode:
		return MENU_SHOWCASE_RADIUS
	var seg_count := 0
	if snake:
		for child in snake.get_children():
			if child.name.begins_with("Seg"):
				seg_count += 1
	return clampi(seg_count + 12, 15, 28)


func _get_camera_footprint() -> Rect2i:
	if not snake:
		return Rect2i()
	var seg0 := snake.get_node_or_null("Seg0") as Node3D
	if not seg0:
		return Rect2i()
	var cx := int(round(seg0.global_position.x))
	var cz := int(round(seg0.global_position.z))
	var r := _get_tile_radius()
	return Rect2i(cx - r, cz - r, r * 2 + 1, r * 2 + 1)


func _update_tiles() -> void:
	if snake == null:
		return
	var bounds := _get_camera_footprint()
	if bounds == Rect2i():
		return
	if bounds == _last_footprint and not active_tiles.is_empty():
		return
	_last_footprint = bounds
	# The first fill after a reset builds the whole footprint (~900+ tiles) in one
	# call. Giving every one of those a pop-in scale tween meant hundreds of
	# simultaneous tweens churning right as the transition curtain reveals the
	# scene -- the "loading screen" stutter. Build the bulk fill instantly (same
	# as the menu showcase already does) and only pop-in the handful of tiles
	# that stream in per-step during actual play.
	var bulk_fill := active_tiles.is_empty()
	var needed: Dictionary = {}
	for x in range(bounds.position.x, bounds.position.x + bounds.size.x):
		for z in range(bounds.position.y, bounds.position.y + bounds.size.y):
			var key := Vector3i(x, 0, z)
			needed[key] = true
			if not active_tiles.has(key):
				_spawn_tile(key, not bulk_fill)
	var to_despawn: Array = []
	for key: Vector3i in active_tiles.keys():
		if not needed.has(key):
			to_despawn.append(key)
	for key: Vector3i in to_despawn:
		_despawn_tile(key)


func _spawn_tile(key: Vector3i, animate_popin: bool = true) -> void:
	var effective_biome := _effective_biome_for(key)

	var tile := Node3D.new()
	tile.name = "Tile_%d_%d" % [key.x, key.z]
	tile.position = Vector3(float(key.x), -0.45, float(key.z))
	tile.scale = Vector3.ZERO

	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "FloorMesh"
	var fm := BoxMesh.new()
	fm.size = Vector3(1.02, 0.05, 1.02)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = _biome_floor_color(key, effective_biome)
	fmat.roughness = 0.9
	floor_mesh.material_override = fmat
	floor_mesh.mesh = fm
	tile.add_child(floor_mesh)

	if effective_biome == "neon":
		var tile_outline := MeshInstance3D.new()
		tile_outline.name = "TileOutline"
		tile_outline.mesh = _outline_unit_mesh
		tile_outline.material_override = _neon_tile_outline_material
		tile_outline.scale = Vector3(1.02 + outline_margin * 2.0, 0.05 + outline_margin * 2.0, 1.02 + outline_margin * 2.0)
		tile.add_child(tile_outline)

	if _is_obstacle_key(key):
		obstacle_grid[key] = true
		var obs_h := _get_obstacle_height(key)
		var obstacle := MeshInstance3D.new()
		obstacle.name = "Obstacle"
		var om := BoxMesh.new()
		om.size = Vector3(1.02, obs_h, 1.02)
		var omat := StandardMaterial3D.new()
		omat.albedo_color = _biome_obstacle_color(key, effective_biome)
		omat.roughness = 0.85 if effective_biome == "mountain" else 0.3
		var emission_energy := _biome_obstacle_emission_energy(effective_biome)
		if emission_energy > 0.0:
			omat.emission_enabled = true
			omat.emission = _biome_obstacle_emission(key, effective_biome)
			omat.emission_energy_multiplier = emission_energy
		obstacle.material_override = omat
		obstacle.mesh = om
		# Bottom sits 0.1 above floor surface (tile top at -0.425, so local offset = 0.125).
		obstacle.position = Vector3(0.0, 0.125 + obs_h * 0.5, 0.0)

		var obstacle_outline := MeshInstance3D.new()
		obstacle_outline.name = "ObstacleOutline"
		obstacle_outline.mesh = _outline_unit_mesh
		var outline_mat := StandardMaterial3D.new()
		outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		outline_mat.cull_mode = BaseMaterial3D.CULL_FRONT
		var bright_color := omat.albedo_color.lightened(0.45)
		outline_mat.albedo_color = bright_color
		outline_mat.emission_enabled = true
		outline_mat.emission = bright_color
		outline_mat.emission_energy_multiplier = maxf(emission_energy, 1.2)
		obstacle_outline.material_override = outline_mat
		obstacle_outline.scale = Vector3(1.02 + outline_margin * 2.0, obs_h + outline_margin * 2.0, 1.02 + outline_margin * 2.0)
		obstacle_outline.position = obstacle.position
		tile.add_child(obstacle_outline)

		var has_turret := false
		if obs_h >= tile_size * 1.5 and _is_turret_candidate(key):
			has_turret = true
			var world_turret_y := -0.45 + 0.125 + obs_h + 0.15
			_turret_positions[key] = Vector3(float(key.x), world_turret_y, float(key.z))
			var turret_vis := MeshInstance3D.new()
			turret_vis.name = "Turret"
			var tm := BoxMesh.new()
			tm.size = Vector3(0.28, 0.28, 0.28)
			var tmat := StandardMaterial3D.new()
			tmat.albedo_color = Color(0.9, 0.1, 0.1, 1.0)
			tmat.emission_enabled = true
			tmat.emission = Color(1.0, 0.0, 0.0)
			tmat.emission_energy_multiplier = 3.0
			turret_vis.material_override = tmat
			turret_vis.mesh = tm
			turret_vis.position = Vector3(0.0, 0.125 + obs_h + 0.15, 0.0)
			tile.add_child(turret_vis)
		tile.add_child(obstacle)
		_maybe_add_tree(tile, key, obs_h, has_turret, effective_biome)

	add_child(tile)
	active_tiles[key] = tile
	if menu_showcase_mode or not animate_popin:
		# Skip the per-tile pop-in tween -- both the menu showcase and the initial
		# gameplay bulk fill build hundreds/thousands of tiles in one go, and a
		# burst of that many simultaneous tweens is a real performance hit (the
		# transition-reveal stutter) for no visible benefit at that scale.
		tile.scale = Vector3.ONE
	else:
		var spawn_tw := create_tween()
		spawn_tw.tween_property(tile, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _effective_biome_for(key: Vector3i) -> String:
	if not menu_showcase_mode:
		return biome
	# Split the showcase area into BIOME_IDS.size() angular wedges radiating
	# from the spawn point, so every biome is visible at once as a pie chart
	# rather than the single active level's biome.
	var angle := atan2(float(key.z), float(key.x))
	var normalized := (angle + PI) / TAU
	var idx := int(normalized * BIOME_IDS.size()) % BIOME_IDS.size()
	return BIOME_IDS[idx]


func _biome_floor_color(key: Vector3i, effective_biome: String) -> Color:
	match effective_biome:
		"mountain":
			var proximity := _mountain_proximity(key)
			var far_color := Color(0.62, 0.58, 0.28, 1.0)
			var near_color := Color(0.12, 0.4, 0.16, 1.0)
			return far_color.lerp(near_color, proximity)
		"desert":
			return Color(0.75, 0.62, 0.35, 1.0)
		"glacier":
			return Color(0.75, 0.85, 0.95, 1.0)
		"crystal_cave":
			return Color(0.08, 0.05, 0.12, 1.0)
		"volcanic":
			return Color(0.1, 0.06, 0.07, 1.0)
		_:
			return Color(0.15, 0.15, 0.18, 1.0)


func _biome_obstacle_color(key: Vector3i, effective_biome: String) -> Color:
	var h := float(abs(hash(Vector3i(key.x * 7, 2, key.z * 13))) % 1000) / 1000.0
	match effective_biome:
		"mountain":
			var shade := 0.32 + h * 0.2
			return Color(shade, shade * 0.92, shade * 0.82, 1.0)
		"desert":
			return Color(0.55 + h * 0.15, 0.28 + h * 0.1, 0.15 + h * 0.05, 1.0)
		"glacier":
			return Color(0.75 + h * 0.15, 0.85 + h * 0.1, 0.95, 1.0)
		"crystal_cave":
			return Color(0.5 + h * 0.3, 0.1 + h * 0.2, 0.7 + h * 0.3, 1.0)
		"volcanic":
			var shade := 0.08 + h * 0.05
			return Color(shade, shade * 0.85, shade * 0.85, 1.0)
		_:
			return Color.from_hsv(h, 0.3, 0.85, 1.0)


func _biome_obstacle_emission(key: Vector3i, effective_biome: String) -> Color:
	var h := float(abs(hash(Vector3i(key.x * 11, 3, key.z * 17))) % 1000) / 1000.0
	match effective_biome:
		"crystal_cave":
			return Color(0.5 + h * 0.4, 0.15, 0.85, 1.0)
		"volcanic":
			return Color(0.95, 0.35 * h, 0.05, 1.0)
		_:
			return Color(0, 0, 0, 1)


func _biome_obstacle_emission_energy(effective_biome: String) -> float:
	match effective_biome:
		"crystal_cave", "volcanic":
			return 1.6
		_:
			return 0.0


func _mountain_proximity(key: Vector3i) -> float:
	var radius := 3
	var count := 0
	var total := 0
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			if dx == 0 and dz == 0:
				continue
			total += 1
			if _is_obstacle_key(Vector3i(key.x + dx, 0, key.z + dz)):
				count += 1
	return clampf(float(count) / (float(total) * 0.4), 0.0, 1.0)


func _maybe_add_tree(tile: Node3D, key: Vector3i, obs_h: float, has_turret: bool, effective_biome: String) -> void:
	if effective_biome != "mountain" or has_turret:
		return
	var h := float(abs(hash(Vector3i(key.x * 13, 9, key.z * 31))) % 1000) / 1000.0
	if h > 0.18:
		return

	var tree := Node3D.new()
	tree.name = "Tree"

	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.05
	tm.bottom_radius = 0.07
	tm.height = 0.22
	trunk.mesh = tm
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.35, 0.22, 0.12, 1.0)
	tmat.roughness = 0.9
	trunk.material_override = tmat
	tree.add_child(trunk)

	var canopy := MeshInstance3D.new()
	var cm := SphereMesh.new()
	cm.radius = 0.16
	cm.height = 0.3
	canopy.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.1, 0.4, 0.14, 1.0)
	cmat.roughness = 0.8
	canopy.material_override = cmat
	canopy.position = Vector3(0.0, 0.18, 0.0)
	tree.add_child(canopy)

	tree.position = Vector3(0.0, 0.125 + obs_h + 0.11, 0.0)
	tile.add_child(tree)


func _get_obstacle_height(key: Vector3i) -> float:
	var neighbor_count := 0
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			if dx == 0 and dz == 0:
				continue
			if _is_obstacle_key(Vector3i(key.x + dx, 0, key.z + dz)):
				neighbor_count += 1
	var min_h := tile_size * 0.6
	var max_h := tile_size * 3.0
	return min_h + (float(neighbor_count) / 8.0) * (max_h - min_h)


func _turret_candidate_for_cell(cell_x: int, cell_z: int) -> Vector2i:
	# Deterministic pseudo-random point per cell, kept away from cell edges so
	# neighboring cells' candidates can never land closer than the margin band —
	# an approximate Poisson-disk minimum-spacing guarantee without needing to
	# track already-placed turrets (which wouldn't be stable in an infinite,
	# streamed world where tiles spawn/despawn as the camera moves).
	var margin := int(turret_cell_size * 0.3)
	var span := maxi(1, turret_cell_size - margin * 2)
	var hx: int = hash(Vector3i(cell_x * 928371, 5, cell_z * 123457))
	var hz: int = hash(Vector3i(cell_z * 928371, 7, cell_x * 654321))
	var lx: int = margin + (abs(hx) % span)
	var lz: int = margin + (abs(hz) % span)
	return Vector2i(cell_x * turret_cell_size + lx, cell_z * turret_cell_size + lz)


func _is_turret_candidate(key: Vector3i) -> bool:
	var cell_x := floori(float(key.x) / turret_cell_size)
	var cell_z := floori(float(key.z) / turret_cell_size)
	var candidate := _turret_candidate_for_cell(cell_x, cell_z)
	var dx := absi(candidate.x - key.x)
	var dz := absi(candidate.y - key.z)
	return dx <= turret_candidate_radius and dz <= turret_candidate_radius


func _is_obstacle_key(key: Vector3i) -> bool:
	if destroyed_tiles.has(key):
		return false
	if _in_carve_zone(key):
		return false
	return _raw_obstacle(key.x, key.z)


func destroy_obstacle_at_grid(gx: int, gz: int) -> void:
	var key := Vector3i(gx, 0, gz)
	destroyed_tiles[key] = true
	obstacle_grid.erase(key)
	_turret_positions.erase(key)
	var tile: Node3D = active_tiles.get(key, null)
	if not tile:
		return
	var obs := tile.get_node_or_null("Obstacle") as MeshInstance3D
	if obs:
		var debris_color := Color(0.6, 0.6, 0.65, 1.0)
		if obs.material_override is StandardMaterial3D:
			debris_color = (obs.material_override as StandardMaterial3D).albedo_color
		_spawn_destruction_effect(obs.global_position, debris_color)
		tile.remove_child(obs)
		obs.queue_free()
		Chiptune.play_sfx("obstacle_destroy")
	var turret := tile.get_node_or_null("Turret")
	if turret:
		tile.remove_child(turret)
		turret.queue_free()
	var outline := tile.get_node_or_null("ObstacleOutline")
	if outline:
		tile.remove_child(outline)
		outline.queue_free()


func _spawn_destruction_effect(at: Vector3, base_color: Color) -> void:
	for i in range(6):
		var chunk := MeshInstance3D.new()
		var cm := BoxMesh.new()
		var s := _debris_rng.randf_range(0.12, 0.24)
		cm.size = Vector3(s, s, s)
		chunk.mesh = cm

		var mat := StandardMaterial3D.new()
		mat.albedo_color = base_color
		mat.emission_enabled = true
		mat.emission = base_color
		mat.emission_energy_multiplier = 2.5
		chunk.material_override = mat

		chunk.global_position = at
		add_child(chunk)

		var dir := Vector3(
			_debris_rng.randf_range(-1.0, 1.0),
			_debris_rng.randf_range(0.3, 1.0),
			_debris_rng.randf_range(-1.0, 1.0)
		).normalized()
		var target := at + dir * _debris_rng.randf_range(0.6, 1.3)

		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(chunk, "global_position", target, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(chunk, "scale", Vector3.ZERO, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_property(chunk, "rotation_degrees", Vector3(_debris_rng.randf_range(90, 360), _debris_rng.randf_range(90, 360), 0), 0.4)

		get_tree().create_timer(0.45).timeout.connect(chunk.queue_free)


func _in_carve_zone(key: Vector3i) -> bool:
	var dx := key.x - _spawn_cell.x
	var dz := key.z - _spawn_cell.z
	return dx * dx + dz * dz <= spawn_carve_radius * spawn_carve_radius


func _raw_obstacle(gx: int, gz: int) -> bool:
	# BSP layer: negative Voronoi cells are open rooms, positive are wall zones.
	var cell_val := _layout_noise.get_noise_2d(float(gx), float(gz))
	if cell_val < 0.0:
		return false
	# Corridor layer: winding paths through wall zones where corridor noise ≈ 0.
	var corridor_val := _corridor_noise.get_noise_2d(float(gx), float(gz))
	if absf(corridor_val) < 0.1:
		return false
	# Detail layer: ~50% of remaining wall tiles become obstacles.
	var detail_val := _detail_noise.get_noise_2d(float(gx), float(gz))
	return detail_val > 0.0


func _despawn_tile(key: Vector3i) -> void:
	var tile: Node3D = active_tiles.get(key, null)
	if tile:
		var tw := create_tween()
		tw.tween_property(tile, "scale", Vector3.ZERO, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_callback(tile.queue_free)
	active_tiles.erase(key)
	obstacle_grid.erase(key)
	_turret_positions.erase(key)


func is_tile_obstacle_at(world_pos: Vector3) -> bool:
	return _is_obstacle_key(Vector3i(int(round(world_pos.x)), 0, int(round(world_pos.z))))


func is_tile_obstacle_at_grid(gx: int, gz: int) -> bool:
	return _is_obstacle_key(Vector3i(gx, 0, gz))


func get_turret_positions() -> Array:
	return _turret_positions.values()
