# Headless: trace the FRONT cross-section (dome arch) from the head-on panel of front.jpg.
# Best-guess silhouette; symmetry is forced later by mirroring the traced half. Draws an
# overlay so we can verify segmentation off the woody background. Run:
#   godot --headless --path instar --script res://trace_front.gd
extends SceneTree

const ReferenceTracer = preload("res://scripts/reference_tracer.gd")
const DIR = "C:/Users/kevin/game-studio/instar/reference/"

func _mark(img: Image, x: int, y: int, col: Color) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var px: int = x + dx
			var py: int = y + dy
			if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
				img.set_pixel(px, py, col)

# Subject test by CHROMA: the bug is cool/neutral (R-B small); wood is warm (R-B large).
func _is_bug(c: Color) -> bool:
	return (c.r - c.b) < 0.06

# Left/right subject edges of a row using the chroma test + a min solid run.
func _row_span_chroma(img: Image, y: int, x0: int, x1: int, min_run: int) -> Vector2i:
	var lo: int = -1
	var run: int = 0
	var start: int = -1
	for x in range(x0, x1):
		if _is_bug(img.get_pixel(x, y)):
			if run == 0: start = x
			run += 1
			if run >= min_run and lo < 0: lo = start
		else:
			run = 0
	if lo < 0:
		return Vector2i(-1, -1)
	var hi: int = -1
	run = 0
	for x in range(x1 - 1, x0 - 1, -1):
		if _is_bug(img.get_pixel(x, y)):
			run += 1
			if run >= min_run:
				hi = x + min_run - 1; break
		else:
			run = 0
	return Vector2i(lo, max(hi, lo))

func _initialize() -> void:
	var img: Image = Image.load_from_file(DIR + "front.jpg")
	print("front.jpg  %d x %d" % [img.get_width(), img.get_height()])
	# Left panel = head-on 3/4 view. Crop to the rounded body (exclude head/legs at the bottom).
	var region := Rect2(0.06, 0.08, 0.42, 0.62)
	var rx0: int = int(region.position.x * img.get_width())
	var ry0: int = int(region.position.y * img.get_height())
	var rx1: int = int((region.position.x + region.size.x) * img.get_width())
	var ry1: int = int((region.position.y + region.size.y) * img.get_height())
	for x in range(rx0, rx1):
		_mark(img, x, ry0, Color(0, 0.5, 1)); _mark(img, x, ry1, Color(0, 0.5, 1))
	for y in range(ry0, ry1):
		_mark(img, rx0, y, Color(0, 0.5, 1)); _mark(img, rx1, y, Color(0, 0.5, 1))
	var s2 := ""
	for s in range(140):
		var y2: int = ry0 + int(float(s) / 139.0 * (ry1 - ry0 - 1))
		var span: Vector2i = _row_span_chroma(img, y2, rx0, rx1, 12)
		if span.x >= 0:
			_mark(img, span.x, y2, Color(1, 0, 0)); _mark(img, span.y, y2, Color(1, 0, 0))
	img.save_png(DIR + "_dbg_front.png")
	for i in range(12):
		var y3: int = ry0 + int(float(i) / 11.0 * (ry1 - ry0 - 1))
		var span3: Vector2i = _row_span_chroma(img, y3, rx0, rx1, 12)
		var hw: float = float(span3.y - span3.x) * 0.5 if span3.x >= 0 else 0.0
		s2 += "%.0f " % hw
	print("front half-width apex->base (px): ", s2)
	quit()
