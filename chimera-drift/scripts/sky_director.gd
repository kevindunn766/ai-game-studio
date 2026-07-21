extends RefCounted

# Builds a procedurally-rolled sky per level. 100% procedural: it only rolls a
# seed from the level's own words and pushes uniforms into procedural_sky.gdshader
# -- no textures. Deterministic per level (same words -> same sky), and it reuses
# the rolled LevelTheme palette so the sky belongs to the level it frames.
#
# Sky is only meaningful where the horizon/background is visible: SURFACE (sky
# over the terrain) and OPEN_VOLUME (space is the backdrop). Corridor is enclosed
# and opts out (caller keeps its flat background + fog).
#
# build() returns a config the caller applies to the Environment + DirectionalLight
# (the shader reads the sun from LIGHT0, so the light must be oriented to match).

const SKY_SHADER := preload("res://shaders/procedural_sky.gdshader")
const MAX_BODIES := 4

# Shape family ints (match LevelSeed.ShapeFamily; kept literal to avoid autoload
# coupling in this helper).
const SURFACE := 1
const OPEN_VOLUME := 2
const CANYON := 3      # surface-like: open sky over a walled gorge
const PILLARED := 4    # surface-like: open sky over a pillar field

# Body types in the shader.
const T_MOON := 0
const T_GAS := 1
const T_RINGED := 2

# The elevated / overhead views look down across a lot of background, and the
# dramatic procedural sky (night atmospheres, deep-space void) can leave the play
# field dim and hard to read. These viewpoints instead get a flat two-colour theme
# gradient with bright even ambient, so everything stays well lit. The immersive
# thirdperson / sidescroll views keep the full procedural sky.
const GRADIENT_VIEWPOINTS := ["threequarter", "topdown", "isometric"]

static func build(rolled_level: Dictionary, theme: Dictionary, sky_quality: int = 3, radiance_size: int = Sky.RADIANCE_SIZE_128) -> Dictionary:
	var viewpoint: String = rolled_level.get("viewpoint", "")
	if viewpoint in GRADIENT_VIEWPOINTS:
		return _build_gradient(theme, radiance_size)

	var shape: int = rolled_level.get("shape_family", 0)
	var surface_like: bool = shape == SURFACE or shape == CANYON or shape == PILLARED
	if not surface_like and shape != OPEN_VOLUME:
		return {"use_sky": false}

	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_of(rolled_level)

	var mat := ShaderMaterial.new()
	mat.shader = SKY_SHADER
	mat.set_shader_parameter("quality", sky_quality)   # perf tier -> sample counts / layers

	var cfg: Dictionary
	if surface_like:
		cfg = _build_surface(mat, rng, rolled_level, theme)
	else:
		cfg = _build_space(mat, rng, rolled_level, theme)

	var sky := Sky.new()
	sky.sky_material = mat
	# Radiance (IBL) resolution scales with the perf tier; incremental spreads the
	# cubemap update cost over frames.
	sky.radiance_size = radiance_size
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	cfg["use_sky"] = true
	cfg["sky"] = sky
	return cfg

# --- Two-colour theme gradient (overhead / angled views) -------------------
# A ProceduralSkyMaterial gradient between two theme colours: a bright tint of the
# accent up top fading to the theme fog at the horizon. Used as the ambient/reflection
# source at high energy so the whole scene is evenly, brightly lit -- no dark corners
# in the orthographic-ish views. Deterministic (no RNG): same theme -> same gradient.
static func _build_gradient(theme: Dictionary, radiance_size: int) -> Dictionary:
	var accent: Color = theme.get("accent", Color(0.6, 0.75, 1.0))
	var fog: Color = theme.get("fog", Color(0.4, 0.45, 0.55))

	var top_color: Color = accent.lerp(Color.WHITE, 0.4)     # bright zenith
	var horizon_color: Color = fog.lerp(Color.WHITE, 0.15)   # lighter toward the horizon

	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = top_color
	mat.sky_horizon_color = horizon_color
	mat.sky_curve = 0.15
	mat.sky_energy_multiplier = 1.0
	# Ground half mirrors the gradient (kept bright) so ambient fills from below too.
	mat.ground_horizon_color = horizon_color
	mat.ground_bottom_color = fog.lerp(Color.WHITE, 0.05)
	mat.ground_curve = 0.1
	mat.ground_energy_multiplier = 1.0
	mat.sun_angle_max = 30.0
	mat.sun_curve = 0.15

	var sky := Sky.new()
	sky.sky_material = mat
	sky.radiance_size = radiance_size
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL

	# A soft key light from high overhead keeps geometry readable with short shadows;
	# most of the fill comes from the bright sky ambient.
	return {
		"use_sky": true,
		"sky": sky,
		"sun_toward": Vector3(0.35, 0.9, 0.2).normalized(),
		"sun_color": Color(1.0, 0.98, 0.95),
		"sun_energy": 0.9,
		"ambient_color": top_color,
		"ambient_energy": 1.3,
	}

