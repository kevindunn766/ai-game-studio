extends RefCounted

# Procedural GIANT LANDMARK obstacles for levels: mesas, step pyramids, stone
# arches, crater rims, jagged ruins, toppled trusses, giant satellite dishes,
# space debris, obelisks, broken ring segments, colossal spires. Each is composed
# from low-poly primitives merged into ONE flat-shaded ArrayMesh (via
# SurfaceTool.append_from), so a single trimesh CollisionShape can make the whole
# thing lethal (concave shapes -- arch openings, crater centres -- work fine).
#
# Modeled base-at-origin, growing +Y (horizontal forms centred on y). `size` is
# the landmark's characteristic extent in world units (giants: ~14-34). The
# spawner colours + places them. No class_name (headless-safe -- preload const).

const MeshUtil := preload("res://scripts/mesh_util.gd")

const GROUND_KINDS := ["mesa", "pyramid", "arch", "crater", "ruins", "truss", "dish", "obelisk", "spire"]
const SPACE_KINDS := ["debris", "dish", "ruins", "truss", "obelisk", "ring", "spire"]

static func build(kind: String, rng: RandomNumberGenerator, size: float) -> ArrayMesh:
	match kind:
		"mesa": return _mesa(rng, size)
		"pyramid": return _pyramid(rng, size)
		"arch": return _arch(rng, size)
		"crater": return _crater(rng, size)
		"ruins": return _ruins(rng, size)
		"truss": return _truss(rng, size)
		"dish": return _dish(rng, size)
		"debris": return _debris(rng, size)
		"obelisk": return _obelisk(rng, size)
		"ring": return _ring(rng, size)
		"spire": return _spire(rng, size)
		_: return _mesa(rng, size)

# --- landmarks --------------------------------------------------------------
static func _mesa(rng: RandomNumberGenerator, size: float) -> ArrayMesh:
	var st := _begin()
	var r: float = size * 0.5
	var h: float = size * rng.randf_range(0.7, 1.2)
	_add(st, _cyl(r * rng.randf_range(0.7, 0.85), r, h, rng.randi_range(6, 9)), _t(Vector3(0, h * 0.5, 0)))
	var r2: float = r * rng.randf_range(0.5, 0.72)
	var h2: float = h * rng.randf_range(0.35, 0.6)
	var ox: float = rng.randf_range(-0.2, 0.2) * r
	_add(st, _cyl(r2 * 0.7, r2, h2, rng.randi_range(6, 8)), _t(Vector3(ox, h + h2 * 0.5, ox * 0.5)))
	return _finish(st)

static func _pyramid(rng: RandomNumberGenerator, size: float) -> ArrayMesh:
	var st := _begin()
	var tiers: int = rng.randi_range(4, 6)
	var base: float = size
	var th: float = size * rng.randf_range(0.7, 1.0) / float(tiers)
	var y: float = 0.0
	for i in range(tiers):
		var f: float = 1.0 - float(i) / float(tiers + 1)
		var w: float = base * f
		_add(st, _box(w, th, w), _t(Vector3(0, y + th * 0.5, 0)))
		y += th
	return _finish(st)

static func _arch(rng: RandomNumberGenerator, size: float) -> ArrayMesh:
	var st := _begin()
	var w: float = size * rng.randf_range(0.3, 0.4)     # half opening width
	var lt: float = size * rng.randf_range(0.1, 0.15)   # leg thickness
	var lh: float = size * rng.randf_range(0.45, 0.7)   # leg height
	var depth: float = lt * 1.5
	_add(st, _box(lt, lh, depth), _t(Vector3(-w, lh * 0.5, 0)))
	_add(st, _box(lt, lh, depth), _t(Vector3(w, lh * 0.5, 0)))
	var segs: int = 9
	var rise: float = size * rng.randf_range(0.28, 0.42)
	for i in range(segs):
		var a: float = PI * (float(i) + 0.5) / float(segs)   # 0..PI over the arc
		var cx: float = -cos(a) * w
		var cy: float = lh + sin(a) * rise
		var seg := _box(lt * 1.05, lt * 1.05, depth)
		_add(st, seg, Transform3D(Basis(Vector3(0, 0, 1), a - PI * 0.5), Vector3(cx, cy, 0)))
	return _finish(st)

