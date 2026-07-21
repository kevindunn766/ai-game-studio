class_name WaistSpline
extends Node3D

# Connects the ribs box (top_path) to the hip box (bottom_path) with a
# thick, wide chain of segments sampled along a Curve3D -- same box-chain
# technique as limb.gd's arms/legs, just wider and shorter, and with no
# IK to solve (both ends are plain node positions, not reach targets).
# Rebuilt every frame since the ribs and hips can rotate independently
# (see Climber's rib/hip counter-twist).

const SEGMENT_COUNT: int = 5
const WIDTH: float = 0.34
const DEPTH: float = 0.24

@export var top_path: NodePath
@export var bottom_path: NodePath

var _top: Node3D
var _bottom: Node3D
var _curve := Curve3D.new()
var _segments: Array[MeshInstance3D] = []
var _segment_mesh: BoxMesh


func _ready() -> void:
	_top = get_node(top_path) as Node3D
	_bottom = get_node(bottom_path) as Node3D
	_curve.bake_interval = 0.05
	_segment_mesh = BoxMesh.new()
	_segment_mesh.size = Vector3(WIDTH, 1.0, DEPTH)
	for i in SEGMENT_COUNT:
		var seg := MeshInstance3D.new()
		seg.mesh = _segment_mesh
		add_child(seg)
		_segments.append(seg)


func _process(_delta: float) -> void:
	_rebuild()


func _rebuild() -> void:
	if not _top or not _bottom:
		return
	var top_local := to_local(_top.global_position)
	var bottom_local := to_local(_bottom.global_position)
	var mid := (top_local + bottom_local) * 0.5

	_curve.clear_points()
	_curve.add_point(top_local, Vector3.ZERO, (mid - top_local) * 0.5)
	_curve.add_point(mid, (top_local - mid) * 0.3, (bottom_local - mid) * 0.3)
	_curve.add_point(bottom_local, (mid - bottom_local) * 0.5, Vector3.ZERO)

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


# Same fix as limb.gd's _stable_look_basis, and arguably more important
# here: this spline runs ribs-bottom to hips-top, which is very close to
# straight down (antiparallel to Vector3.UP) in the neutral pose --
# exactly the degenerate case where Quaternion(Vector3.UP, dir)'s
# fixed-reference shortest-arc construction breaks down (Godot's own
# tracker documents this for near-parallel/antiparallel inputs). Using a
# hint + fallback chain instead avoids relying on a single axis the
# direction is likely to collide with.
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