# Deterministic per-level seed from the level's own words.
static func _seed_of(rl: Dictionary) -> int:
	var s: String = "%s|%s|%s|%s" % [
		rl.get("shape_word", ""), rl.get("modifier_word", ""),
		rl.get("structure_type", ""), rl.get("viewpoint", "")]
	return abs(hash(s))

static func _sun_toward(az: float, el: float) -> Vector3:
	return Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az)).normalized()

# --- SURFACE: atmosphere, time-of-day, clouds, occasional moon -------------
static func _build_surface(mat: ShaderMaterial, rng: RandomNumberGenerator, rl: Dictionary, theme: Dictionary) -> Dictionary:
	var accent: Color = theme.get("accent", Color(0.7, 0.8, 1.0))
	var fog: Color = theme.get("fog", Color(0.5, 0.6, 0.75))
	var floor_c: Color = theme.get("floor", Color(0.3, 0.3, 0.35))
	var modifier: String = rl.get("modifier_word", "")

	# Time of day -- some modifiers bias it (spooky -> night, hot -> sunset).
	var tod_roll: float = rng.randf()
	var tod: String
	if modifier in ["Haunted", "Bioluminescent", "Storm-Wracked"]:
		tod = "night" if tod_roll < 0.6 else "sunset"
	elif modifier in ["Molten", "Irradiated", "Toxic"]:
		tod = "sunset" if tod_roll < 0.6 else "day"
	else:
		tod = ["day", "day", "sunset", "night"][int(tod_roll * 4.0) % 4]

	var az: float = rng.randf_range(0.0, TAU)
	var el: float
	var sun_color: Color
	var sun_energy: float
	var star_density: float = 0.0
	var milkyway: float = 0.0
	match tod:
		"day":
			el = rng.randf_range(0.5, 1.1)
			sun_color = Color(1.0, 0.97, 0.92)
			sun_energy = 1.0
		"sunset":
			el = rng.randf_range(0.02, 0.14)
			sun_color = accent.lerp(Color(1.0, 0.5, 0.25), 0.6)
			sun_energy = 1.0
		_:  # night
			el = rng.randf_range(-0.35, -0.08)
			sun_color = Color(0.6, 0.7, 1.0)
			sun_energy = 0.25
			star_density = rng.randf_range(0.5, 0.9)
			milkyway = rng.randf_range(0.3, 0.8)

	mat.set_shader_parameter("atmosphere_strength", 1.0)
	mat.set_shader_parameter("sun_tint", sun_color)
	mat.set_shader_parameter("sun_disk_size", 0.028)
	mat.set_shader_parameter("mie_amount", rng.randf_range(0.8, 1.6))
	mat.set_shader_parameter("ground_color", floor_c.darkened(0.5))
	mat.set_shader_parameter("space_color", Color(0.01, 0.012, 0.02))
	mat.set_shader_parameter("exposure", 1.0)

	# Clouds tinted subtly to the biome; coverage varies (sometimes clear).
	var cover: float = 0.0 if rng.randf() < 0.25 else rng.randf_range(0.2, 0.7)
	mat.set_shader_parameter("cloud_cover", cover)
	mat.set_shader_parameter("cloud_scale", rng.randf_range(1.6, 3.0))
	mat.set_shader_parameter("cloud_color", Color(1, 1, 1).lerp(fog, 0.25))
	mat.set_shader_parameter("cloud_shadow_color", fog.darkened(0.45))
	mat.set_shader_parameter("cloud_speed", rng.randf_range(0.003, 0.01))

	mat.set_shader_parameter("star_density", star_density)
	mat.set_shader_parameter("star_brightness", 1.2)
	mat.set_shader_parameter("milkyway_strength", milkyway)
	mat.set_shader_parameter("milkyway_axis", _rand_axis(rng))
	mat.set_shader_parameter("galaxy_strength", 0.0)
	mat.set_shader_parameter("nebula_strength", 0.0)

	# Occasional moon (day or night) or a ringed planet low on the horizon.
	var bodies: Array = []
	if rng.randf() < 0.55:
		bodies.append(_roll_body(rng, theme, _horizon_dir(rng, az), true))
	_apply_bodies(mat, bodies)

	var ambient: Color = fog if tod != "night" else Color(0.06, 0.07, 0.12)
	return {
		"sun_toward": _sun_toward(az, el),
		"sun_color": sun_color, "sun_energy": maxf(sun_energy, 0.35),
		"ambient_color": ambient, "ambient_energy": 1.0 if tod != "night" else 0.4,
		"tod": tod,   # day / sunset / night -> drives the ship headlight energy
	}

