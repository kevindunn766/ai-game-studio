class_name FloorManager extends Node3D

@export var snake: Node3D
@export var camera: Camera3D
@export var obstacle_density: float = 0.38
@export var ca_iterations: int = 4
@export var tile_size: float = 0.9
@export var spawn_carve_radius: int = 4

var rng: RandomNumberGenerator
var active_tiles: Dictionary = {}
var obstacles_parent: Node3D
var obstacle_grid: Dictionary = {}
var _last_footprint: Rect2i = Rect2i()
var _spawn_cell: Vector3i = Vector3i(0, 0, 0)


func _ready() -> void:
	rng = RandomNumberGenerator.new()
	rng.randomize()

	obstacles_parent = Node3D.new()
	obstacles_parent.name = "Obstacles"
	add_child(obstacles_parent)

	var main := get_node_or_null("/root/Main")
	if main:
		if snake == null:
			snake = main.get_node_or_null("Snake")
		if camera == null:
			camera = main.get_node_or_null("Snake/Seg0/CameraCranePivot/SpringArm3D/Camera3D")

	if snake:
		var sx := int(round(snake.position.x / tile_size))
		var sz := int(round(snake.position.z / tile_size))
		_spawn_cell = Vector3i(sx, 0, sz)
	else:
		_spawn_cell = Vector3i(0, 0, 0)

	_update_tiles()


func _process(_delta: float) -> void:
	_update_tiles()


func _get_camera_footprint() -> Rect2i:
	if not camera or not is_inside_tree():
		return Rect2i()

	var aspect: float = 1.777
	var viewport = get_viewport()
	if viewport and viewport.size.x > 0:
		aspect = viewport.size.x / viewport.size.y

	var height: float = max(camera.global_position.y, 0.01)
	var half_fov: float = deg_to_rad(camera.fov / 2.0)
	var ground_dist: float = height / tan(half_fov)
	var forward: Vector3 = -camera.global_transform.basis.z
	var near_center: Vector3 = camera.global_position + forward * ground_dist

	var half_h: float = ground_dist * tan(half_fov) + 2.0
	var half_w: float = half_h * aspect

	var margin := 2
	var min_x = int(floor((near_center.x - half_w) / tile_size)) - margin
	var max_x = int(ceil((near_center.x + half_w) / tile_size)) + margin
	var min_z = int(floor((near_center.z - half_h) / tile_size)) - margin
	var max_z = int(ceil((near_center.z + half_h) / tile_size)) + margin

	return Rect2i(min_x, min_z, max_x - min_x + 1, max_z - min_z + 1)


func _update_tiles() -> void:
	if snake == null:
		return

	var footprint := _get_camera_footprint()
	if footprint == Rect2i():
		return

	var bounds: Rect2i = footprint
	if bounds != _last_footprint:
		_last_footprint = bounds
		_refresh_obstacles(bounds)

	var needed: Dictionary = {}
	for x in range(bounds.position.x, bounds.position.x + bounds.size.x):
		for z in range(bounds.position.y, bounds.position.y + bounds.size.y):
			var key: Vector3i = Vector3i(x, 0, z)
			needed[key] = true
			if not active_tiles.has(key):
				_spawn_tile(key)

	var to_despawn: Array = []
	for key: Vector3i in active_tiles.keys():
		if not needed.has(key):
			to_despawn.append(key)
	for key: Vector3i in to_despawn:
		_despawn_tile(key)


func _in_bounds(bounds: Rect2i, x: int, z: int) -> bool:
	return x >= bounds.position.x and x < bounds.position.x + bounds.size.x and z >= bounds.position.y and z < bounds.position.y + bounds.size.y


