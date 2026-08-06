shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Boost pad base deck: amber core with a slow emissive pulse plus a
// hazard-striped border (white/charcoal diagonals) around the top face rim,
// so pads read through SHAPE + PATTERN + BRIGHTNESS — never hue alone
// (colorblind-safe, survives grayscale). Border geometry is derived from
// local-space position sized by half_extents (BoxMesh UV atlases are not
// per-face 0..1, so UV borders are unreliable on boxes). Visual only — the
// Area3D trigger box and apply_boost values are untouched.
// WebGL2/gl_compatibility-safe; mobile-cheap: pure ALU, no textures/noise.

uniform vec4 base_color : source_color = vec4(1.0, 0.72, 0.2, 1.0);
uniform vec4 emission_color : source_color = vec4(1.0, 0.55, 0.1, 1.0);
uniform float pulse_speed = 2.6;
uniform float emission_floor = 0.55;
uniform float emission_pulse = 0.75;
// Top-face half extents of the pad box (4x6 pad => 2, 3).
uniform vec2 half_extents = vec2(2.0, 3.0);
uniform float border_width = 0.42;
uniform float stripe_freq = 2.6;
// 1.0 when accessibility/high_contrast_pickups is on (set by TrackBuilder).
uniform float contrast_boost : hint_range(0.0, 1.0) = 0.0;

varying vec3 local_pos;
varying float top_face;

void vertex() {
	local_pos = VERTEX;
	top_face = step(0.5, NORMAL.y);
}

void fragment() {
	vec2 inset = half_extents - abs(local_pos.xz);
	float edge_d = min(inset.x, inset.y);
	float border = (1.0 - smoothstep(border_width * 0.8, border_width, edge_d)) * top_face;
	// Diagonal hazard stripes: hard step keeps them crisp at race distance.
	float stripe = step(0.5, fract((local_pos.x + local_pos.z) * stripe_freq));
	vec3 stripe_col = mix(vec3(0.07, 0.08, 0.11), vec3(0.97, 0.97, 0.93), stripe);
	float pulse = emission_floor + emission_pulse * (0.5 + 0.5 * sin(TIME * pulse_speed));
	ALBEDO = mix(base_color.rgb, stripe_col, border);
	ROUGHNESS = mix(0.3, 0.6, border);
	SPECULAR = 0.35;
	// Amber core pulses; bright border stripes keep a faint constant glow so
	// the pattern outline survives night courses and deep shadow.
	vec3 core_glow = emission_color.rgb * pulse * (1.0 - border) * (1.0 + contrast_boost * 0.5);
	vec3 border_glow = stripe_col * border * (0.12 + 0.18 * contrast_boost);
	EMISSION = core_glow + border_glow;
}