# --- OPEN_VOLUME: deep space, stars, galaxy, nebula, big bodies -------------
static func _build_space(mat: ShaderMaterial, rng: RandomNumberGenerator, rl: Dictionary, theme: Dictionary) -> Dictionary:
	var accent: Color = theme.get("accent", Color(0.6, 0.7, 1.0))
	var walls2: Color = theme.get("walls2", Color(0.4, 0.5, 0.8))
	var structure: String = rl.get("structure_type", "")
	var shape_word: String = rl.get("shape_word", "")

	mat.set_shader_parameter("atmosphere_strength", 0.0)
	mat.set_shader_parameter("space_color", accent.darkened(0.9))
	mat.set_shader_parameter("cloud_cover", 0.0)
	mat.set_shader_parameter("star_density", rng.randf_range(0.6, 1.0))
	mat.set_shader_parameter("star_brightness", rng.randf_range(1.0, 1.6))
	mat.set_shader_parameter("milkyway_strength", rng.randf_range(0.0, 0.5))
	mat.set_shader_parameter("milkyway_axis", _rand_axis(rng))
	mat.set_shader_parameter("mie_amount", 1.0)
	mat.set_shader_parameter("exposure", 1.0)

	# Nebula strength keyed to the flavor word.
	var nebula_words := ["Nebula", "Ion Storm", "Plasma", "Solar Flare", "Corona", "Cloud"]
	var nebula_bias: float = 0.0
	for w in nebula_words:
		if w in shape_word:
			nebula_bias = 0.6
	var nebula: float = clampf(nebula_bias + rng.randf_range(-0.1, 0.5), 0.0, 1.0)
	mat.set_shader_parameter("nebula_strength", nebula)
	mat.set_shader_parameter("nebula_color_a", accent)
	mat.set_shader_parameter("nebula_color_b", walls2)
	mat.set_shader_parameter("nebula_scale", rng.randf_range(1.0, 2.0))

	# Galaxy sometimes present.
	var galaxy: float = rng.randf_range(0.0, 1.0)
	galaxy = 0.0 if galaxy < 0.45 else rng.randf_range(0.4, 1.0)
	mat.set_shader_parameter("galaxy_strength", galaxy)
	mat.set_shader_parameter("galaxy_dir", _rand_axis(rng))
	mat.set_shader_parameter("galaxy_axis", _rand_axis(rng))
	mat.set_shader_parameter("galaxy_core_color", Color(1.0, 0.9, 0.7))
	mat.set_shader_parameter("galaxy_arm_color", accent.lerp(Color(0.6, 0.7, 1.0), 0.5))
	mat.set_shader_parameter("galaxy_arms", float(rng.randi_range(2, 4)))
	mat.set_shader_parameter("galaxy_twist", rng.randf_range(5.0, 9.0))

	# A sun for the level. Sun-flavored words get a big bright one.
	var sun_big: bool = ("Sun" in shape_word) or ("Solar" in shape_word) or ("Corona" in shape_word)
	var az: float = rng.randf_range(0.0, TAU)
	var el: float = rng.randf_range(-0.3, 0.6)
	var sun_color: Color = Color(1.0, 0.95, 0.88) if not sun_big else accent.lerp(Color(1.0, 0.6, 0.3), 0.5)
	mat.set_shader_parameter("sun_tint", sun_color)
	mat.set_shader_parameter("sun_disk_size", 0.12 if sun_big else rng.randf_range(0.01, 0.03))

	# Celestial bodies: gas giants / ringed planets / moons scattered around.
	var count: int = rng.randi_range(1, 3)
	if "Ring System" in shape_word:
		count = maxi(count, 2)
	var bodies: Array = []
	for i in range(count):
		bodies.append(_roll_body(rng, theme, _rand_axis(rng), false))
	if "Ring System" in shape_word and not bodies.is_empty():
		bodies[0]["type"] = T_RINGED
	_apply_bodies(mat, bodies)

	return {
		"sun_toward": _sun_toward(az, el),
		"sun_color": sun_color, "sun_energy": 1.0 if not sun_big else 1.4,
		"ambient_color": accent.darkened(0.4), "ambient_energy": 0.5,
	}

