extends Node3D

@export var ship_path: NodePath
@export var segment_spacing: float = 10.0
# Camera-visibility streaming window (2026-07-19): build ONLY this far in front of the ship
# (just past the fogged horizon at ~100u + a little off-camera padding) and free everything
# past `build_behind` -- NOT the whole ~200u level. Scenery scales in near the frontier and
# OUT as it recedes, so the tight window's build/free never shows. See StreamWindow.
@export var build_ahead: float = 112.0            # units in front of the ship to build (fog-limited)
@export var build_behind: float = 30.0            # units behind to keep before freeing
@export var fade_ahead: float = 24.0              # scenery scales in over this front margin
@export var fade_behind: float = 18.0             # scenery scales out over this behind margin
@export var lane_half_width: float = 16.0         # lateral scatter band (follows the ship's x)
@export var props_per_density: float = 2.0        # cut from 6 (2026-07-19 perf: dense levels hit ~3700 prop draws)
@export var enemies_per_density: float = 3.0      # restored (Kevin: bring enemy numbers back)
@export var max_active_enemies: int = 12          # generous cap -- still bounds runaway smart-hull spawns
@export var prop_density_scale: float = 1.0       # global multiplier on hazard-prop scatter
@export var terrain_res_z: int = 6                # cliff-face rows along one segment (cliff still strips)
# ENDLESS terrain (2026-07-19): the landscape is a 2D grid of square tiles keyed by
# (ix,iz) that streams in ALL directions around the ship -- tiles spawn as the ship
# approaches them (forward OR laterally) and free when they leave the window in any
# direction -- so the ground extends endlessly no matter which way the player roams,
# instead of the old fixed-width forward strip that showed a hard side edge in the
# angled/overhead views. Tile size + vertex spacing set the mesh/body budget.
@export var terrain_tile_size: float = 32.0       # world-unit square terrain tiles
@export var terrain_vertex_spacing: float = 2.0   # ~world units between terrain verts (canyon lowers for crisp walls)
# Collision LOD: only tiles within this many cells of the ship's cell get a lethal
# trimesh body (a (2N+1)^2 block); distant tiles are visual-only. The ship can only
# ever hit the tile it's over, so this cuts trimesh bodies from the whole grid (~40)
# to ~9 with no gameplay change -- much leaner on low-end devices. 1 => a 3x3 block.
@export var terrain_collision_ring: int = 1
# Feature props + structure features are scattered PER TERRAIN TILE now (not a narrow
# forward lane), so scenery fills the whole visible ground in every direction and
# recycles with its tile -- no more "objects stop at the lane edge while the ground
# keeps going" when you steer wide. Distant-tile scatter is visual-only (collision LOD).
# To keep the flight path as dense as before (gameplay intact) while staying lean,
# density is FULL within a corridor around the ship's path and TAPERS toward the window
# edge (never to zero -> no hard object edge, but far tiles carry few objects).
@export var lane_full_width_mult: float = 1.2   # tiles within this × _half_width of the path keep full (old-lane) density
@export var lane_edge_density: float = 0.035    # floor multiplier far off the path (never 0 -> no hard edge, but sparse)
@export var struct_per_tile: float = 0.5        # expected structure features per FULL-density tile (non-flat structures)
var _scatter_seed: int = 0                       # per-level seed so a tile's scatter is stable across re-entry

const HAZARD_LAYER: int = 4
const StreamWindow := preload("res://scripts/stream_window.gd")
const EnemySpawner := preload("res://scripts/enemy_spawner.gd")
const MineField := preload("res://scripts/mine_field.gd")
const HazardSpawner := preload("res://scripts/hazard_spawner.gd")
const Scatter := preload("res://scripts/scatter.gd")
const Hazard := preload("res://scripts/hazard.gd")
const MeshUtil := preload("res://scripts/mesh_util.gd")
const OCEAN_SHADER := preload("res://shaders/ocean.gdshader")

# Top-down ocean levels render the "floor" as a dead-flat, shader-faked reflective water
# plane instead of the streamed heightmap (Kevin, 2026-07-19 -- "just a flat plane that
# fakes a reflective ocean surface with normals, super light weight"). Gated to top-down
# ocean biomes; every other surface level keeps the rolling heightmap.
const OCEAN_KEYWORDS := ["ocean", "lily-pad", "lily pad"]
var _ocean_flat: bool = false
var _ocean_mat: ShaderMaterial = null

# --- Object planting rules (word-for-word spec) ------------------
# Objects are sunk so the bottom ~1/3 is buried (they never look detached) and
# built a bit LONGER than needed so that buried bottom never shows on a slope.
# Natural props are rotated to the surface normal with a slight random tilt; on a
# near-vertical surface there's a chance they swing back upright, so they read as
# growing OUT of the wall.
const OBJECT_SINK_FRACTION: float = 0.34   # bury ~1/3 of the (elongated) object
const OBJECT_ELONGATE: float = 1.4         # build objects longer than they need to be
const ROT_JITTER: float = 0.14             # slight randomness on the aligned rotation
const VERTICAL_NORMAL_Y: float = 0.5       # normal.y below this reads as a wall
const UPGROW_CHANCE: float = 0.5           # on a wall, chance a plant swings upright

# Hazard-free opening runway (see level_corridor.gd) -- the ship spawns at z=0.
const SAFE_START_DIST: float = 24.0
const MAX_SEGMENTS_PER_FRAME: int = 2   # cap object segments processed per frame (anti-spike)
const MAX_TILES_PER_FRAME: int = 4      # cap terrain tiles built per frame (anti-spike)

@onready var ship: Node3D = get_node(ship_path)

const FEATURE_COLORS := {
	"mushrooms": Color(0.7, 0.3, 0.5, 1.0),
	"rocks": Color(0.5, 0.5, 0.5, 1.0),
	"crystals": Color(0.3, 0.7, 0.9, 1.0),
	"coral": Color(0.9, 0.4, 0.3, 1.0),
	"wreckage": Color(0.4, 0.35, 0.3, 1.0),
	"vents": Color(0.8, 0.5, 0.1, 1.0),
	"spores": Color(0.6, 0.8, 0.3, 1.0),
	"ice spires": Color(0.7, 0.9, 1.0, 1.0),
	"bone piles": Color(0.85, 0.8, 0.7, 1.0),
	"cabling": Color(0.2, 0.2, 0.2, 1.0),
}

