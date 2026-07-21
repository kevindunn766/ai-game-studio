extends "res://scripts/level_surface.gd"

# PILLARED shape family -- an open plain studded with a dense field of tall vertical
# lethal pillars you slalom between, distinct from plain SURFACE. Reuses SURFACE's
# flat-ish streamed floor + all prop/enemy/mine/hazard streaming; the only change is
# that a tile's "structure features" become a CLUSTER of pillars, so the whole ground
# (in every direction, per the 2D tile grid) is a forest of columns rather than the
# ground itself being the hazard.
#
# Pillars are real CylinderMesh + trimesh bodies (lethal on the hazard layer, only on
# the tiles near the ship -- collision LOD), streamed/recycled with their terrain tile.

@export var pillars_per_tile_min: float = 1.0
@export var pillars_per_tile_max: float = 3.0
@export var pillar_radius_min_frac: float = 0.4   # × ship_visual_radius
@export var pillar_radius_max_frac: float = 0.9
@export var pillar_height_min_frac: float = 6.0
@export var pillar_height_max_frac: float = 12.0

# Replace SURFACE's structure dressing with a cluster of pillars per terrain tile, the
# count scaled by this level's rolled density/pillar_density personality.
func _scatter_tile_structures(_ix: int, _iz: int, x0: float, x1: float, z0: float, z1: float, rng: RandomNumberGenerator, near: bool, density_mult: float, out: Array) -> void:
	var thickness: float = level_state.get("pillar_density", 1.0) * level_state.get("density", 1.0)
	var n: int = int(round(rng.randf_range(pillars_per_tile_min, pillars_per_tile_max) * thickness * density_mult))
	for i in range(maxi(0, n)):
		_place_one_pillar(x0, x1, z0, z1, rng, near, out)

func _place_one_pillar(x0: float, x1: float, z0: float, z1: float, rng: RandomNumberGenerator, near: bool, out: Array) -> void:
	var sc: float = ship.ship_visual_radius
	var lane_x: float = rng.randf_range(x0, x1)
	var z: float = rng.randf_range(z0, z1)
	var gy: float = _terrain_height(lane_x, z)
	var radius: float = sc * rng.randf_range(pillar_radius_min_frac, pillar_radius_max_frac)
	var height: float = sc * rng.randf_range(pillar_height_min_frac, pillar_height_max_frac)
	var mesh: CylinderMesh = _cylinder_mesh(radius * rng.randf_range(0.7, 1.0), radius, height)  # slight taper
	var base: Color = theme.get("floor", Color(0.55, 0.55, 0.6))
	var color: Color = _jitter_color(Color(base.r * 0.8, base.g * 0.8, base.b * 0.85))
	var pos := Vector3(lane_x, gy + height * 0.5, z)
	var visual := MeshInstance3D.new()
	visual.mesh = MeshUtil.flat(mesh)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	visual.material_override = material
	visual.position = pos
	add_child(visual)
	var body: StaticBody3D = null
	if near:
		body = Hazard.trimesh_body(visual.mesh, visual.transform)
		add_child(body)
	out.append([visual, body])
