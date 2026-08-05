// Snow surface: procedural value-noise detail, sparse view-dependent sparkle
// glints, soft normal perturbation. Detail additions (gated by detail_level,
// skipped entirely at 0): broad ~2 m grain patches, sastrugi directional
// ridging, grazing-angle glint boost, and a faint cool cavity tint.
// All micro-detail fades out with view distance (clean smooth snow beyond
// ~60 m, sparkle beyond ~20 m) so mid/far ground never reads as static or
// confetti at race-camera distance. Mobile-cheap: no textures, no loops;
// 2 noise octaves base plus 3 extra noise samples inside the detail branch.
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
// 0 = base look (cheapest), 1 = full micro-detail. Set by VisualLibrary from
// the display quality preset (low=0, medium=0.5, high=1).
uniform float detail_level : hint_range(0.0, 1.0) = 1.0;
// World-space frequency of the detail grain octave. 0.5 => ~2 m patches.
// Keep within 0.25-0.65 (1.5-4 m patches); higher values degrade into
// high-frequency pixel confetti at race-camera distance (10-40 m).
uniform float grain_scale = 0.5;
uniform float sastrugi_strength : hint_range(0.0, 1.0) = 0.45;
uniform vec2 sastrugi_dir = vec2(0.28, 1.0); // wind travel direction, world XZ
uniform vec4 cavity_tint : source_color = vec4(0.72, 0.82, 1.0, 1.0);
uniform float cavity_strength : hint_range(0.0, 1.0) = 0.15;
// Grain/sastrugi/cavity/roughness variance fade to zero across
// [detail_fade_start, detail_fade_end] metres of view distance; sparkle
// glints cut off harder so only near-camera snow fires.
uniform float detail_fade_start = 25.0;
uniform float detail_fade_end = 60.0;
uniform float sparkle_fade_start = 12.0;
uniform float sparkle_fade_end = 20.0;

varying vec3 world_pos;
varying float view_dist;

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
	// View-space distance drives the detail/sparkle distance fades.
	view_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	// Top-projected noise ("triplanar-ish": snow surfaces face mostly up,
	// so a single world-XZ projection reads correctly at track scale).
	// Base tonal patches sit at ~2.9 m and ~1.4 m — inside the 1.5-4 m band
	// the race camera resolves as soft drifts rather than mottle.
	vec2 uv = world_pos.xz * noise_scale;
	float n_base = value_noise(uv) * 0.7 + value_noise(uv * 2.1) * 0.3;
	float n = n_base;
	float grain = 0.5;
	float roughness = roughness_value;

	// Distance fade: micro-detail is only resolvable (and only flattering)
	// near the camera; farther snow goes clean and smooth. Skipping the
	// detail branch entirely at distance is also a small perf win.
	float detail_fade = 1.0 - smoothstep(detail_fade_start, detail_fade_end, view_dist);
	float dl = detail_level * detail_fade;

	// Soft normal perturbation from noise gradient (view-space tilt, no
	// tangents required — procedural ribbons have none).
	float e = 0.9;
	float nx = value_noise(uv + vec2(e, 0.0)) - n_base;
	float nz = value_noise(uv + vec2(0.0, e)) - n_base;
	vec3 bump_world = vec3(-nx, 0.0, -nz) * normal_strength;

	if (dl > 0.001) {
		// Broad grain patches (~1/grain_scale metres): a subtle close-range
		// tonal variance (few percent of luminance) plus mild roughness
		// variance so the specular response stops reading flat.
		grain = value_noise(world_pos.xz * grain_scale + vec2(41.7, 13.9));
		n = mix(n_base, n_base * 0.9 + grain * 0.1, dl);
		roughness = clamp(roughness_value + (grain - 0.5) * 0.1 * dl, 0.05, 1.0);

		// Sastrugi: low-frequency noise stretched along the wind direction;
		// its cross-wind gradient tilts the normal into directional ridging.
		vec2 wdir = normalize(sastrugi_dir);
		vec2 wperp = vec2(-wdir.y, wdir.x);
		vec2 suv = vec2(dot(world_pos.xz, wperp) * 0.55, dot(world_pos.xz, wdir) * 0.07);
		float s = value_noise(suv);
		float sgrad = value_noise(suv + vec2(0.35, 0.0)) - s;
		bump_world += vec3(wperp.x, 0.0, wperp.y) * (-sgrad) * sastrugi_strength * dl;
	}

	float blend = clamp(0.5 + (n - 0.5) * detail_strength * 1.6, 0.0, 1.0);
	vec3 albedo = mix(shadow_tint.rgb, tint.rgb, blend);

	if (dl > 0.001) {
		// Faint cool skylight tint in grain troughs. Wide smoothstep and low
		// strength keep it a gentle tonal shift, never dirt speckle.
		float cavity = 1.0 - smoothstep(0.25, 0.75, grain);
		albedo = mix(albedo, albedo * cavity_tint.rgb, cavity * cavity_strength * dl);
	}

	ALBEDO = albedo;
	ROUGHNESS = roughness;
	SPECULAR = 0.3;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(bump_world, 0.0)).xyz);

	// Sparse sparkle glints: per-cell random facet direction, brightens when
	// the view direction lines up. Only the top ~7% of cells host a glint,
	// and glints fade out entirely past ~20 m so distant ground stays calm.
	// At high detail, glints gain modestly at grazing angles like real snow.
	vec2 cell = floor(world_pos.xz * sparkle_density);
	float pick = hash21(cell + 17.0);
	float sparkle_fade = 1.0 - smoothstep(sparkle_fade_start, sparkle_fade_end, view_dist);
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - world_pos);
	vec3 facet = normalize(vec3(
		hash21(cell) - 0.5,
		hash21(cell + 3.0) * 0.6 + 0.55,
		hash21(cell + 7.0) - 0.5));
	float glint = pow(clamp(dot(view_dir, facet), 0.0, 1.0), 48.0);
	float grazing = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float glint_gain = 1.0 + grazing * 1.2 * detail_level;
	EMISSION = vec3(1.0, 1.0, 0.98) * glint * step(0.93, pick) * sparkle_strength * glint_gain * sparkle_fade;
}
