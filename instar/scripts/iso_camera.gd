# Isometric camera rig for INSTAR.
# SpringArm3D boom at a fixed isometric angle (per Kevin's request), following a
# target. Feeds the tilt-shift post pass a per-frame focus depth = the target's
# view-space distance, so the subject stays sharp and the floor falls out of focus.
# Camera framing is code-driven off explicit values (Governing Rule 6): the rig is
# never parented under the (moving/looked-at) target.
extends Node3D

@export var pitch_deg: float = 35.264   # true-isometric elevation
@export var yaw_deg: float = 45.0
@export var boom_length: float = 14.0
@export var ortho_size: float = 3.2
@export var follow_lerp: float = 6.0

var target: Node3D
var pivot: Node3D
var arm: SpringArm3D
var cam: Camera3D
var post: MeshInstance3D
var mat: ShaderMaterial

func _ready() -> void:
	pivot = Node3D.new()
	add_child(pivot)
	arm = SpringArm3D.new()
	arm.spring_length = boom_length
	arm.collision_mask = 0                     # act as a fixed boom, ignore floor
	arm.rotation_degrees = Vector3(-pitch_deg, yaw_deg, 0.0)
	pivot.add_child(arm)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = ortho_size
	cam.near = 0.05
	cam.far = 400.0
	cam.current = true
	arm.add_child(cam)

func setup_tilt_shift(shader: Shader) -> void:
	post = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.0, 2.0)                  # VERTEX.xy spans [-1,1]
	post.mesh = q
	mat = ShaderMaterial.new()
	mat.shader = shader
	post.material_override = mat
	post.extra_cull_margin = 16384.0           # never frustum-culled
	post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	post.position = Vector3(0.0, 0.0, -1.0)     # nominally in front of the camera
	cam.add_child(post)

func _process(delta: float) -> void:
	if target == null:
		return
	var tp := target.global_position
	var w: float = clamp(follow_lerp * delta, 0.0, 1.0)
	pivot.global_position = pivot.global_position.lerp(tp, w)
	if mat != null:
		var view := cam.global_transform.affine_inverse() * tp
		mat.set_shader_parameter("focus_depth", -view.z)
