shader_type canvas_item;

// VHS / CRT title effect for a TextureRect showing the rendered title text.
// ALWAYS ON: fine scanlines + a subtle chromatic (RGB-split) diffraction fringe.
// BURSTS: when `glitch` (0..1, driven from GDScript) spikes, the RGB split widens,
// rows tear/displace horizontally, and the brightness flickers -- a tape-glitch pop.

uniform float glitch : hint_range(0.0, 1.0) = 0.0;   // burst intensity (from GDScript)
uniform float aberration = 0.0022;   // constant base RGB split
uniform float scan_alpha = 0.28;     // scanline darkness
uniform float scan_period = 3.0;     // pixels per scanline pair

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;

	// Row-based horizontal tear/displacement (only meaningful during a burst).
	float row = floor(uv.y * 48.0);
	float seed = floor(TIME * 15.0);
	float rr = hash(vec2(row, seed));
	float shift = 0.0;
	if (rr > 0.80) {
		shift = (hash(vec2(row, seed + 3.0)) - 0.5) * 0.18 * glitch;
	}
	vec2 suv = vec2(uv.x + shift, uv.y);

	// Chromatic aberration / diffraction: sample R and B offset from G -> colour fringe.
	float ab = aberration + glitch * 0.018;
	vec4 cr = texture(TEXTURE, suv + vec2(ab, 0.0));
	vec4 cg = texture(TEXTURE, suv);
	vec4 cb = texture(TEXTURE, suv - vec2(ab, 0.0));
	float a = max(cr.a, max(cg.a, cb.a));
	vec3 rgb = vec3(cr.r, cg.g, cb.b);

	// Scanlines.
	float sl = step(0.5, fract(FRAGCOORD.y / scan_period));
	rgb *= (1.0 - scan_alpha * sl);

	// Brightness flicker during the burst.
	rgb *= 1.0 + glitch * (hash(vec2(seed, 1.0)) - 0.35) * 0.7;

	COLOR = vec4(rgb, a) * COLOR;
}
