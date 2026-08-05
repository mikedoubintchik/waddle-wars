// Ice surface: fresnel rim brightening, view-angle interior darkening (fake
// depth), noise-driven roughness variation, blue-green tint controls.
// High-detail additions (gated by detail_level, skipped entirely at 0):
// internal depth veins (two view-parallaxed noise layers), sparse sharp crack
// lines, and a stronger spectral fresnel rim (blue -> cyan at grazing).
// Mobile-cheap: opaque, no textures, 1 noise octave base + 4 extra samples
// inside the uniform detail branch.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 tint : source_color = vec4(0.52, 0.78, 0.96, 1.0);
uniform vec4 deep_tint : source_color = vec4(0.1, 0.32, 0.55, 1.0);
uniform vec4 rim_tint : source_color = vec4(0.85, 0.97, 1.0, 1.0);
uniform float clarity : hint_range(0.0, 1.0) = 0.7;
uniform float rim_power = 2.6;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.45;
uniform float noise_scale = 0.22;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.12;
uniform float roughness_variation : hint_range(0.0, 1.0) = 0.25;
uniform float specular_amount : hint_range(0.0, 1.0) = 0.6;
// 0 = base look (cheapest), 1 = full micro-detail. Set by VisualLibrary from
// the display quality preset (low=0, medium=0.5, high=1).
uniform float detail_level : hint_range(0.0, 1.0) = 1.0;
uniform float vein_scale = 0.8;
uniform float vein_strength : hint_range(0.0, 1.0) = 0.55;
uniform vec4 vein_tint : source_color = vec4(0.75, 0.92, 1.0, 1.0);
uniform float crack_scale = 0.45;
uniform float crack_strength : hint_range(0.0, 1.0) = 0.6;

varying vec3 world_pos;

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

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, rim_power);
	float n = value_noise(world_pos.xz * noise_scale + world_pos.y * 0.1);

	// Looking straight down = "deeper" ice color; grazing angle = pale rim.
	// clarity pushes toward the deep look (clear ice reads darker inside).
	vec3 body = mix(tint.rgb, deep_tint.rgb, clarity * facing * 0.85);
	body = mix(body, body * 0.92, n * 0.6); // subtle mottling

	vec3 rim_col = rim_tint.rgb;
	float rim_amt = rim_strength;
	float crack = 0.0;

	if (detail_level > 0.001) {
		// Internal depth veins: two noise layers pushed opposite amounts along
		// the view vector; the differential parallax reads as structure
		// suspended below the surface. Very slow scroll = live glacial shimmer.
		vec3 view_world = normalize(CAMERA_POSITION_WORLD - world_pos);
		vec2 base_uv = world_pos.xz * vein_scale + world_pos.y * 0.31;
		float v1 = value_noise(base_uv - view_world.xz * 0.55 + vec2(TIME * 0.015, 0.0));
		float v2 = value_noise(base_uv * 1.9 - view_world.xz * 1.35 + vec2(0.0, TIME * -0.011));
		float veins = smoothstep(0.52, 0.78, v1 * 0.6 + v2 * 0.4);
		body = mix(body, vein_tint.rgb * mix(0.55, 0.85, facing),
				veins * vein_strength * clarity * detail_level * 0.6);

		// Sparse sharp crack lines: thin band around the noise midline, masked
		// by a low-frequency threshold so most of the surface stays clean.
		float cn = value_noise(world_pos.xz * crack_scale + 41.7);
		float line = 1.0 - smoothstep(0.012, 0.05, abs(cn - 0.5));
		float sparse = step(0.55, value_noise(world_pos.xz * 0.07 + 13.1));
		crack = line * sparse * crack_strength * detail_level;
		body = mix(body, vec3(0.93, 0.98, 1.0), crack * 0.7);

		// Spectral rim: blue base shifting toward cyan at grazing angles.
		rim_col = mix(rim_tint.rgb, vec3(0.55, 1.0, 1.0), clamp(fresnel * detail_level * 0.7, 0.0, 1.0));
		rim_amt = rim_strength * (1.0 + 0.4 * detail_level);
	}

	ALBEDO = mix(body, rim_col, clamp(fresnel * rim_amt, 0.0, 1.0));
	EMISSION = rim_col * fresnel * rim_amt * 0.25;

	ROUGHNESS = clamp(roughness_base + (n - 0.5) * roughness_variation + crack * 0.3, 0.02, 1.0);
	SPECULAR = specular_amount;
	METALLIC = 0.0;
}
