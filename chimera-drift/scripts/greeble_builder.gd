extends RefCounted

# Procedural GREEBLE props for the beauty-shot ships: satellite dishes, scaffolding
# trusses, and antennas -- each with several variants for diversity. Built from
# low-poly Godot primitives (correct built-in winding), flat-shaded to match the
# faceted ship. Modeled growing along +Y from the base at origin; the scatter
# (BeautyShipDresser) orients +Y to the hull surface normal. Beauty-shot DETAIL
# only. No class_name (headless-safe -- referenced via preload const).

const MeshUtil := preload("res://scripts/mesh_util.gd")

enum { DISH, TRUSS, ANTENNA }

static func build(kind: int, rng: RandomNumberGenerator, s: float, mat: StandardMaterial3D) -> Node3D:
	match kind:
		DISH:
			return _dish(rng, s, mat)
		TRUSS:
			return _truss(rng, s, mat)
		_:
			return _antenna(rng, s, mat)

static func build_random(rng: RandomNumberGenerator, s: float, mat: StandardMaterial3D) -> Node3D:
	return build(rng.randi() % 3, rng, s, mat)

# --- satellite dishes: parabolic dish / drum radome / ringed dish -----------
static func _dish(rng: RandomNumberGenerator, s: float, mat: StandardMaterial3D) -> Node3D:
	var root := Node3D.new()
	_add(root, _cyl(0.06 * s, 0.14 * s), mat, Transform3D(Basis(), Vector3(0, 0.07 * s, 0)))
	var arm_top := Vector3(0, 0.26 * s, 0.0)
	_bar(root, mat, Vector3(0, 0.14 * s, 0), arm_top, 0.025 * s)
	var tilt := Basis(Vector3(1, 0, 0), -deg_to_rad(rng.randf_range(18.0, 54.0)))

	match rng.randi() % 3:
		0:                                          # classic parabolic dish + feed
			_dish_cup(root, mat, arm_top, tilt, rng.randf_range(0.26, 0.42) * s, s, true, rng)
		1:                                          # drum radome: short wide cylinder + sensor
			var dia: float = rng.randf_range(0.2, 0.32) * s
			_add(root, _cyl(dia, 0.14 * s), mat, Transform3D(tilt, arm_top))
			var cap := _sphere(dia * 0.9)
			_add(root, cap, mat, Transform3D(Basis().scaled(Vector3(1, 0.5, 1)), arm_top + tilt * Vector3(0, 0.1 * s, 0)))
			_add(root, _box(0.05 * s, 0.08 * s, 0.05 * s), mat, Transform3D(tilt, arm_top + tilt * Vector3(0, 0.16 * s, 0)))
		_:                                          # ringed dish: deep cup + rim torus + feed
			var dia2: float = rng.randf_range(0.3, 0.46) * s
			_dish_cup(root, mat, arm_top, tilt, dia2, s, true, rng)
			var rim := TorusMesh.new()
			rim.inner_radius = dia2 * 0.92
			rim.outer_radius = dia2 * 1.05
			rim.rings = 14
			rim.ring_segments = 6
			_add(root, rim, mat, Transform3D(tilt, arm_top + tilt * Vector3(0, 0.045 * s, 0)))
	return root

# A shallow dish cup (+ optional feed rod & receiver), tilted by `tb`, at `at`.
static func _dish_cup(root: Node3D, mat: StandardMaterial3D, at: Vector3, tb: Basis, dia: float, s: float, feed: bool, rng: RandomNumberGenerator) -> void:
	var cup := CylinderMesh.new()
	cup.top_radius = dia
	cup.bottom_radius = dia * 0.16
	cup.height = 0.09 * s
	cup.radial_segments = 12
	cup.rings = 1
	_add(root, cup, mat, Transform3D(tb, at))
	if feed and rng.randf() < 0.8:
		var axis: Vector3 = tb * Vector3(0, 1, 0)
		var focus: Vector3 = at + axis * 0.17 * s
		_bar(root, mat, at + axis * 0.02 * s, focus, 0.012 * s)
		_add(root, _sphere(0.03 * s), mat, Transform3D(Basis(), focus))

# --- scaffolding: box truss / tripod / ladder mast -------------------------
static func _truss(rng: RandomNumberGenerator, s: float, mat: StandardMaterial3D) -> Node3D:
	var root := Node3D.new()
	var h: float = rng.randf_range(0.36, 0.6) * s
	var w: float = rng.randf_range(0.08, 0.13) * s
	var r: float = 0.016 * s

	match rng.randi() % 3:
		0:                                          # box truss: 4 legs + rungs + braces
			var legs := [Vector3(-w, 0, -w), Vector3(w, 0, -w), Vector3(w, 0, w), Vector3(-w, 0, w)]
			for i in range(4):
				var foot: Vector3 = legs[i]
				_bar(root, mat, foot, foot + Vector3(0, h, 0), r)
			for frac in [0.34, 0.67, 1.0]:
				var y: float = h * frac
				for i in range(4):
					_bar(root, mat, legs[i] + Vector3(0, y, 0), legs[(i + 1) % 4] + Vector3(0, y, 0), r * 0.75)
			_bar(root, mat, legs[0], legs[2] + Vector3(0, h, 0), r * 0.7)
			_bar(root, mat, legs[1], legs[3] + Vector3(0, h, 0), r * 0.7)
			_add(root, _box(w * 2.3, 0.05 * s, w * 2.3), mat, Transform3D(Basis(), Vector3(0, h, 0)))
		1:                                          # tripod + top module
			var top := Vector3(0, h, 0)
			for i in range(3):
				var ang: float = TAU * float(i) / 3.0
				var foot := Vector3(cos(ang), 0.0, sin(ang)) * w * 1.7
				_bar(root, mat, foot, top - Vector3(0, 0.08 * s, 0), r)
			_bar(root, mat, top - Vector3(0, 0.08 * s, 0), top, r * 1.2)
			_add(root, _box(0.09 * s, 0.08 * s, 0.09 * s), mat, Transform3D(Basis(), top))
		_:                                          # ladder mast: two rails + rungs
			var rail := w * 1.1
			_bar(root, mat, Vector3(-rail, 0, 0), Vector3(-rail, h, 0), r)
			_bar(root, mat, Vector3(rail, 0, 0), Vector3(rail, h, 0), r)
			var rungs: int = rng.randi_range(3, 5)
			for i in range(rungs + 1):
				var y: float = h * float(i) / float(rungs)
				_bar(root, mat, Vector3(-rail, y, 0), Vector3(rail, y, 0), r * 0.7)
			_add(root, _box(rail * 2.4, 0.05 * s, 0.1 * s), mat, Transform3D(Basis(), Vector3(0, h, 0)))
	return root

