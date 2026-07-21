# INSTAR — Main scene assembler.
# Builds the test bed for the procedural isopod: brown floor, lighting,
# isometric spring-arm camera, and the depth-map tilt-shift post pass.
# No controls yet — the bug drives itself in a circle so the look can be judged.
extends Node3D

const Isopod = preload("res://scripts/isopod.gd")               # preserved walking version
const IsopodRoller = preload("res://scripts/isopod_roller.gd")  # conglobation (roll-up) variant
const IsoCamera = preload("res://scripts/iso_camera.gd")
const MeshBuilder = preload("res://scripts/mesh_builder.gd")
const ReferenceTracer = preload("res://scripts/reference_tracer.gd")
const TiltShiftShader = preload("res://shaders/tilt_shift.gdshader")
const REF_DIR = "C:/Users/kevin/game-studio/instar/reference/"

@export var floor_size: float = 60.0
@export var pebble_count: int = 60

func _ready() -> void:
	_build_environment()
	_build_floor()
	# `--segment`: preview ONE formed-plate segment alone (shell shape review) — no bug/pebbles.
	if "--segment" in OS.get_cmdline_args():
		_build_segment_preview()
		return
	# `--traced`: preview the body lofted from PHOTO-TRACED profiles (side height + top width),
	# with a best-guess symmetric front section. Proves the trace->combine pipeline.
	if "--traced" in OS.get_cmdline_args():
		_build_traced_body_preview()
		return
	_scatter_pebbles()
	# Roller by default (shows the roll-up); `--walker` spawns the preserved walking version.
	var bug: Node3D = Isopod.new() if "--walker" in OS.get_cmdline_args() else IsopodRoller.new()
	if "--nolegs" in OS.get_cmdline_args():
		bug.set("show_legs", false)
	add_child(bug)
	var cam := IsoCamera.new()
	cam.target = bug
	add_child(cam)
	cam.setup_tilt_shift(TiltShiftShader)

	if "--capture" in OS.get_cmdline_args():
		_run_capture()

# Single-segment preview: build ONE formed-plate tergite and frame it, to review the
# traced shell shape before rebuilding the whole body. Dev-only (--segment), removable.
func _build_segment_preview() -> void:
	var target := Node3D.new()
	target.position = Vector3(0.0, 0.55, 0.0)
	add_child(target)
	# Traced FRONT half cross-section of one mid-body tergite (dorsal midline -> epimeron tip):
	# broad round dome, shoulder, then the epimeron flaring out and hanging down toward the legs.
	var seg_outline: Array[Vector2] = [
		Vector2(0.00, 1.00),   # dorsal midline
		Vector2(0.30, 0.985),
		Vector2(0.56, 0.94),
		Vector2(0.77, 0.86),
		Vector2(0.92, 0.72),
		Vector2(1.02, 0.53),   # shoulder (widest)
		Vector2(1.06, 0.33),   # epimeron flares out
		Vector2(1.03, 0.13),
		Vector2(0.90, -0.05),  # epimeron tip (hangs down)
	]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.25, 0.24)
	mat.roughness = 0.65
	var mi := MeshInstance3D.new()
	mi.mesh = MeshBuilder.formed_plate(seg_outline, 0.5, 0.42, 0.34)
	mi.material_override = mat
	mi.position = Vector3(0.0, 0.42, 0.0)     # lift the plate above the floor
	add_child(mi)
	var cam := IsoCamera.new()
	cam.target = target
	cam.ortho_size = 1.8                        # zoom in on the single segment
	add_child(cam)
	cam.setup_tilt_shift(TiltShiftShader)
	if "--capture" in OS.get_cmdline_args():
		_run_capture()

# Replace 0-samples (trace dropouts) with interpolated / clamped neighbours so the loft
# doesn't pinch. Leading/trailing zeros clamp to the nearest real value.
func _clean(arr: PackedFloat32Array) -> PackedFloat32Array:
	var n: int = arr.size()
	var out := arr.duplicate()
	# forward-fill leading zeros
	var first: int = -1
	for i in range(n):
		if arr[i] > 0.001:
			first = i
			break
	if first < 0:
		return out
	for i in range(first):
		out[i] = arr[first]
	# back-fill trailing zeros
	var last: int = n - 1
	while last > 0 and arr[last] <= 0.001:
		last -= 1
	for i in range(last + 1, n):
		out[i] = arr[last]
	# interior zeros: linear interp between the nearest non-zero neighbours
	for i in range(first + 1, last):
		if out[i] <= 0.001:
			var a: int = i - 1
			while a > first and out[a] <= 0.001:
				a -= 1
			var b: int = i + 1
			while b < last and arr[b] <= 0.001:
				b += 1
			var t: float = float(i - a) / float(b - a)
			out[i] = lerp(out[a], arr[b], t)
	return out

# Moving-average smooth a profile (radius r) to kill per-sample trace noise / lumpiness.
func _smooth(arr: PackedFloat32Array, r: int) -> PackedFloat32Array:
	var n: int = arr.size()
	var out := PackedFloat32Array()
	for i in range(n):
		var sum: float = 0.0
		var cnt: int = 0
		for d in range(-r, r + 1):
			var j: int = clampi(i + d, 0, n - 1)
			sum += arr[j]
			cnt += 1
		out.append(sum / float(cnt))
	return out

# Linear-sample a per-length profile array at fractional position u (0..1).
func _sample_arr(arr: PackedFloat32Array, u: float) -> float:
	var n: int = arr.size()
	var f: float = clampf(u, 0.0, 1.0) * float(n - 1)
	var i: int = int(f)
	if i >= n - 1:
		return arr[n - 1]
	return lerp(arr[i], arr[i + 1], f - float(i))

