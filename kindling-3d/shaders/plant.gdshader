shader_type spatial;
render_mode cull_disabled;   // frond blades are thin -- show from both sides

// Per-instance plant shading for the MultiMesh-instanced fronds. Every plant of a tier
// shares one material + one mesh (GPU instancing on the tessellated ground); the burn
// state that used to live on a per-plant node now rides in each instance's CUSTOM data:
//   INSTANCE_CUSTOM.r = char amount  (0 = fresh tier colour, 1 = blackened)
//   INSTANCE_CUSTOM.g = grey amount  (1 = burnt-out ash, after the squash)
// main.gd's distance check flips these per instance so burning still reads exactly like
// the old per-node version (blacken -> squash -> grey), with no Area3D nodes.

uniform vec3 base_color : source_color = vec3(0.36, 0.62, 0.22);

const vec3 CHAR_COLOR = vec3(0.05, 0.04, 0.035);   // blackened (matches old main.gd CHAR_COLOR)
const vec3 ASH_GREY = vec3(0.5, 0.5, 0.5);         // burnt-out (matches old _grey_out)

varying vec2 v_burn;

void vertex() {
	v_burn = clamp(INSTANCE_CUSTOM.rg, vec2(0.0), vec2(1.0));
}

void fragment() {
	vec3 col = mix(base_color, CHAR_COLOR, v_burn.x);   // fresh -> black
	col = mix(col, ASH_GREY, v_burn.y);                 // black -> grey ash
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
