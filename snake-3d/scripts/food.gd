class_name Food extends Node3D

@export var pulse_speed: float = 4.0
@export var pulse_amplitude: float = 0.14

var material: StandardMaterial3D


func _ready() -> void:
	material = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.14, 0.14, 1.0)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.14, 0.14, 1.0)
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
