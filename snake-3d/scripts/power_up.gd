class_name PowerUp extends Node3D

@export var ptype: String = "rainbow"
@export var pulse_speed: float = 3.5
@export var pulse_amplitude: float = 0.16
@export var spin_speed: float = 1.6

var _mesh_node: MeshInstance3D
var _pop_scale: float = 0.0
var _pop_tween: Tween


func pop_out_and_free() -> void:
	if _pop_tween:
		_pop_tween.kill()
	_pop_tween = create_tween()
	_pop_tween.tween_property(self, "_pop_scale", 0.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_pop_tween.tween_callback(queue_free)


func _ready() -> void:
	_mesh_node = MeshInstance3D.new()
	_mesh_node.name = "Mesh"
	var mat := StandardMaterial3D.new()
	mat.metallic = 0.3
	mat.emission_enabled = true

	match ptype:
		"rainbow":
			var m := BoxMesh.new()
			m.size = Vector3(0.55, 0.55, 0.55)
			_mesh_node.mesh = m
			_mesh_node.rotation_degrees = Vector3(45, 45, 0)
			mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
			mat.emission = Color(1.0, 1.0, 1.0)
			mat.emission_energy_multiplier = 1.6
			mat.roughness = 0.1
		"yellow":
			var m2 := SphereMesh.new()
			m2.radius = 0.32
			m2.height = 0.64
			_mesh_node.mesh = m2
			mat.albedo_color = Color(1.0, 0.85, 0.1, 1.0)
			mat.emission = Color(1.0, 0.8, 0.05)
			mat.emission_energy_multiplier = 1.8
			mat.roughness = 0.1
		"red":
			var m3 := BoxMesh.new()
			m3.size = Vector3(0.55, 0.55, 0.55)
			_mesh_node.mesh = m3
			_mesh_node.rotation_degrees = Vector3(45, 45, 0)
			mat.albedo_color = Color(1.0, 0.1, 0.1, 1.0)
			mat.emission = Color(1.0, 0.05, 0.05)
			mat.emission_energy_multiplier = 2.0
			mat.roughness = 0.15
		"blue":
			var m4 := PrismMesh.new()
			m4.size = Vector3(0.6, 0.7, 0.6)
			_mesh_node.mesh = m4
			mat.albedo_color = Color(0.1, 0.55, 1.0, 1.0)
			mat.emission = Color(0.1, 0.5, 1.0)
			mat.emission_energy_multiplier = 1.8
			mat.roughness = 0.1
		"neon_speed":
			var m5 := CylinderMesh.new()
			m5.top_radius = 0.32
			m5.bottom_radius = 0.32
			m5.height = 0.1
			_mesh_node.mesh = m5
			spin_speed = 5.0
			mat.albedo_color = Color(0.2, 1.0, 1.0, 1.0)
			mat.emission = Color(0.2, 1.0, 1.0)
			mat.emission_energy_multiplier = 2.2
			mat.roughness = 0.05
		"mirage":
			var m6 := PrismMesh.new()
			m6.size = Vector3(0.55, 0.55, 0.55)
			_mesh_node.mesh = m6
			mat.albedo_color = Color(0.85, 0.75, 0.5, 0.55)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.emission = Color(0.9, 0.8, 0.55)
			mat.emission_energy_multiplier = 1.2
			mat.roughness = 0.2
		"ice_shield":
			var m7 := CylinderMesh.new()
			m7.top_radius = 0.34
			m7.bottom_radius = 0.34
			m7.height = 0.12
			_mesh_node.mesh = m7
			mat.albedo_color = Color(0.7, 0.9, 1.0, 1.0)
			mat.emission = Color(0.6, 0.85, 1.0)
			mat.emission_energy_multiplier = 1.6
			mat.roughness = 0.1
		"boulder_burst":
			var m8 := BoxMesh.new()
			m8.size = Vector3(0.6, 0.5, 0.55)
			_mesh_node.mesh = m8
			mat.albedo_color = Color(0.45, 0.4, 0.35, 1.0)
			mat.emission = Color(0.5, 0.3, 0.15)
			mat.emission_energy_multiplier = 1.0
			mat.roughness = 0.8
		"crystal_growth":
			var m9 := BoxMesh.new()
			m9.size = Vector3(0.35, 0.75, 0.35)
			_mesh_node.mesh = m9
			_mesh_node.rotation_degrees = Vector3(20, 45, 15)
			mat.albedo_color = Color(0.65, 0.2, 0.85, 1.0)
			mat.emission = Color(0.6, 0.15, 0.9)
			mat.emission_energy_multiplier = 2.0
			mat.roughness = 0.1
		"magma_trail":
			var m10 := SphereMesh.new()
			m10.radius = 0.3
			m10.height = 0.6
			_mesh_node.mesh = m10
			mat.albedo_color = Color(1.0, 0.35, 0.05, 1.0)
			mat.emission = Color(1.0, 0.3, 0.0)
			mat.emission_energy_multiplier = 2.2
			mat.roughness = 0.3
		"laser":
			var m11 := CylinderMesh.new()
			m11.top_radius = 0.12
			m11.bottom_radius = 0.12
			m11.height = 0.9
			_mesh_node.mesh = m11
			mat.albedo_color = Color(0.4, 1.0, 1.0, 1.0)
			mat.emission = Color(0.3, 1.0, 1.0)
			mat.emission_energy_multiplier = 2.4
			mat.roughness = 0.05
		"scatter":
			var m12 := TorusMesh.new()
			m12.inner_radius = 0.18
			m12.outer_radius = 0.34
			_mesh_node.mesh = m12
			_mesh_node.rotation_degrees = Vector3(90, 0, 0)
			mat.albedo_color = Color(1.0, 0.55, 0.1, 1.0)
			mat.emission = Color(1.0, 0.5, 0.05)
			mat.emission_energy_multiplier = 2.0
			mat.roughness = 0.2
		"nova":
			var m13 := SphereMesh.new()
			m13.radius = 0.42
			m13.height = 0.84
			_mesh_node.mesh = m13
			mat.albedo_color = Color(1.0, 0.55, 0.2, 1.0)
			mat.emission = Color(1.0, 0.45, 0.1)
			mat.emission_energy_multiplier = 2.6
			mat.roughness = 0.05

	_mesh_node.set_surface_override_material(0, mat)
	add_child(_mesh_node)

	_pop_tween = create_tween()
	_pop_tween.tween_property(self, "_pop_scale", 1.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	var s := 1.0 + sin(Time.get_ticks_msec() / 1000.0 * pulse_speed * 6.2831853) * pulse_amplitude
	scale = Vector3.ONE * s * _pop_scale
	rotate_y(spin_speed * delta)

	if ptype == "rainbow":
		var mat := _mesh_node.get_surface_override_material(0) as StandardMaterial3D
		if mat:
			var hue := fmod(Time.get_ticks_msec() / 1000.0 * 0.5, 1.0)
			var c := Color.from_hsv(hue, 0.6, 1.0, 1.0)
			mat.albedo_color = c
			mat.emission = c
