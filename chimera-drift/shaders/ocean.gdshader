shader_type spatial;
// Lightweight fake-reflective ocean for the flat top-down water plane (2026-07-19, reworked
// for a choppier wavey look -- the first version's 3 big parallel waves made the sun's
// specular smear into long stretched streaks). Now a small FRACTAL of 5 sine octaves at
// varied directions/frequencies perturbs the NORMAL, so the sun glint shatters into scattered
// "sun-glitter" that reads as choppy water, plus a foam tint on the crests so the waviness
// shows even off-glint. Still cheap: 5 sin() + 5 cos(), no textures, no screen reflection.
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 deep_color : source_color = vec3(0.02, 0.14, 0.26);
uniform vec3 sky_color : source_color = vec3(0.55, 0.75, 0.92);
uniform vec3 foam_color : source_color = vec3(0.85, 0.95, 1.0);
uniform float wave_scale = 0.9;      // base ripple frequency (higher = smaller, choppier waves)
uniform float wave_speed = 0.8;
uniform float wave_strength = 0.16;  // how hard the normal tilts (bigger = choppier)
uniform float foam_amount = 0.18;    // crest brightening
uniform float water_roughness = 0.1; // low -> sharp sun sparkle

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Accumulate a small fractal of directional waves. Returns the normal; writes crest height.
vec3 wave_surface(vec2 p, float t, out float height) {
	vec2 g = vec2(0.0);
	float h = 0.0;
	float f = wave_scale;

	vec2 d1 = normalize(vec2(1.0, 0.35));
	float a1 = dot(p, d1) * f + t * wave_speed;
	h += sin(a1);                    g += d1 * cos(a1) * f;

	vec2 d2 = normalize(vec2(-0.45, 1.0));
	float f2 = f * 1.9;
	float a2 = dot(p, d2) * f2 + t * wave_speed * 1.25;
	h += 0.55 * sin(a2);             g += d2 * cos(a2) * f2 * 0.55;

	vec2 d3 = normalize(vec2(0.8, -0.6));
	float f3 = f * 3.6;
	float a3 = dot(p, d3) * f3 + t * wave_speed * 1.6;
	h += 0.30 * sin(a3);             g += d3 * cos(a3) * f3 * 0.30;

	vec2 d4 = normalize(vec2(-0.7, -0.5));
	float f4 = f * 7.0;
	float a4 = dot(p, d4) * f4 + t * wave_speed * 2.1;
	h += 0.16 * sin(a4);             g += d4 * cos(a4) * f4 * 0.16;

	vec2 d5 = normalize(vec2(0.2, 1.0));
	float f5 = f * 12.0;
	float a5 = dot(p, d5) * f5 + t * wave_speed * 2.6;
	h += 0.09 * sin(a5);             g += d5 * cos(a5) * f5 * 0.09;

	height = h;
	g *= wave_strength;
	return normalize(vec3(-g.x, 1.0, -g.y));
}

void fragment() {
	float h;
	vec3 n = wave_surface(world_pos.xz, TIME, h);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 base = mix(deep_color, sky_color, fres);
	// Foam/brightening on the wave crests so the choppy pattern reads even without a glint.
	base = mix(base, foam_color, smoothstep(0.7, 1.9, h) * foam_amount);
	ALBEDO = base;
	METALLIC = 0.0;
	SPECULAR = 0.7;
	ROUGHNESS = water_roughness;
}
