extends Node3D

# ============================================================================
# Chimera Drift — TITLE SCREEN (first pass)
# A hero render of the ship against a space skybox, with a REROLL SHIP button
# that re-rolls the hull's look (a fresh procedural ship each press). The backdrop
# stays put -- only the ship changes. Reuses the beauty-shot showcase components
# (sky / dresser / cinematic camera / speed-streaks).
#
# Standalone for now: no Play flow yet, so this is NOT the boot scene. Wiring it in
# is a Play button + set RunManager.hull_seed to the shown ship (one-liner later).
# ============================================================================

const SkyDirectorS := preload("res://scripts/sky_director.gd")
const LevelThemeS := preload("res://scripts/level_theme.gd")
const ShipHullGeneratorS := preload("res://scripts/ship_hull_generator.gd")
const Dresser := preload("res://scripts/beauty_ship_dresser.gd")
const CameraDirectorS := preload("res://scripts/beauty_camera_director.gd")
const StreakShader := preload("res://shaders/speed_streak.gdshader")
const StarShader := preload("res://shaders/star_point.gdshader")
const GlitchShader := preload("res://shaders/title_glitch.gdshader")
const LensFlareS := preload("res://scripts/lens_flare.gd")

const SHAPE_WORDS := ["Nebula", "Ring System", "Ion Storm", "Deep Space", "Comet Field", "Solar Flare", "Asteroid Belt", "Wormhole"]
const MODIFIERS := ["Storm-Wracked", "Haunted", "Crystalline", "Irradiated", "Molten", "Frozen", "Pristine", "Bioluminescent"]

var _hull_seed: int = 0
var _accent: Color = Color(0.6, 0.8, 1.0)
var _ship_root: Node3D = null
var _director: Node3D = null
var _time: float = 0.0

var _glitch_mat: ShaderMaterial = null   # VHS title glitch
var _glitch: float = 0.0                 # current burst intensity (decays)
var _glitch_cd: float = 1.5              # seconds until the next burst

func _ready() -> void:
	var r := RandomNumberGenerator.new()
	r.randomize()
	_build_environment(r.randi())   # fixed backdrop
	_build_stars()
	_hull_seed = r.randi()
	_rebuild_ship()                 # the part reroll re-rolls
	_build_ui()
	_maybe_capture()

# --- reroll (the button + Enter/Space via the focused button) ---------------
func _reroll() -> void:
	Sfx.play("reroll")
	var r := RandomNumberGenerator.new()
	r.randomize()
	_hull_seed = r.randi()
	_rebuild_ship()

# Start the run with the ship currently shown, and enter the game. start_new_run
# sets RunManager.hull_seed (so the flown ship == the shown ship) and clears the
# permanent loadout for a fresh run; changing scene hands off to the level flow.
func _play() -> void:
	Sfx.play("ui_confirm")
	RunManager.start_new_run(_hull_seed)
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

# --- best-times panel + wipe flow -------------------------------------------
func _records_text() -> String:
	var lines: Array = ["BEST TIMES"]
	# Boss records in a stable order (only those actually set appear).
	for k in ["Core", "Wall", "Ring", "Super Core", "Super Wall", "Super Ring", "Ultra"]:
		if Profile.boss_best.has(k):
			lines.append("  %-11s %5.1fs" % [k, float(Profile.boss_best[k])])
	if Profile.level_best > 0.0:
		var t: int = int(Profile.level_best)
		lines.append("  %-11s %d:%02d" % ["Level", t / 60, t % 60])
	if Profile.best_sector > 0:
		lines.append("  %-11s %d" % ["Deepest", Profile.best_sector])
	return "\n".join(PackedStringArray(lines))

