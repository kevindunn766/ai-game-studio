class_name Hazard extends Node3D

const HAZARD_COLLISION_LAYER := 4  # distinct from Fuel/StructureFuel's layer 2

@export var hazard_tier: String = ""
@export var shrink_amount: float = 1.5
@export var move_speed: float = 0.8
@export var wander_radius: float = 1.0
@export var wander_pause_min: float = 0.4
@export var wander_pause_max: float = 1.2

# Set by PropManager at spawn time (kept for parity with Fuel/StructureFuel's
# cell_key, though hazards are never marked "burned" -- they persist and
# simply respawn/despawn with the normal streaming footprint).
var cell_key: Vector3i = Vector3i.ZERO

var _visual: Node3D
var _origin: Vector3
var _target: Vector3
var _pause_timer: float = 0.0
var _rng := RandomNumberGenerator.new()


# Same _visual-wrapper pattern as fuel.gd/structure_fuel.gd -- self owns
# HazardArea's CollisionShape3D directly, so pop-in/despawn scale tweens must
# never target self (Godot errors on a zero-scale ancestor's basis).
func _ready() -> void:
	_rng.randomize()
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)

	var area := Area3D.new()
	area.name = "HazardArea"
	area.collision_layer = HAZARD_COLLISION_LAYER
	area.collision_mask = 0
	area.monitoring = false  # only needs to be detected, never detects itself
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.12
	shape.shape = sphere
	area.add_child(shape)
	add_child(area)

	_origin = position
	_pick_new_target()


func set_visual(node: Node3D) -> void:
	_visual.add_child(node)


func play_pop_in() -> void:
	_visual.scale = Vector3.ZERO
	var tw := create_tween()
	tw.tween_property(_visual, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func play_despawn() -> void:
	var tw := create_tween()
	tw.tween_property(_visual, "scale", Vector3.ZERO, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


# Grey-box "AI-lite" wander: pick a random point within wander_radius of the
# spawn origin, walk to it, pause, repeat -- same "greedy heuristic, no real
# pathfinding" spirit as this studio's snake-3d enemy AI, scaled down since
# these are small ambient hazards, not a core antagonist.
func _physics_process(delta: float) -> void:
	if _pause_timer > 0.0:
		_pause_timer -= delta
		return
	var to_target: Vector3 = _target - position
	var dist: float = to_target.length()
	if dist < 0.05:
		_pause_timer = _rng.randf_range(wander_pause_min, wander_pause_max)
		_pick_new_target()
		return
	var step: Vector3 = (to_target / dist) * move_speed * delta
	if step.length() > dist:
		position = _target
	else:
		position += step
		_face_direction(to_target)


func _face_direction(dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		return
	_visual.rotation.y = atan2(flat.x, flat.z)


func _pick_new_target() -> void:
	var angle: float = _rng.randf_range(0.0, TAU)
	var r: float = _rng.randf_range(0.2, wander_radius)
	_target = _origin + Vector3(cos(angle) * r, 0.0, sin(angle) * r)
