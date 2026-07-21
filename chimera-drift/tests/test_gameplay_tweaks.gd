extends Node

# Verifies (1) flying enemies are half size, (2) player bolts gently home toward a
# roughly-ahead enemy but ignore ones outside the seek cone, and (3) enemy bolts don't home.

const EnemySpawner := preload("res://scripts/enemy_spawner.gd")
const Projectile := preload("res://scripts/projectile.gd")
const Combat := preload("res://scripts/combat.gd")

var _fail := 0
func _ok(c: bool, m: String) -> void:
	print(("  PASS: " if c else "  FAIL: "), m)
	if not c: _fail += 1

func _enemy_at(pos: Vector3) -> Area3D:
	var a := Area3D.new()
	a.add_to_group(Combat.GROUP_ENEMY_HURTBOX)
	add_child(a)
	a.global_position = pos
	return a

func _ready() -> void:
	print("=== gameplay tweaks test ===")
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	# (1) enemies half size: create() halves the passed scale.
	var theme := {"accent": Color(0.9, 0.4, 0.3), "features": {}}
	var dumb := EnemySpawner.create("dumb", null, theme, {}, 2.0, rng)
	var smart := EnemySpawner.create("smart", null, theme, {}, 2.0, rng)
	_ok(is_equal_approx(dumb.enemy_scale, 1.0), "dumb enemy is half size (2.0 -> %.2f)" % dumb.enemy_scale)
	_ok(is_equal_approx(smart.enemy_scale, 1.0), "smart enemy is half size (2.0 -> %.2f)" % smart.enemy_scale)
	dumb.free()
	smart.free()

	# (2) player bolt homes toward an in-cone enemy.
	var target := _enemy_at(Vector3(10, 0, -30))       # ahead (-Z) and off to +X, inside the cone
	var p := Projectile.new()
	p.team = Combat.TEAM_PLAYER
	p.velocity = Vector3(0, 0, -60)                    # firing straight -Z
	add_child(p)
	p.global_position = Vector3.ZERO
	var to_t: Vector3 = (target.global_position).normalized()
	var start_ang: float = p.velocity.normalized().angle_to(to_t)
	for i in range(20):
		p._home(1.0 / 60.0)
	var end_ang: float = p.velocity.normalized().angle_to(to_t)
	_ok(end_ang < start_ang - 0.05, "player bolt curves toward the enemy (angle %.2f -> %.2f rad)" % [start_ang, end_ang])
	_ok(is_equal_approx(p.velocity.length(), 60.0), "homing keeps the bolt speed constant")

	# (3) an enemy BEHIND (outside the cone) is ignored.
	var behind := _enemy_at(Vector3(0, 0, 40))
	target.free()                                      # remove the front target
	var p2 := Projectile.new()
	p2.team = Combat.TEAM_PLAYER
	p2.velocity = Vector3(0, 0, -60)
	add_child(p2)
	p2.global_position = Vector3.ZERO
	for i in range(20):
		p2._home(1.0 / 60.0)
	_ok(p2.velocity.normalized().is_equal_approx(Vector3(0, 0, -1)), "a target behind the cone is ignored (bolt stays straight)")

	print("=== %s ===" % ("ALL PASS" if _fail == 0 else "%d FAILURES" % _fail))
	get_tree().quit(_fail)
