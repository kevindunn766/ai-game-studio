extends RefCounted

# Procedural BOSS hull for the end-of-level Star Fox-style boss: a big ARMORED
# central body + symmetric arms with weak-point sockets + menacing greeble. The
# hull faces +Z (toward the player, who flies toward -Z). Returns:
#   { hull: Node3D (flat-shaded MeshInstances), anchors: Array[Vector3] }
# where each anchor is a local position (facing +Z) at which boss.gd mounts a
# glowing vulnerable weak point. No class_name (headless-safe -- preload const).

const MeshUtil := preload("res://scripts/mesh_util.gd")

static func build(rng: RandomNumberGenerator, primary: Color, accent: Color) -> Dictionary:
	# Archetype chosen from the (biome-seeded) rng -> each biome gets its own form.
	var k: int = rng.randi() % 3
	var d: Dictionary
	if k == 1:
		d = _wall(rng, primary, accent)
	elif k == 2:
		d = _ring(rng, primary, accent)
	else:
		d = _core_arms(rng, primary, accent)
	d["kind"] = ["core_arms", "wall", "ring"][k]   # drives the attack pattern
	return d

# Central armored core + symmetric arm pods + optional top cannon.
static func _core_arms(rng: RandomNumberGenerator, primary: Color, accent: Color) -> Dictionary:
	var hull := Node3D.new()
	var armor: StandardMaterial3D = _mat(primary.darkened(0.55), 0.75, 0.4)
	var trim: StandardMaterial3D = _mat(primary.darkened(0.25).lerp(accent, 0.15), 0.55, 0.5)
	var anchors: Array = []

	var r: float = rng.randf_range(3.0, 4.0)              # core radius
	# --- central armored core (flattened, wider than tall) ---
	_add(hull, _sphere(r), armor, Transform3D(Basis().scaled(Vector3(1.35, 0.85, 1.0)), Vector3.ZERO))
	# brow plate over the top-front
	_add(hull, _box(r * 1.7, r * 0.5, r * 0.5), armor, Transform3D(Basis(), Vector3(0, r * 0.55, r * 0.6)))
	# front socket ring around the central weak point
	_add(hull, _cyl(r * 0.62, r * 0.62, r * 0.28, 12), trim, Transform3D(_face_z(), Vector3(0, 0, r * 0.78)))
	anchors.append(Vector3(0, 0, r * 1.0))

	# --- symmetric arms, each ending in a pod that houses a weak point ---
	var arm_len: float = r * rng.randf_range(1.6, 2.3)
	var arm_inner: float = r * 0.9
	for s in [-1.0, 1.0]:
		var beam_cx: float = s * (arm_inner + arm_len * 0.5)
		_add(hull, _box(arm_len, r * 0.42, r * 0.6), armor, Transform3D(Basis(), Vector3(beam_cx, 0, 0)))
		var pod_x: float = s * (arm_inner + arm_len)
		_add(hull, _sphere(r * 0.62), armor, Transform3D(Basis().scaled(Vector3(1.0, 0.9, 1.1)), Vector3(pod_x, 0, r * 0.1)))
		_add(hull, _cyl(r * 0.42, r * 0.42, r * 0.24, 10), trim, Transform3D(_face_z(), Vector3(pod_x, 0, r * 0.55)))
		anchors.append(Vector3(pod_x, 0, r * 0.72))

	# --- optional top cannon-pod weak point (some bosses) ---
	if rng.randf() < 0.7:
		_add(hull, _cyl(r * 0.5, r * 0.62, r * 0.9, 8), armor, Transform3D(Basis(), Vector3(0, r * 0.95, 0)))
		_add(hull, _cyl(r * 0.36, r * 0.36, r * 0.22, 10), trim, Transform3D(_face_z(), Vector3(0, r * 1.05, r * 0.4)))
		anchors.append(Vector3(0, r * 1.05, r * 0.6))

	# --- greeble: menacing spikes/nubs across the front ---
	for _i in range(rng.randi_range(6, 12)):
		var gx: float = rng.randf_range(-arm_inner, arm_inner)
		var gy: float = rng.randf_range(-r * 0.7, r * 0.9)
		var gs: float = rng.randf_range(0.18, 0.4) * r
		_add(hull, _cyl(0.0, gs * 0.35, gs, 5), trim, Transform3D(_face_z(), Vector3(gx, gy, r * 0.85)))

	return {"hull": hull, "anchors": anchors}

