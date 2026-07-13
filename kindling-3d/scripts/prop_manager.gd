class_name PropManager extends Node3D

const FuelScript := preload("res://scripts/fuel.gd")
const StructureFuelScript := preload("res://scripts/structure_fuel.gd")
const HazardScript := preload("res://scripts/hazard.gd")
const DousingThreatScript := preload("res://scripts/dousing_threat.gd")

@export var flame: Node3D
@export var camera: Camera3D
@export var growth_controller: GrowthController

# Streaming radius keys off camera zoom, not just XZ position -- Kindling's
# explicit departure from snake-3d's floor_manager.gd (whose radius is
# derived purely from snake length on a fixed-scale world). As the camera
# pulls back while the flame grows, the streamed area must grow with it.
# Retuned for camera.size now being a small real-world meter span (~0.4-2.75m
# across Bands 1-3, see camera_controller.gd) rather than the old 4-30 range.
const VIEW_SPAN_MARGIN: float = 1.0
const BASE_PADDING: float = 1.0

# Expanded from 20.0 (a 40x40m yard, enough for Bands 1-3) to fit Band 9's
# "district" scale content (see STRUCTURE_FUEL_TIERS below) -- the brief's
# own Continuous Growth section is explicit that this is one continuous
# fixed-geometry world, not per-tier maps, so later bands' fuel needs
# somewhere to actually exist in the same coordinate space as Band 1's yard.
const PARCEL_HALF_EXTENT: float = 600.0

# Multiple independently-streamed tiers, each with its own cell size, since
# grass-scale and plant-scale content can't share one grid. Tuning values are
# placeholders for a later feel-tuning pass. "active_while_scale_below" gates
# a Band-1 tier off once the flame has clearly outgrown it (scale-gated LOD,
# mirrors floor_manager.gd's _in_carve_zone early-out shape); "active_scale_range"
# additionally gates a Band-2 tier from spawning before it's relevant yet.
# Thresholds are calibrated against flame_scale as real-world meters (Band 1
# 0.02-0.08m, Band 2 0.08-0.25m, Band 3 0.25-0.6m -- see growth_controller.gd).
const PROP_TIERS: Array[Dictionary] = [
	# cell_size/density retuned (was 0.5/0.6) after confirming via headless
	# check that the old values put well under 1 expected blade inside the
	# camera's actual ~0.43x0.24m view at match-scale -- deterministic
	# per-cell hashing means a sparse patch near spawn isn't just bad luck,
	# it's the same empty patch every single run. Denser + smaller cells
	# guarantees real coverage inside the tiny starting view.
	#
	# charge_value dropped hard on the two ground-cover tiers (was 0.6/0.5)
	# once the density fix above revealed the real problem underneath: at
	# that density, just walking through a grass field swept the ignite
	# radius through so many blades per second that Band 1 blew straight
	# through to Band 8 within about a second and a half of movement. Visual
	# density and growth economy are different concerns -- a real lawn is
	# dense to look at, but any single blade is nearly worthless as fuel; it
	# takes a lot of grass to actually grow a fire. Kept dense for the eye,
	# made individually near-negligible for the math.
	{ "id": "dry_grass", "cell_size": 0.07, "density": 0.85, "active_while_scale_below": 0.1, "charge_value": 0.08 },
	{ "id": "twig", "cell_size": 0.25, "density": 0.3, "active_while_scale_below": 0.1, "charge_value": 1.0 },
	{ "id": "wrapper", "cell_size": 0.6, "density": 0.1, "active_while_scale_below": 0.1, "charge_value": 1.0 },
	{ "id": "leaf_litter", "cell_size": 0.08, "density": 0.65, "active_while_scale_below": 0.1, "charge_value": 0.06 },
	{ "id": "small_plant", "cell_size": 1.5, "density": 0.2, "active_scale_range": [0.06, 0.35], "charge_value": 3.0 },
	{ "id": "pine_needle", "cell_size": 1.0, "density": 0.3, "active_scale_range": [0.06, 0.35], "charge_value": 1.5 },
	{ "id": "twig_nest", "cell_size": 1.8, "density": 0.06, "active_scale_range": [0.06, 0.35], "charge_value": 4.0 },
	{ "id": "brush_pile", "cell_size": 2.2, "density": 0.08, "active_scale_range": [0.2, 1.2], "charge_value": 6.0 },
	{ "id": "dry_shrub", "cell_size": 1.8, "density": 0.12, "active_scale_range": [0.2, 1.2], "charge_value": 4.5 },
	{ "id": "campfire_log", "cell_size": 2.5, "density": 0.06, "active_scale_range": [0.5, 3.5], "charge_value": 10.0 },
	{ "id": "kindling_pile", "cell_size": 2.0, "density": 0.08, "active_scale_range": [0.5, 3.5], "charge_value": 8.0 },
	{ "id": "tree_grove", "cell_size": 6.0, "density": 0.03, "active_scale_range": [1.3, 8.0], "charge_value": 20.0 },
	{ "id": "tree_stand", "cell_size": 10.0, "density": 0.02, "active_scale_range": [3.0, 18.0], "charge_value": 35.0 },
	{ "id": "forest_section", "cell_size": 40.0, "density": 0.01, "active_scale_range": [18.0, 110.0], "charge_value": 60.0 },
]