static func _crater(rng: RandomNumberGenerator, size: float) -> ArrayMesh:
	var st := _begin()
	# Raised rim = a lumpy ring of blocks around a central pit; fly over/around it.
	var outer: float = size * 0.5
	var blocks: int = rng.randi_range(12, 18)
	for i in range(blocks):
		var a: float = TAU * float(i) / float(blocks)
		var rr: float = outer * rng.randf_range(0.86, 1.0)
		var bh: float = size * rng.randf_range(0.12, 0.28)
		var bw: float = outer * rng.randf_range(0.28, 0.42)
		var b := _box(bw, bh, bw)
		_add(st, b, Transform3D(Basis(Vector3(0, 1, 0), a), Vector3(cos(a) * rr, bh * 0.5, sin(a) * rr)))
	return _finish(st)

static func _ruins(rng: RandomNumberGenerator, size: float) -> ArrayMesh:
	var st := _begin()
	var span: float = size * 0.45
	var walls: int = rng.randi_range(5, 9)
	for i in range(walls):
		var a: float = TAU * float(i) / float(walls) + rng.randf_range(-0.3, 0.3)
		var rr: float = span * rng.randf_range(0.7, 1.0)
		var wh: float = size * rng.randf_range(0.25, 0.75)      # broken -> varied heights
		var ww: float = size * rng.randf_range(0.14, 0.3)
		var wt: float = size * rng.randf_range(0.05, 0.1)
		var tilt: float = rng.randf_range(-0.18, 0.18)
		var basis := Basis(Vector3(0, 1, 0), a) * Basis(Vector3(0, 0, 1), tilt)
		_add(st, _box(ww, wh, wt), Transform3D(basis, Vector3(cos(a) * rr, wh * 0.5, sin(a) * rr)))
	# rubble
	for _j in range(rng.randi_range(4, 8)):
		var rs: float = size * rng.randf_range(0.05, 0.13)
		var rp := Vector3(rng.randf_range(-span, span), rs * 0.5, rng.randf_range(-span, span))
		_add(st, _box(rs, rs, rs), Transform3D(Basis(Vector3(0, 1, 0), rng.randf() * TAU), rp))
	return _finish(st)

static func _truss(rng: RandomNumberGenerator, size: float) -> ArrayMesh:
	var st := _begin()
	# A long lattice lying at a shallow angle (one end on the ground, one raised).
	var length: float = size * rng.randf_range(1.1, 1.7)
	var w: float = size * rng.randf_range(0.1, 0.16)
	var r: float = size * 0.02
	var tilt: float = rng.randf_range(0.1, 0.35)
	var basis := Basis(Vector3(0, 0, 1), tilt)
	# four rails along X (rotated by tilt), with rungs + diagonals
	var corners := [Vector3(0, -w, -w), Vector3(0, w, -w), Vector3(0, w, w), Vector3(0, -w, w)]
	for c in corners:
		_bar(st, c + Vector3(-length * 0.5, 0, 0), c + Vector3(length * 0.5, 0, 0), r, basis)
	var rungs: int = int(length / (w * 1.6))
	for i in range(rungs + 1):
		var x: float = lerp(-length * 0.5, length * 0.5, float(i) / float(maxi(rungs, 1)))
		for k in range(4):
			var a: Vector3 = corners[k] + Vector3(x, 0, 0)
			var b: Vector3 = corners[(k + 1) % 4] + Vector3(x, 0, 0)
			_bar(st, a, b, r * 0.8, basis)
	return _finish(st)

static func _dish(rng: RandomNumberGenerator, size: float) -> ArrayMesh:
	var st := _begin()
	var mast_h: float = size * rng.randf_range(0.35, 0.5)
	var base_w: float = size * 0.18
	# tripod / lattice base
	for i in range(3):
		var a: float = TAU * float(i) / 3.0
		_bar(st, Vector3(cos(a), 0, sin(a)) * base_w, Vector3(0, mast_h * 0.8, 0), size * 0.02, Basis())
	_add(st, _cyl(size * 0.05, size * 0.05, mast_h, 8), _t(Vector3(0, mast_h * 0.5, 0)))
	# big dish cup, tilted skyward
	var dia: float = size * rng.randf_range(0.34, 0.5)
	var tb := Basis(Vector3(1, 0, 0), -deg_to_rad(rng.randf_range(25.0, 55.0)))
	_add(st, _cyl(dia, dia * 0.12, size * 0.1, 14), Transform3D(tb, Vector3(0, mast_h, 0)))
	var axis: Vector3 = tb * Vector3(0, 1, 0)
	_add(st, _cyl(size * 0.012, size * 0.012, size * 0.22, 6), Transform3D(_basis_y(axis), Vector3(0, mast_h, 0) + axis * size * 0.11))
	return _finish(st)

