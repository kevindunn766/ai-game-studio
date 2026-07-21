shader_type sky;

// ============================================================================
// Chimera Drift — procedural sky (2026-07-17)
// One uber sky shader, 100% procedural, driven entirely by seeded uniforms
// (SkyDirector rolls them per level). Layers, back-to-front:
//   deep-space base (nebula + galaxy + Milky Way + stars)  [space levels]
//   physically-based single-scattering atmosphere          [surface levels]
//   celestial bodies (moon / gas giant / ringed) via analytic ray-sphere
//   clouds (domain-warped FBM, sun-lit) + in-sky god rays  [surface levels]
//   sun disk (limb-darkened) + Mie aureole
// The IBL cubemap pass runs a cheaper path (broad light only; no sharp
// stars/bodies) so ambient/reflection stays affordable.
// ============================================================================

// --- global ---------------------------------------------------------------
uniform float atmosphere_strength = 1.0;   // 1 surface air, 0 deep space
uniform vec3  ground_color : source_color = vec3(0.02, 0.02, 0.03);
uniform vec3  space_color  : source_color = vec3(0.005, 0.006, 0.012);
uniform vec3  sun_tint     : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_disk_size = 0.03;        // angular radius (radians-ish)
uniform float mie_amount = 1.0;            // haze / aureole / god-ray strength
uniform float exposure = 1.0;
uniform int quality = 3;                   // 0..3 perf tier: scales sample counts / layers

// --- clouds ---------------------------------------------------------------
uniform float cloud_cover = 0.0;           // 0 none .. 1 overcast
uniform float cloud_scale = 2.2;
uniform vec3  cloud_color        : source_color = vec3(1.0);
uniform vec3  cloud_shadow_color : source_color = vec3(0.35, 0.37, 0.45);
uniform float cloud_speed = 0.006;

// --- stars / Milky Way ----------------------------------------------------
uniform float star_density = 0.0;          // 0 none .. 1 dense
uniform float star_brightness = 1.0;
uniform float milkyway_strength = 0.0;
uniform vec3  milkyway_axis = vec3(0.2, 0.3, 0.93);

// --- galaxy ---------------------------------------------------------------
uniform float galaxy_strength = 0.0;
uniform vec3  galaxy_dir  = vec3(0.0, 0.2, -1.0);
uniform vec3  galaxy_axis = vec3(0.1, 0.95, 0.2);
uniform vec3  galaxy_core_color : source_color = vec3(1.0, 0.9, 0.7);
uniform vec3  galaxy_arm_color  : source_color = vec3(0.6, 0.7, 1.0);
uniform float galaxy_arms = 2.0;
uniform float galaxy_twist = 7.0;

// --- nebula ---------------------------------------------------------------
uniform float nebula_strength = 0.0;
uniform vec3  nebula_color_a : source_color = vec3(0.9, 0.2, 0.4);
uniform vec3  nebula_color_b : source_color = vec3(0.2, 0.5, 0.9);
uniform float nebula_scale = 1.4;

// --- celestial bodies (fixed array) --------------------------------------
const int MAX_BODIES = 4;
uniform int  body_count = 0;
uniform vec3 body_dir[MAX_BODIES];         // direction to each body (unit)
uniform float body_size[MAX_BODIES];       // angular radius
uniform int  body_type[MAX_BODIES];        // 0 moon, 1 gas giant, 2 ringed
uniform vec3 body_axis[MAX_BODIES];        // spin/ring axis (unit)
uniform vec3 body_color_a[MAX_BODIES];
uniform vec3 body_color_b[MAX_BODIES];
uniform float body_seed[MAX_BODIES];
uniform float body_ring_inner[MAX_BODIES]; // in planet radii
uniform float body_ring_outer[MAX_BODIES];

// ==========================================================================
// Hash / noise
// ==========================================================================
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}
vec3 hash33(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)),
			 dot(p, vec3(269.5, 183.3, 246.1)),
			 dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453123);
}
float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
			   mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}
float fbm(vec3 p, int octaves) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= octaves) { break; }
		s += a * vnoise(p);
		p *= 2.02;
		a *= 0.5;
	}
	return s;
}
// Domain-warped FBM (Inigo Quilez): billowy, non-linear structure.
float warp_fbm(vec3 p, int octaves) {
	vec3 q = vec3(fbm(p + vec3(0.0, 0.0, 0.0), octaves),
				  fbm(p + vec3(5.2, 1.3, 2.8), octaves),
				  fbm(p + vec3(1.7, 9.2, 3.1), octaves));
	return fbm(p + 4.0 * q, octaves);
}

