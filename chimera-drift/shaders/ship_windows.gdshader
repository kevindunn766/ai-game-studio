shader_type spatial;

// Rows of windows on the ship BODY's vertical LATERAL sides only (Kevin): windows are
// drawn only where a face's normal is dominantly along X (the left/right flanks), not on
// top/bottom or the nose/tail. No UVs on the generated hull, so the grid is stamped from
// object-local (Z = length, Y = height). Lower, rectangular density so they read as
// windows rather than spots. A per-cell hash lights a fraction (warm cabin light,
// emissive); unlit panes darken so they still read as recessed. Lit like a normal surface.

uniform vec4 albedo : source_color = vec4(0.6, 0.6, 0.65, 1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.25;
uniform float roughness : hint_range(0.0, 1.0) = 0.5;
uniform vec4 window_color : source_color = vec4(1.0, 0.86, 0.55, 1.0);
uniform float window_energy = 3.2;
uniform float lit_fraction : hint_range(0.0, 1.0) = 0.5;
// Cells per object-space unit along (length Z, height Y). Wider-in-Z than tall -> the
// panes read as horizontal windows. Kept low so they're clearly windows, not speckle.
uniform vec2 window_density = vec2(3.0, 5.0);
uniform float window_margin : hint_range(0.0, 0.49) = 0.22;   // pane frame thickness
uniform float side_threshold : hint_range(0.0, 1.0) = 0.45;   // how X-facing a face must be

varying vec3 v_local;
varying vec3 v_norm;

void vertex() {
	v_local = VERTEX;
	v_norm = NORMAL;
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	ALBEDO = albedo.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;

	vec3 an = abs(v_norm);
	// Vertical lateral sides only: normal dominantly along X (the flanks).
	bool is_side = an.x >= an.y && an.x >= an.z && an.x > side_threshold;
	if (is_side) {
		vec2 guv = v_local.zy;               // along length (Z), height (Y)
		vec2 g = guv * window_density;
		vec2 cell = floor(g);
		vec2 f = fract(g);
		float pane = step(window_margin, f.x) * step(f.x, 1.0 - window_margin)
				   * step(window_margin, f.y) * step(f.y, 1.0 - window_margin);
		float rnd = hash21(cell + vec2(3.1, 7.7));
		float lit = step(1.0 - lit_fraction, rnd) * pane;
		ALBEDO = mix(ALBEDO, ALBEDO * 0.35, pane * (1.0 - lit));
		EMISSION = window_color.rgb * window_energy * lit;
	}
}
