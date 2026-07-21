shader_type spatial;
render_mode cull_back, diffuse_burley;

// Proximity-driven wiggle. Each frond reads the shared player position (set once
// per frame by the corridor) and sways only when the ship is close. The sway
// grows toward the frond's tip: vertex COLOR.r carries a 0-at-base .. 1-at-tip
// weight baked into the mesh by LevelGeo.frond().

uniform vec4 albedo : source_color = vec4(0.4, 0.6, 0.3, 1.0);
uniform float phase = 0.0;          // per-instance, so fronds don't sway in lockstep
uniform float sway = 0.18;          // max horizontal displacement (world units) at the tip
uniform float near_dist = 4.5;      // full sway within this distance to the ship
uniform float far_dist = 10.0;      // no sway beyond this distance

global uniform vec3 frond_player_pos;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;                       // this frond's world base
	float d = distance(origin, frond_player_pos);
	float prox = 1.0 - smoothstep(near_dist, far_dist, d);   // 1 near .. 0 far
	float w = COLOR.r;                                       // 0 base .. 1 tip
	float t = TIME * 3.2 + phase;
	VERTEX.x += sin(t + w * 4.0) * sway * w * prox;
	VERTEX.z += cos(t * 0.8 + phase) * sway * 0.55 * w * prox;
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = 0.8;
	METALLIC = 0.0;
}
