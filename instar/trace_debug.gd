# Headless: trace reference photos and draw the extracted outline back onto them so we
# can SEE whether the pixel trace follows the shell. Run:
#   godot --headless --path instar --script res://trace_debug.gd
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

func _dump(label: String, arr: PackedFloat32Array) -> void:
	var s: String = ""
	for i in range(arr.size()):
		s += "%.2f " % arr[i]
	print("%s [%d]: %s" % [label, arr.size(), s])

func _initialize() -> void:
	# ---- SIDE view (dark subject on white bg): dorsal top-line, min_run skips legs/antennae ----
	var side: Image = Image.load_from_file(DIR + "side.jpg")
	print("side.jpg  %d x %d" % [side.get_width(), side.get_height()])
	var side_region := Rect2(0.0, 0.0, 1.0, 1.0)
	var sbb: Rect2i = ReferenceTracer.subject_bbox(side, 0.5, true, side_region)
	print("side bbox: ", sbb)
	for x in range(sbb.position.x, sbb.position.x + sbb.size.x):
		var ty: int = ReferenceTracer._col_top(side, x, sbb.position.y, sbb.position.y + sbb.size.y, 0.5, true, 30)
		if ty >= 0:
			_mark(side, x, ty, Color(1, 0, 0))
	side.save_png(DIR + "_dbg_side.png")
	_dump("side dorsal-arch", ReferenceTracer.trace_topline(side, 24, 0.5, true, side_region, 30))

	# ---- TOP view (bright subject on black bg): dorsal creature = LEFT; crop wide enough ----
	var top: Image = Image.load_from_file(DIR + "anatomy_top.jpg")
	print("anatomy_top.jpg  %d x %d" % [top.get_width(), top.get_height()])
	var top_region := Rect2(0.19, 0.27, 0.30, 0.68)
	var tbb: Rect2i = ReferenceTracer.subject_bbox(top, 0.30, false, top_region)
	print("top bbox: ", tbb)
	for s in range(120):
		var y: int = tbb.position.y + int(float(s) / 119.0 * (tbb.size.y - 1))
		var span: Vector2i = ReferenceTracer._row_span(top, y, tbb.position.x, tbb.position.x + tbb.size.x, 0.30, false, 6)
		if span.x >= 0:
			_mark(top, span.x, y, Color(1, 0, 0))
			_mark(top, span.y, y, Color(1, 0, 0))
	top.save_png(DIR + "_dbg_top.png")
	_dump("top half-width", ReferenceTracer.trace_halfwidth(top, 24, 0.30, false, top_region, 6))
	quit()