func _refresh_obstacles(bounds: Rect2i) -> void:
	for c in obstacles_parent.get_children():
		obstacles_parent.remove_child(c)
		c.queue_free()
	obstacle_grid.clear()

	var grid_min_x := bounds.position.x
	var grid_min_z := bounds.position.y
	var w := bounds.size.x
	var h := bounds.size.y

	var grid: Array = []
	var idx := 0
	for x in range(grid_min_x, grid_min_x + w):
		grid.append([])
		for z in range(grid_min_z, grid_min_z + h):
			var noise := float(hash(Vector3i(x, 0, z)) % 1000) / 1000.0
			grid[idx].append(noise < obstacle_density)
		idx += 1

	var wall_density := obstacle_density * 6.0
	for _iter in range(ca_iterations):
		var next: Array = grid.duplicate(true)
		for x in range(w):
			for z in range(h):
				var neighbors := 0
				if x > 0 and grid[x - 1][z]:
					neighbors += 1
				if x < w - 1 and grid[x + 1][z]:
					neighbors += 1
				if z > 0 and grid[x][z - 1]:
					neighbors += 1
				if z < h - 1 and grid[x][z + 1]:
					neighbors += 1
				if x > 0 and z > 0 and grid[x - 1][z - 1]:
					neighbors += 1
				if x < w - 1 and z > 0 and grid[x + 1][z - 1]:
					neighbors += 1
				if x > 0 and z < h - 1 and grid[x - 1][z + 1]:
					neighbors += 1
				if x < w - 1 and z < h - 1 and grid[x + 1][z + 1]:
					neighbors += 1
				if grid[x][z]:
					next[x][z] = neighbors >= 3 and neighbors <= 6
				else:
					next[x][z] = neighbors >= 5
		grid = next

	var carved := 0
	var cx := _spawn_cell.x - grid_min_x
	var cz := _spawn_cell.z - grid_min_z
	for x in range(w):
		for z in range(h):
			var dx := x - cx
			var dz := z - cz
			if dx * dx + dz * dz <= spawn_carve_radius * spawn_carve_radius:
				grid[x][z] = false
				carved += 1

	if carved == 0 and w > 0 and h > 0:
		var cx2: int = w / 2
		var cz2: int = h / 2
		var r2: int = max(3, w / 6)
		for x in range(w):
			for z in range(h):
				var dx := x - cx2
				var dz := z - cz2
				if dx * dx + dz * dz <= r2 * r2:
					grid[x][z] = false

	for x in range(w):
		for z in range(h):
			if not grid[x][z]:
				continue

			var world_x := float(grid_min_x + x)
			var world_z := float(grid_min_z + z)
			var key := Vector3i(int(round(world_x)), 0, int(round(world_z)))
			obstacle_grid[key] = true

			var obstacle: MeshInstance3D = MeshInstance3D.new()
			obstacle.name = "Wall"
			var om := BoxMesh.new()
			om.size = Vector3(tile_size * 0.85, tile_size * 0.55, tile_size * 0.85)
			var omat := StandardMaterial3D.new()
			var hue: float = rng.randf()
			# Studio Palette v1 (COLOR_SYSTEM.md): fixes the long-standing
			# "walls barely visible against floor" bug. Unlit albedo contrast
			# alone washes out under directional lighting at a glancing
			# angle; emission makes the value gap survive any lighting angle.
			var pastel := Color.from_hsv(hue, 0.32, 0.92, 1.0)
			omat.albedo_color = pastel
			omat.emission_enabled = true
			omat.emission = pastel
			omat.emission_energy_multiplier = 0.55
			omat.roughness = 0.25
			obstacle.material_override = omat
			obstacle.mesh = om
			obstacle.position = Vector3(world_x, tile_size * 0.3, world_z)
			obstacles_parent.add_child(obstacle)


func _spawn_tile(key: Vector3i) -> void:
	var tile: Node3D = Node3D.new()
	tile.name = "Tile_%d_%d" % [key.x, key.z]
	tile.position = Vector3(float(key.x), 0.0, float(key.z))

	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	floor_mesh.name = "FloorMesh"
	var fm := BoxMesh.new()
	fm.size = Vector3(tile_size, 0.05, tile_size)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.1, 0.1, 0.1, 1.0)
	fmat.roughness = 0.95
	floor_mesh.material_override = fmat
	floor_mesh.mesh = fm
	tile.add_child(floor_mesh)

	var grid_mesh: MeshInstance3D = MeshInstance3D.new()
	grid_mesh.name = "GridMesh"
	var gm := BoxMesh.new()
	gm.size = Vector3(tile_size * 1.02, 0.002, tile_size * 1.02)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.35, 0.37, 0.4, 1.0)
	grid_mesh.material_override = gmat
	grid_mesh.mesh = gm
	grid_mesh.position.y = 0.027
	tile.add_child(grid_mesh)

	add_child(tile)
	active_tiles[key] = tile


func _despawn_tile(key: Vector3i) -> void:
	var tile: Node3D = active_tiles.get(key, null)
	if tile:
		remove_child(tile)
		tile.queue_free()
	active_tiles.erase(key)


func is_tile_obstacle_at(world_pos: Vector3) -> bool:
	var key: Vector3i = Vector3i(int(round(world_pos.x)), 0, int(round(world_pos.z)))
	return obstacle_grid.has(key)


func is_tile_obstacle_at_grid(gx: int, gz: int) -> bool:
	var key: Vector3i = Vector3i(gx, 0, gz)
	return obstacle_grid.has(key)
