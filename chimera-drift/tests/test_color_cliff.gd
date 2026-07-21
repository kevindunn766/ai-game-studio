extends Node

# Verifies (1) the Itten complementary used for pickup colours matches the artist pairs Kevin
# named (purple->yellow, blue->orange), including on tinted level colours, and (2) iso/3-4
# canyon levels force the cliffside on while third-person canyons don't.

const ColorAidS := preload("res://scripts/color_aid.gd")

var _fail: int = 0
func _ok(c: bool, m: String) -> void:
	print(("  PASS: " if c else "  FAIL: "), m)
	if not c: _fail += 1

func _ready() -> void:
	print("=== complementary + cliff test ===")

	# Complementary pairs (result is a vivid HUES_12 swatch).
	_ok(ColorAidS.complementary(ColorAidS.hue("violet")).is_equal_approx(ColorAidS.hue("yellow")), "purple/violet -> yellow")
	_ok(ColorAidS.complementary(ColorAidS.hue("blue")).is_equal_approx(ColorAidS.hue("orange")), "blue -> orange")
	_ok(ColorAidS.complementary(ColorAidS.hue("red")).is_equal_approx(ColorAidS.hue("green")), "red -> green")
	# A tinted purple (like a real theme accent) still complements to yellow.
	var tinted_purple: Color = ColorAidS.tint(ColorAidS.hue("violet"), 0.4)
	_ok(ColorAidS.complementary(tinted_purple).is_equal_approx(ColorAidS.hue("yellow")), "tinted purple accent -> yellow")

	# Cliff force: iso/3-4 canyon = cliffside; third-person canyon = none.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_ok(LevelSeed._roll_cliff("Sunken Temple Ruins", "canyon", "isometric", rng).get("enabled"), "iso canyon -> cliffside ON")
	_ok(LevelSeed._roll_cliff("Sunken Temple Ruins", "canyon", "threequarter", rng).get("enabled"), "3/4 canyon -> cliffside ON")
	_ok(not LevelSeed._roll_cliff("Sunken Temple Ruins", "canyon", "thirdperson", rng).get("enabled"), "3rd-person canyon -> no cliff (angled-only rule)")

	print("=== %s ===" % ("ALL PASS" if _fail == 0 else "%d FAILURES" % _fail))
	get_tree().quit(_fail)