var theme: Dictionary = {}
var feature_words: Dictionary = {}
var enemy_words: Dictionary = {}
var mines_density: float = 0.0
var hazards: Dictionary = {}
var current_structure: String = "flat"
var current_viewpoint: String = "thirdperson"
var level_state: Dictionary = {}        # per-level scatter/geometry personality (LevelSeed.roll_state)
var spawned_props: Array = []
var spawned_enemies: Array = []
var spawned_structure_features: Array = []
var next_segment_z: float = 0.0
var segment_index: int = 0
var active: bool = false
# Endless landscape: the "floor" is a streamed heightmap -- rolling hills + finer
# bumps, amplitude/character scaled per structure type + per-level state + theme.
# Height is a pure function _terrain_height(x,z), so adjacent tiles share edges
# seamlessly. Lethal trimesh collision matches the surface. Streamed as a 2D grid
# of tiles keyed by (ix,iz) (see _update_terrain_grid) -- endless in every direction.
var terrain_noise := FastNoiseLite.new()        # rolling hills (low freq)
var terrain_bump_noise := FastNoiseLite.new()   # finer bumps (high freq)
var _terrain_tiles: Dictionary = {}             # "ix,iz" -> [MeshInstance3D, StaticBody3D]
var _tile_res: int = 16                          # per-tile mesh columns/rows (from tile_size / vertex_spacing)
var _half_width: float = 12.0                   # lateral scatter half-width around the ship (props/enemies)
var _amp_hill: float = 1.5
var _amp_bump: float = 0.5
var _floor_color: Color = Color(0.4, 0.4, 0.45)
var foliage_noise := FastNoiseLite.new()   # low-freq patch field (shared by feature-prop scatter)
var scatter_rng := RandomNumberGenerator.new()

# --- Craggy CLIFF backdrop (2026-07-19) ------------------------------------
# A steep craggy cliff on the ship's LEFT (-X), rolled for iso / 3-4 views on
# eligible biomes (and always on the Waterfall/Lava cliff biomes). It's a SEPARATE
# streamed structure -- NOT the heightfield -- so it follows the ship's lateral path
# (each segment sits at the ship's x-at-build minus an offset, exactly like terrain
# strips), reads as a backdrop in the angled cameras, and works the same whether the
# active generator is Surface, Canyon, or Pillared. Lethal trimesh; an optional flow
# (waterfall / lava) streams particles down the face. Foot sits on the terrain.
@export var cliff_dist_frac: float = 1.15    # cliff foot sits this × _half_width left of the ship
@export var cliff_height: float = 26.0       # world-unit height of the cliff face
@export var cliff_res_y: int = 8             # face rows up the height
@export var cliff_craggy_amp: float = 0.4    # jut in/out as a fraction of _half_width
var cliff_enabled: bool = false
var cliff_flow: String = ""                  # "" dry | "water" waterfall | "lava" lava flow
var cliff_height_mult: float = 1.0
var craggy_noise := FastNoiseLite.new()
var spawned_cliff: Array = []                # [MeshInstance3D, StaticBody3D, seg_z]

func configure(rolled_feature_words: Dictionary) -> void:
	feature_words = rolled_feature_words

func configure_enemies(rolled_enemy_words: Dictionary) -> void:
	enemy_words = rolled_enemy_words

func configure_mines(density: float) -> void:
	mines_density = density

func configure_hazards(rolled_hazards: Dictionary) -> void:
	hazards = rolled_hazards

func configure_gravity(_on: bool) -> void:
	pass   # gravity affects open-volume debris only; the surface floor is already lethal

func configure_viewpoint(viewpoint_name: String) -> void:
	current_viewpoint = viewpoint_name   # terrain is an all-directions grid now; no per-view extend needed

func configure_theme(level_theme: Dictionary) -> void:
	theme = level_theme

func _feature_color(word: String) -> Color:
	if theme.has("features") and theme.features.has(word):
		return theme.features[word].color
	return FEATURE_COLORS.get(word, Color(0.6, 0.6, 0.6, 1.0))

func configure_structure(structure_type: String) -> void:
	current_structure = structure_type

func configure_state(state: Dictionary) -> void:
	level_state = state

# Rolled cliff backdrop config (LevelSeed._roll_cliff). Empty / disabled = no cliff.
func configure_cliff(cfg: Dictionary) -> void:
	cliff_enabled = cfg.get("enabled", false)
	cliff_flow = cfg.get("flow", "")
	cliff_height_mult = cfg.get("height_mult", 1.0)

# A navigable pickup point at z: near the lane center, floating a reachable height
# above the (lethal) terrain so the ship can steer to it without hugging the ground.
func reachable_point(z: float, rng: RandomNumberGenerator) -> Vector3:
	var hw: float = _half_width
	var x: float = ship.position.x + rng.randf_range(-hw * 0.5, hw * 0.5)
	var y: float = _terrain_height(x, z) + rng.randf_range(1.5, 3.5) * ship.ship_visual_radius
	return Vector3(x, y, z)

func clear() -> void:
	active = false
	for entry in spawned_props:
		if is_instance_valid(entry[0]):
			entry[0].queue_free()
		if is_instance_valid(entry[1]):
			entry[1].queue_free()
	spawned_props.clear()
	for entry in spawned_enemies:
		if is_instance_valid(entry[0]):
			entry[0].queue_free()
	spawned_enemies.clear()
	for entry in spawned_structure_features:
		if is_instance_valid(entry[0]):
			entry[0].queue_free()
		if is_instance_valid(entry[1]):
			entry[1].queue_free()
	spawned_structure_features.clear()
	for key in _terrain_tiles.keys():
		_free_tile(_terrain_tiles[key])
	_terrain_tiles.clear()
	for entry in spawned_cliff:
		if is_instance_valid(entry[0]):
			entry[0].queue_free()
		if entry[1] != null and is_instance_valid(entry[1]):
			entry[1].queue_free()
	spawned_cliff.clear()
	next_segment_z = 0.0
	segment_index = 0

