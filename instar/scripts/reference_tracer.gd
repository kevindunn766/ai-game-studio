# Trace silhouette profiles directly from reference PHOTOS (pixels), so body profiles
# are READ from the image, not hand-authored. No class_name (headless-safe); use via
# `const ReferenceTracer = preload(...)`.
extends RefCounted

static func _lum(c: Color) -> float:
	return (c.r + c.g + c.b) / 3.0

# Mean luminance of SUBJECT pixels per sampled row along the body length (head->tail).
# Segment grooves show up as local minima (darker transverse lines) in this profile.
# `center_frac` restricts the horizontal band to the central fraction of each row so the
# printed segment NUMBERS / epimera edges don't dominate the groove signal.
static func length_luminance(img: Image, samples: int, thr: float, light_bg: bool, region: Rect2, center_frac: float = 0.6) -> PackedFloat32Array:
	var bb: Rect2i = subject_bbox(img, thr, light_bg, region)
	var out := PackedFloat32Array()
	for s in range(samples):
		var fy: float = float(s) / float(samples - 1)
		var y: int = clampi(bb.position.y + int(fy * (bb.size.y - 1)), 0, img.get_height() - 1)
		var span: Vector2i = _row_span(img, y, bb.position.x, bb.position.x + bb.size.x, thr, light_bg, 6)
		if span.x < 0:
			out.append(0.0)
			continue
		var cx: float = float(span.x + span.y) * 0.5
		var half: float = float(span.y - span.x) * 0.5 * center_frac
		var lo: int = int(cx - half)
		var hi: int = int(cx + half)
		var sum: float = 0.0
		var cnt: int = 0
		for x in range(lo, hi + 1):
			sum += _lum(img.get_pixel(x, y))
			cnt += 1
		out.append(sum / float(max(cnt, 1)))
	return out

# Segment boundary positions (u in 0..1, head->tail) detected from the TOP view: the pale
# overlap lines between tergites are bright local maxima in the length-luminance profile.
static func detect_boundaries(img: Image, samples: int, thr: float, light_bg: bool, region: Rect2, center_frac: float = 0.6, win: int = 3, prominence: float = 0.03, min_bright: float = 0.42) -> PackedFloat32Array:
	var lum: PackedFloat32Array = length_luminance(img, samples, thr, light_bg, region, center_frac)
	var out := PackedFloat32Array()
	var last: int = -100
	for i in range(win, samples - win):
		var v: float = lum[i]
		var is_max: bool = true
		for d in range(-win, win + 1):
			if lum[i + d] > v + 0.0001:
				is_max = false
				break
		var avg: float = (lum[i - win] + lum[i + win]) * 0.5
		if is_max and v > avg + prominence and v > min_bright and (i - last) > win:
			out.append(float(i) / float(samples - 1))
			last = i
	return out

# Subject bounding box. light_bg=true -> subject is DARK (side photo on white);
# light_bg=false -> subject is BRIGHT (dorsal photo on black). Restricted to `region`
# (fractional Rect2 in 0..1) so we can crop to one creature / away from labels.
static func subject_bbox(img: Image, thr: float, light_bg: bool, region: Rect2) -> Rect2i:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var x0: int = int(region.position.x * w)
	var y0: int = int(region.position.y * h)
	var x1: int = int((region.position.x + region.size.x) * w)
	var y1: int = int((region.position.y + region.size.y) * h)
	var minx: int = x1
	var miny: int = y1
	var maxx: int = x0 - 1
	var maxy: int = y0 - 1
	for y in range(y0, y1):
		for x in range(x0, x1):
			var s: float = _lum(img.get_pixel(x, y))
			var hit: bool = (s < thr) if light_bg else (s > thr)
			if hit:
				minx = min(minx, x)
				maxx = max(maxx, x)
				miny = min(miny, y)
				maxy = max(maxy, y)
	return Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1)

