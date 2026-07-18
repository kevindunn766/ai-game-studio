class_name MovementTrail extends Node3D

const ScorchShader := preload("res://shaders/scorch.gdshader")
# preload const rather than the FireEffect class_name global -- a brand-new
# class_name doesn't resolve when this script is parsed headless (see the
# studio's godot class_name/headless note); the const path always resolves.
const FireEffectScript := preload("res://scripts/fire_effect.gd")

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

# Trail particle base params, authored for a ~1m fire and multiplied by the
# flame's real size each frame (see _apply_trail_scale). Embers are the
# short-lived fire flourish; smoke lingers longer and drifts up behind.
const EMBER_AMOUNT: int = 22
const EMBER_LIFETIME: float = 0.55
const EMBER_QUAD: float = 0.16
const EMBER_VEL := Vector2(0.25, 0.6)   # (min, max) initial velocity
const EMBER_GRAVITY: float = 0.45
const SMOKE_AMOUNT: int = 12
const SMOKE_LIFETIME: float = 1.5
const SMOKE_QUAD: float = 0.24
const SMOKE_VEL := Vector2(0.12, 0.32)
const SMOKE_GRAVITY: float = 0.28

var flame: Node3D
var decal_parent: Node3D

var _scorch_timer: float = 0.0
var _embers: GPUParticles3D
var _smoke: GPUParticles3D


func _ready() -> void:
	# Structurally a child of Flame, so the parent link is always correct --
	# no NodePath export needed (see prop_manager.gd's comment on why hand
	# authored NodePath literals don't resolve for Node-typed @export vars).
	flame = get_parent() as Node3D
	# Decals must live in world space under something that never moves (not
	# Flame, not this node), so they stay behind at their spawn position
	# instead of dragging along with the flame.
	decal_parent = get_tree().current_scene
	_build_trail()


func _process(delta: float) -> void:
	if not flame:
		return
	var speed: float = (flame.velocity as Vector3).length() if "velocity" in flame else 0.0
	var moving: bool = speed > move_speed_threshold
	var scale_factor: float = flame.scale_factor if "scale_factor" in flame else 0.02
	var s: float = maxf(scale_factor, 0.02)

	# Emit only while moving so the trail visibly diminishes to nothing when
	# the flame stops -- the leftover world-space particles keep rising/fading
	# on their own after emission cuts off.
	_embers.emitting = moving
	_smoke.emitting = moving
	# Ride just off the flame's base (fire trails from the bottom, smoke a bit
	# higher) -- tracks the flame's grounding height like the old embers did.
	_embers.position.y = s * 0.15
	_smoke.position.y = s * 0.35
	_apply_trail_scale(_embers, EMBER_QUAD, EMBER_VEL, EMBER_GRAVITY, s)
	_apply_trail_scale(_smoke, SMOKE_QUAD, SMOKE_VEL, SMOKE_GRAVITY, s)

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


func _build_trail() -> void:
	# Smoke first so the additive embers draw on top of it.
	_smoke = _make_trail_particles(false, SMOKE_AMOUNT, SMOKE_LIFETIME, SMOKE_QUAD)
	_embers = _make_trail_particles(true, EMBER_AMOUNT, EMBER_LIFETIME, EMBER_QUAD)
	add_child(_smoke)
	add_child(_embers)


# additive = fire embers (light-emitting), else = smoke (alpha). local_coords
# is left false (world space) so emitted particles STAY BEHIND in the world and
# fade where they were dropped -- that world-space persistence is what makes a
# moving flame leave a trail, rather than dragging its particles along with it.
func _make_trail_particles(additive: bool, amount: int, lifetime: float, quad_size: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.emitting = false
	p.local_coords = false
	p.randomness = 0.5
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = quad_size * 0.4
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 32.0
	pm.color = Color(1, 1, 1, 1)
	pm.color_ramp = FireEffectScript._fire_color_ramp() if additive else FireEffectScript._smoke_color_ramp()
	# A spread of small sizes, never a uniform square.
	pm.scale_min = 0.3
	pm.scale_max = 1.0
	if additive:
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 0.4
		pm.turbulence_noise_scale = 1.2
		pm.turbulence_influence_min = 0.05
		pm.turbulence_influence_max = 0.25
	else:
		pm.scale_curve = FireEffectScript._smoke_scale_curve()  # smoke billows outward
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(quad_size, quad_size)
	quad.material = FireEffectScript._particle_material(additive)
	p.draw_pass_1 = quad
	return p


# Trail particles are world-space, so the emitter node's own scale doesn't
# reliably drive particle size -- instead scale the draw mesh, initial
# velocity and buoyancy by the flame's real size each frame, so a match-scale
# trail is a faint few-cm wisp and a Band-9 trail is a rolling wall of fire.
func _apply_trail_scale(p: GPUParticles3D, base_quad: float, base_vel: Vector2, base_gravity: float, s: float) -> void:
	(p.draw_pass_1 as QuadMesh).size = Vector2(base_quad, base_quad) * s
	var pm := p.process_material as ParticleProcessMaterial
	pm.emission_sphere_radius = base_quad * 0.4 * s
	pm.initial_velocity_min = base_vel.x * s
	pm.initial_velocity_max = base_vel.y * s
	pm.gravity = Vector3(0, base_gravity * s, 0)
