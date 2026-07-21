extends Node3D

# ============================================================================
# Chimera Drift — POST-LEVEL BEAUTY SHOT
# The between-levels "loading" screen that shows off the player's ship and the
# new parts they collected. A close-up hero render of the dressed hull against a
# randomly-generated deep-space skybox, cinematic cameras gliding around it,
# twinkling nav-lamps and speed-streaks rushing past (flying-fast feel), with the
# previous level's score + stats laid over the top.
#
# Self-contained + runnable on its own (rolls a demo ship + demo stats). Wire it
# into a real win / level-transition flow via configure(seed, stats) BEFORE the
# scene enters the tree, or call it any time to rebuild.
# ============================================================================

const SkyDirectorS := preload("res://scripts/sky_director.gd")
const LevelThemeS := preload("res://scripts/level_theme.gd")
const ShipHullGeneratorS := preload("res://scripts/ship_hull_generator.gd")
const Dresser := preload("res://scripts/beauty_ship_dresser.gd")
const CameraDirectorS := preload("res://scripts/beauty_camera_director.gd")
const PieceUtil := preload("res://scripts/piece_util.gd")
const StreakShader := preload("res://shaders/speed_streak.gdshader")

# Space-flavoured words so the rolled skybox reads as an open starfield/nebula.
const SHAPE_WORDS := ["Nebula", "Ring System", "Ion Storm", "Deep Space", "Comet Field", "Solar Flare", "Asteroid Belt", "Wormhole"]
const MODIFIERS := ["Storm-Wracked", "Haunted", "Crystalline", "Irradiated", "Molten", "Frozen", "Pristine", "Bioluminescent"]

# Emitted once the player commits the draft: the index of the kept piece in the
# `pieces` array passed to configure(), or -1 for "none". LevelDirector awaits it.
signal choice_made(index: int)

var _seed: int = -1
var _stats: Dictionary = {}
var _pieces: Array = []           # this stage's draftable pieces ({kind,color,effect})
var _loadout: Array = []          # the run's accumulated kept pieces (shown on the ship)
var _accent: Color = Color(0.6, 0.8, 1.0)

var _ship_root: Node3D = null
var _time: float = 0.0

# --- draft menu state ---
var _sel: int = 0
var _cards: Array = []            # the card Control per piece (for restyle)
var _prompt: Label = null
var _chosen: bool = false         # true once committed (locks input)

# ---------------------------------------------------------------------------
# Wire-in point: set the ship seed (the player's run seed), the stats to show,
# and the pieces the player may draft from. Rebuilds if already in the tree.
# ---------------------------------------------------------------------------
func configure(ship_seed: int, stats: Dictionary, pieces: Array = [], loadout: Array = []) -> void:
	_seed = ship_seed
	_stats = stats
	_pieces = pieces
	_loadout = loadout
	if is_inside_tree():
		_rebuild()

func _ready() -> void:
	if _seed < 0:
		_seed = _cmdline_seed()
	if _seed < 0:
		var r := RandomNumberGenerator.new()
		r.randomize()
		_seed = r.randi()
	if _stats.is_empty():
		_stats = _demo_stats()
	if _pieces.is_empty():
		_pieces = _demo_pieces()      # so the menu shows when run standalone
	if _loadout.is_empty():
		_loadout = _demo_loadout()    # so the ship shows some parts when run standalone
	_rebuild()
	_maybe_capture()

func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_cards.clear()
	_prompt = null
	_chosen = false
	_sel = 0

	var rng := RandomNumberGenerator.new()
	rng.seed = _seed

	var theme: Dictionary = _roll_theme(rng)
	_accent = theme.get("accent", Color(0.6, 0.8, 1.0))
	_build_environment(rng, theme)
	_build_ship(rng, theme)
	_build_streaks(theme)
	_build_camera()
	_build_ui()

