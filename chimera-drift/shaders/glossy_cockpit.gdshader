shader_type spatial;
render_mode cull_back, specular_schlick_ggx, diffuse_lambert;

// ============================================================================
// Chimera Drift — glossy cockpit canopy (post-level beauty shot)
// A dark tinted glass that reflects the skybox SHARPLY (very low roughness,
// near-metallic → the sky radiance mirrors off it) with strong fresnel edge
// brightening, an animated sweeping "glint" band (a bright stripe that slides
// across the canopy as if a star/sun were reflecting past), a fine sparkle
// shimmer, and a faint interior cabin glow.
//
// Opaque glass (reliable + reflective in GL Compatibility); the reflection is
// sky IBL, so it "glints off the skybox" behind the ship. No UVs on the hull →
// the moving highlights are driven from OBJECT space.
// ============================================================================

uniform vec4 glass_tint : source_color = vec4(0.05, 0.09, 0.16, 1.0);
uniform float glass_roughness : hint_range(0.0, 0.4) = 0.04;
uniform float glass_metallic : hint_range(0.0, 1.0) = 0.85;

uniform vec4 fresnel_color : source_color = vec4(0.7, 0.85, 1.0, 1.0);
uniform float fresnel_power : hint_range(1.0, 8.0) = 4.0;
uniform float fresnel_strength : hint_range(0.0, 3.0) = 1.1;

uniform vec4 cabin_color : source_color = vec4(1.0, 0.85, 0.55, 1.0);
uniform float cabin_glow : hint_range(0.0, 3.0) = 0.45;

uniform float glint_speed = 0.6;
uniform float glint_strength : hint_range(0.0, 4.0) = 2.0;

varying vec3 v_obj;

void vertex() {
	v_obj = VERTEX;
}

void fragment() {
	ALBEDO = glass_tint.rgb;
	ROUGHNESS = glass_roughness;
	METALLIC = glass_metallic;
	SPECULAR = 1.0;

	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fres = pow(1.0 - ndv, fresnel_power);

	// Sweeping glint band: a narrow bright stripe travelling across the canopy.
	float sweep = sin((v_obj.z + v_obj.y * 0.6) * 3.0 - TIME * glint_speed * 3.0);
	float band = smoothstep(0.86, 0.999, sweep);
	// Fine shimmer so the glass sparkles as the camera moves.
	float spark = smoothstep(0.97, 1.0, sin(v_obj.x * 40.0 + TIME * 2.0) * sin(v_obj.z * 33.0 - TIME * 1.7));

	vec3 emis = fresnel_color.rgb * fres * fresnel_strength;
	emis += fresnel_color.rgb * band * glint_strength * (0.3 + 0.7 * fres);
	emis += vec3(1.0) * spark * glint_strength * 0.5;
	emis += cabin_color.rgb * cabin_glow * (1.0 - fres) * 0.5;   // interior, centre-weighted
	EMISSION = emis;
}
