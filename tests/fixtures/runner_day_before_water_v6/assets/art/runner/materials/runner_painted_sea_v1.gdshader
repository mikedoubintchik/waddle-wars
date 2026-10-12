// Painted ocean: one opaque plane, one filtered sample, no reflection/depth
// reads, animation, displacement or extra passes. Atmosphere colours are
// supplied by RunnerGame's existing biome blend, independent of sky resources.
shader_type spatial;
render_mode unshaded, depth_draw_opaque, cull_back, fog_disabled;

uniform sampler2D painted_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool painted_enabled = false;
uniform vec4 water_tint : source_color = vec4(0.058, 0.340, 0.546, 1.0);
uniform vec4 horizon_tint : source_color = vec4(0.31, 0.51, 0.63, 1.0);
uniform vec4 bottom_tint : source_color = vec4(0.10, 0.27, 0.43, 1.0);
// source_color keeps reference and sample in the same colour space on both
// Compatibility (sRGB) and Forward+ (linear). A fixed linear luma divisor
// clips almost the whole tile in Compatibility, erasing its brush strokes.
uniform vec4 paint_reference : source_color = vec4(0.050, 0.450, 0.695, 1.0);
uniform float tile_metres = 32.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 brush = vec3(1.0);
	if (painted_enabled) {
		// Mirrored repeat meets at identical edge texels even for generated
		// tiles whose opposite borders differ. No second texture read needed.
		vec2 tile_uv = abs(fract(world_pos.xz / (tile_metres * 2.0)) * 2.0 - 1.0);
		vec3 paint = texture(painted_albedo, tile_uv).rgb;
		brush = clamp(paint / max(paint_reference.rgb, vec3(0.005)), vec3(0.4), vec3(1.8));
	}
	// Fragment-space distance is essential: a giant two-triangle plane's
	// corner distances would otherwise flatten all nearby paint to horizon.
	float distance_to_camera = length(VERTEX);
	float haze = smoothstep(110.0, 600.0, distance_to_camera);
	vec3 near_water = water_tint.rgb * mix(vec3(1.0), brush, 0.85);
	// The reference ocean carries small pale sun catches. Derive these from
	// the existing painted crests; no animated noise or extra texture sample.
	float crest = smoothstep(1.15, 1.55, brush.g);
	near_water = mix(near_water, vec3(0.70, 0.91, 1.0), crest * 0.48);
	// Reproduce ProceduralSkyMaterial's default ground_curve (0.02 -> inverse
	// curve 30). Matching only its horizon colour leaves a band at the finite
	// far clip, because those pixels look slightly below the actual horizon.
	float view_y = normalize(world_pos - CAMERA_POSITION_WORLD).y;
	float ground_curve = pow(clamp(1.0 + view_y, 0.0, 1.0), 30.0);
	vec3 distant_ground = mix(bottom_tint.rgb, horizon_tint.rgb, ground_curve);
	// Local fog is disabled so this sky-gradient match is not tinted twice.
	ALBEDO = mix(near_water, distant_ground, haze);
}
