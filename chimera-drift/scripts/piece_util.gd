extends RefCounted

# Helpers for the between-levels "piece draft" (the beauty-shot menu). Which
# collected pickups count as a keepable PIECE, and how each reads in the menu.
# No class_name (headless-safe -- referenced via preload const).
#
# A piece is keepable if it bolts onto the hull (grows_ship) AND is either a
# cosmetic hull part (no effect) or a PERMANENT upgrade. Transient buffs
# (speed_boost / magnet / weapon_up) are deliberately NOT offered as permanent.

const PERMANENT_EFFECTS := ["shield", "fire_rate", "afterburner"]

static func is_eligible(effect: String, grows_ship: bool) -> bool:
	if not grows_ship:
		return false
	return effect == "" or effect in PERMANENT_EFFECTS

# Short, legible menu label for a piece.
static func label_for(kind: String, effect: String) -> String:
	match effect:
		"shield":
			return "SHIELD PLATE"
		"fire_rate":
			return "RAPID FIRE"
		"afterburner":
			return "AFTERBURNER"
		_:
			return kind.to_upper() if kind != "" else "HULL PART"

# A one-line description of what keeping the piece does (menu subtitle).
static func blurb_for(effect: String) -> String:
	match effect:
		"shield":
			return "+ shield capacity, every stage"
		"fire_rate":
			return "faster fire, every stage"
		"afterburner":
			return "unlocks the afterburner boost"
		_:
			return "a permanent hull part"
