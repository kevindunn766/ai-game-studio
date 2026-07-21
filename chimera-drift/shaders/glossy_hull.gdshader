shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

// ============================================================================
// Chimera Drift — glossy hull (post-level beauty shot)
// The showcase counterpart to the grey-box gameplay hull: painted metal that
// reflects the skybox via IBL (low roughness + metallic) and PROCEDURALLY adds
// the surface detail the grey-box lacks — panel seams, corner rivets, a brushed
// micro-grain, edge wear, and a fresnel accent rim that picks up the sky/theme
// colour at grazing angles.
//
// The generated hull has NO UVs, so every detail is stamped from OBJECT space,
// triplanar-blended by the face normal (same idea as ship_windows.gdshader).
// GL-Compatibility safe: reflection is sky radiance, no screen-texture / SSR.
// ============================================================================

uniform vec4 albedo : source_color = vec4(0.55, 0.57, 0.62, 1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.65;
uniform float roughness : hint_range(0.0, 1.0) = 0.28;
uniform float specular : hint_range(0.0, 1.0) = 0.6;

// --- procedural detail ---
uniform float panel_scale = 11.0;                     // seams per object unit (finer grid)
uniform float panel_strength : hint_range(0.0, 1.0) = 0.5;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.35;
uniform float wear_strength : hint_range(0.0, 1.0) = 0.4;
uniform float detail_seed = 0.0;

// --- rust (per-ship chance; oxidation that collects on seams + worn edges) ---
uniform float rust_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 rust_color : source_color = vec4(0.42, 0.2, 0.09, 1.0);

// --- fresnel accent rim (reads the sky/theme colour on the silhouette) ---
uniform vec4 rim_color : source_color = vec4(0.6, 0.8, 1.0, 1.0);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.55;
uniform float rim_power : hint_range(1.0, 8.0) = 3.5;

varying vec3 v_obj;
varying vec3 v_onrm;

void vertex() {
	v_obj = VERTEX;
	v_onrm = normalize(NORMAL);
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float fbm2(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return s;
}

// Seam line mask on a plane coordinate: 1 near a cell edge, 0 in the panel interior.
float seam(vec2 uv) {
	vec2 g = fract(uv);
	vec2 d = min(g, 1.0 - g);
	return 1.0 - smoothstep(0.0, 0.04, min(d.x, d.y));
}
// A rivet dot near each cell corner.
float rivets(vec2 uv) {
	return smoothstep(0.11, 0.0, length(fract(uv + 0.5) - 0.5));
}

void fragment() {
	vec3 an = abs(v_onrm);
	an /= max(an.x + an.y + an.z, 1e-4);

	vec2 uv_x = v_obj.zy * panel_scale;
	vec2 uv_y = v_obj.xz * panel_scale;
	vec2 uv_z = v_obj.xy * panel_scale;

	float seam_m = seam(uv_x) * an.x + seam(uv_y) * an.y + seam(uv_z) * an.z;
	float rivet_m = rivets(uv_x) * an.x + rivets(uv_y) * an.y + rivets(uv_z) * an.z;

	vec2 guv = uv_x * an.x + uv_y * an.y + uv_z * an.z;
	float grain = fbm2(guv * 6.0 + detail_seed);
	float mottle = fbm2(guv * 1.3 + detail_seed * 0.7);

	vec3 col = albedo.rgb;
	col *= mix(0.9, 1.08, mottle);                       // painted two-tone
	col = mix(col, col * 0.55, seam_m * panel_strength); // seams recess (darker)
	col = mix(col, col * 1.25 + 0.02, rivet_m * 0.6);    // rivets catch light
	float wear = smoothstep(0.75, 0.95, grain) * wear_strength;
	col = mix(col, vec3(0.8, 0.82, 0.85), wear * 0.5);   // bare-metal scuffs

	// Rust: patchy oxidation that collects along seams + worn specks, gated by a
	// low-frequency mottle so it blotches unevenly. Off unless rust_amount > 0.
	float rust = clamp((seam_m * 0.8 + wear * 1.3 + smoothstep(0.62, 0.9, mottle) * 0.55) * rust_amount, 0.0, 1.0);
	col = mix(col, rust_color.rgb * mix(0.7, 1.15, grain), rust);
	ALBEDO = col;

	// Glossy metal that reflects the sky: seams read rougher (recessed dirt),
	// worn scuffs read shinier (bare metal), plus a faint brushed variation.
	// Rust is matte + non-metallic, so it kills the reflection where it creeps.
	float r = roughness;
	r = mix(r, min(r + 0.35, 1.0), seam_m * 0.6);
	r = mix(r, max(r - 0.18, 0.02), wear);
	r += (grain - 0.5) * grain_strength * 0.25;
	r = mix(r, 0.9, rust);
	ROUGHNESS = clamp(r, 0.02, 1.0);
	METALLIC = clamp(metallic - seam_m * 0.25, 0.0, 1.0) * (1.0 - rust * 0.85);
	SPECULAR = specular;

	// Fresnel accent rim (NORMAL/VIEW are both view-space in the fragment stage).
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	EMISSION = rim_color.rgb * fres * rim_strength;
}
