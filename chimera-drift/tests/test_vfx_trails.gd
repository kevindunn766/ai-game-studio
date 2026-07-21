extends Node

# Verifies the lightweight jet/trail particle helper and the enemy trail gating:
# - VFX.trail() builds a small world-space CPUParticles3D (billboard, additive, faded).
# - enemy_base gives a trail only to types whose _wants_trail() is true (flying enemies),
#   NOT to mines / stationary hazards (which keep the default false).
#
# Run: godot --headless --path <proj> res://tests/test_vfx_trails.tscn --quit-after 10

const VFX := preload("res://scripts/vfx.gd")

# Tiny stand-ins for a flying enemy (wants a trail) and a mine (does not), so the test
# doesn't need the full enemy visual/AI builders.
class Flyer extends "res://scripts/enemy_base.gd":
	func _wants_trail() -> bool:
		return true

class Stationary extends "res://scripts/enemy_base.gd":
	pass   # inherits _wants_trail() == false, like a mine / rooted hazard

var _fail: int = 0

func _ok(cond: bool, msg: String) -> void:
	print(("  PASS: " if cond else "  FAIL: "), msg)
	if not cond:
		_fail += 1

func _count_particles(n: Node) -> int:
	var c: int = 0
	for ch in n.get_children():
		if ch is CPUParticles3D:
			c += 1
	return c

func _ready() -> void:
	print("=== vfx jets / trails test ===")

	# --- VFX.trail config ---
	var p := VFX.trail(Color(0.5, 0.85, 1.0, 0.8), 0.16, 12, 0.32, Vector3(0, 0, 1), 3.0, true)
	_ok(p is CPUParticles3D, "trail() returns a CPUParticles3D")
	_ok(not p.local_coords, "trail sims in WORLD space (so motion leaves a trail)")
	_ok(p.amount == 12, "amount honored (lightweight count)")
	_ok(p.gravity == Vector3.ZERO, "no gravity (drifting trail)")
	var q := p.mesh as QuadMesh
	_ok(q != null and q.size.x <= 0.2, "particles are small billboards (size <= 0.2)")
	var mat := q.material as StandardMaterial3D
	_ok(mat != null and mat.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED, "billboarded")
	_ok(mat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD, "additive glow")
	p.free()

	# --- enemy trail gating ---
	var flyer := Flyer.new()
	flyer.accent = Color(0.9, 0.3, 0.3)
	flyer.enemy_scale = 1.0
	add_child(flyer)
	var stat := Stationary.new()
	stat.accent = Color(0.9, 0.3, 0.3)
	stat.enemy_scale = 1.0
	add_child(stat)
	await get_tree().process_frame

	var tier_has_particles: bool = PerfProfile.particle_scale > 0.0
	if tier_has_particles:
		_ok(_count_particles(flyer) == 1, "a flying enemy gets exactly one trail emitter")
		_ok(_count_particles(stat) == 0, "a mine / stationary hazard gets NO trail")
	else:
		_ok(_count_particles(flyer) == 0, "lowest perf tier: no trail even on flyers")

	print("=== %s ===" % ("ALL PASS" if _fail == 0 else "%d FAILURES" % _fail))
	get_tree().quit(_fail)
