extends Node3D

# Spiral Drop — a ball falls straight down a vertical shaft while a stack
# of rotating "gates" (rings of teeth with one gap) scroll past. Rotate the
# tower (keys / drag) so the gap lines up with the ball before it arrives.

const NUM_TEETH := 10
const GAP_WIDTH := 2
const GATE_RADIUS := 2.0
const GATE_SPACING := 3.0
const SLOT_ANGLE := TAU / NUM_TEETH
const TOOTH_SIZE := Vector3(0.9, 0.6, 0.55)
const ROTATE_SPEED := 2.4
const DRAG_SENSITIVITY := 0.01
const SAVE_PATH := "user://spiraldrop_highscore.cfg"
const GENERATE_AHEAD := 15
const GENERATE_TRIGGER := 5

# Studio Palette v1 (see COLOR_SYSTEM.md): gates stay cool and deliberately
# less saturated than the ball, so the one thing the player must track never
# has to compete visually with the scenery (Itten's contrast of saturation).
const GATE_HUE_START := 0.5
const GATE_HUE_RANGE := 0.33
const GATE_HUE_STEPS := 5
const GATE_SATURATION := 0.48
const GATE_VALUE := 0.78

# Novelty twist: a rare golden gate (bright gold teeth, unmistakably
# different from the muted cool palette) is worth double score if you
# make it through.
const GOLDEN_GATE_CHANCE := 0.12
const GOLDEN_GATE_COLOR := Color(0.93, 0.76, 0.15, 1.0)
const GOLDEN_GATE_SCORE := 2

# Structural addition: dual-gap gates. Instead of one gap to find, some
# gates open TWO separate gaps on opposite sides of the ring — a wide
# "safe" gap worth the normal point, and a narrower "risk" gap (flagged
# with amber marker teeth) worth more. The player has to commit to a lane
# before the gate arrives, a real choice rather than just aiming for the
# single opening. Mutually exclusive with the golden-gate twist so each
# gate reads as exactly one clear thing.
const DUAL_GAP_CHANCE := 0.3
const RISK_GAP_WIDTH := 1
const RISK_GAP_SCORE := 2
const RISK_MARKER_COLOR := Color(0.95, 0.55, 0.12, 1.0)

# Novel element: Mirror Gate. A rare violet gate that, once passed
# cleanly, inverts the rotation controls (A/D and drag) for a few
# seconds — a disorientation twist distinct from the dual-gap lane
# choice (a spatial decision) and the golden gate (a score multiplier).
# Mutually exclusive with both so every gate still reads as one thing.
const MIRROR_GATE_CHANCE := 0.1
const MIRROR_GATE_COLOR := Color(0.55, 0.25, 0.78, 1.0)
const MIRROR_DURATION := 4.0
var mirror_active: bool = false
var mirror_timer: float = 0.0
var score_label_default_color: Color = Color(1, 1, 1, 1)

@onready var tower_root: Node3D = $TowerRoot
@onready var ball: MeshInstance3D = $Ball
@onready var camera: Camera3D = $Camera3D
@onready var score_label: Label3D = $ScoreLabel
@onready var game_over_overlay: Node3D = $GameOverOverlay
@onready var game_over_score_label: Label3D = $GameOverOverlay/GameOverScore

var gates: Array = []
var next_gate_index: int = 0
var tower_rotation: float = 0.0
var ball_y: float = 2.0
var fall_speed: float = 2.2

var score: int = 0
var high_score: int = 0
var game_over: bool = false
var camera_focus_y: float = 0.0


func _ready() -> void:
	_setup_ball()
	score_label_default_color = score_label.modulate
	_load_high_score()
	_start_game()


func _setup_ball() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.35
	sphere.height = 0.7
	ball.mesh = sphere
	var mat := StandardMaterial3D.new()
	# Warm, high-chroma accent-primary — deliberately far above the gates'
	# saturation so the ball is unmistakable against the muted tower.
	mat.albedo_color = Color.from_hsv(0.11, 0.75, 0.95, 1.0)
	mat.emission_enabled = true
	mat.emission = Color.from_hsv(0.11, 0.85, 1.0, 1.0)
	mat.emission_energy_multiplier = 0.9
	ball.set_surface_override_material(0, mat)