var _ahead_dist: float = 80.0   # effective build distance in front (perf-scaled in start())

func start() -> void:
	active = true
	_ahead_dist = build_ahead * PerfProfile.view_distance_scale
	_init_scatter()       # randomizes scatter_rng (terrain seeds off it)
	_setup_terrain()
	_update_terrain_grid(0)   # initial terrain fill (uncapped) so the ship never spawns over a hole
	# Initial object fill: only up to the visible window, not the whole level.
	while next_segment_z > -_ahead_dist:
		_spawn_segment()

# Seed the shared scatter RNG + patch noise for this level. Terrain seeding and the
# clustered feature-prop scatter both read these. (The old .png-card foliage system
# was removed 2026-07-18 -- it didn't match the low-poly style; ground detail will be
# added by other processes later.)
func _init_scatter() -> void:
	scatter_rng.randomize()
	_scatter_seed = scatter_rng.randi()                             # per-tile scatter derives from this
	foliage_noise.seed = scatter_rng.randi()
	foliage_noise.frequency = level_state.get("patch_freq", 0.03)   # patch size varies per level
	craggy_noise.seed = scatter_rng.randi()
	craggy_noise.frequency = 0.09                                   # jagged cliff-face relief

# Roll this level's terrain character (amplitudes/frequencies) from the structure
# type, per-level state, and theme. Pure-function height field -> seamless tiles.
func _setup_terrain() -> void:
	terrain_noise.seed = scatter_rng.randi()
	terrain_noise.frequency = 0.035
	terrain_bump_noise.seed = scatter_rng.randi()
	terrain_bump_noise.frequency = 0.14
	# Per-structure profile (world-unit amplitudes): hills, bumps, parabola height.
	var prof: Dictionary = {
		"flat":        {"hill": 0.8, "bump": 0.35, "parab": 2.0},
		"hills":       {"hill": 3.0, "bump": 0.6,  "parab": 3.5},
		"mountains":   {"hill": 6.0, "bump": 1.2,  "parab": 5.0},
		"forest":      {"hill": 1.6, "bump": 0.5,  "parab": 3.0},
		"sun_surface": {"hill": 2.2, "bump": 1.4,  "parab": 3.0},
		"pillared":    {"hill": 1.2, "bump": 0.4,  "parab": 3.0},
		"canyon":      {"hill": 1.0, "bump": 0.4,  "parab": 3.0},  # gentle floor; CANYON adds the walls
	}.get(current_structure, {"hill": 1.5, "bump": 0.5, "parab": 3.0})
	var fs: float = level_state.get("feature_scale", 1.0)
	_amp_hill = prof.hill * fs
	_amp_bump = prof.bump * fs
	_half_width = lane_half_width * maxf(0.5, ship.ship_visual_radius) * level_state.get("lane_width", 1.0)
	_floor_color = theme.get("floor", Color(0.4, 0.4, 0.45))
	# Top-down ocean -> flat reflective water plane (see OCEAN_SHADER). Only base Surface
	# biomes go watery; canyon/pillared never match the ocean keywords.
	_ocean_flat = current_viewpoint == "topdown" and _biome_is_ocean()
	# Per-tile mesh resolution: flat water needs almost none; otherwise keep
	# ~terrain_vertex_spacing world units between verts (canyon lowers it for crisp walls).
	if _ocean_flat:
		_tile_res = 2
	else:
		_tile_res = maxi(2, int(round(terrain_tile_size / maxf(0.5, terrain_vertex_spacing))))

func _biome_is_ocean() -> bool:
	var b: String = theme.get("biome", "").to_lower()
	for kw in OCEAN_KEYWORDS:
		if b.find(kw) != -1:
			return true
	return false

# Shared water-shader material, coloured from the level theme (deep = floor, sky = a
# bright tint of the accent). Built once per level.
func _ocean_material() -> ShaderMaterial:
	if _ocean_mat != null:
		return _ocean_mat
	_ocean_mat = ShaderMaterial.new()
	_ocean_mat.shader = OCEAN_SHADER
	var deep: Color = theme.get("floor", Color(0.05, 0.18, 0.3))
	var sky: Color = theme.get("accent", Color(0.55, 0.75, 0.92)).lightened(0.3)
	_ocean_mat.set_shader_parameter("deep_color", Vector3(deep.r, deep.g, deep.b))
	_ocean_mat.set_shader_parameter("sky_color", Vector3(sky.r, sky.g, sky.b))
	return _ocean_mat

# Height of the "floor" at (x,z): OPEN rolling hills + finer bumps (no lateral valley
# walls anymore -- the terrain now follows the ship and extends unbounded left/right so
# the player can roam), ramped in over the safe start so the ship spawns over flat
# ground. Pure function of (x,z) so adjacent tiles share edges seamlessly.
func _terrain_height(x: float, z: float) -> float:
	if _ocean_flat:
		return 0.0                      # dead-flat water plane; the shader fakes the surface
	var hills: float = terrain_noise.get_noise_2d(x, z) * _amp_hill
	var bumps: float = terrain_bump_noise.get_noise_2d(x, z) * _amp_bump
	var ramp: float = smoothstep(0.0, SAFE_START_DIST, -z)
	return (hills + bumps) * ramp

# Surface normal at (x,z) -- same finite-difference used to shade the terrain mesh.
func _terrain_normal(x: float, z: float) -> Vector3:
	var d: float = 0.5
	var hx: float = _terrain_height(x + d, z) - _terrain_height(x - d, z)
	var hz: float = _terrain_height(x, z + d) - _terrain_height(x, z - d)
	return Vector3(-hx, 2.0 * d, -hz).normalized()

