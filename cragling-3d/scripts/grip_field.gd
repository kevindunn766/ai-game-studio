class_name GripField
extends Node3D

# Scatters grip points across the +Z face of a box-shaped wall this node is
# parented to (local origin assumed centered on the wall, matching the
# wall's own CollisionShape3D).
#
# Generation is dart-throwing Poisson-disc sampling (random candidate,
# reject if closer than min_distance to any already-accepted point,
# repeat up to max_attempts) rather than the earlier grid+jitter approach
# -- this guarantees no two handholds ever land closer than min_distance,
# instead of only "usually" being spaced out.
#
# A fraction of grips are tagged crumbling: they survive a limited number
# of climbed-onto uses (see consume_grip, called by Climber once a limb
# actually lands) before breaking away for good -- the first procedurally
# generated obstacle type, per the design brief's Build Milestones.

@export var wall_width: float = 14.0
@export var wall_height: float = 40.0
@export var wall_depth: float = 1.0
@export var min_distance: float = 0.55
@export var max_attempts: int = 14000
@export var crumble_chance: float = 0.16
@export var crumble_uses: int = 2
@export var rng_seed: int = 1337

var grips: Array = [] # each: {id, pos, normal, crumbling, uses_left}

var _markers: Dictionary = {} # id -> MeshInstance3D
var _mat_normal: StandardMaterial3D
var _mat_crumble: StandardMaterial3D
var _mesh_normal: SphereMesh
var _mesh_crumble: SphereMesh
var _next_id: int = 0


func _ready() -> void:
	_generate()


func _generate() -> void:
	grips.clear()
	_markers.clear()
	_next_id = 0
	for c in get_children():
		c.queue_free()

	_mat_normal = StandardMaterial3D.new()
	_mat_normal.albedo_color = Color(0.78, 0.78, 0.78)

	_mat_crumble = StandardMaterial3D.new()
	_mat_crumble.albedo_color = Color(0.8, 0.35, 0.18)

	_mesh_normal = SphereMesh.new()
	_mesh_normal.radius = 0.09
	_mesh_normal.height = 0.18
	_mesh_normal.radial_segments = 8
	_mesh_normal.rings = 4

	_mesh_crumble = SphereMesh.new()
	_mesh_crumble.radius = 0.1
	_mesh_crumble.height = 0.2
	_mesh_crumble.radial_segments = 8
	_mesh_crumble.rings = 4

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	var global_normal: Vector3 = (global_transform.basis * Vector3(0, 0, 1)).normalized()
	for local_pos in _poisson_points(rng):
		var global_pos: Vector3 = global_transform * local_pos
		var is_crumbling := rng.randf() < crumble_chance
		var id := _next_id
		_next_id += 1
		grips.append({
			"id": id,
			"pos": global_pos,
			"normal": global_normal,
			"crumbling": is_crumbling,
			"uses_left": crumble_uses if is_crumbling else -1,
		})
		_spawn_marker(id, local_pos, is_crumbling)


func _poisson_points(rng: RandomNumberGenerator) -> Array:
	var accepted: Array = []
	var half_w := wall_width * 0.5
	var half_h := wall_height * 0.5
	for i in range(max_attempts):
		var candidate := Vector3(rng.randf_range(-half_w, half_w), rng.randf_range(-half_h, half_h), wall_depth * 0.5)
		var ok := true
		for p in accepted:
			if (p as Vector3).distance_to(candidate) < min_distance:
				ok = false
				break
		if ok:
			accepted.append(candidate)
	return accepted


func _spawn_marker(id: int, local_pos: Vector3, is_crumbling: bool) -> void:
	var marker := MeshInstance3D.new()
	marker.mesh = _mesh_crumble if is_crumbling else _mesh_normal
	marker.set_surface_override_material(0, _mat_crumble if is_crumbling else _mat_normal)
	marker.position = local_pos
	add_child(marker)
	_markers[id] = marker


func nearest_grip(point: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_dist := INF
	for g in grips:
		var d: float = (g["pos"] as Vector3).distance_to(point)
		if d < best_dist:
			best_dist = d
			best = g
	return best


func grips_within(point: Vector3, radius: float) -> Array:
	var result: Array = []
	for g in grips:
		if (g["pos"] as Vector3).distance_to(point) <= radius:
			result.append(g)
	return result


# Called once a limb actually lands on (not just plans toward) a grip.
# Non-crumbling grips are a no-op. A crumbling grip loses one use; at zero
# it's removed from `grips` entirely (so future path planning can no
# longer target it) and its marker plays a quick break-away animation.
func consume_grip(id: int) -> void:
	for i in grips.size():
		var g: Dictionary = grips[i]
		if g["id"] != id or not g["crumbling"]:
			continue
		g["uses_left"] -= 1
		if g["uses_left"] <= 0:
			grips.remove_at(i)
			_break_marker(id)
		return


func _break_marker(id: int) -> void:
	var marker: MeshInstance3D = _markers.get(id)
	if not marker:
		return
	_markers.erase(id)
	var tw := marker.create_tween()
	tw.tween_property(marker, "scale", Vector3.ZERO, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(marker.queue_free)
