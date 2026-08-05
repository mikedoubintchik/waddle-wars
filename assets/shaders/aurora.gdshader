// Aurora ribbon: unshaded additive curtain with scrolling vertical bands and
// a slow hue drift between green / cyan / violet. Soft alpha edges all around.
// Map onto any ribbon/plane mesh: UV.x runs along the ribbon, UV.y down it
// (UV.y = 0 at the top edge). Mobile-cheap: one noise octave, no textures.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 color_green : source_color = vec4(0.2, 1.0, 0.5, 1.0);
uniform vec4 color_cyan : source_color = vec4(0.25, 0.85, 1.0, 1.0);
uniform vec4 color_violet : source_color = vec4(0.62, 0.4, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 4.0) = 1.3;
uniform float scroll_speed = 0.05;
uniform float hue_speed = 0.1;
uniform float band_scale = 3.0;
uniform float curtain_frequency = 26.0;
uniform float max_alpha : hint_range(0.0, 1.0) = 0.55;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	// Slow-drifting brightness bands along the ribbon.
	float n = value_noise(vec2(UV.x * band_scale + TIME * scroll_speed, TIME * 0.04));
	float band = smoothstep(0.25, 0.85, n);
	// Fine vertical curtain streaks, wobbling with the noise.
	float curtain = 0.6 + 0.4 * sin(UV.x * curtain_frequency + n * 7.0 + TIME * 0.6);
	// Soft fade at top and bottom edges, plus soft ends.
	float edge_v = sin(clamp(UV.y, 0.0, 1.0) * 3.14159265);
	float edge_h = sin(clamp(UV.x, 0.0, 1.0) * 3.14159265);
	float fade = edge_v * edge_v * clamp(edge_h * 2.2, 0.0, 1.0);

	// Hue drift green -> cyan, tipping to violet near the top of the curtain.
	float m = 0.5 + 0.5 * sin(TIME * hue_speed + UV.x * 2.4);
	vec3 col = mix(color_green.rgb, color_cyan.rgb, m);
	col = mix(col, color_violet.rgb, clamp(1.0 - UV.y, 0.0, 1.0) * 0.55);

	ALBEDO = col * intensity * band * curtain;
	ALPHA = max_alpha * band * curtain * fade;
}
