class_name GrowthController extends Node

signal charge_changed(current: float, max_value: float)
signal phase_changed(new_phase: Phase)
signal band_changed(new_band_index: int)
signal grow_tick(flame_scale: float)

enum Phase { CHARGE, GROW }

# flame_scale is a REAL-WORLD SIZE IN METERS, not an abstract multiplier --
# project-wide rule: 1 Godot unit = 1 meter (see DESIGN.md). A matchstick
# flame is genuinely ~2cm; a "Small-Medium" band-3 fire is genuinely still
# well under a meter, much smaller than a car or shed (those come at bands
# 5+ per the brief's own tier table). Everything else that reads flame_scale
# (camera zoom, ignite/jump reach, PropManager's scale-gated LOD thresholds)
# must be calibrated against these real units, not treated as unitless.
#
# scale_max of band N is defined to equal the scale at which band N+1's fuel
# becomes the relevant target, so "grow_target points" and "crossing into the
# next band's fuel range" (per the brief) describe the same single trigger.
const BAND_TABLE: Array[Dictionary] = [
	{
		"id": 1, "name": "Match",
		"fuel_tiers": ["twig", "wrapper", "leaf_litter", "dry_grass"],
		"charge_target": 8.0, "grow_target": 24.0,
		"scale_min": 0.02, "scale_max": 0.08,
	},
	{
		"id": 2, "name": "Small Fire",
		"fuel_tiers": ["small_plant", "pine_needle", "twig_nest"],
		"charge_target": 14.0, "grow_target": 40.0,
		"scale_min": 0.08, "scale_max": 0.25,
	},
	{
		"id": 3, "name": "Small-Medium",
		"fuel_tiers": ["brush_pile", "dry_shrub", "cardboard_box"],
		"charge_target": 22.0, "grow_target": 60.0,
		"scale_min": 0.25, "scale_max": 0.6,
	},
	{
		"id": 4, "name": "Medium",
		"fuel_tiers": ["campfire_log", "kindling_pile", "wooden_fence"],
		"charge_target": 32.0, "grow_target": 85.0,
		"scale_min": 0.6, "scale_max": 1.6,
	},
	{
		"id": 5, "name": "Medium-Large",
		"fuel_tiers": ["tree_grove", "shed", "car"],
		"charge_target": 46.0, "grow_target": 120.0,
		"scale_min": 1.6, "scale_max": 4.0,
	},
	{
		"id": 6, "name": "Large",
		"fuel_tiers": ["tree_stand", "house"],
		"charge_target": 65.0, "grow_target": 170.0,
		"scale_min": 4.0, "scale_max": 9.0,
	},
	{
		"id": 7, "name": "Extra-Large",
		"fuel_tiers": ["city_block"],
		"charge_target": 90.0, "grow_target": 230.0,
		"scale_min": 9.0, "scale_max": 22.0,
	},
	{
		"id": 8, "name": "Extra-Extra-Large",
		"fuel_tiers": ["forest_section", "neighborhood_block"],
		"charge_target": 125.0, "grow_target": 310.0,
		"scale_min": 22.0, "scale_max": 55.0,
	},
	{
		"id": 9, "name": "Massive",
		"fuel_tiers": ["district"],
		"charge_target": 170.0, "grow_target": 420.0,
		"scale_min": 55.0, "scale_max": 140.0,
	},
]

var band_index: int = 0
var phase: Phase = Phase.CHARGE
var flame_scale: float = 1.0

var _charge_amount: float = 0.0
var _grow_amount: float = 0.0


func _ready() -> void:
	flame_scale = BAND_TABLE[0].scale_min


func current_band() -> Dictionary:
	return BAND_TABLE[band_index]


# Read-only progress fractions for HUD/feedback code, so consumers don't
# need to reach into _charge_amount/_grow_amount directly.
func charge_progress() -> float:
	var target: float = current_band().charge_target
	return clampf(_charge_amount / target, 0.0, 1.0) if target > 0.0 else 0.0


func grow_progress() -> float:
	var target: float = current_band().grow_target
	return clampf(_grow_amount / target, 0.0, 1.0) if target > 0.0 else 0.0


# Applies a burn value, spilling any overflow across the Charge->Grow
# boundary and across band boundaries within a single call so a large burn
# never silently loses value at a threshold crossing.
func register_burn(value: float) -> void:
	var remaining: float = value
	while remaining > 0.0:
		var band: Dictionary = current_band()
		if phase == Phase.CHARGE:
			var room: float = band.charge_target - _charge_amount
			var applied: float = minf(remaining, room)
			_charge_amount += applied
			remaining -= applied
			charge_changed.emit(_charge_amount, band.charge_target)
			if _charge_amount >= band.charge_target:
				phase = Phase.GROW
				_grow_amount = 0.0
				phase_changed.emit(phase)
		else:
			var room: float = band.grow_target - _grow_amount
			var applied: float = minf(remaining, room)
			_grow_amount += applied
			remaining -= applied
			var t: float = clampf(_grow_amount / band.grow_target, 0.0, 1.0)
			flame_scale = lerpf(band.scale_min, band.scale_max, t)
			grow_tick.emit(flame_scale)
			if _grow_amount >= band.grow_target:
				if not _advance_band():
					remaining = 0.0  # ceiling: no band beyond the table yet, hold here


# Hazard "partial shrink" (see brief's Fail State section): drains Growth
# Points, spilling backward across the Charge/Grow boundary and across band
# boundaries -- the mirror image of register_burn()'s forward spillover.
# Never drops below Band 1's scale_min ("never below match-flame size").
func subtract_growth(amount: float) -> void:
	var remaining: float = amount
	while remaining > 0.0:
		var band: Dictionary = current_band()
		if phase == Phase.GROW:
			var applied: float = minf(remaining, _grow_amount)
			_grow_amount -= applied
			remaining -= applied
			var t: float = clampf(_grow_amount / band.grow_target, 0.0, 1.0) if band.grow_target > 0.0 else 0.0
			flame_scale = lerpf(band.scale_min, band.scale_max, t)
			grow_tick.emit(flame_scale)
			if _grow_amount <= 0.0 and remaining > 0.0:
				if not _retreat_band():
					remaining = 0.0  # floor: already at Band 1, match-flame size
		else:
			var applied: float = minf(remaining, _charge_amount)
			_charge_amount -= applied
			remaining -= applied
			charge_changed.emit(_charge_amount, band.charge_target)
			if _charge_amount <= 0.0 and remaining > 0.0:
				if not _retreat_band():
					remaining = 0.0  # floor: already at Band 1, nothing left to drain


func _advance_band() -> bool:
	if band_index >= BAND_TABLE.size() - 1:
		return false
	band_index += 1
	phase = Phase.CHARGE
	_charge_amount = 0.0
	band_changed.emit(band_index)
	return true


# Drops back into the previous band, landing at the top of its Grow phase
# (grow_amount = its grow_target) -- the exact boundary a forward burn would
# have crossed to reach the band we're retreating from.
func _retreat_band() -> bool:
	if band_index <= 0:
		return false
	band_index -= 1
	phase = Phase.GROW
	_grow_amount = current_band().grow_target
	band_changed.emit(band_index)
	return true
