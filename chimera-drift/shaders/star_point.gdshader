shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

// Bright round STARS for the calm menu screens (title / beauty shot). Each particle
// is a billboarded quad rendered as: a tight round core with a CHROMATIC-ABERRATION
// fringe (R/G/B sampled at slightly different radii), 4-point DIFFRACTION spikes, and
// a soft downward LIGHT TRAIL. Per-star TWINKLE from a position-seeded phase. Additive.

uniform vec4 star_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float intensity = 1.9;
uniform float aberration = 0.05;
uniform float spike_len = 0.85;

varying float v_ph;

void vertex() {
	// In-shader billboard (GL-Compatibility safe): keep the quad facing the camera.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	vec3 wp = MODEL_MATRIX[3].xyz;
	v_ph = fract(sin(dot(wp, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

float core(vec2 p, float rm) {
	float r = length(p) * rm;
	return exp(-r * r * 20.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	// Round core split per channel -> coloured diffraction fringe at the edge.
	float cr = core(p, 1.0 - aberration);
	float cg = core(p, 1.0);
	float cb = core(p, 1.0 + aberration);
	// 4-point diffraction spikes (thin bright rays along X and Y).
	float sx = pow(max(0.0, 1.0 - abs(p.y) / 0.05), 3.0) * smoothstep(spike_len, 0.0, abs(p.x));
	float sy = pow(max(0.0, 1.0 - abs(p.x) / 0.05), 3.0) * smoothstep(spike_len, 0.0, abs(p.y));
	float spikes = (sx + sy) * 0.7;
	// Soft light trail (comet tail on +Y, behind the gently down-drifting stars).
	float tail = smoothstep(1.0, 0.0, length(vec2(p.x * 5.0, max(0.0, p.y)))) * 0.45;
	// Per-star twinkle.
	float tw = 0.6 + 0.4 * sin(TIME * 3.0 + v_ph * 6.2831);

	vec3 rgb = vec3(cr, cg, cb) + vec3(spikes) + vec3(tail);
	float a = max(max(cr, cg), max(cb, max(spikes, tail)));
	ALBEDO = star_color.rgb * rgb * COLOR.rgb;
	ALPHA = clamp(a * intensity * tw * COLOR.a, 0.0, 1.0);
}
