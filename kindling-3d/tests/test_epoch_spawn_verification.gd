extends SceneTree

# Verifies PropManager's epoch-tracking system (get_epoch_registry()) is both
# internally consistent (right tiers assigned to the right band) and that
# every tier it lists for a band is actually *capable* of spawning during
# that band -- this is the exact class of bug that motivated building the
# registry in the first place (LOD thresholds that looked right on paper but
# silently never triggered against the real flame_scale range after a
# rescale). Deterministic density scan, not live streaming -- avoids
# flakiness from rare/low-density tiers not happening to land in whatever
# small footprint a real playthrough streams within a short test window.

var _failures: int = 0


func _init() -> void:
	_test_registry_structure()
	_test_registry_matches_band_fuel_tiers()
	_test_every_epoch_tier_can_actually_spawn()
	_test_tiers_not_in_epoch_do_not_spawn_there()

	if _failures == 0:
		print("ALL PASS")
	else:
		print("%d FAILURE(S)" % _failures)
	quit(1 if _failures > 0 else 0)


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("FAIL: ", msg)


func _find_tier(tier_id: String) -> Dictionary:
	var all_tiers: Array[Dictionary] = PropManager.PROP_TIERS + PropManager.STRUCTURE_FUEL_TIERS \
		+ PropManager.HAZARD_TIERS + PropManager.DOUSING_THREAT_TIERS
	for tier: Dictionary in all_tiers:
		if tier.id == tier_id:
			return tier
	return {}


func _test_registry_structure() -> void:
	var pm := PropManager.new()
	var registry: Dictionary = pm.get_epoch_registry()
	_assert(registry.size() == GrowthController.BAND_TABLE.size(), "registry should have one entry per band")
	for band_index in range(GrowthController.BAND_TABLE.size()):
		_assert(registry.has(band_index), "registry missing band %d" % band_index)
		_assert((registry[band_index] as Array).size() > 0, "band %d should have at least one active tier" % band_index)


# Cross-check against GrowthController's own fuel_tiers list (the source of
# truth for which fuel is eligible per band per the brief) so the two tables
# -- one driving growth eligibility, one driving world spawn density -- can't
# silently disagree about which band a fuel type belongs to.
func _test_registry_matches_band_fuel_tiers() -> void:
	var pm := PropManager.new()
	var registry: Dictionary = pm.get_epoch_registry()
	for band_index in range(GrowthController.BAND_TABLE.size()):
		var band: Dictionary = GrowthController.BAND_TABLE[band_index]
		var active_ids: Array = registry[band_index]
		for fuel_tier_id in band.fuel_tiers:
			_assert(active_ids.has(fuel_tier_id),
				"Band %d: GrowthController expects fuel '%s' eligible, but PropManager's epoch registry doesn't spawn it there" % [band_index, fuel_tier_id])


func _test_every_epoch_tier_can_actually_spawn() -> void:
	var pm := PropManager.new()
	var registry: Dictionary = pm.get_epoch_registry()
	for band_index in registry.keys():
		for tier_id in registry[band_index] as Array:
			var tier: Dictionary = _find_tier(tier_id)
			_assert(_scan_finds_a_spawn(pm, tier), "Band %d: tier '%s' is listed as active but never spawns across a wide cell scan (density=%s)" % [band_index, tier_id, tier.get("density", "?")])


# Confirms tiers gated OUT of a band actually stay out -- e.g. Band-3-only
# cardboard_box shouldn't be spawnable at Band 1's tiny scale, catching an
# inverted or overlapping threshold.
func _test_tiers_not_in_epoch_do_not_spawn_there() -> void:
	var pm := PropManager.new()
	var registry: Dictionary = pm.get_epoch_registry()
	var all_tiers: Array[Dictionary] = PropManager.PROP_TIERS + PropManager.STRUCTURE_FUEL_TIERS \
		+ PropManager.HAZARD_TIERS + PropManager.DOUSING_THREAT_TIERS
	for band_index in range(GrowthController.BAND_TABLE.size()):
		var band: Dictionary = GrowthController.BAND_TABLE[band_index]
		var midpoint: float = (band.scale_min + band.scale_max) / 2.0
		var active_ids: Array = registry[band_index]
		for tier: Dictionary in all_tiers:
			if not active_ids.has(tier.id):
				_assert(not pm._should_spawn_detail(tier, midpoint),
					"Band %d (scale=%f): tier '%s' not in the epoch registry but _should_spawn_detail says it would spawn" % [band_index, midpoint, tier.id])


# Deterministic: scans a generous cell range rather than relying on live
# streaming placement, so a sparse/rare tier (e.g. cat, density 0.015)
# doesn't produce a flaky failure just because a short real-time test window
# didn't happen to stream through a hit.
func _scan_finds_a_spawn(pm: PropManager, tier: Dictionary) -> bool:
	if tier.is_empty():
		return false
	for gx in range(-60, 60):
		for gz in range(-60, 60):
			if pm._raw_should_spawn(tier.id, gx, gz, tier.density):
				return true
	return false
