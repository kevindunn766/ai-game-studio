# Procedural isopod — ROLLER variant (copy of isopod.gd). Adds conglobation (volvation): the pill
# bug curls its spine armature ventrally into a tight ball, tergites (dorsal plates) outside, with
# legs/head/antennae tucked inside — the real pill-bug defensive roll-up. Cycles on a timer here.
# No class_name (headless-safe); instanced via preload const from main.gd.
extends Node3D

const MeshBuilder = preload("res://scripts/mesh_builder.gd")

# --- Traced reference profiles (per docs/godot-3d-modeling-process.md) ---
# FRONT view: the half cross-section, traced from the head-on isopod photo — a tall rounded dome
# that comes down the flanks into a hanging epimeron, then a shallow concave belly. (x = half-width
# fraction, y = height fraction; mirrored across X for symmetry.)
const FRONT_OUTLINE: Array[Vector2] = [
	Vector2(0.00, 1.00),   # dorsal ridge
	Vector2(0.28, 0.985),
	Vector2(0.52, 0.94),
	Vector2(0.72, 0.85),
	Vector2(0.88, 0.68),
	Vector2(0.99, 0.46),
	Vector2(1.05, 0.22),
	Vector2(1.06, 0.02),   # epimeron shoulder
	Vector2(0.96, -0.10),  # epimeron tip (hangs toward legs)
	Vector2(0.66, -0.12),  # belly
	Vector2(0.34, -0.10),
	Vector2(0.00, -0.09),  # belly center
]
# Shared body-length axis u (0 = nose, 1 = tail tip) for the TOP and SIDE traces.
const TRACE_U: Array[float] = [0.00, 0.06, 0.12, 0.22, 0.40, 0.60, 0.78, 0.88, 0.94, 1.00]
# TOP view: capsule softened toward an oval — sides curve gently (not parallel), rounder ends.
const TOP_W: Array[float] = [0.16, 0.66, 0.85, 0.94, 1.00, 1.00, 0.94, 0.85, 0.66, 0.16]
# SIDE view: top-half capsule softened the same — gently domed dorsal, rounder front and back.
const SIDE_H: Array[float] = [0.16, 0.66, 0.85, 0.94, 1.00, 1.00, 0.94, 0.85, 0.66, 0.16]

# Fully-typed leg record (avoids Variant from Dictionary access).
class Leg:
	var attach_local: Vector3          # where the coxa meets the body
	var hip_local: Vector3             # coxa tip / femur base
	var side: float
	var phase: float
	var foot_world: Vector3 = Vector3.ZERO
	var swing_from: Vector3 = Vector3.ZERO
	var swing_to: Vector3 = Vector3.ZERO
	var was_swing: bool = false
	var coxa: MeshInstance3D
	var femur: MeshInstance3D
	var tibia: MeshInstance3D

# --- Genome-ish body params — real isopod anatomy (per the reference anatomy diagram) ---
# Cephalothorax (head) + PEREON (7 pereonites, one leg pair each, hanging epimera)
#   + PLEON (5 small pleonites) + pleotelson (tail).  Built ~2:1 length:width.
@export var num_pereon: int = 7              # pereonites 1-7 (leg-bearing, big epimera)
@export var num_pleon: int = 5               # pleonites 1-5 (small, at the rear)
@export var body_span_z: float = 1.8         # nose-to-tail length (traced loft axis)
@export var max_half_width: float = 0.50     # from the TOP trace (half of full width)
@export var max_height: float = 0.58         # from the SIDE/FRONT trace (dome height)
@export var ride_height: float = 0.30        # body arched up -> clear space under it for the legs
@export var scallop_amt: float = 0.0         # epimeron edge lobing (off — scallop removed)
@export var pereon_len: float = 0.52         # plate length; heavy overlap -> continuous carapace
@export var pereon_spacing: float = 0.15     # z-gap between pereonite centers (<< len -> overlap)
@export var pleon_len: float = 0.30
@export var pleon_spacing: float = 0.06
@export var tail_length: float = 0.72         # smooth lofted pleon+telson depth
@export var tail_overlap: float = 0.30        # how far the tail tucks under the last pereonite
@export var epimeron_sweep: float = 0.05      # backward sweep of the side flaps (0 = straight)
@export var head_radius: float = 0.32
@export var show_legs: bool = true           # toggled off (--nolegs) to judge the shell alone

