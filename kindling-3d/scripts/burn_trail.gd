extends Node

# Shader-based burn trail. Drops flat scorch quads (scorch.gdshader) along the flame's
# path, each exactly the flame's on-screen size, and fades them out over time. The marks
# live under `world_root` in CONTENT space, so they scroll and scale with the world exactly
# like everything else -- the flame is fixed at the origin, so a mark dropped at the current
# scroll position trails away behind it as the world moves. Marks land wherever the flame
# passes, so they also scorch the ground under items the player can't burn yet.

const ScorchShader := preload("res://shaders/scorch.gdshader")

@export var lifetime: float = 6.0           # seconds a scorch mark lasts
@export var max_marks: int = 72             # pool cap
@export var drop_fraction: float = 0.4      # drop a new mark every this * mark-size of travel

var world_root: Node3D = null
var height_field: RefCounted = null          # GroundHeight -- so marks sit on the ground

var _marks: Array = []                       # [{mi, mat, age}]
var _last_drop: Vector2 = Vector2.ZERO
var _has_last: bool = false
var _quad: QuadMesh = null
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_quad = QuadMesh.new()
	_quad.size = Vector2(1.0, 1.0)           # unit quad, scaled per mark
	_rng.seed = 0x5EED


# flame_size is the flame's on-screen edge (render units); world_scale scales content ->
# render, so a mark of content size flame_size/world_scale renders at flame_size.
func update(scroll: Vector2, world_scale: float, flame_size: float, delta: float) -> void:
	if world_root == null:
		return

	# Age + fade existing marks; free expired ones.
	var alive: Array = []
	for m in _marks:
		if not is_instance_valid(m.mi):
			continue
		m.age += delta
		var f: float = 1.0 - m.age / lifetime
		if f <= 0.0:
			m.mi.queue_free()
			continue
		m.mat.set_shader_parameter("fade", f)
		alive.append(m)
	_marks = alive

	var content_size: float = flame_size / maxf(world_scale, 0.0001)
	if not _has_last:
		_has_last = true
		_last_drop = scroll
		_drop(scroll, content_size)
	elif scroll.distance_to(_last_drop) >= content_size * drop_fraction:
		_last_drop = scroll
		_drop(scroll, content_size)


func _drop(scroll: Vector2, content_size: float) -> void:
	if _marks.size() >= max_marks:
		var oldest = _marks.pop_front()
		if is_instance_valid(oldest.mi):
			oldest.mi.queue_free()

	var gy: float = 0.02
	if height_field != null:
		gy = height_field.height(scroll.x, scroll.y) + 0.02   # sit on the ground surface
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	mi.rotation.x = -PI * 0.5                 # lie flat, facing up
	mi.rotation.z = _rng.randf_range(0.0, TAU)
	mi.position = Vector3(scroll.x, gy, scroll.y)   # flame's content position at drop time
	mi.scale = Vector3(content_size, content_size, 1.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat := ShaderMaterial.new()
	mat.shader = ScorchShader
	mat.set_shader_parameter("fade", 1.0)
	mat.set_shader_parameter("seed", _rng.randf())
	mi.material_override = mat

	world_root.add_child(mi)
	_marks.append({"mi": mi, "mat": mat, "age": 0.0})


func active_mark_count() -> int:
	return _marks.size()
