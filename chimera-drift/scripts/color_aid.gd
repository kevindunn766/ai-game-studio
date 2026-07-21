extends RefCounted
class_name ColorAid

# Colors in this game are structured on Itten's hue wheel -- the same
# organization the Color-Aid paper system is built on (hues x tints / shades /
# tones). The exact Color-Aid swatch RGB values are proprietary and are not
# published as data anywhere (the coloraid.com site only offers numbering-chart
# PDFs), so this module is the faithful *structure* of that system with a clean
# swap point: drop the real swatch table into HUES_12 / hue_wheel_24() later and
# everything downstream (analogous schemes, tints/shades/tones) keeps working.

# 12 canonical Itten-wheel hues (artist RYB wheel), index 0 = Yellow, stepping
# through orange -> red -> violet -> blue -> green -> yellow-green.
const HUES_12 := [
	Color(1.000, 0.929, 0.000),  # Yellow
	Color(1.000, 0.659, 0.000),  # Yellow-Orange
	Color(0.961, 0.510, 0.125),  # Orange
	Color(0.929, 0.278, 0.133),  # Red-Orange
	Color(0.929, 0.110, 0.141),  # Red
	Color(0.573, 0.153, 0.561),  # Red-Violet
	Color(0.400, 0.176, 0.569),  # Violet
	Color(0.180, 0.192, 0.573),  # Blue-Violet
	Color(0.000, 0.329, 0.651),  # Blue
	Color(0.000, 0.651, 0.612),  # Blue-Green
	Color(0.000, 0.651, 0.318),  # Green
	Color(0.553, 0.776, 0.247),  # Yellow-Green
]

# The 12 hues interpolated to 24 -- Color-Aid uses a finer hue ring than the
# 12-step teaching wheel, so we split each step once.
static func hue_wheel_24() -> Array:
	var wheel: Array = []
	for i in range(HUES_12.size()):
		var a: Color = HUES_12[i]
		var b: Color = HUES_12[(i + 1) % HUES_12.size()]
		wheel.append(a)
		wheel.append(a.lerp(b, 0.5))
	return wheel

# Named entry points into the wheel so themes can ask for a hue by name and
# tint/shade it (e.g. glacier blue = a heavily-tinted blue-green).
const NAMED_HUES := {
	"yellow": 0, "yellow_orange": 1, "orange": 2, "red_orange": 3, "red": 4,
	"red_violet": 5, "violet": 6, "blue_violet": 7, "blue": 8, "blue_green": 9,
	"green": 10, "yellow_green": 11,
}

static func hue(name: String) -> Color:
	return HUES_12[NAMED_HUES.get(name, 8)]

# Artist (Itten/RYB) complementary: the hue 6 steps across the 12-wheel. This gives the
# pairs people expect -- Yellow<->Violet, Blue<->Orange, Red<->Green -- unlike a naive HSV
# hue+0.5 (which sends purple to green). Finds the nearest wheel hue to `c`, returns its
# opposite as a vivid swatch (used to make pickups pop against the level's dominant colour).
static func complementary(c: Color) -> Color:
	var h: float = c.h
	var best: int = 0
	var best_d: float = 2.0
	for i in range(HUES_12.size()):
		var dh: float = absf(h - HUES_12[i].h)
		dh = minf(dh, 1.0 - dh)                 # circular hue distance
		if dh < best_d:
			best_d = dh
			best = i
	return HUES_12[(best + 6) % HUES_12.size()]

static func tint(c: Color, amount: float) -> Color:
	return c.lerp(Color(1, 1, 1), amount)

static func shade(c: Color, amount: float) -> Color:
	return c.lerp(Color(0, 0, 0), amount)

static func tone(c: Color, amount: float) -> Color:
	return c.lerp(Color(0.5, 0.5, 0.5), amount)

# An analogous scheme: a base hue plus its wheel neighbors, each nudged by a
# small tint / shade / tone for variety. Order fans out from the base
# (base, -1, +1, -2, +2 ...) so element 0 is always the dominant hull hue and
# later elements are progressively more distant analogues for accent parts.
static func analogous_scheme(rng: RandomNumberGenerator, count: int = 5) -> Array:
	var wheel := hue_wheel_24()
	var base := rng.randi_range(0, wheel.size() - 1)
	var spread := rng.randi_range(1, 2)  # steps between adjacent analogues
	var colors: Array = []
	for i in range(count):
		var magnitude: int = int(float(i + 1) / 2.0)
		var direction: int = 1 if i % 2 == 0 else -1
		var idx := wrapi(base + magnitude * direction * spread, 0, wheel.size())
		var c: Color = wheel[idx]
		var v := rng.randf()
		if v < 0.4:
			c = tint(c, rng.randf_range(0.1, 0.4))
		elif v < 0.7:
			c = shade(c, rng.randf_range(0.1, 0.35))
		else:
			c = tone(c, rng.randf_range(0.1, 0.3))
		colors.append(c)
	return colors
