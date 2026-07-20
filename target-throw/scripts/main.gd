extends Node2D

# Target Throw — a Knife Hit-style precision game. The target spins on its
# own (the player never controls its rotation, unlike Spiral Drop where
# the player rotates the tower); tap to throw a knife straight up into it.
# Hit an empty spot = it sticks and rotates along with the target from
# then on. Hit a knife you already stuck = game over.

const TARGET_RADIUS := 130.0
const ANGLE_TOLERANCE := 0.32
const KNIVES_PER_ROUND := 6
const BASE_ROTATION_SPEED := 1.1
const ROTATION_SPEED_GROWTH := 0.12
const SAVE_PATH := "user://targetthrow_highscore.cfg"

const TARGET_COLOR := Color(0.4, 0.3, 0.22, 1.0)
const KNIFE_COLOR := Color(0.8, 0.82, 0.86, 1.0)

# Novelty twist: a rare bonus gem rides the target's rim each round. Land
# a throw near it (without hitting an existing knife) to collect it for a
# big score bump — a collectible-on-target mechanism distinct from the
# gate/round bonuses used elsewhere in the studio.
const GEM_CHANCE_PER_ROUND := 0.5
const GEM_SCORE := 5
const GEM_ANGLE_TOLERANCE := 0.4
const GEM_COLOR := Color(0.2, 0.85, 0.55, 1.0)

# Structural addition: a second, independently-rotating inner ring the
# knife must ALSO clear on every throw. Unlike the outer target (which is
# only "blocked" by knives the player has already stuck), this inner ring
# has a fixed narrow gap and spins on its own — usually the opposite way
# from the outer target — so lining up a throw means tracking two
# independently rotating references at once instead of just dodging your
# own past throws.
const INNER_RADIUS := 55.0
const NUM_INNER_TEETH := 8
const INNER_GAP_TEETH := 2
const INNER_TOOTH_SIZE := Vector2(11.0, 9.0)
const INNER_BASE_ROTATION_SPEED := -1.4
const INNER_ROTATION_SPEED_GROWTH := -0.08
const INNER_TOOTH_COLOR := Color(0.55, 0.58, 0.65, 1.0)

# Novel element: Combo Multiplier. Consecutive sticks within the SAME
# round build a score multiplier (every 2 hits, up to x3); advancing to a
# new round resets it. Since a miss here is instant game over (not a
# strike to survive), the combo's natural reset point is round advance
# rather than a mid-run stumble — a within-round momentum mechanic that
# refreshes every 6 throws.
const COMBO_STEP := 2
const COMBO_MAX_MULT := 3
var combo_hits: int = 0
var combo_multiplier: int = 1

@onready var target: Node2D = $Target
@onready var target_circle: Polygon2D = $Target/TargetCircle
@onready var inner_ring: Node2D = $InnerRing
@onready var score_label: Label = $ScoreLabel
@onready var ready_overlay: ColorRect = $ReadyOverlay
@onready var game_over_overlay: ColorRect = $GameOverOverlay
@onready var game_over_score_label: Label = $GameOverOverlay/GameOverScore

var knives: Array = []
var knives_this_round: int = 0
var round_number: int = 0
var rotation_speed: float = BASE_ROTATION_SPEED
var inner_rotation_speed: float = INNER_BASE_ROTATION_SPEED
var gem_angle: float = -10.0
var gem_node: Node2D = null

var score: int = 0
var high_score: int = 0
var game_over: bool = false
var game_started: bool = false


func _ready() -> void:
	target_circle.polygon = _circle_points(TARGET_RADIUS, 32)
	target_circle.color = TARGET_COLOR
	_build_inner_ring()
	_load_high_score()
	_start_game()


func _build_inner_ring() -> void:
	for c in inner_ring.get_children():
		c.queue_free()
	var slot_angle: float = TAU / NUM_INNER_TEETH
	for tooth_i in range(NUM_INNER_TEETH):
		if tooth_i < INNER_GAP_TEETH:
			continue
		var angle: float = tooth_i * slot_angle
		var tooth := Polygon2D.new()
		var hw: float = INNER_TOOTH_SIZE.x / 2.0
		var hh: float = INNER_TOOTH_SIZE.y / 2.0
		tooth.polygon = PackedVector2Array([Vector2(-hw, -hh), Vector2(hw, -hh), Vector2(hw, hh), Vector2(-hw, hh)])
		tooth.position = Vector2(cos(angle), sin(angle)) * INNER_RADIUS
		tooth.rotation = angle
		tooth.color = INNER_TOOTH_COLOR
		inner_ring.add_child(tooth)


