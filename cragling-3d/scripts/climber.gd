class_name Climber
extends Node3D

# Tap-to-follow controller. On a tap, greedily plans a sequence of single-
# limb reaches toward the tapped grip (always 3 points of contact -- only
# one limb moves at a time), then executes that plan as a queue of
# animated reaches. Logical grip claims (held_grip) update the instant a
# step starts so path-planning never double-books a grip mid-flight;
# torso weight-shift (stable_grip) only updates once a limb has actually
# landed -- same "logical state instant, visual state interpolated"
# split used for the camera-follow fix in snake-3d.
#
# The torso is two boxes (Ribs, Hips) linked by a spline (WaistSpline),
# not one rigid block -- arms hang off Ribs, legs off Hips. Both still
# move/reorient together via Torso's own position+facing lerp below;
# only a small extra twist (see _process) rotates Ribs toward whichever
# arm led most recently, with Hips countering slightly the other way,
# mimicking a real climber's shoulder/hip opposition.

const LIMB_NAMES := ["left_arm", "right_arm", "left_leg", "right_leg"]

const LIMB_NODE_NAMES := {
	"left_arm": "LeftArm",
	"right_arm": "RightArm",
	"left_leg": "LeftLeg",
	"right_leg": "RightLeg",
}

# Which of the two torso boxes each limb is actually parented under.
const LIMB_PARENT_IS_RIBS := {
	"left_arm": true,
	"right_arm": true,
	"left_leg": false,
	"right_leg": false,
}

# Anchor offsets for path-planning purposes only, relative to Torso (not
# Ribs/Hips individually) -- deliberately ignores the subtle rib/hip
# twist, which is a cosmetic few degrees and not worth the complexity of
# simulating during planning. The Limb nodes' real, live positions (used
# for rendering) come from the scene tree under Ribs/Hips instead.
const LIMB_OFFSETS := {
	"left_arm": Vector3(-0.3, 0.26, -0.05),
	"right_arm": Vector3(0.3, 0.26, -0.05),
	"left_leg": Vector3(-0.16, -0.32, -0.05),
	"right_leg": Vector3(0.16, -0.32, -0.05),
}

# +1 = right side, -1 = left side -- used only to stop a limb from being
# planned across the body to the wrong side (CROSS_ALLOWANCE below); the
# actual reach limit is physical, driven by Limb's own segment lengths.
const LIMB_SIDE := {
	"left_arm": -1.0,
	"right_arm": 1.0,
	"left_leg": -1.0,
	"right_leg": 1.0,
}

const LIMB_ROLE := {
	"left_arm": "arm",
	"right_arm": "arm",
	"left_leg": "leg",
	"right_leg": "leg",
}

# Contralateral climbing gait: real climbers move opposite hand/foot pairs
# together for balance (same pattern as a walking gait). Purely a scoring
# nudge in _plan_path, not a hard rule -- a clearly better move for the
# "wrong" limb still wins.
const DIAGONAL_PARTNER := {
	"left_arm": "right_leg",
	"right_arm": "left_leg",
	"left_leg": "right_arm",
	"right_leg": "left_arm",
}
const DIAGONAL_BIAS: float = 1.2

# Candidate search radius during planning. Deliberately shy of Limb's full
# UPPER_LENGTH + LOWER_LENGTH extension (not equal to it) so a grip that's
# merely "just barely" geometrically reachable doesn't get selected only to
# render as a fully locked-straight limb -- see Limb.MAX_STRAIGHT_SLACK for
# the matching visual-side margin.
const MAX_REACH: float = (Limb.UPPER_LENGTH + Limb.LOWER_LENGTH) * 0.9
const CROSS_ALLOWANCE: float = 0.35

# Shoulder/hip range-of-motion cone, researched from standard goniometry
# norms (approximated -- see limb.gd's header for the elbow/knee/wrist/
# ankle side of this same research pass):
#   Shoulder flexion ~180 deg, abduction ~180 deg (huge combined forward/
#     up/out range) but extension (swinging behind the body) only ~50-60
#     deg.
#   Hip flexion ~120-125 deg with a bent knee (this is what stops a leg
#     from ever swinging up past shoulder height, let alone over the
#     head) but extension only ~10-30 deg -- hips are much less mobile
#     than shoulders.
# Modeled as a single cone from "hanging straight down," blended between
# a forward limit and a (much tighter) backward limit based on how much
# the candidate direction actually points behind the climber. In
# practice grips only ever exist in front of the climber (on the wall),
# so the backward limit rarely engages -- it's a safety bound, not the
# main constraint. The forward limit is what actually shapes gameplay.
const SHOULDER_FORWARD_LIMIT_DEG: float = 170.0
const SHOULDER_BACKWARD_LIMIT_DEG: float = 60.0
const HIP_FORWARD_LIMIT_DEG: float = 120.0
const HIP_BACKWARD_LIMIT_DEG: float = 20.0

