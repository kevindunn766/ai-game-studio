shader_type spatial;
// X-ray silhouette pass -- ONLY visible where the ship is OCCLUDED by other
// geometry. A next_pass on the ship hull + attachments. In the open it draws
// nothing; behind a wall/prop the ship's outline shows through, in the level theme.
//
// It runs with depth_test_disabled (so the GPU doesn't cull the occluded fragments
// before our shader), reconstructs the view-space Z of the nearest opaque surface
// from the depth texture, and draws ONLY where that surface is IN FRONT OF the whole
// ship -- i.e. closer to the camera than the ship's nearest point (`ship_front_vz`,
// fed per frame by ship.gd). A real occluder is always in front of the ship; the
// ship's OWN parts never are, so this can't x-ray the ship against itself.
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_back, blend_add;

uniform vec3 xray_color : source_color = vec3(0.4, 0.8, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 2.0;
uniform float strength : hint_range(0.0, 3.0) = 1.4;
// View-space Z of the ship's nearest point (negative = in front of camera). Until
// ship.gd sets it, the huge default means "nothing is in front of the ship" -> off.
uniform float ship_front_vz = 100000.0;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;

void fragment() {
	float d = texture(depth_tex, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, d);
	vec4 vp = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float scene_vz = vp.z / vp.w;     // view-space Z of the nearest opaque surface
	// Draw only where that surface is closer to the camera than the whole ship.
	// (view Z: less negative = closer, so a real occluder has scene_vz > ship_front_vz.)
	if (scene_vz <= ship_front_vz) {
		discard;
	}
	float fres = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(fres, rim_power);
	ALBEDO = xray_color;
	EMISSION = xray_color * rim;
	ALPHA = clamp(rim * strength, 0.0, 1.0);
}
