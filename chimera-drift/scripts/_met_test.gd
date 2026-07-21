extends Node3D

# Temp: numerically verify meteorite behavior in real physics --
#  A) head-on high closing speed -> ship crashes
#  B) glancing/zero closing speed -> ship survives, rock gets nudged
#  C) lone rock drifts (microgravity, low damping)

const MET := preload("res://scripts/meteorite.gd")

class FakeShip extends Node3D:
	var velocity: Vector3 = Vector3.ZERO
	var alive: bool = true
	var ship_visual_radius: float = 1.0
	var crashed: bool = false
	func crash() -> void:
		crashed = true
		alive = false

func _ready() -> void:
	await _test_crash()
	await _test_nudge()
	await _test_drift()
	get_tree().quit()

func _spawn(sz: int, pos: Vector3, ship: Node3D) -> RigidBody3D:
	var m: RigidBody3D = MET.new()
	add_child(m)
	m.setup(sz, pos, 1.0, ship, self, Color(0.5, 0.5, 0.5))
	m.linear_velocity = Vector3.ZERO       # deterministic start
	m.angular_velocity = Vector3.ZERO
	return m

# required by meteorite.spawn callback (unused here)
func spawn_meteorite(_s: int, _p: Vector3, _v: Vector3) -> void:
	pass

func _test_crash() -> void:
	var ship := FakeShip.new()
	ship.position = Vector3.ZERO
	ship.velocity = Vector3(0, 0, -8)      # fast, head-on toward the rock ahead
	add_child(ship)
	var m := _spawn(MET.Size.MEDIUM, Vector3(0, 0, -0.8), ship)
	for i in range(3):
		await get_tree().physics_frame
	print("A head-on: ship.crashed=", ship.crashed, " (expect true)")
	m.queue_free()
	ship.queue_free()

func _test_nudge() -> void:
	var ship := FakeShip.new()
	ship.position = Vector3.ZERO
	ship.velocity = Vector3(0, 0, -8)      # moving -Z; rock is off to the +X side
	add_child(ship)
	var m := _spawn(MET.Size.MEDIUM, Vector3(0.8, 0, 0), ship)
	for i in range(3):
		await get_tree().physics_frame
	print("B glancing: ship.crashed=", ship.crashed, " (expect false)  rock vel.x=",
		snappedf(m.linear_velocity.x, 0.01), " (expect > 0)")
	m.queue_free()
	ship.queue_free()

func _test_drift() -> void:
	var ship := FakeShip.new()
	ship.position = Vector3(0, 0, -100)    # far away: no contact
	add_child(ship)
	var m := _spawn(MET.Size.SMALL, Vector3(0, 0, 0), ship)
	m.linear_velocity = Vector3(0, 1.0, 0)
	var y0: float = m.global_position.y
	for i in range(20):
		await get_tree().physics_frame
	var y1: float = m.global_position.y
	print("C drift: dy=", snappedf(y1 - y0, 0.001), " (expect > 0, ~microgravity)")
	m.queue_free()
	ship.queue_free()
