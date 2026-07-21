extends RefCounted
class_name LevelTheme

# Resolves a rolled level's attribute words into a concrete visual theme:
#   - env palette (walls / walls2 / floor / accent / pillar) + fog color
#   - per-feature-word prop {color, shape}
#   - automatic shape-dressing (stalagmites/stalactites) tinted to the biome
#
# The MODIFIER word drives the biome palette (Frozen vs Molten vs Toxic ...), so
# one shape word x 15 modifiers = 15 looks. All colors are ColorAid-derived
# (Itten hues + tints/shades/tones) so the whole game stays on one color system.
#
# FIRST-PASS COLORS -- tune freely; the palette per modifier is one match arm.

const WHITE := Color(0.90, 0.93, 0.97)
const GREY := Color(0.58, 0.60, 0.65)

static func resolve(rolled: Dictionary) -> Dictionary:
	var modifier: String = rolled.get("modifier_word", "")
	var biome: String = rolled.get("biome", "")
	# The BIOME now drives the palette (Kevin) -- keyword-mapped to a base palette
	# family so an ice biome reads icy, a lava biome molten, etc. The modifier still
	# applies a light secondary tint so repeats of a biome still vary a little.
	var pal := _blended_palette(biome, modifier)

	var features: Dictionary = {}
	for word in rolled.get("feature_words", {}).keys():
		features[word] = _feature_style(word, pal.accent)

	return {
		"biome": biome,
		"walls": pal.walls,
		"walls2": pal.walls2,
		"floor": pal.floor,
		"accent": pal.accent,
		"pillar": pal.pillar,
		"fog": pal.fog,
		"features": features,
		"dressing": _dressing(pal),
	}

# Biome base palette, lightly tinted toward the modifier's palette for per-level
# variety (biome-dominant).
const MOD_TINT: float = 0.22

static func _blended_palette(biome: String, modifier: String) -> Dictionary:
	var bp := _palette(_biome_palette_key(biome))
	if modifier == "":
		return bp
	var mp := _palette(modifier)
	return {
		"walls": bp.walls.lerp(mp.walls, MOD_TINT),
		"walls2": bp.walls2.lerp(mp.walls2, MOD_TINT),
		"floor": bp.floor.lerp(mp.floor, MOD_TINT),
		"accent": bp.accent.lerp(mp.accent, MOD_TINT),
		"pillar": bp.pillar.lerp(mp.pillar, MOD_TINT),
		"fog": bp.fog.lerp(mp.fog, MOD_TINT),
	}

# Map a biome name to one of the palette families (reuses the same _palette arms as
# the modifiers). First keyword match wins; ordered specific -> generic.
const _BIOME_PALETTE_RULES := [
	# Waterfall must precede Flooded (whose "water" keyword would otherwise catch it)
	# so waterfall cliffs read bright teal/white, not deep-blue water.
	["Waterfall", ["waterfall"]],
	["Frozen", ["ice", "frost", "glacier", "tundra", "frozen", "rime", "snow"]],
	["Molten", ["lava", "magma", "volcanic", "sun", "solar", "flare", "plasma", "ember", "cinder", "ash", "corona", "geothermal"]],
	["Flooded", ["ocean", "water", "aquatic", "submarine", "reef", "kelp", "underwater", "lily", "swamp", "sunken", "coral", "jelly"]],
	["Storm-Wracked", ["storm", "ion", "nebula", "cloud", "comet", "gravity", "wormhole"]],
	["Fungal-Infested", ["fungal", "mushroom", "spore", "hive", "biomech"]],
	["Crystalline", ["crystal", "geode", "prism"]],
	["Haunted", ["haunt", "void", "deep space", "black hole", "graveyard", "derelict", "ribcage", "skeletal", "vertebrae", "bone"]],
	["Toxic", ["toxic", "sewer", "sludge", "bog"]],
	["Irradiated", ["irradiat", "radio", "reactor"]],
	["Overgrown", ["overgrown", "forest", "savanna", "grassland", "biolumin", "meadow", "vent field"]],
	["Ancient", ["ancient", "ruin", "temple", "sandstone", "desert", "dune", "salt"]],
	["Petrified", ["cyber", "server", "circuit", "city", "scrapyard", "station", "megastructure", "dyson", "ring", "meteor", "asteroid", "rock", "stone", "debris", "crater", "petrified"]],
]

