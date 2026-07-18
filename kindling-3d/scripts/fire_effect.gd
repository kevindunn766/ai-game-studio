class_name FireEffect extends Node3D

# A reusable fire + smoke visual built entirely from Godot primitives and
# procedural textures -- no external asset, per the studio's grey-box rule.
#
# Authored for a ~1m-tall reference fire at node scale 1. The Flame scales THIS
# node's transform (see flame.gd::set_scale_factor), so the same effect serves
# the whole 2cm..140m range: a node scale of 0.02 renders a 2cm match flicker,
# 140 renders a city-block inferno. Children use local_coords = true so node
# scaling scales the whole simulation (positions AND velocities), keeping the
# fire physically proportional at every size.
#
# Physics modeled (see DESIGN.md fire notes): buoyancy (particles accelerate
# upward and taper), a blackbody cooling gradient (white-yellow core -> orange
# -> red -> fades to nothing as it cools), turbulence for the flicker/lick, and
# a separate slower-rising, expanding, alpha-blended smoke plume above the fire.

@export var fire_amount: int = 40
@export var smoke_amount: int = 14
# Multiplies particle sizes/velocities so the same script can author a bright
# tight leading core vs. a softer trailing body from one class.
@export var intensity: float = 1.0

var _fire: GPUParticles3D
var _smoke: GPUParticles3D


func _ready() -> void:
	_smoke = _build_smoke()
	_fire = _build_fire()
	# Smoke added first so the additive fire draws over it.
	add_child(_smoke)
	add_child(_fire)


func set_emitting(on: bool) -> void:
	if _fire:
		_fire.emitting = on
	if _smoke:
		_smoke.emitting = on


# Froude-scaling flicker (see DESIGN.md): real diffusion flames flicker at
# f ~= 1.5/sqrt(D), so a match shimmers fast and a city fire billows slowly.
# node scale here is the flame's real size in meters. speed_scale drives the
# whole sim rate, so smaller = quicker, clamped so it never gets frantic or
# stalls.
func set_flicker_for_scale(meters: float) -> void:
	var s: float = clampf(0.45 / sqrt(maxf(meters, 0.04)), 0.6, 2.6)
	if _fire:
		_fire.speed_scale = s
	if _smoke:
		_smoke.speed_scale = clampf(s * 0.8, 0.5, 2.0)


func _build_fire() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Fire"
	p.amount = fire_amount
	p.lifetime = 0.7
	p.local_coords = true
	p.randomness = 0.4
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12 * intensity
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 16.0
	pm.initial_velocity_min = 0.5 * intensity
	pm.initial_velocity_max = 1.0 * intensity
	# Positive-Y gravity = buoyancy: hot gas accelerates upward as it rises.
	pm.gravity = Vector3(0.0, 0.9 * intensity, 0.0)
	pm.damping_min = 0.1
	pm.damping_max = 0.3
	# scale_min/max are multipliers on the draw mesh -> a real spread of small
	# particle sizes, never one uniform square.
	pm.scale_min = 0.35
	pm.scale_max = 1.1
	pm.scale_curve = _fire_scale_curve()
	pm.color = Color(1, 1, 1, 1)
	pm.color_ramp = _fire_color_ramp()
	pm.hue_variation_min = -0.03
	pm.hue_variation_max = 0.03
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.5
	pm.turbulence_noise_scale = 1.4
	pm.turbulence_influence_min = 0.1
	pm.turbulence_influence_max = 0.35
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.3, 0.3) * intensity
	quad.material = _particle_material(true)
	p.draw_pass_1 = quad
	return p


func _build_smoke() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Smoke"
	p.amount = smoke_amount
	p.lifetime = 2.0
	p.local_coords = true
	p.randomness = 0.5
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.1 * intensity
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 22.0
	pm.initial_velocity_min = 0.35 * intensity
	pm.initial_velocity_max = 0.6 * intensity
	pm.gravity = Vector3(0.0, 0.5 * intensity, 0.0)
	pm.damping_min = 0.2
	pm.damping_max = 0.5
	# Smoke EXPANDS over its life (opposite of the tapering fire) and is larger.
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.scale_curve = _smoke_scale_curve()
	pm.color = Color(1, 1, 1, 1)
	pm.color_ramp = _smoke_color_ramp()
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.35
	pm.turbulence_noise_scale = 1.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.2
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.45, 0.45) * intensity
	quad.material = _particle_material(false)
	p.draw_pass_1 = quad
	return p


# --- Shared procedural resources ------------------------------------------

# A soft round particle: white core fading to transparent at the edge, built
# from a radial GradientTexture2D so there's no square hard edge and no
# external texture file. Tint/blend come from the particle color_ramp +
# material blend mode, so one shape texture serves both fire and smoke.
static func soft_particle_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([
		Color(1, 1, 1, 1.0),
		Color(1, 1, 1, 0.45),
		Color(1, 1, 1, 0.0),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex


# additive = true for fire (light-emitting, cool end fades out naturally);
# false = alpha/mix for smoke (blocks light).
static func _particle_material(additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.albedo_texture = soft_particle_texture()
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.particles_anim_h_frames = 1
	m.particles_anim_v_frames = 1
	m.particles_anim_loop = false
	m.disable_receive_shadows = true
	return m


static func _fire_color_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.3, 0.65, 1.0])
	g.colors = PackedColorArray([
		Color(1.0, 0.95, 0.65, 1.0),  # hot white-yellow core
		Color(1.0, 0.6, 0.15, 1.0),   # orange
		Color(0.9, 0.25, 0.05, 0.7),  # cooling red
		Color(0.25, 0.03, 0.0, 0.0),  # burnt out, transparent
	])
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func _smoke_color_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	g.colors = PackedColorArray([
		Color(0.2, 0.18, 0.17, 0.0),   # fade in
		Color(0.16, 0.15, 0.14, 0.45), # thin grey
		Color(0.1, 0.1, 0.1, 0.0),     # dissipate
	])
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func _fire_scale_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.5))
	c.add_point(Vector2(0.22, 1.0))
	c.add_point(Vector2(1.0, 0.0))  # taper to a point
	var t := CurveTexture.new()
	t.curve = c
	return t


static func _smoke_scale_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.3))
	c.add_point(Vector2(1.0, 1.3))  # billow outward as it rises
	var t := CurveTexture.new()
	t.curve = c
	return t
