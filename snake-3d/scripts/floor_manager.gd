class_name FloorManager extends Node3D

@export var snake: Node3D
@export var view_radius: int = 18
@export var obstacle_chance: float = 0.25
@export var tile_size: float = 0.9

var rng: RandomNumberGenerator
var active_tiles: Dictionary = {}


func _ready() -> void:
	rng = RandomNumberGenerator.new()
	rng.randomize()
	_update_tiles()

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

	if rng.randf() < obstacle_chance:
		var obstacle: MeshInstance3D = MeshInstance3D.new()
		obstacle.name = "Obstacle"
		var om := BoxMesh.new()
		om.size = Vector3(tile_size * 0.55, tile_size * 0.55, tile_size * 0.55)
		var omat := StandardMaterial3D.new()
		var hue: float = rng.randf()
		var pastel := Color.from_hsv(hue, 0.35, 0.92, 1.0)
		omat.albedo_color = pastel
		omat.roughness = 0.3
		obstacle.material_override = omat
		obstacle.mesh = om
		obstacle.position.y = tile_size * 0.3
		tile.add_child(obstacle)

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
	if active_tiles.has(key):
		var tile: Node3D = active_tiles[key]
		return tile.has_node("Obstacle")
	return false


func is_tile_obstacle_at_grid(gx: int, gz: int) -> bool:
	var key: Vector3i = Vector3i(gx, 0, gz)
	if active_tiles.has(key):
		var tile: Node3D = active_tiles[key]
		return tile.has_node("Obstacle")
	return false
