class_name Flame extends Node3D

signal hazard_hit(hazard: Hazard)

# Top speed is derived every physics tick from CameraController's own
# target_size_for_scale(), NOT a flat constant -- a flat speed made the
# flame "zip around" at match-scale (3 m/s across a ~0.7m view crosses the
# whole visible world in under a quarter second) while feeling sluggish at
# large scale once the world around it is hundreds of meters wide. Deriving
# speed from the same formula that drives camera framing means the flame
# always crosses roughly the same FRACTION of its own visible world per
# second, regardless of how big it's grown -- see camera_controller.gd.
@export var view_crossing_seconds: float = 2.2
# Time to reach full speed from a stop, and to fully decelerate -- kept
# constant (not itself scale-derived) so controls feel equally responsive
# at every scale even though the top speed they ramp to varies hugely.
@export var accel_ramp_time: float = 0.35
@export var mesh_scale_tween_time: float = 0.35

# Ignite/jump reach use a base-reach-plus-growth formula, NOT pure
# proportional scaling with flame_scale (which is now a real-world size in
# meters, per growth_controller.gd -- a literal 2cm matchstick flame scaled
# purely proportionally could never reach a blade of grass a few cm away).
# The base term keeps interaction workable at match-scale; the growth term
# still gives a real sense of reach increasing as the flame grows.
@export var ignite_base_reach: float = 0.1
@export var ignite_reach_growth: float = 0.5

@export var jump_base_radius: float = 0.15
@export var jump_radius_growth: float = 2.0
@export var jump_forward_cone_deg: float = 60.0
@export var jump_duration: float = 0.35
@export var jump_height: float = 0.6
@export var jump_fallback_base: float = 0.15
@export var jump_fallback_growth: float = 1.0

# Brief-length invulnerability after a hazard hit so standing inside one
# wandering hazard's contact radius (or overlapping several at once) doesn't
# shred Growth Points every single physics tick -- one hit registers, then a
# short grace window before the next one can land.
@export var hit_invuln_duration: float = 1.0

@onready var mesh: Node3D = $Mesh
@onready var ignite_area: Area3D = $IgniteArea
@onready var ignite_shape: CollisionShape3D = $IgniteArea/IgniteShape

# Single source of truth for the flame's growth scale is GrowthController;
# this is kept in sync via set_scale_factor() (called from grow_tick) so
# movement/camera/jump code all read the same value. Real-world meters, not
# an abstract multiplier -- see growth_controller.gd's BAND_TABLE comment.
var scale_factor: float = 0.02

var move_direction: Vector3 = Vector3.ZERO
# Not underscore-prefixed -- movement_trail.gd (and later, jump feel/animation
# code) reads this directly to know whether/how fast the flame is moving.
var velocity: Vector3 = Vector3.ZERO
var _scale_tween: Tween

var _last_heading: Vector3 = Vector3.FORWARD
var _is_jumping: bool = false
var _jump_tween: Tween

# Structure Fuel's health only drains while contact is actively held (see
# structure_fuel.gd::drain) -- tracked here rather than one-shot ignite()
# like Fuel, since Area3D only fires entered/exited, not "still touching".
var _touching_structures: Array[StructureFuel] = []
var _hit_invuln_timer: float = 0.0


func _ready() -> void:
	# IgniteArea is a direct child of Flame (not Mesh) so its radius is
	# explicitly maintained via _update_ignite_radius() using the
	# base-reach-plus-growth formula above, rather than automatically
	# inheriting Mesh's own visual scale (which would make a match-scale
	# flame's reach shrink to near-zero along with its tiny visual size).
	ignite_area.area_entered.connect(_on_ignite_area_entered)
	ignite_area.area_exited.connect(_on_ignite_area_exited)
	_update_ignite_radius()


func _on_ignite_area_entered(area: Area3D) -> void:
	var target: Node = area.get_parent()
	if target is Fuel:
		if not (target as Fuel).is_ignited():
			(target as Fuel).ignite()
	elif target is StructureFuel:
		var s := target as StructureFuel
		if not s.is_fully_burned():
			if not _touching_structures.has(s):
				_touching_structures.append(s)
			s.begin_contact()
	elif target is Hazard:
		_try_take_hazard_hit(target as Hazard)


func _on_ignite_area_exited(area: Area3D) -> void:
	var target: Node = area.get_parent()
	if target is StructureFuel:
		_touching_structures.erase(target)


func _try_take_hazard_hit(hazard: Hazard) -> void:
	if _hit_invuln_timer > 0.0:
		return
	_hit_invuln_timer = hit_invuln_duration
	hazard_hit.emit(hazard)


