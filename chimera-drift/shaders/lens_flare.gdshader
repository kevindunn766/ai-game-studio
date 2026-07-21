shader_type canvas_item;
render_mode blend_add;

// Screen-space LENS FLARE for a full-rect ColorRect overlay. Given the light's screen
// position `flare_pos` (0..1 UV), it draws: a bright source glow, an anamorphic
// horizontal streak, a faint vertical streak, a line of chromatic GHOST discs marching
// from the source through screen centre, and a chromatic halo ring -- the classic
// dirty-lens look. Additive; `intensity` (from GDScript) fades it as the sun leaves frame.

uniform vec2 flare_pos = vec2(0.5, 0.4);
uniform vec3 flare_color : source_color = vec3(1.0, 0.92, 0.78);
uniform float intensity = 1.0;
uniform float aspect = 1.777;

float disc(vec2 uv, vec2 c, float r) {
	float d = length((uv - c) * vec2(aspect, 1.0));
	return smoothstep(r, 0.0, d);
}

void fragment() {
	vec2 uv = UV;
	vec2 p = flare_pos;
	vec2 center = vec2(0.5, 0.5);
	vec2 dir = center - p;

	vec3 col = vec3(0.0);

	// Source: broad glow + tight core.
	col += flare_color * disc(uv, p, 0.13) * 0.9;
	col += flare_color * disc(uv, p, 0.035) * 2.0;

	// Anamorphic streaks (cool blue), horizontal strong + vertical faint.
	vec2 d2 = (uv - p) * vec2(aspect, 1.0);
	col += vec3(0.5, 0.7, 1.0) * exp(-abs(d2.y) * 150.0) * exp(-abs(d2.x) * 2.0) * 1.7;
	col += vec3(0.6, 0.75, 1.0) * exp(-abs(d2.x) * 150.0) * exp(-abs(d2.y) * 3.2) * 0.7;

	// Chromatic ghost discs along the source->centre axis.
	col += vec3(0.4, 0.6, 1.0) * disc(uv, p + dir * -0.35, 0.05) * 0.35;
	col += vec3(1.0, 0.7, 0.4) * disc(uv, p + dir * 0.30, 0.085) * 0.30;
	col += vec3(0.5, 1.0, 0.7) * disc(uv, p + dir * 0.52, 0.03) * 0.32;
	col += vec3(0.9, 0.5, 1.0) * disc(uv, p + dir * 0.74, 0.12) * 0.18;
	col += vec3(1.0, 0.9, 0.5) * disc(uv, p + dir * 1.15, 0.06) * 0.28;
	col += vec3(0.6, 0.8, 1.0) * disc(uv, p + dir * 1.5, 0.09) * 0.20;

	// Chromatic halo ring around the centre (R/G/B at slightly different radii).
	float rr = length((uv - center) * vec2(aspect, 1.0));
	vec3 ring = vec3(
		smoothstep(0.02, 0.0, abs(rr - 0.265)),
		smoothstep(0.02, 0.0, abs(rr - 0.285)),
		smoothstep(0.02, 0.0, abs(rr - 0.305)));
	col += ring * 0.14;

	COLOR = vec4(col * intensity, 1.0);
}