# A wide armored WALL / gate: weak points in a row across the face, buttresses at
# the ends. Reads great from top-down and side (a barrier spanning the screen).
static func _wall(rng: RandomNumberGenerator, primary: Color, accent: Color) -> Dictionary:
	var hull := Node3D.new()
	var armor: StandardMaterial3D = _mat(primary.darkened(0.55), 0.7, 0.45)
	var trim: StandardMaterial3D = _mat(primary.darkened(0.2).lerp(accent, 0.15), 0.55, 0.5)
	var anchors: Array = []

	var w: float = rng.randf_range(9.0, 13.0)
	var h: float = rng.randf_range(3.5, 5.5)
	var th: float = rng.randf_range(1.4, 2.2)
	_add(hull, _box(w, h, th), armor, Transform3D())
	# end buttresses
	for s in [-1.0, 1.0]:
		_add(hull, _box(th * 1.1, h * 1.35, th * 1.3), armor, Transform3D(Basis(), Vector3(s * w * 0.5, 0, th * 0.1)))
	# weak points in a row across the front (+Z)
	var cols: int = rng.randi_range(3, 5)
	for i in range(cols):
		var x: float = lerp(-w * 0.36, w * 0.36, float(i) / float(cols - 1))
		var y: float = rng.randf_range(-h * 0.12, h * 0.2)
		_add(hull, _cyl(0.9, 0.9, th * 0.5, 10), trim, Transform3D(_face_z(), Vector3(x, y, th * 0.5)))
		anchors.append(Vector3(x, y, th * 0.62))
	# a few crenellation nubs along the top
	for _i in range(rng.randi_range(3, 6)):
		var gx: float = rng.randf_range(-w * 0.45, w * 0.45)
		_add(hull, _box(w * 0.06, h * 0.3, th * 0.9), armor, Transform3D(Basis(), Vector3(gx, h * 0.6, 0)))
	return {"hull": hull, "anchors": anchors}

# A RING of pods around a hub, weak point on each pod. Reads well from every view.
static func _ring(rng: RandomNumberGenerator, primary: Color, accent: Color) -> Dictionary:
	var hull := Node3D.new()
	var armor: StandardMaterial3D = _mat(primary.darkened(0.55), 0.75, 0.4)
	var trim: StandardMaterial3D = _mat(primary.darkened(0.2).lerp(accent, 0.15), 0.55, 0.5)
	var anchors: Array = []

	var radius: float = rng.randf_range(4.0, 6.0)
	var pods: int = rng.randi_range(3, 5)
	var phase: float = rng.randf() * TAU
	# central hub
	_add(hull, _sphere(radius * 0.42), armor, Transform3D(Basis().scaled(Vector3(1.1, 1.1, 0.8)), Vector3.ZERO))
	# central weak point too
	_add(hull, _cyl(radius * 0.32, radius * 0.32, 0.4, 10), trim, Transform3D(_face_z(), Vector3(0, 0, radius * 0.35)))
	anchors.append(Vector3(0, 0, radius * 0.5))
	for i in range(pods):
		var a: float = phase + TAU * float(i) / float(pods)
		var px: float = cos(a) * radius
		var py: float = sin(a) * radius
		_bar(hull, armor, Vector3.ZERO, Vector3(px, py, 0), radius * 0.09)
		_add(hull, _sphere(radius * 0.42), armor, Transform3D(Basis().scaled(Vector3(1.0, 1.0, 0.9)), Vector3(px, py, 0)))
		_add(hull, _cyl(radius * 0.26, radius * 0.26, 0.35, 10), trim, Transform3D(_face_z(), Vector3(px, py, radius * 0.28)))
		anchors.append(Vector3(px, py, radius * 0.4))
	return {"hull": hull, "anchors": anchors}

# --- helpers ----------------------------------------------------------------
static func _bar(hull: Node3D, mat: StandardMaterial3D, a: Vector3, b: Vector3, r: float) -> void:
	var d: Vector3 = b - a
	if d.length() < 1e-4:
		return
	var y: Vector3 = d.normalized()
	var ref: Vector3 = Vector3.FORWARD if absf(y.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var x: Vector3 = ref.cross(y).normalized()
	var z: Vector3 = x.cross(y).normalized()
	_add(hull, _cyl(r, r, d.length(), 6), mat, Transform3D(Basis(x, y, z), (a + b) * 0.5))

static func _face_z() -> Basis:
	# A cylinder/cone models along +Y; rotate so it points along +Z (toward player).
	return Basis(Vector3(1, 0, 0), PI * 0.5)

static func _mat(c: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = roughness
	return m

static func _add(hull: Node3D, mesh: Mesh, mat: StandardMaterial3D, xf: Transform3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshUtil.flat(mesh)
	mi.material_override = mat
	mi.transform = xf
	hull.add_child(mi)

static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 14
	s.rings = 7
	return s

static func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b

static func _cyl(rt: float, rb: float, h: float, sides: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = sides
	c.rings = 1
	return c
