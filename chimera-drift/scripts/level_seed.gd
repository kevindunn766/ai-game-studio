extends Node

# Appended CANYON/PILLARED at the end (3/4) so the existing 0/1/2 literals used
# elsewhere (sky_director's SURFACE=1/OPEN_VOLUME=2, director's in_space==2) stay valid.
enum ShapeFamily { CORRIDOR, SURFACE, OPEN_VOLUME, CANYON, PILLARED }

# The level roll is now DRIVEN BY biome_attribute_table.csv (via BiomeTable): each
# level picks a biome, then a valid (structure, viewpoint) combo, its gravity, a
# subset of that biome's 10 objects, and its enemies -- instead of the old generic
# word pools. See STRUCTURE_MAP for how CSV structures map onto the three generators.
const BiomeTable := preload("res://scripts/biome_table.gd")

# CSV structure token -> [shape family, generator structure_type]. Design call: open
# canyons/plains map to SURFACE (so they support the angled/overhead views the CSV
# lists for them); only genuinely enclosed tunnels/arches map to CORRIDOR, which the
# camera rule pins to third-person. Aquatic variants reuse their dry structure.
const STRUCTURE_MAP := {
	"Landscape": [ShapeFamily.SURFACE, "flat"],
	"Aquatic Landscape": [ShapeFamily.SURFACE, "flat"],
	"Mountains": [ShapeFamily.SURFACE, "mountains"],
	# Canyons / Pillared Planes are now their OWN families (open-top walled gorge /
	# slalom pillar field) instead of being faked inside SURFACE's generator.
	"Canyons": [ShapeFamily.CANYON, "canyon"],
	"Pillared Planes": [ShapeFamily.PILLARED, "pillared"],
	"Arched Planes": [ShapeFamily.CORRIDOR, "arched"],
	"Tunneling Caves": [ShapeFamily.CORRIDOR, "cave"],
	# Aquatic Canyons stays CORRIDOR: these read as enclosed submarine corridors, not
	# the open-top CANYON family (their CSV name is literally "...Corridors").
	"Aquatic Canyons": [ShapeFamily.CORRIDOR, "canyon"],
	"Open Space": [ShapeFamily.OPEN_VOLUME, "asteroid_field"],
	"Cloudy Open Space": [ShapeFamily.OPEN_VOLUME, "field"],
	# Dedicated cliff biomes (Waterfall / Lava Flow Cliffs): open Surface floor whose
	# structure_type "cliffs" forces the craggy left-side cliff backdrop ON (see _roll_cliff).
	"Cliffs": [ShapeFamily.SURFACE, "cliffs"],
}

# The MODIFIER still drives the biome palette/mood (LevelTheme), layered on top of the
# biome for extra variety ("Molten" vs "Frozen" tint). Anti-repeated each level.
const MODIFIER_WORDS := [
	"Frozen", "Molten", "Flooded", "Crumbling", "Overgrown", "Irradiated",
	"Toxic", "Ancient", "Pristine", "Storm-Wracked", "Bioluminescent",
	"Crystalline", "Fungal-Infested", "Petrified", "Haunted",
]

# How many of the biome's 10 objects appear per level.
const MIN_FEATURE_OBJECTS: int = 3
const MAX_FEATURE_OBJECTS: int = 5
# Per-object chance to swap in an object from a DIFFERENT biome instead of this one's
# (Kevin) -- keeps levels endlessly varied without breaking the view/structure rules,
# which stay keyed to the rolled biome. The palette also stays the biome's, so a
# foreign object just reads as an odd transplant, not a whole theme change.
const OBJECT_SWAP_CHANCE: float = 0.28
# Flat pool of every biome's objects, cached (built lazily from the table).
var _all_objects: Array = []

# Flying-enemy categories -- dumb radial swarmer + smart ship-pipeline dogfighter.
# Rolled independently per level; the biome supplies their names (enemy_names).
const ENEMY_KINDS := ["dumb", "smart"]
const ENEMY_ROLL := {
	"dumb": {"chance": 0.72, "min": 0.14, "max": 0.42},
	"smart": {"chance": 0.55, "min": 0.06, "max": 0.24},
}

