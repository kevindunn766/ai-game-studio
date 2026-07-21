extends Node3D

# Streams power-up pickups along the flight path, the same way the level
# generators stream props/enemies -- this is the fix for the design brief's
# long-standing gap where power-ups were static one-time scene nodes that ran out
# after ~45 units and killed the ship-growth ("cosplay") hook for the rest of a
# run. Now pickups spawn continuously ahead of the ship and recycle behind it.
#
# Shape-agnostic: it asks whichever generator is active for a reachable point at a
# given z (each generator knows its own navigable envelope -- tube interior,
# terrain surface, open-volume core), so pickups always sit in flyable space.
#
# Owned/reset by LevelDirector: configure() each build, clear()/start() around
# every level (re)build just like the generators.

@export var ship_path: NodePath
@export var spawn_interval: float = 18.0     # avg units of distance between pickups
@export var spawn_jitter: float = 5.0        # +/- variance on the interval
@export var pickups_ahead: float = 90.0      # stream this far in front of the ship

# First-guess pickup mix (flagged for tuning in the brief). Cosmetic dominates so
# the ship keeps gaining greebles; the two functional effects are the only ones
# buildable without a weapon/health system yet (speed_boost, magnet).
@export var speed_boost_chance: float = 0.20
@export var magnet_chance: float = 0.15

const SAFE_START_DIST: float = 24.0          # matches the generators' opening runway
const PowerUp := preload("res://scripts/power_up.gd")
const AttachmentBuilder := preload("res://scripts/attachment_builder.gd")

@onready var ship: Node3D = get_node(ship_path)

var active_generator: Node = null
var theme: Dictionary = {}
var rng := RandomNumberGenerator.new()
var spawned: Array = []          # [pickup, spawn_z]
var next_pickup_z: float = 0.0
var active: bool = false

func configure(generator: Node, level_theme: Dictionary) -> void:
	active_generator = generator
	theme = level_theme

func clear() -> void:
	active = false
	for entry in spawned:
		if is_instance_valid(entry[0]):
			entry[0].queue_free()
	spawned.clear()

func start() -> void:
	rng.randomize()
	active = true
	# First pickup just past the hazard-free opening runway.
	next_pickup_z = -SAFE_START_DIST - rng.randf_range(0.0, spawn_interval)
	while next_pickup_z > ship.position.z - pickups_ahead:
		_spawn_pickup()

func _process(_delta: float) -> void:
	if not active:
		return
	while next_pickup_z > ship.position.z - pickups_ahead:
		_spawn_pickup()
	_recycle()

func _spawn_pickup() -> void:
	if active_generator == null or not active_generator.has_method("reachable_point"):
		next_pickup_z -= spawn_interval
		return
	var z: float = next_pickup_z
	var pos: Vector3 = active_generator.reachable_point(z, rng)

	var pickup: Area3D = PowerUp.new()
	var roll: float = rng.randf()
	var accent: Color = theme.get("accent", Color(0.7, 0.8, 1.0, 1.0))
	if roll < speed_boost_chance:
		pickup.effect = "speed_boost"
		pickup.kind = "barrel"
	elif roll < speed_boost_chance + magnet_chance:
		pickup.effect = "magnet"
		pickup.kind = "dome"
	else:
		pickup.effect = ""
		pickup.kind = AttachmentBuilder.KIND_COSMETIC[rng.randi() % AttachmentBuilder.KIND_COSMETIC.size()]
	pickup.attach_color = _themed_color(accent)
	pickup.ship = ship

	add_child(pickup)
	pickup.position = pos
	spawned.append([pickup, z])
	next_pickup_z -= spawn_interval + rng.randf_range(-spawn_jitter, spawn_jitter)

# Small per-pickup hue jitter around the level accent so a run's parts share the
# level's palette without every greeble being an identical color.
func _themed_color(accent: Color) -> Color:
	var h: float = accent.h + rng.randf_range(-0.04, 0.04)
	var s: float = clampf(accent.s * rng.randf_range(0.85, 1.05), 0.0, 1.0)
	var v: float = clampf(accent.v * rng.randf_range(0.9, 1.1), 0.15, 1.0)
	return Color.from_hsv(fposmod(h, 1.0), s, v)

func _recycle() -> void:
	var behind_distance: float = 20.0
	var i: int = 0
	while i < spawned.size():
		if spawned[i][1] > ship.position.z + behind_distance:
			if is_instance_valid(spawned[i][0]):
				spawned[i][0].queue_free()
			spawned.remove_at(i)
		else:
			i += 1
