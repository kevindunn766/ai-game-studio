shader_type canvas_item;
render_mode unshaded;

uniform sampler2D SCREEN_TEXTURE: hint_screen_texture, filter_linear_mipmap;
// Vertical screen position of the focus band centre (0=top, 1=bottom)
uniform float focus_center: hint_range(0.0, 1.0) = 0.5;
// Half-height of the sharp zone in screen UV units
uniform float focus_half_width: hint_range(0.0, 0.5) = 0.15;
// Maximum mip level sampled at the extreme edges (higher = more blur)
uniform float max_blur: hint_range(0.0, 8.0) = 3.0;

void fragment() {
	float dist = abs(SCREEN_UV.y - focus_center);
	float t = clamp((dist - focus_half_width) / max(0.001, 0.5 - focus_half_width), 0.0, 1.0);
	COLOR = textureLod(SCREEN_TEXTURE, SCREEN_UV, t * max_blur);
}
