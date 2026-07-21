extends Node3D

# Third-person sits back so the ship reads smaller (Kevin, 2026-07-19 -- was 2.15 /
# ~1/3 of the screen) -- deliberately NOT scaled by the global zoom_out (which is for
# the pulled-back angled/overhead views). Still scales with ship_visual_radius so the
# ship keeps its on-screen size as it grows.
@export var third_person_base_distance: float = 3.4
@export var side_scroll_base_distance: float = 5.0
@export var side_scroll_height: float = 1.5
@export var isometric_base_distance: float = 14.0
@export var isometric_base_size: float = 6.0
# Elevation of the iso camera above the horizon. Classic iso is ~35.26 deg (the old
# hardcoded Vector3(1,1,1) direction); a much SHALLOWER angle (Kevin) looks more across
# toward the horizon, so the cliff backdrop + gorge walls loom instead of reading flat.
@export var isometric_elevation_degrees: float = 18.0
@export var top_down_base_distance: float = 16.0
@export var top_down_base_size: float = 8.0
@export var three_quarter_base_distance: float = 9.0
# 3/4 view sits ABOVE and to the RIGHT of the ship (a real over-the-shoulder
# diagonal), not directly behind -- otherwise it's indistinguishable from the
# third-person chase. Azimuth swings it right of straight-behind; elevation lifts
# it up. (Ship flies toward -Z, so +X is its right and +Z is behind.)
@export var three_quarter_elevation_degrees: float = 18.0   # much shallower (was 35) -- looks across toward the horizon
@export var three_quarter_azimuth_degrees: float = 42.0

# Global zoom-out: every rig pulls back / grows its ortho size by this factor so the
# world reads smaller and the player sees more ahead (more reaction time). For the
# orthographic rigs (iso, top-down) it is `size` that actually zooms -- distance is
# scaled too only to keep near/far clearance. Fog + streaming (below and in the
# generators/director) are pushed out to match so nothing pops or over-fogs.
@export var zoom_out: float = 1.6

# Side-scroll and top-down push the ship off-center toward the near edge (left /
# bottom respectively) so more of what's AHEAD is on screen. Implemented as a
# translation of the camera + its aim toward the ship's travel direction (-Z), so
# the framing angle is unchanged -- only where the ship sits in frame moves.
# side-scroll shift is a fraction of the camera distance; top-down of the ortho size.
# Kept off the very edge -- the ship sits toward the edge with a clear margin.
@export var side_scroll_screen_shift: float = 0.5
@export var top_down_screen_shift: float = 0.24

# Iso + 3/4 put the ship in the LOWER-LEFT corner (Kevin) -- a 2-axis screen-space
# push, expressed as fractions of the rig's characteristic length (iso: ortho size;
# 3/4: camera distance). Bigger = deeper into the corner. Third-person keeps the ship
# centered but slightly BELOW the midpoint, via a base frustum v_offset.
@export var isometric_corner_x: float = 0.36     # push ship left (with edge margin)
@export var isometric_corner_y: float = 0.22     # push ship down
@export var three_quarter_corner_x: float = 0.34 # push ship left
@export var three_quarter_corner_y: float = 0.2  # push ship down
@export var third_person_lower: float = 0.18     # frustum v_offset -> ship a touch below center

# Steer look-ahead / anticipation. The aim point leads the ship toward its steer
# direction (in seconds of steer velocity) and eases, so turns have gentle
# follow-through. Kept subtle and slow-easing on purpose -- a big lead + fast
# smoothing whips the camera around; this glides. Positions are NOT moved -- only
# the aim leads -- so Governing Rule 6 framing distances stay exact.
@export var look_ahead: float = 0.15
@export var look_smooth: float = 2.2
@export var tp_lead_yaw_deg: float = 4.0      # third-person chase pivot leads into turns (gentle)
@export var tp_lead_pitch_deg: float = 2.5

# Crash screen-shake (trauma model). Applied as frustum h/v offset so it reads
# identically on every rig -- including the spring-arm third-person cam -- without
# fighting camera positioning. Self-clears as trauma decays.
@export var shake_decay: float = 2.5
@export var shake_max_offset: float = 0.45

# Framing radius easing: ship_visual_radius jumps in discrete steps when a pickup grows the
# ship, which snapped the camera (distance/size scale off it). Ease a smoothed value toward it
# at a CONSTANT rate (move_toward, not an exponential lerp) so the zoom GLIDES at a fixed gentle
# speed instead of lurching fast then decaying -- the lurch was the felt "jerk". Radius units
# per second; a pickup adds `growth_step` (0.15), so 0.3 => it catches up over ~0.5s. Still
# driven off ship_visual_radius (Governing Rule 6).
@export var radius_ease_rate: float = 0.3

