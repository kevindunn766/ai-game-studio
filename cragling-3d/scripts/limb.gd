class_name Limb
extends Node3D

# One arm or leg, solved as a classic 2-bone analytic IK chain (law of
# cosines) with fixed segment lengths, a terminal hand/foot block, and
# real range-of-motion limits at the elbow/knee (this script) plus the
# shoulder/hip (Climber._outside_joint_cone, since that one depends on
# where other limbs and the goal are, which only the planner knows).
#
# Researched ROM reference (standard goniometry/kinesiology norms, e.g.
# AAOS clinical ranges -- approximated and simplified for a grey-box
# rig, not a medical rig):
#   Elbow flexion: ~145-150 deg of travel from full extension, i.e. the
#     interior angle at the elbow ranges from 180 deg (straight) down to
#     roughly 30-35 deg at full flexion. No hyperextension past 180 deg
#     for a healthy joint.
#   Knee flexion: ~135-150 deg of travel, interior angle down to roughly
#     40 deg at full active flexion (a bit less extreme than the elbow --
#     climbing rarely folds a knee as tightly as an elbow can fold).
#   Wrist flexion/extension: ~80 deg / ~70 deg from neutral (roughly
#     150 deg combined sweep). Modeled here as a single symmetric cap
#     since the hand only needs to bend one way (toward the grip
#     surface), not a true flex/extend pair.
#   Ankle dorsi/plantarflexion: ~20 deg / ~50 deg from neutral (~70 deg
#     combined, notably less mobile than the wrist), same single-cap
#     simplification as the wrist.
# These four numbers turn into two things below: the elbow/knee number
# sets MIN_REACH_DIST (via the inverse law of cosines, so the limb
# geometrically cannot fold tighter than the real joint could), and the
# wrist/ankle number caps how far the terminal hand/foot block can bend
# away from "continuing the forearm/shin line" to lie flat against the
# grip surface.

const UPPER_LENGTH: float = 0.7
const LOWER_LENGTH: float = 0.7
const SEGMENT_COUNT: int = 6
const LIMB_THICKNESS: float = 0.14
const REACH_DURATION: float = 0.22
const MAX_STRAIGHT_SLACK: float = 0.02 # keeps the solve just shy of dead-straight, avoids a singular/locked pose

const ELBOW_MIN_ANGLE_DEG: float = 30.0
const KNEE_MIN_ANGLE_DEG: float = 40.0
const WRIST_MAX_BEND_DEG: float = 70.0
const ANKLE_MAX_BEND_DEG: float = 40.0

const HAND_LENGTH: float = 0.16
const HAND_THICKNESS: float = 0.15

const JOINT_SEPARATION_RADIUS: float = 0.18 # min distance kept between this limb's elbow/knee and any other limb's

@export var side_sign: float = 1.0
@export var is_leg: bool = false

# Set externally by Climber right after all 4 Limb nodes exist (see
# climber.gd::_wire_limb_collision_refs), not exported -- these are runtime
# scene-graph links, not tunable/serializable properties.
var sibling_limbs: Array[Limb] = []
var body_avoid_points: Array = [] # each entry: {"node": Node3D, "radius": float}

# This limb's own anchor X-offset from the body's actual center (Climber's
# LIMB_OFFSETS[this limb].x, e.g. -0.16 for left_leg), wired in by
# _wire_limb_collision_refs. Needed because this script's own local X=0 is
# at the *anchor's* position, not the body's midline -- see _clamp_midline.
var anchor_offset_x: float = 0.0

# Last frame's elbow/knee world position, read by sibling limbs during
# their own separation check (see _resolve_sibling_separation) -- one
# frame stale by design, not same-frame-synchronized. Cheap and avoids
# needing Climber to orchestrate a strict two-pass update order across
# all 4 limbs every frame; at 60fps a 1-frame lag is imperceptible.
var last_elbow_global: Vector3 = Vector3.ZERO

var current_hand_global: Vector3 = Vector3.ZERO
var _wall_normal_global: Vector3 = Vector3(0, 0, 1)
var _curve := Curve3D.new()
var _segments: Array[MeshInstance3D] = []
var _segment_mesh: BoxMesh
var _hand_mesh: MeshInstance3D
var _hand_box: BoxMesh
var _min_reach_dist: float


