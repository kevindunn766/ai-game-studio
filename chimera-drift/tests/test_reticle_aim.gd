extends Node3D

# Verifies the reticle aim ray-trace: a ray along the fire line (-Z) against LAYER_ENEMY
# (8), areas-only, must hit enemy/mine hurtboxes -- which are Area3D with monitoring=false
# (enemy_base's config) -- and land at the nearest one, and miss when nothing's in line.
#
# Run: godot --headless --path <proj> res://tests/test_reticle_aim.tscn --quit-after 20

const Combat := preload("res://scripts/combat.gd")

var _fail: int = 0
var _near: Area3D
var _far: Area3D
var _frames: int = 0

func _ok(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: "), msg)
	if not cond:
		_fail += 1

func _make_target(pos: Vector3, radius: float) -> Area3D:
	var a := Area3D.new()
	a.collision_layer = Combat.LAYER_ENEMY   # like enemy_base / mine hurtboxes
	a.collision_mask = 0
	a.monitoring = false                     # the exact enemy_base config (detected, doesn't detect)
	a.monitorable = true
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = radius
	cs.shape = sph
	a.add_child(cs)
	add_child(a)
	a.global_position = pos
	return a

func _ready() -> void:
	print("=== reticle aim ray-trace test ===")
	# Two targets in the -Z fire line, plus one off to the side.
	_near = _make_target(Vector3(0, 0.1, -10.0), 1.0)
	_far = _make_target(Vector3(0, 0.1, -20.0), 1.0)
	# (an off-line target to prove the ray doesn't grab it)
	_make_target(Vector3(6.0, 0.1, -10.0), 1.0)

func _cast() -> Dictionary:
	var space := get_world_3d().direct_space_state
	var origin := Vector3(0, 0.1, 0)
	var q := PhysicsRayQueryParameters3D.create(origin, origin + Vector3(0, 0, -1) * 120.0)
	q.collision_mask = Combat.LAYER_ENEMY
	q.collide_with_areas = true
	q.collide_with_bodies = false
	return space.intersect_ray(q)

func _physics_process(_delta: float) -> void:
	_frames += 1
	if _frames == 5:
		# Nearest target in line -> hit its FRONT face (~z = -9).
		var hit := _cast()
		_ok(not hit.is_empty(), "ray hits an Area3D hurtbox with monitoring=false")
		if not hit.is_empty():
			_ok(absf(hit.position.z + 9.0) < 0.6, "lands on the NEAREST target's front face (~z=-9)")
			_ok(absf(hit.position.x) < 0.3, "hit is centred on the fire line (x~0)")
			_ok(hit.collider == _near, "hit collider is the near target, not the far / off-line one")
	elif _frames == 10:
		# Remove the near one -> ray should now reach the far target (~z = -19).
		_near.queue_free()
	elif _frames == 15:
		var hit := _cast()
		_ok(not hit.is_empty() and absf(hit.position.z + 19.0) < 0.6, "with the near target gone, the ray reaches the far one (~z=-19)")
		# Now move the far one off the line -> nothing in the fire line -> miss.
		_far.global_position = Vector3(20.0, 0.1, -20.0)
	elif _frames == 20:
		var hit := _cast()
		_ok(hit.is_empty(), "no target in the fire line -> no hit (reticle falls back to fixed distance)")
		print("=== %s ===" % ("ALL PASS" if _fail == 0 else "%d FAILURES" % _fail))
		get_tree().quit(_fail)
