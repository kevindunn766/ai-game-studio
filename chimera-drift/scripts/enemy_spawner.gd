extends RefCounted

# Factory for the flying-enemy roster. Each generator computes shape-appropriate
# spawn positions (lane, terrain, ring) and calls create() to get a configured
# enemy node, then parents it and sets its position. Centralizing construction
# here keeps the two enemy categories' tuning + drop tables in one place instead
# of duplicated across the three generators.
#
# Two categories, per Kevin's design:
#   "dumb"  -> radial swarmer built from the level's feature objects; drops a
#              TEMPORARY shooting upgrade (single -> double -> triple -> spread).
#   "smart" -> ship-pipeline dogfighter themed to the level; drops a PERMANENT
#              ship piece (shield / rate-of-fire / afterburner).

const DUMB := preload("res://scripts/enemy_dumb.gd")
const SMART := preload("res://scripts/enemy_smart.gd")

# Global size multiplier on flying enemies (Kevin: shrink enemies by half). Drives both the
# visual (built from enemy_scale) and the hurtbox (_hurt_radius), so the whole enemy shrinks.
const ENEMY_SCALE_MULT: float = 0.5

# Permanent pieces a smart enemy can drop, with the greeble silhouette each adds
# to the hull when collected (so the upgrade is visually legible on the ship).
const SMART_DROPS := [
	{"effect": "shield", "kind": "plate"},      # armor plating
	{"effect": "fire_rate", "kind": "vent"},    # cooling vents
	{"effect": "afterburner", "kind": "barrel"},# thruster nozzle
]

static func create(kind: String, ship: Node3D, theme: Dictionary, feature_words: Dictionary, enemy_scale: float, rng: RandomNumberGenerator) -> Area3D:
	var accent: Color = theme.get("accent", Color(0.9, 0.4, 0.3, 1.0))
	var e: Area3D
	if kind == "smart":
		e = SMART.new()
		e.max_health = 9.0
		e.health = 9.0
		var pick: Dictionary = SMART_DROPS[rng.randi_range(0, SMART_DROPS.size() - 1)]
		e.drop_effect = pick.effect
		e.drop_kind = pick.kind
		e.drop_grows_ship = true                # a permanent piece bolts onto the ship
	else:
		e = DUMB.new()
		e.max_health = 3.0
		e.health = 3.0
		e.drop_effect = "weapon_up"             # temporary shooting-tier boost
		e.drop_kind = "cosmetic"
		e.drop_grows_ship = false               # temporary buff, not a permanent piece
		e.feature_shape = _pick_feature_shape(theme, feature_words, rng)
		e.shoots = rng.randf() < 0.45
	e.ship = ship
	e.theme = theme
	e.enemy_scale = enemy_scale * ENEMY_SCALE_MULT   # half-size enemies
	e.accent = accent
	return e

# Choose which level object the dumb ring is built from: prefer a rolled feature
# word's theme shape, so the swarmer matches what the level is dressed with.
static func _pick_feature_shape(theme: Dictionary, feature_words: Dictionary, rng: RandomNumberGenerator) -> String:
	var features: Dictionary = theme.get("features", {})
	var shapes: Array = []
	for word in feature_words.keys():
		if features.has(word) and features[word].has("shape"):
			shapes.append(features[word].shape)
	if shapes.is_empty():
		return "mushroom"
	return shapes[rng.randi_range(0, shapes.size() - 1)]