// Star temperature -> color (blackbody-ish ramp red->white->blue).
vec3 star_color(float t) {
	vec3 cool = vec3(1.0, 0.6, 0.35);
	vec3 mid  = vec3(1.0, 0.98, 0.95);
	vec3 hot  = vec3(0.7, 0.8, 1.0);
	return t < 0.5 ? mix(cool, mid, t * 2.0) : mix(mid, hot, (t - 0.5) * 2.0);
}

// ==========================================================================
// Physically-based single-scattering atmosphere (Rayleigh + Mie ray march).
// Adapted from the common wwwtyro/Nishita single-scattering model.
// (PI is a built-in shader constant in Godot.)
// ==========================================================================
vec2 ray_sphere_i(vec3 o, vec3 d, float r) {
	float b = dot(o, d);
	float c = dot(o, o) - r * r;
	float disc = b * b - c;
	if (disc < 0.0) { return vec2(1e9, -1e9); }
	disc = sqrt(disc);
	return vec2(-b - disc, -b + disc);
}

vec3 atmosphere(vec3 rd, vec3 sun_dir, int primary_steps, int light_steps) {
	const float planetR = 6371000.0;
	const float atmoR   = 6471000.0;
	const vec3  betaR   = vec3(5.5e-6, 13.0e-6, 22.4e-6); // Rayleigh
	const float betaM   = 21e-6;                          // Mie
	const float hR = 8000.0;
	const float hM = 1200.0;
	const float g  = 0.76;
	vec3 ro = vec3(0.0, planetR + 1000.0, 0.0);

	vec2 t = ray_sphere_i(ro, rd, atmoR);
	if (t.x > t.y) { return vec3(0.0); }
	// Don't march into the planet.
	vec2 tp = ray_sphere_i(ro, rd, planetR);
	if (tp.x <= tp.y && tp.x > 0.0) { t.y = min(t.y, tp.x); }
	t.x = max(t.x, 0.0);

	float seg = (t.y - t.x) / float(primary_steps);
	float tcur = t.x;
	vec3 sumR = vec3(0.0);
	vec3 sumM = vec3(0.0);
	float odR = 0.0;
	float odM = 0.0;

	float mu = dot(rd, sun_dir);
	float phaseR = 3.0 / (16.0 * PI) * (1.0 + mu * mu);
	float gg = g * g;
	float phaseM = 3.0 / (8.0 * PI) * ((1.0 - gg) * (1.0 + mu * mu)) /
		((2.0 + gg) * pow(1.0 + gg - 2.0 * g * mu, 1.5));

	for (int i = 0; i < 24; i++) {
		if (i >= primary_steps) { break; }
		vec3 sp = ro + rd * (tcur + seg * 0.5);
		float h = length(sp) - planetR;
		float hr = exp(-h / hR) * seg;
		float hm = exp(-h / hM) * seg;
		odR += hr;
		odM += hm;
		// light ray optical depth
		vec2 tl = ray_sphere_i(sp, sun_dir, atmoR);
		float lseg = tl.y / float(light_steps);
		float lcur = 0.0;
		float lodR = 0.0;
		float lodM = 0.0;
		bool blocked = false;
		for (int j = 0; j < 12; j++) {
			if (j >= light_steps) { break; }
			vec3 lp = sp + sun_dir * (lcur + lseg * 0.5);
			float lh = length(lp) - planetR;
			if (lh < 0.0) { blocked = true; break; }
			lodR += exp(-lh / hR) * lseg;
			lodM += exp(-lh / hM) * lseg;
			lcur += lseg;
		}
		if (!blocked) {
			vec3 tau = betaR * (odR + lodR) + betaM * 1.1 * (odM + lodM);
			vec3 att = exp(-tau);
			sumR += att * hr;
			sumM += att * hm;
		}
		tcur += seg;
	}
	vec3 col = (sumR * betaR * phaseR + sumM * betaM * phaseM) * 28.0;
	// Gentle saturation lift -- the raw single-scattering result reads a touch pale.
	float l = dot(col, vec3(0.2126, 0.7152, 0.0722));
	col = max(mix(vec3(l), col, 1.25), vec3(0.0));
	return col;
}

