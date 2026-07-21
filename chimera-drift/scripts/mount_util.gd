extends RefCounted

# Snug attachment mount points on a hull, shared by the gameplay ship (grow_ship)
# and the beauty-shot showcase (attach_loadout) so parts sit IDENTICALLY in both.
#
# The 6 mounts are the face-centres of the hull's AABB (front/rear/left/right/
# top/bottom), pulled slightly INWARD so an attached part's base embeds in the
# surface instead of floating off it -- and derived per-hull, so it snugs on wide
# deltas and slim shafts alike (a fixed offset can't). Outward orientation is the
# canonical face normal (independent of the hull's centre offset).
#
# No class_name (headless-safe -- referenced via preload const).

# Face normals, in mount order.
const DIRECTIONS := [
	Vector3(0, 0, -1),   # front
	Vector3(0, 0, 1),    # rear
	Vector3(-1, 0, 0),   # left
	Vector3(1, 0, 0),    # right
	Vector3(0, 1, 0),    # top
	Vector3(0, -1, 0),   # bottom
]

const INSET := 0.14      # fraction of the half-extent to pull each mount inward

# Mount positions RELATIVE TO THE HULL CENTRE (so a centred showcase hull uses
# them directly; the gameplay hull adds centre()).
static func positions_centered(aabb: AABB, scale: float) -> Array:
	var h: Vector3 = aabb.size * 0.5 * scale
	var inset: Vector3 = h * INSET
	return [
		Vector3(0.0, 0.0, -h.z + inset.z),
		Vector3(0.0, 0.0, h.z - inset.z),
		Vector3(-h.x + inset.x, 0.0, 0.0),
		Vector3(h.x - inset.x, 0.0, 0.0),
		Vector3(0.0, h.y - inset.y, 0.0),
		Vector3(0.0, -h.y + inset.y, 0.0),
	]

# The hull's geometric centre in scaled local space (offset for a non-centred hull).
static func center(aabb: AABB, scale: float) -> Vector3:
	return (aabb.position + aabb.size * 0.5) * scale