func _start_game() -> void:
	for child in tower_root.get_children():
		child.queue_free()
	gates.clear()
	next_gate_index = 0
	tower_rotation = 0.0
	tower_root.rotation.y = 0.0
	ball_y = 2.0
	fall_speed = 2.2
	score = 0
	game_over = false
	camera_focus_y = ball_y
	score_label.text = "0"
	mirror_active = false
	mirror_timer = 0.0
	score_label.modulate = score_label_default_color
	game_over_overlay.visible = false

	_generate_gates(GENERATE_AHEAD)


func _gate_color(idx: int) -> Color:
	var step: int = idx % GATE_HUE_STEPS
	var hue: float = fmod(GATE_HUE_START + (float(step) / float(GATE_HUE_STEPS)) * GATE_HUE_RANGE, 1.0)
	return Color.from_hsv(hue, GATE_SATURATION, GATE_VALUE, 1.0)


func _generate_gates(count: int) -> void:
	for _i in range(count):
		var idx: int = gates.size()
		var y: float = -float(idx) * GATE_SPACING
		var gap_start: int = randi() % NUM_TEETH
		var is_dual: bool = randf() < DUAL_GAP_CHANCE
		var is_golden: bool = (not is_dual) and randf() < GOLDEN_GATE_CHANCE
		var is_mirror: bool = (not is_dual) and (not is_golden) and randf() < MIRROR_GATE_CHANCE
		var color: Color = MIRROR_GATE_COLOR if is_mirror else (GOLDEN_GATE_COLOR if is_golden else _gate_color(idx))

		var risk_gap_start: int = (gap_start + NUM_TEETH / 2) % NUM_TEETH

		var gate_node := Node3D.new()
		gate_node.name = "Gate%d" % idx
		gate_node.position = Vector3(0, y, 0)
		tower_root.add_child(gate_node)

		for tooth_i in range(NUM_TEETH):
			var in_gap := false
			for k in range(GAP_WIDTH):
				if (gap_start + k) % NUM_TEETH == tooth_i:
					in_gap = true
					break
			if is_dual and not in_gap:
				for k in range(RISK_GAP_WIDTH):
					if (risk_gap_start + k) % NUM_TEETH == tooth_i:
						in_gap = true
						break
			if in_gap:
				continue

			var angle: float = tooth_i * SLOT_ANGLE
			var tooth := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = TOOTH_SIZE
			tooth.mesh = box
			tooth.position = Vector3(GATE_RADIUS * cos(angle), 0, GATE_RADIUS * sin(angle))
			tooth.rotation.y = -angle

			var mat := StandardMaterial3D.new()
			mat.albedo_color = color
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy_multiplier = 0.4
			tooth.set_surface_override_material(0, mat)

			gate_node.add_child(tooth)

		if is_dual:
			_add_risk_marker(gate_node, risk_gap_start)

		gates.append({
			"y": y,
			"gap_start": gap_start,
			"resolved": false,
			"golden": is_golden,
			"dual": is_dual,
			"risk_gap_start": risk_gap_start,
			"mirror": is_mirror,
		})


func _add_risk_marker(gate_node: Node3D, risk_gap_start: int) -> void:
	var center_slot: float = float(risk_gap_start) + (float(RISK_GAP_WIDTH) - 1.0) / 2.0
	var angle: float = center_slot * SLOT_ANGLE
	var marker := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.28
	disc.bottom_radius = 0.28
	disc.height = 0.08
	marker.mesh = disc
	marker.position = Vector3(GATE_RADIUS * cos(angle), 0, GATE_RADIUS * sin(angle))

	var mat := StandardMaterial3D.new()
	mat.albedo_color = RISK_MARKER_COLOR
	mat.emission_enabled = true
	mat.emission = RISK_MARKER_COLOR
	mat.emission_energy_multiplier = 0.9
	marker.set_surface_override_material(0, mat)

	gate_node.add_child(marker)


