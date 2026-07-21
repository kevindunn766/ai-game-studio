shader_type spatial;
render_mode cull_disabled;

// Cel-shaded, lightly-tessellated ground. The mesh is a subdivided plane; this shader
// displaces it a little (from a shared seamless height noise, so objects can match it on
// the CPU), shades it as flat toon bands, paints a procedural cel-shaded soil base, and
// layers the generated top-down patch PNGs (grass / moss / rock / dirt / pebble -- 3 shape
// variants each, in a texture array) chosen by a low-frequency biome field. Everything is
// keyed to CONTENT space (world_scale + scroll from GroundTiler) so it scrolls and scales
// with the world without swimming. Each patch cell gets its own variant, size, rotation and
// mirror so the tiling never reads as a grid.

uniform sampler2D height_tex : repeat_enable, filter_linear;
uniform sampler2DArray patch_grass : filter_nearest, repeat_disable;
uniform sampler2DArray patch_moss : filter_nearest, repeat_disable;
uniform sampler2DArray patch_rock : filter_nearest, repeat_disable;
uniform sampler2DArray patch_dirt : filter_nearest, repeat_disable;
uniform sampler2DArray patch_pebble : filter_nearest, repeat_disable;

uniform float world_scale = 1.0;
uniform vec2 scroll = vec2(0.0);
uniform float height_period = 5.0;
uniform float height_amp = 0.22;
uniform float patch_size = 2.2;          // content units per patch cell AT octave 0 (world_scale 1.0)
uniform float patch_density = 0.62;      // fraction of cells that get a patch
uniform float patch_stagger = 0.45;      // per-area spread in the tier fade (0 = even, uniform)
// Moss decals span the full range from small to cell-filling large (everything in between).
uniform float moss_size_min = 0.25;      // smallest moss decal (fraction of a cell)
uniform float moss_size_max = 1.05;      // largest moss decal (fills the cell)

// Bare-ground base under/between the patch PNGs, sRGB->linear (ALBEDO here is linear). A
// deep, cool green -- darkened (black) and given some blue so it's not a bright lime.
// Displays ~#2A663D.
const vec3 GROUND_BASE = vec3(0.023, 0.133, 0.047);   // srgb_to_linear(~#2A663D)
const vec3 SUN = vec3(0.35, 0.86, 0.37);

varying vec2 v_content;
varying vec3 v_wnormal;


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 34.56);
	return fract(p.x * p.y);
}

float h_at(vec2 c) {
	return (texture(height_tex, c / height_period).r - 0.5) * height_amp;
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

float fbm(vec2 p) {
	float s = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		s += amp * vnoise(p);
		p *= 2.0;
		amp *= 0.5;
	}
	return s;
}

// Sample a material's patch array in its cell with a per-cell variant, size, mirror and
// rotation so the tiling doesn't read as a grid. Empty cells (per-cell hash) return nothing.
vec4 patch_at(sampler2DArray t, vec2 c, float smin, float smax) {
	vec2 cell = floor(c / patch_size);
	if (hash21(cell + 3.7) > patch_density) {
		return vec4(0.0);
	}
	float layer = floor(hash21(cell + 5.1) * 3.0);        // shape variant 0..2
	float psize = smin + (smax - smin) * hash21(cell + 7.3);   // per-cell size (small..large)
	vec2 uv = fract(c / patch_size);
	if (hash21(cell + 1.3) > 0.5) { uv.x = 1.0 - uv.x; }
	if (hash21(cell + 2.9) > 0.5) { uv.y = 1.0 - uv.y; }
	float a = hash21(cell) * 6.2831853;
	vec2 r = (uv - 0.5) / psize;
	r = mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a))) * r;
	uv = r + 0.5;
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return vec4(0.0);
	}
	return texture(t, vec3(uv, layer));
}


void vertex() {
	vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 c = wpos.xz / max(world_scale, 0.0001) + scroll;
	v_content = c;
	VERTEX.y += h_at(c);
	float e = height_period * 0.03;
	float hx = h_at(c + vec2(e, 0.0)) - h_at(c - vec2(e, 0.0));
	float hz = h_at(c + vec2(0.0, e)) - h_at(c - vec2(0.0, e));
	v_wnormal = normalize(vec3(-hx, 2.0 * e, -hz));
}

// One octave of world-anchored blotches at content coordinate `coord`: a low-frequency biome
// field picks the material, then patch_at stamps a per-cell decal. Same call as before, just
// factored out so we can sample two octaves and crossfade between them.
vec4 sample_patch_layer(vec2 coord) {
	float b = fbm(coord * 0.35 + 11.0);
	if (b < 0.28) {
		return patch_at(patch_dirt, coord, 0.4, 1.05);
	} else if (b < 0.46) {
		return patch_at(patch_grass, coord, 0.4, 1.05);
	} else if (b < 0.60) {
		return patch_at(patch_moss, coord, moss_size_min, moss_size_max);
	} else if (b < 0.80) {
		return patch_at(patch_rock, coord, 0.4, 1.05);
	}
	return patch_at(patch_pebble, coord, 0.4, 1.05);
}

void fragment() {
	vec2 c = v_content;

	// Bare ground = lawn-green base; the patch PNGs (in their own colours) sit on top.
	vec3 col = GROUND_BASE;

	// Tiered, WORLD-ANCHORED blotches. Each octave is a set of blotches whose cell size is
	// patch_size * 2^octave (content units) -- a given blotch never grows, it just shrinks and
	// fades as the world scales down. We render the two octaves bracketing the current zoom:
	//   - `p_out` (this tier) shrinking + fading OUT as we zoom past it,
	//   - `p_in`  (next tier, 2x bigger cells) already present but so large you only see part
	//     of one cell -- it resolves into blotches as you reach that tier.
	// A per-area stagger shifts the fade point around so it never reads as an even dotted grid.
	float lvl = max(-log2(max(world_scale, 0.00001)), 0.0);
	float o0 = floor(lvl);
	float f = lvl - o0;
	vec2 c_out = c / exp2(o0);
	vec2 c_in = c / exp2(o0 + 1.0);
	float sg = fbm(c_out * 0.7 + 5.0) - 0.5;             // per-area variation, -0.5..0.5
	float env = 4.0 * f * (1.0 - f);                     // 0 at octave boundaries, 1 mid-transition
	float ff = clamp(f + sg * patch_stagger * env, 0.0, 1.0);  // staggered transition progress
	vec4 p_in = sample_patch_layer(c_in);
	vec4 p_out = sample_patch_layer(c_out);
	if (p_in.a > 0.5) {
		col = mix(col, p_in.rgb, ff);                    // next tier fading in (behind)
	}
	if (p_out.a > 0.5) {
		col = mix(col, p_out.rgb, 1.0 - ff);             // this tier fading out (on top)
	}

	// Flat toon shading: quantize the light into a few bands.
	float ndl = clamp(dot(normalize(v_wnormal), normalize(SUN)), 0.0, 1.0);
	float band = ndl < 0.45 ? 0.75 : (ndl < 0.8 ? 0.9 : 1.05);
	ALBEDO = col * band;
}
