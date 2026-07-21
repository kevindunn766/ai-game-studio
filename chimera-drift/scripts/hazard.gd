extends RefCounted

# Shared hazard-collision builder. Project rule (Kevin, 2026-07-17): every SOLID
# item's collision is a TRIMESH built from that item's own visual mesh -- never a
# box/sphere/cylinder or convex-hull approximation -- so what you see is exactly
# what you crash into. Trimesh (ConcavePolygonShape3D) vs. the ship's HazardDetector
# Area3D is already proven in this project (streamed terrain, holed asteroids).
#
# Exemptions (handled by their callers, NOT here): foliage + fronds are pass-through
# decoration (no collision); the ship's own hitbox is a deliberate forgiveness box;
# meteorites are dynamic RigidBody3Ds, which Godot forbids from using concave shapes.

const HAZARD_LAYER: int = 4

# StaticBody3D whose collision is the trimesh of `mesh`, placed at `xform` (the
# same transform as the visual, so collision and visual coincide exactly).
static func trimesh_body(mesh: Mesh, xform: Transform3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = HAZARD_LAYER
	body.collision_mask = 0
	body.transform = xform
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	return body

# Trimesh CollisionShape3D for a body that moves/pulses (enemies). Returned bare so
# the caller can add it to its AnimatableBody3D and scale the node to animate size.
static func trimesh_shape(mesh: Mesh) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	return cs