static func _biome_palette_key(biome: String) -> String:
	var b: String = biome.to_lower()
	for rule in _BIOME_PALETTE_RULES:
		for kw in rule[1]:
			if b.find(kw) != -1:
				return rule[0]
	return "Petrified"

# --- Per-modifier biome palette (ColorAid-derived) -------------------------
# Every modifier owns a DISTINCT dominant hue so no two biomes read as the same
# colour. Twelve Itten hues + two neutrals (white/grey) cover 14; the 15th is a
# value-split on a hue (Frozen light vs Bioluminescent dark blue-green; Crystalline
# light vs Haunted dark violet), which reads as clearly different despite the shared
# family. Warm modifiers fan across red_orange->yellow, cool ones across
# green->violet, so the wheel is evenly used.
#   Frozen blue_green(light)  Bioluminescent blue_green(dark)  Flooded blue
#   Storm-Wracked blue_violet Crystalline violet(light)        Haunted violet(dark)
#   Fungal red_violet         Molten red_orange                Crumbling orange
#   Ancient yellow_orange     Toxic yellow                     Irradiated yellow_green
#   Overgrown green           Pristine white                   Petrified grey
static func _palette(modifier: String) -> Dictionary:
	match modifier:
		"Frozen":
			# Pale glacial cyan -- the light half of the blue-green split.
			var glacier := ColorAid.tint(ColorAid.hue("blue_green"), 0.5)
			return {"walls": ColorAid.tint(ColorAid.hue("blue_green"), 0.7), "walls2": glacier, "floor": ColorAid.tint(ColorAid.hue("blue"), 0.35),
				"accent": ColorAid.tint(ColorAid.hue("blue_green"), 0.35), "pillar": ColorAid.tint(glacier, 0.2),
				"fog": ColorAid.tint(ColorAid.hue("blue_green"), 0.72)}
		"Bioluminescent":
			# Dark teal world lit by bright cyan glow -- the dark half of the blue-green split.
			return {"walls": ColorAid.shade(ColorAid.hue("blue_green"), 0.6), "walls2": ColorAid.shade(ColorAid.hue("blue"), 0.5),
				"floor": ColorAid.shade(ColorAid.hue("blue_green"), 0.75), "accent": ColorAid.tint(ColorAid.hue("blue_green"), 0.25),
				"pillar": ColorAid.shade(ColorAid.hue("blue_green"), 0.5), "fog": ColorAid.shade(ColorAid.hue("blue_green"), 0.6)}
		"Flooded":
			# Deep saturated blue water.
			return {"walls": ColorAid.shade(ColorAid.hue("blue"), 0.3), "walls2": ColorAid.tint(ColorAid.hue("blue"), 0.3),
				"floor": ColorAid.shade(ColorAid.hue("blue"), 0.6), "accent": ColorAid.tint(ColorAid.hue("blue"), 0.45),
				"pillar": ColorAid.shade(ColorAid.hue("blue"), 0.45), "fog": ColorAid.shade(ColorAid.hue("blue"), 0.35)}
		"Storm-Wracked":
			# Electric indigo.
			return {"walls": ColorAid.shade(ColorAid.hue("blue_violet"), 0.4), "walls2": ColorAid.tint(ColorAid.hue("blue_violet"), 0.3),
				"floor": ColorAid.shade(ColorAid.hue("blue_violet"), 0.6), "accent": ColorAid.tint(ColorAid.hue("blue"), 0.5),
				"pillar": ColorAid.shade(ColorAid.hue("blue_violet"), 0.5), "fog": ColorAid.shade(ColorAid.hue("blue_violet"), 0.4)}
		"Crystalline":
			# Bright amethyst -- the light half of the violet split.
			return {"walls": ColorAid.tint(ColorAid.hue("violet"), 0.5), "walls2": ColorAid.tint(ColorAid.hue("violet"), 0.35),
				"floor": ColorAid.tint(ColorAid.hue("violet"), 0.2), "accent": ColorAid.tint(ColorAid.hue("violet"), 0.55),
				"pillar": ColorAid.tint(ColorAid.hue("violet"), 0.4), "fog": ColorAid.tint(ColorAid.hue("violet"), 0.6)}
		"Haunted":
			# Near-black gloom-purple with a spectral glow -- the dark half of the violet split.
			return {"walls": ColorAid.shade(ColorAid.hue("violet"), 0.6), "walls2": ColorAid.tone(ColorAid.hue("violet"), 0.5),
				"floor": ColorAid.shade(ColorAid.hue("violet"), 0.75), "accent": ColorAid.tint(ColorAid.hue("violet"), 0.4),
				"pillar": ColorAid.shade(ColorAid.hue("violet"), 0.55), "fog": ColorAid.shade(ColorAid.hue("violet"), 0.55)}
		"Fungal-Infested":
			# Magenta fungus over green stalks.
			return {"walls": ColorAid.shade(ColorAid.hue("red_violet"), 0.35), "walls2": ColorAid.shade(ColorAid.hue("green"), 0.4),
				"floor": ColorAid.shade(ColorAid.hue("red_violet"), 0.55), "accent": ColorAid.tint(ColorAid.hue("red_violet"), 0.2),
				"pillar": ColorAid.shade(ColorAid.hue("red_violet"), 0.45), "fog": ColorAid.shade(ColorAid.hue("red_violet"), 0.4)}
		"Molten":
			# Hot red-orange lava.
			return {"walls": ColorAid.shade(ColorAid.hue("red_orange"), 0.55), "walls2": ColorAid.hue("orange"),
				"floor": ColorAid.shade(ColorAid.hue("red"), 0.7), "accent": ColorAid.tint(ColorAid.hue("yellow_orange"), 0.1),
				"pillar": ColorAid.shade(ColorAid.hue("red_orange"), 0.4), "fog": ColorAid.shade(ColorAid.hue("red_orange"), 0.45)}
		"Crumbling":
			# Rust / decay brown (shaded orange), kept clearly warmer & darker than Ancient gold.
			return {"walls": ColorAid.shade(ColorAid.hue("orange"), 0.55), "walls2": ColorAid.tone(ColorAid.hue("orange"), 0.4),
				"floor": ColorAid.shade(ColorAid.hue("orange"), 0.7), "accent": ColorAid.tone(ColorAid.hue("yellow_orange"), 0.35),
				"pillar": ColorAid.tone(ColorAid.hue("orange"), 0.5), "fog": ColorAid.tone(ColorAid.hue("orange"), 0.4)}
		"Ancient":
			# Golden sandstone (tinted yellow-orange), bright and warm.
			return {"walls": ColorAid.tint(ColorAid.hue("yellow_orange"), 0.25), "walls2": ColorAid.tint(ColorAid.hue("yellow"), 0.3),
				"floor": ColorAid.shade(ColorAid.hue("yellow_orange"), 0.4), "accent": ColorAid.tint(ColorAid.hue("yellow"), 0.25),
				"pillar": ColorAid.tint(ColorAid.hue("yellow_orange"), 0.15), "fog": ColorAid.tint(ColorAid.hue("yellow_orange"), 0.55)}
		"Toxic":
			# Acid yellow sludge (olive walls, bright yellow glow).
			return {"walls": ColorAid.shade(ColorAid.hue("yellow"), 0.4), "walls2": ColorAid.tone(ColorAid.hue("yellow"), 0.3),
				"floor": ColorAid.shade(ColorAid.hue("yellow"), 0.55), "accent": ColorAid.hue("yellow"),
				"pillar": ColorAid.tone(ColorAid.hue("yellow"), 0.4), "fog": ColorAid.tint(ColorAid.hue("yellow"), 0.4)}
		"Irradiated":
			# Glowing radioactive lime (yellow-green), distinct from Toxic yellow & Overgrown green.
			return {"walls": ColorAid.shade(ColorAid.hue("yellow_green"), 0.4), "walls2": ColorAid.tint(ColorAid.hue("yellow_green"), 0.35),
				"floor": ColorAid.shade(ColorAid.hue("yellow_green"), 0.55), "accent": ColorAid.tint(ColorAid.hue("yellow_green"), 0.1),
				"pillar": ColorAid.shade(ColorAid.hue("yellow_green"), 0.5), "fog": ColorAid.tint(ColorAid.hue("yellow_green"), 0.45)}
		"Overgrown":
			# Verdant true green.
			return {"walls": ColorAid.shade(ColorAid.hue("green"), 0.3), "walls2": ColorAid.tint(ColorAid.hue("green"), 0.2),
				"floor": ColorAid.shade(ColorAid.hue("green"), 0.55), "accent": ColorAid.hue("green"),
				"pillar": ColorAid.shade(ColorAid.hue("green"), 0.45), "fog": ColorAid.tint(ColorAid.hue("green"), 0.4)}
		"Waterfall":
			# Bright teal / spray-white with a luminous cyan accent (the falling water).
			var teal := ColorAid.tint(ColorAid.hue("blue_green"), 0.45)
			return {"walls": ColorAid.tint(ColorAid.hue("blue_green"), 0.55), "walls2": ColorAid.tint(ColorAid.hue("blue"), 0.5),
				"floor": ColorAid.shade(ColorAid.hue("blue_green"), 0.4), "accent": ColorAid.tint(ColorAid.hue("blue"), 0.6),
				"pillar": ColorAid.tint(teal, 0.2), "fog": ColorAid.tint(ColorAid.hue("blue"), 0.7)}
		"Pristine":
			# Clean white with cool blue accents (neutral-white identity).
			return {"walls": WHITE, "walls2": ColorAid.tint(ColorAid.hue("blue"), 0.6),
				"floor": ColorAid.tint(GREY, 0.5), "accent": ColorAid.tint(ColorAid.hue("blue"), 0.5),
				"pillar": ColorAid.tint(ColorAid.hue("blue"), 0.5), "fog": ColorAid.tint(ColorAid.hue("blue"), 0.82)}
		"Petrified":
			# Stone grey with petrified-wood tan (neutral-grey identity).
			return {"walls": ColorAid.tone(GREY, 0.2), "walls2": ColorAid.shade(ColorAid.hue("yellow_orange"), 0.5),
				"floor": ColorAid.tone(GREY, 0.4), "accent": ColorAid.tone(ColorAid.hue("orange"), 0.4),
				"pillar": GREY, "fog": ColorAid.tint(GREY, 0.25)}
		_:
			# Neutral fallback for any unmapped modifier.
			return {"walls": ColorAid.tint(GREY, 0.1), "walls2": GREY, "floor": ColorAid.shade(GREY, 0.25),
				"accent": ColorAid.tint(ColorAid.hue("orange"), 0.2), "pillar": GREY, "fog": ColorAid.shade(GREY, 0.35)}

