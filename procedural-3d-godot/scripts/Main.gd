class_name Main
extends Node3D

@onready var player: Node3D = $Player
@onready var camera_rig: Node3D = $CameraRig
@onready var world: Node3D = $World
@onready var score_label: Label = $UIRoot/ScoreLabel
@onready var high_score_label: Label = $UIRoot/HighScoreLabel

var score: int = 0
var high_score: int = 0
var game_speed: float = 12.0
var platform_spawn_timer: float = 0.0
var platform_spawn_distance: float = 0.0
var game_active: bool = false

const PLATFORM_SPAWN_GAP: float = 8.0
const PLATFORM_LENGTH: float = 6.0
const LANE_WIDTH: float = 3.0
const PICKUP_PATH: String = "res://scenes/Pickup.tscn"

func _ready() -> void:
    randomize()
    _load_high_score()
    if player:
        player.main_ref = self
    _start_game()

func _load_high_score() -> void:
    var cfg = ConfigFile.new()
    var err = cfg.load("user://scores.cfg")
    if err == OK:
        high_score = cfg.get_value("player", "high_score", 0)
    if high_score_label:
        high_score_label.text = "Best: %d" % high_score

func _save_high_score() -> void:
    var cfg = ConfigFile.new()
    cfg.set_value("player", "high_score", high_score)
    cfg.save("user://scores.cfg")

func _start_game() -> void:
    game_active = true
    score = 0
    game_speed = 12.0
    if score_label:
        score_label.text = "Score: 0"
    _spawn_initial_platforms()

func _spawn_initial_platforms() -> void:
    _spawn_platform_row(0.0)
    for i in range(20):
        platform_spawn_distance += PLATFORM_SPAWN_GAP
        _spawn_platform_row(platform_spawn_distance)

func _spawn_platform_row(z_pos: float) -> void:
    for lane in [-1, 0, 1]:
        var px = lane * LANE_WIDTH
        _spawn_platform(Vector3(px, 0, z_pos))

    if randf() < 0.25:
        _spawn_hazard(z_pos)
    if randf() < 0.20:
        _spawn_pickup(z_pos)

func _spawn_platform(pos: Vector3) -> void:
    var mesh = MeshInstance3D.new()
    var box = BoxMesh.new()
    box.size = Vector3(LANE_WIDTH * 0.95, 0.5, PLATFORM_LENGTH)
    mesh.mesh = box
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.15, 0.75, 1.0, 1.0)
    mat.roughness = 0.6
    mesh.material_override = mat
    mesh.position = pos
    world.add_child(mesh)

func _spawn_hazard(z_pos: float) -> void:
    var lane = randi() % 3 - 1
    var mesh = MeshInstance3D.new()
    var box = BoxMesh.new()
    box.size = Vector3(LANE_WIDTH * 0.7, 1.2, 1.0)
    mesh.mesh = box
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(1.0, 0.2, 0.2, 1.0)
    mat.roughness = 0.4
    mesh.material_override = mat
    mesh.position = Vector3(lane * LANE_WIDTH, 0.5, z_pos)
    mesh.add_to_group("hazards")
    world.add_child(mesh)

func _spawn_pickup(z_pos: float) -> void:
    var lane = randi() % 3 - 1
    var mesh = MeshInstance3D.new()
    var sphere = SphereMesh.new()
    sphere.radius = 0.35
    sphere.height = 0.7
    mesh.mesh = sphere
    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(1.0, 0.9, 0.1, 1.0)
    mat.roughness = 0.2
    mat.emission_enabled = true
    mat.emission = Color(1.0, 0.9, 0.1, 1.0)
    mat.emission_energy_multiplier = 0.4
    mesh.material_override = mat
    mesh.position = Vector3(lane * LANE_WIDTH, 1.0, z_pos)
    mesh.add_to_group("pickups")
    world.add_child(mesh)

func _process(delta: float) -> void:
    if not game_active or not world:
        return

    for child in world.get_children():
        if child is Node3D:
            child.position.z += game_speed * delta

    platform_spawn_distance -= game_speed * delta
    if platform_spawn_distance < PLATFORM_SPAWN_GAP * 18:
        platform_spawn_distance += PLATFORM_SPAWN_GAP
        _spawn_platform_row(platform_spawn_distance)

    for child in world.get_children():
        if child is Node3D and child.position.z > 12.0:
            child.queue_free()

    game_speed += delta * 0.05

func add_score(amount: int) -> void:
    score += amount
    if score_label:
        score_label.text = "Score: %d" % score

func game_over() -> void:
    game_active = false
    if score > high_score:
        high_score = score
        _save_high_score()
    get_tree().reload_current_scene()
