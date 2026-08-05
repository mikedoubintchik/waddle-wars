// Snow surface: procedural value-noise detail, sparse view-dependent sparkle
// glints, soft normal perturbation. Mobile-cheap: no textures, no loops,
// 2 noise octaves (8 hash evaluations) per fragment.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 tint : source_color = vec4(0.94, 0.97, 1.0, 1.0);
uniform vec4 shadow_tint : source_color = vec4(0.78, 0.86, 0.98, 1.0);
uniform float noise_scale = 0.35;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.5;
uniform float normal_strength : hint_range(0.0, 1.0) = 0.35;
uniform float sparkle_strength : hint_range(0.0, 2.0) = 0.55;
uniform float sparkle_density = 9.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.85;

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
	// Top-projected noise ("triplanar-ish": snow surfaces face mostly up,
	// so a single world-XZ projection reads correctly at track scale).
	vec2 uv = world_pos.xz * noise_scale;
	float n = value_noise(uv) * 0.65 + value_noise(uv * 3.7) * 0.35;
	float blend = clamp(0.5 + (n - 0.5) * detail_strength * 1.6, 0.0, 1.0);
	ALBEDO = mix(shadow_tint.rgb, tint.rgb, blend);
	ROUGHNESS = roughness_value;
	SPECULAR = 0.3;

	// Soft normal perturbation from noise gradient (view-space tilt, no
	// tangents required — procedural ribbons have none).
	float e = 0.9;
	float nx = value_noise(uv + vec2(e, 0.0)) - n;
	float nz = value_noise(uv + vec2(0.0, e)) - n;
	vec3 bump_world = vec3(-nx, 0.0, -nz) * normal_strength;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(bump_world, 0.0)).xyz);

	// Sparse sparkle glints: per-cell random facet direction, brightens when
	// the view direction lines up. Sparse via high hash threshold.
	vec2 cell = floor(world_pos.xz * sparkle_density);
	float pick = hash21(cell + 17.0);
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_pos);
	vec3 facet = normalize(vec3(
		hash21(cell) - 0.5,
		hash21(cell + 3.0) * 0.6 + 0.55,
		hash21(cell + 7.0) - 0.5));
	float glint = pow(clamp(dot(view_dir, facet), 0.0, 1.0), 48.0);
	EMISSION = vec3(1.0, 1.0, 0.98) * glint * step(0.8, pick) * sparkle_strength;
}