# --- Feature-object prop styles (keyword-driven) ---------------------------
# The biome table gives each biome ~10 uniquely-named objects (540 total), so styles
# are inferred by keyword instead of a fixed word->style map: a SHAPE from the small
# set the generators can build (mushroom/frond/crystal/vent/girder/blob/rock), and a
# COLOR from an obvious material keyword (ice=blue, lava=orange, bone, ...) falling
# back to the biome accent so unmatched objects still belong to the palette.
static func _feature_style(word: String, biome_accent: Color) -> Dictionary:
	var w: String = word.to_lower()
	return {"color": _object_color(w, biome_accent), "shape": _object_shape(w)}

# First matching keyword group wins; order is specific -> generic.
const _SHAPE_KEYWORDS := [
	["mushroom", ["mushroom", "toadstool", "cap", "puffball", "fungal", "bracket", "gill", "hyphae", "mycelium", "spore"]],
	["frond", ["kelp", "coral", "vine", "frond", "reed", "cattail", "tentacle", "anemone", "weed", "grass", "moss", "leaf", "lily", "lotus", "bloom", "flower", "fan", "root", "drape", "streamer", "filament", "tendril", "wisp", "seaweed", "fern", "algae", "lichen", "creeper", "sponge", "holdfast", "sea "]],
	["crystal", ["crystal", "spire", "shard", "spike", "icicle", "quartz", "prism", "geode", "gem", "peak", "ridge", "needle", "thorn", "spine", "spur", "tusk", "facet", "column", "pillar", "trunk", "cactus", "obelisk", "stalk", "serac", "stalagmite"]],
	["vent", ["vent", "geyser", "fumarole", "jet", "spout", "pool", "pit", "crater", "fissure", "plume", "spring", "fountain", "flare", "prominence", "coronal", "spicule", "mud pot", "boiling", "sinter", "terrace", "loop"]],
	["girder", ["girder", "truss", "beam", "rebar", "rack", "panel", "plate", "frame", "bulkhead", "hull", "cable", "wire", "pipe", "conduit", "duct", "module", "container", "crate", "tile", "board", "grate", "hatch", "array", "dish", "screen", "sign", "billboard", "pylon", "coil", "machinery", "gear", "piston", "valve", "wheel", "satellite", "solar", "mast", "antenna", "tower", "strut", "spar", "rig", "console", "core"]],
	["blob", ["pod", "sac", "orb", "bubble", "clump", "nodule", "node", "mound", "ball", "egg", "cell", "bell", "jelly", "cloud", "puff", "clod", "mote", "grain", "clam", "shell", "nurser", "proto", "haze", "veil", "buoy", "granule", "sunspot"]],
]