# An EVEN semicircle (flat-bottomed dome) half cross-section, generated with equal angular
# steps — no hand-placed data points. Runs from the dorsal midline (0,1) around the arc to
# the side (1,0), then a flat base back to centre (0,0); the loft mirrors it across X.
func _semicircle_outline(arc_steps: int) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	for i in range(arc_steps + 1):
		var ang: float = PI * 0.5 * float(i) / float(arc_steps)   # 0..90 deg, even steps
		pts.append(Vector2(sin(ang), cos(ang)))                   # (0,1) -> (1,0)
	pts.append(Vector2(0.0, 0.0))                                 # flat base to centre
	return pts

# Build the body as DISCRETE segment pieces: segment ENDS come from the top-view boundary
# edges; each piece is a SEMICIRCLE section scaled by the traced width; the side-view height
# profile ALIGNS the pieces along the dorsal arch; pieces overlap like shingles.
func _build_traced_body_preview() -> void:
	var side: Image = Image.load_from_file(REF_DIR + "side.jpg")
	var top: Image = Image.load_from_file(REF_DIR + "anatomy_top.jpg")
	var top_region := Rect2(0.19, 0.27, 0.30, 0.68)
	var side_h: PackedFloat32Array = _smooth(_clean(ReferenceTracer.trace_topline(side, 60, 0.5, true, Rect2(0, 0, 1, 1), 30)), 3)
	var top_w: PackedFloat32Array = _smooth(_clean(ReferenceTracer.trace_halfwidth(top, 60, 0.30, false, top_region, 6)), 3)
	# Segment boundaries (u) detected from the top view -> the ends of the segments.
	var b: PackedFloat32Array = ReferenceTracer.detect_boundaries(top, 120, 0.30, false, top_region)
	var edges: Array = [0.0]
	for u in b:
		edges.append(u)
	edges.append(1.0)                              # head + one piece per gap + tail
	# Proportions from the traced bboxes: length 1.8; width from the top bbox (409/605).
	# HEIGHT: the side bbox (383px) includes the LEGS hanging below the shell, so the shell
	# is only ~half of it — use 0.5 or the body reads as a fat round coil (not a flat isopod).
	var span_z: float = 1.8
	var max_hw: float = span_z * 0.5 * (409.0 / 605.0)
	var max_h: float = span_z * (383.0 / 1029.0) * 0.5
	var overlap: float = 0.06                       # front of each piece tucks well under the one ahead
	var proud: float = 0.03                         # rear sits proud (thin shingle lip)
	var semi: Array[Vector2] = _semicircle_outline(10)   # even generated cross-section
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.25, 0.24)
	mat.roughness = 0.65
	for s in range(edges.size() - 1):
		var u0: float = maxf(float(edges[s]) - overlap, 0.0)
		var u1: float = float(edges[s + 1])
		var rings: int = 6
		var sx := PackedFloat32Array()
		var sy := PackedFloat32Array()
		var zs := PackedFloat32Array()
		var zc: float = lerp(-span_z * 0.5, span_z * 0.5, (u0 + u1) * 0.5)
		for k in range(rings):
			var t: float = float(k) / float(rings - 1)
			var u: float = lerp(u0, u1, t)
			var p: float = 1.0 + proud * t
			sx.append(max_hw * maxf(_sample_arr(top_w, u), 0.12) * p)
			sy.append(max_h * (0.30 + 0.70 * _sample_arr(side_h, u)) * p)
			zs.append(lerp(-span_z * 0.5, span_z * 0.5, u) - zc)
		var mi := MeshInstance3D.new()
		mi.mesh = MeshBuilder.loft_closed(semi, sx, sy, zs)
		mi.material_override = mat
		mi.position = Vector3(0.0, max_h + 0.05, zc)
		add_child(mi)
	var target := Node3D.new()
	target.position = Vector3(0.0, max_h + 0.05, 0.0)
	add_child(target)
	var cam := IsoCamera.new()
	cam.target = target
	cam.ortho_size = 2.6
	add_child(cam)
	cam.setup_tilt_shift(TiltShiftShader)
	if "--capture" in OS.get_cmdline_args():
		_run_capture()

# Temporary dev-only screenshot capture (flag-gated, removable).
func _run_capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://_shots"))
	for n in range(1, 5):
		await get_tree().create_timer(0.45).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://_shots/shot%d.png" % n)
	get_tree().quit()

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.30, 0.34, 0.40)     # soft grey-blue backdrop
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.60)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 40.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)

func _build_floor() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(floor_size, floor_size)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.34, 0.24, 0.15)         # brown dirt floor
	mat.roughness = 1.0
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	add_child(mi)

# Small scattered pebbles: purely a depth reference to judge the tilt-shift focus
# band (near = sharp, far = blurred). Trivially removable test dressing.
func _scatter_pebbles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260718
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.24, 0.20)
	mat.roughness = 1.0
	for _i in range(pebble_count):
		var box := BoxMesh.new()
		var s := rng.randf_range(0.10, 0.28)
		box.size = Vector3(s, s * 0.6, s)
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.material_override = mat
		var r := rng.randf_range(1.5, floor_size * 0.45)
		var a := rng.randf_range(0.0, TAU)
		mi.position = Vector3(cos(a) * r, s * 0.3, sin(a) * r)
		mi.rotation.y = rng.randf_range(0.0, TAU)
		add_child(mi)
