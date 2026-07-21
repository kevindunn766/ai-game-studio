extends Node

# Level streaming (Chimera Drift's grid-streamer approach) for Kindling's TREADMILL +
# SCALE-VOYAGE world. The world is a 2D grid of square cells keyed by (ix, iz), streamed
# in/out of a window around the scroll centre, nearest-first, capped per frame,
# deterministic per-cell scatter (a cell looks identical every time it streams back).
#
# SCALE VOYAGE: the player burns their way through LAYERS of ever-larger objects. Which
# object tiers spawn is gated by the current `world_scale` (the world-size number that
# main.gd also scales the whole world by). As the player burns, world_scale shrinks; a
# tiny "layer 1" tier (grass) fades out and a bigger "layer 2" tier (weeds) fades in,
# with an overlap band so the handoff is smooth. This is one transition -- the template
# for the rest.
#
# INSTANCED ON THE TESSELLATION: each cell's plants are drawn with MultiMeshInstance3D
# (one MultiMesh per cell / tier / mesh-variant, GPU-instanced) instead of one node per
# plant, and sit on the tessellated ground (they sample the shared height field so their
# bases match the ground shader's displacement). Because the instances are not nodes, they
# carry no Area3D -- burning is a distance check against the fixed flame at the origin
# (see process_burn), and per-instance burn state rides in each instance's CUSTOM data.
#
# COVERAGE tracks zoom: build_radius is derived from world_scale so the streamed window
# always covers roughly the visible area (the world renders at world_scale, so a smaller
# world_scale needs a larger content-space radius to fill the screen).

const Frond := preload("res://scripts/frond.gd")
const PlantShader := preload("res://shaders/plant.gdshader")
const CardShader := preload("res://shaders/grass_card.gdshader")

# The burn-mark PNG, painted (via decal) onto un-burnable items where the flame brushes them.
const BURN_MARK_TEXTURE: Texture2D = preload("res://assets/marks/burn_mark.png")

# Reference per-cell count a tier has WHEN IT IS THE CURRENT (point-giving) tier at its
# own scale. On-screen density is held constant by scaling the content count with
# world_scale^2 (see _expected_count), so the field never packs tighter on screen as the
# world shrinks -- and each new tier reads exactly as dense as tier 1 did at the start.
const REFERENCE_PER_CELL: float = 4.0
# How sparse the NEXT tier starts while it's still too big to burn (the odd giant one in
# the distance). It lerps up to its ready value as the player burns through the current tier.
const FLOWER_SPARSE: float = 0.015

# Burn feedback timing (was main.gd's HIT_SQUASH_TIME / char rate; now applied per instance).
const HIT_SQUASH_TIME: float = 0.15     # seconds to squash a burnt plant's height to 10%

# --- Object tiers (the scale layers). native_scale is the Frond build scale in content
# units (BEFORE world_scale). A tier spawns while world_scale is inside [scale_lo, scale_hi]
# (or always, if always_spawn). current_scale is the world_scale at which the tier becomes
# the player's current (point-giving) scale -- density references this.
const TIERS: Array = [
	{   # Layer 1 -- mini plants: grass / sprouts. Current from the start (world_scale 1.0).
		"id": "sprout",
		"native_scale": 0.35,
		"scale_lo": 0.11, "scale_hi": 2.0,
		"current_scale": 1.0,
		"color": Color(0.36, 0.62, 0.22),
	},
	{   # Layer 2 -- bigger plants: weeds. ~8x the native size; current around world_scale
		# 0.16. Present the whole time (always_spawn) but sparse until then; each wears a
		# bright FLOWER so you can tell the moment you enter this scale.
		"id": "weed",
		"native_scale": 2.8,
		"scale_lo": 0.0, "scale_hi": 0.16,
		"current_scale": 0.16,
		"always_spawn": true,
		"color": Color(0.30, 0.50, 0.20),
		"flower": true,
		"flower_color": Color(0.97, 0.80, 0.22),
	},
	{   # Layer 3 -- medium weed: a butterfly-weed clump (splayed stems + orange flower umbels).
		# Current around world_scale 0.026 (one 6x step past the small weed).
		"id": "butterfly_weed",
		"builder": "butterfly_weed",
		"native_scale": 17.0,
		"scale_lo": 0.0, "scale_hi": 0.026,
		"current_scale": 0.026,
		"always_spawn": true,
		"color": Color(0.28, 0.50, 0.19),           # stem green
		"flower": true,
		"flower_color": Color(0.93, 0.42, 0.06),    # butterfly-weed orange
	},
	{   # Layer 4 -- large weed: Queen Anne's Lace (tall thin stems + flat white lacy umbels).
		"id": "queen_annes_lace",
		"builder": "queen_annes_lace",
		"native_scale": 106.0,
		"scale_lo": 0.0, "scale_hi": 0.0042,
		"current_scale": 0.0042,
		"always_spawn": true,
		"color": Color(0.30, 0.50, 0.19),           # stem green
		"flower": true,
		"flower_color": Color(0.95, 0.95, 0.90),    # lacy white
	},
	{   # Layer 5 -- bush: woody bifurcating twig skeleton + dark-green oval leaves at the tips.
		"id": "bush",
		"builder": "bush",
		"native_scale": 660.0,
		"scale_lo": 0.0, "scale_hi": 0.00068,
		"current_scale": 0.00068,
		"always_spawn": true,
		"color": Color(0.34, 0.23, 0.13),           # woody brown branches
		"flower": true,
		"flower_color": Color(0.11, 0.27, 0.10),    # dark-green leaves
	},
]

