extends SceneTree

var _failures: int = 0


func _init() -> void:
	_test_charge_accumulates()
	_test_charge_to_grow_transition()
	_test_grow_scales_flame()
	_test_band_advance_resets_charge()
	_test_ceiling_holds_at_last_band()
	_test_overflow_spillover_conserves_value()
	_test_subtract_growth_shrinks_within_band()
	_test_subtract_growth_retreats_band()
	_test_subtract_growth_floors_at_band_one()
	_test_band3_reachable_with_correct_fuel_tiers()

	if _failures == 0:
		print("ALL PASS")
	else:
		print("%d FAILURE(S)" % _failures)
	quit(1 if _failures > 0 else 0)


func _assert(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		print("FAIL: ", msg)


func _assert_almost(a: float, b: float, msg: String) -> void:
	_assert(absf(a - b) < 0.0001, "%s (got %f, expected %f)" % [msg, a, b])


func _new_controller() -> GrowthController:
	var gc := GrowthController.new()
	gc._ready()
	return gc


func _test_charge_accumulates() -> void:
	var gc := _new_controller()
	gc.register_burn(3.0)
	_assert(gc.phase == GrowthController.Phase.CHARGE, "should still be charging below threshold")
	_assert_almost(gc._charge_amount, 3.0, "charge amount should accumulate")
	_assert_almost(gc.flame_scale, 0.02, "flame_scale should not move during Charge")


func _test_charge_to_grow_transition() -> void:
	var gc := _new_controller()
	gc.register_burn(8.0)  # exactly Band 1's charge_target
	_assert(gc.phase == GrowthController.Phase.GROW, "should flip to Grow at exact threshold")


func _test_grow_scales_flame() -> void:
	var gc := _new_controller()
	gc.register_burn(8.0)  # enter Grow
	gc.register_burn(12.0)  # half of Band 1's 24.0 grow_target
	_assert_almost(gc.flame_scale, lerpf(0.02, 0.08, 0.5), "flame_scale should lerp with grow progress")


func _test_band_advance_resets_charge() -> void:
	var gc := _new_controller()
	gc.register_burn(8.0 + 24.0)  # fully clear Band 1's charge + grow
	_assert(gc.band_index == 1, "should advance to Band 2")
	_assert(gc.phase == GrowthController.Phase.CHARGE, "new band should start at Charge")
	_assert_almost(gc._charge_amount, 0.0, "new band's charge should start at zero")
	_assert_almost(gc.flame_scale, 0.08, "flame_scale should equal Band 1's scale_max at handoff")


func _test_ceiling_holds_at_last_band() -> void:
	var gc := _new_controller()
	# Sum every band's charge+grow targets programmatically (not hand-summed)
	# so this test doesn't need updating every time a band is added -- clear
	# every band entirely, then massively overshoot; must not crash or go
	# out of bounds past the table's last entry.
	var total: float = 0.0
	for band: Dictionary in GrowthController.BAND_TABLE:
		total += band.charge_target + band.grow_target
	gc.register_burn(total + 1000.0)
	var last_index: int = GrowthController.BAND_TABLE.size() - 1
	_assert(gc.band_index == last_index, "should hold at last band index, not crash")
	_assert_almost(gc.flame_scale, GrowthController.BAND_TABLE[last_index].scale_max, "flame_scale should hold at last band's scale_max")


func _test_overflow_spillover_conserves_value() -> void:
	var gc := _new_controller()
	# Single burn bigger than charge_target should spill into Grow, not
	# silently drop the excess.
	gc.register_burn(10.0)  # 8.0 fills charge, 2.0 should spill into grow
	_assert(gc.phase == GrowthController.Phase.GROW, "overflow burn should cross into Grow")
	_assert_almost(gc._grow_amount, 2.0, "overflow amount should carry into grow_amount")


func _test_subtract_growth_shrinks_within_band() -> void:
	var gc := _new_controller()
	gc.register_burn(8.0 + 12.0)  # enter Grow, halfway through Band 1
	var before: float = gc.flame_scale
	gc.subtract_growth(6.0)
	_assert(gc.flame_scale < before, "subtract_growth should shrink flame_scale back down")
	_assert(gc.band_index == 0, "a moderate shrink should not cross a band boundary")
	_assert(gc.flame_scale >= 0.02, "flame_scale should never drop below band's scale_min")


func _test_subtract_growth_retreats_band() -> void:
	var gc := _new_controller()
	# Reach partway through Band 2's Grow phase (grow_amount = 10.0 / 40.0).
	gc.register_burn(8.0 + 24.0 + 14.0 + 10.0)
	_assert(gc.band_index == 1, "sanity: should be in Band 2 before the shrink")
	# 10.0 drains Band 2's grow_amount to exactly 0, retreating into Band 1 at
	# its grow_target (the boundary); the leftover 5.0 then keeps draining
	# from that boundary, same spillover-conservation contract as
	# register_burn()'s forward overflow -- final grow_amount = 24.0 - 5.0 = 19.0.
	gc.subtract_growth(10.0 + 5.0)
	_assert(gc.band_index == 0, "a severe shrink should drop back a band")
	_assert(gc.phase == GrowthController.Phase.GROW, "retreat should land in the previous band's Grow phase")
	_assert_almost(gc.flame_scale, lerpf(0.02, 0.08, 19.0 / 24.0), "leftover shrink should keep draining past the retreat boundary, not vanish")


func _test_subtract_growth_floors_at_band_one() -> void:
	var gc := _new_controller()
	gc.register_burn(8.0 + 5.0)  # small way into Band 1's Grow phase
	gc.subtract_growth(1000.0)  # wildly overshoot the floor
	_assert(gc.band_index == 0, "should never retreat below Band 1")
	_assert_almost(gc.flame_scale, 0.02, "should floor at Band 1's scale_min (match-flame size), never below")


func _test_band3_reachable_with_correct_fuel_tiers() -> void:
	var gc := _new_controller()
	gc.register_burn(8.0 + 24.0 + 14.0 + 40.0)  # clear Bands 1 and 2 exactly
	_assert(gc.band_index == 2, "should reach Band 3")
	_assert(gc.current_band().fuel_tiers.has("cardboard_box"), "Band 3 should list cardboard_box as an eligible fuel tier")
	_assert(gc.current_band().fuel_tiers.has("brush_pile"), "Band 3 should list brush_pile as an eligible fuel tier")
