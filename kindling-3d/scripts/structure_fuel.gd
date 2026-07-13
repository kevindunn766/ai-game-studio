class_name StructureFuel extends Node3D

signal fully_burned(structure: StructureFuel)

const FUEL_COLLISION_LAYER := 2  # same layer as Fuel -- Flame's IgniteArea detects both
const DissolveShader := preload("res://shaders/dissolve.gdshader")

@export var fuel_tier: String = ""
@export var max_health: float = 10.0
@export var full_charge_value: float = 10.0
@export var drain_rate: float = 4.0  # health per second while flame stays in contact
@export var burnt_husk_fade_in: float = 0.3

# Set by PropManager at spawn time so the fully_burned signal's listener can
# mark the correct streaming cell as permanently burned.
var cell_key: Vector3i = Vector3i.ZERO

var current_health: float
var _ignited: bool = false
var _fully_burned: bool = false
var _dissolve_mat: ShaderMaterial
var _pristine_visual: Node3D
var _burn_particles: GPUParticles3D

# All visuals (pristine mesh, burnt husk) live under this wrapper, never
# under self -- self owns StructureFuelArea's CollisionShape3D directly, and
# Godot errors ("det == 0", basis inversion) the instant any ancestor's scale
# hits zero, so play_despawn()'s fade-out must never scale self. Same fix
# pattern as fuel.gd's _visual.
var _visual_root: Node3D


func _ready() -> void:
	current_health = max_health
	_visual_root = Node3D.new()
	_visual_root.name = "Visual"
	add_child(_visual_root)

	var area := Area3D.new()
	area.name = "StructureFuelArea"
	area.collision_layer = FUEL_COLLISION_LAYER
	area.collision_mask = 0
	area.monitoring = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.45  # bigger contact radius than Quick Fuel, matches a bigger object
	shape.shape = sphere
	area.add_child(shape)
	add_child(area)


func is_fully_burned() -> bool:
	return _fully_burned


func burn_progress() -> float:
	return 1.0 - (current_health / max_health) if max_health > 0.0 else 1.0


# Called by PropManager right after add_child(structure); swaps the mesh's
# material for the shared dissolve shader so drain() can drive burn_progress.
func set_pristine_visual(node: Node3D) -> void:
	_pristine_visual = node
	_visual_root.add_child(node)
	if node is MeshInstance3D:
		_apply_dissolve_material(node as MeshInstance3D)


func _apply_dissolve_material(mesh_inst: MeshInstance3D) -> void:
	var base_color: Color = Color(0.6, 0.6, 0.6)
	if mesh_inst.material_override is StandardMaterial3D:
		base_color = (mesh_inst.material_override as StandardMaterial3D).albedo_color
	var mat := ShaderMaterial.new()
	mat.shader = DissolveShader
	mat.set_shader_parameter("albedo_color", base_color)
	mat.set_shader_parameter("burn_progress", 0.0)
	mesh_inst.material_override = mat
	_dissolve_mat = mat


# Touching a Structure Fuel ignites it (visual burn starts) but does not by
# itself drain health -- health only drains via drain(), called every physics
# tick from Flame while contact is actively held. Losing contact simply
# pauses the drain; no explicit "end contact" bookkeeping is needed here.
func begin_contact() -> void:
	if _fully_burned or _ignited:
		return
	_ignited = true
	_start_burn_particles()


func drain(delta: float) -> void:
	if _fully_burned or not _ignited:
		return
	current_health = maxf(0.0, current_health - drain_rate * delta)
	if _dissolve_mat:
		_dissolve_mat.set_shader_parameter("burn_progress", burn_progress())
	if current_health <= 0.0:
		_complete_burn()


func _complete_burn() -> void:
	_fully_burned = true
	fully_burned.emit(self)
	if _burn_particles:
		_burn_particles.emitting = false
	if _pristine_visual:
		_pristine_visual.queue_free()
	_spawn_burnt_husk()


# Used by PropManager when a not-yet-fully-burned structure streams out of
# range -- discards whatever burn progress had been made (M2 scope: no
# partial-progress persistence), same "fade and free" treatment as Quick Fuel.
func play_despawn() -> void:
	if _burn_particles:
		_burn_particles.emitting = false
	var tw := create_tween()
	tw.tween_property(_visual_root, "scale", Vector3.ZERO, 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


func _spawn_burnt_husk() -> void:
	var husk := Node3D.new()
	husk.name = "BurntHusk"

	var mesh_inst := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(0.42, 0.12, 0.32)  # collapsed/flattened relative to the pristine box
	mesh_inst.mesh = m
	mesh_inst.position.y = 0.06
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.07, 0.06, 0.06)
	mat.roughness = 1.0
	mesh_inst.material_override = mat
	husk.add_child(mesh_inst)

	husk.scale = Vector3.ZERO
	_visual_root.add_child(husk)
	var tw := create_tween()
	tw.tween_property(husk, "scale", Vector3.ONE, burnt_husk_fade_in).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _start_burn_particles() -> void:
	_burn_particles = GPUParticles3D.new()
	_burn_particles.amount = 16
	_burn_particles.lifetime = 0.6
	_burn_particles.emitting = true

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 40.0
	mat.initial_velocity_min = 0.3
	mat.initial_velocity_max = 0.7
	mat.gravity = Vector3(0, 0.4, 0)
	mat.scale_min = 0.9
	mat.scale_max = 1.8
	mat.color = Color(1.0, 0.45, 0.08)
	_burn_particles.process_material = mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.07, 0.07)
	_burn_particles.draw_pass_1 = quad
	_burn_particles.position.y = 0.15

	add_child(_burn_particles)
