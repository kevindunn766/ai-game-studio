extends CanvasLayer

@export var ship_path: NodePath
@export var level_director_path: NodePath

@onready var ship: Node3D = get_node(ship_path)
@onready var level_director := get_node(level_director_path)
@onready var info_label: Label = $InfoLabel
@onready var crash_label: Label = $CrashLabel
@onready var health_bar: ProgressBar = $HealthBar
@onready var shield_bar: ProgressBar = $ShieldBar
@onready var reticle: Control = $Reticle

const WEAPON_NAMES := ["", "Single", "Double", "Triple", "Spread"]
const TouchControls := preload("res://scripts/touch_controls.gd")
var _touch: Control = null

# How far ahead of the ship (world units, along its -Z fire line) to place the aim
# point per view. Each view's camera then projects that point to screen -- so the
# reticle works correctly everywhere, but the distance that reads well differs:
# the pulled-back angled/overhead views want it nearer, the chase cam further.
# Orthographic views (top-down/iso) map world distance straight to screen offset, so
# they need a SHORT distance to keep the reticle on screen; the perspective views
# (third-person/side-scroll/3-4) converge to a vanishing point, so they take more.
const RETICLE_DIST := {
	"thirdperson": 28.0,
	"sidescroll": 9.0,
	"topdown": 6.0,
	"isometric": 7.0,
	"threequarter": 12.0,
}

var crashed: bool = false
var _zone_flash: ColorRect = null      # full-screen red flash when leaving the combat zone
var _zone_label: Label = null
var _alarm_t: float = 0.0

var _boss_root: Control = null         # boss health bar (shown only while a boss is active)
var _boss_bar_bg: Panel = null
var _boss_fill: ColorRect = null
var _boss_label: Label = null

var _shield_row: Control = null        # hidden when the ship has no shield
var _hull_val: Label = null            # numeric HP / shield readouts beside the bars
var _shld_val: Label = null
var _hull_seg: Dictionary = {}         # segmented (blocky) hull + shield bars
var _shld_seg: Dictionary = {}

func _ready() -> void:
	crash_label.visible = false
	_add_hud_scanlines()
	_build_zone_alarm()
	_build_boss_bar()
	_apply_retro_style()
	_build_status_panel()
	ship.crashed.connect(_on_ship_crashed)
	ship.health_changed.connect(_on_health_changed)
	level_director.level_won.connect(_on_level_won)
	_on_health_changed(ship.health, ship.MAX_HEALTH, ship.shield, ship.shield_capacity)
	_touch = TouchControls.new()
	add_child(_touch)

# A full-screen red flash (behind the readouts) + a warning banner, both pulsing, shown
# while the ship is leaving the combat zone.
# A faint CRT overlay over gameplay (under the HUD widgets) so the whole game shares
# the arcade look. Kept subtle so it never hurts readability in flight.
func _add_hud_scanlines() -> void:
	var crt := UITheme.scanlines(0.06, 0.32)
	add_child(crt)
	move_child(crt, 0)   # behind the readouts, over the 3D viewport

# Retro pass over the crash/win banner (the status panel builds its own widgets).
func _apply_retro_style() -> void:
	crash_label.add_theme_font_override("font", UITheme.FONT)
	crash_label.add_theme_font_size_override("font_size", 24)
	crash_label.add_theme_color_override("font_outline_color", UITheme.INK)
	crash_label.add_theme_constant_override("outline_size", 5)
	crash_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crash_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

# Traditional top-left status HUD: the player's HULL + SHIELD bars stacked with
# numeric readouts, and a compact stat line below (distance / parts / weapon /
# boost). The level's biome/view/enemy flavour text is intentionally gone.
func _build_status_panel() -> void:
	health_bar.visible = false          # replaced by the segmented block bars
	shield_bar.visible = false

	# No border / background during gameplay -- the readouts float over the action
	# (text stays legible via its INK outline; bars read via lit vs dim blocks).
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 18.0
	panel.offset_top = 16.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	_hull_seg = UITheme.seg_bar(10, UITheme.GREEN, Vector2(15, 24), false)
	_hull_val = UITheme.label("", 14, UITheme.TEXT, false)
	vb.add_child(_status_row("HULL", _hull_seg["frame"], _hull_val, UITheme.GREEN))
	_shld_seg = UITheme.seg_bar(10, UITheme.CYAN, Vector2(15, 24), false)
	_shld_val = UITheme.label("", 14, UITheme.CYAN, false)
	_shield_row = _status_row("SHLD", _shld_seg["frame"], _shld_val, UITheme.CYAN)
	vb.add_child(_shield_row)

	# Reparent the compact stat readout below the bars, inside the same panel.
	if info_label.get_parent() != null:
		info_label.get_parent().remove_child(info_label)
	info_label.add_theme_font_override("font", UITheme.FONT)
	info_label.add_theme_font_size_override("font_size", 12)
	info_label.add_theme_color_override("font_color", UITheme.DIM)
	info_label.add_theme_color_override("font_outline_color", UITheme.INK)
	info_label.add_theme_constant_override("outline_size", 3)
	info_label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	vb.add_child(info_label)