# --- Leg params (short, splayed out under the shell) ---
@export var num_leg_pairs: int = 7           # 7 pairs = 14 legs
@export var leg_u_start: float = 0.14        # first leg pair along the body (0=nose)
@export var leg_u_end: float = 0.84          # last leg pair — spread evenly head-to-tail
@export var femur_len: float = 0.15
@export var tibia_len: float = 0.19
@export var foot_out: float = 0.06           # feet splay just past the body edge
@export var leg_radius: float = 0.026

# --- Gait ---
@export var duty: float = 0.42               # fraction of cycle a leg is in swing
@export var step_lift: float = 0.06          # foot lift height at mid-swing
@export var wave_span: float = 0.85          # metachronal spread head->tail
@export var stride_length: float = 0.13      # distance per gait cycle (< leg reach, so no stretch)

# --- Locomotion (no controls yet: drive in a circle) ---
@export var circle_radius: float = 3.2
@export var ang_speed: float = 0.40          # rad/sec around the circle

# --- Conglobation (roll-up) ---
@export var roll_period: float = 3.4          # full cycle: extend -> roll up -> hold -> unroll
@export var curl_per_joint_deg: float = 40.0  # per-joint ventral curl at full roll (~ball)
@export var ball_ride_height: float = 0.40    # body lift when balled (sits on the floor)

var _legs: Array[Leg] = []
var _angle: float = 0.0
var _gait_phase: float = 0.0
var _body_mat: StandardMaterial3D
var _leg_mat: StandardMaterial3D
var _antenna_mat: StandardMaterial3D
var _pereon_z: Array[float] = []       # per leg-segment z (shared by body + legs)
var _pereon_hw: Array[float] = []      # per leg-segment half-width
var _joints: Array[Node3D] = []        # spine armature: chained joints, one carapace piece each
var _antenna_segs: Array[MeshInstance3D] = []
var _time: float = 0.0
var _roll: float = 0.0                  # 0 = extended (walking), 1 = fully balled

func _ready() -> void:
	_make_materials()
	_build_body()
	_build_legs()
	_build_antennae()
	_place_on_circle()

func _make_materials() -> void:
	# Colors sampled from the reference: dark slate-brown carapace, pale grey-tan legs.
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = Color(0.28, 0.25, 0.24)
	_body_mat.roughness = 0.65
	_leg_mat = StandardMaterial3D.new()
	_leg_mat.albedo_color = Color(0.55, 0.50, 0.46)
	_leg_mat.roughness = 0.8
	_antenna_mat = StandardMaterial3D.new()
	_antenna_mat.albedo_color = Color(0.34, 0.25, 0.21)   # reddish-brown antennae
	_antenna_mat.roughness = 0.7

func _u_to_z(u: float) -> float:
	return lerp(-body_span_z * 0.5, body_span_z * 0.5, u)

func _sample(u: float, ys: Array[float]) -> float:
	var n: int = TRACE_U.size()
	if u <= TRACE_U[0]:
		return ys[0]
	if u >= TRACE_U[n - 1]:
		return ys[n - 1]
	for k in range(n - 1):
		if u <= TRACE_U[k + 1]:
			var t: float = (u - TRACE_U[k]) / (TRACE_U[k + 1] - TRACE_U[k])
			return lerp(ys[k], ys[k + 1], t)
	return ys[n - 1]

# One carapace piece: a slice of the traced body form over [u0,u1], built by lofting the FRONT
# cross-section scaled by the TOP (width) and SIDE (height) traces. Because every piece samples the
# SAME body surface, adjacent pieces nest cleanly (no screw/gaps). `proud` lifts the rear edge so
# it overhangs the next plate (the armour overlap). Returned centered on its own z (local to joint).
func _body_slice(u0: float, u1: float, proud: float, rings_n: int, scallop_amt: float = 0.0) -> Array:
	var zc: float = _u_to_z((u0 + u1) * 0.5)
	var sx := PackedFloat32Array()
	var sy := PackedFloat32Array()
	var zs := PackedFloat32Array()
	var sc := PackedFloat32Array()
	for k in range(rings_n):
		var t: float = float(k) / float(rings_n - 1)
		var u: float = lerp(u0, u1, t)
		var p: float = 1.0 + proud * t                      # rear edge sits proud
		sx.append(max_half_width * _sample(u, TOP_W) * p)
		sy.append(max_height * _sample(u, SIDE_H) * p)
		zs.append(_u_to_z(u) - zc)
		sc.append(scallop_amt * sin(PI * t))                # epimeron lobes out mid-plate, notches at edges
	# Outline indices 5-8 are the epimeron (outer shoulder + hanging flap) -> scalloped per plate.
	return [zc, _make_mi(MeshBuilder.loft_closed(FRONT_OUTLINE, sx, sy, zs, 5, 8, sc))]