# Mines: per-segment formation chance.
const MINES_CHANCE: float = 0.5
const MINES_MIN: float = 0.12
const MINES_MAX: float = 0.35

# Hazards: slow-damage field/leech/grasper + stationary turret + push (geyser).
const HAZARD_KINDS := ["field", "leech", "grasper", "turret", "push"]
const HAZARD_ROLL := {
	"field": {"chance": 0.4, "min": 0.10, "max": 0.30},
	"leech": {"chance": 0.4, "min": 0.10, "max": 0.30},
	"grasper": {"chance": 0.4, "min": 0.10, "max": 0.30},
	"turret": {"chance": 0.4, "min": 0.08, "max": 0.24},
	"push": {"chance": 0.35, "min": 0.10, "max": 0.28},
}

# State-machine memory: the previous level's key attributes, so a fresh roll can be
# forced to differ (see the anti-repeat picks below). Persists across the session.
var _prev: Dictionary = {}

# Biomes already visited THIS playthrough -- no biome is ever revisited in a single
# run (there are 56, far more than any run is long). Reset by begin_playthrough(),
# which fires on `RunManager.run_started` (i.e. exactly when a new run starts and the
# permanent loadout is cleared).
var _visited: Dictionary = {}

# Set at run start from the persistent Profile: if the player has BEATEN the game,
# every future run starts directly in the endless scrambled NG+ mode (until wiped).
var _force_ng_plus: bool = false

func _ready() -> void:
	# Reached via the /root path (not the RunManager autoload global) so this script
	# still compiles when preloaded outside the autoload context (headless -s tests).
	var rm: Node = get_node_or_null("/root/RunManager")
	if rm != null and rm.has_signal("run_started"):
		rm.run_started.connect(_on_run_started)

func _on_run_started(_hull_seed: int) -> void:
	begin_playthrough()

# Start a fresh run: forget every visited biome (and the last-level memory) so the
# whole biome roster is available again. If the persistent profile says the game has
# been beaten, this run is NG+ from level 1.
func begin_playthrough() -> void:
	_visited.clear()
	_prev = {}
	var prof: Node = get_node_or_null("/root/Profile")
	_force_ng_plus = prof != null and prof.beaten

# Per-level numeric "personality" -- the scatter/geometry knobs, rolled within
# shape-family-appropriate ranges so each level's density/scale/clumping/patch feel
# differs from the last. Generators read this via configure_state().
func roll_state(shape_family: int, r: RandomNumberGenerator) -> Dictionary:
	var s: Dictionary = {
		"density": r.randf_range(0.6, 1.6),
		"feature_scale": r.randf_range(0.75, 1.4),
		"clumpiness": r.randf_range(0.28, 0.62),
		"patch_freq": r.randf_range(0.02, 0.06),
	}
	match shape_family:
		ShapeFamily.CORRIDOR:
			s["tunnel_width"] = r.randf_range(0.8, 1.4)
			s["tunnel_breath"] = r.randf_range(0.3, 1.1)
			s["widen_factor"] = r.randf_range(1.3, 2.2)
		ShapeFamily.SURFACE:
			s["lane_width"] = r.randf_range(0.8, 1.4)
		ShapeFamily.CANYON:
			s["lane_width"] = r.randf_range(0.8, 1.4)   # inherited surface scatter band
			s["gorge_width"] = r.randf_range(0.8, 1.4)  # how wide the walled gorge sits
		ShapeFamily.PILLARED:
			s["lane_width"] = r.randf_range(0.8, 1.4)
			s["pillar_density"] = r.randf_range(0.7, 1.5)  # how thick the slalom field is
		ShapeFamily.OPEN_VOLUME:
			s["ring_radius"] = r.randf_range(0.8, 1.4)
	return s

