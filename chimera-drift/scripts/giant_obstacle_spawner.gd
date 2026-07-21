extends Node3D

# Per-level GIANT OBSTACLE spawner (owned by LevelDirector, like PowerUpStreamer).
# Each level has a chance to contain one colossal landmark the ship must navigate
# around -- a mesa, arch, step pyramid, crater, ruins, toppled truss, giant dish,
# space debris, obelisk, ring segment or spire. Placed on/near the flight path via
# the active generator's terrain, made lethal with a trimesh body (layer 4), and
# themed to the level. Deterministic per level (same seed -> same landmark).
#
# Corridor levels are skipped (a tunnel is too tight for a giant); surface / canyon
# / pillared get GROUND landmarks; open-volume gets floating SPACE wreckage.

const GiantBuilder := preload("res://scripts/giant_builder.gd")
const Hazard := preload("res://scripts/hazard.gd")

const GIANT_CHANCE: float = 0.5
const MIN_Z: float = 44.0        # nearest a giant may sit ahead of the spawn (past the safe runway)
const MAX_Z: float = 135.0
const METAL_KINDS := ["dish", "debris", "truss", "ring"]

# Roll + place this level's giant (clears any previous one first). Called from
# LevelDirector._build_level after the active generator has started.
func build(active_generator: Node, theme: Dictionary, rolled: Dictionary) -> void:
	clear()
	var shape_family: int = rolled.get("shape_family", 0)
	if shape_family == LevelSeed.ShapeFamily.CORRIDOR:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = _seed_of(rolled)
	if rng.randf() > GIANT_CHANCE:
		return

	var space: bool = shape_family == LevelSeed.ShapeFamily.OPEN_VOLUME
	var kinds: Array = GiantBuilder.SPACE_KINDS if space else GiantBuilder.GROUND_KINDS
	var kind: String = kinds[rng.randi() % kinds.size()]
	var size: float = rng.randf_range(16.0, 32.0)
	var z: float = -rng.randf_range(MIN_Z, MAX_Z)
	var mesh: ArrayMesh = GiantBuilder.build(kind, rng, size)
	var yaw := Basis(Vector3(0, 1, 0), rng.randf() * TAU)

	var pos: Vector3
	if space:
		var dir := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		if dir.length() < 0.1:
			dir = Vector2(1, 0)
		var off: Vector2 = dir.normalized() * rng.randf_range(7.0, 16.0)
		pos = Vector3(off.x, off.y, z)
	else:
		# Ground giants sit to one side of the path; arch/crater centre so the ship
		# flies THROUGH the opening / OVER the pit.
		var offx: float = (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(4.0, 12.0)
		if kind == "arch" or kind == "crater":
			offx = rng.randf_range(-3.0, 3.0)
		pos = Vector3(offx, _ground_y(active_generator, offx, z), z)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = _giant_color(kind, theme)
	mat.roughness = 0.9
	mat.metallic = 0.4 if kind in METAL_KINDS else 0.05

	var mi := MeshInstance3D.new()
	mi.name = "Giant_" + kind
	mi.mesh = mesh
	mi.material_override = mat
	mi.transform = Transform3D(yaw, pos)
	add_child(mi)

	add_child(Hazard.trimesh_body(mesh, mi.transform))   # lethal, same transform

func clear() -> void:
	for c in get_children():
		c.queue_free()

func _ground_y(gen: Node, x: float, z: float) -> float:
	if gen != null and gen.has_method("_terrain_height"):
		return gen._terrain_height(x, z)
	return 0.0

func _giant_color(kind: String, theme: Dictionary) -> Color:
	var c: Color = theme.get("walls2", Color(0.5, 0.52, 0.56)) if kind in METAL_KINDS else theme.get("walls", Color(0.5, 0.5, 0.55))
	return c.darkened(0.1)

func _seed_of(rolled: Dictionary) -> int:
	var s: String = "%s|%s|%s|giant" % [rolled.get("shape_word", ""), rolled.get("modifier_word", ""), rolled.get("structure_type", "")]
	return abs(hash(s))
