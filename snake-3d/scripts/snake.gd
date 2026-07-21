class_name Snake
extends Node3D

var segments: Array = []
var direction: Vector3 = Vector3.FORWARD
var grow_pending: int = 0

# Buffered turns waiting to be applied on future ticks, instead of a single
# "next direction" slot -- a single slot silently drops the first of two quick
# taps thrown between grid ticks (the classic "my fast turn didn't register"
# snake complaint). Small and bounded so input can't be queued arbitrarily far
# ahead of what the player can actually see happening.
var _direction_queue: Array = []
const MAX_QUEUED_DIRECTIONS := 2

@export var tile_size: float = 0.9
var move_duration: float = 0.16

var head_material: StandardMaterial3D
var body_material: StandardMaterial3D
var sphere_head_material: StandardMaterial3D
var sphere_body_material: StandardMaterial3D
var spike_head_material: StandardMaterial3D

var rainbow_mode: bool = false
var sphere_mode: bool = false
var spike_mode: bool = false
var _prev_segment_count: int = 0

var _turret_base_mesh: CylinderMesh
var _turret_tip_mesh: BoxMesh
var _turret_base_material: StandardMaterial3D
var _turret_tip_material: StandardMaterial3D


func _ready() -> void:
	_setup_materials()
	_setup_turret_resources()
	segments = [
		Vector3(0, 0, 0),
		Vector3(-1, 0, 0),
		Vector3(-2, 0, 0),
	]
	_prev_segment_count = segments.size()
	_segments_changed()


func _process(_delta: float) -> void:
	if not rainbow_mode:
		return
	var hue := fmod(Time.get_ticks_msec() / 1000.0 * 0.6, 1.0)
	var c := Color.from_hsv(hue, 0.85, 1.0, 1.0)
	head_material.albedo_color = c
	head_material.emission = c
	var hue2 := fmod(hue + 0.5, 1.0)
	var c2 := Color.from_hsv(hue2, 0.85, 1.0, 1.0)
	body_material.albedo_color = c2
	body_material.emission = c2


func set_rainbow_mode(on: bool) -> void:
	rainbow_mode = on
	if not on:
		var head_color := Color(0.05, 0.9, 0.3, 1.0)
		var body_color := Color(0.05, 0.65, 0.22, 1.0)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(head_material, "albedo_color", head_color, 0.3)
		tw.tween_property(head_material, "emission", head_color, 0.3)
		tw.tween_property(body_material, "albedo_color", body_color, 0.3)
		tw.tween_property(body_material, "emission", body_color, 0.3)


func set_sphere_mode(on: bool) -> void:
	sphere_mode = on
	_swap_shape_transition()


func set_spike_mode(on: bool) -> void:
	spike_mode = on
	_swap_shape_transition()


func _swap_shape_transition() -> void:
	var mesh_nodes: Array = []
	for idx in range(segments.size()):
		var n := get_node_or_null("Seg%d" % idx) as Node3D
		if n:
			var m := n.get_node_or_null("Mesh") as Node3D
			if m:
				mesh_nodes.append(m)
	if mesh_nodes.is_empty():
		_segments_changed()
		return

	var tw := create_tween()
	tw.set_parallel(true)
	for m in mesh_nodes:
		tw.tween_property(m, "scale:y", 0.05, 0.11).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(_finish_shape_swap)


