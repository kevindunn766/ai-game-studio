extends SceneTree

var _failures: int = 0


func _init() -> void:
	_test_lod_cutoff_flips()
	_test_lod_range_gates_band2_tiers()
	_test_lod_range_gates_band3_tiers()
	_test_deterministic_spawn_decision()

	if _failures == 0:
		print("ALL PASS")
	else:
		print("%d FAILURE(S)" % _failures)
	quit(1 if _failures > 0 else 0)


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("FAIL: ", msg)


func _grass_tier() -> Dictionary:
	for tier: Dictionary in PropManager.PROP_TIERS:
		if tier.id == "dry_grass":
			return tier
	return {}


func _small_plant_tier() -> Dictionary:
	for tier: Dictionary in PropManager.PROP_TIERS:
		if tier.id == "small_plant":
			return tier
	return {}


func _brush_pile_tier() -> Dictionary:
	for tier: Dictionary in PropManager.PROP_TIERS:
		if tier.id == "brush_pile":
			return tier
	return {}


func _test_lod_cutoff_flips() -> void:
	var pm := PropManager.new()
	var tier := _grass_tier()
	_assert(pm._should_spawn_detail(tier, 0.02), "grass should spawn well below its cutoff")
	_assert(pm._should_spawn_detail(tier, 0.49), "grass should still spawn just under its cutoff")
	_assert(not pm._should_spawn_detail(tier, 0.5), "grass should stop spawning at its cutoff")
	_assert(not pm._should_spawn_detail(tier, 2.0), "grass should stay stopped well above its cutoff")


func _test_lod_range_gates_band2_tiers() -> void:
	var pm := PropManager.new()
	var tier := _small_plant_tier()
	_assert(not pm._should_spawn_detail(tier, 0.02), "small_plant should not spawn before its range starts")
	_assert(pm._should_spawn_detail(tier, 0.15), "small_plant should spawn inside its range")
	_assert(pm._should_spawn_detail(tier, 1.0), "small_plant should still spawn in the widened tail of its range")
	_assert(not pm._should_spawn_detail(tier, 2.0), "small_plant should not spawn past its (widened) range")


func _test_lod_range_gates_band3_tiers() -> void:
	var pm := PropManager.new()
	var tier := _brush_pile_tier()
	_assert(not pm._should_spawn_detail(tier, 0.02), "brush_pile should not spawn at Band 1 scale")
	_assert(pm._should_spawn_detail(tier, 0.4), "brush_pile should spawn inside its Band 3 range")
	_assert(not pm._should_spawn_detail(tier, 8.0), "brush_pile should not spawn well past its (widened) range")


func _test_deterministic_spawn_decision() -> void:
	var pm := PropManager.new()
	# Same cell, tier, and density must always yield the same decision
	# regardless of call order -- no stored per-object RNG state.
	var first: bool = pm._raw_should_spawn("grass", 17, -42, 0.6)
	for i in range(5):
		var again: bool = pm._raw_should_spawn("grass", 17, -42, 0.6)
		_assert(again == first, "spawn decision for a fixed cell must be stable across repeated calls")

	# Sanity: over many cells, the fraction spawned should roughly track density
	# (loose bound, just catching a badly broken hash/threshold).
	var count := 0
	var total := 2000
	for gx in range(total):
		if pm._raw_should_spawn("grass", gx, 0, 0.6):
			count += 1
	var frac: float = float(count) / float(total)
	_assert(frac > 0.5 and frac < 0.7, "spawn fraction should roughly track configured density (got %f)" % frac)