# The up-axis to plant an object on `normal`: aligned to the normal, but on a
# near-vertical surface a random chance swings it back toward world-up (grows OUT of
# the wall), plus a slight random tilt.
func _planted_up(normal: Vector3) -> Vector3:
	var up: Vector3 = normal
	if up.y < VERTICAL_NORMAL_Y and randf() < UPGROW_CHANCE:
		up = up.lerp(Vector3.UP, randf_range(0.55, 0.85)).normalized()
	up = (up + Vector3(randf_range(-ROT_JITTER, ROT_JITTER), 0.0, randf_range(-ROT_JITTER, ROT_JITTER))).normalized()
	return up

# Right-handed basis (det +1 -> winding preserved) with `up` as Y, spun by `yaw`.
func _basis_from_up(up: Vector3, yaw: float) -> Basis:
	var ref: Vector3 = Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD
	var x_axis: Vector3 = ref.cross(up).normalized()
	var z_axis: Vector3 = x_axis.cross(up).normalized()
	return Basis(x_axis, up, z_axis).rotated(up, yaw)

# Established prop-shape dispatch (mirrors level_corridor._prop_mesh) so surface
# props are real procedural meshes instead of boxes.
func _prop_mesh(shape: String, scale: float, seed: float) -> ArrayMesh:
	match shape:
		"mushroom": return LevelGeo.mushroom(scale, seed)
		"crystal": return LevelGeo.crystal(scale, seed)
		"blob": return LevelGeo.blob(scale, seed)
		"vent": return LevelGeo.vent(scale, seed)
		"frond": return LevelGeo.frond(scale, seed)
		"girder": return LevelGeo.girder(scale, seed)
		"stalagmite": return LevelGeo.stalagmite(scale, seed)
		"stalactite": return LevelGeo.stalactite(scale, seed)
		_: return LevelGeo.rock(scale, seed)

func _jitter_color(c: Color) -> Color:
	var j: float = randf_range(-0.06, 0.06)
	return Color(clampf(c.r + j, 0.0, 1.0), clampf(c.g + j, 0.0, 1.0), clampf(c.b + j, 0.0, 1.0))

# Stream the 2D terrain-tile grid around the ship: spawn every tile whose (ix,iz)
# cell falls inside the build window (R ahead/lateral, build_behind behind) and free
# every tile outside it -- in ALL directions, so the ground is endless whichever way
# the ship roams. `cap` limits tiles built this frame (0 = unlimited, for the initial
# fill); when capped, the nearest missing tiles are built first so no hole ever opens
# under the ship. Tiles seam automatically because _terrain_height is a pure function.
func _update_terrain_grid(cap: int) -> void:
	var ts: float = terrain_tile_size
	var r: float = _ahead_dist                       # lateral + forward reach (matches the fog horizon)
	var cx: float = ship.position.x
	var cz: float = ship.position.z
	var ix0: int = int(floor((cx - r) / ts))
	var ix1: int = int(floor((cx + r) / ts))
	var iz_far: int = int(floor((cz - r) / ts))          # ahead is -Z (smaller z)
	var iz_near: int = int(floor((cz + build_behind) / ts))
	# Free tiles that have left the window in any direction.
	for key in _terrain_tiles.keys():
		var parts: PackedStringArray = key.split(",")
		var ix: int = int(parts[0])
		var iz: int = int(parts[1])
		if ix < ix0 or ix > ix1 or iz < iz_far or iz > iz_near:
			_free_tile(_terrain_tiles[key])
			_terrain_tiles.erase(key)
	# Move collision to the tiles near the ship (runs every frame, even if none are missing).
	_reconcile_tile_collision()
	# Collect missing tiles inside the window.
	var missing: Array = []
	for iz in range(iz_far, iz_near + 1):
		for ix in range(ix0, ix1 + 1):
			if not _terrain_tiles.has("%d,%d" % [ix, iz]):
				missing.append(Vector2i(ix, iz))
	if missing.is_empty():
		return
	# Build nearest-first (by tile centre distance to the ship) so visible ground
	# near the player is never the tile that gets deferred by the per-frame cap.
	missing.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var ax: float = (a.x + 0.5) * ts - cx
		var az: float = (a.y + 0.5) * ts - cz
		var bx: float = (b.x + 0.5) * ts - cx
		var bz: float = (b.y + 0.5) * ts - cz
		return ax * ax + az * az < bx * bx + bz * bz)
	var made: int = 0
	for cell in missing:
		_spawn_terrain_tile_at(cell.x, cell.y, ts)
		made += 1
		if cap > 0 and made >= cap:
			return

# One terrain tile covering grid cell (ix,iz). Visual mesh always; a lethal trimesh
# body only if the cell is within the collision ring of the ship (see collision LOD).
func _spawn_terrain_tile_at(ix: int, iz: int, ts: float) -> void:
	# z_near = higher z (behind edge), z_far = lower z (ahead edge) -- same vertex/index
	# ordering the mesh builder has always used, so the face winding stays correct.
	var mesh: Mesh = MeshUtil.flat(_build_terrain_mesh(float(ix) * ts, float(ix + 1) * ts, float(iz + 1) * ts, float(iz) * ts))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if _ocean_flat:
		mi.material_override = _ocean_material()   # shader-faked reflective water
	else:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.roughness = 0.95
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = mat
	add_child(mi)
	var near: bool = _cell_wants_collision(ix, iz, ts)
	var body: StaticBody3D = null
	if near:
		body = _make_tile_body(mesh)
		add_child(body)
	# Scenery (feature props + structure features) that lives ON this tile -- fills the
	# whole ground in every direction, recycles with the tile. Each entry is
	# [visual, body_or_null]; bodies exist only on near tiles (collision LOD).
	var scatter: Array = _populate_tile(ix, iz, ts, near)
	_terrain_tiles["%d,%d" % [ix, iz]] = [mi, body, scatter]

# True if grid cell (ix,iz) is within the ship's collision ring -- these get a lethal
# trimesh body; the rest of the grid is visual-only (the ship can only hit the tile
# it's over, so distant collision is wasted work on low-end devices).
func _cell_wants_collision(ix: int, iz: int, ts: float) -> bool:
	var six: int = int(floor(ship.position.x / ts))
	var siz: int = int(floor(ship.position.z / ts))
	return absi(ix - six) <= terrain_collision_ring and absi(iz - siz) <= terrain_collision_ring

