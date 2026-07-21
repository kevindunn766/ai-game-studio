extends RefCounted

# Builds the greeble that snaps onto a filled ship mount when a power-up is
# collected. One function, many silhouettes -- this is the cheap "tons of visual
# variety" lever from the design brief: a handful of primitive-based shape kinds
# x the per-level themed color = an emergent, one-of-a-kind ship by end of run.
#
# Grey-box discipline (Governing Rule 2): every part is a Godot PRIMITIVE mesh
# (Box/Cylinder/Sphere/Prism/Torus), which carry correct built-in winding/normals
# -- no custom meshing here, so the mesh-winding rule in CLAUDE.md doesn't apply.
#
# Convention: each kind is modeled growing along +Y (base at the mount origin,
# body extending outward). build() reorients that +Y to the mount's outward
# direction so attachments splay away from the hull instead of all pointing up.

const KIND_COSMETIC := ["fin", "pod", "spar", "vent", "plate"]
const MeshUtil := preload("res://scripts/mesh_util.gd")

# kind      -> shape drawn; effect pickups map to a legible kind:
#   speed_boost -> "barrel" (a thruster/emitter nozzle)
#   magnet      -> "dome"   (a dish)
# cosmetic pickups roll one of KIND_COSMETIC.
static func build(kind: String, color: Color, s: float, outward: Vector3) -> Node3D:
	var root := Node3D.new()
	_orient(root, outward)
	var mat := _material(color)

	match kind:
		"barrel":
			_add(root, _cylinder(0.18 * s, 0.9 * s), mat, Vector3(0, 0.45 * s, 0))
			_add(root, _cylinder(0.26 * s, 0.16 * s), mat, Vector3(0, 0.9 * s, 0))   # muzzle ring
		"dome":
			var dish := SphereMesh.new()
			dish.radius = 0.42 * s
			dish.height = 0.5 * s
			_add(root, dish, mat, Vector3(0, 0.28 * s, 0))
			_add(root, _cylinder(0.1 * s, 0.28 * s), mat, Vector3(0, 0.14 * s, 0))    # stalk
		"fin":
			var blade := PrismMesh.new()
			blade.size = Vector3(0.12 * s, 0.95 * s, 0.7 * s)
			_add(root, blade, mat, Vector3(0, 0.48 * s, 0))
		"pod":
			_add(root, _cylinder(0.16 * s, 0.3 * s), mat, Vector3(0, 0.15 * s, 0))    # pylon
			var pod := SphereMesh.new()
			pod.radius = 0.34 * s
			pod.height = 0.85 * s
			_add(root, pod, mat, Vector3(0, 0.6 * s, 0))
		"spar":
			_add(root, _cylinder(0.07 * s, 1.15 * s), mat, Vector3(0, 0.57 * s, 0))
			var tip := SphereMesh.new()
			tip.radius = 0.12 * s
			tip.height = 0.24 * s
			_add(root, tip, mat, Vector3(0, 1.15 * s, 0))
		"vent":
			_add(root, _cylinder(0.36 * s, 0.28 * s), mat, Vector3(0, 0.14 * s, 0))
			_add(root, _cylinder(0.22 * s, 0.22 * s), mat, Vector3(0, 0.36 * s, 0))
		"plate":
			var plate := BoxMesh.new()
			plate.size = Vector3(0.85 * s, 0.2 * s, 0.72 * s)
			_add(root, plate, mat, Vector3(0, 0.1 * s, 0))
		_:
			var b := BoxMesh.new()
			b.size = Vector3.ONE * 0.5 * s
			_add(root, b, mat, Vector3(0, 0.25 * s, 0))
	return root

static func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.2
	mat.roughness = 0.6
	return mat

static func _cylinder(radius: float, height: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	return c

static func _add(root: Node3D, mesh: Mesh, mat: StandardMaterial3D, at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshUtil.flat(mesh)   # flat-shaded (no smooth normals)
	mi.material_override = mat
	mi.position = at
	root.add_child(mi)

# Reorient the greeble so its local +Y points along `outward` (the mount's
# direction away from the hull center). Builds a stable 3-axis basis with a
# fallback reference when outward is near-vertical (avoids the degenerate
# shortest-arc case that has bitten this repo before).
static func _orient(root: Node3D, outward: Vector3) -> void:
	if outward.length() < 0.001:
		return
	var y_axis := outward.normalized()
	var ref := Vector3.FORWARD if absf(y_axis.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var x_axis := ref.cross(y_axis).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	root.basis = Basis(x_axis, y_axis, z_axis)
