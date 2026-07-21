extends Node

# ============================================================================
# UITheme — the studio's shared RETRO-SPACE look (autoload `UITheme`).
# On _ready it builds ONE global Theme (arcade pixel font + square neon-bordered
# styleboxes) and applies it to the root window, so EVERY Control inherits the look
# automatically. Screens then use the helpers here for consistent panels / headings /
# buttons / stat rows and a CRT scanline overlay -> a uniform look with no per-screen
# drift. Reached via the `UITheme` autoload global (in-scene UI only).
# ============================================================================

const FONT := preload("res://assets/fonts/PressStart2P-Regular.ttf")
const CRT := preload("res://shaders/crt_overlay.gdshader")

# --- palette (phosphor-on-void) ---------------------------------------------
const INK := Color(0.02, 0.02, 0.05)          # text outline / shadow
const VOID := Color(0.03, 0.045, 0.09, 0.9)   # panel fill
const CYAN := Color(0.33, 0.85, 1.0)          # primary
const MAGENTA := Color(1.0, 0.36, 0.62)       # danger / secondary accent
const GOLD := Color(1.0, 0.79, 0.34)          # highlight / NG+
const GREEN := Color(0.44, 0.93, 0.68)        # health / positive
const DIM := Color(0.55, 0.66, 0.82)          # secondary text
const TEXT := Color(0.9, 0.95, 1.0)           # main text

const BORDER := 4                             # chunky arcade border width
const MARGIN := 14                            # chunky panel padding

func _ready() -> void:
	get_window().theme = build_theme()

# One global theme: pixel font everywhere + square arcade styleboxes as defaults.
func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = FONT
	t.default_font_size = 16
	t.set_color("font_color", "Label", TEXT)

	# Buttons (square, thick cyan border, dark fill; brighten on hover/press).
	t.set_stylebox("normal", "Button", box(VOID, CYAN, BORDER))
	t.set_stylebox("hover", "Button", box(_tint(CYAN, 0.24), CYAN.lightened(0.2), BORDER))
	t.set_stylebox("pressed", "Button", box(_tint(CYAN, 0.42), CYAN.lightened(0.35), BORDER))
	t.set_stylebox("focus", "Button", box(_tint(CYAN, 0.24), CYAN.lightened(0.3), BORDER))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_font_size("font_size", "Button", 20)

	# Panels.
	t.set_stylebox("panel", "PanelContainer", box(VOID, CYAN, BORDER))
	t.set_stylebox("panel", "Panel", box(VOID, CYAN, BORDER))

	# Progress bars (square, thin border; fill colour overridden per-bar).
	var bg := box(Color(0.05, 0.06, 0.11, 0.92), _alpha(CYAN, 0.5), 1)
	bg.set_content_margin_all(0)
	var fg := box(CYAN, CYAN, 0)
	fg.set_content_margin_all(0)
	t.set_stylebox("background", "ProgressBar", bg)
	t.set_stylebox("fill", "ProgressBar", fg)
	t.set_color("font_color", "ProgressBar", TEXT)
	return t

# --- factories used by the screens ------------------------------------------
func box(fill: Color, border: Color, bw: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(0)          # square corners = arcade
	s.set_content_margin_all(MARGIN)
	return s

func label(text: String, size: int, color: Color, center: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	style_label(l, size, color)
	return l

func style_label(l: Label, size: int, color: Color) -> void:
	l.add_theme_font_override("font", FONT)   # explicit so it never falls back
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", maxi(3, size / 6))   # chunky drop-shadow

# A bordered panel StyleBox in the given accent (filled or ghosted).
func panel_box(accent: Color, filled: bool = true) -> StyleBoxFlat:
	return box(VOID if filled else _alpha(VOID, 0.42), accent, BORDER)

func style_button(btn: Button, accent: Color) -> void:
	btn.focus_mode = Control.FOCUS_ALL
	btn.add_theme_font_override("font", FONT)   # explicit so it never falls back
	btn.add_theme_stylebox_override("normal", box(VOID, accent, BORDER))
	btn.add_theme_stylebox_override("hover", box(_tint(accent, 0.24), accent.lightened(0.2), BORDER))
	btn.add_theme_stylebox_override("pressed", box(_tint(accent, 0.42), accent.lightened(0.35), BORDER))
	btn.add_theme_stylebox_override("focus", box(_tint(accent, 0.24), accent.lightened(0.3), BORDER))
	btn.add_theme_color_override("font_color", TEXT)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_focus_color", Color.WHITE)

# Style a ProgressBar with a coloured fill (health = green, shield = cyan, …).
func style_bar(bar: ProgressBar, fill: Color) -> void:
	var bg := box(Color(0.05, 0.06, 0.11, 0.92), _alpha(fill, 0.55), 1)
	bg.set_content_margin_all(0)
	var fg := box(fill, fill, 0)
	fg.set_content_margin_all(0)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)

# A chunky SEGMENTED bar (classic arcade health blocks) inside a thick frame. Returns
# a dict {frame, cells, fill, empty}; drive it with set_seg(bar, fraction).
func seg_bar(segments: int, fill: Color, cell_size: Vector2, framed: bool = true) -> Dictionary:
	var frame := PanelContainer.new()
	if framed:
		var fb := box(Color(0.02, 0.03, 0.06, 0.9), fill, BORDER)
		fb.set_content_margin_all(4)
		frame.add_theme_stylebox_override("panel", fb)
	else:
		frame.add_theme_stylebox_override("panel", StyleBoxEmpty.new())   # no border/bg
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	frame.add_child(h)
	var cells: Array = []
	for i in range(segments):
		var c := ColorRect.new()
		c.custom_minimum_size = cell_size
		c.size_flags_vertical = Control.SIZE_FILL
		h.add_child(c)
		cells.append(c)
	return {"frame": frame, "cells": cells, "fill": fill, "empty": _tint(fill, 0.16)}

# Light up the first floor(frac*N) blocks; the rest go dim. Always ≥1 block while alive.
func set_seg(bar: Dictionary, frac: float) -> void:
	var cells: Array = bar["cells"]
	var lit: int = int(round(clampf(frac, 0.0, 1.0) * float(cells.size())))
	if frac > 0.0:
		lit = maxi(1, lit)
	for i in range(cells.size()):
		(cells[i] as ColorRect).color = bar["fill"] if i < lit else bar["empty"]

# Full-rect CRT scanline + vignette overlay. Add it LAST (on top) to a CanvasLayer.
func scanlines(alpha: float = 0.14, vignette: float = 0.5) -> ColorRect:
	var cr := ColorRect.new()
	cr.name = "CRTOverlay"
	cr.set_anchors_preset(Control.PRESET_FULL_RECT)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = CRT
	m.set_shader_parameter("scanline_alpha", alpha)
	m.set_shader_parameter("vignette_strength", vignette)
	cr.material = m
	return cr

func _tint(c: Color, k: float) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, 0.95)

func _alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)