# Structure Fuel tiers stream through the same per-cell mechanism as Quick
# Fuel (same _update_tier/_raw_should_spawn path) but spawn a StructureFuel
# instance instead of a Fuel instance -- see _spawn_prop(). First test object
# is the cardboard box (Band 3); "structure" is the only field that
# distinguishes a row here from a Quick Fuel row above.
const STRUCTURE_FUEL_TIERS: Array[Dictionary] = [
	{ "id": "cardboard_box", "cell_size": 3.0, "density": 0.04, "active_scale_range": [0.2, 1.2], "max_health": 10.0, "structure": true },
	{ "id": "wooden_fence", "cell_size": 4.0, "density": 0.03, "active_scale_range": [0.5, 3.5], "max_health": 18.0, "structure": true },
	{ "id": "shed", "cell_size": 8.0, "density": 0.015, "active_scale_range": [1.3, 8.0], "max_health": 35.0, "structure": true },
	{ "id": "car", "cell_size": 7.0, "density": 0.02, "active_scale_range": [1.3, 8.0], "max_health": 28.0, "structure": true },
	{ "id": "house", "cell_size": 15.0, "density": 0.012, "active_scale_range": [3.0, 18.0], "max_health": 60.0, "structure": true },
	{ "id": "city_block", "cell_size": 30.0, "density": 0.008, "active_scale_range": [7.0, 44.0], "max_health": 100.0, "structure": true },
	{ "id": "neighborhood_block", "cell_size": 60.0, "density": 0.006, "active_scale_range": [18.0, 110.0], "max_health": 160.0, "structure": true },
	{ "id": "district", "cell_size": 120.0, "density": 0.004, "active_scale_range": [44.0, 300.0], "max_health": 260.0, "structure": true },
]

# Non-lethal hazards ("shrink, don't always kill" per the brief's Fail State
# section) stream through the same per-cell mechanism, spawning a Hazard
# instance instead of Fuel/StructureFuel -- see _spawn_prop(). Hazards are
# never marked "burned" (nothing consumes them); they simply respawn/despawn
# with the normal streaming footprint as the flame roams. One row per
# tier/band from the brief's Scale Tier System table (Bands 1-3 only, per
# this milestone's scope).
const HAZARD_TIERS: Array[Dictionary] = [
	{ "id": "ant", "cell_size": 2.0, "density": 0.05, "active_while_scale_below": 0.1, "shrink_amount": 1.5, "move_speed": 0.8, "wander_radius": 1.0, "hazard": true },
	{ "id": "fly", "cell_size": 2.5, "density": 0.04, "active_while_scale_below": 0.1, "shrink_amount": 1.0, "move_speed": 1.4, "wander_radius": 1.5, "hazard": true },
	{ "id": "beetle", "cell_size": 2.5, "density": 0.04, "active_scale_range": [0.06, 0.35], "shrink_amount": 2.5, "move_speed": 0.6, "wander_radius": 1.2, "hazard": true },
	{ "id": "earthworm", "cell_size": 2.5, "density": 0.03, "active_scale_range": [0.06, 0.35], "shrink_amount": 2.0, "move_speed": 0.3, "wander_radius": 0.8, "hazard": true },
	{ "id": "moth", "cell_size": 2.8, "density": 0.04, "active_scale_range": [0.06, 0.35], "shrink_amount": 2.0, "move_speed": 1.6, "wander_radius": 1.8, "hazard": true },
	{ "id": "bird", "cell_size": 3.5, "density": 0.03, "active_scale_range": [0.2, 1.2], "shrink_amount": 4.0, "move_speed": 1.2, "wander_radius": 2.5, "hazard": true },
	{ "id": "cat", "cell_size": 4.0, "density": 0.015, "active_scale_range": [0.2, 1.2], "shrink_amount": 6.0, "move_speed": 1.0, "wander_radius": 2.0, "hazard": true },
	{ "id": "dog", "cell_size": 5.0, "density": 0.03, "active_scale_range": [0.5, 3.5], "shrink_amount": 8.0, "move_speed": 1.2, "wander_radius": 3.0, "hazard": true },
	{ "id": "person_blanket", "cell_size": 6.0, "density": 0.02, "active_scale_range": [0.5, 3.5], "shrink_amount": 10.0, "move_speed": 0.9, "wander_radius": 2.5, "hazard": true },
	{ "id": "homeowner", "cell_size": 9.0, "density": 0.015, "active_scale_range": [1.3, 8.0], "shrink_amount": 15.0, "move_speed": 0.9, "wander_radius": 4.0, "hazard": true },
	{ "id": "resident", "cell_size": 14.0, "density": 0.012, "active_scale_range": [3.0, 18.0], "shrink_amount": 22.0, "move_speed": 1.0, "wander_radius": 6.0, "hazard": true },
	{ "id": "security_guard", "cell_size": 16.0, "density": 0.008, "active_scale_range": [3.0, 18.0], "shrink_amount": 28.0, "move_speed": 1.1, "wander_radius": 7.0, "hazard": true },
	{ "id": "first_responder", "cell_size": 25.0, "density": 0.01, "active_scale_range": [7.0, 44.0], "shrink_amount": 35.0, "move_speed": 1.4, "wander_radius": 10.0, "hazard": true },
	{ "id": "fire_crew", "cell_size": 35.0, "density": 0.008, "active_scale_range": [18.0, 110.0], "shrink_amount": 50.0, "move_speed": 1.2, "wander_radius": 15.0, "hazard": true },
	# "low threat" per the brief -- evacuation chaos is set dressing, not a
	# real danger, hence the deliberately small shrink_amount relative to its
	# band (contrast fire_crew's 50.0 one band earlier).
	{ "id": "evacuee", "cell_size": 50.0, "density": 0.02, "active_scale_range": [44.0, 300.0], "shrink_amount": 5.0, "move_speed": 1.5, "wander_radius": 20.0, "hazard": true },
]

