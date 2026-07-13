shader_type spatial;

// Structure Fuel's shared burn-down look: a procedural (texture-free, no
// external asset) value-noise cutout advancing as burn_progress rises from
// 0->1, so the char/transparency edge reads as an organic front rather than
// a uniform wipe. UV-based (not screen-space) so the pattern stays locked to
// the object rather than sliding as the camera moves.

uniform float burn_progress : hint_range(0.0, 1.0) = 0.0;
uniform vec3 albedo_color : source_color = vec3(0.6, 0.6, 0.6);
uniform vec3 edge_color : source_color = vec3(1.0, 0.4, 0.05);
uniform float edge_width : hint_range(0.01, 0.5) = 0.12;
uniform float noise_scale : hint_range(1.0, 40.0) = 12.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float proc_noise(vec2 uv) {
	vec2 i = floor(uv);
	vec2 f = fract(uv);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	float n = proc_noise(UV * noise_scale);
	if (n < burn_progress) {
		discard;
	}
	float edge = smoothstep(burn_progress, burn_progress + edge_width, n);
	ALBEDO = mix(edge_color, albedo_color, edge);
	EMISSION = edge_color * (1.0 - edge) * 2.0;
	ROUGHNESS = 0.8;
}
