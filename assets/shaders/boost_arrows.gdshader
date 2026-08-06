shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;

// Scrolling chevron arrows on boost pads. PlaneMesh UV v increases toward the
// pad's local +Z; travel direction is local -Z, so chevron tips point toward
// -v and the pattern scrolls toward -v (verified via tests/pad_shot.tscn
// top-down captures: tips up-screen, motion up-screen).

uniform vec3 arrow_color : source_color = vec3(1.0, 0.93, 0.6);
uniform float scroll_speed = 1.1;
uniform float chevron_count = 3.0;
uniform float chevron_slope = 1.6;

void fragment() {
	float edge = chevron_slope * abs(UV.x - 0.5);
	float band = fract(UV.y * chevron_count - edge + TIME * scroll_speed * chevron_count);
	float chev = smoothstep(0.02, 0.10, band) * (1.0 - smoothstep(0.30, 0.40, band));
	// Soften toward lateral pad edges and fade both ends of the strip.
	float side_fade = 1.0 - smoothstep(0.36, 0.5, abs(UV.x - 0.5));
	float end_fade = smoothstep(0.0, 0.12, UV.y) * (1.0 - smoothstep(0.88, 1.0, UV.y));
	// Brightness pulse so pads read as "alive" even from far away.
	float pulse = 0.8 + 0.2 * sin(TIME * 4.0);
	ALBEDO = arrow_color * chev * side_fade * end_fade * pulse;
	ALPHA = clamp(chev * side_fade * end_fade, 0.0, 1.0);
}
