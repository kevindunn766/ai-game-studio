shader_type canvas_item;
render_mode blend_mix;

// A cheap CRT/arcade overlay for a full-rect ColorRect placed on top of a screen:
// dark horizontal scanlines + a corner vignette, with a faint cool tint. It only
// ADDS a translucent dark layer (no screen read), so it's cheap and works over both
// 3D gameplay and menu backdrops. Tune alpha low over gameplay, higher on menus.

uniform float scanline_alpha = 0.14;   // strength of the dark scanlines
uniform float scanline_period = 3.0;   // pixels per line pair
uniform float vignette_strength = 0.5; // corner darkening
uniform vec3 tint : source_color = vec3(0.04, 0.10, 0.16);  // cool tint of the dark

void fragment() {
	// Scanlines: darken alternating pixel rows (FRAGCOORD is in pixels).
	float line = step(0.5, fract(FRAGCOORD.y / scanline_period));
	float a = scanline_alpha * line;

	// Vignette: darken toward the corners (UV spans 0..1 across the full-rect).
	vec2 d = UV - vec2(0.5);
	float vig = smoothstep(0.42, 0.9, length(d) * 1.35) * vignette_strength;

	float alpha = clamp(a + vig, 0.0, 0.88);
	COLOR = vec4(tint, alpha);
}