const POOL_PER_TIER: int = 6                  # distinct frond meshes reused per tier

# Decorative grass-CARD filler (textured crossed quads, MultiMesh-instanced) scattered
# densely at sprout scale to make the ground read lush. Purely visual -- not burnable, not
# tracked as an instance -- the frond sprouts remain the fuel. Fades out (stops spawning)
# once the flame outgrows the sprout tier, same as the sprouts themselves.
const GRASS_CARD_VARIANTS: int = 3            # distinct card textures (assets/grass/grass_card_*.png)
const CARD_REFERENCE_PER_CELL: float = 26.0   # dense filler count per cell at world_scale 1.0
const CARD_HEIGHT: float = 0.42               # content units tall (a lush tuft, ~sprout scale)
const CARD_WIDTH: float = 0.40                # content units wide
const CARD_BLACK_TIME: float = 0.18           # a touched card fades to black over this
const CARD_GREY_TIME: float = 0.35            # then black -> grey ash over this

@export var cell_size: float = 3.0            # content-space cell edge (fixed grid)
@export var view_margin: float = 2.2          # build well past the visible area
@export var min_radius: float = 6.0
@export var max_radius: float = 48.0
@export var camera_view: float = 2.5          # ~ortho size the world is framed at (render units)
@export var max_cells_per_frame: int = 8      # anti-spike build cap (0 = unlimited)

var world_root: Node3D = null                 # content parent; main.gd scrolls + scales this
var height_field: RefCounted = null           # GroundHeight -- so plants sit on the ground surface

var _cells: Dictionary = {}                   # "ix,iz" -> Node3D (cell root)
var _cell_instances: Dictionary = {}          # "ix,iz" -> Array[instance-record]
var _burning: Array = []                       # instance-records mid squash-to-ash animation
var _seed: int = 0
var _active_sig: String = ""                  # which tiers are currently spawning
var _cur_scale: float = 1.0                    # world_scale of the current stream pass
var _pools: Dictionary = {}                   # tier id -> Array[{mesh, tip}]
var _mats: Dictionary = {}                    # tier id -> ShaderMaterial (stalk, shared)
var _flower_pools: Dictionary = {}            # tier id -> Array[ArrayMesh] (flower heads)
var _flower_mats: Dictionary = {}             # tier id -> ShaderMaterial (flower, shared)
var _card_mesh: ArrayMesh = null              # shared crossed-quad card mesh (built once)
var _card_mats: Array = []                    # one ShaderMaterial per card variant
var _card_instances: Dictionary = {}          # cell_key -> Array[card burn-record]
var _card_burning: Array = []                 # card records mid black->grey fade


func start(scroll: Vector2, world_scale: float = 1.0) -> void:
	_seed = randi()
	update_stream(scroll, world_scale, 0)     # initial fill uncapped -- no hole under the player


