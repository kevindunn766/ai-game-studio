extends Node3D

# Stack Rush — tap/click/space to drop the moving block and stack the
# tower as high as possible. Overhang is sliced off and falls away.
# Miss completely (zero overlap) = game over.

const BASE_SIZE := Vector3(3.0, 0.6, 3.0)
const SAVE_PATH := "user://stackrush_highscore.cfg"
const MIN_OVERLAP := 0.12
const CAMERA_OFFSET := Vector3(7.0, 6.0, 7.0)

const PALETTE := [
	Color(1.0, 0.42, 0.42, 1.0),
	Color(1.0, 0.68, 0.3, 1.0),
	Color(1.0, 0.86, 0.35, 1.0),
	Color(0.45, 0.85, 0.55, 1.0),
	Color(0.35, 0.75, 0.95, 1.0),
	Color(0.6, 0.5, 0.95, 1.0),
	Color(0.95, 0.45, 0.75, 1.0),
]

@onready var camera: Camera3D = $Camera3D
@onready var score_label: Label3D = $ScoreLabel
@onready var game_over_overlay: Node3D = $GameOverOverlay
@onready var game_over_score_label: Label3D = $GameOverOverlay/GameOverScore

var blocks: Array = []
var layer_index: int = 0
var moving_node: MeshInstance3D = null
var moving_size: Vector3 = BASE_SIZE
var moving_axis_idx: int = 0
var move_amplitude: float = 2.2
var move_speed: float = 1.6
var t: float = 0.0

var falling_pieces: Array = []

var score: int = 0
var high_score: int = 0
var game_over: bool = false
var camera_focus_y: float = 0.0


func _ready() -> void:
	_load_high_score()
	_start_game()


func _start_game() -> void:
	for child in get_children():
		if child.name.begins_with("Block") or child.name.begins_with("Debris"):
			child.queue_free()
	blocks.clear()
	falling_pieces.clear()
	layer_index = 0
	score = 0
	game_over = false
	t = 0.0
	camera_focus_y = 0.0
	game_over_overlay.visible = false
	score_label.text = "0"

	var base_block := _make_block(BASE_SIZE, Vector3.ZERO, Color(0.85, 0.87, 0.92, 1.0))
	base_block.name = "Block0"
	blocks.append({"center": Vector3.ZERO, "size": BASE_SIZE})

	_spawn_next_moving_block()


func _make_block(size: Vector3, center: Vector3, color: Color) -> MeshInstance3D:
	var mesh_node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_node.mesh = box
	mesh_node.position = center

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.35
	mat.roughness = 0.55
	mesh_node.set_surface_override_material(0, mat)

	add_child(mesh_node)
	return mesh_node


func _spawn_next_moving_block() -> void:
	layer_index += 1
	moving_axis_idx = 0 if layer_index % 2 == 1 else 2

	var last: Dictionary = blocks.back()
	moving_size = last["size"]

	var start_center: Vector3 = last["center"]
	start_center.y = last["center"].y + BASE_SIZE.y
	# Bias the starting side so the sweep begins clearly off to one edge.
	t = -PI / 2.0

	var color: Color = PALETTE[layer_index % PALETTE.size()]
	moving_node = _make_block(moving_size, start_center, color)
	moving_node.name = "BlockMoving"


func _process(delta: float) -> void:
	if not game_over:
		t += delta
		if moving_node:
			var last: Dictionary = blocks.back()
			var pos: Vector3 = moving_node.position
			var axis_center: float = last["center"][moving_axis_idx]
			pos[moving_axis_idx] = axis_center + sin(t * move_speed) * move_amplitude
			moving_node.position = pos

	_update_falling_pieces(delta)
	_update_camera(delta)


func _update_camera(delta: float) -> void:
	var target_y: float = blocks.back()["center"].y if not blocks.is_empty() else 0.0
	camera_focus_y = lerp(camera_focus_y, target_y, clamp(delta * 3.0, 0.0, 1.0))
	camera.position = CAMERA_OFFSET + Vector3(0, camera_focus_y, 0)
	camera.look_at(Vector3(0, camera_focus_y + 1.0, 0), Vector3.UP)


