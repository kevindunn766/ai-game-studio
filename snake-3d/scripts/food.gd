class_name Food extends Node3D

signal eaten()

var base_scale := Vector3.ONE
var pulse_amplitude := 0.15
var pulse_speed := 4.0
var material: StandardMaterial3D


func _ready() -> void:
	material = StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.15, 0.15, 1.0)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.15, 0.15, 1.0)
	material.emission_energy_multiplier = 1.4
	material.roughness = 0.25

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var b := BoxMesh.new()
	b.size = Vector3(0.65, 0.65, 0.65)
	mesh.mesh = b
	mesh.set_surface_override_material(0, material)
	add_child(mesh)

	base_scale = Vector3.ONE


func _process(delta: float) -> void:
	var s := base_scale + Vector3.ONE * sin(Time.get_ticks_msec() / 1000.0 * pulse_speed * 6.2831853) * pulse_amplitude
	scale = s


func _on_area_entered(area: Area3D) -> void:
	if area.owner is Snake:
		eaten.emit()
		queue_free()
		# Note: queue_free may not keep script logic local, but caller respawns via GameManager.