# Exactly one Dousing Threat per band (per the brief: "exactly one
# recognizable enemy/attack per tier is an instant-kill water hit"), streamed
# sparsely (large cell_size, low density) since these are meant to be rare,
# high-stakes "boss patterns" the player learns to recognize, not ambient
# clutter like Hazards. Active-scale ranges match each threat's own band.
const DOUSING_THREAT_TIERS: Array[Dictionary] = [
	{ "id": "dew_drop", "cell_size": 9.0, "density": 0.02, "active_while_scale_below": 0.1,
	  "zone_radius": 0.18, "telegraph_duration": 1.0, "active_duration": 0.25, "cooldown_duration": 3.0, "dousing": true },
	{ "id": "squirt_bottle", "cell_size": 9.0, "density": 0.02, "active_scale_range": [0.06, 0.35],
	  "zone_radius": 0.4, "telegraph_duration": 0.8, "active_duration": 0.3, "cooldown_duration": 3.5, "dousing": true },
	{ "id": "sprinkler", "cell_size": 9.0, "density": 0.02, "active_scale_range": [0.2, 1.2],
	  "zone_radius": 0.7, "telegraph_duration": 1.5, "active_duration": 0.6, "cooldown_duration": 4.0, "dousing": true },
	{ "id": "garden_hose", "cell_size": 12.0, "density": 0.02, "active_scale_range": [0.5, 3.5],
	  "zone_radius": 1.0, "telegraph_duration": 0.9, "active_duration": 0.3, "cooldown_duration": 3.0, "dousing": true },
	{ "id": "fire_extinguisher", "cell_size": 15.0, "density": 0.02, "active_scale_range": [1.3, 8.0],
	  "zone_radius": 1.8, "telegraph_duration": 1.0, "active_duration": 0.35, "cooldown_duration": 3.5, "dousing": true },
	{ "id": "hose_reel_firefighter", "cell_size": 20.0, "density": 0.02, "active_scale_range": [3.0, 18.0],
	  "zone_radius": 3.0, "telegraph_duration": 1.2, "active_duration": 0.4, "cooldown_duration": 4.0, "dousing": true },
	{ "id": "fire_truck_pumper", "cell_size": 30.0, "density": 0.02, "active_scale_range": [7.0, 44.0],
	  "zone_radius": 6.0, "telegraph_duration": 1.5, "active_duration": 0.5, "cooldown_duration": 4.5, "dousing": true },
	{ "id": "ladder_company", "cell_size": 45.0, "density": 0.02, "active_scale_range": [18.0, 110.0],
	  "zone_radius": 10.0, "telegraph_duration": 1.8, "active_duration": 0.6, "cooldown_duration": 5.0, "dousing": true },
	# "Final confrontation" per the brief -- the aerial water bomber is the
	# last Dousing Threat in the table; no scripted end-of-run sequence is
	# built yet (out of scope for this content pass), it's still just the
	# same telegraph/active/cooldown pattern as every other threat.
	{ "id": "water_bomber", "cell_size": 60.0, "density": 0.02, "active_scale_range": [44.0, 300.0],
	  "zone_radius": 20.0, "telegraph_duration": 2.2, "active_duration": 0.8, "cooldown_duration": 6.0, "dousing": true },
]

