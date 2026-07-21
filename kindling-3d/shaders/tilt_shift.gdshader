shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled;

// Depth-based tilt-shift, drawn as a fullscreen quad (spatial shaders can read the scene
// DEPTH_TEXTURE and have INV_PROJECTION_MATRIX built in). A focal plane at `focus_distance`
// metres in front of the camera stays sharp; the scene blurs by how far each pixel's real
// depth is from that plane -- like actual tilt-shift photography. The camera is orthographic
// and fixed, so the depth spread across the frame is constant at every zoom.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float focus_distance = 20.0;    // depth of the sharp plane (view-space metres)
uniform float focus_half_width = 0.35;  // half-thickness of the sharp band (metres)
uniform float blur_falloff = 1.3;       // metres of depth over which blur ramps to max
uniform float max_blur = 2.5;           // max mip level sampled (higher = blurrier)
uniform float grain_amount = 0.025;     // classic photographic film grain strength
uniform float aberration_amount = 0.003;// chromatic aberration in the blurred areas (very slight)

void vertex() {
	// Fullscreen: QuadMesh is size 2 (verts at +/-1), so this covers the whole screen.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float d = texture(depth_tex, SCREEN_UV).x;
	// Reconstruct view-space position from the depth buffer; its -z is the depth in front
	// of the camera. (Orthographic -> this depends essentially on d alone.)
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	view.xyz /= view.w;
	float view_z = -view.z;
	float dist = abs(view_z - focus_distance);
	float t = clamp((dist - focus_half_width) / max(0.001, blur_falloff), 0.0, 1.0);
	float mip = t * max_blur;

	// Chromatic aberration, ONLY where the image is blurred (scaled by t) -- a radial split
	// of the red/blue channels, like a real lens's out-of-focus fringing.
	vec2 ab = (SCREEN_UV - 0.5) * (t * aberration_amount);
	float r = textureLod(screen_tex, SCREEN_UV + ab, mip).r;
	float g = textureLod(screen_tex, SCREEN_UV, mip).g;
	float b = textureLod(screen_tex, SCREEN_UV - ab, mip).b;
	vec3 col = vec3(r, g, b);

	// Classic monochrome film grain, animated so it shimmers frame to frame.
	vec2 seed = SCREEN_UV * 1024.0 + vec2(fract(TIME) * 137.0, fract(TIME) * 61.0);
	float grain = fract(sin(dot(seed, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	col += grain * grain_amount;

	ALBEDO = col;
}
