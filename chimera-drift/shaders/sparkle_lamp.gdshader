shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

// ============================================================================
// Chimera Drift — twinkling nav-lamp sparkle (post-level beauty shot)
// A glowing point light on the hull, drawn on a camera-facing quad: a soft
// radial core + a 4-point star flare + a twinkle pulse over TIME. Additive, so
// lamps read as bright sparkles catching the eye. Pair with a real OmniLight3D
// where a lamp should actually cast light on the hull.
//
// Per-lamp phase comes from INSTANCE_CUSTOM.x so a MultiMesh of lamps twinkles
// out of sync. GL-Compatibility safe (in-shader billboard via INV_VIEW_MATRIX).
// ============================================================================

uniform vec4 lamp_color : source_color = vec4(1.0, 0.9, 0.6, 1.0);
uniform float twinkle_speed = 3.0;
uniform float flare_length : hint_range(0.0, 1.0) = 0.55;
uniform float intensity : hint_range(0.0, 4.0) = 2.0;

varying float v_phase;

void vertex() {
	v_phase = INSTANCE_CUSTOM.x * 6.2831853;
	// Camera-facing billboard (keeps the quad's own size).
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);

	float tw = 0.55 + 0.45 * sin(TIME * twinkle_speed + v_phase);

	float core = pow(smoothstep(1.0, 0.0, r), 2.5);
	float fx = smoothstep(flare_length, 0.0, abs(uv.y)) * smoothstep(1.0, 0.0, abs(uv.x));
	float fy = smoothstep(flare_length, 0.0, abs(uv.x)) * smoothstep(1.0, 0.0, abs(uv.y));
	float flare = (fx + fy) * 0.5;

	float a = (core + flare * 0.6) * tw * intensity;
	ALBEDO = lamp_color.rgb;
	ALPHA = clamp(a, 0.0, 1.0);
}
