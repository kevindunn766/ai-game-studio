class_name Player
extends CharacterBody3D

@onready var mesh_instance: MeshInstance3D = $Mesh

const MOVE_SPEED: float = 10.0
const LANE_WIDTH: float = 3.0
const MAX_LANES: int = 1
const JUMP_VELOCITY: float = 8.5
const SLIDE_TIME: float = 0.6

var target_lane: int = 0
var current_lane: int = 0
var vertical_velocity: float = 0.0
var is_sliding: bool = false
var slide_timer: float = 0.0
var main_ref: Object = null

func _ready() -> void:
    var box: BoxMesh = null
    if mesh_instance.mesh is BoxMesh:
        box = mesh_instance.mesh as BoxMesh
    else:
        box = BoxMesh.new()
        mesh_instance.mesh = box
    box.size = Vector3(1.0, 1.8, 1.0)

    var mat = StandardMaterial3D.new()
    mat.albedo_color = Color(0.2, 0.9, 1.0, 1.0)
    mat.roughness = 0.3
    mat.emission_enabled = true
    mat.emission = Color(0.2, 0.9, 1.0, 1.0)
    mat.emission_energy_multiplier = 0.3
    mesh_instance.material_override = mat

    var shape = BoxShape3D.new()
    shape.size = Vector3(1.0, 1.8, 1.0)
    $CollisionShape3D.shape = shape

func _lane_input(dir: int) -> void:
    current_lane = clamp(current_lane + dir, -MAX_LANES, MAX_LANES)

func _physics_process(delta: float) -> void:
    var move_dir = 0
    if Input.is_action_just_pressed("ui_left"):
        move_dir = -1
    elif Input.is_action_just_pressed("ui_right"):
        move_dir = 1

    if move_dir != 0:
        _lane_input(move_dir)

    if Input.is_action_just_pressed("ui_up") and is_on_floor():
        vertical_velocity = JUMP_VELOCITY

    if Input.is_action_just_pressed("ui_down") and is_on_floor() and not is_sliding:
        is_sliding = true
        slide_timer = SLIDE_TIME
        _set_slide_height(true)

    if is_sliding:
        slide_timer -= delta
        if slide_timer <= 0:
            is_sliding = false
            _set_slide_height(false)

    if not is_on_floor():
        vertical_velocity -= 12.0 * delta

    var target_x = current_lane * LANE_WIDTH
    var diff_x = target_x - position.x
    var vel_x = diff_x * 15.0

    velocity = Vector3(vel_x, vertical_velocity, 0)
    move_and_slide()

    _check_hazards()

func _set_slide_height(sliding: bool) -> void:
    var h = 0.4 if sliding else 1.8
    var box: BoxMesh = mesh_instance.mesh as BoxMesh
    if box:
        box.size = Vector3(1.0, h, 1.0)
    var shape = $CollisionShape3D.shape as BoxShape3D
    if shape:
        shape.size = Vector3(1.0, h, 1.0)
    position.y = h / 2.0 if sliding else 1.0

func _check_hazards() -> void:
    var space = get_world_3d()
    if not space:
        return
    var query = PhysicsShapeQueryParameters3D.new()
    var shape = BoxShape3D.new()
    shape.size = Vector3(0.9, 1.6, 0.9)
    query.shape = shape
    query.transform = global_transform
    query.collision_mask = 2
    var results = space.direct_space_state.intersect_shape(query)

    for r in results:
        var collider = r.collider
        if collider.is_in_group("hazards"):
            if main_ref:
                main_ref.game_over()
            return

    var pickup_query = PhysicsShapeQueryParameters3D.new()
    var sphere = SphereShape3D.new()
    sphere.radius = 0.6
    pickup_query.shape = sphere
    pickup_query.transform = global_transform
    pickup_query.collision_mask = 4
    var pickups = space.direct_space_state.intersect_shape(pickup_query)

    for r in pickups:
        var collider = r.collider
        if collider.is_in_group("pickups"):
            collider.queue_free()
            if main_ref:
                main_ref.add_score(10)