var _active: Dictionary = {}          # tier_id -> {Vector3i: Node3D}
var _burned: Dictionary = {}          # tier_id -> {Vector3i: true}
var _last_footprint: Dictionary = {}  # tier_id -> Rect2i
var _all_tiers: Array[Dictionary] = []


func _ready() -> void:
	# Main.tscn assigns these via a hand-authored NodePath literal, which does
	# not auto-resolve into an object reference for a Node-typed @export (that
	# only works via the editor's own drag-and-drop wiring) -- same situation
	# as this studio's snake-3d camera_controller.gd, which re-resolves the
	# same way. Fall back to a relative lookup here too.
	if not flame:
		flame = get_node_or_null("../Flame") as Node3D
	if not camera:
		camera = get_node_or_null("../Flame/CameraPivot/SpringArm3D/Camera3D") as Camera3D
	if not growth_controller:
		growth_controller = get_node_or_null("../GrowthController") as GrowthController
	_all_tiers = PROP_TIERS + STRUCTURE_FUEL_TIERS + HAZARD_TIERS + DOUSING_THREAT_TIERS
	for tier: Dictionary in _all_tiers:
		_active[tier.id] = {}
		_burned[tier.id] = {}
		_last_footprint[tier.id] = Rect2i()


func _process(_delta: float) -> void:
	if not flame or not camera:
		return
	for tier: Dictionary in _all_tiers:
		_update_tier(tier)


# Maps each GrowthController band index to the tier ids (Quick Fuel,
# Structure Fuel, Hazard, and Dousing Threat all together) that should be
# spawning once the flame reaches that band's midpoint scale. Built by
# running the same _should_spawn_detail() gate the real streaming logic
# uses against each band's real-world-meter midpoint (see
# growth_controller.gd's BAND_TABLE) -- not a hand-maintained parallel
# table, so it can never silently drift out of sync with the actual spawn
# thresholds the way the old scale-mismatch bug did. Callable on a bare
# PropManager.new() without _ready() having run (doesn't touch _all_tiers).
func get_epoch_registry() -> Dictionary:
	var all_tiers: Array[Dictionary] = PROP_TIERS + STRUCTURE_FUEL_TIERS + HAZARD_TIERS + DOUSING_THREAT_TIERS
	var registry: Dictionary = {}
	for band_index in range(GrowthController.BAND_TABLE.size()):
		var band: Dictionary = GrowthController.BAND_TABLE[band_index]
		var midpoint: float = (band.scale_min + band.scale_max) / 2.0
		var active_ids: Array[String] = []
		for tier: Dictionary in all_tiers:
			if _should_spawn_detail(tier, midpoint):
				active_ids.append(tier.id)
		registry[band_index] = active_ids
	return registry


func _get_stream_radius() -> float:
	return camera.size * VIEW_SPAN_MARGIN + BASE_PADDING


func _should_spawn_detail(tier: Dictionary, current_scale: float) -> bool:
	if tier.has("active_while_scale_below"):
		return current_scale < tier.active_while_scale_below
	if tier.has("active_scale_range"):
		var r: Array = tier.active_scale_range
		return current_scale >= r[0] and current_scale <= r[1]
	return true


func _update_tier(tier: Dictionary) -> void:
	var tier_id: String = tier.id
	var cell_size: float = tier.cell_size
	var radius_cells: int = maxi(1, ceili(_get_stream_radius() / cell_size))

	var fx: int = floori(flame.global_position.x / cell_size)
	var fz: int = floori(flame.global_position.z / cell_size)
	var bounds := Rect2i(fx - radius_cells, fz - radius_cells, radius_cells * 2 + 1, radius_cells * 2 + 1)

	if bounds == _last_footprint[tier_id] and not (_active[tier_id] as Dictionary).is_empty():
		return
	_last_footprint[tier_id] = bounds

	var spawn_allowed: bool = _should_spawn_detail(tier, flame.scale_factor)
	var needed: Dictionary = {}
	for gx in range(bounds.position.x, bounds.position.x + bounds.size.x):
		for gz in range(bounds.position.y, bounds.position.y + bounds.size.y):
			var key := Vector3i(gx, 0, gz)
			if not _in_parcel(key, cell_size):
				continue
			needed[key] = true
			var active_tier: Dictionary = _active[tier_id]
			var burned_tier: Dictionary = _burned[tier_id]
			if spawn_allowed and not active_tier.has(key) and not burned_tier.has(key):
				if _raw_should_spawn(tier_id, gx, gz, tier.density):
					_spawn_prop(tier, key)

	var to_despawn: Array = []
	var active_tier: Dictionary = _active[tier_id]
	for key: Vector3i in active_tier.keys():
		if not needed.has(key):
			to_despawn.append(key)
	for key: Vector3i in to_despawn:
		_despawn_prop(tier_id, key)