# `force_biome` / `force_view` let the debug preview hotkeys (LevelDirector) jump straight to
# a specific level -- otherwise it rolls randomly as before. A forced view that the biome can't
# support is ignored (falls back to any valid combo for that biome).
func roll_new_level(rng: RandomNumberGenerator = null, force_biome: String = "", force_view: String = "") -> Dictionary:
	var r: RandomNumberGenerator = rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.randomize()

	var biomes: Dictionary = BiomeTable.table()
	if biomes.is_empty():
		return _fallback_level(r)
	var total: int = biomes.size()

	# NEW GAME PLUS: once every biome has been visited (base game complete), levels
	# stop being biome-grouped and become endlessly SCRAMBLED -- any rule-valid
	# structure/view/gravity/enemy/object combo, no biome coherence. Debug-forcing a
	# specific biome/view opts out (stays on the normal path).
	var forcing: bool = force_biome != "" or force_view != ""
	if not forcing and (_force_ng_plus or _visited.size() >= total):
		return _roll_ng_plus(biomes, r, force_view)

	var biome: String
	if force_biome != "" and biomes.has(force_biome):
		biome = force_biome
	else:
		# Pick a biome NOT yet visited this playthrough (so no biome is seen twice).
		var names: Array = biomes.keys()
		var avail: Array = names.filter(func(n): return not _visited.has(n))
		if avail.is_empty():
			avail = names   # whole roster cleared in one run -> allow repeats rather than stall
		biome = avail[r.randi_range(0, avail.size() - 1)]
	var data: Dictionary = biomes[biome]
	_visited[biome] = true   # mark visited so this playthrough won't return here

	# Build the valid (family, structure, viewpoint) combos for this biome; honor a forced
	# view if one was given and the biome supports it, else use every valid combo.
	var combos: Array = _build_combos(data, force_view)
	if combos.is_empty():
		combos = _build_combos(data, "")
	if combos.is_empty():
		combos.append([ShapeFamily.SURFACE, "flat", "thirdperson"])
	# Anti-repeat the viewpoint if the biome still offers an alternative (not when forcing).
	if not forcing and _prev.has("viewpoint"):
		var pv: String = _prev["viewpoint"]
		var alt: Array = combos.filter(func(c): return c[2] != pv)
		if not alt.is_empty():
			combos = alt
	var combo: Array = combos[r.randi_range(0, combos.size() - 1)]
	var shape_family: int = combo[0]
	var structure_type: String = combo[1]
	var viewpoint: String = combo[2]

	# Modifier drives palette/mood, anti-repeated so the look shifts every level.
	var mod_pool: Array = MODIFIER_WORDS.duplicate()
	if _prev.has("modifier_word") and mod_pool.size() > 1:
		mod_pool.erase(_prev["modifier_word"])
	var modifier_word: String = mod_pool[r.randi_range(0, mod_pool.size() - 1)]

	# Feature objects: mostly this biome's, but each slot has a chance to be swapped for
	# a random object from ANY biome, for endless cross-biome variety.
	var objs: Array = (data["objects"] as Array).duplicate()
	_rng_shuffle(objs, r)
	var pool: Array = _global_objects(biomes)
	var fcount: int = r.randi_range(MIN_FEATURE_OBJECTS, MAX_FEATURE_OBJECTS)
	var feature_words: Dictionary = {}
	var oi: int = 0
	var guard: int = 0
	while feature_words.size() < fcount and guard < fcount * 6:
		guard += 1
		var obj_name: String
		if not pool.is_empty() and r.randf() < OBJECT_SWAP_CHANCE:
			obj_name = pool[r.randi_range(0, pool.size() - 1)]
		elif oi < objs.size():
			obj_name = objs[oi]
			oi += 1
		elif not pool.is_empty():
			obj_name = pool[r.randi_range(0, pool.size() - 1)]
		else:
			break
		if not feature_words.has(obj_name):
			feature_words[obj_name] = r.randf_range(0.08, 0.6)

	var enemy_words: Dictionary = {}
	for kind in ENEMY_KINDS:
		var cfg: Dictionary = ENEMY_ROLL[kind]
		if r.randf() < cfg["chance"]:
			enemy_words[kind] = r.randf_range(cfg["min"], cfg["max"])

	var mines_density: float = 0.0
	if r.randf() < MINES_CHANCE:
		mines_density = r.randf_range(MINES_MIN, MINES_MAX)

	var hazards: Dictionary = {}
	for hkind in HAZARD_KINDS:
		var hcfg: Dictionary = HAZARD_ROLL[hkind]
		if r.randf() < hcfg["chance"]:
			hazards[hkind] = r.randf_range(hcfg["min"], hcfg["max"])

	var cliff: Dictionary = _roll_cliff(biome, structure_type, viewpoint, r)
	# The cliff's flow spawns its matching threat: waterfalls push you off course, lava
	# flows both burn (DOT) and push. Only present on the dedicated cliff biomes.
	if cliff.flow == "water":
		hazards["waterfall"] = r.randf_range(0.3, 0.55)
	elif cliff.flow == "lava":
		hazards["lava"] = r.randf_range(0.3, 0.55)
	var state: Dictionary = roll_state(shape_family, r)
	_prev = {
		"viewpoint": viewpoint,
		"shape_family": shape_family,
		"structure_type": structure_type,
		"modifier_word": modifier_word,
		"biome": biome,
	}
	return {
		"shape_family": shape_family,
		"shape_word": biome,
		"biome": biome,
		"modifier_word": modifier_word,
		"structure_type": structure_type,
		"viewpoint": viewpoint,
		"feature_words": feature_words,
		"enemy_words": enemy_words,
		"enemy_names": data["enemies"],
		"gravity": data["gravity"],
		"mines": mines_density,
		"hazards": hazards,
		"state": state,
		"cliff": cliff,
		"ng_plus": false,
		# The single level that consumes the LAST unvisited biome ends the base game
		# -> its boss is the ULTRA (final) boss.
		"final_biome": _visited.size() >= total,
	}