# Topmost y in column `x` (within [y0,y1)) that STARTS a solid subject run of at least
# `min_run` pixels — this skips thin legs/antennae and stray specks, finding the shell.
# Returns -1 if the column has no qualifying run.
static func _col_top(img: Image, x: int, y0: int, y1: int, thr: float, light_bg: bool, min_run: int) -> int:
	var run: int = 0
	var run_start: int = -1
	for y in range(y0, y1):
		var v: float = _lum(img.get_pixel(x, y))
		var hit: bool = (v < thr) if light_bg else (v > thr)
		if hit:
			if run == 0:
				run_start = y
			run += 1
			if run >= min_run:
				return run_start
		else:
			run = 0
			run_start = -1
	return -1

# DORSAL top-line along the body length, traced from a SIDE photo. For each of `samples`
# columns across the subject bbox (nose->tail), find the shell's upper outline (topmost
# solid run, so thin legs/antennae are ignored). Returns normalized arch height
# (0 = lowest shell point i.e. head/tail, 1 = tallest point mid-body).
static func trace_topline(img: Image, samples: int, thr: float, light_bg: bool, region: Rect2, min_run: int = 30) -> PackedFloat32Array:
	var bb: Rect2i = subject_bbox(img, thr, light_bg, region)
	var tops := PackedInt32Array()
	var lo_y: int = 1 << 30
	var hi_y: int = -(1 << 30)
	for s in range(samples):
		var fx: float = float(s) / float(samples - 1)
		var x: int = clampi(bb.position.x + int(fx * (bb.size.x - 1)), 0, img.get_width() - 1)
		var ty: int = _col_top(img, x, bb.position.y, bb.position.y + bb.size.y, thr, light_bg, min_run)
		tops.append(ty)
		if ty >= 0:
			lo_y = min(lo_y, ty)
			hi_y = max(hi_y, ty)
	var out := PackedFloat32Array()
	var span: float = float(max(hi_y - lo_y, 1))
	for ty in tops:
		if ty < 0:
			out.append(0.0)
		else:
			out.append(clampf(float(hi_y - ty) / span, 0.0, 1.0))   # 1 at the peak (smallest y)
	return out

# Left & right subject edges of row `y` (within [x0,x1)), each requiring a solid run of
# `min_run` to ignore specks/labels. Returns Vector2i(lo, hi), or (-1,-1) if none.
static func _row_span(img: Image, y: int, x0: int, x1: int, thr: float, light_bg: bool, min_run: int) -> Vector2i:
	var lo: int = -1
	var run: int = 0
	var run_start: int = -1
	for x in range(x0, x1):
		var v: float = _lum(img.get_pixel(x, y))
		var hit: bool = (v < thr) if light_bg else (v > thr)
		if hit:
			if run == 0:
				run_start = x
			run += 1
			if run >= min_run and lo < 0:
				lo = run_start
		else:
			run = 0
	if lo < 0:
		return Vector2i(-1, -1)
	var hi: int = -1
	run = 0
	for x in range(x1 - 1, x0 - 1, -1):
		var v2: float = _lum(img.get_pixel(x, y))
		var hit2: bool = (v2 < thr) if light_bg else (v2 > thr)
		if hit2:
			run += 1
			if run >= min_run:
				hi = x + min_run - 1
				break
		else:
			run = 0
	return Vector2i(lo, max(hi, lo))

# HALF-WIDTH along the body length, traced from a TOP (dorsal) photo. Body runs vertically,
# so we sample ROWS (head->tail) and measure the subject's horizontal extent (solid runs
# only). Returns normalized half-width (0..1, 1 = widest).
static func trace_halfwidth(img: Image, samples: int, thr: float, light_bg: bool, region: Rect2, min_run: int = 6) -> PackedFloat32Array:
	var h: int = img.get_height()
	var bb: Rect2i = subject_bbox(img, thr, light_bg, region)
	var widths := PackedFloat32Array()
	var maxw: float = 1.0
	for s in range(samples):
		var fy: float = float(s) / float(samples - 1)
		var y: int = clampi(bb.position.y + int(fy * (bb.size.y - 1)), 0, h - 1)
		var span: Vector2i = _row_span(img, y, bb.position.x, bb.position.x + bb.size.x, thr, light_bg, min_run)
		var ww: float = float(span.y - span.x) if span.x >= 0 else 0.0
		widths.append(ww)
		maxw = max(maxw, ww)
	var out := PackedFloat32Array()
	for ww in widths:
		out.append(ww / maxw)
	return out
