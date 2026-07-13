class_name DousingThreat extends Node3D

# One recognizable instant-kill "boss pattern" per band (per the brief's Fail
# State section): Telegraph (visible tell) -> Active (lethal for a brief
# window) -> Cooldown (inert), repeating. All three bands' threats (dew drop,
# squirt-bottle, sprinkler) share this one state machine with per-tier
# timing/visuals rather than bespoke mechanics each -- a deliberate M2
# simplification to prove "recognize the tell, avoid the zone" as the core
# skill expression before any band-specific flavor is layered on.
enum State { COOLDOWN, TELEGRAPH, ACTIVE }

@export var threat_tier: String = ""
@export var zone_radius: float = 0.3
@export var telegraph_duration: float = 1.0
@export var active_duration: float = 0.3
@export var cooldown_duration: float = 3.0

var cell_key: Vector3i = Vector3i.ZERO

var _state: State = State.COOLDOWN
var _timer: float = 0.0
var _visual: Node3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _flame: Node3D
var _killed_this_active_window: bool = false
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	_build_base_visual()
	_build_ring()
	# Desync multiple threats so they don't all telegraph in lockstep.
	_timer = _rng.randf_range(cooldown_duration * 0.3, cooldown_duration)
	_flame = get_tree().current_scene.get_node_or_null("Flame")


func play_pop_in() -> void:
	_visual.scale = Vector3.ZERO
	var tw := create_tween()
	tw.tween_property(_visual, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func play_despawn() -> void:
	var tw := create_tween()
	tw.tween_property(_visual, "scale", Vector3.ZERO, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


func is_lethal() -> bool:
	return _state == State.ACTIVE


func _process(delta: float) -> void:
	_timer -= delta
	match _state:
		State.COOLDOWN:
			if _timer <= 0.0:
				_enter_telegraph()
		State.TELEGRAPH:
			var t: float = 1.0 - clampf(_timer / telegraph_duration, 0.0, 1.0)
			_ring.visible = true
			_ring.scale = Vector3.ONE * lerpf(0.35, 1.0, t) * zone_radius
			_ring_mat.albedo_color = Color(0.3, 0.6, 1.0, lerpf(0.25, 0.7, t))
			if _timer <= 0.0:
				_enter_active()
		State.ACTIVE:
			_check_lethal_overlap()
			if _timer <= 0.0:
				_enter_cooldown()


func _enter_telegraph() -> void:
	_state = State.TELEGRAPH
	_timer = telegraph_duration


func _enter_active() -> void:
	_state = State.ACTIVE
	_timer = active_duration
	_killed_this_active_window = false
	_ring.scale = Vector3.ONE * zone_radius
	_ring_mat.albedo_color = Color(0.5, 0.75, 1.0, 0.9)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = Color(0.5, 0.8, 1.0)
	_ring_mat.emission_energy_multiplier = 2.0


func _enter_cooldown() -> void:
	_state = State.COOLDOWN
	_timer = cooldown_duration
	_ring.visible = false
	_ring_mat.emission_enabled = false


func _check_lethal_overlap() -> void:
	if _killed_this_active_window or not _flame:
		return
	if global_position.distance_to(_flame.global_position) > zone_radius:
		return
	_killed_this_active_window = true
	var km: Node = get_tree().current_scene
	if km and km.has_method("trigger_death"):
		km.call("trigger_death")


func _build_ring() -> void:
	_ring = MeshInstance3D.new()
	var m := TorusMesh.new()
	m.inner_radius = 0.75
	m.outer_radius = 1.0
	_ring.mesh = m
	_ring.rotation_degrees = Vector3(90, 0, 0)
	_ring.position.y = 0.02
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.albedo_color = Color(0.3, 0.6, 1.0, 0.0)
	_ring.material_override = _ring_mat
	_ring.visible = false
	add_child(_ring)


func _build_base_visual() -> void:
	var mesh_inst := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.4
	match threat_tier:
		"dew_drop":
			var m := SphereMesh.new()
			m.radius = 0.05
			m.height = 0.09
			mesh_inst.mesh = m
			mesh_inst.position.y = 0.5  # hangs overhead, "falls" conceptually
			mat.albedo_color = Color(0.6, 0.8, 1.0, 0.85)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.metallic = 0.3
		"squirt_bottle":
			var m := CylinderMesh.new()
			m.top_radius = 0.05
			m.bottom_radius = 0.07
			m.height = 0.28
			mesh_inst.mesh = m
			mesh_inst.position.y = 0.14
			mat.albedo_color = Color(0.85, 0.25, 0.2)
		"sprinkler":
			var m := CylinderMesh.new()
			m.top_radius = 0.04
			m.bottom_radius = 0.06
			m.height = 0.2
			mesh_inst.mesh = m
			mesh_inst.position.y = 0.1
			mat.albedo_color = Color(0.35, 0.35, 0.32)
			mat.metallic = 0.5
		"garden_hose":
			var m := CapsuleMesh.new()
			m.radius = 0.27
			m.height = 1.7
			mesh_inst.mesh = m
			mesh_inst.position.y = 0.85
			mat.albedo_color = Color(0.3, 0.55, 0.35)
		"fire_extinguisher":
			var m := CylinderMesh.new()
			m.top_radius = 0.12
			m.bottom_radius = 0.16
			m.height = 0.55
			mesh_inst.mesh = m
			mesh_inst.position.y = 0.275
			mat.albedo_color = Color(0.75, 0.1, 0.08)
			mat.metallic = 0.3
		"hose_reel_firefighter":
			var m := CapsuleMesh.new()
			m.radius = 0.32
			m.height = 1.85
			mesh_inst.mesh = m
			mesh_inst.position.y = 0.925
			mat.albedo_color = Color(0.85, 0.6, 0.05)
		"fire_truck_pumper":
			var m := BoxMesh.new()
			m.size = Vector3(2.6, 2.8, 7.0)
			mesh_inst.mesh = m
			mesh_inst.position.y = 1.4
			mat.albedo_color = Color(0.75, 0.08, 0.06)
			mat.metallic = 0.3
		"ladder_company":
			var m := BoxMesh.new()
			m.size = Vector3(3.0, 3.5, 10.0)
			mesh_inst.mesh = m
			mesh_inst.position.y = 1.75
			mat.albedo_color = Color(0.7, 0.1, 0.08)
			mat.metallic = 0.3
		"water_bomber":
			var m := BoxMesh.new()
			m.size = Vector3(9.0, 3.5, 14.0)
			mesh_inst.mesh = m
			mesh_inst.position.y = 8.0  # airborne
			mat.albedo_color = Color(0.85, 0.7, 0.15)
			mat.metallic = 0.5
		_:
			var m := BoxMesh.new()
			m.size = Vector3(0.1, 0.1, 0.1)
			mesh_inst.mesh = m
			mat.albedo_color = Color(1, 0, 1)
	mesh_inst.material_override = mat
	_visual.add_child(mesh_inst)
