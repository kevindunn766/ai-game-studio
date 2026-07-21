// Depth-driven tilt-shift for INSTAR.
// Full-screen post pass (spatial shader on a fullscreen quad). Reads the scene
// color + depth; keeps a narrow band around `focus_depth` sharp and blurs the
// rest, so the isometric scene reads like a miniature diorama.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

uniform float focus_depth = 12.0;    // view-space distance kept sharp (fed per-frame)
uniform float focus_range = 1.2;     // half-width of the sharp band
uniform float focus_falloff = 6.0;   // how quickly blur ramps past the band
uniform float max_blur = 5.0;        // max blur radius (screen texels * 8)
uniform float saturation = 1.15;     // slight pop for the miniature look

void vertex() {
	// Cover the whole screen regardless of this quad's transform.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float linear_view_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
	vec4 view = inv_proj * vec4(ndc, 1.0);
	return -(view.z / view.w);
}

void fragment() {
	vec2 texel = 1.0 / vec2(textureSize(screen_tex, 0));
	float lz = linear_view_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float coc = clamp((abs(lz - focus_depth) - focus_range) / focus_falloff, 0.0, 1.0);
	float radius = coc * max_blur;

	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	if (radius > 0.25) {
		vec3 sum = col;
		float wsum = 1.0;
		const int N = 16;
		for (int i = 0; i < N; i++) {
			float ang = float(i) * 2.3999632;             // golden angle
			float rr = sqrt((float(i) + 0.5) / float(N));  // even disk coverage
			vec2 off = vec2(cos(ang), sin(ang)) * rr * radius * texel * 8.0;
			sum += texture(screen_tex, SCREEN_UV + off).rgb;
			wsum += 1.0;
		}
		col = sum / wsum;
	}

	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, saturation);
	ALBEDO = col;
}