# One "LABEL [==blocks==] value" row.
func _status_row(name: String, bar: Control, val: Label, color: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lbl := UITheme.label(name, 14, color, false)
	lbl.custom_minimum_size = Vector2(66, 0)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	val.custom_minimum_size = Vector2(96, 0)
	val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(val)
	return row

func _build_zone_alarm() -> void:
	_zone_flash = ColorRect.new()
	_zone_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_zone_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zone_flash.color = Color(0.9, 0.0, 0.0, 0.0)
	add_child(_zone_flash)
	move_child(_zone_flash, 0)             # behind the health/reticle/labels
	_zone_label = Label.new()
	_zone_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_zone_label.offset_top = 70.0
	_zone_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zone_label.text = "! LEAVING COMBAT ZONE !"
	_zone_label.add_theme_font_override("font", UITheme.FONT)
	_zone_label.add_theme_font_size_override("font_size", 26)
	_zone_label.add_theme_color_override("font_color", UITheme.MAGENTA)
	_zone_label.add_theme_color_override("font_outline_color", UITheme.INK)
	_zone_label.add_theme_constant_override("outline_size", 5)
	_zone_label.visible = false
	add_child(_zone_label)

# Top-centre boss health bar: a label + a dark track with a fill that shrinks as
# the boss's weak points are destroyed. Built hidden; shown by _update_boss_bar.
func _build_boss_bar() -> void:
	_boss_root = Control.new()
	_boss_root.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_boss_root.offset_top = 108.0
	_boss_root.offset_left = 150.0
	_boss_root.offset_right = -150.0
	_boss_root.offset_bottom = 170.0
	_boss_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_root.visible = false
	add_child(_boss_root)

	_boss_label = UITheme.label("- BOSS -", 16, UITheme.MAGENTA)
	_boss_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_boss_root.add_child(_boss_label)

	_boss_bar_bg = Panel.new()
	_boss_bar_bg.add_theme_stylebox_override("panel", UITheme.box(Color(0.06, 0.02, 0.04, 0.9), UITheme.MAGENTA, UITheme.BORDER))
	_boss_bar_bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_boss_bar_bg.offset_top = 34.0
	_boss_bar_bg.offset_bottom = 64.0
	_boss_root.add_child(_boss_bar_bg)

	_boss_fill = ColorRect.new()
	_boss_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)   # full height, left-anchored; width set per-frame
	_boss_fill.offset_left = 5.0
	_boss_fill.offset_top = 5.0
	_boss_fill.offset_bottom = -5.0
	_boss_fill.color = Color(1.0, 0.3, 0.2, 0.95)
	_boss_bar_bg.add_child(_boss_fill)

func _update_boss_bar() -> void:
	var boss: Node3D = level_director.active_boss() if level_director.has_method("active_boss") else null
	if boss == null:
		_boss_root.visible = false
		return
	_boss_root.visible = true
	if boss.has_method("hud_title"):
		_boss_label.text = boss.hud_title()
	var frac: float = boss.health_fraction()
	_boss_fill.offset_right = 5.0 + maxf(0.0, (_boss_bar_bg.size.x - 10.0) * frac)
	_boss_fill.color = Color(1.0, 0.24, 0.18).lerp(Color(1.0, 0.78, 0.28), frac)   # reddens as it weakens

