class_name MovementTrail extends Node3D

const ScorchShader := preload("res://shaders/scorch.gdshader")

@export var scorch_interval: float = 0.12
# Brief's own open question (fade-vs-persist) -- defaulting to fade;
# revisit if it reads wrong in playtest.
@export var scorch_fade_duration: float = 25.0
@export var move_speed_threshold: float = 0.15
# Scorch mark is sized relative to the flame's own real-world footprint
# (flame_scale is meters -- see growth_controller.gd), with a floor so it
# never shrinks to an invisible sliver at match-scale.
@export var scorch_size_ratio: float = 1.5
@export var scorch_min_size: float = 0.03

var flame: Node3D
var decal_parent: Node3D

var _scorch_timer: float = 0.0
var _embers: GPUParticles3D


func _ready() -> void:
	# Structurally a child of Flame, so the parent link is always correct --
	# no NodePath export needed (see prop_manager.gd's comment on why hand
	# authored NodePath literals don't resolve for Node-typed @export vars).
	flame = get_parent() as Node3D
	# Decals must live in world space under something that never moves (not
	# Flame, not this node), so they stay behind at their spawn position
	# instead of dragging along with the flame.
	decal_parent = get_tree().current_scene
	_build_embers()


func _process(delta: float) -> void:
	if not flame:
		return
	var speed: float = (flame.velocity as Vector3).length() if "velocity" in flame else 0.0
	var moving: bool = speed > move_speed_threshold
	var scale_factor: float = flame.scale_factor if "scale_factor" in flame else 0.02

	_embers.emitting = moving
	# Track the flame's own grounding height (see flame.gd::set_scale_factor)
	# so embers ride at the flame's actual base instead of a fixed offset
	# that would read as floating above a tiny match-scale flame.
	_embers.position.y = scale_factor * 0.5

	_scorch_timer -= delta
	if moving and _scorch_timer <= 0.0:
		_scorch_timer = scorch_interval
		_spawn_scorch_mark(scale_factor)


# Soft-edged circular burn mark via scorch.gdshader (UV-distance falloff) --
# not a flat opaque box -- fading out over scorch_fade_duration by animating
# the shader's own "fade" uniform rather than tweening mesh scale/alpha.
func _spawn_scorch_mark(scale_factor: float) -> void:
	if not decal_parent:
		return
	var s: float = maxf(scale_factor * scorch_size_ratio, scorch_min_size)

	var decal := MeshInstance3D.new()
	var m := QuadMesh.new()
	m.size = Vector2(s, s)
	decal.mesh = m
	decal.rotation_degrees = Vector3(-90, 0, 0)  # lie flat, facing up

	var mat := ShaderMaterial.new()
	mat.shader = ScorchShader
	mat.set_shader_parameter("fade", 1.0)
	mat.set_shader_parameter("scorch_color", Color(0.05, 0.03, 0.02))
	decal.material_override = mat

	# add_child() first -- global_position can't be set on a node that isn't
	# in the tree yet (there's no parent transform to resolve it against).
	decal_parent.add_child(decal)
	decal.global_position = Vector3(flame.global_position.x, 0.005, flame.global_position.z)

	var tw := decal.create_tween()
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("fade", v), 1.0, 0.0, scorch_fade_duration)
	tw.tween_callback(decal.queue_free)


func _build_embers() -> void:
	_embers = GPUParticles3D.new()
	_embers.amount = 24
	_embers.lifetime = 0.6
	_embers.emitting = false

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 25.0
	mat.initial_velocity_min = 0.15
	mat.initial_velocity_max = 0.4
	mat.gravity = Vector3(0, 0.3, 0)
	mat.scale_min = 0.8
	mat.scale_max = 1.6
	mat.color = Color(1.0, 0.45, 0.05)
	_embers.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	_embers.draw_pass_1 = quad

	add_child(_embers)