# --- antennas: whips / Yagi / dish-on-mast / flat panel --------------------
static func _antenna(rng: RandomNumberGenerator, s: float, mat: StandardMaterial3D) -> Node3D:
	var root := Node3D.new()
	match rng.randi() % 4:
		0:                                          # cluster of whips + tip balls
			var n: int = rng.randi_range(2, 3)
			for i in range(n):
				var x: float = (float(i) - float(n - 1) * 0.5) * 0.07 * s
				var hh: float = rng.randf_range(0.42, 0.72) * s * (1.0 - 0.12 * float(i))
				_bar(root, mat, Vector3(x, 0.03 * s, 0), Vector3(x, hh, 0), 0.012 * s)
				_add(root, _sphere(0.022 * s), mat, Transform3D(Basis(), Vector3(x, hh, 0)))
			_add(root, _box(0.15 * s, 0.05 * s, 0.1 * s), mat, Transform3D(Basis(), Vector3(0, 0.025 * s, 0)))
		1:                                          # Yagi: mast + shortening elements
			var h1: float = rng.randf_range(0.46, 0.68) * s
			_bar(root, mat, Vector3(0, 0, 0), Vector3(0, h1, 0), 0.017 * s)
			var elems: int = rng.randi_range(3, 5)
			for i in range(elems):
				var t: float = float(i) / float(elems)
				var y: float = h1 * (0.32 + 0.62 * t)
				var el: float = (0.3 - 0.16 * t) * s
				_bar(root, mat, Vector3(-el, y, 0), Vector3(el, y, 0), 0.01 * s)
			_add(root, _box(0.08 * s, 0.06 * s, 0.05 * s), mat, Transform3D(Basis(), Vector3(0, 0.035 * s, 0)))
		2:                                          # dish on a mast
			var h2: float = rng.randf_range(0.4, 0.6) * s
			_bar(root, mat, Vector3(0, 0, 0), Vector3(0, h2, 0), 0.02 * s)
			var tb := Basis(Vector3(1, 0, 0), -deg_to_rad(rng.randf_range(25.0, 55.0)))
			_dish_cup(root, mat, Vector3(0, h2, 0), tb, rng.randf_range(0.18, 0.28) * s, s, true, rng)
		_:                                          # flat panel antenna on a short mast
			var h3: float = rng.randf_range(0.3, 0.5) * s
			_bar(root, mat, Vector3(0, 0, 0), Vector3(0, h3, 0), 0.02 * s)
			var pb := Basis(Vector3(1, 0, 0), -deg_to_rad(rng.randf_range(10.0, 40.0)))
			_add(root, _box(rng.randf_range(0.26, 0.4) * s, 0.03 * s, rng.randf_range(0.14, 0.24) * s), mat, Transform3D(pb, Vector3(0, h3, 0)))
			_add(root, _box(0.07 * s, 0.06 * s, 0.05 * s), mat, Transform3D(Basis(), Vector3(0, 0.03 * s, 0)))
	return root

# --- primitive + placement helpers -----------------------------------------
static func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 8
	c.rings = 1
	return c

static func _sphere(r: float) -> SphereMesh:
	var sp := SphereMesh.new()
	sp.radius = r
	sp.height = r * 2.0
	sp.radial_segments = 8
	sp.rings = 4
	return sp

static func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b

# A thin strut (cylinder) spanning a -> b.
static func _bar(root: Node3D, mat: StandardMaterial3D, a: Vector3, b: Vector3, r: float) -> void:
	var d: Vector3 = b - a
	var len: float = d.length()
	if len < 1e-5:
		return
	_add(root, _cyl(r, len), mat, Transform3D(_basis_y(d), (a + b) * 0.5))

static func _add(root: Node3D, mesh: Mesh, mat: StandardMaterial3D, xf: Transform3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshUtil.flat(mesh)     # faceted, to match the ship
	mi.material_override = mat
	mi.transform = xf
	root.add_child(mi)

# Basis whose local +Y points along `dir`.
static func _basis_y(dir: Vector3) -> Basis:
	var y: Vector3 = dir.normalized()
	var ref: Vector3 = Vector3.FORWARD if absf(y.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var x: Vector3 = ref.cross(y).normalized()
	var z: Vector3 = x.cross(y).normalized()
	return Basis(x, y, z)
