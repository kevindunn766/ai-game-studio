extends RefCounted

# Shared lightweight particle helpers (2026-07-19). One tiny world-space CPUParticles3D
# used for both the player's engine jets and the enemies' motion trails: because it sims
# in WORLD space (local_coords = false), simply moving the emitter leaves a trail behind
# it -- no per-frame code. Kept cheap on purpose: small counts, small billboards, no
# gravity, additive glow, and the amount scales with PerfProfile.particle_scale (0 on the
# lowest tier -> the caller skips it entirely). No class_name (headless-safe; preload it).

# A small trailing emitter. `size` is the billboard's world size (kept small);
# `back_speed` (world units/sec along `back_dir`) gives the player jet a bit of plume,
# enemies pass 0 and just leave puffs their motion trails. Colour fades to transparent
# over `lifetime`.
static func trail(color: Color, size: float, amount: int, lifetime: float, back_dir: Vector3, back_speed: float, additive: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.local_coords = false                       # world sim -> the emitter's motion draws the trail
	p.amount = maxi(1, amount)
	p.lifetime = lifetime
	p.explosiveness = 0.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT
	if back_speed > 0.0 and back_dir.length() > 0.001:
		p.direction = back_dir.normalized()
		p.spread = 8.0
		p.initial_velocity_min = back_speed * 0.7
		p.initial_velocity_max = back_speed * 1.1
	else:
		p.spread = 0.0
		p.initial_velocity_min = 0.0
		p.initial_velocity_max = 0.0
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.15

	var q := QuadMesh.new()
	q.size = Vector2(size, size)                 # small on purpose
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED   # billboard has no meaningful backface
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	q.material = m
	p.mesh = q

	var g := Gradient.new()
	g.set_color(0, Color(color.r, color.g, color.b, color.a))
	g.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = g
	return p