func _physics_process(delta: float) -> void:
	_drain_touching_structures(delta)
	if _hit_invuln_timer > 0.0:
		_hit_invuln_timer -= delta
	if _is_jumping:
		return
	var speed: float = current_move_speed()
	var accel: float = speed / accel_ramp_time if accel_ramp_time > 0.0 else speed
	var target_velocity: Vector3 = move_direction * speed
	velocity = velocity.move_toward(target_velocity, accel * delta)
	if move_direction.length_squared() > 0.01:
		_last_heading = move_direction.normalized()
	if velocity.length_squared() < 0.0001:
		return
	position += velocity * delta


# Top speed proportional to the camera's own view span at the current scale
# (see the view_crossing_seconds comment above) -- public so movement_trail.gd
# or future feel/animation code can reuse the same value instead of
# re-deriving it.
func current_move_speed() -> float:
	return CameraController.target_size_for_scale(scale_factor) / view_crossing_seconds


# Draining happens every physics tick regardless of jump/movement state --
# you can stand still (or mid-arc through a jump) and still be cooking a
# Structure Fuel you're overlapping.
func _drain_touching_structures(delta: float) -> void:
	if _touching_structures.is_empty():
		return
	var still_touching: Array[StructureFuel] = []
	for s in _touching_structures:
		if not is_instance_valid(s) or s.is_fully_burned():
			continue
		s.drain(delta)
		still_touching.append(s)
	_touching_structures = still_touching


func set_move_direction(dir: Vector3) -> void:
	move_direction = dir


# Double-tap jump: launches along an arc toward the nearest not-yet-ignited
# Fuel within jump radius, in a forward cone of the current heading. If
# nothing qualifies, still performs a short fixed hop in that heading -- the
# brief is explicit that this should never be a no-op whiff, even at
# match-scale where the radius barely reaches anything yet.
func jump() -> void:
	if _is_jumping:
		return
	var heading: Vector3 = _last_heading
	var radius: float = jump_base_radius + scale_factor * jump_radius_growth
	var target: Node3D = _find_jump_target(radius, heading)
	var fallback_distance: float = jump_fallback_base + scale_factor * jump_fallback_growth
	var target_pos: Vector3 = target.global_position if target else global_position + heading * fallback_distance
	_is_jumping = true
	_play_jump_arc(target_pos)


func _find_jump_target(radius: float, heading: Vector3) -> Node3D:
	var space_state := get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), global_position)
	query.collision_mask = Fuel.FUEL_COLLISION_LAYER
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var results: Array = space_state.intersect_shape(query, 32)

	var cos_threshold: float = cos(deg_to_rad(jump_forward_cone_deg))
	var best: Node3D = null
	var best_dist: float = INF
	for r: Dictionary in results:
		var area: Area3D = r.collider
		var target: Node = area.get_parent()
		if not _is_eligible_jump_target(target):
			continue
		var to_target: Vector3 = (target as Node3D).global_position - global_position
		var dist: float = to_target.length()
		if dist < 0.01:
			continue
		if (to_target / dist).dot(heading) < cos_threshold:
			continue
		if dist < best_dist:
			best_dist = dist
			best = target
	return best


func _is_eligible_jump_target(target: Node) -> bool:
	if target is Fuel:
		return not (target as Fuel).is_ignited()
	if target is StructureFuel:
		return not (target as StructureFuel).is_fully_burned()
	return false


func _play_jump_arc(target_pos: Vector3) -> void:
	var start_pos: Vector3 = global_position
	if _jump_tween:
		_jump_tween.kill()
	_jump_tween = create_tween()
	_jump_tween.tween_method(_apply_jump_frame.bind(start_pos, target_pos), 0.0, 1.0, jump_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_jump_tween.tween_callback(func() -> void: _is_jumping = false)


func _apply_jump_frame(t: float, start_pos: Vector3, target_pos: Vector3) -> void:
	var flat: Vector3 = start_pos.lerp(target_pos, t)
	flat.y = start_pos.y + sin(t * PI) * jump_height
	global_position = flat


func set_scale_factor(new_scale: float) -> void:
	scale_factor = new_scale
	_update_ignite_radius()
	if not mesh:
		return
	if _scale_tween:
		_scale_tween.kill()
	_scale_tween = create_tween()
	_scale_tween.set_parallel(true)
	_scale_tween.tween_property(mesh, "scale", Vector3.ONE * new_scale, mesh_scale_tween_time)
	# Mesh's base BoxMesh is 1x1x1 centered on its own origin, so it must sit
	# at half its current (scaled) height to stay grounded instead of
	# floating or clipping into the ground as new_scale changes.
	_scale_tween.tween_property(mesh, "position:y", new_scale * 0.5, mesh_scale_tween_time)


func _update_ignite_radius() -> void:
	if not ignite_shape or not (ignite_shape.shape is SphereShape3D):
		return
	(ignite_shape.shape as SphereShape3D).radius = ignite_base_reach + scale_factor * ignite_reach_growth