func _in_parcel(key: Vector3i, cell_size: float) -> bool:
	var wx: float = float(key.x) * cell_size
	var wz: float = float(key.z) * cell_size
	return absf(wx) <= PARCEL_HALF_EXTENT and absf(wz) <= PARCEL_HALF_EXTENT


# Deterministic per-cell Bernoulli trial -- same cell always yields the same
# spawn decision regardless of spawn/despawn order, matching floor_manager.gd's
# determinism guarantee for a streamed, regenerable world.
func _raw_should_spawn(tier_id: String, gx: int, gz: int, density: float) -> bool:
	var salt: int = tier_id.hash()
	var h: int = hash(Vector3i(gx * 928371 + salt, 1, gz * 654321 + salt))
	var frac: float = float(absi(h) % 100000) / 100000.0
	return frac < density


func _jitter_for_cell(key: Vector3i, cell_size: float) -> Vector3:
	var h1: int = hash(Vector3i(key.x * 37, 41, key.z * 53))
	var h2: int = hash(Vector3i(key.x * 59, 61, key.z * 67))
	var jx: float = (float(absi(h1) % 1000) / 1000.0 - 0.5) * cell_size * 0.7
	var jz: float = (float(absi(h2) % 1000) / 1000.0 - 0.5) * cell_size * 0.7
	return Vector3(jx, 0.0, jz)


func _spawn_prop(tier: Dictionary, key: Vector3i) -> void:
	if tier.get("dousing", false):
		_spawn_dousing_threat(tier, key)
	elif tier.get("hazard", false):
		_spawn_hazard(tier, key)
	elif tier.get("structure", false):
		_spawn_structure_fuel(tier, key)
	else:
		_spawn_quick_fuel(tier, key)


func _spawn_quick_fuel(tier: Dictionary, key: Vector3i) -> void:
	var cell_size: float = tier.cell_size
	var world_pos: Vector3 = Vector3(float(key.x) * cell_size, 0.0, float(key.z) * cell_size) + _jitter_for_cell(key, cell_size)

	var fuel: Fuel = FuelScript.new()
	fuel.name = "%s_%d_%d" % [tier.id, key.x, key.z]
	fuel.fuel_tier = tier.id
	fuel.charge_value = tier.charge_value
	fuel.cell_key = key
	fuel.position = world_pos
	fuel.ignited.connect(_on_fuel_ignited)

	# add_child() first so Fuel._ready() runs and builds its _visual wrapper
	# + FuelArea before we attach the mesh or start the pop-in tween.
	add_child(fuel)
	fuel.set_visual(_build_prop_visual(tier.id))
	fuel.play_pop_in()

	(_active[tier.id] as Dictionary)[key] = fuel


func _spawn_structure_fuel(tier: Dictionary, key: Vector3i) -> void:
	var cell_size: float = tier.cell_size
	var world_pos: Vector3 = Vector3(float(key.x) * cell_size, 0.0, float(key.z) * cell_size) + _jitter_for_cell(key, cell_size)

	var structure: StructureFuel = StructureFuelScript.new()
	structure.name = "%s_%d_%d" % [tier.id, key.x, key.z]
	structure.fuel_tier = tier.id
	structure.max_health = tier.max_health
	structure.full_charge_value = tier.max_health  # 1 health point == 1 charge point, M2 simplicity
	structure.cell_key = key
	structure.position = world_pos
	structure.fully_burned.connect(_on_structure_fully_burned)

	add_child(structure)
	structure.set_pristine_visual(_build_structure_fuel_visual(tier.id))

	(_active[tier.id] as Dictionary)[key] = structure


func _spawn_hazard(tier: Dictionary, key: Vector3i) -> void:
	var cell_size: float = tier.cell_size
	var world_pos: Vector3 = Vector3(float(key.x) * cell_size, 0.0, float(key.z) * cell_size) + _jitter_for_cell(key, cell_size)

	var hazard: Hazard = HazardScript.new()
	hazard.name = "%s_%d_%d" % [tier.id, key.x, key.z]
	hazard.hazard_tier = tier.id
	hazard.shrink_amount = tier.shrink_amount
	hazard.move_speed = tier.move_speed
	hazard.wander_radius = tier.wander_radius
	hazard.cell_key = key
	hazard.position = world_pos

	add_child(hazard)
	hazard.set_visual(_build_hazard_visual(tier.id))
	hazard.play_pop_in()

	(_active[tier.id] as Dictionary)[key] = hazard