# --- environment / skybox --------------------------------------------------
func _roll_theme(rng: RandomNumberGenerator) -> Dictionary:
	var rolled := {
		"shape_family": 2,   # OPEN_VOLUME → SkyDirector deep-space path
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

func _build_environment(_rng: RandomNumberGenerator, theme: Dictionary) -> void:
	var rolled: Dictionary = theme.get("_rolled", {})
	var cfg: Dictionary = SkyDirectorS.build(rolled, theme, 3, Sky.RADIANCE_SIZE_256)

	var env := Environment.new()
	if cfg.get("use_sky", false):
		env.background_mode = Environment.BG_SKY
		var sky: Sky = cfg.get("sky") as Sky
		_enrich_sky(sky)          # guarantee a lush, bright backdrop to glint off
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.01, 0.01, 0.02)
	env.ambient_light_color = cfg.get("ambient_color", Color(0.1, 0.12, 0.2))
	env.ambient_light_energy = maxf(float(cfg.get("ambient_energy", 0.5)), 0.9)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

	# Sun: the sky shader reads it from LIGHT0, so orient a DirectionalLight to
	# match cfg.sun_toward (direction TO the sun → light forward = -sun_toward).
	var sun_toward: Vector3 = cfg.get("sun_toward", Vector3(0.3, 0.5, 0.6))
	sun_toward = sun_toward.normalized()
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = cfg.get("sun_color", Color(1, 0.97, 0.92))
	sun.light_energy = maxf(float(cfg.get("sun_energy", 1.0)), 1.1)
	sun.shadow_enabled = true
	add_child(sun)
	var up: Vector3 = Vector3.UP if absf(sun_toward.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	sun.look_at_from_position(Vector3.ZERO, -sun_toward, up)

	# A soft cool fill from the opposite side so the shadowed flank still reads.
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = _accent.lerp(Color.WHITE, 0.3)
	fill.light_energy = 0.35
	fill.shadow_enabled = false
	add_child(fill)
	fill.look_at_from_position(Vector3.ZERO, sun_toward + Vector3(0.2, -0.4, 0.1), Vector3.UP)

# Push the rolled deep-space sky toward a rich, bright "beauty backdrop": floor
# the star/nebula/galaxy strength and lift exposure so there's always something
# lush for the glossy hull + glass to reflect (the rolled variety is preserved,
# only raised to a minimum). No-op for a non-shader sky.
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

# --- ship ------------------------------------------------------------------
func _build_ship(rng: RandomNumberGenerator, theme: Dictionary) -> void:
	_ship_root = Node3D.new()
	_ship_root.name = "ShipRoot"
	add_child(_ship_root)

	var result: Dictionary = ShipHullGeneratorS.generate(rng)
	var hull: Node3D = result.hull
	hull.name = "Hull"

	var aabb: AABB = result.aabb
	var longest: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	var k: float = (ShipHullGeneratorS.TARGET_LONGEST / longest) if longest > 0.0 else 1.0
	hull.scale = Vector3.ONE * k
	# Re-centre the hull's geometric centre on the ship-root origin.
	var centre: Vector3 = (aabb.position + aabb.size * 0.5) * k
	hull.position = -centre
	_ship_root.add_child(hull)

	Dresser.dress(hull, result.colors, _accent, rng)
	Dresser.attach_loadout(_ship_root, _loadout, aabb, k, _accent, rng)   # show the kept parts

	# Framing radius = half the bounding-sphere diagonal so nothing clips.
	var radius: float = 0.5 * aabb.size.length() * k
	_ship_root.set_meta("radius", radius)

func _build_camera() -> void:
	var d := CameraDirectorS.new()
	d.name = "CameraDirector"
	add_child(d)
	var radius: float = float(_ship_root.get_meta("radius", 1.2))
	d.set_target(_ship_root.global_position, radius)

# --- speed streaks ---------------------------------------------------------
func _build_streaks(_theme: Dictionary) -> void:
	var scale: float = maxf(float(PerfProfile.particle_scale), 0.4)
	var p := CPUParticles3D.new()
	p.name = "SpeedStreaks"
	p.local_coords = false
	p.amount = maxi(24, int(150.0 * scale))
	p.lifetime = 1.6
	p.preprocess = 1.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(16.0, 10.0, 22.0)
	p.direction = Vector3(0.0, 0.0, 1.0)          # rush PAST the ship (it flies -Z)
	p.spread = 0.0
	p.initial_velocity_min = 55.0
	p.initial_velocity_max = 85.0
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.4

	var q := QuadMesh.new()
	q.size = Vector2(0.16, 3.0)                    # thin + long → a warp line
	var mat := ShaderMaterial.new()
	mat.shader = StreakShader
	mat.set_shader_parameter("streak_color", _accent.lerp(Color.WHITE, 0.5))
	mat.set_shader_parameter("intensity", 1.7)
	q.material = mat
	p.mesh = q

	# Fade in then out over the lifetime (drives COLOR.a in the shader).
	var g := Gradient.new()
	g.set_offset(0, 0.0)
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.add_point(0.15, Color(1, 1, 1, 1.0))
	g.add_point(0.85, Color(1, 1, 1, 1.0))
	g.set_offset(g.get_point_count() - 1, 1.0)
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0.0))
	p.color_ramp = g
	add_child(p)