# NEW GAME PLUS roll: a scrambled level. Structure/view is any rule-valid combo ANY
# biome allows (so CORRIDOR stays third-person, cliffs stay angled, etc.), gravity is
# a coin flip, and enemies/objects are drawn from the GLOBAL pools -- no biome
# coherence, endless variety. A random real biome name seeds only the palette base.
func _roll_ng_plus(biomes: Dictionary, r: RandomNumberGenerator, force_view: String) -> Dictionary:
	var combos: Array = _global_combos(biomes, force_view)
	if combos.is_empty():
		combos = _global_combos(biomes, "")
	if combos.is_empty():
		combos.append([ShapeFamily.SURFACE, "flat", "thirdperson"])
	if _prev.has("viewpoint"):
		var pv: String = _prev["viewpoint"]
		var alt: Array = combos.filter(func(c): return c[2] != pv)
		if not alt.is_empty():
			combos = alt
	var combo: Array = combos[r.randi_range(0, combos.size() - 1)]
	var shape_family: int = combo[0]
	var structure_type: String = combo[1]
	var viewpoint: String = combo[2]

	var modifier_word: String = _pick_modifier(r)
	var bnames: Array = biomes.keys()
	var palette_biome: String = bnames[r.randi_range(0, bnames.size() - 1)]   # palette base only

	# Objects drawn purely from the GLOBAL pool (any biome's props, mixed together).
	var pool: Array = _global_objects(biomes)
	var fcount: int = r.randi_range(MIN_FEATURE_OBJECTS, MAX_FEATURE_OBJECTS)
	var feature_words: Dictionary = {}
	var guard: int = 0
	while feature_words.size() < fcount and guard < fcount * 8 and not pool.is_empty():
		guard += 1
		var o: String = pool[r.randi_range(0, pool.size() - 1)]
		if not feature_words.has(o):
			feature_words[o] = r.randf_range(0.08, 0.6)

	var enemy_words: Dictionary = {}
	for kind in ENEMY_KINDS:
		var cfg: Dictionary = ENEMY_ROLL[kind]
		if r.randf() < cfg["chance"]:
			enemy_words[kind] = r.randf_range(cfg["min"], cfg["max"])

	var mines_density: float = 0.0
	if r.randf() < MINES_CHANCE:
		mines_density = r.randf_range(MINES_MIN, MINES_MAX)

	var hazards: Dictionary = {}
	for hkind in HAZARD_KINDS:
		var hcfg: Dictionary = HAZARD_ROLL[hkind]
		if r.randf() < hcfg["chance"]:
			hazards[hkind] = r.randf_range(hcfg["min"], hcfg["max"])

	var cliff: Dictionary = _roll_cliff(palette_biome, structure_type, viewpoint, r)
	# Only spawn a flow threat when the cliff is actually visible (avoids a phantom
	# waterfall/lava push with no cliff behind it in the scramble).
	if cliff.enabled and cliff.flow == "water":
		hazards["waterfall"] = r.randf_range(0.3, 0.55)
	elif cliff.enabled and cliff.flow == "lava":
		hazards["lava"] = r.randf_range(0.3, 0.55)

	var state: Dictionary = roll_state(shape_family, r)
	_prev = {
		"viewpoint": viewpoint,
		"shape_family": shape_family,
		"structure_type": structure_type,
		"modifier_word": modifier_word,
		"biome": palette_biome,
	}
	return {
		"shape_family": shape_family,
		"shape_word": "Anomaly",       # scrambled -> not a named biome
		"biome": palette_biome,         # palette base only
		"modifier_word": modifier_word,
		"structure_type": structure_type,
		"viewpoint": viewpoint,
		"feature_words": feature_words,
		"enemy_words": enemy_words,
		"enemy_names": _pick_scrambled_enemies(biomes, r),
		"gravity": r.randf() < 0.5,
		"mines": mines_density,
		"hazards": hazards,
		"state": state,
		"cliff": cliff,
		"ng_plus": true,
		"final_biome": false,
	}

