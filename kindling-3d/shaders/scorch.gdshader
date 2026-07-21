shader_type spatial;
render_mode cull_disabled, unshaded, shadows_disabled;

// One scorch mark of the burn trail -- a flat quad laid on the ground. Cel-shaded and
// OPAQUE with a hard cut-out edge (discard) rather than alpha blend: alpha-blended objects
// draw after the tilt-shift post quad has already captured the screen, so they'd vanish;
// an opaque cut-out renders in the normal pass and reads as crisp cel-shaded char anyway.
// `fade` (per mark, from its age) erodes the mark inward until it's gone; `seed` varies the
// edge wobble per mark.
uniform float fade = 1.0;
uniform float seed = 0.0;

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;                    // 0 at centre .. 1 at the edge
	float ang = atan(p.y, p.x);
	float edge = 0.9 + 0.08 * sin(ang * 6.0 + seed * 20.0) + 0.04 * sin(ang * 13.0 - seed * 11.0);
	float vis = edge * clamp(fade, 0.0, 1.0);     // shrinks inward as the mark ages
	if (r > vis) {
		discard;
	}
	float nr = r / max(vis, 0.001);
	vec3 char_col = vec3(0.05, 0.04, 0.035);      // burnt core
	vec3 ash_col = vec3(0.22, 0.19, 0.16);        // ashy rim
	// Thin, very irregular ash rim: the threshold rides high (so only a sliver near the
	// edge is ash) and wobbles across several frequencies (patchy -- many angles exceed 1.0
	// and get no ash at all).
	float ash_thresh = 0.90 + 0.10 * sin(ang * 7.0 + seed * 30.0) + 0.07 * sin(ang * 23.0 - seed * 12.0) + 0.05 * sin(ang * 43.0 + seed * 7.0);
	ALBEDO = mix(char_col, ash_col, step(ash_thresh, nr));
}
