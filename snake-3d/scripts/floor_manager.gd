class_name FloorManager extends Node3D

@export var snake: Node3D
@export var view_radius: int = 18
@export var obstacle_chance: float = 0.25
@export var tile_size: float = 0.9

# CA + WFC-inspired obstacle generation
@export var obstacle_density: float = 0.45
@export var ca_iterations: int = 3
@export var min_cluster_size: int = 4

var rng: RandomNumberGenerator
var active_tiles: Dictionary = {}
var obstacles_parent: Node3D
var obstacle_grid: Dictionary = {}
var _last_center_cell: Vector3i = Vector3i(0x7fffffff, 0, 0x7fffffff)


func _ready() -> void:
	rng = RandomNumberGenerator.new()
	rng.randomize()
	_update_tiles()

	obstacles_parent = Node3D.new()
	obstacles_parent.name = "Obstacles"
	add_child(obstacles_parent)

	var snake_node := get_node_or_null("../Snake")
	if snake_node:
		snake = snake_node


func _process(_delta: float) -> void:
	_update_tiles()


func _update_tiles() -> void:
	if not snake:
		return

	var head: Vector3 = snake.global_position
	var cx: int = int(round(head.x))
	var cz: int = int(round(head.z))
	var center_cell: Vector3i = Vector3i(cx, 0, cz)

	if center_cell != _last_center_cell:
		_last_center_cell = center_cell
		_refresh_obstacles(cx, cz)

	var needed: Dictionary = {}
	for x: int in range(cx - view_radius, cx + view_radius + 1):
		for z: int in range(cz - view_radius, cz + view_radius + 1):
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


func _refresh_obstacles(cx: int, cz: int) -> void:
	# Clear previous obstacles.
	for c in obstacles_parent.get_children():
		remove_child(c)
		c.queue_free()
	obstacle_grid.clear()

	var r: int = view_radius
	var min_x: int = cx - r
	var max_x: int = cx + r
	var min_z: int = cz - r
	var max_z: int = cz + r
	var w: int = max_x - min_x + 1
	var h: int = max_z - min_z + 1

	# Initial noise based on global coordinates (deterministic).
	var grid: Array = []
	for x in range(min_x, max_x + 1):
		grid.append([])
		for z in range(min_z, max_z + 1):
			var noise := float(hash(Vector3i(x, 0, z)) % 1000) / 1000.0
			grid[x - min_x].append(noise < obstacle_density)

	# CA smoothing to encourage clusters.
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
				if grid[x][z]:
					if neighbors < 2:
						next[x][z] = false
				else:
					if neighbors >= 3:
						next[x][z] = true
		grid = next

	# Connected components -> merged obstacle shapes.
	var visited: Array = []
	for x in range(w):
		visited.append([])
		for z in range(h):
			visited[x].append(false)

	for x in range(w):
		for z in range(h):
			if not grid[x][z] or visited[x][z]:
				continue
			var stack: Array = [Vector2i(x, z)]
			visited[x][z] = true
			var component: Array = []
			while stack.size() > 0:
				var cur: Vector2i = stack.pop_back()
				component.append(cur)
				for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx = cur.x + dir.x
					var nz = cur.y + dir.y
					if nx < 0 or nz < 0 or nx >= w or nz >= h:
						continue
					if visited[nx][nz] or not grid[nx][nz]:
						continue
					visited[nx][nz] = true
					stack.append(Vector2i(nx, nz))
			if component.size() < min_cluster_size:
				continue

			var origin: Vector2i = component[0]
			var comp_min_x: int = origin.x
			var comp_max_x: int = origin.x
			var comp_min_z: int = origin.y
			var comp_max_z: int = origin.y
			for idx in range(1, component.size()):
				var p: Vector2i = component[idx]
				if p.x < comp_min_x:
					comp_min_x = p.x
				if p.x > comp_max_x:
					comp_max_x = p.x
				if p.y < comp_min_z:
					comp_min_z = p.y
				if p.y > comp_max_z:
					comp_max_z = p.y

			var world_x1 := float(min_x + comp_min_x)
			var world_x2 := float(min_x + comp_max_x)
			var world_z1 := float(min_z + comp_min_z)
			var world_z2 := float(min_z + comp_max_z)

			var size_x := (world_x2 - world_x1 + 1.0) * tile_size
			var size_z := (world_z2 - world_z1 + 1.0) * tile_size
			var center_x := (world_x1 + world_x2) / 2.0
			var center_z := (world_z1 + world_z2) / 2.0

			var obstacle: MeshInstance3D = MeshInstance3D.new()
			obstacle.name = "Obstacle"
			var om := BoxMesh.new()
			om.size = Vector3(size_x, tile_size * 0.55, size_z)
			var omat := StandardMaterial3D.new()
			var hue: float = rng.randf()
			var pastel := Color.from_hsv(hue, 0.35, 0.92, 1.0)
			omat.albedo_color = pastel
			omat.roughness = 0.3
			obstacle.material_override = omat
			obstacle.mesh = om
			obstacle.position = Vector3(center_x, tile_size * 0.3, center_z)

			obstacles_parent.add_child(obstacle)

			for p in component:
				var key := Vector3i(min_x + p.x, 0, min_z + p.y)
				obstacle_grid[key] = true


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