# True when this run is in NG+ -- either the profile unlocked it (beaten before) or
# every biome has been visited this run (base game just completed).
func in_new_game_plus() -> bool:
	return _force_ng_plus or _visited.size() >= BiomeTable.table().size()

func biome_count() -> int:
	return BiomeTable.table().size()

# Every rule-valid (family, structure, viewpoint) combo ANY biome allows, deduped.
func _global_combos(biomes: Dictionary, force_view: String) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for data in biomes.values():
		for c in _build_combos(data, force_view):
			var key: String = "%d|%s|%s" % [c[0], c[1], c[2]]
			if not seen.has(key):
				seen[key] = true
				out.append(c)
	return out

# Modifier word, anti-repeated against the previous level so the palette shifts.
func _pick_modifier(r: RandomNumberGenerator) -> String:
	var mod_pool: Array = MODIFIER_WORDS.duplicate()
	if _prev.has("modifier_word") and mod_pool.size() > 1:
		mod_pool.erase(_prev["modifier_word"])
	return mod_pool[r.randi_range(0, mod_pool.size() - 1)]

# 3 distinct enemy names drawn from every biome's roster, mixed (NG+ scramble).
func _pick_scrambled_enemies(biomes: Dictionary, r: RandomNumberGenerator) -> Array:
	var seen: Dictionary = {}
	var flat: Array = []
	for data in biomes.values():
		for e in data["enemies"]:
			if not seen.has(e):
				seen[e] = true
				flat.append(e)
	_rng_shuffle(flat, r)
	return flat.slice(0, min(3, flat.size()))