# Camera collision: no rig may sit inside/behind the lethal terrain (esp. with the new
# shallow angles). The third-person spring arm shrinks natively; the scripted rigs use a
# manual spring -- raycast from the ship out to the desired camera spot and, if terrain is
# in the way, pull the camera to the near side of it (so the ground/wall never occludes
# the ship and the camera never dips underground). Pulled back off the surface by margin.
const HAZARD_COLLISION_LAYER: int = 4
@export var camera_collision_margin: float = 0.5

@onready var ship: Node3D = get_parent()
@onready var third_person_pivot: Node3D = $ThirdPersonPivot
@onready var third_person_spring_arm: SpringArm3D = $ThirdPersonPivot/ThirdPersonSpringArm3D
@onready var third_person_camera: Camera3D = $ThirdPersonPivot/ThirdPersonSpringArm3D/ThirdPersonCamera3D
@onready var side_scroll_camera: Camera3D = $SideScrollPivot/SideScrollCamera3D
@onready var isometric_camera: Camera3D = $IsometricPivot/IsometricCamera3D
@onready var top_down_camera: Camera3D = $TopDownPivot/TopDownCamera3D
@onready var three_quarter_camera: Camera3D = $ThreeQuarterPivot/ThreeQuarterCamera3D

# Diagonal ground bearing of the iso camera (+X right, +Z behind); its height comes
# from isometric_elevation_degrees so the angle is tunable (shallow) rather than fixed.
const ISOMETRIC_BEARING: Vector3 = Vector3(1, 0, 1)

var _lead: Vector3 = Vector3.ZERO
var _trauma: float = 0.0
var _framing_radius: float = 1.0

func _ready() -> void:
	ship.crashed.connect(_on_ship_crashed)
	_framing_radius = ship.ship_visual_radius
	# Let the third-person spring arm shrink when terrain gets between it and the ship.
	third_person_spring_arm.collision_mask = HAZARD_COLLISION_LAYER
	third_person_spring_arm.margin = camera_collision_margin

func _on_ship_crashed(_distance: float) -> void:
	_trauma = 1.0

