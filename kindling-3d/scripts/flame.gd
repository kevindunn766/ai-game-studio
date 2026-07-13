class_name Flame extends Node3D

signal hazard_hit(hazard: Hazard)

# Top speed is inversely proportional to scale_factor -- a small flame moves
# fast, a large flame moves slow. current_move_speed() = move_speed_constant
# / scale_factor.
@export var move_speed_constant: float = 2.0
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

# Climb & leap (Milestone 4): jumping onto a still-standing StructureFuel
# (shed wall, house, city block) arcs proportionally higher than a flat
# fuel-to-fuel hop, reading as "crawling up the vertical surface" rather than
# a uniform bounce, per the brief's Locomotion & Fire Physics section. Always
# lands back at the target's own (ground-level) position -- a persistent
# "stay attached to the wall" movement state is a real state machine this
# grey-box pass doesn't build; see DESIGN.md's Milestone 4 notes.
@export var climb_height_fraction: float = 0.5

# Delayed mass-follow (Milestone 4): a second visual node trails the flame's
# actual position by a short time delay, sampled from a recorded position
# history -- same underlying idea as snake-3d's segment-follows-head, just
# continuous instead of grid-discrete since Kindling free-roams. Gives the
# fire body visible weight/stretch during fast repositioning (climb/leap
# arcs especially), per the brief.
@export var mass_follow_delay_seconds: float = 0.18
@export var mass_follow_lerp_speed: float = 10.0
@export var body_scale_fraction: float = 0.85

# Brief-length invulnerability after a hazard hit so standing inside one
# wandering hazard's contact radius (or overlapping several at once) doesn't
# shred Growth Points every single physics tick -- one hit registers, then a
# short grace window before the next one can land.
@export var hit_invuln_duration: float = 1.0

@onready var mesh: Node3D = $Mesh
@onready var ignite_area: Area3D = $IgniteArea
@onready var ignite_shape: CollisionShape3D = $IgniteArea/IgniteShape
@onready var body: Node3D = $Body
@onready var body_mesh: MeshInstance3D = $Body/BodyMesh

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

# Oldest-first list of {t: float (seconds, Time.get_ticks_msec()/1000.0),
# pos: Vector3}. Trimmed to MASS_HISTORY_MAX_SECONDS -- generous enough to
# always cover mass_follow_delay_seconds even during a slow long jump arc.
var _position_history: Array[Dictionary] = []
const MASS_HISTORY_MAX_SECONDS: float = 1.2

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
	_record_position_history()
	_update_mass_follow(delta)
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


# Public so movement_trail.gd or future feel/animation code can reuse the
# same value instead of re-deriving it.
func current_move_speed() -> float:
	return move_speed_constant / scale_factor


func _record_position_history() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	_position_history.append({"t": now, "pos": position})
	while _position_history.size() > 2 and now - (_position_history[0].t as float) > MASS_HISTORY_MAX_SECONDS:
		_position_history.pop_front()


func _update_mass_follow(delta: float) -> void:
	if not body:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var target: Vector3 = sample_history(_position_history, now - mass_follow_delay_seconds) if not _position_history.is_empty() else position
	body.global_position = body.global_position.lerp(target, clampf(delta * mass_follow_lerp_speed, 0.0, 1.0))


# Pure/testable (no live scene tree needed): linearly interpolates a
# recorded {t, pos} history buffer to the position Flame was at absolute
# time `t`. Static so tests/test_flame_locomotion.gd can exercise it
# directly, same convention as camera_controller.gd's target_size_for_scale.
static func sample_history(history: Array[Dictionary], t: float) -> Vector3:
	if history.is_empty():
		return Vector3.ZERO
	if t <= (history[0].t as float):
		return history[0].pos
	for i in range(history.size() - 1):
		var a: Dictionary = history[i]
		var b: Dictionary = history[i + 1]
		if t >= (a.t as float) and t <= (b.t as float):
			var span: float = (b.t as float) - (a.t as float)
			var frac: float = (t - (a.t as float)) / span if span > 0.0001 else 0.0
			return (a.pos as Vector3).lerp(b.pos as Vector3, frac)
	return history[-1].pos


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
	var target_height: float = (target as StructureFuel).height if target is StructureFuel else 0.0
	var arc_height: float = climb_arc_height(jump_height, target_height, climb_height_fraction)
	_is_jumping = true
	_play_jump_arc(target_pos, arc_height)


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


func _play_jump_arc(target_pos: Vector3, arc_height: float) -> void:
	var start_pos: Vector3 = global_position
	if _jump_tween:
		_jump_tween.kill()
	_jump_tween = create_tween()
	_jump_tween.tween_method(_apply_jump_frame.bind(start_pos, target_pos, arc_height), 0.0, 1.0, jump_duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_jump_tween.tween_callback(func() -> void: _is_jumping = false)


func _apply_jump_frame(t: float, start_pos: Vector3, target_pos: Vector3, arc_height: float) -> void:
	var flat: Vector3 = start_pos.lerp(target_pos, t)
	flat.y = start_pos.y + sin(t * PI) * arc_height
	global_position = flat


# Pure/testable: a flat fuel-to-fuel hop keeps the normal jump_height; a
# not-yet-burned StructureFuel with real height (shed wall, house, city
# block) arcs proportionally higher, reading as climbing its vertical
# surface rather than a uniform bounce.
static func climb_arc_height(base_jump_height: float, target_height: float, climb_fraction: float) -> float:
	if target_height <= 0.0:
		return base_jump_height
	return base_jump_height + target_height * climb_fraction


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
	if body_mesh:
		# Trailing "bulk" reads slightly smaller than the leading edge
		# (body_scale_fraction) so the two visually read as one fire with a
		# hot tip, not two identical stacked boxes.
		_scale_tween.tween_property(body_mesh, "scale", Vector3.ONE * new_scale * body_scale_fraction, mesh_scale_tween_time)
		_scale_tween.tween_property(body_mesh, "position:y", new_scale * 0.5, mesh_scale_tween_time)


func _update_ignite_radius() -> void:
	if not ignite_shape or not (ignite_shape.shape is SphereShape3D):
		return
	(ignite_shape.shape as SphereShape3D).radius = ignite_base_reach + scale_factor * ignite_reach_growth