# Valid (family, structure, viewpoint) combos for a biome, honoring the camera rules
# (CORRIDOR is third-person only; cliffs are iso/3-4 only). `force_view` != "" keeps only
# that viewpoint.
func _build_combos(data: Dictionary, force_view: String) -> Array:
	var combos: Array = []
	for st in data["structures"]:
		if not STRUCTURE_MAP.has(st):
			continue
		var m: Array = STRUCTURE_MAP[st]
		for vp in data["views"]:
			if force_view != "" and vp != force_view:
				continue
			if m[0] == ShapeFamily.CORRIDOR and vp != "thirdperson":
				continue
			if m[1] == "cliffs" and not (vp in CLIFF_VIEWS):
				continue
			combos.append([m[0], m[1], vp])
	return combos

# A steep craggy CLIFF backdrop on the ship's left. Only meaningful in the angled iso /
# 3-4 cameras (it reads as a dramatic wall behind the play field). Forced ON for the
# dedicated cliff biomes (structure "cliffs"); otherwise a random opt-in on eligible
# open biomes (mountains / canyons / cityscapes). Flow (waterfall / lava) comes from
# the biome name and only exists on the dedicated cliff biomes.
const CLIFF_CHANCE: float = 0.45
const CLIFF_VIEWS := ["isometric", "threequarter"]

func _roll_cliff(biome: String, structure_type: String, viewpoint: String, r: RandomNumberGenerator) -> Dictionary:
	var b: String = biome.to_lower()
	var flow: String = ""
	if b.find("waterfall") != -1:
		flow = "water"
	elif b.find("lava flow") != -1 or b.find("lava cliff") != -1:
		flow = "lava"
	var enabled: bool = false
	if structure_type == "cliffs":
		enabled = true                                   # dedicated cliff biome: always
	elif structure_type == "canyon" and viewpoint in CLIFF_VIEWS:
		enabled = true                                   # Kevin: ALL iso/3-4 canyons are cliffside
	elif viewpoint in CLIFF_VIEWS and _cliff_eligible(structure_type, b):
		enabled = r.randf() < CLIFF_CHANCE               # opt-in on other eligible open biomes
	# Hard rule: a cliff only ever exists in an angled view (iso / 3-4), never anywhere else.
	if not (viewpoint in CLIFF_VIEWS):
		enabled = false
	return {"enabled": enabled, "flow": flow, "height_mult": r.randf_range(0.85, 1.3)}

func _cliff_eligible(structure_type: String, biome_lower: String) -> bool:
	if structure_type == "mountains" or structure_type == "canyon" or structure_type == "cliffs":
		return true
	for kw in ["city", "mountain", "canyon", "crag", "cliff"]:
		if biome_lower.find(kw) != -1:
			return true
	return false

# Safety net if the CSV can't be read (should not happen in a normal build).
func _fallback_level(r: RandomNumberGenerator) -> Dictionary:
	return {
		"shape_family": ShapeFamily.SURFACE,
		"shape_word": "Planet Surface",
		"biome": "Planet Surface",
		"modifier_word": "Pristine",
		"structure_type": "flat",
		"viewpoint": "thirdperson",
		"feature_words": {"rocks": 0.4, "crystals": 0.3},
		"enemy_words": {},
		"enemy_names": ["Drifters", "Hunters", "Mines"],
		"gravity": true,
		"mines": 0.0,
		"hazards": {},
		"state": roll_state(ShapeFamily.SURFACE, r),
		"cliff": {"enabled": false, "flow": "", "height_mult": 1.0},
	}

# Flat, deduped pool of every biome's objects (for cross-biome object swaps). Cached.
func _global_objects(biomes: Dictionary) -> Array:
	if not _all_objects.is_empty():
		return _all_objects
	var seen: Dictionary = {}
	for b in biomes.values():
		for o in b["objects"]:
			if not seen.has(o):
				seen[o] = true
				_all_objects.append(o)
	return _all_objects

func _rng_shuffle(array: Array, r: RandomNumberGenerator) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j: int = r.randi_range(0, i)
		var temp = array[i]
		array[i] = array[j]
		array[j] = temp
