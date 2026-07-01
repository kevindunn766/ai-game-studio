class_name Snake
extends Node3D

var grid_size: int = 20
var segments: Array = []
var direction: Vector3 = Vector3.FORWARD
var next_direction: Vector3 = Vector3.FORWARD
var grow_pending: int = 0

var head_material: StandardMaterial3D
var body_material: StandardMaterial3D


func _ready() -> void:
	_setup_materials()
	segments = [
		Vector3(10, 0, 10),
		Vector3(9, 0, 10),
		Vector3(8, 0, 10),
	]
	_segments_changed()


func set_direction(dir: Vector3) -> void:
	var opposite := Vector3.ZERO - direction
	if dir == opposite and segments.size() > 1:
		return
	next_direction = dir


func get_direction() -> Vector3:
	return direction


func step() -> bool:
	direction = next_direction

	var head := segments.front() as Vector3
	var new_head := head + direction

	# Wall death
	if (
		new_head.x < 0
		or new_head.z < 0
		or new_head.x >= grid_size
		or new_head.z >= grid_size
	):
		return false

	# Self collision
	var occupied: Dictionary = {}
	for seg: Vector3 in segments:
		occupied[seg] = true
	if occupied.has(new_head):
		return false

	segments.push_front(new_head)
	if grow_pending > 0:
		grow_pending -= 1
	else:
		segments.pop_back()

	_segments_changed()
	return true


func grow() -> void:
	grow_pending += 1
	_segments_changed()


func _setup_materials() -> void:
	var head_color := Color(0.05, 0.9, 0.3, 1.0)
	var body_color := Color(0.05, 0.65, 0.22, 1.0)

	head_material = StandardMaterial3D.new()
	head_material.albedo_color = head_color
	head_material.emission_enabled = true
	head_material.emission = head_color
	head_material.emission_energy_multiplier = 0.8
	head_material.roughness = 0.3

	body_material = StandardMaterial3D.new()
	body_material.albedo_color = body_color
	body_material.emission_enabled = true
	body_material.emission = body_color
	body_material.emission_energy_multiplier = 0.5
	body_material.roughness = 0.45


func _clear_segment_nodes() -> void:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()


func _segments_changed() -> void:
	_clear_segment_nodes()
	for idx: int in segments.size():
		var seg: Vector3 = segments[idx]
		var node := Node3D.new()
		node.name = "Seg%d" % idx
		node.position = seg

		var mesh_node := MeshInstance3D.new()
		mesh_node.name = "Mesh"
		var m := BoxMesh.new()
		m.size = Vector3(0.85, 0.85, 0.85)
		mesh_node.mesh = m
		mesh_node.set_surface_override_material(
			0,
			head_material if idx == 0 else body_material
		)
		node.add_child(mesh_node)
		add_child(node)
