extends "res://scripts/level_surface.gd"

# CANYON shape family -- an open-TOP walled gorge system you fly through, distinct from
# the enclosed CORRIDOR (lethal ceiling, third-person-only) and from open SURFACE (no
# walls). Reuses SURFACE's whole streamed-terrain + prop/enemy/mine/hazard machinery;
# the only thing it changes is the height field.
#
# The floor is carved by 2-3 SEPARATE gorge channels whose centerlines ZIGZAG (sinusoid
# per channel, each a different amplitude / frequency / phase) forward along the flight
# path. Each channel has its own FLOOR HEIGHT; the terrain is the MIN over the channels
# (near any channel = down in a low gorge; between channels = a high ridge/wall). Because
# the centerlines weave at different rates, the lateral gap between channels varies with
# distance and they periodically OVERLAP -- merging into one wide low basin then splitting
# apart again. Streamed seamlessly: the height is a pure function of (x,z), so every tile
# and its lethal trimesh line up. Overriding just _terrain_height reshapes the whole level
# (mesh, collision, normals, and every prop/enemy/pickup Y all dispatch through it).

@export var min_gorges: int = 2
@export var max_gorges: int = 3
@export var gorge_half_frac: float = 0.40    # each channel's half-width = _half_width * this × per-gorge jitter
@export var wall_rise_frac: float = 0.4      # over how much x the wall ramps up (× _half_width)
@export var wall_height: float = 24.0        # world-unit height of the ridges between/around channels

# Rolled channels: each { amp, freq, phase, floor, half }. Lazily rolled on first use
# (needs _half_width, which _setup_terrain sets during start()); reset each start().
var _gorges: Array = []

# CLIFFSIDE mode (iso / 3-4 views): the angled cameras sit above + to one side and would
# clip through the near gorge ridge. In these views the canyon is converted into a CLIFF
# landscape instead -- the gorge walls are dropped (flat-ish floor) so the ONLY vertical
# geometry is the single cliff backdrop on the far side (forced on in LevelSeed._roll_cliff),
# and there's no close wall for the camera to punch through. The gorge terrain is kept for
# the non-angled views (third-person / top-down / side-scroll), where it reads fine.
var _cliffside: bool = false

func _ready() -> void:
	terrain_vertex_spacing = 1.0   # crisper walls + the winding channels want denser verts

func start() -> void:
	_gorges.clear()      # reroll the gorge layout for this level
	_cliffside = current_viewpoint == "isometric" or current_viewpoint == "threequarter"
	super.start()

func _ensure_gorges() -> void:
	if not _gorges.is_empty():
		return
	var r := RandomNumberGenerator.new()
	r.randomize()
	var n: int = r.randi_range(min_gorges, max_gorges)
	var base_half: float = _half_width * gorge_half_frac * level_state.get("gorge_width", 1.0)
	for i in range(n):
		var half: float = base_half * r.randf_range(0.7, 1.15)
		var g := {
			"amp": r.randf_range(5.0, 12.0),        # lateral swing of this channel
			"freq": r.randf_range(0.015, 0.05),     # how fast it zigzags along z
			"phase": r.randf_range(0.0, TAU),
			"floor": r.randf_range(-2.0, 7.0),      # this channel's floor height (varied)
			"half": half,
		}
		if i == 0:
			# Channel 0 is the SAFE SPINE the ship spawns on (x=0): keep its swing strictly
			# inside its own half-width so the straight-ahead line x=0 is ALWAYS in its flat
			# floor, never on a rising wall. It still visibly zigzags, just gently; the other
			# channels swing wide and weave across it.
			g.phase = 0.0
			g.amp = half * r.randf_range(0.2, 0.5)
			g.floor = r.randf_range(-1.0, 1.0)
		_gorges.append(g)

# Lateral centerline of channel g at depth z (the zigzag).
func _gorge_center(g: Dictionary, z: float) -> float:
	return g.amp * sin(z * g.freq + g.phase)

# MIN over the zigzagging channels: near any channel you're in its (low) floor; between
# channels the walls from both sides pile up into a ridge. Ramped in over the safe start.
func _terrain_height(x: float, z: float) -> float:
	if _cliffside:
		return super._terrain_height(x, z)   # cliff landscape: flat-ish floor, NO gorge walls
	_ensure_gorges()
	var floor_noise: float = super._terrain_height(x, z)   # gentle hills+bumps, already ramped
	var ramp: float = smoothstep(0.0, SAFE_START_DIST, -z)
	var rise: float = _half_width * wall_rise_frac
	var best: float = INF
	for g in _gorges:
		var d: float = absf(x - _gorge_center(g, z))
		var wall: float = smoothstep(g.half, g.half + rise, d) * wall_height
		best = minf(best, (g.floor + wall) * ramp)
	return floor_noise + best

# Keep pickups inside a channel: pick one gorge and offset within its half-width around
# its centerline at that z, floating a reachable height above the floor.
func reachable_point(z: float, rng: RandomNumberGenerator) -> Vector3:
	if _cliffside:
		return super.reachable_point(z, rng)   # open floor -> use the surface pickup placement
	_ensure_gorges()
	var g: Dictionary = _gorges[rng.randi_range(0, _gorges.size() - 1)] if not _gorges.is_empty() else {"half": _half_width * gorge_half_frac}
	var cx: float = _gorge_center(g, z) if not _gorges.is_empty() else 0.0
	var half: float = g.get("half", _half_width * gorge_half_frac)
	var x: float = cx + rng.randf_range(-half * 0.6, half * 0.6)
	var y: float = _terrain_height(x, z) + rng.randf_range(1.5, 3.5) * ship.ship_visual_radius
	return Vector3(x, y, z)
