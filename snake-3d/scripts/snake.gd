class_name Snake
extends Node3D

var segments: Array = []
var direction: Vector3 = Vector3.FORWARD
var next_direction: Vector3 = Vector3.FORWARD
var grow_pending: int = 0

@export var tile_size: float = 0.9

var head_material: StandardMaterial3D
var body_material: StandardMaterial3D


func _ready() -> void:
	_setup_materials()
	segments = [
		Vector3(0, 0, 0),
		Vector3(-1, 0, 0),
		Vector3(-2, 0, 0),
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


func teleport(offset: Vector3) -> void:
	for i in range(segments.size()):
		segments[i] += offset
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
		if c.name == "CameraCranePivot":
			continue
		if c.name == "Seg0" and c.get_node_or_null("CameraCranePivot"):
			continue
		remove_child(c)
		c.queue_free()


func _segments_changed() -> void:
	_clear_segment_nodes()

	var existing_head: Node3D = get_node_or_null("Seg0")
	if not existing_head:
		existing_head = Node3D.new()
		existing_head.name = "Seg0"
		add_child(existing_head)

	existing_head.position = segments[0] if not segments.is_empty() else Vector3.ZERO

	for child: Node in existing_head.get_children():
		if child.name == "CameraCranePivot":
			continue
		existing_head.remove_child(child)
		child.queue_free()

	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Mesh"
	var m := BoxMesh.new()
	m.size = Vector3(0.85, 0.85, 0.85)
	mesh_node.mesh = m
	mesh_node.set_surface_override_material(
		0,
		head_material
	)
	existing_head.add_child(mesh_node)

	for idx: int in range(1, segments.size()):
		var seg: Vector3 = segments[idx]
		var node := Node3D.new()
		node.name = "Seg%d" % idx
		node.position = seg

		var mesh_node2 := MeshInstance3D.new()
		mesh_node2.name = "Mesh"
		var m2 := BoxMesh.new()
		m2.size = Vector3(0.85, 0.85, 0.85)
		mesh_node2.mesh = m2
		mesh_node2.set_surface_override_material(
			0,
			body_material
		)
		node.add_child(mesh_node2)
		add_child(node)