# Confirmation modal -- warns the player they'll lose their NG+ unlock (records kept).
func _ask_reset() -> void:
	var layer := CanvasLayer.new()
	layer.name = "WipeModal"
	layer.layer = 50
	add_child(layer)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var panel := PanelContainer.new()
	var sb := UITheme.box(Color(0.04, 0.05, 0.1, 0.98), UITheme.MAGENTA, 2)
	sb.set_content_margin_all(26)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	vb.custom_minimum_size = Vector2(480, 0)
	panel.add_child(vb)

	var head := UITheme.label("RESET NG+ ?", 26, UITheme.MAGENTA)
	vb.add_child(head)

	var body := UITheme.label(
		"RETURNS YOU TO THE BASE GAME. YOU MUST BEAT IT AGAIN TO UNLOCK NG+.  YOUR BEST-TIME RECORDS ARE KEPT.",
		13, UITheme.TEXT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(440, 0)
	vb.add_child(body)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)

	var cancel := Button.new()
	cancel.text = "CANCEL"
	cancel.custom_minimum_size = Vector2(210, 56)
	cancel.add_theme_font_size_override("font_size", 20)
	_style_button(cancel, UITheme.CYAN, true)
	cancel.pressed.connect(func() -> void: layer.queue_free())
	row.add_child(cancel)

	var confirm := Button.new()
	confirm.text = "RESET"
	confirm.custom_minimum_size = Vector2(210, 56)
	confirm.add_theme_font_size_override("font_size", 20)
	_style_button(confirm, UITheme.MAGENTA, false)
	confirm.pressed.connect(_do_reset)
	row.add_child(confirm)

	# Default to CANCEL so a stray Enter never resets progress.
	cancel.focus_neighbor_right = confirm.get_path()
	confirm.focus_neighbor_left = cancel.get_path()
	cancel.grab_focus()

func _do_reset() -> void:
	Profile.reset_ng_plus()
	get_tree().reload_current_scene()   # rebuild the title cleanly (badge/reset button gone, records stay)

func _rebuild_ship() -> void:
	if _ship_root != null and is_instance_valid(_ship_root):
		_ship_root.queue_free()
	if _director != null and is_instance_valid(_director):
		_director.queue_free()

	var rng := RandomNumberGenerator.new()
	rng.seed = _hull_seed
	_ship_root = Node3D.new()
	_ship_root.name = "ShipRoot"
	add_child(_ship_root)

	var result: Dictionary = ShipHullGeneratorS.generate(rng)
	var hull: Node3D = result.hull
	var aabb: AABB = result.aabb
	var longest: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	var k: float = (ShipHullGeneratorS.TARGET_LONGEST / longest) if longest > 0.0 else 1.0
	hull.scale = Vector3.ONE * k
	hull.position = -(aabb.position + aabb.size * 0.5) * k
	_ship_root.add_child(hull)
	Dresser.dress(hull, result.colors, _accent, rng, result.spec.get("symmetric", true))
	# Show any parts already kept this run (empty on a fresh run -> base hull).
	Dresser.attach_loadout(_ship_root, RunManager.permanent_pieces, aabb, k, _accent, rng)

	var radius: float = 0.5 * aabb.size.length() * k
	_director = _make_camera(_ship_root.global_position, radius)

func _make_camera(center: Vector3, radius: float) -> Node3D:
	var d := CameraDirectorS.new()
	d.name = "CameraDirector"
	add_child(d)
	d.set_target(center, radius)
	return d

func _process(delta: float) -> void:
	_time += delta
	if _ship_root != null and is_instance_valid(_ship_root):
		_ship_root.rotation = Vector3(
			deg_to_rad(2.5) * sin(_time * 0.45 + 1.0),
			deg_to_rad(4.0) * sin(_time * 0.16),
			deg_to_rad(5.0) * sin(_time * 0.33))
	_update_glitch(delta)

# Fire an irregular VHS glitch burst on the title every few seconds; decay between.
func _update_glitch(delta: float) -> void:
	if _glitch_mat == null:
		return
	_glitch_cd -= delta
	if _glitch_cd <= 0.0:
		_glitch = randf_range(0.7, 1.0)          # trigger a burst
		_glitch_cd = randf_range(2.5, 6.5)       # ...then wait a while
	_glitch = maxf(0.0, _glitch - delta * 3.2)   # short burst, quick decay
	_glitch_mat.set_shader_parameter("glitch", _glitch)

# Big chunky title rendered to a SubViewport, then displayed through the VHS glitch
# shader (chromatic diffraction + scanlines + intermittent tape-tear bursts).
func _build_glitch_title(layer: CanvasLayer, accent: Color, text: String) -> void:
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.size = Vector2i(1120, 168)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	var lbl := UITheme.label(text, 72, accent)
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_constant_override("outline_size", 10)   # chunky
	vp.add_child(lbl)

	_glitch_mat = ShaderMaterial.new()
	_glitch_mat.shader = GlitchShader

	var tr := TextureRect.new()
	tr.texture = vp.get_texture()
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # keep the pixels crunchy
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.material = _glitch_mat
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_preset(Control.PRESET_CENTER_TOP)
	tr.offset_left = -560.0
	tr.offset_right = 560.0
	tr.offset_top = 28.0
	tr.offset_bottom = 196.0
	layer.add_child(tr)