# --- idle motion + draft input ---------------------------------------------
func _process(delta: float) -> void:
	_time += delta
	if _ship_root != null and is_instance_valid(_ship_root):
		# Subtle "banking in flight" life; the cameras do the real moving.
		_ship_root.rotation = Vector3(
			deg_to_rad(2.5) * sin(_time * 0.45 + 1.0),
			deg_to_rad(4.0) * sin(_time * 0.16),
			deg_to_rad(5.0) * sin(_time * 0.33))
	_process_menu()

# --- stats / score UI ------------------------------------------------------
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "StatsUI"
	add_child(layer)

	# Cinematic vignette (darken the corners → focus on the ship, lift edge text)
	# then top/bottom scrims so the title/score/stats always read over any sky.
	_add_vignette(layer)
	_add_scrim(layer, true)
	_add_scrim(layer, false)

	var title_text: String = _stats.get("title", "SECTOR CLEARED")
	var score: int = int(_stats.get("score", 0))
	var rows: Array = _stats.get("rows", [])
	var footer: String = _stats.get("footer", "PREPARING NEXT SECTOR…")
	var accent: Color = UITheme.CYAN   # uniform neon chrome

	# Title (top-centre).
	var title := UITheme.label(title_text, 38, accent)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 26.0
	layer.add_child(title)

	# Score (under the title).
	var score_label := UITheme.label("SCORE %s" % _commas(score), 22, UITheme.GOLD)
	score_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	score_label.offset_top = 82.0
	layer.add_child(score_label)

	# Stat block (top-left console panel; the bottom is reserved for the draft menu).
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 34.0
	panel.offset_top = 132.0
	panel.add_theme_stylebox_override("panel", UITheme.panel_box(accent, true))
	layer.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 9)
	panel.add_child(vb)
	for row in rows:
		var arr: Array = row
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 18)
		var key := UITheme.label(str(arr[0]), 13, UITheme.DIM, false)
		key.custom_minimum_size = Vector2(200, 0)
		var val := UITheme.label(str(arr[1]), 13, accent, false)
		line.add_child(key)
		line.add_child(val)
		vb.add_child(line)

	# The draft menu owns the bottom of the screen.
	_build_menu(layer, accent)

	# CRT scanline + vignette overlay across the whole beauty shot.
	layer.add_child(UITheme.scanlines(0.12, 0.5))