func _spawn_dousing_threat(tier: Dictionary, key: Vector3i) -> void:
	var cell_size: float = tier.cell_size
	var world_pos: Vector3 = Vector3(float(key.x) * cell_size, 0.0, float(key.z) * cell_size) + _jitter_for_cell(key, cell_size)

	var threat: DousingThreat = DousingThreatScript.new()
	threat.name = "%s_%d_%d" % [tier.id, key.x, key.z]
	threat.threat_tier = tier.id
	threat.zone_radius = tier.zone_radius
	threat.telegraph_duration = tier.telegraph_duration
	threat.active_duration = tier.active_duration
	threat.cooldown_duration = tier.cooldown_duration
	threat.cell_key = key
	threat.position = world_pos

	add_child(threat)
	threat.play_pop_in()

	(_active[tier.id] as Dictionary)[key] = threat


# Ignition eligibility (a flame must be big enough for a given fuel type) is
# already enforced by which tiers PropManager is currently spawning -- once
# something exists in the world, touching it always grants its full
# charge_value. No extra runtime gate here; keep it minimal per M1 scope.
func _on_fuel_ignited(fuel: Fuel) -> void:
	mark_burned(fuel.fuel_tier, fuel.cell_key)
	if growth_controller:
		growth_controller.register_burn(fuel.charge_value)


# Per the brief: "Full points are only awarded once its health bar reaches
# zero" -- no partial register_burn() calls happen during the drain itself.
func _on_structure_fully_burned(structure: StructureFuel) -> void:
	mark_burned(structure.fuel_tier, structure.cell_key)
	if growth_controller:
		growth_controller.register_burn(structure.full_charge_value)


func _despawn_prop(tier_id: String, key: Vector3i) -> void:
	var active_tier: Dictionary = _active[tier_id]
	var prop: Node3D = active_tier.get(key, null)
	if prop and is_instance_valid(prop) and prop.has_method("play_despawn"):
		prop.play_despawn()
	active_tier.erase(key)


# Called once fuel.gd's ignite detection lands (task 7) -- marks a cell as
# permanently consumed so a burned prop never respawns when the streaming
# footprint revisits that cell later, mirroring floor_manager.gd's
# destroyed_tiles convention.
func mark_burned(tier_id: String, key: Vector3i) -> void:
	(_burned[tier_id] as Dictionary)[key] = true
	(_active[tier_id] as Dictionary).erase(key)


func _build_prop_visual(tier_id: String) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.85
	match tier_id:
		"dry_grass":
			# Upside-down cone (wide top, pointed base) as a stylized tuft of
			# grass -- top_radius/bottom_radius swapped relative to pine_needle's
			# normal cone below, which is what makes this one read as "upside
			# down": the point sits at the ground, leaves flare out at the top.
			var m := CylinderMesh.new()
			m.top_radius = 0.035
			m.bottom_radius = 0.0
			m.height = 0.16
			mesh_inst.mesh = m
			mesh_inst.position.y = 0.08
			mat.albedo_color = Color(0.3, 0.62, 0.22)
		"twig":
			var m := CylinderMesh.new()
			m.top_radius = 0.02
			m.bottom_radius = 0.03
			m.height = 0.3
			mesh_inst.mesh = m
			mesh_inst.rotation_degrees = Vector3(0, 0, 80)
			mesh_inst.position.y = 0.03
			mat.albedo_color = Color(0.4, 0.28, 0.16)
		"wrapper":
			var m := BoxMesh.new()
			m.size = Vector3(0.12, 0.01, 0.08)
			mesh_inst.mesh = m
			mesh_inst.position.y = 0.01
			mat.albedo_color = Color(0.75, 0.75, 0.8)
			mat.metallic = 0.3
		"leaf_litter":
			var m := BoxMesh.new()
			m.size = Vector3(0.1, 0.015, 0.1)
			mesh_inst.mesh = m
			mesh_inst.position.y = 0.01
			mat.albedo_color = Color(0.55, 0.35, 0.12)
		"small_plant":
			var m := SphereMesh.new()
			m.radius = 0.14
			m.height = 0.28
			mesh_inst.mesh = m
			mesh_inst.position.y = 0.14
			mat.albedo_color = Color(0.25, 0.5, 0.2)
		"pine_needle":
			var m := CylinderMesh.new()
			m.top_radius = 0.0
			m.bottom_radius = 0.03
			m.height = 0.16
			mesh_inst.mesh = m
			mesh_inst.position.y = 0.08
			mat.albedo_color = Color(0.15, 0.35, 0.18)
		"twig_nest":
			var m := TorusMesh.new()
			m.inner_radius = 0.08
			m.outer_radius = 0.16
			mesh_inst.mesh = m
			mesh_inst.rotation_degrees = Vector3(90, 0, 0)
			mesh_inst.position.y = 0.05
			mat.albedo_color = Color(0.38, 0.26, 0.14)
		"brush_pile":
			var m := SphereMesh.new()
			m.radius = 0.4
			m.height = 0.5
			mesh_inst.mesh = m
			mesh_inst.scale = Vector3(1.0, 0.55, 1.0)
			mesh_inst.position.y = 0.14
			mat.albedo_color = Color(0.45, 0.34, 0.16)
			mat.roughness = 0.95
		"dry_shrub":
			var m := SphereMesh.new()
			m.radius = 0.3
			m.height = 0.55
			mesh_inst.mesh = m
			mesh_inst.position.y = 0.28
			mat.albedo_color = Color(0.5, 0.42, 0.18)
		"campfire_log":
			var m := CylinderMesh.new()
			m.top_radius = 0.08
			m.bottom_radius = 0.09
			m.height = 0.6
			mesh_inst.mesh = m
			mesh_inst.rotation_degrees = Vector3(0, 0, 85)
			mesh_inst.position.y = 0.09
			mat.albedo_color = Color(0.38, 0.24, 0.14)
		"kindling_pile":
			var m := SphereMesh.new()
			m.radius = 0.45
			m.height = 0.6
			mesh_inst.mesh = m
			mesh_inst.scale = Vector3(1.0, 0.6, 1.0)
			mesh_inst.position.y = 0.16
			mat.albedo_color = Color(0.42, 0.3, 0.15)
			mat.roughness = 0.95
		"tree_grove":
			var m := SphereMesh.new()
			m.radius = 1.4
			m.height = 2.6
			mesh_inst.mesh = m
			mesh_inst.position.y = 1.6
			mat.albedo_color = Color(0.14, 0.32, 0.13)
		"tree_stand":
			var m := SphereMesh.new()
			m.radius = 2.6
			m.height = 4.8
			mesh_inst.mesh = m
			mesh_inst.position.y = 3.0
			mat.albedo_color = Color(0.12, 0.28, 0.12)
		"forest_section":
			var m := SphereMesh.new()
			m.radius = 9.0
			m.height = 16.0
			mesh_inst.mesh = m
			mesh_inst.position.y = 10.0
			mat.albedo_color = Color(0.1, 0.24, 0.1)
		_:
			var m := BoxMesh.new()
			m.size = Vector3(0.1, 0.1, 0.1)
			mesh_inst.mesh = m
			mat.albedo_color = Color(1, 0, 1)
	mesh_inst.material_override = mat
	return mesh_inst


