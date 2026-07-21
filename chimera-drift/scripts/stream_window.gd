extends RefCounted

# Shared camera-visibility streaming window (2026-07-19). Generators build ONLY within a
# tight window around what the player can actually see -- `build_ahead` in front (just past
# the fogged horizon, plus a little off-camera padding) and `build_behind` behind -- and
# free everything outside it, instead of laying out the whole ~200u level. So at any moment
# only the visible slice (+padding) is in memory.
#
# To keep the tight window from ever SHOWING its build/free, scenery objects scale in near
# the far frontier and scale OUT as they recede past the ship, shrinking to nothing before
# they're freed. `scale_factor` returns that 0..1 multiplier for an object at world-z obj_z.

# 0 at/beyond the frontier -> 1 in the visible middle -> 0 at/beyond the behind cull.
static func scale_factor(obj_z: float, ship_z: float, build_ahead: float, build_behind: float, fade_ahead: float, fade_behind: float) -> float:
	var ahead: float = ship_z - obj_z    # >0 in front of the ship, <0 behind it
	var f: float = 1.0
	if fade_ahead > 0.0 and ahead > build_ahead - fade_ahead:
		f = clampf((build_ahead - ahead) / fade_ahead, 0.0, 1.0)   # grows in as it nears
	if fade_behind > 0.0 and ahead < -(build_behind - fade_behind):
		f = minf(f, clampf((build_behind + ahead) / fade_behind, 0.0, 1.0))   # shrinks out as it recedes
	return f

# CAMERA-DISTANCE cull (2026-07-19): in the DEEP views (third-person / 3-4) the landscape
# runs far back, so objects should scale DOWN as they recede from the camera and CULL
# (stop rendering) before the fogged horizon -- rather than a whole field of props drawing
# far into the distance. These fractions of the build distance set where that ramp sits.
const CULL_BEGIN_FRAC: float = 0.5    # objects start shrinking at this × build distance from the camera
const CULL_END_FRAC: float = 0.82     # ...and are fully culled (hidden) by this ×

# Camera-distance visibility cull WITHOUT scaling. For nodes that own a CollisionShape3D
# (enemies): scaling those toward zero triggers Godot's "det == 0" basis-inversion spam
# (see the studio note -- never scale a collider-owning node). Just hide it past `end`.
static func cull(node: Node3D, cam_pos: Vector3, begin: float, end: float) -> void:
	if not is_instance_valid(node):
		return
	node.visible = camera_factor(node.global_position, cam_pos, begin, end) > 0.02

# 1.0 near the camera -> 0.0 at/beyond `end`. Pass end<=0 to disable (non-deep views).
static func camera_factor(node_pos: Vector3, cam_pos: Vector3, begin: float, end: float) -> float:
	if end <= 0.0 or end <= begin:
		return 1.0
	var d: float = node_pos.distance_to(cam_pos)
	return clampf((end - d) / (end - begin), 0.0, 1.0)

# Scale a scenery node toward zero by its window factor (base scale captured once), AND --
# when cam_end>0 -- by its distance from the camera, whichever shrinks it more. The node is
# HIDDEN once it shrinks to ~nothing (a real render cull, not just a 0-scale draw). Safe for
# the padding/far zones because the ship is far from anything being scaled there, so the
# object's (unscaled) collision body is never in play while its visual shrinks.
static func apply(node: Node3D, seg_z: float, ship_z: float, ba: float, bb: float, fa: float, fb: float,
		cam_pos: Vector3 = Vector3.ZERO, cam_begin: float = 0.0, cam_end: float = -1.0) -> void:
	if not is_instance_valid(node):
		return
	if not node.has_meta("stream_base_scale"):
		node.set_meta("stream_base_scale", node.scale)
	var base: Vector3 = node.get_meta("stream_base_scale")
	var f: float = minf(scale_factor(seg_z, ship_z, ba, bb, fa, fb), camera_factor(node.global_position, cam_pos, cam_begin, cam_end))
	# Never scale to EXACTLY 0 -- a 0-scale basis is singular and spams Godot's
	# "det == 0" basis-inversion error (esp. for collider-owning nodes). The node is
	# already hidden below the visible threshold, so the tiny floor is never seen.
	node.scale = base * maxf(f, 0.0015)
	node.visible = f > 0.02