# Real climbing push-pull cycle: legs push the body away from the wall,
# arms pull it back in close. This isn't just cosmetic -- it's the fix
# for knees clipping through the wall when the front-bend change made
# them fold toward it, since the clearance is now largest exactly when
# the knee bend is most pronounced (right after a leg push). Whichever
# role (arm/leg) most recently landed sets the target distance; _process
# lerps toward it every frame, so the body visibly breathes out on a leg
# landing and back in on an arm landing as the gait alternates.
const BODY_OFFSET: float = 0.6 # neutral distance used only before the first move
const PUSH_OFFSET: float = 0.85 # legs just pushed -- body away from the wall
const PULL_OFFSET: float = 0.45 # arms just pulled -- body in close to the wall
const OFFSET_LERP_SPEED: float = 3.0
const TORSO_LERP_SPEED: float = 6.0
const GOAL_EPSILON: float = 0.6
const MAX_PLAN_STEPS: int = 40
const MIN_IMPROVEMENT: float = 0.01

# Ribs/hip counter-rotation -- kept small and equal-priority-secondary
# per "make it subtle at first": ribs lead with the full twist, hips
# follow with a smaller countering twist in the opposite direction.
const RIB_TWIST_MAX_DEG: float = 10.0
const HIP_TWIST_RATIO: float = 0.6
const TWIST_LERP_SPEED: float = 4.0

# Bounding-sphere radii Limb uses for cheap elbow/knee-vs-body avoidance
# (see Limb._resolve_body_avoidance) -- approximate each torso box as a
# sphere around its own global_position rather than doing real box math,
# since this only needs to be "roughly don't let a joint sink into the
# torso," not exact. Roughly matches each box's own half-diagonal
# (Ribs 0.5x0.34x0.3, Hips 0.42x0.3x0.28 in Main.tscn) minus a bit of
# slack, so it's tight to the box rather than a generous personal-space
# bubble -- the shoulder/hip anchors themselves already sit close to
# their box's edge.
const RIBS_AVOID_RADIUS: float = 0.23
const HIPS_AVOID_RADIUS: float = 0.21

# Descent/rappel (see _start_rappel): a tap counted as "pushing down"
# only if the goal sits meaningfully below the current centroid, not just
# marginally lower than an otherwise-lateral tap. NO_DESCENT_TOLERANCE is
# the small slack given to the normal-mode "only climb up" guard in
# _plan_path, for the same reason (grip jitter / near-level candidates
# shouldn't count as "going down").
const DESCENT_TRIGGER_DROP: float = 0.3
const NO_DESCENT_TOLERANCE: float = 0.05

# Gap jump (double tap above, see start_gap_jump): a single dynamic lunge
# with one limb, not a walked multi-step plan -- meant to read as an actual
# dyno, reaching well past a careful single-step climb, not just a slightly
# wider version of it. Previously only ~5% wider than MAX_REACH, which was
# rarely distinguishable from normal climbing and could silently find
# nothing on a genuine gap. The landing limb's own 2-bone IK still clamps
# at its true physical max (UPPER_LENGTH + LOWER_LENGTH), so a far grip
# renders as a visibly fully-extended, stretched-out reach -- that's the
# intended visual signature of a dyno, distinct from calm careful climbing.
const GAP_JUMP_REACH: float = (Limb.UPPER_LENGTH + Limb.LOWER_LENGTH) * 1.5

# The jump itself: previously the torso just sat there passively (the
# ordinary push-pull lerp in _process) while one limb reached far away,
# which reads as "an arm stretches," not "the climber jumps" -- there was
# no launch, no body leaving the wall, no arc. Now the whole torso is
# explicitly driven through a push-off-and-land arc by _apply_jump_progress
# while _jumping is true (which suppresses the passive lerp below).
# GAP_JUMP_DURATION was originally tied to Limb.REACH_DURATION (0.22s, the
# same speed as an ordinary careful reach) so the primary limb's reach_to
# would land in sync with the arc -- but that made the whole launch read as
# instant/twitchy, not a jump. Slowed to a distinctly longer, more visible
# hang time; the primary limb's own reach_to is retimed to match (see
# start_gap_jump) so it still lands exactly when the arc completes.
# GAP_JUMP_LAUNCH_RATIO / GAP_JUMP_VERTICAL_RATIO: how far the body pushes
# out from the wall / rises above the straight path at the arc's peak,
# each a *fraction of the actual start->end travel distance* rather than a
# fixed number. Fixed offsets (previously 1.4 out, 1.2 up, regardless of
# how far the jump actually went) were wrong: for a short-to-medium jump
# the bump dwarfed the real travel, so the body looked like it puffed out
# and popped up, hung there, then snapped back down near where it
# started -- barely any sense of actually going anywhere -- instead of
# reading as forward momentum toward the new hold. Scaling both to travel
# distance means the flourish is always proportionate: a bigger jump gets
# a bigger arc, a short one stays subtle, and the bump can never swamp the
# real direction of travel. Clamped between a small minimum (so even a
# short jump still visibly leaves the wall) and a cap (so a very long jump
# doesn't balloon into an ridiculous swing).
const GAP_JUMP_DURATION: float = 0.45
const GAP_JUMP_LAUNCH_RATIO: float = 0.35
const GAP_JUMP_VERTICAL_RATIO: float = 0.35
const GAP_JUMP_MIN_BUMP: float = 0.25
const GAP_JUMP_MAX_BUMP: float = 0.9