# --- environment / skybox (fixed for the session) ---------------------------
func _build_environment(sky_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = sky_seed
	var theme: Dictionary = _roll_theme(rng)
	_accent = theme.get("accent", Color(0.6, 0.8, 1.0))
	var rolled: Dictionary = theme.get("_rolled", {})
	var cfg: Dictionary = SkyDirectorS.build(rolled, theme, 3, Sky.RADIANCE_SIZE_256)

	var env := Environment.new()
	if cfg.get("use_sky", false):
		env.background_mode = Environment.BG_SKY
		var sky: Sky = cfg.get("sky") as Sky
		_enrich_sky(sky)
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.01, 0.01, 0.02)
	env.ambient_light_color = cfg.get("ambient_color", Color(0.1, 0.12, 0.2))
	env.ambient_light_energy = maxf(float(cfg.get("ambient_energy", 0.5)), 0.55)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.85

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

	var sun_toward: Vector3 = cfg.get("sun_toward", Vector3(0.3, 0.5, 0.6))
	sun_toward = sun_toward.normalized()
	var sun := DirectionalLight3D.new()
	sun.light_color = cfg.get("sun_color", Color(1, 0.97, 0.92))
	sun.light_energy = maxf(float(cfg.get("sun_energy", 1.0)), 0.72)
	sun.shadow_enabled = true
	add_child(sun)
	var up: Vector3 = Vector3.UP if absf(sun_toward.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	sun.look_at_from_position(Vector3.ZERO, -sun_toward, up)

	var fill := DirectionalLight3D.new()
	fill.light_color = _accent.lerp(Color.WHITE, 0.3)
	fill.light_energy = 0.22
	add_child(fill)
	fill.look_at_from_position(Vector3.ZERO, sun_toward + Vector3(0.2, -0.4, 0.1), Vector3.UP)

	# Lens flare that tracks the sun across the screen.
	var lf := LensFlareS.new()
	lf.sun_direction = sun_toward
	lf.flare_color = sun.light_color.lerp(Color.WHITE, 0.3)
	lf.base_intensity = 0.7
	add_child(lf)

func _roll_theme(rng: RandomNumberGenerator) -> Dictionary:
	var rolled := {
		"shape_family": 2,
		"viewpoint": "thirdperson",
		"shape_word": SHAPE_WORDS[rng.randi_range(0, SHAPE_WORDS.size() - 1)],
		"modifier_word": MODIFIERS[rng.randi_range(0, MODIFIERS.size() - 1)],
		"structure_type": "",
		"biome": SHAPE_WORDS[rng.randi_range(0, SHAPE_WORDS.size() - 1)],
		"feature_words": {},
	}
	var theme: Dictionary = LevelThemeS.resolve(rolled)
	theme["_rolled"] = rolled
	return theme

func _enrich_sky(sky: Sky) -> void:
	if sky == null or not (sky.sky_material is ShaderMaterial):
		return
	var sm: ShaderMaterial = sky.sky_material as ShaderMaterial
	sm.set_shader_parameter("star_density", _floor_param(sm, "star_density", 0.8))
	sm.set_shader_parameter("star_brightness", _floor_param(sm, "star_brightness", 1.7))
	sm.set_shader_parameter("nebula_strength", _floor_param(sm, "nebula_strength", 0.45))
	sm.set_shader_parameter("milkyway_strength", _floor_param(sm, "milkyway_strength", 0.22))
	sm.set_shader_parameter("galaxy_strength", _floor_param(sm, "galaxy_strength", 0.25))
	sm.set_shader_parameter("exposure", 1.0)

func _floor_param(sm: ShaderMaterial, name: String, floor_v: float) -> float:
	var cur: Variant = sm.get_shader_parameter(name)
	return maxf(float(cur), floor_v) if cur != null else floor_v

# --- stars ------------------------------------------------------------------
func _build_stars() -> void:
	var scale: float = maxf(float(PerfProfile.particle_scale), 0.4)
	var p := CPUParticles3D.new()
	p.name = "Stars"
	p.local_coords = false
	p.amount = maxi(30, int(80.0 * scale))
	p.lifetime = 5.0
	p.preprocess = 5.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(22.0, 13.0, 20.0)
	p.direction = Vector3(0.0, -1.0, 0.0)          # gentle downward drift (for the trail)
	p.spread = 25.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 3.5
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.45
	p.scale_amount_max = 1.25

	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var mat := ShaderMaterial.new()
	mat.shader = StarShader
	mat.set_shader_parameter("star_color", _accent.lerp(Color.WHITE, 0.75))
	mat.set_shader_parameter("intensity", 1.9)
	q.material = mat
	p.mesh = q

	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.add_point(0.12, Color(1, 1, 1, 1.0))
	g.add_point(0.88, Color(1, 1, 1, 1.0))
	g.set_offset(g.get_point_count() - 1, 1.0)
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0.0))
	p.color_ramp = g
	add_child(p)

