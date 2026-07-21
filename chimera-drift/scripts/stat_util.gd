extends RefCounted

# Stat model for permanent draft parts. Some parts carry a numeric VALUE for a
# gameplay stat (fire rate / shot damage / hull armor / shield). Values are ROLLED
# per pickup and scale with progress: low + random early, better as the run goes
# deeper. The draft menu uses this to show each part's stat and whether it upgrades
# the player. No class_name (headless-safe -- referenced via preload const).

# Per-stat roll range at sector 1 (lo..hi) plus how much both ends grow per sector.
const RANGES := {
	"fire_rate":   {"lo": 0.05, "hi": 0.12, "grow": 0.028},  # + rate-of-fire multiplier
	"shot_damage": {"lo": 0.08, "hi": 0.18, "grow": 0.05},   # + damage per bullet (base 1.0)
	"armor":       {"lo": 4.0,  "hi": 9.0,  "grow": 3.0},    # + max hull HP
	"shield":      {"lo": 12.0, "hi": 24.0, "grow": 6.0},    # + shield capacity
}
const GROW_CAP := 11.0   # stat growth flattens after ~sector 12

static func has_value(effect: String) -> bool:
	return RANGES.has(effect)

# A scaled random value for `effect` at the given sector (1-based).
static func roll_value(effect: String, sector: int, rng: RandomNumberGenerator) -> float:
	if not RANGES.has(effect):
		return 0.0
	var r: Dictionary = RANGES[effect]
	var s: float = clampf(float(sector) - 1.0, 0.0, GROW_CAP)
	return rng.randf_range(r.lo + r.grow * s, r.hi + r.grow * s)

# Short stat name for the draft card.
static func label(effect: String) -> String:
	match effect:
		"fire_rate":
			return "FIRE RATE"
		"shot_damage":
			return "DAMAGE"
		"armor":
			return "ARMOR"
		"shield":
			return "SHIELD"
		_:
			return ""

# Human-readable magnitude (for the "+X" on the card).
static func format(effect: String, v: float) -> String:
	match effect:
		"fire_rate", "shot_damage":
			return "+%.2f" % v
		"armor", "shield":
			return "+%d" % int(round(v))
		_:
			return ""

# Sum of a loadout's values for a given stat (its current contribution).
static func total(loadout: Array, effect: String) -> float:
	var sum: float = 0.0
	for p_v in loadout:
		var p: Dictionary = p_v
		if p.get("effect", "") == effect:
			sum += float(p.get("value", 0.0))
	return sum
