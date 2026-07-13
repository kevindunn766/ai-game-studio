shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, blend_mix;

// Movement trail's scorch mark: a soft-edged circular burn spot computed
// from UV distance, not a flat opaque quad -- avoids the "hard black square"
// look. fade drives both alpha and lets movement_trail.gd animate it out
// over scorch_fade_duration without needing a separate mesh-scale tween.

uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform vec3 scorch_color : source_color = vec3(0.05, 0.03, 0.02);
uniform float softness : hint_range(0.01, 1.0) = 0.4;

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float d = length(centered);
	float mask = 1.0 - smoothstep(1.0 - softness, 1.0, d);
	ALBEDO = scorch_color;
	ALPHA = mask * fade;
}