# Per-limb behavior during the flight (see _apply_jump_progress): a limb
# reaching toward a real grip is clamped to at most MAX_REACH from its own
# CURRENT (moving) anchor every frame, so it visibly extends toward the
# target but can never render past a natural reach -- it only actually
# arrives once the anchor gets close enough on its own. Legs that aren't
# the one jumping don't reach for anything at all; they just dangle a
# fixed, comfortably-short distance below the current anchor.
const GAP_JUMP_DANGLE_LENGTH: float = 0.9

# Rope/descent (see start_rappel_to, start_continuous_slide): the rope is a
# fixed, perfectly vertical prop -- top pinned to whichever currently-held
# grip is highest, straight down (same X/Z, no lean toward wherever the
# player tapped) to ROPE_BOTTOM_Y. Tap/click position only decides *that* a
# descend gesture fired (see is_point_below); it never influences the
# rope's shape or where the climber ends up. RAPPEL_STEP_DOWN is one
# discrete "repel" step's distance down the rope (quick tap below);
# SLIDE_SPEED is how fast the continuous hold-to-slide descends.
const ROPE_BOTTOM_Y: float = 0.5
const RAPPEL_STEP_DOWN: float = 1.1
const SLIDE_SPEED: float = 2.0

@export var grip_field_path: NodePath
@export var torso_path: NodePath = NodePath("Torso")
@export var ribs_path: NodePath = NodePath("Torso/Ribs")
@export var hips_path: NodePath = NodePath("Torso/Hips")
@export var rope_path: NodePath = NodePath("Rope")

var grip_field: GripField
var torso: Node3D
var ribs: Node3D
var hips: Node3D
var rope: RopeSpline
var limbs: Dictionary = {}
var held_grip: Dictionary = {}
var stable_grip: Dictionary = {}
var _executing: bool = false
var _last_moved_limb: String = ""
var _last_moved_arm: String = ""
var _last_moved_role: String = ""
var _current_body_offset: float = BODY_OFFSET
var _sliding: bool = false
var _slide_anchor_global: Vector3 = Vector3.ZERO
var _slide_position_global: Vector3 = Vector3.ZERO
var _jumping: bool = false


func _ready() -> void:
	torso = get_node(torso_path) as Node3D
	ribs = get_node(ribs_path) as Node3D
	hips = get_node(hips_path) as Node3D
	rope = get_node(rope_path) as RopeSpline
	for limb_name in LIMB_NAMES:
		var parent: Node3D = ribs if LIMB_PARENT_IS_RIBS[limb_name] else hips
		limbs[limb_name] = parent.get_node(LIMB_NODE_NAMES[limb_name]) as Limb
	_wire_limb_collision_refs()
	grip_field = get_node(grip_field_path) as GripField
	_init_stance()


# Gives each Limb what it needs for elbow/knee-vs-body and elbow/knee-vs-
# sibling-limb avoidance (see Limb._resolve_body_avoidance /
# _resolve_sibling_separation) -- runtime scene-graph links, set once
# here rather than exported, since they only make sense after all 4 Limb
# nodes exist.
func _wire_limb_collision_refs() -> void:
	var body_avoid_points: Array = [
		{"node": ribs, "radius": RIBS_AVOID_RADIUS},
		{"node": hips, "radius": HIPS_AVOID_RADIUS},
	]
	for limb_name in LIMB_NAMES:
		var limb := limbs[limb_name] as Limb
		var siblings: Array[Limb] = []
		for other_name in LIMB_NAMES:
			if other_name != limb_name:
				siblings.append(limbs[other_name] as Limb)
		limb.sibling_limbs = siblings
		limb.body_avoid_points = body_avoid_points
		limb.anchor_offset_x = (LIMB_OFFSETS[limb_name] as Vector3).x