func _make_tile_body(mesh: Mesh) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = HAZARD_LAYER
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()   # verts are world-space; body sits at origin
	body.add_child(cs)
	return body

# Collision LOD: as the ship moves, tiles entering its ring gain a lethal body and
# tiles leaving it drop theirs, so only ~(2*ring+1)^2 trimesh bodies exist at once.
# A tile always gains its body while the ship is still a full cell away (ring >= 1),
# so the ship never reaches a tile before that tile is lethal.
func _reconcile_tile_collision() -> void:
	var ts: float = terrain_tile_size
	for key in _terrain_tiles.keys():
		var parts: PackedStringArray = key.split(",")
		var ix: int = int(parts[0])
		var iz: int = int(parts[1])
		var t: Array = _terrain_tiles[key]
		var wants: bool = _cell_wants_collision(ix, iz, ts)
		# Terrain mesh body.
		var has_body: bool = t[1] != null and is_instance_valid(t[1])
		if wants and not has_body:
			var body := _make_tile_body(t[0].mesh)
			add_child(body)
			t[1] = body
		elif has_body and not wants:
			t[1].queue_free()
			t[1] = null
		# Scenery bodies on this tile follow the same LOD (only lethal when near).
		for e in t[2]:
			var e_has: bool = e[1] != null and is_instance_valid(e[1])
			if wants and not e_has and is_instance_valid(e[0]):
				var eb := Hazard.trimesh_body(e[0].mesh, e[0].transform)
				add_child(eb)
				e[1] = eb
			elif e_has and not wants:
				e[1].queue_free()
				e[1] = null

# Free a tile entry: its mesh, its collision body, and all its scenery (visual + body).
func _free_tile(t: Array) -> void:
	if is_instance_valid(t[0]):
		t[0].queue_free()
	if t[1] != null and is_instance_valid(t[1]):
		t[1].queue_free()
	for e in t[2]:
		if is_instance_valid(e[0]):
			e[0].queue_free()
		if e[1] != null and is_instance_valid(e[1]):
			e[1].queue_free()

