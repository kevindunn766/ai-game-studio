extends Area3D

const MeshUtil := preload("res://scripts/mesh_util.gd")

# A pickup. Streamed ambiently by PowerUpStreamer, OR dropped by a destroyed enemy
# (see enemy_base._spawn_drop). Built entirely in code, so it sets up its own
# collision + visual in _ready from the fields the spawner assigns before add_child:
#   kind         -> greeble silhouette granted on collect (see AttachmentBuilder)
#   effect       -> "" (cosmetic) | "speed_boost" | "magnet"     (ambient)
#                   | "weapon_up"                                  (dumb-enemy drop, temporary)
#                   | "shield" | "fire_rate" | "afterburner"       (smart-enemy drop, permanent)
#   grows_ship   -> whether collecting also fills a ship mount with a themed greeble.
#                   Permanent pieces do (they "attach to the ship"); the temporary
#                   weapon_up buff does not.
#   attach_color -> themed color for BOTH this pickup's glow and the hull greeble
#
# Detection mirrors the established project pattern: the SHIP carries a
# monitorable PickupDetector Area3D (layer 2, group "ship_pickup_detector"); this
# pickup monitors layer 2 and reacts when that detector overlaps it. Kept on its
# own layer/mask so pickups never interact with the hazard/combat layers.

var kind: String = "cosmetic"
var effect: String = ""
var grows_ship: bool = true
var attach_color: Color = Color(0.7, 0.8, 1.0, 1.0)
var pickup_radius: float = 1.1

@export var speed_boost_multiplier: float = 1.7
@export var speed_boost_duration: float = 3.0
@export var magnet_duration: float = 5.0
@export var spin_speed: float = 1.6
@export var magnet_range: float = 14.0
@export var magnet_pull: float = 20.0

# Set by the streamer so an active magnet can pull this pickup toward the ship.
var ship: Node3D = null

var collected: bool = false
var _visual: Node3D = null

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2                # see the ship's layer-2 PickupDetector
	monitoring = true
	monitorable = true
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = pickup_radius
	cs.shape = sphere
	add_child(cs)
	_build_visual()
	area_entered.connect(_on_area_entered)

# A bright, gently-emissive silhouette that reads as "collect me" -- distinct from
# the matte lethal hazard props. Shape hints at the effect (chevron thruster for
# speed, ring for magnet, spinning gem for cosmetic).
func _build_visual() -> void:
	_visual = MeshInstance3D.new()
	var mesh: Mesh
	match effect:
		"speed_boost", "afterburner":
			var p := PrismMesh.new()
			p.size = Vector3(0.7, 0.7, 0.7)
			mesh = p
		"magnet":
			var t := TorusMesh.new()
			t.inner_radius = 0.24
			t.outer_radius = 0.5
			mesh = t
		"weapon_up":
			# A pointed spike -> reads as "more firepower".
			var c := CylinderMesh.new()
			c.top_radius = 0.0
			c.bottom_radius = 0.42
			c.height = 0.85
			mesh = c
		"shield":
			var b := BoxMesh.new()
			b.size = Vector3(0.7, 0.7, 0.2)             # plating slab
			mesh = b
		"fire_rate":
			var b := BoxMesh.new()
			b.size = Vector3(0.6, 0.6, 0.6)
			mesh = b
			_visual.rotation = Vector3(0.6, 0.0, 0.6)
		_:
			var b := BoxMesh.new()
			b.size = Vector3(0.55, 0.55, 0.55)
			mesh = b
			_visual.rotation = Vector3(0.6, 0.0, 0.6)   # gem-like diamond tilt
	mesh = MeshUtil.flat(mesh)   # flat-shaded (no smooth normals)
	var mat := StandardMaterial3D.new()
	# The floating pickup GLOWS in the COMPLEMENTARY of the level's dominant colour so it
	# pops off the scenery (purple level -> yellow pickup, blue -> orange). The hull greeble
	# it grants still uses attach_color, so a run's parts stay in the level palette.
	var glow: Color = ColorAid.complementary(attach_color).lightened(0.15)
	mat.albedo_color = glow
	mat.emission_enabled = true
	mat.emission = glow
	mat.emission_energy_multiplier = 1.1   # brighter so it reads as "collect me"
	_visual.mesh = mesh
	_visual.material_override = mat
	add_child(_visual)

func _process(delta: float) -> void:
	if collected:
		return
	if _visual != null:
		_visual.rotate_y(spin_speed * delta)
	# Magnet assist: while the ship's magnet is up, drift toward it once in range.
	if ship != null and is_instance_valid(ship) and ship.alive and ship.magnet_active:
		var to_ship: Vector3 = ship.global_position - global_position
		if to_ship.length() < magnet_range:
			global_position += to_ship.normalized() * magnet_pull * delta

func _on_area_entered(area: Area3D) -> void:
	if collected:
		return
	if not area.is_in_group("ship_pickup_detector"):
		return
	collected = true
	var collecting_ship: Node3D = area.get_parent()
	# Permanent pieces (and the ambient cosmetic/speed/magnet pickups) bolt a themed
	# greeble onto the hull; the temporary weapon_up buff does not consume a mount.
	Sfx.play("part" if grows_ship else "pickup", 1.0, 0.05)
	if grows_ship:
		collecting_ship.grow_ship(kind, attach_color)
	match effect:
		"speed_boost":
			collecting_ship.apply_speed_boost(speed_boost_multiplier, speed_boost_duration)
		"magnet":
			collecting_ship.apply_magnet(magnet_duration)
		"weapon_up":
			collecting_ship.add_weapon_tier()
		"shield":
			collecting_ship.add_shield()
		"fire_rate":
			collecting_ship.upgrade_fire_rate()
		"afterburner":
			collecting_ship.unlock_afterburner()
	# Log this pickup as a draft candidate for the between-levels menu (the ship
	# filters out transient buffs; only hull parts + permanent upgrades qualify).
	collecting_ship.note_collected_piece(kind, attach_color, effect, grows_ship)
	queue_free()