func _update_falling_pieces(delta: float) -> void:
	var still_falling := []
	for piece in falling_pieces:
		piece["vel"].y -= 18.0 * delta
		piece["node"].position += piece["vel"] * delta
		piece["node"].rotate_x(delta * 2.0)
		if piece["node"].position.y > camera_focus_y - 20.0:
			still_falling.append(piece)
		else:
			piece["node"].queue_free()
	falling_pieces = still_falling


func _input(event: InputEvent) -> void:
	var tapped := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped = true
	elif event is InputEventScreenTouch and event.pressed:
		tapped = true
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		tapped = true

	if not tapped:
		return

	if game_over:
		_start_game()
	else:
		_try_drop()


func _try_drop() -> void:
	if not moving_node:
		return

	var last: Dictionary = blocks.back()
	var axis := moving_axis_idx

	var moving_half: float = moving_size[axis] / 2.0
	var moving_pos: float = moving_node.position[axis]
	var moving_min: float = moving_pos - moving_half
	var moving_max: float = moving_pos + moving_half

	var last_half: float = last["size"][axis] / 2.0
	var last_center: float = last["center"][axis]
	var last_min: float = last_center - last_half
	var last_max: float = last_center + last_half

	var overlap_min: float = max(moving_min, last_min)
	var overlap_max: float = min(moving_max, last_max)
	var overlap: float = overlap_max - overlap_min

	if overlap <= MIN_OVERLAP:
		_trigger_game_over()
		return

	# Spawn debris for the sliced-off overhang piece(s).
	if moving_min < overlap_min:
		_spawn_debris(axis, moving_min, overlap_min, moving_node.position.y, -1.0)
	if moving_max > overlap_max:
		_spawn_debris(axis, overlap_max, moving_max, moving_node.position.y, 1.0)

	var new_size: Vector3 = moving_size
	new_size[axis] = overlap
	var new_center: Vector3 = last["center"]
	new_center[axis] = (overlap_min + overlap_max) / 2.0
	new_center.y = moving_node.position.y

	var box: BoxMesh = moving_node.mesh as BoxMesh
	box.size = new_size
	moving_node.position = new_center
	moving_node.name = "Block%d" % layer_index

	blocks.append({"center": new_center, "size": new_size})
	moving_node = null

	score += 1
	score_label.text = str(score)
	move_speed = 1.6 + score * 0.045

	_spawn_next_moving_block()


func _spawn_debris(axis: int, from_edge: float, to_edge: float, y: float, out_dir: float) -> void:
	var length: float = to_edge - from_edge
	if length <= 0.001:
		return
	var size: Vector3 = moving_size
	size[axis] = length
	var center: Vector3 = moving_node.position
	center[axis] = (from_edge + to_edge) / 2.0

	var mat_color: Color = (moving_node.get_surface_override_material(0) as StandardMaterial3D).albedo_color
	var debris := _make_block(size, center, mat_color)
	debris.name = "Debris%d" % Time.get_ticks_msec()

	var vel := Vector3.ZERO
	vel[axis] = out_dir * 1.5
	falling_pieces.append({"node": debris, "vel": vel})


func _trigger_game_over() -> void:
	game_over = true
	if moving_node:
		var vel := Vector3(0, -1.0, 0)
		falling_pieces.append({"node": moving_node, "vel": vel})
		moving_node = null

	if score > high_score:
		high_score = score
		_save_high_score()

	game_over_score_label.text = "Score: %d  Best: %d" % [score, high_score]
	game_over_overlay.visible = true
	game_over_overlay.position = Vector3(0, camera_focus_y, 0)


func _load_high_score() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		high_score = int(cfg.get_value("scores", "high_score", 0))


func _save_high_score() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("scores", "high_score", high_score)
	cfg.save(SAVE_PATH)
