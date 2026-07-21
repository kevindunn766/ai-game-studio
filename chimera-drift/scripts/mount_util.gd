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

# Outward face normal per mount, aligned index-for-index with positions_centered().
# RATIONAL PLACEMENT: parts fill in this order, so the ones you get first sit in the
# most natural, balanced spots -- and there is NO forward/nose mount (a part there
# just juts off the point of the ship). Centre-line spots come first (a lone part
# stays symmetric); the wing PAIR fills last.
const DIRECTIONS := [
	Vector3(0, 1, 0),    # 0 dorsal, forward   (top spine)
	Vector3(0, -1, 0),   # 1 ventral           (belly)
	Vector3(0, 1, 0),    # 2 dorsal, aft        (top spine, rear)
	Vector3(0, 0, 1),    # 3 tail pod           (rear, above the nozzle)
	Vector3(-1, 0, 0),   # 4 left wing
	Vector3(1, 0, 0),    # 5 right wing
]

const INSET := 0.14      # fraction of the half-extent to pull each mount inward

# Mount positions RELATIVE TO THE HULL CENTRE (so a centred showcase hull uses them
# directly; the gameplay hull adds centre()). Positions are derived per-hull from the
# AABB so they snug on wide deltas and slim shafts alike, and are placed on natural
# ship features (spine / belly / flanks / tail) rather than raw face centres.
static func positions_centered(aabb: AABB, scale: float) -> Array:
	var h: Vector3 = aabb.size * 0.5 * scale
	var i: Vector3 = h * INSET
	return [
		Vector3(0.0, h.y - i.y, -0.12 * h.z),        # dorsal, just forward of centre
		Vector3(0.0, -h.y + i.y, 0.05 * h.z),        # ventral, near centre
		Vector3(0.0, h.y - i.y, 0.34 * h.z),         # dorsal, rear third
		Vector3(0.0, 0.28 * h.y, h.z - i.z),         # tail pod, lifted above the nozzle
		Vector3(-h.x + i.x, 0.02 * h.y, 0.12 * h.z), # left wing, slightly back
		Vector3(h.x - i.x, 0.02 * h.y, 0.12 * h.z),  # right wing, slightly back
	]

# The hull's geometric centre in scaled local space (offset for a non-centred hull).
static func center(aabb: AABB, scale: float) -> Vector3:
	return (aabb.position + aabb.size * 0.5) * scale
