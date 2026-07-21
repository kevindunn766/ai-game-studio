# Headless: detect segment boundaries from the TOP view (transverse groove minima) and
# draw them on the overlay so we can verify the "edges" that will become segment ends.
#   godot --headless --path instar --script res://trace_segments.gd
extends SceneTree

const ReferenceTracer = preload("res://scripts/reference_tracer.gd")
const DIR = "C:/Users/kevin/game-studio/instar/reference/"

func _initialize() -> void:
	var top: Image = Image.load_from_file(DIR + "anatomy_top.jpg")
	var region := Rect2(0.19, 0.27, 0.30, 0.68)
	var N: int = 120
	var lum: PackedFloat32Array = ReferenceTracer.length_luminance(top, N, 0.30, false, region, 0.6)
	# Print the profile (head->tail) so we can see the groove minima.
	var s := ""
	for i in range(N):
		s += "%.2f " % lum[i]
	print("length luminance [%d]: %s" % [N, s])
	# Detect local MAXIMA: the pale overlap lines between segments are bright transverse rows.
	var bb: Rect2i = ReferenceTracer.subject_bbox(top, 0.30, false, region)
	var bounds: Array = []
	var win: int = 3
	for i in range(win, N - win):
		var v: float = lum[i]
		var is_max: bool = true
		for d in range(-win, win + 1):
			if lum[i + d] > v + 0.0001:
				is_max = false
				break
		var avg: float = (lum[i - win] + lum[i + win]) * 0.5
		if is_max and v > avg + 0.03 and v > 0.42:
			bounds.append(i)
	# de-dup near-duplicates
	var merged: Array = []
	for b in bounds:
		if merged.is_empty() or (b - int(merged[-1])) > 3:
			merged.append(b)
	print("detected boundaries (of %d): %s" % [N, str(merged)])
	# Draw them as horizontal green lines on the overlay.
	for b in merged:
		var y: int = bb.position.y + int(float(b) / float(N - 1) * (bb.size.y - 1))
		for x in range(bb.position.x, bb.position.x + bb.size.x):
			top.set_pixel(x, y, Color(0, 1, 0))
			top.set_pixel(x, y + 1, Color(0, 1, 0))
	top.save_png(DIR + "_dbg_segments.png")
	quit()
