class_name Food extends Node3D

@export var pulse_speed: float = 4.0
@export var pulse_amplitude: float = 0.14

var material: StandardMaterial3D


func _ready() -> void:
	# Studio Palette v1 (COLOR_SYSTEM.md): food is a reward, not a hazard, so
	# it gets the reward-accent family (warm gold) instead of red — red is
	# reserved studio-wide for danger/lose-condition signals.
	var reward_color := Color.from_hsv(0.13, 0.78, 0.95, 1.0)
	material = StandardMaterial3D.new()
	material.albedo_color = reward_color
	material.emission_enabled = true
	material.emission = reward_color
	material.emission_energy_multiplier = 1.4
	material.roughness = 0.25

	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Mesh"
	var b := BoxMesh.new()
	b.size = Vector3(0.65, 0.65, 0.65)
	mesh_node.mesh = b
	mesh_node.set_surface_override_material(0, material)
	add_child(mesh_node)


func _process(_delta: float) -> void:
	var s := 1.0 + sin(Time.get_ticks_msec() / 1000.0 * pulse_speed * 6.2831853) * pulse_amplitude
	scale = Vector3.ONE * s
