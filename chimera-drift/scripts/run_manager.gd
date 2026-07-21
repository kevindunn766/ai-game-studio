extends Node

# Owns per-RUN state -- the things that persist across deaths within a single
# run and only reset when the player returns to the menu and starts a new run.
#
# Right now that is the ship hull: it is rolled once from `hull_seed`, kept
# through every death-retry (same seed -> identical hull), and re-rolled only
# when `start_new_run()` is called. A future menu calls start_new_run(); until
# it exists, autoload._ready() rolls the first run so the game boots straight in.
#
# Seeding everything off an int also sets up shareable "daily run" seeds cheaply
# later (an open question in the design brief).

const MeshUtil := preload("res://scripts/mesh_util.gd")

signal run_started(hull_seed: int)

var hull_seed: int = 0
var run_active: bool = false

# The run's PERMANENT loadout: pieces the player kept via the between-levels draft
# (each {kind, color, effect}). Re-applied to the ship every stage (Ship.
# apply_permanent_loadout) so kept parts/upgrades persist across levels and deaths.
# Cleared only when a brand-new run starts.
var permanent_pieces: Array = []

# Per-run girder: one spec rolled from the run seed, its CSG carved + baked ONCE
# and reused for every girder instance in the run. `girder_severed` gates
# placement (a severed beam may only span a canyon/cavern with both ends buried).
var girder_spec: Dictionary = {}
var girder_mesh: Mesh = null
var girder_severed: bool = false

# Per-run vent scale (vents read a consistent size within a run).
var vent_scale: float = 1.0

func _ready() -> void:
	# Groundwork for the menu: the menu will suppress this and call
	# start_new_run() itself. With no menu yet, boot directly into a run.
	if not run_active:
		start_new_run()

func start_new_run(seed: int = -1) -> void:
	if seed < 0:
		var r := RandomNumberGenerator.new()
		r.randomize()
		hull_seed = r.randi()
	else:
		hull_seed = seed
	run_active = true
	permanent_pieces.clear()   # a fresh run starts with no kept pieces
	girder_mesh = null
	_roll_vent()
	_roll_girder()
	_bake_girder()   # async; girder_mesh is null until it completes
	run_started.emit(hull_seed)

func make_hull_rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hull_seed
	return r

# Roll the run's girder: scale, length, bend, and 1-3 bites (each sliding along
# the length + slightly off-axis). A mid-length bite wide enough to span the
# cross-section severs the beam.
func _roll_girder() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hull_seed ^ 0x5DEECE66
	var scale: float = r.randf_range(0.8, 1.5)
	var count: int = r.randi_range(1, 3)
	var bites: Array = []
	var severed := false
	for i in range(count):
		var z: float = r.randf_range(0.15, 1.0)
		var r_frac: float = r.randf_range(0.16, 0.44)   # radius as a fraction of scale
		var offset := Vector2(r.randf_range(-0.18, 0.18), r.randf_range(-0.12, 0.12)) * scale
		bites.append({"z": z, "offset": offset, "radius": r_frac * scale})
		# Cross-section half-extent is ~0.34*scale; a mid-length bite that wide cuts through.
		if z > 0.3 and z < 0.85 and r_frac >= 0.34:
			severed = true
	girder_spec = {
		"scale": scale,
		"length_mult": r.randf_range(0.9, 1.6),
		"bend": (r.randf_range(0.18, 0.42) if r.randf() < 0.4 else 0.0),
		"bites": bites,
	}
	girder_severed = severed

# Roll the run's vent size. Seeded off its own constant so it is independent of
# the girder roll (adding/removing girder rolls won't shift the vent size).
func _roll_vent() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hull_seed ^ 0x1F123BB5
	vent_scale = r.randf_range(0.7, 1.5)

func _bake_girder() -> void:
	var combiner: CSGCombiner3D = LevelGeo.build_girder_csg(girder_spec.scale, girder_spec.length_mult, girder_spec.bites)
	add_child(combiner)
	await get_tree().process_frame
	await get_tree().process_frame
	var meshes: Array = combiner.get_meshes()
	var baked: Mesh = meshes[1] if meshes.size() >= 2 else null
	combiner.queue_free()
	if baked != null and girder_spec.bend > 0.0:
		baked = _bend_mesh(baked, girder_spec.bend, LevelGeo.girder_length(girder_spec.scale, girder_spec.length_mult))
	# CSG bake is smooth-shaded -> flatten for the faceted look.
	girder_mesh = MeshUtil.flat(baked) if baked != null else null

# Post-bake bend: bow the beam in X along its length (peak at the middle).
func _bend_mesh(mesh: Mesh, bend: float, length: float) -> Mesh:
	if mesh.get_surface_count() == 0:
		return mesh
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in range(verts.size()):
		var v: Vector3 = verts[i]
		var t: float = clampf(-v.z / length, 0.0, 1.0)   # 0 start .. 1 far end
		v.x += bend * length * 0.5 * sin(PI * t)
		verts[i] = v
	arrays[Mesh.ARRAY_VERTEX] = verts
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out
