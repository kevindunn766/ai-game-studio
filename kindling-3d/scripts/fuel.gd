class_name Fuel extends Node3D

signal ignited(fuel: Fuel)

const FUEL_COLLISION_LAYER := 2  # matches Flame's IgniteArea collision_mask

@export var fuel_tier: String = ""
@export var charge_value: float = 1.0
@export var burn_duration: float = 0.5

# Set by PropManager at spawn time so the ignited signal's listener can mark
# the correct streaming cell as permanently burned.
var cell_key: Vector3i = Vector3i.ZERO

var _ignited: bool = false
var _visual: Node3D


# Fuel's own scale must always stay at 1.0 -- FuelArea's CollisionShape3D is
# a direct child, and Godot errors ("det == 0", basis inversion) the instant
# any ancestor's scale hits zero. Pop-in/burn-down animation therefore
# targets a separate _visual child instead of self.
func _ready() -> void:
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)

	var area := Area3D.new()
	area.name = "FuelArea"
	area.collision_layer = FUEL_COLLISION_LAYER
	area.collision_mask = 0
	area.monitoring = false  # only needs to be detected, never detects itself
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.1
	shape.shape = sphere
	area.add_child(shape)
	add_child(area)


# Called by PropManager right after add_child(fuel) (so _ready() has already
# built _visual) to attach the tier's mesh.
func set_visual(node: Node3D) -> void:
	_visual.add_child(node)


func play_pop_in() -> void:
	_visual.scale = Vector3.ZERO
	var tw := create_tween()
	tw.tween_property(_visual, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# Used by PropManager when a cell streams out of range unburned (not ignited)
# -- same _visual-only scale target as play_pop_in()/ignite(), so this never
# touches self.scale either.
func play_despawn() -> void:
	var tw := create_tween()
	tw.tween_property(_visual, "scale", Vector3.ZERO, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


func is_ignited() -> bool:
	return _ignited


# Quick Fuel's burn-down is a simple scale-to-zero tween (mirrors
# food.gd::pop_out_and_free in snake-3d) -- the shared noise-driven dissolve
# shader with a burn_progress uniform is Structure Fuel's burnt-husk-reveal
# infrastructure, out of scope for M1's Quick-Fuel-only roster.
func ignite() -> void:
	if _ignited:
		return
	_ignited = true
	ignited.emit(self)
	_spawn_burn_particles()
	var tw := create_tween()
	tw.tween_property(_visual, "scale", Vector3.ZERO, burn_duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


func _spawn_burn_particles() -> void:
	var particles := GPUParticles3D.new()
	particles.amount = 14
	particles.lifetime = 0.4
	particles.one_shot = true
	particles.explosiveness = 1.0

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 50.0
	mat.initial_velocity_min = 0.4
	mat.initial_velocity_max = 0.9
	mat.gravity = Vector3(0, 0.5, 0)
	mat.scale_min = 0.8
	mat.scale_max = 1.6
	mat.color = Color(1.0, 0.5, 0.1)
	particles.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	particles.draw_pass_1 = quad

	add_child(particles)
	particles.emitting = true
	get_tree().create_timer(particles.lifetime + 0.1).timeout.connect(particles.queue_free)