# --- UI: title + reroll button ----------------------------------------------
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "TitleUI"
	add_child(layer)
	var accent: Color = UITheme.CYAN   # uniform neon chrome, regardless of rolled backdrop

	var game_name: String = str(ProjectSettings.get_setting("application/config/name", "CHIMERA"))
	_build_glitch_title(layer, accent, game_name.to_upper())

	# NEW GAME PLUS badge (persistent once the game's been beaten).
	if Profile.beaten:
		var ngp := UITheme.label("- NEW GAME + -", 22, UITheme.GOLD)
		ngp.set_anchors_preset(Control.PRESET_TOP_WIDE)
		ngp.offset_top = 120.0
		layer.add_child(ngp)

	# Best-times panel (the post-game time-attack records) in a bordered console box.
	if Profile.has_progress():
		var recp := PanelContainer.new()
		recp.add_theme_stylebox_override("panel", UITheme.panel_box(UITheme.CYAN, true))
		recp.set_anchors_preset(Control.PRESET_TOP_LEFT)
		recp.offset_left = 34.0
		recp.offset_top = 164.0
		layer.add_child(recp)
		var rec := UITheme.label(_records_text(), 14, UITheme.DIM, false)
		recp.add_child(rec)

	# Menu buttons — Play (primary) over Reroll (secondary), centred at the bottom.
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	vb.anchor_left = 0.5
	vb.anchor_right = 0.5
	vb.offset_left = -180.0
	vb.offset_right = 180.0
	vb.offset_top = -200.0
	vb.offset_bottom = -46.0
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	layer.add_child(vb)

	var play := Button.new()
	play.text = "> PLAY"
	play.custom_minimum_size = Vector2(360, 66)
	play.add_theme_font_size_override("font_size", 26)
	_style_button(play, UITheme.CYAN, true)
	play.pressed.connect(_play)
	vb.add_child(play)

	var reroll := Button.new()
	reroll.text = "REROLL SHIP"
	reroll.custom_minimum_size = Vector2(360, 56)
	reroll.add_theme_font_size_override("font_size", 20)
	_style_button(reroll, UITheme.CYAN, false)
	reroll.pressed.connect(_reroll)
	vb.add_child(reroll)

	# Keyboard/gamepad focus: start on Play; up/down + Tab move down the column.
	play.focus_neighbor_bottom = reroll.get_path()
	reroll.focus_neighbor_top = play.get_path()
	play.focus_next = reroll.get_path()
	reroll.focus_previous = play.get_path()

	# RESET NEW GAME + (danger) -- only when NG+ is actually unlocked. Warns first;
	# best-time records are kept, only the NG+ unlock is cleared.
	if Profile.beaten:
		var reset := Button.new()
		reset.text = "RESET NG+"
		reset.custom_minimum_size = Vector2(360, 52)
		reset.add_theme_font_size_override("font_size", 18)
		_style_button(reset, UITheme.MAGENTA, false)
		reset.pressed.connect(_ask_reset)
		vb.add_child(reset)
		reroll.focus_neighbor_bottom = reset.get_path()
		reset.focus_neighbor_top = reroll.get_path()
		reroll.focus_next = reset.get_path()
		reset.focus_previous = reroll.get_path()
		# Grow the column upward so the 3rd (bigger) button clears the controls hint.
		vb.offset_top = -300.0
		vb.offset_bottom = -74.0

	play.grab_focus()

	var hint := UITheme.label("[UP/DN] SELECT    [ENTER] CONFIRM", 13, UITheme.DIM)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -46.0
	hint.offset_bottom = -22.0
	layer.add_child(hint)

	# CRT scanline + vignette overlay on top of the whole menu.
	layer.add_child(UITheme.scanlines(0.13, 0.55))

func _style_button(btn: Button, accent: Color, _primary: bool) -> void:
	UITheme.style_button(btn, accent)   # shared square neon arcade style
	btn.focus_entered.connect(func() -> void: Sfx.play("ui_move"))

# --- windowed capture for verification --------------------------------------
# godot --path chimera-drift res://scenes/Title.tscn -- --capture
func _maybe_capture() -> void:
	if "--capture" in OS.get_cmdline_user_args():
		_capture_seq()

func _capture_seq() -> void:
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://_title_0.png")
	_reroll()                                # prove the ship changes
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://_title_1.png")
	print("TITLE_CAPTURE done")
	get_tree().quit()