func _process(delta: float) -> void:
	if stable_grip.size() < LIMB_NAMES.size():
		return

	if _jumping:
		return # torso is being driven directly by _apply_jump_progress's tween

	if _sliding:
		_slide_position_global.y = max(_slide_position_global.y - SLIDE_SPEED * delta, ROPE_BOTTOM_Y)
		for limb_name in LIMB_NAMES:
			(limbs[limb_name] as Limb).current_hand_global = _slide_position_global
		var slide_normal := _average_normal(stable_grip)
		torso.global_position = _slide_position_global + slide_normal * PULL_OFFSET
		return

	var centroid := _centroid(stable_grip)
	var normal := _average_normal(stable_grip)

	var target_offset: float = PUSH_OFFSET if _last_moved_role == "leg" else PULL_OFFSET
	var offset_t: float = clamp(delta * OFFSET_LERP_SPEED, 0.0, 1.0)
	_current_body_offset = lerp(_current_body_offset, target_offset, offset_t)

	var target_pos := centroid + normal * _current_body_offset
	var t: float = clamp(delta * TORSO_LERP_SPEED, 0.0, 1.0)
	torso.global_position = torso.global_position.lerp(target_pos, t)
	if normal != Vector3.ZERO:
		var target_basis := Basis.looking_at(-normal, Vector3.UP)
		torso.global_transform.basis = torso.global_transform.basis.slerp(target_basis, t)

	var target_rib_deg := 0.0
	if _last_moved_arm == "left_arm":
		target_rib_deg = RIB_TWIST_MAX_DEG
	elif _last_moved_arm == "right_arm":
		target_rib_deg = -RIB_TWIST_MAX_DEG
	var t2: float = clamp(delta * TWIST_LERP_SPEED, 0.0, 1.0)
	var new_rib_deg: float = lerp(rad_to_deg(ribs.rotation.y), target_rib_deg, t2)
	ribs.rotation.y = deg_to_rad(new_rib_deg)
	hips.rotation.y = -deg_to_rad(new_rib_deg) * HIP_TWIST_RATIO


func start_climb_to(target_point: Vector3) -> void:
	if _executing or not grip_field:
		return
	var goal: Dictionary = grip_field.nearest_grip(target_point)
	if goal.is_empty():
		return
	var steps := _plan_path(goal)
	if steps.is_empty():
		return
	_execute_path(steps)


# Used by TapInput to decide, before it even knows the gesture, whether a
# press falls in "climb" or "descend" territory -- both the single-tap
# rappel and the hold-to-slide gesture route through here first.
func is_point_below(target_point: Vector3) -> bool:
	if not grip_field:
		return false
	var goal: Dictionary = grip_field.nearest_grip(target_point)
	if goal.is_empty():
		return false
	var centroid := _centroid(stable_grip)
	return (goal["pos"] as Vector3).y < centroid.y - DESCENT_TRIGGER_DROP


# Whichever arm currently holds the higher grip -- the one the rope
# anchors to and the one that slides down it. Tap/click position never
# enters into this: a below-tap is purely a direction trigger (see
# is_point_below), not a destination.
func _higher_arm() -> String:
	if (stable_grip["right_arm"]["pos"] as Vector3).y > (stable_grip["left_arm"]["pos"] as Vector3).y:
		return "right_arm"
	return "left_arm"


# Quick tap below: a single discrete "repel" step down the fixed vertical
# rope (see the header comment above ROPE_BOTTOM_Y/RAPPEL_STEP_DOWN) --
#   1. Whichever arm holds the higher grip anchors the rope; that grip's
#      position is the rope's fixed top, straight down to ROPE_BOTTOM_Y.
#   2. That arm releases the rock and slides RAPPEL_STEP_DOWN down the
#      rope's own vertical line (same X/Z as the anchor -- never toward
#      wherever the player tapped).
#   3. The other arm detaches and grasps the nearest reachable real grip
#      near the new position.
#   4. The legs plan a normal-style descent (allow_descent=true) to catch
#      up, same as before.
func start_rappel_to() -> void:
	if _executing or not grip_field:
		return
	_executing = true

	var anchor_name := _higher_arm()
	var other_name := "right_arm" if anchor_name == "left_arm" else "left_arm"
	var anchor_pos: Vector3 = (stable_grip[anchor_name]["pos"] as Vector3)
	var rope_bottom := Vector3(anchor_pos.x, ROPE_BOTTOM_Y, anchor_pos.z)

	if rope:
		rope.set_endpoints(anchor_pos, rope_bottom)
		rope.visible = true

	var slide_target := Vector3(anchor_pos.x, max(anchor_pos.y - RAPPEL_STEP_DOWN, ROPE_BOTTOM_Y), anchor_pos.z)
	# Synthetic grip (id -1, never matches a real grip_field id) -- the
	# anchor hand is holding the rope itself, not a wall hold.
	var slide_grip := {"pos": slide_target, "normal": Vector3(0, 0, 1), "id": -1, "crumbling": false}

	held_grip[anchor_name] = slide_grip
	await (limbs[anchor_name] as Limb).reach_to(slide_target, Vector3(0, 0, 1))
	stable_grip[anchor_name] = slide_grip
	_last_moved_limb = anchor_name
	_last_moved_role = "arm"
	_last_moved_arm = anchor_name

	if rope:
		rope.visible = false

	var regrasp := _find_regrasp_grip(other_name, slide_target)
	if not regrasp.is_empty():
		held_grip[other_name] = regrasp
		await (limbs[other_name] as Limb).reach_to(regrasp["pos"], regrasp["normal"])
		stable_grip[other_name] = regrasp
		_last_moved_limb = other_name
		_last_moved_role = "arm"
		_last_moved_arm = other_name
		if regrasp.get("crumbling", false):
			grip_field.consume_grip(regrasp["id"])

	var leg_steps := _plan_path({"pos": slide_target}, ["left_leg", "right_leg"], true)
	_executing = false
	if not leg_steps.is_empty():
		_execute_path(leg_steps)


