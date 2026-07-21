class_name RopeSpline
extends Node3D

# Visual-only rope for the descent/rappel sequence (see Climber._start_rappel):
# a thin chain of segments along a straight Curve3D between a fixed anchor
# point (the highest arm's grip, which doesn't move -- the rope's real-world
# origin) and the descending hand's current position. Climber toggles
# `visible` on/off around the anchor-hand's slide; while hidden this does no
# work at all (see the early-out in _process).
#
# Thinner than the limb/waist segments (THICKNESS well under LIMB_THICKNESS)
# so it reads as a rope, not another limb.

const SEGMENT_COUNT: int = 8
const THICKNESS: float = 0.06

var _curve := Curve3D.new()
var _segments: Array[MeshInstance3D] = []
var _segment_mesh: BoxMesh
var _anchor_global: Vector3 = Vector3.ZERO
var _end_global: Vector3 = Vector3.ZERO


func _ready() -> void:
	visible = false
	_curve.bake_interval = 0.05
	_segment_mesh = BoxMesh.new()
	_segment_mesh.size = Vector3(THICKNESS, 1.0, THICKNESS)
	var mat := StandardMaterial3D.new()
	# A muted grey (like the limb segments) read as almost indistinguishable
	# from a limb under this scene's warm directional light -- pushed to a
	# clearly saturated gold/rope color, not just a slightly-different grey,
	# so it reads unambiguously as "a rope" rather than "another limb."
	mat.albedo_color = Color(0.82, 0.58, 0.18)
	mat.roughness = 0.85
	for i in SEGMENT_COUNT:
		var seg := MeshInstance3D.new()
		seg.mesh = _segment_mesh
		seg.set_surface_override_material(0, mat)
		add_child(seg)
		_segments.append(seg)


func set_endpoints(anchor_global: Vector3, end_global: Vector3) -> void:
	_anchor_global = anchor_global
	_end_global = end_global


func _process(_delta: float) -> void:
	if not visible:
		return
	_rebuild()


func _rebuild() -> void:
	var top_local := to_local(_anchor_global)
	var bottom_local := to_local(_end_global)

	_curve.clear_points()
	_curve.add_point(top_local, Vector3.ZERO, Vector3.ZERO)
	_curve.add_point(bottom_local, Vector3.ZERO, Vector3.ZERO)

	var baked_len := _curve.get_baked_length()
	if baked_len <= 0.001:
		for seg in _segments:
			seg.visible = false
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
			seg.quaternion = _stable_look_basis(seg_vec).get_rotation_quaternion()
		seg.scale = Vector3(1.0, max(seg_len, 0.001), 1.0)


# Same fix as limb.gd/waist_spline.gd's _stable_look_basis: a rope hangs
# close to straight down, which is the exact degenerate case for
# Quaternion(Vector3.UP, dir) (see feedback_rules.md's entry on this) --
# RIGHT is used as the primary hint here instead, for the same reason
# waist_spline.gd does.
static func _stable_look_basis(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := Vector3.RIGHT.cross(y)
	if x.length() < 0.01:
		x = Vector3.FORWARD.cross(y)
	if x.length() < 0.01:
		x = Vector3.UP.cross(y)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)