func _radius_for(world_scale: float) -> float:
	return clampf(camera_view * view_margin / maxf(world_scale, 0.0001), min_radius, max_radius)


# Largest object reach in content units -- the free window is padded by this so on-screen
# objects (big flowers) aren't culled while a corner of them is still visible.
func _max_native() -> float:
	var m: float = 0.0
	for t in TIERS:
		m = maxf(m, float(t.native_scale))
	return m


# Free cells outside the window, build missing cells inside it (nearest-first, capped).
# When the set of active tiers changes (a layer transition), all cells are freed so they
# rebuild with the new tiers.
func update_stream(scroll: Vector2, world_scale: float = 1.0, cap: int = -1) -> void:
	if world_root == null:
		return
	_cur_scale = world_scale

	# Which tiers spawn is decided per newly-built cell from the current world_scale. Do
	# NOT rebuild existing cells when the active set changes -- the flowers simply appear
	# in cells built at the off-screen streaming frontier and scroll in (no ground pop).
	_active_sig = _active_signature(world_scale)

	var ts: float = cell_size
	var r: float = _radius_for(world_scale)
	var cx: float = scroll.x
	var cz: float = scroll.y
	var ix0: int = int(floor((cx - r) / ts))
	var ix1: int = int(floor((cx + r) / ts))
	var iz0: int = int(floor((cz - r) / ts))
	var iz1: int = int(floor((cz + r) / ts))

	# Free cells only once they're off screen by more than the largest object's reach, so a
	# big object (a flower) is never removed while any part of it is still visible.
	var rf: float = r + _max_native()
	var fx0: int = int(floor((cx - rf) / ts))
	var fx1: int = int(floor((cx + rf) / ts))
	var fz0: int = int(floor((cz - rf) / ts))
	var fz1: int = int(floor((cz + rf) / ts))
	for key in _cells.keys():
		var parts: PackedStringArray = key.split(",")
		var ix: int = int(parts[0])
		var iz: int = int(parts[1])
		if ix < fx0 or ix > fx1 or iz < fz0 or iz > fz1:
			_free_cell(key)

	# Collect missing cells inside a circular window.
	var missing: Array = []
	for iz in range(iz0, iz1 + 1):
		for ix in range(ix0, ix1 + 1):
			if _cells.has("%d,%d" % [ix, iz]):
				continue
			var tcx: float = (float(ix) + 0.5) * ts
			var tcz: float = (float(iz) + 0.5) * ts
			var dx: float = tcx - cx
			var dz: float = tcz - cz
			if dx * dx + dz * dz <= r * r:
				missing.append(Vector2i(ix, iz))

	if missing.is_empty():
		return

	# Build nearest-first so the closest cells are never the ones deferred by the cap.
	missing.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var ax: float = (float(a.x) + 0.5) * ts - cx
		var az: float = (float(a.y) + 0.5) * ts - cz
		var bx: float = (float(b.x) + 0.5) * ts - cx
		var bz: float = (float(b.y) + 0.5) * ts - cz
		return ax * ax + az * az < bx * bx + bz * bz)

	var lim: int = cap if cap >= 0 else max_cells_per_frame
	var made: int = 0
	for cell in missing:
		_spawn_cell(cell.x, cell.y, ts)
		made += 1
		if lim > 0 and made >= lim:
			break


# Approach-zoom is OFF for this pass (camera_controller size_gain 0) and the instanced
# plants have no per-plant nodes to poll, so this reports no influence. If subtle
# approach-zoom comes back, drive it from the flame-local cell instead.
func approach_influence(_world_center: Vector3, _radius: float) -> float:
	return 0.0


# Expected per-cell object count for a tier at a given world_scale.
#  - Current (point-giving) tier: REFERENCE * world_scale^2  -> constant on-screen density.
#  - A tier not yet current (world_scale above its current_scale): starts super sparse and
#    lerps up to its ready value (REFERENCE * current_scale^2) as the world nears its scale,
#    so it's already on screen at the right density when the player grows into it.
func _expected_count(tier_index: int, world_scale: float) -> float:
	var t: Dictionary = TIERS[tier_index]
	var cs: float = t.current_scale
	if world_scale > cs:
		var ready: float = REFERENCE_PER_CELL * cs * cs
		var progress: float = clampf((1.0 - world_scale) / (1.0 - cs), 0.0, 1.0)
		return lerpf(FLOWER_SPARSE, ready, progress)
	return REFERENCE_PER_CELL * world_scale * world_scale


