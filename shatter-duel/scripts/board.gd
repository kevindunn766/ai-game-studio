extends Node3D
# A vertical wall of cube blocks (grey-box).
#   interactive = true  -> local board: each block is a pickable StaticBody3D (tap to shoot).
#   interactive = false -> opponent mirror: plain cubes, driven purely by a synced count.
# All geometry is built from Godot's BoxMesh so triangle winding is guaranteed correct
# (see docs/godot-3d-best-practices.md — no hand-rolled meshes here on purpose).

signal block_tapped(body)

const BLOCK := 0.5
const GAP := 0.09
const COLS := 5
const COLORS := [Color("e05a47"), Color("47a0e0"), Color("e0c247"), Color("6cc24a")]

var interactive := false

var _bodies: Array[Node3D] = []
var _mesh := BoxMesh.new()

func _ready() -> void:
	_mesh.size = Vector3.ONE * BLOCK

func count() -> int:
	return _bodies.size()

func has_block(body: Node3D) -> bool:
	return _bodies.has(body)

func any_block() -> Node3D:
	if _bodies.is_empty():
		return null
	return _bodies[0]

func fill(n: int) -> void:
	_clear()
	for i in n:
		_add_block(i)

func add_blocks(n: int) -> void:
	var start := _bodies.size()
	for i in n:
		_add_block(start + i)

func remove_one(body: Node3D) -> void:
	_bodies.erase(body)
	body.queue_free()
	_relayout()

# Visual-only mirror of the opponent's board: grow or shrink to match a count.
func set_count(n: int) -> void:
	if n > _bodies.size():
		add_blocks(n - _bodies.size())
	else:
		while _bodies.size() > n and not _bodies.is_empty():
			var b: Node3D = _bodies.pop_back()
			b.queue_free()

func _clear() -> void:
	for b in _bodies:
		b.queue_free()
	_bodies.clear()

func _add_block(index: int) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLORS[index % COLORS.size()]

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = _mesh
	mesh_inst.material_override = mat

	var node: Node3D
	if interactive:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3.ONE * BLOCK
		shape.shape = box
		body.add_child(shape)
		body.add_child(mesh_inst)
		body.input_ray_pickable = true
		body.input_event.connect(_on_body_input.bind(body))
		node = body
	else:
		node = mesh_inst

	add_child(node)
	_bodies.append(node)
	node.position = _slot(index)

func _relayout() -> void:
	for i in _bodies.size():
		_bodies[i].position = _slot(i)

func _slot(i: int) -> Vector3:
	@warning_ignore("integer_division")
	var row := i / COLS
	var col := i % COLS
	var span := float(COLS - 1) * (BLOCK + GAP)
	return Vector3(float(col) * (BLOCK + GAP) - span * 0.5, float(row) * (BLOCK + GAP), 0.0)

func _on_body_input(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int, body: Node3D) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		emit_signal("block_tapped", body)
	elif event is InputEventScreenTouch and event.pressed:
		emit_signal("block_tapped", body)
