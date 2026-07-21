shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

// ============================================================================
// Chimera Drift — fast-flight speed streaks (post-level beauty shot)
// Bright additive comet lines that rush past the ship to sell the sense that it
// is flying fast. Applied to a CPUParticles3D quad: a soft vertical streak
// (thin bright core along X, fading tips along Y) that reads as a warp-line as
// the particle flies by. Per-particle fade comes from the CPUParticles
// color_ramp via COLOR. GL-Compatibility safe (in-shader billboard).
// ============================================================================

uniform vec4 streak_color : source_color = vec4(0.7, 0.9, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 4.0) = 1.6;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float core = pow(smoothstep(0.5, 0.0, abs(uv.x)), 2.0);   // thin along X
	float len = smoothstep(1.0, 0.0, abs(uv.y));              // fade the tips
	float a = core * len * intensity * COLOR.a;               // COLOR.a = ramp fade
	ALBEDO = streak_color.rgb * COLOR.rgb;
	ALPHA = clamp(a, 0.0, 1.0);
}