func _process(delta: float) -> void:
	if not game_over:
		if mirror_active:
			mirror_timer -= delta
			if mirror_timer <= 0.0:
				_end_mirror_effect()
		_handle_rotation_input(delta)
		ball_y -= fall_speed * delta

		while next_gate_index < gates.size() and ball_y <= gates[next_gate_index]["y"]:
			_resolve_gate(next_gate_index)
			next_gate_index += 1
			if game_over:
				break

		if gates.size() - next_gate_index < GENERATE_TRIGGER:
			_generate_gates(10)

	ball.position = Vector3(GATE_RADIUS, ball_y, 0)
	tower_root.rotation.y = tower_rotation
	_update_camera(delta)


func _handle_rotation_input(delta: float) -> void:
	var dir := 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir += 1.0
	if mirror_active:
		dir = -dir
	tower_rotation += dir * ROTATE_SPEED * delta


func _start_mirror_effect() -> void:
	mirror_active = true
	mirror_timer = MIRROR_DURATION
	score_label.modulate = MIRROR_GATE_COLOR


func _end_mirror_effect() -> void:
	mirror_active = false
	score_label.modulate = score_label_default_color


func _update_camera(delta: float) -> void:
	camera_focus_y = lerp(camera_focus_y, ball_y, clamp(delta * 4.0, 0.0, 1.0))
	camera.position = Vector3(0, camera_focus_y + 2.0, 7.0)
	camera.look_at(Vector3(0, camera_focus_y, 0), Vector3.UP)


func _resolve_gate(index: int) -> void:
	var gate: Dictionary = gates[index]
	if gate["resolved"]:
		return
	gate["resolved"] = true
	gates[index] = gate

	# A tooth placed at local angle (tooth_i * SLOT_ANGLE) ends up at world
	# angle (tooth_i * SLOT_ANGLE - tower_rotation) once TowerRoot's Y
	# rotation is applied (Godot's rotation.y maps local (x,z) -> world
	# angle = local_angle - rotation). The ball sits at world angle 0, so
	# solve for which tooth slot lands there: slot = tower_rotation / SLOT_ANGLE.
	# (Previously negated, which checked the mirror-image slot — the tower
	# could never actually be rotated to a working position.)
	var relative_angle: float = wrapf(tower_rotation, 0.0, TAU)
	var slot: int = int(round(relative_angle / SLOT_ANGLE)) % NUM_TEETH
	var gap_start: int = gate["gap_start"]

	var in_safe_gap := false
	for k in range(GAP_WIDTH):
		if (gap_start + k) % NUM_TEETH == slot:
			in_safe_gap = true
			break

	var in_risk_gap := false
	if gate["dual"]:
		var risk_gap_start: int = gate["risk_gap_start"]
		for k in range(RISK_GAP_WIDTH):
			if (risk_gap_start + k) % NUM_TEETH == slot:
				in_risk_gap = true
				break

	if in_risk_gap:
		score += RISK_GAP_SCORE
		score_label.text = str(score)
		fall_speed = min(2.2 + score * 0.03, 6.0)
		if gate["mirror"]:
			_start_mirror_effect()
	elif in_safe_gap:
		score += GOLDEN_GATE_SCORE if gate["golden"] else 1
		score_label.text = str(score)
		fall_speed = min(2.2 + score * 0.03, 6.0)
		if gate["mirror"]:
			_start_mirror_effect()
	else:
		_trigger_game_over()


func _input(event: InputEvent) -> void:
	if game_over:
		var tapped := false
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			tapped = true
		elif event is InputEventScreenTouch and event.pressed:
			tapped = true
		elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
			tapped = true
		if tapped:
			_start_game()
		return

	var drag_sign: float = -1.0 if mirror_active else 1.0
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		tower_rotation += event.relative.x * DRAG_SENSITIVITY * drag_sign
	elif event is InputEventScreenDrag:
		tower_rotation += event.relative.x * DRAG_SENSITIVITY * drag_sign


func _trigger_game_over() -> void:
	game_over = true
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