// ==========================================================================
// Deep-space background: nebula + galaxy + Milky Way + stars.
// ==========================================================================
vec3 nebula(vec3 dir) {
	if (nebula_strength <= 0.0) { return vec3(0.0); }
	float d1 = warp_fbm(dir * nebula_scale + 11.0, 5);
	float d2 = warp_fbm(dir * nebula_scale * 2.1 + 41.0, 4);
	float density = pow(clamp(d1 * 1.4, 0.0, 1.0), 2.0);
	float glow = pow(clamp(d2, 0.0, 1.0), 2.5);
	vec3 col = mix(nebula_color_a, nebula_color_b, clamp(d2 * 1.3, 0.0, 1.0));
	col = col * density + nebula_color_b * glow * 0.5;
	// dark absorption lanes
	float dark = smoothstep(0.35, 0.7, fbm(dir * nebula_scale * 1.3 + 90.0, 4));
	col *= mix(1.0, 0.25, dark * 0.7);
	return col * nebula_strength;
}

vec3 galaxy(vec3 dir) {
	if (galaxy_strength <= 0.0) { return vec3(0.0); }
	vec3 ax = normalize(galaxy_axis);
	vec3 cen = normalize(galaxy_dir);
	// project onto galactic plane
	float hgt = dot(dir, ax);
	vec3 inplane = dir - ax * hgt;
	float r = length(inplane);
	if (r < 1e-4) { return galaxy_core_color * galaxy_strength; }
	vec3 u = normalize(cen - ax * dot(cen, ax));
	vec3 v = cross(ax, u);
	float theta = atan(dot(inplane, v), dot(inplane, u));
	float rn = r; // 0 at center .. 1 near 90deg away
	// logarithmic spiral arms
	float arm = cos(galaxy_arms * (theta - galaxy_twist * log(rn + 0.06)));
	float armMask = smoothstep(0.1, 0.9, arm);
	float radial = exp(-rn * 3.0);
	float disk = radial * mix(0.15, 1.0, armMask);
	// bright bulge
	float bulge = exp(-rn * rn * 42.0);
	// vertical falloff (thin disk)
	float thin = exp(-abs(hgt) * 26.0);
	vec3 col = galaxy_arm_color * disk * thin + galaxy_core_color * bulge;
	// dust lane across the core
	float dust = smoothstep(0.3, 0.6, fbm(dir * 8.0, 4));
	col *= mix(1.0, 0.4, dust * thin * step(rn, 0.4));
	return col * galaxy_strength;
}

vec3 milkyway(vec3 dir) {
	if (milkyway_strength <= 0.0) { return vec3(0.0); }
	float band = 1.0 - smoothstep(0.0, 0.35, abs(dot(dir, normalize(milkyway_axis))));
	float clouds = fbm(dir * 10.0, 5);
	float dark = smoothstep(0.4, 0.75, fbm(dir * 14.0 + 3.0, 4));
	vec3 col = mix(vec3(0.5, 0.55, 0.7), vec3(0.8, 0.75, 0.65), clouds);
	return col * band * clouds * mix(1.0, 0.2, dark) * milkyway_strength;
}

vec3 starfield(vec3 dir) {
	if (star_density <= 0.0) { return vec3(0.0); }
	vec3 col = vec3(0.0);
	// two grids of different densities for size variety (one on the lowest tier)
	int nlayers = quality >= 1 ? 2 : 1;
	for (int layer = 0; layer < 2; layer++) {
		if (layer >= nlayers) { break; }
		float scale = 220.0 + float(layer) * 380.0;
		vec3 gp = dir * scale;
		vec3 cell = floor(gp);
		vec3 f = fract(gp);
		vec3 h = hash33(cell + float(layer) * 17.0);
		float present = step(1.0 - star_density * (0.06 - float(layer) * 0.03), h.x);
		vec2 sp = h.yz;
		float d = length(f.xy - sp);
		float star = present * smoothstep(0.09, 0.0, d);
		float mag = pow(h.z, 3.0);                 // few bright, many faint
		float tw = 0.7 + 0.3 * sin(TIME * (1.0 + h.x * 4.0) + h.y * 30.0);
		col += star_color(h.y) * star * mag * tw;
	}
	return col * star_brightness;
}

// ==========================================================================
// Celestial bodies: analytic ray-sphere (bodies at unit distance).
// ==========================================================================
void body_local_basis(vec3 axis, out vec3 bu, out vec3 bv) {
	vec3 ref = abs(axis.y) < 0.95 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
	bu = normalize(cross(ref, axis));
	bv = cross(axis, bu);
}