# Build each carapace piece as a slice of the traced body, then hang them on a spine armature
# (chain of joints, head -> pereonites -> tail). Rotating a joint later flexes/curls the rest.
func _build_body() -> void:
	_pereon_z.clear()
	_pereon_hw.clear()
	_joints.clear()
	var items: Array = []                       # [z_center, MeshInstance3D], head-to-tail
	# Cephalothorax.
	items.append(_body_slice(0.0, 0.17, 0.0, 6))
	# PEREON — 7 pereonites, each a proud-edged slice tucking under the one ahead.
	var pu0: float = 0.14
	var pu1: float = 0.66
	var seg: float = (pu1 - pu0) / float(num_pereon)
	for j in range(num_pereon):
		var us: float = pu0 + seg * float(j) - 0.6 * seg    # front tucks under previous
		var ue: float = pu0 + seg * float(j + 1)
		var uc: float = pu0 + seg * (float(j) + 0.5)
		_pereon_z.append(_u_to_z(uc))
		_pereon_hw.append(max_half_width * _sample(uc, TOP_W))
		items.append(_body_slice(us, ue, 0.04, 7, scallop_amt))
	# PLEON + PLEOTELSON — tail slice tapering to the blunt tip.
	items.append(_body_slice(0.62, 1.0, 0.0, 9))
	# Chain the joints: each joint a child of the previous, offset by the z delta.
	var parent: Node3D = self
	var prev_abs: float = 0.0
	for it in items:
		var iz: float = it[0]
		var node: MeshInstance3D = it[1]
		var joint := Node3D.new()
		joint.position = Vector3(0.0, 0.0, iz - prev_abs)
		parent.add_child(joint)
		node.position = Vector3.ZERO
		joint.add_child(node)
		_joints.append(joint)
		parent = joint
		prev_abs = iz

