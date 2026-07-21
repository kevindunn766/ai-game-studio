extends "res://scripts/enemy_base.gd"

# DUMB flying enemy: a bright, radial structure built from the level's own feature
# objects -- e.g. a ring of mushrooms linked together at their bases (design
# brief, Kevin). Constructed per-level from whatever feature words rolled, so a
# mushroom level's swarmers are mushroom-rings, a crystal level's are crystal-
# rings, etc. Movement is dumb by design: it spins in place and drifts on a lazy
# sine while the world scrolls it past the player, and MAY pop off the odd shot.
# Killing one drops a TEMPORARY shooting upgrade (single -> double -> triple ->
# spread) -- wired in EnemySpawner as drop_effect = "weapon_up".

const MeshUtil := preload("res://scripts/mesh_util.gd")

# Assigned by the spawner.
var feature_shape: String = "mushroom"   # which level object the ring is made of
var shoots: bool = false

var _spin_speed: float = 1.2
var _spin: float = 0.0
var _bob_axis_x: bool = true
var _bob_amp: float = 0.0
var _bob_speed: float = 1.0
var _bob_phase: float = 0.0
var _origin: Vector3 = Vector3.ZERO
var _petal_count: int = 7
var _ring_radius: float = 1.6
var _fire_cd: float = 1.0

# Randomly-added build variety, rolled per enemy.
const ALT_SHAPES := ["mushroom", "crystal", "blob", "frond", "girder", "vent"]
var _mix_shapes: bool = false      # petals occasionally use a different shape
var _second_ring: bool = false     # an extra inner ring of smaller petals
var _hub_style: int = 0            # 0 torus, 1 sphere cluster, 2 spiky core

func _hurt_radius() -> float:
	# Covers the ring's outer reach so shots/contact register on the whole flower.
	return _ring_radius + enemy_scale * 0.5

func _wants_trail() -> bool:
	return true

func _ready() -> void:
	_ring_radius = enemy_scale * randf_range(1.2, 2.1)
	_petal_count = randi_range(5, 11)
	super._ready()

	_spin_speed = randf_range(0.7, 1.8) * (1.0 if randf() < 0.5 else -1.0)
	_bob_axis_x = randf() < 0.5
	_bob_amp = enemy_scale * randf_range(0.6, 1.4)
	_bob_speed = randf_range(0.8, 1.6)
	_bob_phase = randf_range(0.0, TAU)
	fire_interval = randf_range(1.4, 2.6)
	shot_damage = 6.0

	# Randomly-rolled build modifiers -> no two swarmers build the same.
	_mix_shapes = randf() < 0.45
	_second_ring = randf() < 0.4
	_hub_style = randi() % 3

	_build_ring()
	# A random resting tilt so the flowers don't all face flat-on (spin is z-only, so
	# these x/y tilts persist).
	rotation.x = randf_range(-0.35, 0.35)
	rotation.y = randf_range(-0.35, 0.35)

func post_spawn() -> void:
	# Called by the spawner after position is set, so the bob oscillates around the
	# spawn point rather than drifting away from it.
	_origin = position

func _build_ring() -> void:
	var base_bright: Color = accent.lightened(0.35)
	base_bright.s = clampf(base_bright.s * 1.15, 0.0, 1.0)
	var hub_r: float = _ring_radius * 0.5
	_build_hub(base_bright, hub_r)
	_ring_of_petals(_petal_count, hub_r, base_bright, 1.0, 0.0)
	if _second_ring:
		var inner_count: int = maxi(3, int(round(_petal_count * randf_range(0.4, 0.7))))
		var inner_r: float = hub_r * randf_range(0.5, 0.75)
		_ring_of_petals(inner_count, inner_r, base_bright, randf_range(0.55, 0.8), randf_range(0.0, TAU))

# The central hub the petals link onto -- one of three random styles.
func _build_hub(base: Color, hub_r: float) -> void:
	var mat := _petal_material(base)
	match _hub_style:
		1:   # cluster of small spheres
			var n: int = randi_range(4, 7)
			for i in range(n):
				var a: float = TAU * float(i) / float(n)
				var sph := SphereMesh.new()
				sph.radius = hub_r * 0.32
				sph.height = hub_r * 0.64
				_part(self, sph, _petal_material(_jitter_color(base)), Vector3(cos(a) * hub_r * 0.42, sin(a) * hub_r * 0.42, 0))
			var c := SphereMesh.new()
			c.radius = hub_r * 0.4
			c.height = hub_r * 0.8
			_part(self, c, mat, Vector3.ZERO)
		2:   # spiky core
			var core := SphereMesh.new()
			core.radius = hub_r * 0.55
			core.height = hub_r * 1.1
			_part(self, core, mat, Vector3.ZERO)
			var m: int = randi_range(5, 8)
			for i in range(m):
				var a2: float = TAU * float(i) / float(m)
				var spike := CylinderMesh.new()
				spike.top_radius = 0.0
				spike.bottom_radius = hub_r * 0.1
				spike.height = hub_r * 0.9
				var node := Node3D.new()
				add_child(node)
				_orient_y(node, Vector3(cos(a2), sin(a2), randf_range(-0.3, 0.3)))
				_part(node, spike, mat, Vector3(0, hub_r * 0.45, 0))
		_:   # torus + core (the classic ring)
			var torus := TorusMesh.new()
			torus.inner_radius = hub_r * 0.72
			torus.outer_radius = hub_r
			var hub := MeshInstance3D.new()
			hub.mesh = MeshUtil.flat(torus)
			hub.material_override = mat
			hub.rotation = Vector3(deg_to_rad(90), 0, 0)
			add_child(hub)
			var core2 := SphereMesh.new()
			core2.radius = hub_r * 0.5
			core2.height = hub_r
			_part(self, core2, mat, Vector3.ZERO)

