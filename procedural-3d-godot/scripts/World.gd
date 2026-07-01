extends Node3D

const LANE_X := [-2.0, 0.0, 2.0]
const CHUNK_LENGTH := 8.0
const PLATFORM_W := 1.8
const PLATFORM_H := 0.5
const SPAWN_AHEAD := 14
const KEEP_BEHIND := 3

var player: CharacterBody3D = null
var chunks: Array[Node3D] = []
var next_z := 0.0
var chunk_count := 0

var _mat_a: StandardMaterial3D
var _mat_b: StandardMaterial3D

@onready var platform_parent: Node3D = $PlatformParent

func _ready() -> void:
	randomize()
	_mat_a = StandardMaterial3D.new()
	_mat_a.albedo_color = Color(0.45, 0.5, 0.6)
	_mat_b = StandardMaterial3D.new()
	_mat_b.albedo_color = Color(0.38, 0.43, 0.52)
	for i in range(6):
		_spawn_chunk(true)
	for i in range(SPAWN_AHEAD - 6):
		_spawn_chunk(false)

func set_player(p: CharacterBody3D) -> void:
	player = p

func _process(_delta: float) -> void:
	if not player:
		return
	var pz := player.global_position.z
	while next_z > pz - SPAWN_AHEAD * CHUNK_LENGTH:
		_spawn_chunk(false)
	for chunk in chunks.duplicate():
		if not is_instance_valid(chunk):
			chunks.erase(chunk)
		elif chunk.global_position.z > pz + KEEP_BEHIND * CHUNK_LENGTH:
			chunk.queue_free()
			chunks.erase(chunk)

func _spawn_chunk(force_all: bool) -> void:
	var chunk := Node3D.new()
	chunk.position.z = next_z
	platform_parent.add_child(chunk)
	chunks.append(chunk)
	chunk_count += 1

	var lanes_active := [true, true, true]
	if not force_all and chunk_count > 8 and randf() < 0.3:
		lanes_active[randi() % 3] = false

	var mat: StandardMaterial3D = _mat_a if chunk_count % 2 == 0 else _mat_b
	for i in range(3):
		if lanes_active[i]:
			_add_platform(chunk, i, mat)

	next_z -= CHUNK_LENGTH

func _add_platform(parent: Node3D, lane_idx: int, mat: StandardMaterial3D) -> void:
	var body := StaticBody3D.new()
	body.position = Vector3(LANE_X[lane_idx], -PLATFORM_H * 0.5, -CHUNK_LENGTH * 0.5)

	var shape := BoxShape3D.new()
	shape.size = Vector3(PLATFORM_W, PLATFORM_H, CHUNK_LENGTH)
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)

	var mesh := BoxMesh.new()
	mesh.size = Vector3(PLATFORM_W, PLATFORM_H, CHUNK_LENGTH)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)

	parent.add_child(body)
