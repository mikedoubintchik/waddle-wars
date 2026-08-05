// Aurora ribbon: unshaded additive curtain with scrolling vertical bands and
// a slow hue drift between green / cyan / violet. Soft alpha edges all around.
// Map onto any ribbon/plane mesh: UV.x runs along the ribbon, UV.y down it
// (UV.y = 0 at the top edge). High-detail additions (gated by detail_level,
// skipped entirely at 0): fine vertical ray striations inside the curtain
// folds, a brighter core band partway down, and gentle per-height horizontal
// drift so the curtain sways instead of sliding. Mobile-cheap: 1 noise octave
// base + 2 extra samples inside the uniform detail branch, no textures.
shader_type spatial;
// fog_disabled: distance fog must never gray the curtains out — ribbons sit
// 300-700m away, where even thin haze desaturates additive color to a flat
// gray-blue smudge. Additive blend: the curtain only ever adds light.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

uniform vec4 color_green : source_color = vec4(0.2, 1.0, 0.5, 1.0);
uniform vec4 color_cyan : source_color = vec4(0.25, 0.85, 1.0, 1.0);
uniform vec4 color_violet : source_color = vec4(0.62, 0.4, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 4.0) = 1.3;
uniform float scroll_speed = 0.05;
uniform float hue_speed = 0.1;
uniform float band_scale = 3.0;
uniform float curtain_frequency = 26.0;
uniform float max_alpha : hint_range(0.0, 1.0) = 0.55;
// 0 = base look (cheapest), 1 = full micro-detail. Set by VisualLibrary from
// the display quality preset (low=0, medium=0.5, high=1).
uniform float detail_level : hint_range(0.0, 1.0) = 1.0;
uniform float ray_frequency = 90.0;
uniform float ray_strength : hint_range(0.0, 1.0) = 0.55;
uniform float core_position : hint_range(0.0, 1.0) = 0.42;
uniform float core_width : hint_range(0.05, 1.0) = 0.3;
uniform float core_boost : hint_range(0.0, 2.0) = 0.8;
uniform float drift_variation : hint_range(0.0, 1.0) = 0.6;

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
	float ux = UV.x;
	float rays = 1.0;
	float core = 0.0;
	if (detail_level > 0.001) {
		// Gentle horizontal drift that varies with height: the curtain sways
		// like fabric instead of sliding as one rigid sheet.
		ux += (value_noise(vec2(UV.y * 1.7, TIME * 0.05)) - 0.5)
				* 0.08 * drift_variation * detail_level;
	}

	// Slow-drifting brightness bands along the ribbon.
	float n = value_noise(vec2(ux * band_scale + TIME * scroll_speed, TIME * 0.04));
	float band = smoothstep(0.25, 0.85, n);
	// Fine vertical curtain streaks, wobbling with the noise.
	float curtain = 0.6 + 0.4 * sin(ux * curtain_frequency + n * 7.0 + TIME * 0.6);

	if (detail_level > 0.001) {
		// Vertical ray striations inside each curtain fold: fine sin comb with
		// noise-jittered phase so rays cluster and break naturally.
		float rn = value_noise(vec2(ux * ray_frequency * 0.12, UV.y * 0.9 - TIME * 0.07));
		float rs = 0.5 + 0.5 * sin(ux * ray_frequency + rn * 9.0);
		rays = mix(1.0, 0.55 + 0.45 * rs + 0.25 * rn, ray_strength * detail_level);
		// Brighter core band partway down the curtain (gaussian falloff).
		float dc = (UV.y - core_position) / max(core_width, 0.05);
		core = exp(-dc * dc * 3.0) * core_boost * detail_level;
	}

	// Soft fade at top and bottom edges, plus soft ends.
	float edge_v = sin(clamp(UV.y, 0.0, 1.0) * 3.14159265);
	float edge_h = sin(clamp(UV.x, 0.0, 1.0) * 3.14159265);
	float fade = edge_v * edge_v * clamp(edge_h * 2.2, 0.0, 1.0);

	// Hue drift green -> cyan, tipping to violet near the top of the curtain.
	float m = 0.5 + 0.5 * sin(TIME * hue_speed + ux * 2.4);
	vec3 col = mix(color_green.rgb, color_cyan.rgb, m);
	col = mix(col, color_violet.rgb, clamp(1.0 - UV.y, 0.0, 1.0) * 0.55);

	// Brightness lives in ALBEDO (additive HDR), coverage in ALPHA. The old
	// form multiplied band*curtain into BOTH, so the added light fell off
	// quadratically and typical pixels sat ~0.1 HDR: flat dim smudges. Now the
	// color keeps a lit floor across the curtain and the core band multiplies
	// it up to ~3.4x, pushing the curtain heart past the glow HDR threshold
	// (~1.05) so it visibly blooms against the twilight sky.
	float energy = band * curtain * rays;
	float core_gain = 1.0 + core * 3.0;
	ALBEDO = col * intensity * (0.3 + 1.05 * energy) * core_gain;
	ALPHA = clamp(max_alpha * fade * (0.35 + 0.65 * band * curtain)
			* (1.0 + core * 0.5), 0.0, 1.0);
}
