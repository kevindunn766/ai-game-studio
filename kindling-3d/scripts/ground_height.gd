extends RefCounted

# The shared ground height field. A periodic (tileable) value-noise fBm is baked once into a
# single-channel image; the ground shader samples the matching texture for its displacement,
# and objects sample this image on the CPU to sit exactly on the surface. Because both read
# the SAME baked data (with the same half-texel convention), plants never float or bury.

const IMG: int = 128            # baked tile resolution
const BASE_GRID: int = 6        # base lattice cells across one tile
const OCTAVES: int = 4
const PERIOD: float = 5.0       # content units per height tile
const AMP: float = 0.22         # displacement amplitude (content units), a little depth

var image: Image = null
var texture: ImageTexture = null


func _init() -> void:
	image = Image.create(IMG, IMG, false, Image.FORMAT_RF)
	for y in range(IMG):
		for x in range(IMG):
			var v: float = _pfbm(float(x) / float(IMG), float(y) / float(IMG))
			image.set_pixel(x, y, Color(v, 0.0, 0.0))
	texture = ImageTexture.create_from_image(image)


# Displacement height (content units) at a content-space XZ -- matches the shader's
# texture(height_tex, c / PERIOD) bilinear sample (including the half-texel centre offset).
func height(cx: float, cz: float) -> float:
	var u: float = fposmod(cx / PERIOD, 1.0) * float(IMG) - 0.5
	var v: float = fposmod(cz / PERIOD, 1.0) * float(IMG) - 0.5
	var x0: int = int(floor(u))
	var y0: int = int(floor(v))
	var fx: float = u - float(x0)
	var fy: float = v - float(y0)
	var xa: int = posmod(x0, IMG)
	var ya: int = posmod(y0, IMG)
	var xb: int = posmod(x0 + 1, IMG)
	var yb: int = posmod(y0 + 1, IMG)
	var a: float = image.get_pixel(xa, ya).r
	var b: float = image.get_pixel(xb, ya).r
	var c: float = image.get_pixel(xa, yb).r
	var d: float = image.get_pixel(xb, yb).r
	var val: float = lerp(lerp(a, b, fx), lerp(c, d, fx), fy)
	return (val - 0.5) * AMP


func _pfbm(u: float, v: float) -> float:
	var s: float = 0.0
	var amp: float = 0.5
	var grid: int = BASE_GRID
	for o in range(OCTAVES):
		s += amp * _pvalue(u * float(grid), v * float(grid), grid)
		grid *= 2
		amp *= 0.5
	return clampf(s, 0.0, 1.0)


# Periodic value noise: the lattice wraps at `period`, so the tile is seamless.
func _pvalue(x: float, z: float, period: int) -> float:
	var xi: int = int(floor(x))
	var zi: int = int(floor(z))
	var xf: float = x - float(xi)
	var zf: float = z - float(zi)
	xf = xf * xf * (3.0 - 2.0 * xf)
	zf = zf * zf * (3.0 - 2.0 * zf)
	var a: float = _lhash(posmod(xi, period), posmod(zi, period))
	var b: float = _lhash(posmod(xi + 1, period), posmod(zi, period))
	var c: float = _lhash(posmod(xi, period), posmod(zi + 1, period))
	var d: float = _lhash(posmod(xi + 1, period), posmod(zi + 1, period))
	return lerp(lerp(a, b, xf), lerp(c, d, xf), zf)


func _lhash(ix: int, iz: int) -> float:
	var h: int = (ix * 73856093) ^ (iz * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	return float(h & 0xFFFFFF) / float(0xFFFFFF)