func _update_zone_alarm(delta: float) -> void:
	if ship.leaving_zone:
		_alarm_t += delta
		var pulse: float = 0.5 + 0.5 * sin(_alarm_t * 9.0)   # fast blink
		_zone_flash.color.a = 0.10 + 0.22 * pulse
		_zone_label.visible = true
		_zone_label.modulate.a = 0.35 + 0.65 * pulse
	else:
		_zone_flash.color.a = 0.0
		_zone_label.visible = false

func _process(_delta: float) -> void:
	if _touch != null:
		_touch.set_active(ship.alive)   # touch controls only while flying
	if ship.alive:
		_update_zone_alarm(_delta)
		crash_label.visible = false
		crashed = false
		var distance: int = int(-ship.position.z)
		var viewpoint: String = level_director.rolled_level.get("viewpoint", "?")
		var parts: int = ship.filled_mounts
		var part_cap: int = ship.mounts.get_child_count()
		var weapon: String = WEAPON_NAMES[clampi(ship.weapon_tier, 1, 4)].to_upper()
		var ab: String = ("READY" if ship.afterburner_ready() else "CHARGING") if ship.owns_afterburner else "-"
		# Trimmed to the gameplay essentials only (no biome / view / gravity / enemy flavour).
		info_label.text = "DIST  %d M\nPARTS  %d/%d\nWEAPON  %s  x%.1f\nBOOST  %s" % [distance, parts, part_cap, weapon, ship.fire_rate_mult, ab]
		_update_reticle(viewpoint)
	else:
		reticle.visible = false
		_zone_flash.color.a = 0.0
		_zone_label.visible = false
		if crashed and Input.is_action_just_pressed("ui_accept"):
			level_director.retry_level()

# Place the reticle at the on-screen projection of a world point along the ship's fire
# line (-Z). Projecting through the active camera makes it correct in every view.
# In the angled 3-4 / isometric views the reticle is RAY-TRACED along the actual shot
# path and lands directly on the first enemy/mine it would hit (ship.aim_point); with no
# target in the line of fire it falls back to the fixed per-view distance, like the other
# views. A distinct "locked" crosshair shows when it's sitting on a target.
func _update_reticle(viewpoint: String) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		reticle.visible = false
		return
	var ray_aimed: bool = viewpoint == "isometric" or viewpoint == "threequarter"
	var locked: bool = ray_aimed and ship.aim_hit
	var aim: Vector3
	if locked:
		aim = ship.aim_point                      # ray-traced onto the enemy/mine
	else:
		var dist: float = RETICLE_DIST.get(viewpoint, 24.0)
		aim = ship.global_position + Vector3(0, 0, -1) * dist
	if cam.is_position_behind(aim):
		reticle.visible = false
		return
	reticle.position = cam.unproject_position(aim)
	reticle.visible = true
	if reticle.has_method("set_locked"):
		reticle.set_locked(locked)

func _on_health_changed(health: float, max_health: float, shield: float, shield_capacity: float) -> void:
	if not _hull_seg.is_empty() and max_health > 0.0:
		UITheme.set_seg(_hull_seg, health / max_health)
	if _hull_val != null:
		_hull_val.text = "%d/%d" % [int(ceil(health)), int(max_health)]
	var has_shield: bool = shield_capacity > 0.0
	if _shield_row != null:
		_shield_row.visible = has_shield
	if has_shield:
		if not _shld_seg.is_empty():
			UITheme.set_seg(_shld_seg, shield / shield_capacity)
		if _shld_val != null:
			_shld_val.text = "%d/%d" % [int(ceil(shield)), int(shield_capacity)]

func _on_ship_crashed(distance_traveled: float) -> void:
	crashed = true
	crash_label.text = "-- CRASHED --\nDIST %d M\n[ENTER] RETRY" % int(distance_traveled)
	crash_label.add_theme_color_override("font_color", UITheme.MAGENTA)
	crash_label.add_theme_stylebox_override("normal", UITheme.box(Color(0.04, 0.01, 0.05, 0.92), UITheme.MAGENTA, UITheme.BORDER))
	crash_label.visible = true

func _on_level_won(distance_traveled: float) -> void:
	Sfx.play("win")
	crash_label.text = "LEVEL CLEAR\nDIST %d M" % int(distance_traveled)
	crash_label.add_theme_color_override("font_color", UITheme.GREEN)
	crash_label.add_theme_stylebox_override("normal", UITheme.box(Color(0.01, 0.05, 0.03, 0.92), UITheme.GREEN, UITheme.BORDER))
	crash_label.visible = true