# --- draft menu (pick ONE collected piece to keep permanently) --------------
func _build_menu(layer: CanvasLayer, accent: Color) -> void:
	# A heading above the cards so the interaction is obvious.
	var heading := Label.new()
	heading.text = "CHOOSE A PART TO KEEP" if not _pieces.is_empty() else "NO NEW PARTS THIS STAGE"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_label(heading, 20, accent)
	heading.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	heading.offset_top = -220.0
	heading.offset_bottom = -186.0
	layer.add_child(heading)

	# Card row, horizontally centred in a bottom band.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	center.offset_top = -180.0
	center.offset_bottom = -64.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	center.add_child(row)
	# Size cards so the whole draft fits one centred row, however many were collected.
	var n: int = _pieces.size()
	var card_w: int = 190
	if n > 0:
		card_w = clampi(int((1200.0 - float(n - 1) * 16.0) / float(n)), 128, 200)
	for i in range(n):
		var card: Control = _make_card(_pieces[i], card_w, i)
		row.add_child(card)
		_cards.append(card)

	# Prompt line at the very bottom.
	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_label(_prompt, 13, UITheme.DIM)
	_prompt.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_prompt.offset_top = -42.0
	_prompt.offset_bottom = -16.0
	_prompt.text = ("TAP A PART   OR  [<] [>] + [ENTER]" if not _pieces.is_empty()
		else "TAP TO CONTINUE")
	layer.add_child(_prompt)

	# No-parts case: a tappable CONTINUE button (mobile) that just advances.
	if _pieces.is_empty():
		var cont := Button.new()
		cont.text = "CONTINUE"
		cont.focus_mode = Control.FOCUS_NONE
		cont.add_theme_font_size_override("font_size", 20)
		UITheme.style_button(cont, UITheme.CYAN)
		cont.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		cont.anchor_left = 0.5
		cont.anchor_right = 0.5
		cont.offset_left = -110.0
		cont.offset_right = 110.0
		cont.offset_top = -150.0
		cont.offset_bottom = -100.0
		cont.pressed.connect(_commit_choice)
		layer.add_child(cont)

	_refresh_cards()

# One piece card: a colour-swatched panel with the piece name + what it does.
func _make_card(piece: Dictionary, card_w: int, index: int) -> Control:
	var kind: String = piece.get("kind", "")
	var effect: String = piece.get("effect", "")
	var color: Color = piece.get("color", Color(0.7, 0.75, 0.85))

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(card_w, 118)
	panel.set_meta("piece_color", color)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 7)
	panel.add_child(vb)

	var swatch := ColorRect.new()
	swatch.color = color
	swatch.custom_minimum_size = Vector2(0, 30)
	vb.add_child(swatch)

	var name_lbl := Label.new()
	name_lbl.text = PieceUtil.label_for(kind, effect)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.clip_text = true                     # never widen the card past card_w
	name_lbl.add_theme_font_override("font", UITheme.FONT)
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", UITheme.TEXT)
	vb.add_child(name_lbl)
	panel.set_meta("name_label", name_lbl)

	var blurb := Label.new()
	blurb.text = PieceUtil.blurb_for(effect)
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_font_override("font", UITheme.FONT)
	blurb.add_theme_font_size_override("font_size", 9)
	blurb.add_theme_color_override("font_color", UITheme.DIM)
	vb.add_child(blurb)

	# Transparent tap target over the card (mobile): tap = select + keep.
	var tap := Button.new()
	tap.flat = true
	tap.focus_mode = Control.FOCUS_NONE
	tap.pressed.connect(_on_card_tapped.bind(index))
	panel.add_child(tap)

	return panel

func _on_card_tapped(index: int) -> void:
	if _chosen:
		return
	_sel = index
	_refresh_cards()
	_commit_choice()

# Restyle every card so the selected one stands out (accent border + brighter bg).
func _refresh_cards() -> void:
	for i in range(_cards.size()):
		var card: Control = _cards[i]
		var color: Color = card.get_meta("piece_color", Color.WHITE)
		var selected: bool = i == _sel
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.08, 0.13, 0.92) if selected else Color(0.02, 0.03, 0.06, 0.7)
		sb.border_color = color if selected else Color(color.r, color.g, color.b, 0.4)
		sb.set_border_width_all(3 if selected else 1)
		sb.set_corner_radius_all(0)   # square = arcade
		sb.set_content_margin_all(9)
		if selected:
			sb.shadow_color = Color(color.r, color.g, color.b, 0.5)
			sb.shadow_size = 12
		card.add_theme_stylebox_override("panel", sb)

# Poll the draft input each frame (global Input, so viewport routing is a non-issue).
func _process_menu() -> void:
	if _chosen:
		return
	if not _pieces.is_empty():
		if Input.is_action_just_pressed("ui_left"):
			_sel = (_sel - 1 + _pieces.size()) % _pieces.size()
			_refresh_cards()
			Sfx.play("ui_move")
		elif Input.is_action_just_pressed("ui_right"):
			_sel = (_sel + 1) % _pieces.size()
			_refresh_cards()
			Sfx.play("ui_move")
	if Input.is_action_just_pressed("ui_accept"):
		_commit_choice()