func _build_terrain_mesh(x_min: float, x_max: float, z_near: float, z_far: float) -> ArrayMesh:
	var nx: int = _tile_res
	var nz: int = _tile_res
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var d: float = 0.5
	for iz in range(nz + 1):
		var z: float = lerpf(z_near, z_far, float(iz) / float(nz))
		for ix in range(nx + 1):
			var x: float = lerpf(x_min, x_max, float(ix) / float(nx))
			var y: float = _terrain_height(x, z)
			verts.append(Vector3(x, y, z))
			var hx: float = _terrain_height(x + d, z) - _terrain_height(x - d, z)
			var hz: float = _terrain_height(x, z + d) - _terrain_height(x, z - d)
			normals.append(Vector3(-hx, 2.0 * d, -hz).normalized())
			var shade: float = clampf(0.75 + y * 0.04, 0.55, 1.25)   # valleys darker, peaks catch light
			colors.append(Color(_floor_color.r * shade, _floor_color.g * shade, _floor_color.b * shade))
	for iz in range(nz):
		for ix in range(nx):
			var a: int = iz * (nx + 1) + ix
			indices.append_array([a, a + (nx + 1), a + 1, a + 1, a + (nx + 1), a + (nx + 1) + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh

# One craggy cliff-face segment on the ship's LEFT, its foot on the terrain, rising to
# cliff_height (ramped in over the safe start so the spawn stays open). Lethal trimesh.
# Placed at the ship's current x minus an offset, so the whole wall trails the ship's
# lateral path (matching how terrain strips are centered on the ship's x).
func _spawn_cliff_segment() -> void:
	var cx: float = ship.position.x
	var base_x: float = cx - _half_width * cliff_dist_frac
	var seg_center: float = next_segment_z
	var mesh: ArrayMesh = MeshUtil.flat(_build_cliff_mesh(base_x, next_segment_z + segment_spacing * 0.5, next_segment_z - segment_spacing * 0.5))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.96
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # terrain-like; see _spawn_terrain_tile_at
	mi.material_override = mat
	add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = HAZARD_LAYER
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	add_child(body)
	spawned_cliff.append([mi, body, next_segment_z])
	if cliff_flow != "":
		var top_y: float = _terrain_height(base_x, seg_center) + cliff_height * cliff_height_mult * smoothstep(0.0, SAFE_START_DIST, -seg_center)
		_spawn_cliff_flow(base_x, seg_center, top_y)

func _build_cliff_mesh(base_x: float, z_near: float, z_far: float) -> ArrayMesh:
	var nz: int = terrain_res_z
	var ny: int = cliff_res_y
	var amp: float = _half_width * cliff_craggy_amp
	var wall: Color = theme.get("walls", Color(0.5, 0.5, 0.55))
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for iz in range(nz + 1):
		var z: float = lerpf(z_near, z_far, float(iz) / float(nz))
		var ground: float = _terrain_height(base_x, z)
		var ramp: float = smoothstep(0.0, SAFE_START_DIST, -z)
		var h: float = cliff_height * cliff_height_mult * ramp
		for iy in range(ny + 1):
			var t: float = float(iy) / float(ny)
			var y: float = ground + t * h
			# Craggy relief: jut in/out along the face, strongest mid-height.
			var jut: float = craggy_noise.get_noise_2d(z * 1.0, y * 1.0) * amp * (0.4 + 0.6 * sin(t * PI))
			verts.append(Vector3(base_x + jut, y, z))
			normals.append(Vector3.RIGHT)   # replaced by MeshUtil.flat per-face
			var shade: float = clampf(0.55 + t * 0.6, 0.5, 1.2)   # dark foot, lit crest
			colors.append(Color(wall.r * shade, wall.g * shade, wall.b * shade))
	for iz in range(nz):
		for iy in range(ny):
			var a: int = iz * (ny + 1) + iy
			indices.append_array([a, a + (ny + 1), a + 1, a + 1, a + (ny + 1), a + (ny + 1) + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_COLOR] = colors
	arr[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh

# Waterfall / lava particles streaming DOWN the cliff face for this segment. Water
# falls fast + pale; lava creeps + glows. Purely decorative (the push/DOT threat comes
# from the dedicated hazards, per the design). Freed with its cliff segment.
func _spawn_cliff_flow(base_x: float, seg_center: float, top_y: float) -> void:
	var p := CPUParticles3D.new()
	p.position = Vector3(base_x + _half_width * cliff_craggy_amp * 0.4, top_y, seg_center)
	p.emitting = true
	p.one_shot = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.3, 0.6, segment_spacing * 0.5)
	p.direction = Vector3(0, -1, 0)
	p.spread = 6.0
	var acc: Color = theme.get("accent", Color(0.6, 0.8, 1.0))
	if cliff_flow == "lava":
		p.amount = 30
		p.lifetime = 2.4
		p.gravity = Vector3(0, -4.0, 0)
		p.initial_velocity_min = 2.0
		p.initial_velocity_max = 4.0
		p.scale_amount_min = 0.7 * ship.ship_visual_radius
		p.scale_amount_max = 1.5 * ship.ship_visual_radius
		_flow_material(p, Color(1.0, 0.5, 0.12), Color(0.7, 0.12, 0.05), true)
	else:  # water
		p.amount = 46
		p.lifetime = 1.8
		p.gravity = Vector3(0, -16.0, 0)
		p.initial_velocity_min = 3.0
		p.initial_velocity_max = 6.0
		p.scale_amount_min = 0.5 * ship.ship_visual_radius
		p.scale_amount_max = 1.1 * ship.ship_visual_radius
		var pale: Color = acc.lerp(Color(0.95, 0.98, 1.0), 0.7)
		_flow_material(p, pale, pale.darkened(0.25), false)
	add_child(p)
	spawned_cliff.append([p, null, next_segment_z])

func _flow_material(p: CPUParticles3D, top: Color, bottom: Color, glow: bool) -> void:
	var q := QuadMesh.new()
	q.size = Vector2(1.0 * ship.ship_visual_radius, 1.6 * ship.ship_visual_radius)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	if glow:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	q.material = mat
	p.mesh = q
	p.color = top
	var g := Gradient.new()
	g.set_color(0, Color(top.r, top.g, top.b, 0.9))
	g.set_color(1, Color(bottom.r, bottom.g, bottom.b, 0.0))
	p.color_ramp = g

func _recycle_old_cliff() -> void:
	var behind_distance: float = build_behind
	var i: int = 0
	while i < spawned_cliff.size():
		if spawned_cliff[i][2] > ship.position.z + behind_distance:
			if is_instance_valid(spawned_cliff[i][0]):
				spawned_cliff[i][0].queue_free()
			if spawned_cliff[i][1] != null and is_instance_valid(spawned_cliff[i][1]):
				spawned_cliff[i][1].queue_free()
			spawned_cliff.remove_at(i)
		else:
			i += 1

func _process(_delta: float) -> void:
	if not active:
		return
	# Share the ship position so the grass shader can gust when the ship passes.
	RenderingServer.global_shader_parameter_set("frond_player_pos", ship.global_position)
	# Cap segments built per frame so a hitch never spikes (each strip is wider now).
	var made: int = 0
	while next_segment_z > ship.position.z - _ahead_dist and made < MAX_SEGMENTS_PER_FRAME:
		_spawn_segment()
		made += 1
	_update_terrain_grid(MAX_TILES_PER_FRAME)   # stream terrain tiles in all directions
	_recycle_old_props()
	_recycle_old_enemies()
	_recycle_old_structure_features()
	_recycle_old_cliff()
	_apply_camera_cull()

# Camera-distance cull for the DEEP views (third-person / 3-4), where the landscape runs
# far back: every tile's scenery + enemies scale DOWN as they recede from the camera and
# are hidden (culled) before the fogged horizon, so a whole field of props doesn't draw
# into the distance. No-op in the orthographic / side views (they frame a bounded area).
func _apply_camera_cull() -> void:
	if current_viewpoint != "thirdperson" and current_viewpoint != "threequarter":
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp: Vector3 = cam.global_position
	var cb: float = _ahead_dist * StreamWindow.CULL_BEGIN_FRAC
	var ce: float = _ahead_dist * StreamWindow.CULL_END_FRAC
	for key in _terrain_tiles.keys():
		for e in _terrain_tiles[key][2]:
			StreamWindow.apply(e[0], 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, cp, cb, ce)
	# Enemies own a CollisionShape3D -> HIDE (not scale) past the cull distance, or Godot
	# spams "det == 0" from inverting a zero-scale transform (studio-noted gotcha).
	for e in spawned_enemies:
		if is_instance_valid(e[0]):
			StreamWindow.cull(e[0], cp, cb, ce)

func _spawn_segment() -> void:
	var half_width: float = _half_width
	if cliff_enabled:
		_spawn_cliff_segment()
	# Feature props + structure features are scattered per terrain tile now (see
	# _populate_tile), so they fill the whole ground and recycle in all directions.
	# The per-segment loop still streams the sparse moving threats along the flight
	# path (enemies / mines / slow-damage hazards), kept out of the opening runway.
	if next_segment_z <= -SAFE_START_DIST:
		_spawn_enemies(half_width)
		_spawn_mines()
		_spawn_hazards()
	segment_index += 1
	next_segment_z -= segment_spacing

func _tile_seed(ix: int, iz: int) -> int:
	return hash(Vector3i(ix, iz, _scatter_seed))

# Everything that lives ON a terrain tile: feature-word props (lethal hazards) + the
# structure-type dressing. Scattered across the tile's own footprint with a per-tile
# seed (stable across re-entry), so scenery fills the ground in every direction and is
# freed with the tile. Skips tiles touching the hazard-free opening runway. `near`
# decides whether the props get a lethal body now (collision LOD -- distant = visual).
func _populate_tile(ix: int, iz: int, ts: float, near: bool) -> Array:
	var out: Array = []
	var z0: float = float(iz) * ts
	var z1: float = float(iz + 1) * ts
	# Ship spawns at z=0 flying to -z; keep the opening runway (and anything at/behind
	# spawn) clear. A tile whose nearer (larger-z) edge is inside the runway is skipped.
	if z1 > -SAFE_START_DIST:
		return out
	var x0: float = float(ix) * ts
	var x1: float = float(ix + 1) * ts
	var rng := RandomNumberGenerator.new()
	rng.seed = _tile_seed(ix, iz)
	# Density is full along the flight path and tapers toward the window edge.
	var dm: float = _lane_density_mult((x0 + x1) * 0.5)
	_scatter_tile_props(x0, x1, z0, z1, rng, near, dm, out)
	if current_structure != "flat" and not _ocean_flat:
		_scatter_tile_structures(ix, iz, x0, x1, z0, z1, rng, near, dm, out)
	return out

# Lateral density multiplier for a tile whose centre x is tile_cx: 1.0 within a
# corridor around the ship's current x (flight path stays as dense as the old lane),
# tapering to lane_edge_density out at the window edge -- so distant scenery still
# exists (no hard edge) but is sparse (lean).
func _lane_density_mult(tile_cx: float) -> float:
	var lane_d: float = absf(tile_cx - ship.position.x)
	var corridor: float = _half_width * lane_full_width_mult
	if lane_d <= corridor:
		return 1.0
	# Quadratic falloff past the corridor: density ~ 1/(1+e^2) so the count per lateral
	# ring stays roughly flat (far rings have far more tiles), keeping the total bounded
	# while the flight path stays full-density. Floored so distant scenery never vanishes.
	var excess: float = (lane_d - corridor) / corridor
	return maxf(lane_edge_density, 1.0 / (1.0 + excess * excess))

# Feature-word props (LETHAL hazards) patch-scattered across a tile with clump + scale
# falloff. `density_mult` (1.0 on the flight path, tapering out) keeps the full-window
# fill from exploding the object count while the corridor stays as dense as before.
func _scatter_tile_props(x0: float, x1: float, z0: float, z1: float, rng: RandomNumberGenerator, near: bool, density_mult: float, out: Array) -> void:
	var st_density: float = level_state.get("density", 1.0)
	var st_scale: float = level_state.get("feature_scale", 1.0)
	var st_clump: float = level_state.get("clumpiness", 0.45) - 0.45
	for word in feature_words.keys():
		var density: float = feature_words[word]
		var dens: float = density * props_per_density * 0.05 * prop_density_scale * st_density * density_mult
		var pts: Array = Scatter.patch(rng, foliage_noise, x0, x1, z0, z1,
			dens, clampf(0.42 + st_clump, 0.05, 0.9), 0.28, 0.35 * st_scale, 1.05 * st_scale, float(hash(word) % 1000), 500.0)
		var shape: String = "rock"
		if theme.has("features") and theme.features.has(word):
			shape = theme.features[word].get("shape", "rock")
		var col: Color = _feature_color(word)
		for p in pts:
			var prop_scale: float = ship.ship_visual_radius * p.scale
			# Real procedural mesh (established LevelGeo generators), not a box.
			var mesh: ArrayMesh = MeshUtil.flat(_prop_mesh(shape, prop_scale, rng.randf() * 900.0))
			var prop := MeshInstance3D.new()
			prop.mesh = mesh
			var material := StandardMaterial3D.new()
			material.albedo_color = _jitter_color(col)
			material.roughness = 0.9
			prop.material_override = material
			var surf := Vector3(p.pos.x, _terrain_height(p.pos.x, p.pos.z), p.pos.z)
			var up := _planted_up(_terrain_normal(p.pos.x, p.pos.z))   # rotate to normal (+ jitter, + wall up-grow)
			var basis := _basis_from_up(up, rng.randf() * TAU)
			# Elongate along the up-axis and jitter the others; sink the bottom third.
			basis = basis.scaled(Vector3(rng.randf_range(0.85, 1.15), OBJECT_ELONGATE * rng.randf_range(0.9, 1.15), rng.randf_range(0.85, 1.15)))
			var gp := surf - up * (prop_scale * OBJECT_SINK_FRACTION)
			prop.transform = Transform3D(basis, gp)
			add_child(prop)
			var prop_body: StaticBody3D = null
			if near:
				prop_body = Hazard.trimesh_body(mesh, prop.transform)
				add_child(prop_body)
			out.append([prop, prop_body])

# Structure-type dressing scattered across a tile (mounds / peaks / trunks / columns
# -- one profile per structure so each reads as distinct terrain). Base places up to
# `struct_per_tile` (expected) features; subclasses (pillared) override for a cluster.
func _scatter_tile_structures(ix: int, iz: int, x0: float, x1: float, z0: float, z1: float, rng: RandomNumberGenerator, near: bool, density_mult: float, out: Array) -> void:
	var expected: float = struct_per_tile * density_mult
	while expected > 0.0:
		if expected < 1.0 and rng.randf() > expected:
			break
		_place_one_structure(x0, x1, z0, z1, rng, near, out)
		expected -= 1.0

# One structure-type feature somewhere in the tile, sitting on the terrain. Primitive
# mesh (sphere/cone/cylinder) + matching trimesh body (only when `near`, collision LOD).
func _place_one_structure(x0: float, x1: float, z0: float, z1: float, rng: RandomNumberGenerator, near: bool, out: Array) -> void:
	var lane_x: float = rng.randf_range(x0, x1)
	var z: float = rng.randf_range(z0, z1)
	var gy: float = _terrain_height(lane_x, z)   # sit on the terrain surface
	var mesh: Mesh
	var color: Color
	var center_y: float

	match current_structure:
		"hills":
			var mound_radius: float = ship.ship_visual_radius * rng.randf_range(1.5, 3.0)
			mesh = _sphere_mesh(mound_radius)
			color = Color(0.45, 0.55, 0.3, 1.0)
			center_y = mound_radius * 0.3
		"mountains":
			var peak_radius: float = ship.ship_visual_radius * rng.randf_range(0.8, 1.4)
			var peak_height: float = ship.ship_visual_radius * rng.randf_range(4.0, 7.0)
			mesh = _cylinder_mesh(0.0, peak_radius, peak_height)   # cone
			color = Color(0.5, 0.48, 0.45, 1.0)
			center_y = peak_height * 0.5
		"forest":
			var trunk_radius: float = ship.ship_visual_radius * 0.25
			var trunk_height: float = ship.ship_visual_radius * rng.randf_range(2.5, 4.5)
			mesh = _cylinder_mesh(trunk_radius, trunk_radius, trunk_height)
			color = Color(0.25, 0.5, 0.25, 1.0)
			center_y = trunk_height * 0.5
		"sun_surface":
			var pillar_radius: float = ship.ship_visual_radius * 0.3
			var pillar_height: float = ship.ship_visual_radius * rng.randf_range(2.0, 5.0)
			mesh = _cylinder_mesh(pillar_radius, pillar_radius, pillar_height)
			color = Color(1.0, 0.6, 0.1, 1.0)
			center_y = pillar_height * 0.5
		"pillared":
			var col_radius: float = ship.ship_visual_radius * 0.6
			var col_height: float = ship.ship_visual_radius * 6.0
			mesh = _cylinder_mesh(col_radius, col_radius, col_height)
			color = Color(0.6, 0.6, 0.65, 1.0)
			center_y = col_height * 0.5
		_:
			return

	var pos := Vector3(lane_x, gy + center_y, z)
	var visual := MeshInstance3D.new()
	visual.mesh = MeshUtil.flat(mesh)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	visual.material_override = material
	visual.position = pos
	add_child(visual)
	var body: StaticBody3D = null
	if near:
		body = Hazard.trimesh_body(visual.mesh, visual.transform)
		add_child(body)
	out.append([visual, body])

func _sphere_mesh(radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	return m

func _cylinder_mesh(top_radius: float, bottom_radius: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top_radius
	m.bottom_radius = bottom_radius
	m.height = height
	return m

func _spawn_enemies(half_width: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for kind in enemy_words.keys():
		var density: float = enemy_words[kind]
		var count: int = int(round(density * enemies_per_density))
		for i in range(count):
			if spawned_enemies.size() >= max_active_enemies:
				return                                       # cap concurrent moving threats
			var enemy_scale: float = ship.ship_visual_radius
			var ex: float = ship.position.x + randf_range(-half_width * 0.7, half_width * 0.7)
			var ez: float = next_segment_z + randf_range(-segment_spacing * 0.3, segment_spacing * 0.3)
			# Float a clear margin above the lethal terrain so they read as flyers.
			var ey: float = _terrain_height(ex, ez) + randf_range(2.5, 5.0) * ship.ship_visual_radius
			var enemy: Area3D = EnemySpawner.create(kind, ship, theme, feature_words, enemy_scale, rng)
			enemy.world = self
			add_child(enemy)
			enemy.position = Vector3(ex, ey, ez)
			if enemy.has_method("post_spawn"):
				enemy.post_spawn()
			spawned_enemies.append([enemy, next_segment_z])

func _recycle_old_props() -> void:
	var behind_distance: float = build_behind
	var i: int = 0
	while i < spawned_props.size():
		if spawned_props[i][2] > ship.position.z + behind_distance:
			spawned_props[i][0].queue_free()
			spawned_props[i][1].queue_free()
			spawned_props.remove_at(i)
		else:
			i += 1

func _recycle_old_enemies() -> void:
	var behind_distance: float = build_behind
	var i: int = 0
	while i < spawned_enemies.size():
		var e = spawned_enemies[i][0]
		if not is_instance_valid(e):        # self-freed on death / mine detonation
			spawned_enemies.remove_at(i)
		elif spawned_enemies[i][1] > ship.position.z + behind_distance:
			e.queue_free()
			spawned_enemies.remove_at(i)
		else:
			i += 1

# Occasionally lay a mine formation (line / ring / diamond) above the terrain.
func _spawn_mines() -> void:
	if mines_density <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if rng.randf() > mines_density:
		return
	var z: float = next_segment_z + rng.randf_range(-segment_spacing * 0.3, segment_spacing * 0.3)
	var center: Vector3 = reachable_point(z, rng)
	for m in MineField.build(center, ship.ship_visual_radius, theme, ship, self, rng):
		spawned_enemies.append([m, next_segment_z])

# Slow-damage hazards on the landscape: fields drift above the terrain, leeches
# leap up from the ground, graspers root in the terrain.
func _spawn_hazards() -> void:
	if hazards.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var sc: float = ship.ship_visual_radius
	for kind in hazards.keys():
		if rng.randf() > hazards[kind]:
			continue
		var z: float = next_segment_z + rng.randf_range(-segment_spacing * 0.3, segment_spacing * 0.3)
		var x: float = ship.position.x + rng.randf_range(-_half_width * 0.6, _half_width * 0.6)
		var pos: Vector3
		var opts: Dictionary = {}
		match kind:
			"leech":
				pos = Vector3(x, _terrain_height(x, z), z)
				opts = {"mode": "leap"}
			"grasper", "turret", "push":
				pos = Vector3(x, _terrain_height(x, z), z)
			"waterfall", "lava":
				# Root these at the cliff base (the flow comes down the cliff) when there
				# is one; otherwise on the terrain in the lane.
				var hx: float = x
				if cliff_enabled:
					hx = ship.position.x - _half_width * cliff_dist_frac + _half_width * 0.2
				pos = Vector3(hx, _terrain_height(hx, z), z)
			_:
				pos = reachable_point(z, rng)
		var h: Node3D = HazardSpawner.create(kind, ship, theme, sc, opts, rng)
		if h == null:
			continue
		if "world" in h:                     # enemy_base hazards need it for the death VFX
			h.world = self
		add_child(h)
		h.position = pos
		if h.has_method("post_spawn"):
			h.post_spawn()
		spawned_enemies.append([h, next_segment_z])

func _recycle_old_structure_features() -> void:
	var behind_distance: float = build_behind
	var i: int = 0
	while i < spawned_structure_features.size():
		if spawned_structure_features[i][2] > ship.position.z + behind_distance:
			spawned_structure_features[i][0].queue_free()
			spawned_structure_features[i][1].queue_free()
			spawned_structure_features.remove_at(i)
		else:
			i += 1
