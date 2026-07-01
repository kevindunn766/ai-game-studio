class_name Snake
extends Node3D

var segments: Array = []
var direction: Vector3 = Vector3.FORWARD
var next_direction: Vector3 = Vector3.FORWARD
var grid_size: int = 20

var segment_mesh: BoxMesh
var head_material: StandardMaterial3D
var body_material: StandardMaterial3D


func _ready() -> void:
	_setup_materials()
	segments = [Vector3(10, 0, 10), Vector3(9, 0, 10), Vector3(8, 0, 10)]
	_rebuild_meshes()


func set_direction(dir: Vector3) -> void:
	var opposite := Vector3.ZERO - direction
	if dir == opposite and segments.size() > 1:
		return
	next_direction = dir


func step() -> bool:
	direction = next_direction

	var head := segments.front() as Vector3
	var new_head := head + direction

	# wall collision
	if (
		new_head.x < 0
		or new_head.z < 0
		or new_head.x >= grid_size
		or new_head.z >= grid_size
	):
		return false

	# self collision
	var occupied: Dictionary = {}
	for seg: Vector3 in segments:
		occupied[seg] = true
	if occupied.has(new_head):
		return false

	segments.push_front(new_head)

	# food eaten check delegated to parent via signal
	food_eaten_here.emit()

	_segments_changed()

	return true


func grow() -> void:
	_segments_changed()


signal food_eaten_here


func _setup_materials() -> void:
	var head_color := Color(0.05, 0.9, 0.3, 1.0)
	var body_color := Color(0.05, 0.6, 0.2, 1.0)

	head_material = StandardMaterial3D.new()
	head_material.albedo_color = head_color
	head_material.emission_enabled = true
	head_material.emission = head_color
	head_material.emission_energy_multiplier = 0.7
	head_material.roughness = 0.35

	body_material = StandardMaterial3D.new()
	body_material.albedo_color = body_color
	body_material.emission_enabled = true
	body_material.emission = body_color
	body_material.emission_energy_multiplier = 0.5
	body_material.roughness = 0.45

	var mat := body_material.duplicate() as StandardMaterial3D
	mat.albedo_color = Color(0.95, 0.95, 0.2, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.95, 0.95, 0.2, 1.0)
	mat.emission_energy_multiplier = 0.9
	mat.roughness = 0.3


func _rebuild_meshes() -> void:
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
		if idx == 0:
			mesh_node.set_surface_override_material(0, head_material)
		else:
			mesh_node.set_surface_override_material(0, body_material)
		node.add_child(mesh_node)
		add_child(node)
		segments[idx] = seg


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
		mesh_node.set_surface_override_material(0, head_material if idx == 0 else body_material)
		node.add_child(mesh_node)
		add_child(node)
