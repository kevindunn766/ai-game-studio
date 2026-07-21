extends Node3D

# Reusable detonation VFX in THREE particle types (Kevin), all CPUParticles3D so
# they're guaranteed on the GL Compatibility renderer this project ships:
#   1. BURST  -- bright RED and YELLOW bits that radially fly out in all directions.
#   2. SPARKS -- small bits that fling out and FALL, FLICKERING at the end of the fall.
#   3. SMOKE  -- a plume that starts bright + fiery then cools to dark grey and black
#                as it rises and fades (a beat after the burst).
# All particles are medium-to-small and randomly sized. Self-frees when done.
#
# Fields set by the spawner before add_child:
#   accent    -> theme tint mixed lightly into the smoke
#   scale_ref -> overall size of the blast (bigger mine = bigger boom)

var accent: Color = Color(1.0, 0.8, 0.4, 1.0)
var scale_ref: float = 1.0

const RED := Color(1.0, 0.16, 0.06)
const YELLOW := Color(1.0, 0.85, 0.22)

func _ready() -> void:
	# The burst is two colours so it reads as a spray of red AND yellow bits.
	_burst(RED, 11)
	_burst(YELLOW, 13)
	_sparks()
	_smoke_then_free()

# Layer 1: a radial fling of bright bits (called once per colour).
func _burst(col: Color, amount: int) -> void:
	var p := _new_particles(true)
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = randf_range(0.24, 0.34)
	p.spread = 180.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 6.0 * scale_ref
	p.initial_velocity_max = 13.0 * scale_ref
	p.scale_amount_min = 0.18 * scale_ref      # small-medium, randomly sized
	p.scale_amount_max = 0.42 * scale_ref
	p.color = col
	p.color_ramp = _ramp(col, 1.0, 0.0)
	add_child(p)

# Layer 2: sparks fling out, fall, and flicker as they burn out.
func _sparks() -> void:
	var p := _new_particles(true)
	p.explosiveness = 1.0
	p.amount = 24
	p.lifetime = randf_range(0.8, 1.15)
	p.spread = 180.0
	p.gravity = Vector3(0.0, -9.5 * scale_ref, 0.0)   # fall
	p.initial_velocity_min = 4.0 * scale_ref
	p.initial_velocity_max = 9.0 * scale_ref
	p.damping_min = 0.5
	p.damping_max = 1.6                         # slow a touch so they arc over
	p.scale_amount_min = 0.05 * scale_ref       # small, randomly sized
	p.scale_amount_max = 0.15 * scale_ref
	var spark: Color = Color(1.0, 0.82, 0.38)
	p.color = spark
	p.color_ramp = _flicker_ramp(spark)         # steady, then flickers at the end of the fall
	add_child(p)

# Layer 3: smoke plume -- randomly sized, fiery -> grey -> black, rises, then frees.
func _smoke_then_free() -> void:
	await get_tree().create_timer(0.04).timeout
	if not is_instance_valid(self):
		return
	var plume: float = randf_range(0.7, 1.4)    # random overall plume size per blast
	var p := _new_particles(false)
	p.explosiveness = 0.7
	p.amount = 22
	p.lifetime = randf_range(1.1, 1.7)
	p.spread = 55.0
	p.direction = Vector3(0, 1, 0)
	p.gravity = Vector3(0.0, 1.7 * scale_ref, 0.0)    # rise
	p.initial_velocity_min = 0.8 * scale_ref
	p.initial_velocity_max = 2.8 * scale_ref
	p.scale_amount_min = 0.35 * scale_ref * plume     # medium, randomly sized
	p.scale_amount_max = 0.9 * scale_ref * plume
	p.color = Color(1.0, 0.75, 0.3)
	p.color_ramp = _smoke_ramp()                # bright fiery -> dark grey -> black
	add_child(p)

	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(self):
		queue_free()

# --- Gradients ----------------------------------------------------------------
# Simple fade (start alpha -> end alpha) for the burst bits.
func _ramp(base: Color, a0: float, a1: float) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(base.r, base.g, base.b, a0))
	g.set_color(1, Color(base.r, base.g, base.b, a1))
	return g

# Steady for the first half, then rapid on/off flicker as the spark burns out.
func _flicker_ramp(c: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(c.r, c.g, c.b, 1.0))
	g.set_color(1, Color(c.r, c.g, c.b, 0.0))
	g.add_point(0.5, Color(c.r, c.g, c.b, 1.0))
	g.add_point(0.62, Color(c.r, c.g, c.b, 0.2))
	g.add_point(0.72, Color(c.r, c.g, c.b, 1.0))
	g.add_point(0.82, Color(c.r, c.g, c.b, 0.15))
	g.add_point(0.9, Color(c.r, c.g, c.b, 0.9))
	g.add_point(0.96, Color(c.r, c.g, c.b, 0.1))
	return g

# Smoke cools over its life: bright fiery orange -> red -> dark grey -> black,
# with the alpha easing out at the very end. Accent tints the grey a touch.
func _smoke_ramp() -> Gradient:
	var grey: Color = Color(0.26, 0.25, 0.26).lerp(accent.darkened(0.55), 0.25)
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.78, 0.32, 0.95))     # bright, fiery
	g.set_color(1, Color(0.03, 0.03, 0.03, 0.0))      # black, gone
	g.add_point(0.18, Color(1.0, 0.42, 0.12, 0.95))   # fiery orange
	g.add_point(0.4, Color(0.5, 0.22, 0.12, 0.85))    # cooling ember
	g.add_point(0.62, Color(grey.r, grey.g, grey.b, 0.7))   # dark grey
	g.add_point(0.85, Color(0.06, 0.06, 0.06, 0.4))   # near-black, fading
	return g

# --- Particle factory ---------------------------------------------------------
# A one-shot CPUParticles3D with a unit billboard quad (final size = scale_amount).
func _new_particles(additive: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = _mat(additive)
	p.mesh = q
	return p

func _mat(additive: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	return mat