func _active_signature(world_scale: float) -> String:
	var ids: Array = []
	for i in range(TIERS.size()):
		var t: Dictionary = TIERS[i]
		if t.get("always_spawn", false) or (world_scale >= t.scale_lo and world_scale <= t.scale_hi):
			ids.append(str(i))
	return ",".join(ids)


# Among the tiers active at this world_scale, the one with the largest native size --
# the scale the player has grown INTO. Only objects of this tier award points, so burning
# a smaller, outgrown tier (old scale) gives nothing. -1 if none active.
func top_active_tier(world_scale: float) -> int:
	var best: int = -1
	var best_native: float = -1.0
	for i in range(TIERS.size()):
		var t: Dictionary = TIERS[i]
		if world_scale >= t.scale_lo and world_scale <= t.scale_hi and t.native_scale > best_native:
			best_native = t.native_scale
			best = i
	return best


# Build a tier's shared resources once: the pool of stalk meshes, the stalk material, and
# (for flower tiers) the flower mesh pool + flower material. Materials are per-instance
# ShaderMaterials whose base_color is the tier colour; burn state comes from CUSTOM data.
func _ensure_tier(tier_index: int) -> void:
	var t: Dictionary = TIERS[tier_index]
	if _pools.has(t.id):
		return

	# Compound builders (butterfly weed, Queen Anne's Lace, bush, ...) return TWO merged meshes:
	# a primary (stems / woody branches, `t.color`) + a secondary (flower umbels / leaves,
	# `t.flower_color`), both base-origin. They slot straight onto the stalk+flower MultiMesh
	# path with pool tip ZERO (the secondary is already positioned in its own mesh).
	var builder: String = t.get("builder", "")
	if builder != "":
		var entries: Array = []
		var fmeshes: Array = []
		for v in range(POOL_PER_TIER):
			var d: Dictionary = _build_compound(builder, t.native_scale, float(hash(Vector2i(tier_index, v))))
			entries.append({"mesh": d.mesh, "tip": Vector3.ZERO})
			fmeshes.append(d.flower_mesh)
		_pools[t.id] = entries
		_mats[t.id] = _plant_material(t.color)
		_flower_pools[t.id] = fmeshes
		_flower_mats[t.id] = _plant_material(t.flower_color)
		return

	var entries2: Array = []                     # each: {mesh, tip}
	for v in range(POOL_PER_TIER):
		entries2.append(Frond.build_stalk(t.native_scale, float(hash(Vector2i(tier_index, v)))))
	_pools[t.id] = entries2
	_mats[t.id] = _plant_material(t.color)
	if t.get("flower", false):
		var fmeshes2: Array = []
		for v in range(POOL_PER_TIER):
			fmeshes2.append(Frond.build_flower_head(t.native_scale, float(hash(Vector2i(tier_index * 31 + 5, v)))))
		_flower_pools[t.id] = fmeshes2
		_flower_mats[t.id] = _plant_material(t.flower_color)


# Dispatch a compound tier builder by name -> {"mesh":..., "flower_mesh":...}.
func _build_compound(builder: String, scale: float, seed: float) -> Dictionary:
	match builder:
		"butterfly_weed":
			return Frond.build_butterfly_weed(scale, seed)
		"queen_annes_lace":
			return Frond.build_queen_annes_lace(scale, seed)
		"bush":
			return Frond.build_bush(scale, seed)
	return Frond.build_butterfly_weed(scale, seed)