# Structure Fuel's pristine visual is built the same imperative way as Quick
# Fuel's, but kept separate since StructureFuel.set_pristine_visual() swaps
# whatever material_override is here for the shared dissolve shader material
# (reading its albedo_color first) rather than using it directly.
func _build_structure_fuel_visual(tier_id: String) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.8
	match tier_id:
		"cardboard_box":
			var m := BoxMesh.new()
			m.size = Vector3(0.55, 0.45, 0.4)
			mesh_inst.mesh = m
			mesh_inst.position.y = 0.225
			mat.albedo_color = Color(0.62, 0.48, 0.32)
		"wooden_fence":
			var m := BoxMesh.new()
			m.size = Vector3(2.4, 1.2, 0.08)
			mesh_inst.mesh = m
			mesh_inst.position.y = 0.6
			mat.albedo_color = Color(0.5, 0.36, 0.2)
		"shed":
			var m := BoxMesh.new()
			m.size = Vector3(2.2, 2.0, 2.0)
			mesh_inst.mesh = m
			mesh_inst.position.y = 1.0
			mat.albedo_color = Color(0.55, 0.5, 0.42)
		"car":
			var m := BoxMesh.new()
			m.size = Vector3(1.7, 1.3, 4.2)
			mesh_inst.mesh = m
			mesh_inst.position.y = 0.65
			mat.albedo_color = Color(0.65, 0.15, 0.15)
			mat.metallic = 0.4
		"house":
			var m := BoxMesh.new()
			m.size = Vector3(7.0, 5.0, 8.0)
			mesh_inst.mesh = m
			mesh_inst.position.y = 2.5
			mat.albedo_color = Color(0.72, 0.64, 0.5)
		"city_block":
			var m := BoxMesh.new()
			m.size = Vector3(18.0, 8.0, 14.0)
			mesh_inst.mesh = m
			mesh_inst.position.y = 4.0
			mat.albedo_color = Color(0.5, 0.48, 0.46)
		"neighborhood_block":
			var m := BoxMesh.new()
			m.size = Vector3(35.0, 6.0, 35.0)
			mesh_inst.mesh = m
			mesh_inst.position.y = 3.0
			mat.albedo_color = Color(0.45, 0.42, 0.4)
		"district":
			var m := BoxMesh.new()
			m.size = Vector3(70.0, 10.0, 70.0)
			mesh_inst.mesh = m
			mesh_inst.position.y = 5.0
			mat.albedo_color = Color(0.38, 0.36, 0.34)
		_:
			var m := BoxMesh.new()
			m.size = Vector3(0.3, 0.3, 0.3)
			mesh_inst.mesh = m
			mat.albedo_color = Color(1, 0, 1)
	mesh_inst.material_override = mat
	return mesh_inst


