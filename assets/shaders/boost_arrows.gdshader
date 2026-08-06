shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;

// Double-stroke scrolling chevrons on boost pads. Anatomy per stroke, inside
// to out: high-brightness white CORE -> warm amber halo -> dark navy OUTLINE.
// The white-on-dark double stroke keeps the arrows legible in pure grayscale
// and under every color-vision condition (shape + brightness, never hue).
// blend_mix (not add) so the dark outline can actually darken the amber pad.
// PlaneMesh UV v increases toward the pad's local +Z; travel direction is
// local -Z, so chevron tips point toward -v and the pattern scrolls toward -v
// (verified via tests/pad_shot.tscn top-down captures: tips up-screen, motion
// up-screen).

uniform vec3 core_color : source_color = vec3(1.0, 0.99, 0.94);
uniform vec3 arrow_color : source_color = vec3(1.0, 0.87, 0.45);
uniform vec3 outline_color : source_color = vec3(0.04, 0.06, 0.1);
uniform float scroll_speed = 1.1;
uniform float chevron_count = 3.0;
uniform float chevron_slope = 1.6;
// 1.0 when accessibility/high_contrast_pickups is on (set by
// TrackBuilder.add_boost_pad on every pad build): pure-white cores, brighter
// pulse floor, fully opaque strokes.
uniform float contrast_boost : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float edge = chevron_slope * abs(UV.x - 0.5);
	float band = fract(UV.y * chevron_count - edge + TIME * scroll_speed * chevron_count);
	// Stroke bands in band space: outline 0.02-0.44 wraps halo 0.05-0.41
	// wraps core 0.10-0.36 — a crisp double stroke at any viewing distance.
	float outline_zone = smoothstep(0.02, 0.05, band) * (1.0 - smoothstep(0.41, 0.44, band));
	float halo = smoothstep(0.05, 0.10, band) * (1.0 - smoothstep(0.36, 0.41, band));
	float core = smoothstep(0.10, 0.15, band) * (1.0 - smoothstep(0.31, 0.36, band));
	// Soften toward lateral pad edges and fade both ends of the strip.
	float side_fade = 1.0 - smoothstep(0.36, 0.5, abs(UV.x - 0.5));
	float end_fade = smoothstep(0.0, 0.12, UV.y) * (1.0 - smoothstep(0.88, 1.0, UV.y));
	// Core-only brightness pulse (floor 0.72) so pads read "alive" from afar
	// while the dark outline stays rock-solid for the outline read.
	float pulse = 0.86 + 0.14 * sin(TIME * 4.0);
	vec3 col = outline_color;
	col = mix(col, arrow_color, halo);
	vec3 core_col = mix(core_color, vec3(1.0), contrast_boost * 0.5);
	col = mix(col, core_col * (pulse + contrast_boost * 0.25), core);
	float alpha = outline_zone * mix(0.9, 1.0, contrast_boost) * side_fade * end_fade;
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