func _commit_choice() -> void:
	_chosen = true
	Sfx.play("ui_confirm")
	var idx: int = _sel if not _pieces.is_empty() else -1
	if idx >= 0 and idx < _cards.size():
		var card: Control = _cards[idx]
		var name_lbl: Label = card.get_meta("name_label") as Label
		if name_lbl != null:
			name_lbl.text = "* " + name_lbl.text
	if _prompt != null:
		_prompt.text = "PART ADDED - PREPARING NEXT SECTOR" if idx >= 0 else "PREPARING NEXT SECTOR"
	await get_tree().create_timer(0.7).timeout   # brief confirmation beat
	choice_made.emit(idx)

func _add_vignette(layer: CanvasLayer) -> void:
	var grad := Gradient.new()
	grad.set_offset(0, 0.0)
	grad.set_color(0, Color(0, 0, 0.01, 0.0))
	grad.add_point(0.6, Color(0, 0, 0.01, 0.0))
	grad.set_offset(grad.get_point_count() - 1, 1.0)
	grad.set_color(grad.get_point_count() - 1, Color(0, 0, 0.01, 0.5))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	var tr := TextureRect.new()
	tr.texture = tex
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(tr)

func _add_scrim(layer: CanvasLayer, top: bool) -> void:
	var grad := Gradient.new()
	var dark := Color(0.0, 0.0, 0.02, 0.6)
	var clear := Color(0.0, 0.0, 0.02, 0.0)
	grad.set_color(0, dark if top else clear)
	grad.set_color(1, clear if top else dark)
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 8
	tex.height = 256
	var tr := TextureRect.new()
	tr.texture = tex
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if top:
		tr.set_anchors_preset(Control.PRESET_TOP_WIDE)
		tr.offset_bottom = 195.0
	else:
		tr.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		tr.offset_top = -175.0
	layer.add_child(tr)

func _commas(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	var c: int = 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out

func _demo_stats() -> Dictionary:
	return {
		"title": "SECTOR 3 CLEARED",
		"score": 128450,
		"rows": [
			["SECTOR", "Crystalline Nebula"],
			["DISTANCE", "200 m"],
			["NEW PARTS", "4"],
			["ENEMIES DOWNED", "46"],
			["TIME", "3:12"],
		],
		"footer": "PREPARING NEXT SECTOR…",
	}

func _demo_pieces() -> Array:
	return [
		{"kind": "fin", "color": Color(0.4, 0.8, 1.0), "effect": ""},
		{"kind": "pod", "color": Color(0.9, 0.5, 0.9), "effect": ""},
		{"kind": "plate", "color": Color(0.5, 0.9, 0.6), "effect": "shield"},
		{"kind": "spar", "color": Color(1.0, 0.7, 0.3), "effect": "fire_rate"},
	]

func _demo_loadout() -> Array:
	# Muted, level-themed-looking colours (real loadout parts are tinted to the
	# level they were collected on, then matured by the dresser).
	return [
		{"kind": "fin", "color": Color(0.42, 0.52, 0.62), "effect": ""},
		{"kind": "pod", "color": Color(0.62, 0.42, 0.38), "effect": ""},
		{"kind": "spar", "color": Color(0.5, 0.56, 0.44), "effect": ""},
	]

# --- headless/windowed verification capture --------------------------------
# Run with:  godot --path chimera-drift res://scenes/BeautyShot.tscn -- --capture
# Saves a couple of PNGs into the project root and quits, so a render can be
# eyeballed without a live display session.
func _cmdline_seed() -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			return int(a.substr(7))
	return -1

func _maybe_capture() -> void:
	if "--capture" in OS.get_cmdline_user_args():
		_capture_seq()

func _capture_seq() -> void:
	var gaps: Array = [3.0, 8.0]
	for i in range(gaps.size()):
		await get_tree().create_timer(float(gaps[i])).timeout
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png("res://_beauty_%d.png" % i)
		print("BEAUTY_CAPTURE saved res://_beauty_%d.png" % i)
	get_tree().quit()