func _ready() -> void:
	var min_angle_deg: float = KNEE_MIN_ANGLE_DEG if is_leg else ELBOW_MIN_ANGLE_DEG
	var min_angle_rad := deg_to_rad(min_angle_deg)
	_min_reach_dist = sqrt(UPPER_LENGTH * UPPER_LENGTH + LOWER_LENGTH * LOWER_LENGTH - 2.0 * UPPER_LENGTH * LOWER_LENGTH * cos(min_angle_rad))

	_curve.bake_interval = 0.05
	_segment_mesh = BoxMesh.new()
	_segment_mesh.size = Vector3(LIMB_THICKNESS, 1.0, LIMB_THICKNESS)
	for i in SEGMENT_COUNT:
		var seg := MeshInstance3D.new()
		seg.mesh = _segment_mesh
		add_child(seg)
		_segments.append(seg)

	_hand_box = BoxMesh.new()
	_hand_box.size = Vector3(HAND_THICKNESS, HAND_LENGTH, HAND_THICKNESS * 0.7)
	_hand_mesh = MeshInstance3D.new()
	_hand_mesh.mesh = _hand_box
	add_child(_hand_mesh)


func set_initial_hand(global_pos: Vector3, normal: Vector3) -> void:
	current_hand_global = global_pos
	_wall_normal_global = normal
	_rebuild_visual()