# A ring of petals, each with its own jittered colour / size / radius / out-of-plane
# tilt, and (when mixing is on) an occasional different shape.
func _ring_of_petals(count: int, radius: float, base: Color, scale_mult: float, phase: float) -> void:
	for i in range(count):
		var ang: float = TAU * float(i) / float(count) + phase + randf_range(-0.12, 0.12)
		var outward := Vector3(cos(ang), sin(ang), randf_range(-0.15, 0.15)).normalized()
		var shape: String = feature_shape
		if _mix_shapes and randf() < 0.4:
			shape = ALT_SHAPES[randi() % ALT_SHAPES.size()]
		var petal := _build_feature(_petal_material(_jitter_color(base)), shape, scale_mult)
		_orient_y(petal, outward)
		petal.position = outward * radius * randf_range(0.88, 1.18)
		add_child(petal)

func _jitter_color(c: Color) -> Color:
	var h: float = fposmod(c.h + randf_range(-0.05, 0.05), 1.0)
	var sat: float = clampf(c.s * randf_range(0.85, 1.1), 0.0, 1.0)
	var v: float = clampf(c.v * randf_range(0.85, 1.15), 0.15, 1.0)
	return Color.from_hsv(h, sat, v)

func _petal_material(col: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 0.55
	mat.metallic = 0.1
	mat.roughness = 0.5
	return mat

# One feature "object" modeled growing along +Y (base at origin). Grey-box
# primitives only -- correct built-in winding, then flat-shaded to match the game.
func _build_feature(mat: StandardMaterial3D, shape: String, scale_mult: float) -> Node3D:
	var root := Node3D.new()
	var s: float = enemy_scale * randf_range(0.5, 0.85) * scale_mult
	match shape:
		"mushroom":
			_part(root, _cyl(0.12 * s, 0.7 * s), mat, Vector3(0, 0.35 * s, 0))
			var cap := SphereMesh.new()
			cap.radius = 0.34 * s
			cap.height = 0.42 * s
			_part(root, cap, mat, Vector3(0, 0.78 * s, 0))
		"crystal", "spire":
			var prism := PrismMesh.new()
			prism.size = Vector3(0.34 * s, 1.0 * s, 0.34 * s)
			_part(root, prism, mat, Vector3(0, 0.5 * s, 0))
		"girder", "vent":
			var box := BoxMesh.new()
			box.size = Vector3(0.28 * s, 0.9 * s, 0.28 * s)
			_part(root, box, mat, Vector3(0, 0.45 * s, 0))
		"frond":
			_part(root, _cyl(0.07 * s, 0.9 * s), mat, Vector3(0, 0.45 * s, 0))
			var tip := SphereMesh.new()
			tip.radius = 0.18 * s
			tip.height = 0.3 * s
			_part(root, tip, mat, Vector3(0, 0.95 * s, 0))
		_:   # blob / rock / anything else -> a bulbous nub
			var blob := SphereMesh.new()
			blob.radius = 0.42 * s
			blob.height = 0.9 * s
			_part(root, blob, mat, Vector3(0, 0.45 * s, 0))
	return root

func _part(root: Node3D, mesh: Mesh, mat: StandardMaterial3D, at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshUtil.flat(mesh)
	mi.material_override = mat
	mi.position = at
	root.add_child(mi)

func _cyl(radius: float, height: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	return c

# Point a node's local +Y along `outward` (stable basis, near-vertical fallback --
# same idiom as AttachmentBuilder._orient).
func _orient_y(node: Node3D, outward: Vector3) -> void:
	if outward.length() < 0.001:
		return
	var y_axis := outward.normalized()
	var ref := Vector3.FORWARD if absf(y_axis.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var x_axis := ref.cross(y_axis).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	node.basis = Basis(x_axis, y_axis, z_axis)

func _process(delta: float) -> void:
	if not alive:
		return
	_spin += _spin_speed * delta
	rotation.z = _spin                 # spin the flower (hurtbox sphere is spin-invariant)

	_bob_phase += _bob_speed * delta
	var offset: float = sin(_bob_phase) * _bob_amp
	if _bob_axis_x:
		position.x = _origin.x + offset
	else:
		position.y = _origin.y + offset

	if shoots:
		_fire_cd -= delta
		if _fire_cd <= 0.0 and _player_in_range():
			_fire_at_player(0.09)
			_fire_cd = fire_interval