func _make_mi(mesh: ArrayMesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _body_mat
	return mi

# One traced leg (coxa + femur + tibia) per pereonite, mirrored to both sides. The same three
# traced segment meshes are reused for every leg and posed each frame by the IK solve (step 8:
# trace each segment, rotate into place, rig on IK; steps 6-7: trace one, mirror/rotate into sockets).
func _build_legs() -> void:
	if not show_legs:
		return
	for k in range(num_leg_pairs):
		# Spread the leg pairs evenly along the body (head -> tail), not bunched in the pereon.
		var t: float = (float(k) + 0.5) / float(num_leg_pairs)
		var u: float = lerp(leg_u_start, leg_u_end, t)
		var z: float = _u_to_z(u)
		var hw: float = max_half_width * _sample(u, TOP_W)
		for side in [-1.0, 1.0]:
			var leg := Leg.new()
			leg.attach_local = Vector3(side * hw * 0.56, -0.02, z)   # coxa root under the body
			leg.hip_local = Vector3(side * hw * 0.74, -0.06, z)      # coxa tip / femur base (angled down)
			leg.side = side
			var ph: float = wave_span * float(k) / float(num_leg_pairs)
			if side > 0.0:
				ph += 0.5                        # right side anti-phase to left
			leg.phase = fposmod(ph, 1.0)
			# Each segment mesh is built at its TRUE fixed length — bones are rigid, only rotated
			# (never resized after attach). coxa length is the fixed attach->hip distance.
			var coxa_len: float = (leg.hip_local - leg.attach_local).length()
			leg.coxa = _make_bone(leg_radius * 1.15, leg_radius, coxa_len)
			leg.femur = _make_bone(leg_radius, leg_radius * 0.75, femur_len)
			leg.tibia = _make_bone(leg_radius * 0.75, leg_radius * 0.45, tibia_len)
			_legs.append(leg)

func _make_bone(r0: float, r1: float, length: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshBuilder.tapered_tube(r0, r1, length, 7)
	mi.material_override = _leg_mat
	add_child(mi)
	return mi

# Antenna 2 (x2, mirrored): a jointed peduncle (segments 1-3) + a thinner flagellum (4-5), traced
# as rigid tapered segments sweeping forward-down-out from the cephalothorax. Static (local) pose.
func _build_antennae() -> void:
	var r0s := PackedFloat32Array([0.024, 0.021, 0.018, 0.013, 0.010])
	var r1s := PackedFloat32Array([0.021, 0.018, 0.015, 0.010, 0.005])
	var nose_z: float = _u_to_z(0.0)
	for side in [-1.0, 1.0]:
		# Joint chain in body-local space (nose is at -Z; sweep forward-out-down).
		var pts: Array[Vector3] = [
			Vector3(side * 0.07, 0.30, nose_z + 0.08),
			Vector3(side * 0.13, 0.27, nose_z - 0.06),
			Vector3(side * 0.20, 0.23, nose_z - 0.20),
			Vector3(side * 0.26, 0.18, nose_z - 0.32),   # peduncle end
			Vector3(side * 0.30, 0.13, nose_z - 0.42),
			Vector3(side * 0.33, 0.09, nose_z - 0.50),   # flagellum tip
		]
		for i in range(pts.size() - 1):
			var seg := MeshInstance3D.new()
			seg.mesh = MeshBuilder.tapered_tube(r0s[i], r1s[i], (pts[i + 1] - pts[i]).length(), 6)
			seg.material_override = _antenna_mat
			add_child(seg)
			_aim_bone_local(seg, pts[i], pts[i + 1])
			_antenna_segs.append(seg)

# Like _aim_bone but sets the LOCAL transform (for static parts that ride with the body).
func _aim_bone_local(mi: MeshInstance3D, p0: Vector3, p1: Vector3) -> void:
	var axis: Vector3 = p1 - p0
	var y: Vector3 = axis.normalized() if axis.length() > 1e-6 else Vector3.UP
	var x: Vector3 = Vector3.RIGHT
	if abs(y.dot(x)) > 0.99:
		x = Vector3.FORWARD
	var z: Vector3 = x.cross(y).normalized()
	x = y.cross(z).normalized()
	mi.transform = Transform3D(Basis(x, y, z), p0)

func _place_on_circle() -> void:
	var pos := Vector3(cos(_angle), 0.0, sin(_angle)) * circle_radius
	pos.y = lerp(ride_height, ball_ride_height, _roll)   # lift onto the floor when balled
	var fwd := Vector3(-sin(_angle), 0.0, cos(_angle))   # tangent (travel dir)
	global_position = pos
	look_at(pos + fwd, Vector3.UP)                        # -Z (head) faces travel

func _process(delta: float) -> void:
	_time += delta
	_update_roll()
	var moving: bool = _roll < 0.02
	if moving:
		_angle += ang_speed * delta                      # only walk while extended
	_place_on_circle()
	_apply_curl()
	_apply_tuck()
	var speed: float = (abs(ang_speed) * circle_radius) if moving else 0.0
	_gait_phase += (speed / max(stride_length, 0.01)) * delta
	_update_legs(speed)

# Roll cycle: extended (walk) -> curl into a ball -> hold -> unroll.
func _update_roll() -> void:
	var t_ext: float = 0.3
	var t_up: float = 1.0
	var t_hold: float = 0.9
	var t_down: float = max(roll_period - t_ext - t_up - t_hold, 0.01)
	var p: float = fposmod(_time, roll_period)
	if p < t_ext:
		_roll = 0.0
	elif p < t_ext + t_up:
		_roll = smoothstep(0.0, 1.0, (p - t_ext) / t_up)
	elif p < t_ext + t_up + t_hold:
		_roll = 1.0
	else:
		_roll = smoothstep(0.0, 1.0, 1.0 - (p - t_ext - t_up - t_hold) / t_down)

# Curl every spine joint ventrally by the same angle -> the chain wraps into a ball (tergites out).
func _apply_curl() -> void:
	var ang: float = -deg_to_rad(curl_per_joint_deg) * _roll
	for j in _joints:
		j.rotation = Vector3(ang, 0.0, 0.0)

# Antennae retract inside the ball as it closes.
func _apply_tuck() -> void:
	var vis: bool = _roll < 0.12
	for s in _antenna_segs:
		s.visible = vis

func _update_legs(speed: float) -> void:
	var right: Vector3 = global_transform.basis.x
	var fwd: Vector3 = -global_transform.basis.z
	for leg in _legs:
		var hip_world: Vector3 = to_global(leg.hip_local)
		var ground_hip := Vector3(hip_world.x, 0.0, hip_world.z)
		var desired: Vector3 = ground_hip + right * (leg.side * foot_out)
		desired.y = 0.0
		if leg.foot_world == Vector3.ZERO:            # first frame: plant, don't draw to world origin
			leg.foot_world = desired
		var c: float = fposmod(_gait_phase + leg.phase, 1.0)
		var swing: bool = c < duty
		if swing:
			var lt: float = c / duty
			if not leg.was_swing:
				leg.swing_from = leg.foot_world
				leg.swing_to = desired + fwd * speed * 0.04   # anticipate ahead (small)
			var e: float = smoothstep(0.0, 1.0, lt)
			var f: Vector3 = leg.swing_from.lerp(leg.swing_to, e)
			f.y += step_lift * sin(PI * lt)
			leg.foot_world = f
		else:
			if leg.was_swing:
				leg.foot_world = leg.swing_to               # plant
			# else: foot stays world-fixed (stance)
		leg.was_swing = swing
		if _roll > 0.001:
			leg.foot_world = leg.foot_world.lerp(hip_world, _roll)   # retract feet up when rolling
		var lvis: bool = _roll < 0.16                                # hide legs as they tuck inside
		leg.coxa.visible = lvis
		leg.femur.visible = lvis
		leg.tibia.visible = lvis
		_solve_and_draw(leg, to_global(leg.attach_local), hip_world)

func _solve_and_draw(leg: Leg, attach: Vector3, hip: Vector3) -> void:
	var knee: Vector3 = _ik_knee(hip, leg.foot_world, femur_len, tibia_len, leg.side)
	# Draw the tibia rigid (exactly tibia_len) toward the foot — no stretching if out of reach.
	var to_foot: Vector3 = leg.foot_world - knee
	var foot_dir: Vector3 = to_foot.normalized() if to_foot.length() > 1e-6 else Vector3.DOWN
	var foot_draw: Vector3 = knee + foot_dir * tibia_len
	_aim_bone(leg.coxa, attach, hip)
	_aim_bone(leg.femur, hip, knee)
	_aim_bone(leg.tibia, knee, foot_draw)

# 2-bone IK: return the knee/elbow position bending up-and-outward.
func _ik_knee(hip: Vector3, target: Vector3, l1: float, l2: float, side: float) -> Vector3:
	var to_t: Vector3 = target - hip
	var raw_len: float = to_t.length()
	var dirn: Vector3 = (to_t / raw_len) if raw_len > 1e-6 else Vector3.DOWN
	var dist: float = clamp(raw_len, 0.001, l1 + l2 - 0.001)
	var cos_a: float = clamp((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var a: float = acos(cos_a)
	var outward: Vector3 = global_transform.basis.x * side
	var pole: Vector3 = (outward * 0.5 - Vector3.UP * 0.5).normalized()   # knees bend down (nearly vertical legs)
	pole = pole - dirn * pole.dot(dirn)
	if pole.length() < 1e-4:
		pole = Vector3.UP - dirn * dirn.dot(Vector3.UP)
	pole = pole.normalized()
	return hip + dirn * (l1 * cos_a) + pole * (l1 * sin(a))

# Rotate a fixed-length +Y segment mesh (base at y=0) so it points from p0 toward p1, rooted at p0.
# ROTATION ONLY — the mesh is already its true length, so we never resize the bone after attaching.
func _aim_bone(mi: MeshInstance3D, p0: Vector3, p1: Vector3) -> void:
	var axis: Vector3 = p1 - p0
	var y: Vector3 = axis.normalized() if axis.length() > 1e-6 else Vector3.UP
	var x: Vector3 = Vector3.RIGHT
	if abs(y.dot(x)) > 0.99:
		x = Vector3.FORWARD
	var z: Vector3 = x.cross(y).normalized()
	x = y.cross(z).normalized()                 # right-handed (det +1)
	mi.global_transform = Transform3D(Basis(x, y, z), p0)