func _process(delta: float) -> void:
	# Glide the framing radius toward the ship's real (stepwise) radius at a CONSTANT rate so a
	# pickup's zoom change is a steady gentle drift, never a lurch (see radius_ease_rate).
	_framing_radius = move_toward(_framing_radius, ship.ship_visual_radius, radius_ease_rate * delta)
	var radius: float = _framing_radius
	var ship_pos: Vector3 = ship.global_transform.origin

	# Smoothed steer look-ahead: aim a bit toward where the ship is steering.
	var steer: Vector2 = ship.steer_velocity
	var target_lead: Vector3 = Vector3(steer.x, steer.y, 0.0) * look_ahead
	var ease: float = 1.0 - exp(-look_smooth * delta)
	_lead = _lead.lerp(target_lead, ease)
	var aim: Vector3 = ship_pos + _lead

	third_person_spring_arm.spring_length = third_person_base_distance * radius
	# Chase cam leads into the turn by yawing/pitching its pivot slightly.
	var span: float = maxf(0.001, ship.steer_speed)
	var nx: float = clampf(steer.x / span, -1.0, 1.0)
	var ny: float = clampf(steer.y / span, -1.0, 1.0)
	third_person_pivot.rotation.y = lerp_angle(third_person_pivot.rotation.y, deg_to_rad(-tp_lead_yaw_deg) * nx, ease)
	third_person_pivot.rotation.x = lerp_angle(third_person_pivot.rotation.x, deg_to_rad(tp_lead_pitch_deg) * ny, ease)

	# Side-scroll: pull back by zoom_out, then translate camera + aim toward -Z so the
	# ship rides the LEFT of the screen (screen-right maps to -Z here) and more of the
	# track ahead is visible.
	var ss_dist: float = side_scroll_base_distance * radius * zoom_out
	var ss_shift: Vector3 = Vector3(0, 0, -ss_dist * side_scroll_screen_shift)
	side_scroll_camera.position = _spring_local(Vector3(ss_dist, side_scroll_height, 0) + ss_shift)
	side_scroll_camera.look_at(aim + ss_shift, Vector3.UP)

	# Iso -> ship in the lower-left corner: translate camera + aim by a screen-space
	# (right, up) offset so the ship sits screen-left + screen-down. Offset is
	# perpendicular to the view direction, so the framing scale is unchanged.
	var iso_dist: float = isometric_base_distance * radius * zoom_out
	var iso_size: float = isometric_base_size * radius * zoom_out
	var iso_el: float = deg_to_rad(isometric_elevation_degrees)
	var iso_dir: Vector3 = (ISOMETRIC_BEARING.normalized() * cos(iso_el) + Vector3.UP * sin(iso_el)).normalized()
	var iso_off: Vector3 = _screen_offset(-iso_dir, Vector3.UP, iso_size * isometric_corner_x, iso_size * isometric_corner_y)
	isometric_camera.position = _spring_local(iso_dir * iso_dist + iso_off)
	isometric_camera.look_at(aim + iso_off, Vector3.UP)
	isometric_camera.size = iso_size

	# Top-down: bigger ortho size zooms out; translate camera + aim toward -Z so the
	# ship rides the BOTTOM of the screen (screen-up maps to -Z here).
	var td_dist: float = top_down_base_distance * radius * zoom_out
	var td_size: float = top_down_base_size * radius * zoom_out
	var td_shift: Vector3 = Vector3(0, 0, -td_size * top_down_screen_shift)
	top_down_camera.position = _spring_local(Vector3(0, td_dist, 0) + td_shift)
	top_down_camera.look_at(aim + td_shift, Vector3.FORWARD)
	top_down_camera.size = td_size

	# Above + right + behind: swing right by the azimuth, lift by the elevation.
	var el_rad: float = deg_to_rad(three_quarter_elevation_degrees)
	var az_rad: float = deg_to_rad(three_quarter_azimuth_degrees)
	var three_quarter_direction: Vector3 = Vector3(
		sin(az_rad) * cos(el_rad),   # +X -> ship's right
		sin(el_rad),                 # +Y -> above
		cos(az_rad) * cos(el_rad))   # +Z -> behind (keeps the ship's forward path in view)
	# 3/4 -> ship in the lower-left corner too (same screen-space offset scheme).
	var tq_dist: float = three_quarter_base_distance * radius * zoom_out
	var tq_off: Vector3 = _screen_offset(-three_quarter_direction, Vector3.UP, tq_dist * three_quarter_corner_x, tq_dist * three_quarter_corner_y)
	three_quarter_camera.position = _spring_local(three_quarter_direction * tq_dist + tq_off)
	three_quarter_camera.look_at(aim + tq_off, Vector3.UP)

	_apply_shake(delta)

# World-space translation that shifts the framed subject on screen: moving the camera
# + aim by (+screen_right, +screen_up) makes the subject appear (left, down). Both
# axes are derived from the view direction (fwd) and an up hint, and are perpendicular
# to fwd so the subject distance -- and thus the framing scale -- is unchanged.
# Manual spring for the scripted rigs: cast from the ship out to the desired camera spot;
# if lethal terrain is in the way, return a LOCAL position on the near side of it (minus a
# margin) so the camera never sits behind/under the ground. `desired_local` is relative to
# the ship (the pivots are at the ship with identity basis, so world = ship_pos + local).
func _spring_local(desired_local: Vector3) -> Vector3:
	var origin: Vector3 = ship.global_position
	var space := get_world_3d().direct_space_state
	if space == null:
		return desired_local
	var q := PhysicsRayQueryParameters3D.create(origin, origin + desired_local)
	q.collision_mask = HAZARD_COLLISION_LAYER
	q.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return desired_local
	var dir: Vector3 = desired_local.normalized()
	return (hit.position - dir * camera_collision_margin) - origin

func _screen_offset(fwd: Vector3, up_hint: Vector3, right_amt: float, up_amt: float) -> Vector3:
	var right: Vector3 = fwd.cross(up_hint).normalized()
	var scr_up: Vector3 = right.cross(fwd).normalized()
	return right * right_amt + scr_up * up_amt

func _apply_shake(delta: float) -> void:
	_trauma = maxf(0.0, _trauma - shake_decay * delta)
	var amount: float = _trauma * _trauma          # quadratic falloff feels punchier
	var ox: float = randf_range(-1.0, 1.0) * amount * shake_max_offset
	var oy: float = randf_range(-1.0, 1.0) * amount * shake_max_offset
	for cam in [side_scroll_camera, isometric_camera, top_down_camera, three_quarter_camera]:
		cam.h_offset = ox
		cam.v_offset = oy
	# Third-person keeps the ship centered but a touch BELOW the midpoint (base
	# v_offset), with the shake added on top.
	third_person_camera.h_offset = ox
	third_person_camera.v_offset = third_person_lower + oy
