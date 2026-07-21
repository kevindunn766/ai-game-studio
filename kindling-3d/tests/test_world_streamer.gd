extends SceneTree

# Verifies the treadmill grid streamer + scale-tier gating:
#  - an initial fill covers the window; moving the scroll centre frees cells that leave
#    and builds cells that enter (nearest-first, capped), so the world is endless;
#  - cell contents are deterministic (same layout when a cell streams back);
#  - which object tier spawns is gated by world_scale (grass near full scale, weeds once
#    shrunk, both in the overlap band), and changing the active set rebuilds cells.

const WorldStreamer := preload("res://scripts/world_streamer.gd")

const SPROUT_SIZE := 0.35   # TIERS[0].native_scale
const WEED_SIZE := 2.8      # TIERS[1].native_scale

var _fail: int = 0


func _init() -> void:
	var ws := WorldStreamer.new()
	var root := Node3D.new()
	ws.world_root = root

	# --- Streaming at a shrunk world_scale (large radius -> many cells) ---------------
	ws.start(Vector2.ZERO, 0.13)
	var initial: int = ws.active_cell_count()
	_ok(initial > 20, "initial fill should cover the window (got %d cells)" % initial)
	_ok(ws._cells.has("0,0"), "cell at the scroll centre should exist after fill")

	# Scroll far away: old-centre cells leave the window and are freed; the per-frame cap
	# limits new builds on the first update.
	ws.update_stream(Vector2(400.0, 0.0), 0.13)
	_ok(not ws._cells.has("0,0"), "cell far behind the new centre should be freed")

	for i in range(80):
		ws.update_stream(Vector2(400.0, 0.0), 0.13)
	_ok(ws.active_cell_count() > 20, "window should refill around the new centre (got %d)" % ws.active_cell_count())
	var here_ix: int = int(floor(400.0 / ws.cell_size))
	_ok(ws._cells.has("%d,0" % here_ix), "cell at the new scroll centre should exist")

	# Determinism: a cell re-streamed has the same instance count.
	var before: int = ws.cell_instance_count(here_ix, 0)
	for i in range(60):
		ws.update_stream(Vector2(0.0, 0.0), 0.13)      # leave it
	for i in range(80):
		ws.update_stream(Vector2(400.0, 0.0), 0.13)    # come back
	var after: int = ws.cell_instance_count(here_ix, 0)
	_ok(before == after, "a cell should have the same instance count when it streams back (%d vs %d)" % [before, after])

	# --- Density: on-screen density held constant via world_scale^2 ------------------
	# Current point-giving tier: count falls with the square of world_scale.
	_ok(is_equal_approx(ws._expected_count(0, 1.0), 4.0), "sprout is full density at world_scale 1.0")
	_ok(is_equal_approx(ws._expected_count(0, 0.5), 1.0), "sprout thins as scale^2 (0.5 -> a quarter)")
	_ok(ws._expected_count(0, 1.0) > ws._expected_count(0, 0.5) and ws._expected_count(0, 0.5) > ws._expected_count(0, 0.2), "point-giving density decreases as world_scale decreases")
	# Next tier: super sparse far out, lerps UP to its ready value by its own scale.
	_ok(is_equal_approx(ws._expected_count(1, 1.0), 0.015), "weeds start super sparse at world_scale 1.0")
	_ok(ws._expected_count(1, 1.0) < ws._expected_count(1, 0.5) and ws._expected_count(1, 0.5) < ws._expected_count(1, 0.16), "weeds lerp denser as the player nears their scale")
	_ok(is_equal_approx(ws._expected_count(1, 0.16), 4.0 * 0.16 * 0.16), "weeds reach their ready density at their current scale")

	# Sprouts don't spawn below their band; weeds are present around their scale.
	var ws2 := WorldStreamer.new()
	ws2.world_root = Node3D.new()
	ws2.start(Vector2.ZERO, 1.0)
	_ok(ws2.count_native(SPROUT_SIZE) > 0, "sprouts spawn at world_scale 1.0")

	var ws3 := WorldStreamer.new()
	ws3.world_root = Node3D.new()
	ws3.start(Vector2.ZERO, 0.05)
	_ok(ws3.count_native(SPROUT_SIZE) == 0, "sprouts do NOT spawn below their band (0.05)")

	var ws4 := WorldStreamer.new()
	ws4.world_root = Node3D.new()
	ws4.start(Vector2.ZERO, 0.13)
	_ok(ws4.count_native(WEED_SIZE) > 0, "weeds are present around their scale (0.13)")

	# --- Point-gating: which tier is the current scale (awards points) --------------
	var wsx := WorldStreamer.new()
	_ok(wsx.top_active_tier(1.0) == 0, "near full scale, sprouts are the current scale")
	_ok(wsx.top_active_tier(0.2) == 0, "just above the overlap, still sprouts")
	_ok(wsx.top_active_tier(0.13) == 1, "in the overlap, weeds are the current scale (old sprouts give nothing)")
	_ok(wsx.top_active_tier(0.05) == 1, "well shrunk, weeds are the current scale")
	_ok(wsx.top_active_tier(3.0) == -1, "beyond all tiers, none active")

	# --- Weeds carry a flower (instanced): a flowering record has both stalk + flower MMs --
	var weed: Dictionary = ws4.first_flower_record()
	_ok(not weed.is_empty(), "should have a flowering weed at world_scale 0.13")
	if not weed.is_empty():
		_ok(weed.smm is MultiMesh, "weed record should carry an instanced stalk MultiMesh")
		_ok(weed.fmm is MultiMesh, "weed record should carry an instanced flower MultiMesh")
		_ok(absf(float(weed.native) - WEED_SIZE) < 0.001, "flowering record should be the weed tier")

	print("ALL PASS" if _fail == 0 else "%d FAILURE(S)" % _fail)
	quit(1 if _fail > 0 else 0)


func _ok(c: bool, m: String) -> void:
	if not c:
		_fail += 1
		print("FAIL: ", m)