func _plant_material(base_color: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = PlantShader
	mat.set_shader_parameter("base_color", base_color)
	return mat


func _new_multimesh(mesh: Mesh, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true                   # per-instance burn state (char, grey)
	mm.mesh = mesh
	mm.instance_count = count
	return mm


func _spawn_cell(ix: int, iz: int, ts: float) -> void:
	var root := Node3D.new()
	root.position = Vector3(float(ix) * ts, 0.0, float(iz) * ts)
	var cell_key: String = "%d,%d" % [ix, iz]
	var records: Array = []

	# Scatter each active tier's plants, deterministic from a per-cell + per-tier seed, then
	# group them by mesh variant so each variant streams as ONE instanced MultiMesh.
	for ti in range(TIERS.size()):
		var t: Dictionary = TIERS[ti]
		if _active_sig.find(str(ti)) == -1:
			continue
		_ensure_tier(ti)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector3i(ix * 73856093, iz * 19349663, _seed + ti))
		# Content count that keeps this tier's on-screen density constant (fractional part
		# is a per-cell coin flip, so sparse tiers still scatter deterministically).
		var expected: float = _expected_count(ti, _cur_scale)
		var n: int = int(expected)
		if rng.randf() < (expected - float(n)):
			n += 1
		if n <= 0:
			continue

		# Roll every plant first, bucketed by variant (deterministic RNG order preserved).
		var by_variant: Dictionary = {}         # variant -> Array[{lpos, yaw, content}]
		for i in range(n):
			var pidx: int = rng.randi() % POOL_PER_TIER
			var px: float = rng.randf_range(0.0, ts)
			var pz: float = rng.randf_range(0.0, ts)
			var wx: float = float(ix) * ts + px
			var wz: float = float(iz) * ts + pz
			var py: float = 0.0
			if height_field != null:
				py = height_field.height(wx, wz)
			var yaw: float = rng.randf_range(0.0, TAU)
			if not by_variant.has(pidx):
				by_variant[pidx] = []
			by_variant[pidx].append({"lpos": Vector3(px, py, pz), "yaw": yaw, "content": Vector2(wx, wz)})

		for pidx in by_variant.keys():
			_build_variant_group(root, records, ti, pidx, by_variant[pidx])

	# Lush decorative grass cards wherever the sprout tier is active (the starting scale).
	if _active_sig.find("0") != -1:
		_scatter_cards(root, cell_key, ix, iz, ts)

	world_root.add_child(root)
	_cells[cell_key] = root
	_cell_instances[cell_key] = records


# One MultiMesh of stalks (and, for flower tiers, one of flower heads) for all plants in a
# cell that share mesh variant `pidx`. Fills the per-instance transforms + zeroed burn data
# and appends a burn-tracking record per plant.
func _build_variant_group(root: Node3D, records: Array, tier_index: int, pidx: int, group: Array) -> void:
	var t: Dictionary = TIERS[tier_index]
	var entry: Dictionary = _pools[t.id][pidx]
	var count: int = group.size()

	var smm := _new_multimesh(entry.mesh, count)
	var smi := MultiMeshInstance3D.new()
	smi.multimesh = smm
	smi.material_override = _mats[t.id]
	root.add_child(smi)

	var fmm: MultiMesh = null
	if t.get("flower", false):
		var fpool: Array = _flower_pools[t.id]
		fmm = _new_multimesh(fpool[pidx % fpool.size()], count)
		var fmi := MultiMeshInstance3D.new()
		fmi.multimesh = fmm
		fmi.material_override = _flower_mats[t.id]
		root.add_child(fmi)

	var tip: Vector3 = entry.tip
	for gi in range(count):
		var g: Dictionary = group[gi]
		var xform := Transform3D(Basis(Vector3.UP, g.yaw), g.lpos)
		smm.set_instance_transform(gi, xform)
		smm.set_instance_custom_data(gi, Color(0.0, 0.0, 0.0, 0.0))

		var base_f := Transform3D()
		if fmm != null:
			base_f = xform * Transform3D(Basis(), tip)      # flower sits on the stalk tip
			fmm.set_instance_transform(gi, base_f)
			fmm.set_instance_custom_data(gi, Color(0.0, 0.0, 0.0, 0.0))

		records.append({
			"tier": tier_index,
			"native": float(t.native_scale),
			"flower": t.get("flower", false),
			"content": g.content,               # world content XZ -- distance-checked vs scroll
			"smm": smm, "sidx": gi,
			"fmm": fmm, "fidx": gi,
			"base_s": xform,
			"base_f": base_f,
			"base_y": g.lpos.y,                 # plant base height (squash pivots here)
			"consumed": false,
			"char": 0.0,
			"squash_t": 0.0,
		})


# Distance-check burn against the fixed flame at the origin. In render space the flame sits
# at the origin and an instance at content position P renders at world_scale*(P - scroll),
# so "flame touches plant" is |P - scroll| <= (flame_half/world_scale + plant_half) in
# CONTENT space. Only cells around the flame are scanned. Returns how many CURRENT-tier
# plants were consumed this call (main.gd scores + shrinks the world by that many).
func process_burn(scroll: Vector2, world_scale: float, flame_render_half: float, delta: float) -> int:
	_advance_burns(delta)
	_advance_card_burns(delta)

	var top: int = top_active_tier(world_scale)
	var flame_content_half: float = flame_render_half / maxf(world_scale, 0.0001)
	var ts: float = cell_size
	var cix: int = int(floor(scroll.x / ts))
	var ciz: int = int(floor(scroll.y / ts))
	var points: int = 0

	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var mix: int = cix + dx
			var miz: int = ciz + dz
			var key: String = "%d,%d" % [mix, miz]
			var recs: Array = _cell_instances.get(key, [])
			for rec in recs:
				if rec.consumed:
					continue
				var contact: float = flame_content_half + rec.native * 0.5
				if scroll.distance_to(rec.content) > contact:
					continue
				if rec.flower and rec.tier != top:
					# Too big to burn: the brush paints a ground-patch mark onto its mesh.
					_mark_instance(rec, mix, miz, ts, scroll, flame_content_half)
				else:
					_consume_instance(rec)
					if rec.tier == top:
						points += 1

			# Decorative grass cards touched by the flame fade black->grey (no points/shrink).
			var crecs: Array = _card_instances.get(key, [])
			for crec in crecs:
				if crec.touched:
					continue
				var creach: float = flame_content_half + crec.size * 0.5
				if scroll.distance_to(crec.content) <= creach:
					crec.touched = true
					_card_burning.append(crec)
	return points


# Paint a single ground-patch brush mark ONTO an un-burnable item's mesh where the flame
# brushes it (once per item -- no spreading). A Decal projects a ground-patch texture
# horizontally into the plant from the flame's side, so it lands on the actual blade
# triangles (not the ground). Parented to the item's cell root -> scrolls/scales/frees with it.
func _mark_instance(rec: Dictionary, mix: int, miz: int, ts: float, scroll: Vector2, flame_content_half: float) -> void:
	if rec.get("marked", false):
		return
	rec.marked = true
	var root: Node3D = _cells.get("%d,%d" % [mix, miz], null)
	if root == null:
		return

	# Horizontal direction from the flame INTO the plant -- the decal projects along it.
	var to_plant: Vector2 = rec.content - scroll
	var n: Vector3 = Vector3(to_plant.x, 0.0, to_plant.y)
	n = n.normalized() if n.length() > 0.0001 else Vector3(0.0, 0.0, 1.0)

	var brush_h: float = clampf(flame_content_half * 1.5, 0.06, rec.native * 0.5)   # low, where the small flame reaches
	var off: float = rec.native * 0.12
	var cxz: Vector2 = rec.content - Vector2(n.x, n.z) * off                        # nudge toward the flame side
	var gy: float = 0.0
	if height_field != null:
		gy = height_field.height(cxz.x, cxz.y)
	var center: Vector3 = Vector3(cxz.x, gy + brush_h, cxz.y)

	# Decal projects along its local -Y; aim that along n (into the plant).
	var y_axis: Vector3 = -n
	var x_axis: Vector3 = Vector3.UP.cross(y_axis)
	x_axis = x_axis.normalized() if x_axis.length() > 0.001 else Vector3.RIGHT
	var z_axis: Vector3 = x_axis.cross(y_axis).normalized()

	var d := Decal.new()
	d.texture_albedo = BURN_MARK_TEXTURE
	var sz: float = maxf(flame_content_half * 3.0, 0.12)         # localized brush footprint
	d.size = Vector3(sz, maxf(rec.native * 0.6, sz), sz)         # Y = projection depth through the blades
	d.transform = Transform3D(Basis(x_axis, y_axis, z_axis), center - Vector3(float(mix) * ts, 0.0, float(miz) * ts))
	root.add_child(d)


# Burn a plant: blacken it immediately, then it squashes to ash over HIT_SQUASH_TIME.
func _consume_instance(rec: Dictionary) -> void:
	rec.consumed = true
	rec.squash_t = 0.0
	var black := Color(1.0, 0.0, 0.0, 0.0)
	rec.smm.set_instance_custom_data(rec.sidx, black)
	if rec.fmm != null:
		rec.fmm.set_instance_custom_data(rec.fidx, black)
	_burning.append(rec)


# Advance consumed plants: squash height 1.0 -> 0.1 about the base, then flip to grey ash.
func _advance_burns(delta: float) -> void:
	if _burning.is_empty():
		return
	var still: Array = []
	for rec in _burning:
		rec.squash_t = float(rec.squash_t) + delta
		var f: float = clampf(float(rec.squash_t) / HIT_SQUASH_TIME, 0.0, 1.0)
		var ys: float = lerpf(1.0, 0.1, f)
		var bs: Transform3D = rec.base_s
		rec.smm.set_instance_transform(rec.sidx, Transform3D(bs.basis.scaled(Vector3(1.0, ys, 1.0)), bs.origin))
		if rec.fmm != null:
			var bf: Transform3D = rec.base_f
			var ny: float = float(rec.base_y) + (bf.origin.y - float(rec.base_y)) * ys
			rec.fmm.set_instance_transform(rec.fidx, Transform3D(bf.basis.scaled(Vector3(1.0, ys, 1.0)), Vector3(bf.origin.x, ny, bf.origin.z)))
		if f >= 1.0:
			var ash := Color(1.0, 1.0, 0.0, 0.0)   # char=1, grey=1
			rec.smm.set_instance_custom_data(rec.sidx, ash)
			if rec.fmm != null:
				rec.fmm.set_instance_custom_data(rec.fidx, ash)
		else:
			still.append(rec)
	_burning = still


# Build the shared card mesh (two crossed vertical quads) + one material per variant texture.
# Normals point UP so the flat blades catch the top light evenly (no dark edge-on cards).
func _ensure_cards() -> void:
	if _card_mesh != null:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_card_quad(st, Vector3(1.0, 0.0, 0.0))   # spans X, faces Z
	_add_card_quad(st, Vector3(0.0, 0.0, 1.0))   # spans Z, faces X
	_card_mesh = st.commit()
	for v in range(GRASS_CARD_VARIANTS):
		var tex: Texture2D = load("res://assets/grass/grass_card_%d.png" % v)
		var m := ShaderMaterial.new()
		m.shader = CardShader                                        # cutout + per-instance burn tint
		m.set_shader_parameter("card_tex", tex)
		_card_mats.append(m)


# One vertical quad: unit width along `ax` (-0.5..0.5), unit height (0..1), UV bottom=1 so
# the texture's rooted base sits on the ground. Up-facing normals.
func _add_card_quad(st: SurfaceTool, ax: Vector3) -> void:
	var up := Vector3(0.0, 1.0, 0.0)
	var bl := ax * -0.5
	var br := ax * 0.5
	var tl := bl + up
	var tr := br + up
	st.set_normal(up); st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(bl)
	st.set_normal(up); st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(br)
	st.set_normal(up); st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(tr)
	st.set_normal(up); st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(bl)
	st.set_normal(up); st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(tr)
	st.set_normal(up); st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(tl)


# Scatter dense decorative grass cards across a cell, grouped by variant into MultiMeshes
# (deterministic per cell). On-screen density held constant via world_scale^2, like the tiers.
# Each card gets a burn-record so the flame's distance check can fade it black->grey on touch.
func _scatter_cards(root: Node3D, cell_key: String, ix: int, iz: int, ts: float) -> void:
	_ensure_cards()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(ix * 83492791, iz * 29874533, _seed + 777))
	var expected: float = CARD_REFERENCE_PER_CELL * _cur_scale * _cur_scale
	var n: int = int(expected)
	if rng.randf() < (expected - float(n)):
		n += 1
	if n <= 0:
		return

	var by_variant: Dictionary = {}
	for i in range(n):
		var v: int = rng.randi() % GRASS_CARD_VARIANTS
		var px: float = rng.randf_range(0.0, ts)
		var pz: float = rng.randf_range(0.0, ts)
		var py: float = 0.0
		if height_field != null:
			py = height_field.height(float(ix) * ts + px, float(iz) * ts + pz)
		var sc: float = rng.randf_range(0.72, 1.25)
		if not by_variant.has(v):
			by_variant[v] = []
		by_variant[v].append({"pos": Vector3(px, py, pz), "yaw": rng.randf_range(0.0, TAU), "sc": sc})

	var card_recs: Array = []
	for v in by_variant.keys():
		var group: Array = by_variant[v]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true                   # per-instance burn tint (char, grey)
		mm.mesh = _card_mesh
		mm.instance_count = group.size()
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _card_mats[v]
		# Crossed quads cast an ugly cross-shaped shadow blob at each base -- skip it; the
		# cards read as lush filler without self/ground shadows.
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		for gi in range(group.size()):
			var g: Dictionary = group[gi]
			var b := Basis(Vector3.UP, g.yaw).scaled(Vector3(CARD_WIDTH * g.sc, CARD_HEIGHT * g.sc, CARD_WIDTH * g.sc))
			mm.set_instance_transform(gi, Transform3D(b, g.pos))
			mm.set_instance_custom_data(gi, Color(0.0, 0.0, 0.0, 0.0))
			card_recs.append({
				"mm": mm, "idx": gi,
				"content": Vector2(float(ix) * ts + g.pos.x, float(iz) * ts + g.pos.z),
				"size": CARD_WIDTH * g.sc,
				"touched": false, "char": 0.0, "grey": 0.0,
			})
	if not card_recs.is_empty():
		_card_instances[cell_key] = card_recs


