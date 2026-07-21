shader_type canvas_item;
// Full-screen underwater post-process (2026-07-19). A single cheap pass over the rendered
// scene that: tints everything light blue, adds swaying god-ray shafts + animated caustics,
// splits the channels toward the edges for a refractive-rainbow fringe, and softens
// (blurs) the edges so they read "fuzzy". Runs only on underwater levels (toggled by the
// director). ~8 screen taps; no extra passes.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec3 water_tint : source_color = vec3(0.45, 0.72, 0.95);
uniform float tint_strength = 0.4;
uniform float aberration = 0.006;     // refractive rainbow (chromatic split) toward edges
uniform float blur_amount = 0.003;    // fuzzy edges
uniform float godray_strength = 0.16;
uniform float caustic_strength = 0.12;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float edge = clamp(dot(c, c) * 4.0, 0.0, 1.0);   // 0 centre -> ~1 at the corners

	// Refractive rainbow: sample R/G/B at spreading offsets (stronger toward edges),
	// wobbled over time so the fringe shimmers like light through water.
	float wob = 0.8 + 0.4 * sin(uv.y * 40.0 + TIME * 1.5);
	vec2 off = normalize(c + 1e-5) * aberration * (0.3 + edge) * wob;
	vec3 col;
	col.r = texture(screen_tex, uv + off).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - off).b;

	// Fuzzy edges: a cheap 4-tap box blur mixed in by how far out we are.
	vec3 blur = texture(screen_tex, uv + vec2(blur_amount, 0.0)).rgb
			  + texture(screen_tex, uv - vec2(blur_amount, 0.0)).rgb
			  + texture(screen_tex, uv + vec2(0.0, blur_amount)).rgb
			  + texture(screen_tex, uv - vec2(0.0, blur_amount)).rgb;
	col = mix(col, blur * 0.25, edge);

	// Light-blue underwater tint over everything.
	col = mix(col, col * water_tint + water_tint * 0.12, tint_strength);

	// God rays: soft vertical shafts swaying over time, brighter toward the surface (top).
	float shafts = max(0.0, sin(uv.x * 18.0 + TIME * 0.6 + sin(uv.y * 3.0) * 1.5))
				 * max(0.0, sin(uv.x * 33.0 - TIME * 0.4));
	col += water_tint * shafts * godray_strength * (1.0 - uv.y);

	// Caustics: animated interference net, faded a touch toward the edges.
	vec2 q = uv * 8.0;
	float ca = max(0.0, sin(q.x + TIME) * sin(q.y - TIME * 0.8) + sin((q.x + q.y) * 0.7 + TIME * 1.3));
	col += water_tint * ca * caustic_strength * (1.0 - edge * 0.4);

	COLOR = vec4(col, 1.0);
}