# Double tap above: a real dyno, not just a longer single-limb reach --
# the whole torso launches off the wall and arcs toward the new hold (see
# _apply_jump_progress) while the landing limb reaches for its grip in
# parallel, both timed to land together. GAP_JUMP_REACH's wider search
# radius still picks which limb/grip; same safety guards as normal
# planning (crossing, joint cone), just no distance-improvement chain --
# one limb, one reach, no plan.
#
# Once the primary limb lands, the other three walk the rest of the way to
# the actual tapped goal via the same ladder planner normal climbing uses
# (_plan_path/_execute_path). This replaced an earlier single-shot
# "catch up only if stranded" version that turned out to be pointless in
# practice: centroid is an average of all 4 holds, so one limb jumping far
# barely moves it, and a catch-up step judged against that still-low
# centroid would often decide the other limbs were "close enough" and never
# move them at all -- the body could visibly gain almost no real height
# from a whole gap-jump gesture. Running the full multi-step planner
# instead means the other three limbs keep climbing, each step nudging the
# centroid further, until the body is actually near the goal or truly can't
# get closer -- the flashy jump becomes the opening move of real, felt
# progress, not a hollow animation.
func start_gap_jump(target_point: Vector3) -> void:
	if _executing or not grip_field:
		return
	var goal: Dictionary = grip_field.nearest_grip(target_point)
	if goal.is_empty():
		return
	var centroid := _centroid(stable_grip)
	var best_limb := ""
	var best_grip: Dictionary = {}
	var best_dist := INF
	for limb_name in LIMB_NAMES:
		var anchor: Vector3 = centroid + LIMB_OFFSETS[limb_name]
		for g in grip_field.grips_within(anchor, GAP_JUMP_REACH):
			if _grip_claimed(g, stable_grip):
				continue
			if _crosses_body(g["pos"], centroid, limb_name):
				continue
			if _outside_joint_cone(g["pos"], centroid, limb_name):
				continue
			var d: float = (g["pos"] as Vector3).distance_to(goal["pos"])
			if d < best_dist:
				best_dist = d
				best_limb = limb_name
				best_grip = g
	if best_limb == "":
		return
	_executing = true
	_jumping = true

	var launch_normal := _average_normal(stable_grip)
	var start_torso := torso.global_position
	var start_basis := torso.global_transform.basis

	var sim_holds: Dictionary = stable_grip.duplicate(true)
	sim_holds[best_limb] = best_grip
	var landing_normal := _average_normal(sim_holds)
	var landing_offset: float = PUSH_OFFSET if LIMB_ROLE[best_limb] == "leg" else PULL_OFFSET
	# The body has to actually travel to where the jumping limb is going, not
	# to an average diluted by the other 3 limbs' old (unmoved) positions --
	# that average only shifts about a quarter as far as the real jump, which
	# is exactly why the arm used to visibly outrun the body during the arc.
	var end_torso: Vector3 = (best_grip["pos"] as Vector3) - LIMB_OFFSETS[best_limb] + landing_normal * landing_offset
	var end_basis := Basis.looking_at(-landing_normal, Vector3.UP) if landing_normal != Vector3.ZERO else start_basis

	held_grip[best_limb] = best_grip

	# Every limb's hand placement during the flight goes through the same
	# clamped-reach logic in _apply_jump_progress rather than an independent
	# reach_to tween -- the hand tween and the body's own arc used to move
	# on unrelated curves, so the true anchor-to-hand distance could exceed
	# the arm's real length partway through and render as a stretch. Legs
	# that aren't the one jumping just dangle loose; arms that aren't
	# jumping reach toward a real nearby grip the same way the jumping limb
	# does -- both clamped so neither can ever look overextended.
	var reach_targets: Dictionary = {best_limb: best_grip["pos"]}
	var dangling_limbs: Array = []
	for limb_name in LIMB_NAMES:
		if limb_name == best_limb:
			continue
		if LIMB_ROLE[limb_name] == "leg":
			dangling_limbs.append(limb_name)
		else:
			var future_anchor: Vector3 = end_torso + LIMB_OFFSETS[limb_name]
			reach_targets[limb_name] = _flight_reach_target(limb_name, future_anchor)

	var travel_dist := start_torso.distance_to(end_torso)
	var launch_bump: float = clamp(travel_dist * GAP_JUMP_LAUNCH_RATIO, GAP_JUMP_MIN_BUMP, GAP_JUMP_MAX_BUMP)
	var vertical_bump: float = clamp(travel_dist * GAP_JUMP_VERTICAL_RATIO, GAP_JUMP_MIN_BUMP, GAP_JUMP_MAX_BUMP)

	var body_tween := create_tween()
	body_tween.tween_method(_apply_jump_progress.bind(start_torso, end_torso, start_basis, end_basis, launch_normal, launch_bump, vertical_bump, reach_targets, dangling_limbs), 0.0, 1.0, GAP_JUMP_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await body_tween.finished

	_jumping = false
	_current_body_offset = landing_offset
	stable_grip[best_limb] = best_grip
	_last_moved_limb = best_limb
	_last_moved_role = LIMB_ROLE[best_limb]
	if LIMB_ROLE[best_limb] == "arm":
		_last_moved_arm = best_limb
	if best_grip.get("crumbling", false):
		grip_field.consume_grip(best_grip["id"])

	var catchup_limbs: Array = []
	for limb_name in LIMB_NAMES:
		if limb_name != best_limb:
			catchup_limbs.append(limb_name)
	var catchup_steps := _plan_path(goal, catchup_limbs)
	if catchup_steps.is_empty():
		_executing = false
	else:
		await _execute_path(catchup_steps)


# Finds a real, plausible grip near `future_anchor` for a non-primary arm to
# visibly reach toward during a gap jump's flight -- doesn't need to be that
# limb's actual final hold (the post-landing catch-up ladder re-picks a
# proper one anyway), just something real and nearby so the reach direction
# looks intentional. Falls back to `future_anchor` itself (a zero-length,
# folded-in "reach") in the pathological case where grip_field has nothing
# at all nearby, which is always safe -- never a stretch, just an idle arm.
func _flight_reach_target(limb_name: String, future_anchor: Vector3) -> Vector3:
	var best_pos: Vector3 = future_anchor
	var best_dist := INF
	var found := false
	for g in grip_field.grips_within(future_anchor, MAX_REACH):
		if _grip_claimed(g, stable_grip):
			continue
		var d: float = future_anchor.distance_to(g["pos"] as Vector3)
		if d < best_dist:
			best_dist = d
			best_pos = g["pos"]
			found = true
	if not found:
		var nearest: Dictionary = grip_field.nearest_grip(future_anchor)
		if not nearest.is_empty():
			best_pos = nearest["pos"]
	return best_pos


# Drives the torso through a push-off-the-wall-and-land arc during a gap
# jump: `t` interpolates torso position linearly from `start` to `end`
# (the actual travel toward the new hold -- this is the real forward
# momentum) while a sine bump 0->peak->0 adds two things on top, both
# peaking at the arc's midpoint: a push outward along `launch_normal`
# (leaves the wall, lands back against it) and a separate rise along world
# UP. `launch_bump`/`vertical_bump` are pre-scaled to the jump's actual
# travel distance (see start_gap_jump) so the flourish stays proportionate
# to real progress instead of a fixed size that can dwarf it.
#
# Every limb's hand also updates each frame here, never as an independent
# tween, so none can ever drift farther from its own anchor than a natural
# reach allows:
#   - reach_targets (the jumping limb, plus any other arm): hand sits at
#     most MAX_REACH from that limb's CURRENT anchor, along the direction to
#     its target -- visibly extends toward the hold, but only actually
#     arrives once the (also-moving) anchor gets close enough on its own.
#   - dangling_limbs (legs that aren't the one jumping): hand just hangs a
#     fixed, comfortably-short distance straight down from the current
#     anchor -- a loose dangle, not reaching for anything at all.
func _apply_jump_progress(t: float, start: Vector3, end: Vector3, start_basis: Basis, end_basis: Basis, launch_normal: Vector3, launch_bump: float, vertical_bump: float, reach_targets: Dictionary, dangling_limbs: Array) -> void:
	var linear := start.lerp(end, t)
	var hop := sin(t * PI)
	torso.global_position = linear + launch_normal * (hop * launch_bump) + Vector3.UP * (hop * vertical_bump)
	torso.global_transform.basis = start_basis.slerp(end_basis, t)

	for limb_name in reach_targets:
		var limb := limbs[limb_name] as Limb
		var anchor_global: Vector3 = limb.global_position
		var to_target: Vector3 = (reach_targets[limb_name] as Vector3) - anchor_global
		var dist := to_target.length()
		if dist <= MAX_REACH or dist < 0.0001:
			limb.current_hand_global = reach_targets[limb_name]
		else:
			limb.current_hand_global = anchor_global + to_target * (MAX_REACH / dist)

	for limb_name in dangling_limbs:
		var limb := limbs[limb_name] as Limb
		limb.current_hand_global = limb.global_position + Vector3.DOWN * GAP_JUMP_DANGLE_LENGTH


func is_sliding() -> bool:
	return _sliding


# Press-and-hold below: all 4 limbs let go of the wall and grab the fixed
# vertical rope (anchored to the higher arm's current grip, straight down
# to ROPE_BOTTOM_Y -- same rope construction as start_rappel_to, never
# tied to the tap/hold position), then _process slides the shared grab
# point down that fixed line at SLIDE_SPEED for as long as this stays
# active. Every limb just tracks current_hand_global directly each frame
# (no reach_to tween -- there's no fixed target, the point keeps moving)
# which means the existing per-frame wall-collision and sibling-separation
# checks in Limb still run automatically during the slide, same as normal
# movement. The rope itself doesn't redraw each frame -- it's a fixed prop
# for the whole slide, set once here.
func start_continuous_slide() -> void:
	if _executing or _sliding or not grip_field:
		return
	_sliding = true
	_executing = true

	var anchor_name := _higher_arm()
	var anchor_pos: Vector3 = (stable_grip[anchor_name]["pos"] as Vector3)
	_slide_anchor_global = anchor_pos
	_slide_position_global = anchor_pos

	if rope:
		rope.set_endpoints(_slide_anchor_global, Vector3(anchor_pos.x, ROPE_BOTTOM_Y, anchor_pos.z))
		rope.visible = true

	for limb_name in LIMB_NAMES:
		(limbs[limb_name] as Limb).current_hand_global = _slide_position_global


# Release: stop descending and re-grab real holds near wherever the slide
# ended, one nearest-reachable grip per limb (same fallback-to-nearest
# philosophy as the rappel's regrasp). Treated as a leg landing for the
# push-pull cycle, since the whole point is coming back to rest against
# the wall after a fast descent.
func stop_continuous_slide() -> void:
	if not _sliding:
		return
	_sliding = false
	_executing = false
	if rope:
		rope.visible = false

	for limb_name in LIMB_NAMES:
		var anchor: Vector3 = _slide_position_global + LIMB_OFFSETS[limb_name]
		var g: Dictionary = grip_field.nearest_grip(anchor)
		held_grip[limb_name] = g
		stable_grip[limb_name] = g
		(limbs[limb_name] as Limb).reach_to(g["pos"], g["normal"])
	_last_moved_role = "leg"


func _init_stance() -> void:
	for limb_name in LIMB_NAMES:
		var anchor: Vector3 = torso.global_position + LIMB_OFFSETS[limb_name]
		var g: Dictionary = grip_field.nearest_grip(anchor)
		held_grip[limb_name] = g
		stable_grip[limb_name] = g
		(limbs[limb_name] as Limb).set_initial_hand(g["pos"], g["normal"])
	torso.global_position = _centroid(stable_grip) + _average_normal(stable_grip) * BODY_OFFSET


# Greedy single-limb-at-a-time planner: each iteration, try every limb
# against every grip within its reach and take whichever single move
# closes the most distance to the goal. Stops when no move helps or the
# step cap is hit -- a partial path still executes (the forgiving
# "snap toward the tap" fallback from the design brief), it just won't
# fully reach the tapped point in one go.
#
# `limb_names` restricts which limbs are eligible (used by the rappel's
# leg-descent phase to plan legs only). `allow_descent` lifts the
# "climber can only climb up" rule below (also rappel-only) -- normal
# climbing never passes either override.
func _plan_path(goal: Dictionary, limb_names: Array = LIMB_NAMES, allow_descent: bool = false) -> Array:
	var sim_holds: Dictionary = held_grip.duplicate(true)
	var steps: Array = []
	var last_moved := _last_moved_limb
	for i in range(MAX_PLAN_STEPS):
		var sim_centroid := _centroid(sim_holds)
		if sim_centroid.distance_to(goal["pos"]) < GOAL_EPSILON:
			break
		var best_limb := ""
		var best_grip: Dictionary = {}
		var best_score := MIN_IMPROVEMENT
		var preferred_limb: String = DIAGONAL_PARTNER.get(last_moved, "")
		for limb_name in limb_names:
			var anchor: Vector3 = sim_centroid + LIMB_OFFSETS[limb_name]
			var cur_grip_pos: Vector3 = sim_holds[limb_name]["pos"]
			var cur_dist: float = cur_grip_pos.distance_to(goal["pos"])
			for g in grip_field.grips_within(anchor, MAX_REACH):
				if _grip_claimed(g, sim_holds):
					continue
				if _crosses_body(g["pos"], sim_centroid, limb_name):
					continue
				if _outside_joint_cone(g["pos"], sim_centroid, limb_name):
					continue
				# Climbing (not rappelling) never moves a limb to a lower
				# grip than the one it already holds -- descent only
				# happens through the dedicated rappel sequence.
				if not allow_descent and (g["pos"] as Vector3).y < cur_grip_pos.y - NO_DESCENT_TOLERANCE:
					continue
				var new_dist: float = (g["pos"] as Vector3).distance_to(goal["pos"])
				var score: float = cur_dist - new_dist
				if limb_name == preferred_limb:
					score *= DIAGONAL_BIAS
				if score > best_score:
					best_score = score
					best_limb = limb_name
					best_grip = g
		if best_limb == "":
			break
		steps.append({"limb": best_limb, "grip": best_grip})
		sim_holds[best_limb] = best_grip
		last_moved = best_limb
	return steps


func _execute_path(steps: Array) -> void:
	_executing = true
	for step in steps:
		var limb_name: String = step["limb"]
		var grip: Dictionary = step["grip"]
		held_grip[limb_name] = grip
		await (limbs[limb_name] as Limb).reach_to(grip["pos"], grip["normal"])
		stable_grip[limb_name] = grip
		_last_moved_limb = limb_name
		_last_moved_role = LIMB_ROLE[limb_name]
		if limb_name == "left_arm" or limb_name == "right_arm":
			_last_moved_arm = limb_name
		if grip.get("crumbling", false):
			grip_field.consume_grip(grip["id"])
	_executing = false


# Finds the grip closest to `near_pos` that `limb_name` can actually reach
# from its current anchor -- used for the rappel's "other arm detaches and
# grasps above or below" step, so the re-grasp is physically reachable
# rather than just nearest in space. Falls back to the field's nearest
# grip regardless of reach if nothing reachable qualifies, matching the
# design brief's "snap toward it instead of rejecting outright" fallback.
func _find_regrasp_grip(limb_name: String, near_pos: Vector3) -> Dictionary:
	var centroid := _centroid(stable_grip)
	var anchor: Vector3 = centroid + LIMB_OFFSETS[limb_name]
	var best: Dictionary = {}
	var best_dist := INF
	for g in grip_field.grips_within(anchor, MAX_REACH):
		if _grip_claimed(g, stable_grip):
			continue
		var d: float = (g["pos"] as Vector3).distance_to(near_pos)
		if d < best_dist:
			best_dist = d
			best = g
	if best.is_empty():
		return grip_field.nearest_grip(near_pos)
	return best


# Rejects a candidate grip that would make a limb reach noticeably across
# the body's own midline (e.g. the left arm grabbing something well to the
# right) -- a cheap, real "unnatural position" guard on top of the 2-bone
# IK's physical length constraint, which only stops overstretching, not
# crossing.
func _crosses_body(grip_pos: Vector3, sim_centroid: Vector3, limb_name: String) -> bool:
	var local_x: float = (grip_pos - sim_centroid).dot(torso.global_transform.basis.x)
	return local_x * LIMB_SIDE[limb_name] < -CROSS_ALLOWANCE


# Shoulder/hip range-of-motion cone (see the researched limits above):
# rejects a candidate whose direction from the anchor exceeds the real
# joint's flexion/extension limit, blended by how much that direction
# actually points behind the climber. This is what stops a leg from ever
# reaching above shoulder height (hip flexion tops out well below the
# shoulder's own, much larger, range) -- a principled replacement for an
# earlier flat height-based guard.
func _outside_joint_cone(grip_pos: Vector3, sim_centroid: Vector3, limb_name: String) -> bool:
	var anchor: Vector3 = sim_centroid + LIMB_OFFSETS[limb_name]
	var dir: Vector3 = grip_pos - anchor
	if dir.length() < 0.001:
		return false
	dir = dir.normalized()
	var basis := torso.global_transform.basis
	var rest_down: Vector3 = -basis.y
	var back_axis: Vector3 = basis.z # local +Z points away from the wall, i.e. behind the climber
	var back_amount: float = clamp(dir.dot(back_axis), 0.0, 1.0)
	var is_leg: bool = LIMB_ROLE[limb_name] == "leg"
	var forward_limit_deg: float = HIP_FORWARD_LIMIT_DEG if is_leg else SHOULDER_FORWARD_LIMIT_DEG
	var backward_limit_deg: float = HIP_BACKWARD_LIMIT_DEG if is_leg else SHOULDER_BACKWARD_LIMIT_DEG
	var limit_deg: float = lerp(forward_limit_deg, backward_limit_deg, back_amount)
	var angle_deg: float = rad_to_deg(acos(clamp(dir.dot(rest_down), -1.0, 1.0)))
	return angle_deg > limit_deg


func _centroid(holds: Dictionary) -> Vector3:
	var sum := Vector3.ZERO
	for limb_name in LIMB_NAMES:
		sum += (holds[limb_name]["pos"] as Vector3)
	return sum / LIMB_NAMES.size()


func _average_normal(holds: Dictionary) -> Vector3:
	var sum := Vector3.ZERO
	for limb_name in LIMB_NAMES:
		sum += (holds[limb_name]["normal"] as Vector3)
	if sum == Vector3.ZERO:
		return Vector3.ZERO
	return sum.normalized()


func _grip_claimed(g: Dictionary, holds: Dictionary) -> bool:
	for limb_name in LIMB_NAMES:
		if holds[limb_name]["id"] == g["id"]:
			return true
	return false