static func _object_shape(w: String) -> String:
	for group in _SHAPE_KEYWORDS:
		for kw in group[1]:
			if w.find(kw) != -1:
				return group[0]
	return "rock"

static func _object_color(w: String, biome_accent: Color) -> Color:
	# Strong material keywords override the palette so the object reads true.
	if _has_any(w, ["ice", "frost", "snow", "rime", "glacial", "frozen", "serac", "hoarfrost"]):
		return ColorAid.tint(ColorAid.hue("blue"), 0.55)
	if _has_any(w, ["lava", "magma", "ember", "molten", "fire", "flare", "plasma", "coronal", "spatter", "prominence"]):
		return ColorAid.tint(ColorAid.hue("red_orange"), 0.1)
	if _has_any(w, ["ash", "soot", "char", "cinder", "smoke", "obsidian", "basalt", "scorch"]):
		return ColorAid.shade(GREY, 0.35)
	if _has_any(w, ["bone", "skull", "marrow", "fossil", "tusk", "vertebrae", "rib", "ossif", "spine"]):
		return Color(0.85, 0.80, 0.70)
	if _has_any(w, ["moss", "vine", "kelp", "algae", "leaf", "reed", "fern", "frond", "lily", "lotus", "creeper", "grass", "tendril", "seaweed"]):
		return ColorAid.shade(ColorAid.hue("green"), 0.35)
	if _has_any(w, ["crystal", "quartz", "prism", "geode", "gem", "glint", "facet", "refract"]):
		return ColorAid.tint(ColorAid.hue("blue_green"), 0.4)
	if _has_any(w, ["rust", "scrap", "metal", "hull", "girder", "cable", "pipe", "iron", "rebar", "steel", "reactor", "engine", "machinery"]):
		return ColorAid.tone(GREY, 0.1)
	if _has_any(w, ["neon", "glow", "luminous", "radiant", "phosphor", "gleam", "ion", "charged", "spark", "arc", "bolt", "energy", "flux", "light", "warp"]):
		return biome_accent.lightened(0.3)
	if _has_any(w, ["sand", "dune", "desert", "salt", "dust", "sandstone", "borax", "evaporite"]):
		return Color(0.80, 0.70, 0.50)
	return biome_accent

static func _has_any(w: String, kws: Array) -> bool:
	for kw in kws:
		if w.find(kw) != -1:
			return true
	return false

# --- Auto shape-dressing (cave spikes), tinted to the biome ----------------
static func _dressing(pal: Dictionary) -> Array:
	return [
		{"shape": "stalagmite", "color": pal.pillar},
		{"shape": "stalactite", "color": pal.walls},
	]
