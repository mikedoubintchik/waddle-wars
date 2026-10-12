// Painted ocean: one opaque plane, at most two filtered samples, no reflection/depth
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
uniform vec2 haze_distances = vec2(110.0, 600.0);
uniform vec3 crest_tint = vec3(0.70, 0.91, 1.0);
// Isolated DAY review: original non-DAY path remains below.
uniform float day_detail_weight = 0.0;
uniform vec2 day_tile_metres = vec2(10.0, 128.0);
uniform float day_lateral_reference_metres = 80.0;
uniform vec4 day_trough_tint : source_color = vec4(0.1733874951, 0.3539693131, 0.6587933568, 1.0);
uniform vec4 day_body_tint : source_color = vec4(0.1617658861, 0.4084237627, 0.7555587524, 1.0);
uniform vec4 day_face_tint : source_color = vec4(0.1070936283, 0.4641352836, 0.8910564644, 1.0);
uniform vec4 day_crest_tint : source_color = vec4(0.68, 0.94, 1.0, 1.0);

// Compatibility samples source_color in sRGB; Forward+ uses linear. The
// authored paint thresholds are sRGB scalars, while palette RGB always stays
// in the renderer's own working space through source_color uniforms.
float paint_srgb_scalar(float value) {
    if (OUTPUT_IS_SRGB) {
        return value;
    }
    return value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1.0 / 2.4) - 0.055;
}


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
	float haze = smoothstep(haze_distances.x, haze_distances.y, distance_to_camera);
	vec3 near_water = water_tint.rgb * mix(vec3(1.0), brush, 0.85);
	// The reference ocean carries small pale sun catches. Derive these from
	// the existing painted crests; no animated noise or extra texture sample.
	float crest = smoothstep(1.15, 1.55, brush.g);
	near_water = mix(near_water, crest_tint, crest * 0.48);
	// Reproduce ProceduralSkyMaterial's default ground_curve (0.02 -> inverse
	// curve 30). Matching only its horizon colour leaves a band at the finite
	// far clip, because those pixels look slightly below the actual horizon.
	float view_y = normalize(world_pos - CAMERA_POSITION_WORLD).y;
	float ground_curve = pow(clamp(1.0 + view_y, 0.0, 1.0), 30.0);
	vec3 distant_ground = mix(bottom_tint.rgb, horizon_tint.rgb, ground_curve);
	// Local fog is disabled so this sky-gradient match is not tinted twice.
	// The runner's low fixed-lateral camera makes off-axis world-X
    // derivatives enormous. World-fixed UVs require >100:1 anisotropy here,
    // averaging painted wave bodies into rows. Angular lateral coordinates
    // keep the same paint readable; longitudinal phase remains world-anchored.
    // This is authored runner-camera mapping, not a change to mip filtering.
    float detail_weight = clamp(day_detail_weight, 0.0, 1.0);
    if (painted_enabled && detail_weight > 0.0) {
        float view_depth = max(-VERTEX.z, 1.0);
        vec2 detail_coordinates = vec2(
            VERTEX.x / view_depth * day_lateral_reference_metres / day_tile_metres.x,
            world_pos.z / day_tile_metres.y);
        vec2 detail_uv = abs(fract(detail_coordinates * 0.5) * 2.0 - 1.0);
        float signal = paint_srgb_scalar(texture(painted_albedo, detail_uv).g);
        vec3 detailed_water = mix(day_trough_tint.rgb, day_body_tint.rgb,
            smoothstep(0.35, 0.43, signal));
        detailed_water = mix(detailed_water, day_face_tint.rgb,
            smoothstep(0.43, 0.58, signal));
        // A sparse smooth tail survives filtering without whitening every
        // wave face. These highlights follow the existing painted facets.
        float catch_weight = smoothstep(0.60, 0.73, signal);
        detailed_water = mix(detailed_water, day_crest_tint.rgb, catch_weight);
        near_water = mix(near_water, detailed_water, detail_weight);
    }
    // Preserve the exact distant sky match and smooth approach to it. DAY
    // keeps saturated middle-distance facets instead of bleaching them early.
    float day_haze = haze * haze;
    day_haze *= day_haze;
    float detailed_haze = mix(haze, day_haze, detail_weight);
    ALBEDO = mix(near_water, distant_ground, detailed_haze);
}
