shader_type spatial;
render_mode cull_disabled;   // crossed quads -- show both faces

// Grass-card shading with a per-instance BURN tint. The card texture is an alpha cutout;
// when the flame touches a card the streamer fades it toward black then grey via the
// instance's MultiMesh CUSTOM data (same scheme as plant.gdshader):
//   INSTANCE_CUSTOM.r = char amount (0 fresh -> 1 black)
//   INSTANCE_CUSTOM.g = grey amount (1 = burnt-out ash)
uniform sampler2D card_tex : source_color, filter_nearest;

const vec3 CHAR_COLOR = vec3(0.05, 0.04, 0.035);   // blackened
const vec3 ASH_GREY = vec3(0.5, 0.5, 0.5);         // burnt-out

varying vec2 v_burn;

void vertex() {
	v_burn = clamp(INSTANCE_CUSTOM.rg, vec2(0.0), vec2(1.0));
}

void fragment() {
	vec4 t = texture(card_tex, UV);
	if (t.a < 0.5) {
		discard;                          // crisp cutout, no magenta fringe (nearest filter)
	}
	vec3 col = mix(t.rgb, CHAR_COLOR, v_burn.x);   // fresh -> black
	col = mix(col, ASH_GREY, v_burn.y);            // black -> grey ash
	ALBEDO = col;
	ROUGHNESS = 1.0;
}