# A touched card fades to black over CARD_BLACK_TIME, then black -> grey ash over CARD_GREY_TIME.
func _advance_card_burns(delta: float) -> void:
	if _card_burning.is_empty():
		return
	var still: Array = []
	for crec in _card_burning:
		if crec.char < 1.0:
			crec.char = minf(1.0, float(crec.char) + delta / CARD_BLACK_TIME)
		elif crec.grey < 1.0:
			crec.grey = minf(1.0, float(crec.grey) + delta / CARD_GREY_TIME)
		crec.mm.set_instance_custom_data(crec.idx, Color(crec.char, crec.grey, 0.0, 0.0))
		if crec.char < 1.0 or crec.grey < 1.0:
			still.append(crec)      # keep until fully faded to grey ash
	_card_burning = still


func _free_cell(key: String) -> void:
	var t: Node3D = _cells.get(key, null)
	if t != null and is_instance_valid(t):
		t.queue_free()
	_cells.erase(key)
	if _card_instances.has(key):
		var crecs: Array = _card_instances[key]
		if not _card_burning.is_empty():
			var kept: Array = []
			for crec in _card_burning:
				if not crecs.has(crec):
					kept.append(crec)
			_card_burning = kept
		_card_instances.erase(key)
	if _cell_instances.has(key):
		# Drop any of this cell's plants that are still mid-burn from the animation list.
		var recs: Array = _cell_instances[key]
		if not _burning.is_empty():
			var still: Array = []
			for rec in _burning:
				if not recs.has(rec):
					still.append(rec)
			_burning = still
		_cell_instances.erase(key)


func active_cell_count() -> int:
	return _cells.size()


# --- Query helpers (used by tests) -------------------------------------------------------

func cell_instance_count(ix: int, iz: int) -> int:
	var recs: Array = _cell_instances.get("%d,%d" % [ix, iz], [])
	return recs.size()


func count_native(size: float) -> int:
	var n: int = 0
	for key in _cell_instances.keys():
		for rec in _cell_instances[key]:
			if absf(float(rec.native) - size) < 0.001:
				n += 1
	return n


func first_flower_record() -> Dictionary:
	for key in _cell_instances.keys():
		for rec in _cell_instances[key]:
			if rec.flower:
				return rec
	return {}