static func _debris(rng: RandomNumberGenerator, size: float) -> ArrayMesh:
	var st := _begin()
	var chunks: int = rng.randi_range(6, 11)
	for _i in range(chunks):
		var s := Vector3(rng.randf_range(0.15, 0.5), rng.randf_range(0.1, 0.35), rng.randf_range(0.2, 0.6)) * size
		var p := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * size * 0.4
		var av := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		if av.length() < 0.1:
			av = Vector3.UP
		var basis := Basis(av.normalized(), rng.randf() * TAU)
		if rng.randf() < 0.35:
			_add(st, _prism(s.x, s.y, s.z), Transform3D(basis, p))
		else:
			_add(st, _box(s.x, s.y, s.z), Transform3D(basis, p))
	# a couple of bent beams
	for _j in range(rng.randi_range(2, 4)):
		var a := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * size * 0.4
		var b := a + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * size * 0.5
		_bar(st, a, b, size * 0.025, Basis())
	return _finish(st)

static func _obelisk(rng: RandomNumberGenerator, size: float) -> ArrayMesh:
	var st := _begin()
	var h: float = size * rng.randf_range(1.0, 1.5)
	var r: float = size * rng.randf_range(0.12, 0.2)
	_add(st, _cyl(r * 0.45, r, h, 4), _t(Vector3(0, h * 0.5, 0)))
	_add(st, _cyl(0.0, r * 0.45, h * 0.14, 4), _t(Vector3(0, h + h * 0.07, 0)))   # pyramidal cap
	return _finish(st)

static func _ring(rng: RandomNumberGenerator, size: float) -> ArrayMesh:
	var st := _begin()
	# A broken segment of a colossal ring/orbital -- an arc of thick blocks.
	var radius: float = size * 0.9
	var arc: float = rng.randf_range(1.0, 2.0)     # radians of arc present
	var segs: int = int(arc / 0.22)
	var start: float = rng.randf() * TAU
	var th: float = size * 0.12
	for i in range(segs):
		var a: float = start + arc * float(i) / float(maxi(segs, 1))
		var cx: float = cos(a) * radius
		var cy: float = sin(a) * radius
		var basis := Basis(Vector3(0, 0, 1), a)
		_add(st, _box(size * 0.14, th, size * 0.34), Transform3D(basis, Vector3(cx, cy, 0)))
	return _finish(st)

static func _spire(rng: RandomNumberGenerator, size: float) -> ArrayMesh:
	var st := _begin()
	var n: int = rng.randi_range(1, 3)
	for i in range(n):
		var h: float = size * rng.randf_range(0.8, 1.4) * (1.0 - 0.18 * float(i))
		var r: float = size * rng.randf_range(0.08, 0.16)
		var p := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25)) * size
		var lean := Basis(Vector3(0, 0, 1), rng.randf_range(-0.12, 0.12))
		_add(st, _cyl(0.0, r, h, rng.randi_range(5, 7)), Transform3D(lean, p + Vector3(0, h * 0.5, 0)))
	return _finish(st)

# --- primitive + composition helpers ---------------------------------------
static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

static func _finish(st: SurfaceTool) -> ArrayMesh:
	return MeshUtil.flat(st.commit())

static func _add(st: SurfaceTool, mesh: Mesh, xf: Transform3D) -> void:
	st.append_from(mesh, 0, xf)

# A thick strut (cylinder) spanning a -> b, optionally pre-rotated by `basis`.
static func _bar(st: SurfaceTool, a: Vector3, b: Vector3, r: float, basis: Basis) -> void:
	var a2: Vector3 = basis * a
	var b2: Vector3 = basis * b
	var d: Vector3 = b2 - a2
	if d.length() < 1e-5:
		return
	_add(st, _cyl(r, r, d.length(), 6), Transform3D(_basis_y(d), (a2 + b2) * 0.5))

static func _box(x: float, y: float, z: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(x, y, z)
	return b

static func _prism(x: float, y: float, z: float) -> PrismMesh:
	var p := PrismMesh.new()
	p.size = Vector3(x, y, z)
	return p

static func _cyl(rt: float, rb: float, h: float, sides: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = sides
	c.rings = 1
	return c

static func _t(pos: Vector3) -> Transform3D:
	return Transform3D(Basis(), pos)

static func _basis_y(dir: Vector3) -> Basis:
	var y: Vector3 = dir.normalized()
	var ref: Vector3 = Vector3.FORWARD if absf(y.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var x: Vector3 = ref.cross(y).normalized()
	var z: Vector3 = x.cross(y).normalized()
	return Basis(x, y, z)