func _finish_shape_swap() -> void:
	_segments_changed()
	for idx in range(segments.size()):
		var n := get_node_or_null("Seg%d" % idx) as Node3D
		if n:
			var m := n.get_node_or_null("Mesh") as Node3D
			if m:
				m.scale = Vector3(1.0, 0.05, 1.0)
				var tw2 := create_tween()
				tw2.tween_property(m, "scale:y", 1.0, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func set_direction(dir: Vector3) -> void:
	# Compare against whatever direction will be current by the time this input
	# actually takes effect -- the tail of the queue if anything's already
	# buffered, otherwise the snake's present direction.
	var reference: Vector3 = _direction_queue.back() if not _direction_queue.is_empty() else direction
	if dir == reference:
		return
	var opposite := Vector3.ZERO - reference
	if dir == opposite and segments.size() > 1:
		return
	if _direction_queue.size() >= MAX_QUEUED_DIRECTIONS:
		return
	_direction_queue.append(dir)


func get_direction() -> Vector3:
	return direction


func step() -> bool:
	if not _direction_queue.is_empty():
		direction = _direction_queue.pop_front()

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


func grow(amount: int = 1) -> void:
	grow_pending += amount
	_segments_changed()


# Used to snap back to the original spawn state after the title-screen demo
# wander -- that runs the snake around the map for an arbitrary, unbounded
# amount of time, so the real run always needs to start clean at the origin
# (where floor_manager's carve-safe zone actually is) rather than wherever
# the demo happened to leave it.
func reset_to_spawn() -> void:
	direction = Vector3.FORWARD
	_direction_queue.clear()
	grow_pending = 0
	segments = [Vector3(0, 0, 0), Vector3(-1, 0, 0), Vector3(-2, 0, 0)]
	_prev_segment_count = segments.size()
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

	sphere_head_material = StandardMaterial3D.new()
	sphere_head_material.albedo_color = Color(1.0, 0.85, 0.15, 1.0)
	sphere_head_material.emission_enabled = true
	sphere_head_material.emission = Color(1.0, 0.8, 0.1)
	sphere_head_material.emission_energy_multiplier = 1.2
	sphere_head_material.metallic = 0.6
	sphere_head_material.roughness = 0.15

	sphere_body_material = StandardMaterial3D.new()
	sphere_body_material.albedo_color = Color(1.0, 0.75, 0.1, 1.0)
	sphere_body_material.emission_enabled = true
	sphere_body_material.emission = Color(1.0, 0.7, 0.05)
	sphere_body_material.emission_energy_multiplier = 0.9
	sphere_body_material.metallic = 0.6
	sphere_body_material.roughness = 0.2

	spike_head_material = StandardMaterial3D.new()
	spike_head_material.albedo_color = Color(0.1, 0.55, 1.0, 1.0)
	spike_head_material.emission_enabled = true
	spike_head_material.emission = Color(0.1, 0.5, 1.0)
	spike_head_material.emission_energy_multiplier = 1.4
	spike_head_material.metallic = 0.6
	spike_head_material.roughness = 0.15


func _setup_turret_resources() -> void:
	_turret_base_mesh = CylinderMesh.new()
	_turret_base_mesh.top_radius = 0.14
	_turret_base_mesh.bottom_radius = 0.16
	_turret_base_mesh.height = 0.16

	_turret_tip_mesh = BoxMesh.new()
	_turret_tip_mesh.size = Vector3(0.1, 0.1, 0.1)

	_turret_base_material = StandardMaterial3D.new()
	_turret_base_material.albedo_color = Color(0.6, 0.6, 0.65, 1.0)
	_turret_base_material.metallic = 0.7
	_turret_base_material.roughness = 0.3

	_turret_tip_material = StandardMaterial3D.new()
	_turret_tip_material.albedo_color = Color(0.1, 1.0, 0.4, 1.0)
	_turret_tip_material.emission_enabled = true
	_turret_tip_material.emission = Color(0.05, 0.9, 0.3)
	_turret_tip_material.emission_energy_multiplier = 1.6


# Every segment mounts one of these (game_manager.gd fires from each segment's
# world position each volley) -- shares cached mesh/material resources since a
# fresh node gets built for every segment on every movement tick anyway.
func _make_turret_node() -> Node3D:
	var turret := Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0.0, 0.46, 0.0)

	var base := MeshInstance3D.new()
	base.mesh = _turret_base_mesh
	base.material_override = _turret_base_material
	turret.add_child(base)

	var tip := MeshInstance3D.new()
	tip.mesh = _turret_tip_mesh
	tip.material_override = _turret_tip_material
	tip.position = Vector3(0.0, 0.13, 0.0)
	turret.add_child(tip)

	return turret


func _clear_segment_nodes() -> void:
	for c: Node in get_children():
		if c.name == "Seg0":
			continue
		remove_child(c)
		c.queue_free()



func _segments_changed() -> void:
	var prev_positions: Dictionary = {}
	for c: Node in get_children():
		if c is Node3D and c.name.begins_with("Seg"):
			var idx_str := c.name.substr(3)
			if idx_str.is_valid_int():
				prev_positions[idx_str.to_int()] = (c as Node3D).position

	_clear_segment_nodes()

	var existing_head: Node3D = get_node_or_null("Seg0")
	if not existing_head:
		existing_head = Node3D.new()
		existing_head.name = "Seg0"
		add_child(existing_head)

	var head_target: Vector3 = segments[0] if not segments.is_empty() else Vector3.ZERO
	_tween_segment_position(existing_head, head_target)

	for child: Node in existing_head.get_children():
		if child.name == "CameraCranePivot":
			continue
		existing_head.remove_child(child)
		child.queue_free()

	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Mesh"
	mesh_node.mesh = _make_segment_mesh(true)
	var head_mat := head_material
	if spike_mode:
		head_mat = spike_head_material
		mesh_node.basis = Basis(Quaternion(Vector3.UP, direction))
		mesh_node.position = direction * 0.15
	elif sphere_mode:
		head_mat = sphere_head_material
	mesh_node.set_surface_override_material(0, head_mat)
	existing_head.add_child(mesh_node)
	if not spike_mode:
		existing_head.add_child(_make_turret_node())

	for idx: int in range(1, segments.size()):
		var seg: Vector3 = segments[idx]
		var node := Node3D.new()
		node.name = "Seg%d" % idx
		node.position = prev_positions.get(idx, seg)

		var mesh_node2 := MeshInstance3D.new()
		mesh_node2.name = "Mesh"
		mesh_node2.mesh = _make_segment_mesh(false)
		var body_mat := body_material
		if sphere_mode:
			body_mat = sphere_body_material
		mesh_node2.set_surface_override_material(0, body_mat)
		node.add_child(mesh_node2)
		node.add_child(_make_turret_node())
		add_child(node)
		_tween_segment_position(node, seg)

	if segments.size() > _prev_segment_count and segments.size() > 1:
		var new_tail := get_node_or_null("Seg%d" % (segments.size() - 1)) as Node3D
		if new_tail:
			new_tail.scale = Vector3.ZERO
			var tw := create_tween()
			tw.tween_property(new_tail, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_prev_segment_count = segments.size()


func _tween_segment_position(node: Node3D, target: Vector3) -> void:
	if node.position.distance_squared_to(target) < 0.0001:
		node.position = target
		return
	var tw := create_tween()
	tw.tween_property(node, "position", target, move_duration).set_trans(Tween.TRANS_LINEAR)


func _make_segment_mesh(is_head: bool) -> Mesh:
	if spike_mode and is_head:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.4
		cm.height = 1.1
		return cm
	if sphere_mode:
		var sm := SphereMesh.new()
		sm.radius = 0.45
		sm.height = 0.9
		return sm
	var bm := BoxMesh.new()
	bm.size = Vector3(0.85, 0.85, 0.85)
	return bm
