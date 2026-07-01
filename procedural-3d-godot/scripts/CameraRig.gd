extends Node3D

@export var follow_speed: float = 8.0
@export var height: float = 3.5
@export var z_behind: float = 7.0

func _physics_process(delta: float) -> void:
	var player: Node3D = get_node_or_null("../Player") as Node3D
	if not player:
		return
	var target: Vector3 = player.global_position + Vector3(0.0, height, z_behind)
	global_position = global_position.lerp(target, clamp(follow_speed * delta, 0.0, 1.0))
	var look_target: Vector3 = player.global_position + Vector3(0.2, 0.5, -6.0)
	if global_position.distance_to(look_target) > 0.1:
		look_at(look_target, Vector3.UP)