func _build_hazard_visual(tier_id: String) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.6
	match tier_id:
		"ant":
			var m := CapsuleMesh.new()
			m.radius = 0.025
			m.height = 0.08
			mesh_inst.mesh = m
			mesh_inst.rotation_degrees = Vector3(90, 0, 0)
			mesh_inst.position.y = 0.03
			mat.albedo_color = Color(0.08, 0.06, 0.05)
		"fly":
			var m := SphereMesh.new()
			m.radius = 0.02
			m.height = 0.04
			mesh_inst.mesh = m
			mesh_inst.position.y = 0.15
			mat.albedo_color = Color(0.05, 0.05, 0.06)
		"beetle":
			var m := SphereMesh.new()
			m.radius = 0.06
			m.height = 0.09
			mesh_inst.mesh = m
			mesh_inst.scale = Vector3(1.2, 0.7, 1.0)
			mesh_inst.position.y = 0.045
			mat.albedo_color = Color(0.1, 0.25, 0.1)
			mat.metallic = 0.4
		"earthworm":
			var m := CapsuleMesh.new()
			m.radius = 0.02
			m.height = 0.18
			mesh_inst.mesh = m
			mesh_inst.rotation_degrees = Vector3(90, 0, 0)
			mesh_inst.position.y = 0.02
			mat.albedo_color = Color(0.68, 0.42, 0.42)
		"moth":
			var m := BoxMesh.new()
			m.size = Vector3(0.1, 0.01, 0.06)
			mesh_inst.mesh = m
			mesh_inst.position.y = 0.2
			mat.albedo_color = Color(0.72, 0.7, 0.62)
		"bird":
			var m := SphereMesh.new()
			m.radius = 0.14
			m.height = 0.24
			mesh_inst.mesh = m
			mesh_inst.scale = Vector3(1.0, 0.9, 1.4)
			mesh_inst.position.y = 0.16
			mat.albedo_color = Color(0.42, 0.32, 0.2)
		"cat":
			var m := CapsuleMesh.new()
			m.radius = 0.16
			m.height = 0.5
			mesh_inst.mesh = m
			mesh_inst.rotation_degrees = Vector3(90, 0, 0)
			mesh_inst.position.y = 0.18
			mat.albedo_color = Color(0.55, 0.45, 0.3)
		"dog":
			var m := CapsuleMesh.new()
			m.radius = 0.18
			m.height = 0.6
			mesh_inst.mesh = m
			mesh_inst.rotation_degrees = Vector3(90, 0, 0)
			mesh_inst.position.y = 0.22
			mat.albedo_color = Color(0.5, 0.36, 0.2)
		"person_blanket":
			var m := CapsuleMesh.new()
			m.radius = 0.25
			m.height = 1.6
			mesh_inst.mesh = m
			mesh_inst.position.y = 0.8
			mat.albedo_color = Color(0.35, 0.4, 0.6)
		"homeowner":
			var m := CapsuleMesh.new()
			m.radius = 0.28
			m.height = 1.75
			mesh_inst.mesh = m
			mesh_inst.position.y = 0.875
			mat.albedo_color = Color(0.7, 0.5, 0.3)
		"resident":
			var m := CapsuleMesh.new()
			m.radius = 0.28
			m.height = 1.75
			mesh_inst.mesh = m
			mesh_inst.position.y = 0.875
			mat.albedo_color = Color(0.5, 0.35, 0.55)
		"security_guard":
			var m := CapsuleMesh.new()
			m.radius = 0.3
			m.height = 1.8
			mesh_inst.mesh = m
			mesh_inst.position.y = 0.9
			mat.albedo_color = Color(0.15, 0.17, 0.25)
		"first_responder":
			var m := CapsuleMesh.new()
			m.radius = 0.3
			m.height = 1.8
			mesh_inst.mesh = m
			mesh_inst.position.y = 0.9
			mat.albedo_color = Color(0.85, 0.55, 0.05)
			mat.emission_enabled = true
			mat.emission = Color(0.85, 0.55, 0.05)
			mat.emission_energy_multiplier = 0.6
		"fire_crew":
			var m := CapsuleMesh.new()
			m.radius = 0.32
			m.height = 1.85
			mesh_inst.mesh = m
			mesh_inst.position.y = 0.925
			mat.albedo_color = Color(0.8, 0.15, 0.1)
		"evacuee":
			var m := CapsuleMesh.new()
			m.radius = 0.28
			m.height = 1.7
			mesh_inst.mesh = m
			mesh_inst.position.y = 0.85
			mat.albedo_color = Color(0.55, 0.52, 0.48)
		_:
			var m := BoxMesh.new()
			m.size = Vector3(0.1, 0.1, 0.1)
			mesh_inst.mesh = m
			mat.albedo_color = Color(1, 0, 1)
	mesh_inst.material_override = mat
	return mesh_inst