// Returns rgb + alpha for a body along EYEDIR; alpha 0 if the ray misses.
vec4 render_body(int idx, vec3 rd, vec3 sun_dir) {
	vec3 C = normalize(body_dir[idx]);         // center at unit distance
	float rp = tan(clamp(body_size[idx], 0.001, 0.5));
	int typ = body_type[idx];
	vec3 axis = normalize(body_axis[idx]);
	vec3 ca = body_color_a[idx];
	vec3 cb = body_color_b[idx];
	float bseed = body_seed[idx];

	// ray (origin 0) vs sphere centered at C
	vec2 ts = ray_sphere_i(-C, rd, rp);
	float planet_t = (ts.x <= ts.y && ts.y > 0.0) ? max(ts.x, 0.0) : 1e9;

	vec3 out_col = vec3(0.0);
	float out_a = 0.0;

	// ---- rings (draw first; planet may occlude) ----
	if (typ == 2) {
		float denom = dot(rd, axis);
		if (abs(denom) > 1e-4) {
			float rt = dot(C, axis) / denom;
			if (rt > 0.0) {
				vec3 H = rd * rt;
				float rr = length(H - C) / rp;      // in planet radii
				float ri = body_ring_inner[idx];
				float ro = body_ring_outer[idx];
				if (rr >= ri && rr <= ro && rt < planet_t) {
					float u = (rr - ri) / max(0.001, ro - ri);
					float bands = 0.55 + 0.45 * sin(u * 60.0 + bseed);
					float gap = smoothstep(0.02, 0.06, abs(fract(u * 7.0 + 0.3) - 0.5));
					vec3 rcol = mix(ca, cb, u) * bands * gap;
					// planet shadow on ring
					vec3 toSun = sun_dir;
					vec2 sh = ray_sphere_i(H - C, toSun, rp);
					float lit = (sh.x <= sh.y && sh.y > 0.0) ? 0.25 : 1.0;
					float alpha = 0.85 * gap;
					out_col = rcol * lit;
					out_a = alpha;
				}
			}
		}
	}

	// ---- planet sphere ----
	if (planet_t < 1e8) {
		vec3 P = rd * planet_t;                 // hit point (camera at origin)
		vec3 N = normalize(P - C);              // outward normal (sphere center at C)
		float ndl = max(dot(N, sun_dir), 0.0);
		float terminator = smoothstep(0.0, 0.12, ndl);
		vec3 surf;
		if (typ == 1 || typ == 2) {
			// gas giant: latitudinal bands, domain-warped, + storm oval
			float lat = asin(clamp(dot(N, axis), -1.0, 1.0));
			vec3 bu; vec3 bv; body_local_basis(axis, bu, bv);
			float lon = atan(dot(N, bv), dot(N, bu));
			float warp = fbm(N * 6.0 + bseed, 5) - 0.5;
			float band = lat * 3.0 + warp * 1.6;
			float t = 0.5 + 0.5 * sin(band * 4.0);
			surf = mix(ca, cb, t);
			// storm oval (Great-Red-Spot-like)
			float slat = lat - 0.4;
			float slon = lon - (bseed * 0.7 - 1.0);
			float storm = 1.0 - smoothstep(0.0, 0.25, length(vec2(slon * 0.6, slat * 1.4)));
			surf = mix(surf, mix(cb, vec3(1.0, 0.7, 0.4), 0.5),
					   storm * (0.6 + 0.4 * fbm(N * 20.0, 3)));
		} else {
			// moon: albedo + crater noise
			float craters = fbm(N * 14.0 + bseed, 5);
			float pit = smoothstep(0.45, 0.5, craters) - smoothstep(0.5, 0.55, craters);
			surf = mix(ca, cb, craters) * (1.0 - pit * 0.5);
		}
		float lit = terminator * ndl + 0.03;
		vec3 pcol = surf * lit;
		// ring shadow on planet
		if (typ == 2) {
			float denom = dot(sun_dir, axis);
			if (abs(denom) > 1e-4) {
				float st = dot(C - P, axis) / denom;
				if (st > 0.0) {
					vec3 SH = P + sun_dir * st;
					float sr = length(SH - C) / rp;
					if (sr >= body_ring_inner[idx] && sr <= body_ring_outer[idx]) {
						pcol *= 0.5;
					}
				}
			}
		}
		// planet is opaque -> overwrite ring where it occludes
		out_col = pcol;
		out_a = 1.0;
	}
	return vec4(out_col, out_a);
}