func _circle_points(radius: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a: float = i * TAU / segments
		pts.append(Vector2(cos(a), sin(a)) * radius)
	return pts


func _start_game() -> void:
	for k in knives:
		if is_instance_valid(k):
			k.queue_free()
	knives.clear()
	knives_this_round = 0
	round_number = 0
	combo_hits = 0
	combo_multiplier = 1
	rotation_speed = BASE_ROTATION_SPEED
	inner_rotation_speed = INNER_BASE_ROTATION_SPEED
	target.rotation = 0.0
	inner_ring.rotation = 0.0
	score = 0
	game_over = false
	game_started = false
	score_label.text = "0"
	game_over_overlay.visible = false
	ready_overlay.visible = true
	if is_instance_valid(gem_node):
		gem_node.queue_free()
	gem_node = null
	gem_angle = -10.0
	_maybe_spawn_gem()


func _process(delta: float) -> void:
	if game_over or not game_started:
		return
	target.rotation += rotation_speed * delta
	inner_ring.rotation += inner_rotation_speed * delta


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

	if not game_started:
		game_started = true
		ready_overlay.visible = false
		return
	if game_over:
		_start_game()
		return

	_throw_knife()


func _throw_knife() -> void:
	# The contact point (directly above the target's center, where the
	# thrown knife always lands) is fixed in world space. Converting it to
	# the target's local space via to_local() — rather than hand-deriving
	# the rotation math — means Godot's own transform system guarantees the
	# angle is correct regardless of which way rotation.y composes, instead
	# of risking the same kind of sign error Spiral Drop had.
	var contact_world: Vector2 = target.position + Vector2(0, -TARGET_RADIUS)
	var local_contact: Vector2 = target.to_local(contact_world)
	var new_angle: float = local_contact.angle()

	if not _inner_ring_clear(contact_world):
		_trigger_game_over()
		return

	for k in knives:
		var existing_angle: float = k.position.angle()
		var diff: float = wrapf(new_angle - existing_angle, -PI, PI)
		if abs(diff) < ANGLE_TOLERANCE:
			_trigger_game_over()
			return

	var knife := Polygon2D.new()
	knife.position = local_contact.normalized() * (TARGET_RADIUS - 6.0)
	knife.rotation = new_angle + PI / 2.0
	knife.color = KNIFE_COLOR
	knife.polygon = PackedVector2Array([Vector2(0, -23), Vector2(-6, 7), Vector2(6, 7)])
	target.add_child(knife)
	knives.append(knife)

	combo_hits += 1
	if combo_hits % COMBO_STEP == 0:
		combo_multiplier = min(COMBO_MAX_MULT, combo_multiplier + 1)
	score += 1 * combo_multiplier

	if gem_angle > -5.0:
		var gem_diff: float = wrapf(new_angle - gem_angle, -PI, PI)
		if abs(gem_diff) < GEM_ANGLE_TOLERANCE:
			score += GEM_SCORE
			if is_instance_valid(gem_node):
				gem_node.queue_free()
			gem_node = null
			gem_angle = -10.0

	_update_score_label()
	knives_this_round += 1
	if knives_this_round >= KNIVES_PER_ROUND:
		_advance_round()


func _update_score_label() -> void:
	if combo_multiplier > 1:
		score_label.text = "%d  x%d" % [score, combo_multiplier]
	else:
		score_label.text = str(score)


func _inner_ring_clear(contact_world: Vector2) -> bool:
	var local_contact: Vector2 = inner_ring.to_local(contact_world)
	var angle: float = wrapf(local_contact.angle(), 0.0, TAU)
	var slot_angle: float = TAU / NUM_INNER_TEETH
	var slot: int = int(round(angle / slot_angle)) % NUM_INNER_TEETH
	return slot < INNER_GAP_TEETH


func _maybe_spawn_gem() -> void:
	if randf() >= GEM_CHANCE_PER_ROUND:
		return
	gem_angle = randf() * TAU
	gem_node = Polygon2D.new()
	gem_node.position = Vector2(cos(gem_angle), sin(gem_angle)) * (TARGET_RADIUS - 6.0)
	gem_node.color = GEM_COLOR
	gem_node.polygon = PackedVector2Array([Vector2(0, -14), Vector2(10, 0), Vector2(0, 14), Vector2(-10, 0)])
	target.add_child(gem_node)


func _advance_round() -> void:
	for k in knives:
		k.queue_free()
	knives.clear()
	knives_this_round = 0
	combo_hits = 0
	combo_multiplier = 1
	round_number += 1
	rotation_speed = BASE_ROTATION_SPEED + round_number * ROTATION_SPEED_GROWTH
	inner_rotation_speed = INNER_BASE_ROTATION_SPEED + round_number * INNER_ROTATION_SPEED_GROWTH
	if is_instance_valid(gem_node):
		gem_node.queue_free()
	gem_node = null
	gem_angle = -10.0
	_maybe_spawn_gem()


func _trigger_game_over() -> void:
	game_over = true
	if score > high_score:
		high_score = score
		_save_high_score()
	game_over_score_label.text = "Score: %d  Best: %d" % [score, high_score]
	game_over_overlay.visible = true


func _load_high_score() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		high_score = int(cfg.get_value("scores", "high_score", 0))


func _save_high_score() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("scores", "high_score", high_score)
	cfg.save(SAVE_PATH)