func reach_to(target_global: Vector3, normal: Vector3, duration: float = REACH_DURATION) -> void:
	var start := current_hand_global
	_wall_normal_global = normal
	var tw := create_tween()
	tw.tween_method(_apply_hand_progress.bind(start, target_global), 0.0, 1.0, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	current_hand_global = target_global


func _apply_hand_progress(t: float, start: Vector3, target: Vector3) -> void:
	current_hand_global = start.lerp(target, t)


func _process(_delta: float) -> void:
	_rebuild_visual()


func _rebuild_visual() -> void:
	var anchor_local := Vector3.ZERO
	var hand_local := to_local(current_hand_global)
	var normal_local := global_transform.basis.inverse() * _wall_normal_global
	if normal_local != Vector3.ZERO:
		normal_local = normal_local.normalized()

	var elbow := _solve_elbow(anchor_local, hand_local, normal_local)

	_curve.clear_points()
	_curve.add_point(anchor_local, Vector3.ZERO, (elbow - anchor_local) * 0.5)
	_curve.add_point(elbow, (anchor_local - elbow) * 0.3, (hand_local - elbow) * 0.3)
	_curve.add_point(hand_local, (elbow - hand_local) * 0.5, Vector3.ZERO)

	var baked_len := _curve.get_baked_length()
	if baked_len <= 0.001:
		for seg in _segments:
			seg.visible = false
		_hand_mesh.visible = false
		return

	var points: Array[Vector3] = []
	for i in range(SEGMENT_COUNT + 1):
		points.append(_curve.sample_baked(float(i) / float(SEGMENT_COUNT) * baked_len))

	for i in SEGMENT_COUNT:
		var p1: Vector3 = points[i]
		var p2: Vector3 = points[i + 1]
		var seg_vec := p2 - p1
		var seg_len := seg_vec.length()
		var seg := _segments[i]
		seg.visible = true
		seg.position = (p1 + p2) * 0.5
		if seg_len > 0.0001:
			seg.quaternion = _stable_look_basis(seg_vec, Vector3.UP).get_rotation_quaternion()
		seg.scale = Vector3(1.0, max(seg_len, 0.001), 1.0)

	_place_hand(elbow, hand_local, normal_local)


# The hand/foot doesn't need its own IK target -- it just continues the
# forearm/shin's final direction, bent (within WRIST/ANKLE_MAX_BEND_DEG)
# toward lying flat against the grip surface, like a palm or sole
# pressing onto the hold rather than dangling in line with the arm.
func _place_hand(elbow: Vector3, hand_local: Vector3, normal_local: Vector3) -> void:
	_hand_mesh.visible = true
	var forearm_dir := (hand_local - elbow)
	if forearm_dir.length() < 0.0001:
		forearm_dir = Vector3.DOWN
	forearm_dir = forearm_dir.normalized()
	var surface_dir := -normal_local if normal_local != Vector3.ZERO else forearm_dir
	var max_bend_deg: float = ANKLE_MAX_BEND_DEG if is_leg else WRIST_MAX_BEND_DEG
	var hand_dir := _rotate_toward(forearm_dir, surface_dir, deg_to_rad(max_bend_deg))
	_hand_mesh.position = hand_local - hand_dir * (HAND_LENGTH * 0.5)
	var hand_up_hint := normal_local if normal_local != Vector3.ZERO else Vector3.UP
	_hand_mesh.quaternion = _stable_look_basis(hand_dir, hand_up_hint).get_rotation_quaternion()


# Rotates `from` toward `to`, capped at `max_angle` radians -- used to
# bend the hand/foot toward the grip surface without exceeding real
# wrist/ankle range of motion.
static func _rotate_toward(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var f := from.normalized()
	var t := to.normalized()
	var cos_a: float = clamp(f.dot(t), -1.0, 1.0)
	var angle := acos(cos_a)
	if angle <= max_angle or angle < 0.0001:
		return t
	var axis := f.cross(t)
	if axis.length() < 0.0001:
		return f
	axis = axis.normalized()
	return f.rotated(axis, max_angle)


# Builds an orthonormal basis whose Y axis is `dir` (matching this
# script's Y-long-axis boxes), used instead of Godot's
# Quaternion(arc_from, arc_to) shortest-arc constructor.
#
# That constructor is a documented source of exactly the kind of bug a
# single-frame position check can't catch: it rotates from a single
# FIXED reference axis (we were using Vector3.UP), and that construction
# is degenerate whenever the target direction passes near-parallel or
# antiparallel to that fixed reference -- Godot's own tracker has this
# logged (angles under ~0.0045 rad silently produce no rotation;
# antiparallel cases hit a zero cross-product with an arbitrarily-picked
# axis). A limb whose direction routinely swings through "straight down"
# -- which is the common case for a leg reaching a lower foothold -- was
# hitting exactly that case, risking a segment popping to a wrong or
# frame-inconsistent orientation with no error and no wrong *position*,
# since the bug is in the rotation, not the point math.
#
# The fix follows the standard technique for this (see e.g. how
# Basis.looking_at avoids the same trap): derive the perpendicular axes
# from a cross product against an up-hint, with a fallback chain (hint,
# then RIGHT, then FORWARD) so there's always a valid non-degenerate
# choice regardless of which way `dir` points -- no single fixed
# reference the direction can collide with.
static func _stable_look_basis(dir: Vector3, up_hint: Vector3) -> Basis:
	var y := dir.normalized()
	var x := up_hint.cross(y)
	if x.length() < 0.01:
		x = Vector3.RIGHT.cross(y)
	if x.length() < 0.01:
		x = Vector3.FORWARD.cross(y)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


# Law-of-cosines 2-bone IK. `dist` (anchor to hand) is clamped to
# [_min_reach_dist, UPPER_LENGTH + LOWER_LENGTH - slack] before solving --
# the lower bound comes from ELBOW/KNEE_MIN_ANGLE_DEG above (the real
# joint's max-fold angle, via the inverse law of cosines), so the elbow
# geometrically cannot fold tighter than a real elbow/knee could, and the
# upper bound keeps the limb from telescoping past its own length.
# `normal` (+ a per-side offset) only picks which side the elbow bends
# toward; it never affects how far the limb can reach.
#
# The bend biases toward the FRONT of the figure (-normal, i.e. toward
# the wall the climber faces), not away from it. This matters most for
# the knee: a real knee is a one-way hinge whose bend point (the kneecap
# side) sits on the front of the leg, with the shin folding backward
# behind it -- biasing away from the wall put the knee on the wrong
# side entirely. Applying the same front bias to the elbow keeps both
# joints visually consistent, per feedback that arms and legs should
# share one "bends toward the front" rule rather than each doing its
# own thing.
func _solve_elbow(anchor: Vector3, hand: Vector3, normal: Vector3) -> Vector3:
	var to_hand := hand - anchor
	var raw_dist := to_hand.length()
	var max_dist := UPPER_LENGTH + LOWER_LENGTH - MAX_STRAIGHT_SLACK
	var dist: float = clamp(raw_dist, _min_reach_dist, max_dist)
	var dir := to_hand.normalized() if raw_dist > 0.0001 else Vector3.FORWARD

	var bend_hint := -normal + Vector3.RIGHT * side_sign * 0.5
	var bend_axis := _perpendicular_component(bend_hint, dir)
	if bend_axis.length() < 0.001:
		bend_axis = _perpendicular_component(Vector3.UP, dir)
	if bend_axis.length() < 0.001:
		bend_axis = _perpendicular_component(Vector3.RIGHT, dir)
	bend_axis = bend_axis.normalized() if bend_axis.length() > 0.001 else Vector3.UP

	var cos_theta: float = clamp((UPPER_LENGTH * UPPER_LENGTH + dist * dist - LOWER_LENGTH * LOWER_LENGTH) / (2.0 * UPPER_LENGTH * dist), -1.0, 1.0)
	var theta := acos(cos_theta)
	var elbow_dir := (dir * cos(theta) + bend_axis * sin(theta)).normalized()
	var elbow_local := anchor + elbow_dir * UPPER_LENGTH

	if is_leg:
		elbow_local = _clamp_midline(elbow_local)

	# Every correction below works in global space so it's directly
	# comparable against sibling limbs (different local frames) and the
	# body (a different node entirely) -- converted back to local once at
	# the end, rather than round-tripping per check.
	var anchor_global := to_global(anchor)
	var elbow_global := to_global(elbow_local)
	elbow_global = _resolve_body_avoidance(elbow_global)
	elbow_global = _resolve_sibling_separation(elbow_global)
	elbow_global = _clamp_to_wall(anchor_global, elbow_global)
	last_elbow_global = elbow_global
	return to_local(elbow_global)


static func _perpendicular_component(v: Vector3, dir: Vector3) -> Vector3:
	return v - dir * dir.dot(v)


# Keeps the knee from ever swinging across the body's own midline (e.g. the
# left knee bending out past the body's centerline into the right leg's
# territory) -- a fundamental anatomical constraint on the bend point
# itself, distinct from Climber._crosses_body, which only gates which GRIP
# a foot is allowed to target and says nothing about where the knee bends
# on the way there.
#
# This script's local X=0 is at this limb's own anchor, which already sits
# anchor_offset_x away from the body's true center (e.g. -0.16 for
# left_leg) -- so the midline, expressed in this limb's own local frame, is
# at local X = -anchor_offset_x, not at 0. side_sign says which way is
# "wrong": a left limb (side_sign < 0) must not push local X higher than
# the midline; a right limb must not push it lower.
func _clamp_midline(elbow_local: Vector3) -> Vector3:
	var midline_x := -anchor_offset_x
	var corrected := elbow_local
	if side_sign < 0.0:
		corrected.x = min(corrected.x, midline_x)
	else:
		corrected.x = max(corrected.x, midline_x)
	return corrected


# Cheap sphere-vs-point push-out against the torso boxes (Ribs/Hips,
# passed in as bounding-sphere approximations by Climber) -- not a
# physics query, just a couple of distance checks per limb per frame, per
# "just the points, not the whole limb, keep it cheap."
func _resolve_body_avoidance(pos: Vector3) -> Vector3:
	var corrected := pos
	for entry in body_avoid_points:
		var node: Node3D = entry["node"]
		if not node:
			continue
		var center: Vector3 = node.global_position
		var radius: float = entry["radius"]
		var diff := corrected - center
		var dist := diff.length()
		if dist < radius and dist > 0.0001:
			corrected = center + diff.normalized() * radius
	return corrected


# Cheap sphere-vs-sphere push-apart against the other 3 limbs' elbow/knee
# points (their last-frame position, see last_elbow_global) -- same
# "just the points" cost profile as body avoidance above, at most 3
# distance checks.
func _resolve_sibling_separation(pos: Vector3) -> Vector3:
	var corrected := pos
	for other in sibling_limbs:
		if not other or other == self:
			continue
		var other_pos: Vector3 = other.last_elbow_global
		var diff := corrected - other_pos
		var dist := diff.length()
		if dist < JOINT_SEPARATION_RADIUS and dist > 0.0001:
			corrected = other_pos + diff.normalized() * JOINT_SEPARATION_RADIUS
	return corrected


# Raycasts from the anchor toward the elbow/knee's ideal position, using the
# same physics query technique as tap_input.gd's tap raycast -- a real
# collision check against the wall's actual CollisionShape3D, not a
# hardcoded "assume the wall is a flat plane" shortcut. If that segment
# would pass through the wall, the joint is pulled back to just in front of
# the real hit surface (offset along the hit normal by WALL_CLEARANCE) so
# the knee/elbow can never render embedded in solid rock, and this keeps
# working once walls stop being flat boxes (sculpted biome geometry later).
# Runs last so the wall constraint always has final say over the softer
# body/sibling nudges above.
const WALL_CLEARANCE: float = 0.08

func _clamp_to_wall(from: Vector3, to: Vector3) -> Vector3:
	if from.distance_to(to) < 0.001:
		return to
	var space_state := get_world_3d().direct_space_state
	if not space_state:
		return to
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var result := space_state.intersect_ray(query)
	if not result.has("position"):
		return to
	var hit_pos: Vector3 = result["position"]
	var hit_normal: Vector3 = result["normal"]
	return hit_pos + hit_normal * WALL_CLEARANCE
