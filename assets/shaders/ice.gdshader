// Ice surface: fresnel rim brightening, view-angle interior darkening (fake
// depth), noise-driven roughness variation, blue-green tint controls.
// Mobile-cheap: opaque, no textures, single noise octave.
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
	ALBEDO = mix(body, rim_tint.rgb, fresnel * rim_strength);
	EMISSION = rim_tint.rgb * fresnel * rim_strength * 0.25;

	ROUGHNESS = clamp(roughness_base + (n - 0.5) * roughness_variation, 0.02, 1.0);
	SPECULAR = specular_amount;
	METALLIC = 0.0;
}