// ==========================================================================
// Clouds (surface): domain-warped FBM on a sky plane, lit toward the sun.
// ==========================================================================
vec3 clouds(vec3 rd, vec3 sun_dir, vec3 sky_col, out float cloud_a) {
	cloud_a = 0.0;
	if (cloud_cover <= 0.0 || rd.y <= 0.02) { return sky_col; }
	vec3 p = vec3(rd.x, rd.z, 0.0) / rd.y;       // project onto sky plane
	p *= cloud_scale;
	p += vec3(TIME * cloud_speed, TIME * cloud_speed * 0.6, 0.0);
	float d = warp_fbm(vec3(p.xy, 0.3), 6);
	float cov = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.35, d);
	if (cov <= 0.0) { return sky_col; }
	// cheap lighting: gradient of density toward the sun
	vec2 sdir = normalize((sun_dir.xz) - rd.xz + 1e-4);
	float dl = warp_fbm(vec3(p.xy + sdir * 0.15, 0.3), 5);
	float lit = clamp(0.5 + (d - dl) * 3.0, 0.0, 1.0);
	vec3 cc = mix(cloud_shadow_color, cloud_color, lit);
	// fade at the horizon
	float horizon = smoothstep(0.02, 0.18, rd.y);
	cloud_a = cov * horizon;
	return mix(sky_col, cc, cloud_a);
}

// ==========================================================================
void sky() {
	vec3 rd = normalize(EYEDIR);
	vec3 sun_dir = LIGHT0_ENABLED ? normalize(-LIGHT0_DIRECTION) : normalize(vec3(0.3, 0.4, 0.6));
	vec3 sun_col = LIGHT0_ENABLED ? LIGHT0_COLOR * LIGHT0_ENERGY : sun_tint;

	bool ibl = AT_CUBEMAP_PASS;
	// Atmosphere ray-march sample counts scale with the perf tier (and the IBL
	// cubemap pass always runs cheap). quality 0..3 -> 8..20 primary steps.
	int psteps = ibl ? 6 : (8 + quality * 4);
	int lsteps = ibl ? 3 : (4 + quality);

	// --- deep-space base ---
	vec3 space = space_color;
	space += nebula(rd);
	space += galaxy(rd);
	space += milkyway(rd);
	if (!ibl) { space += starfield(rd); }

	// --- atmosphere ---
	vec3 col = space;
	float day = 0.0;
	if (atmosphere_strength > 0.0) {
		vec3 atm = atmosphere(rd, sun_dir, psteps, lsteps) * atmosphere_strength;
		atm *= sun_col;
		day = clamp(dot(sun_dir, vec3(0.0, 1.0, 0.0)) * 4.0 + 0.3, 0.0, 1.0); // sun above horizon
		float sky_lum = clamp(dot(atm, vec3(0.33)) * 3.0, 0.0, 1.0);
		// stars/space fade out as the daylit sky brightens
		col = atm + space * (1.0 - sky_lum);
		// below horizon -> ground tint
		col = mix(ground_color * (0.3 + 0.7 * day), col, smoothstep(-0.05, 0.05, rd.y));
	}

	// --- celestial bodies ---
	if (!ibl) {
		for (int i = 0; i < MAX_BODIES; i++) {
			if (i >= body_count) { break; }
			vec4 b = render_body(i, rd, sun_dir);
			col = mix(col, b.rgb, b.a);
		}
	}

	// --- sun disk + Mie aureole ---
	float sd = dot(rd, sun_dir);
	float ang = acos(clamp(sd, -1.0, 1.0));
	float disk = smoothstep(sun_disk_size, sun_disk_size * 0.6, ang);
	float limb = 0.6 + 0.4 * sqrt(max(1.0 - ang / max(sun_disk_size, 1e-4), 0.0));
	float aureole = pow(max(sd, 0.0), 8.0) * mie_amount * 0.5;
	if (rd.y > -0.1 || atmosphere_strength <= 0.0) {
		col += sun_col * disk * limb * 6.0;
		col += sun_col * aureole;
	}

	// --- clouds + god rays (surface) ---
	if (!ibl && atmosphere_strength > 0.0) {
		float ca;
		col = clouds(rd, sun_dir, col, ca);
		// in-sky god rays: brighten un-clouded directions near the sun
		float shafts = pow(max(sd, 0.0), 3.0) * (1.0 - ca) * mie_amount * day;
		col += sun_col * shafts * 0.15;
	}

	col *= exposure;
	COLOR = col;
}
