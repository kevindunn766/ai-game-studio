class_name Food extends Node3D

@export var pulse_speed: float = 4.0
@export var pulse_amplitude: float = 0.14

const BONUS_PULSE_SPEED := 8.0
const BONUS_PULSE_AMPLITUDE := 0.28
const BONUS_SCORE_VALUE := 3

var material: StandardMaterial3D
var mesh_node: MeshInstance3D
var is_bonus: bool = false

var _base_pulse_speed: float
var _base_pulse_amplitude: float


func _ready() -> void:
	_base_pulse_speed = pulse_speed
	_base_pulse_amplitude = pulse_amplitude

	material = StandardMaterial3D.new()
	material.emission_enabled = true
	material.emission_energy_multiplier = 1.4
	material.roughness = 0.25

	mesh_node = MeshInstance3D.new()
	mesh_node.name = "Mesh"
	var b := BoxMesh.new()
	b.size = Vector3(0.65, 0.65, 0.65)
	mesh_node.mesh = b
	mesh_node.set_surface_override_material(0, material)
	add_child(mesh_node)

	set_bonus(false)


func set_bonus(bonus: bool) -> void:
	is_bonus = bonus
	# Studio Palette v1 (COLOR_SYSTEM.md): normal food is the reward-accent
	# family (warm gold) — red is reserved studio-wide for danger signals.
	# Bonus food (novelty twist: rare, worth 3x score) gets a distinct,
	# even higher-chroma cyan so it's unmistakable at a glance, and pulses
	# faster/bigger to draw the eye before it's gone.
	var color: Color = Color.from_hsv(0.5, 0.85, 0.95, 1.0) if bonus else Color.from_hsv(0.13, 0.78, 0.95, 1.0)
	material.albedo_color = color
	material.emission = color
	var b: BoxMesh = mesh_node.mesh as BoxMesh
	b.size = Vector3(0.8, 0.8, 0.8) if bonus else Vector3(0.65, 0.65, 0.65)
	pulse_speed = BONUS_PULSE_SPEED if bonus else _base_pulse_speed
	pulse_amplitude = BONUS_PULSE_AMPLITUDE if bonus else _base_pulse_amplitude


func score_value() -> int:
	return BONUS_SCORE_VALUE if is_bonus else 1


func _process(_delta: float) -> void:
	var s := 1.0 + sin(Time.get_ticks_msec() / 1000.0 * pulse_speed * 6.2831853) * pulse_amplitude
	scale = Vector3.ONE * s