# --- helpers ---------------------------------------------------------------
static func _rand_axis(rng: RandomNumberGenerator) -> Vector3:
	return Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()

# A direction sitting a little above the horizon (for surface bodies).
static func _horizon_dir(rng: RandomNumberGenerator, base_az: float) -> Vector3:
	var az: float = base_az + rng.randf_range(1.5, 4.5)
	var el: float = rng.randf_range(0.05, 0.35)
	return _sun_toward(az, el)

static func _roll_body(rng: RandomNumberGenerator, theme: Dictionary, dir: Vector3, surface: bool) -> Dictionary:
	var accent: Color = theme.get("accent", Color(0.7, 0.7, 0.8))
	var walls: Color = theme.get("walls", Color(0.6, 0.6, 0.65))
	var roll: float = rng.randf()
	var typ: int
	if surface:
		typ = T_MOON if roll < 0.7 else T_RINGED
	else:
		typ = T_MOON if roll < 0.35 else (T_GAS if roll < 0.75 else T_RINGED)
	var size: float
	match typ:
		T_MOON: size = rng.randf_range(0.02, 0.06)
		T_GAS: size = rng.randf_range(0.08, 0.18)
		_: size = rng.randf_range(0.07, 0.14)
	return {
		"dir": dir, "size": size, "type": typ, "axis": _rand_axis(rng),
		"color_a": accent.lerp(walls, rng.randf()),
		"color_b": accent.lerp(Color(1, 0.85, 0.6), rng.randf() * 0.6),
		"seed": rng.randf_range(0.0, 100.0),
		"ring_inner": rng.randf_range(1.3, 1.6),
		"ring_outer": rng.randf_range(2.0, 2.8),
	}

static func _v3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)

static func _apply_bodies(mat: ShaderMaterial, bodies: Array) -> void:
	# Typed Packed arrays so the shader's vec3[]/float[]/int[] uniforms receive
	# the right element type (Color->vec3 needs explicit conversion).
	var dirs := PackedVector3Array()
	var axes := PackedVector3Array()
	var col_a := PackedVector3Array()
	var col_b := PackedVector3Array()
	var sizes := PackedFloat32Array()
	var seeds := PackedFloat32Array()
	var ri := PackedFloat32Array()
	var ro := PackedFloat32Array()
	var types := PackedInt32Array()
	for i in range(MAX_BODIES):
		if i < bodies.size():
			var b: Dictionary = bodies[i]
			dirs.append(b.dir); sizes.append(b.size); types.append(b.type)
			axes.append(b.axis); col_a.append(_v3(b.color_a)); col_b.append(_v3(b.color_b))
			seeds.append(b.seed); ri.append(b.ring_inner); ro.append(b.ring_outer)
		else:
			dirs.append(Vector3.UP); sizes.append(0.0); types.append(0)
			axes.append(Vector3.UP); col_a.append(Vector3.ZERO); col_b.append(Vector3.ZERO)
			seeds.append(0.0); ri.append(1.3); ro.append(2.0)
	mat.set_shader_parameter("body_count", bodies.size())
	mat.set_shader_parameter("body_dir", dirs)
	mat.set_shader_parameter("body_size", sizes)
	mat.set_shader_parameter("body_type", types)
	mat.set_shader_parameter("body_axis", axes)
	mat.set_shader_parameter("body_color_a", col_a)
	mat.set_shader_parameter("body_color_b", col_b)
	mat.set_shader_parameter("body_seed", seeds)
	mat.set_shader_parameter("body_ring_inner", ri)
	mat.set_shader_parameter("body_ring_outer", ro)
