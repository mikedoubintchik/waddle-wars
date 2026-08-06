// Snow surface: procedural value-noise detail, sparse view-dependent sparkle
// glints, soft normal perturbation. Detail additions (gated by detail_level,
// skipped entirely at 0): broad ~2 m grain patches, fine micro-roughness
// variation, two-octave sastrugi directional ridging, grazing-angle glint
// boost, a cool cavity tint, and footprint-scale micro bumps that only exist
// within ~18 m of the camera (their own tight distance fade). Crevice-depth
// blue: deep noise troughs cool + darken toward glacial blue (grayscale-safe
// depth cue). Sparkles carry a faint per-glint prismatic tint like real
// faceted crystals and a per-glint temporal twinkle so snow scintillates even
// under a stationary camera. Physical plausibility: a wrapped-diffuse subsurface
// approximation adds a warm forward-scatter bleed when the sun grazes the
// surface, and shadowed tones cool slightly toward sky-bounce blue.
// All micro-detail fades out with view distance (clean smooth snow beyond
// ~60 m, sparkle beyond ~20 m, micro bumps beyond ~18 m) so mid/far ground
// never reads as static or confetti at race-camera distance. Mobile-cheap:
// no textures, no loops; 2 noise octaves base plus 8 extra noise samples
// across the distance-gated detail branches.
// WebGL2/gl_compatibility-safe: basic spatial features only, no screen or
// depth reads.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 tint : source_color = vec4(0.94, 0.97, 1.0, 1.0);
uniform vec4 shadow_tint : source_color = vec4(0.85, 0.91, 0.99, 1.0);
uniform float noise_scale = 0.35;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.32;
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
uniform vec4 cavity_tint : source_color = vec4(0.6, 0.74, 1.0, 1.0);
uniform float cavity_strength : hint_range(0.0, 1.0) = 0.28;
// Footprint-scale micro bumps (~0.4 m hollows/crests): normal perturbation +
// matched shading that only resolves within [micro_fade_start,
// micro_fade_end] metres — near-camera crunch, invisible at mid-distance.
uniform float micro_bump_strength : hint_range(0.0, 1.0) = 0.5;
uniform float micro_bump_scale = 2.6;
uniform float micro_fade_start = 8.0;
uniform float micro_fade_end = 18.0;
// Grain/sastrugi/cavity/roughness variance fade to zero across
// [detail_fade_start, detail_fade_end] metres of view distance; sparkle
// glints cut off harder so only near-camera snow fires.
uniform float detail_fade_start = 25.0;
uniform float detail_fade_end = 60.0;
uniform float sparkle_fade_start = 12.0;
uniform float sparkle_fade_end = 20.0;
// Direction TOWARD the sun (world space); pairs with the course sun light.
// Drives the wrapped-diffuse subsurface bleed only — safe to leave default.
uniform vec3 sun_direction = vec3(-0.35, 0.72, -0.55);
// Warm scatter color of light that has traveled through the snow crust.
uniform vec4 sss_tint : source_color = vec4(1.0, 0.86, 0.68, 1.0);
uniform float sss_strength : hint_range(0.0, 1.0) = 0.55;
// Cool sky-bounce shift applied to the shadowed end of the albedo ramp.
uniform float shadow_cool : hint_range(0.0, 1.0) = 0.35;

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

		// Finer micro-roughness octave (~0.3 m): breaks the specular response
		// into subtle crystalline patchiness so highlights stop reading as a
		// uniform plastic sheen.
		float micro = value_noise(world_pos.xz * grain_scale * 6.0 + vec2(7.3, 91.4));
		roughness = clamp(roughness + (micro - 0.5) * 0.12 * dl, 0.05, 1.0);

		// Sastrugi: low-frequency noise stretched along the wind direction;
		// its cross-wind gradient tilts the normal into directional ridging.
		vec2 wdir = normalize(sastrugi_dir);
		vec2 wperp = vec2(-wdir.y, wdir.x);
		vec2 suv = vec2(dot(world_pos.xz, wperp) * 0.55, dot(world_pos.xz, wdir) * 0.07);
		float s = value_noise(suv);
		float sgrad = value_noise(suv + vec2(0.35, 0.0)) - s;
		bump_world += vec3(wperp.x, 0.0, wperp.y) * (-sgrad) * sastrugi_strength * dl;

		// Second, finer sastrugi octave: wind-rippled corduroy riding on the
		// broad ridges — the cross-wind gradient again tilts the normal.
		vec2 suv2 = suv * vec2(3.3, 2.2) + 11.0;
		float s2 = value_noise(suv2);
		float sgrad2 = value_noise(suv2 + vec2(0.3, 0.0)) - s2;
		bump_world += vec3(wperp.x, 0.0, wperp.y) * (-sgrad2) * sastrugi_strength * 0.45 * dl;
	}

	float blend = clamp(0.5 + (n - 0.5) * detail_strength * 1.05, 0.0, 1.0);
	// Sky-bounce: shadowed snow is lit mostly by blue sky, so the dark end of
	// the ramp cools slightly (drop red/green, hold blue) — never a hue swap.
	vec3 shadow_col = shadow_tint.rgb * mix(vec3(1.0), vec3(0.88, 0.95, 1.02), shadow_cool);
	vec3 albedo = mix(shadow_col, tint.rgb, blend);

	// Crevice depth-blue (always on, zero extra samples): the deepest noise
	// troughs cool toward glacial blue with a matched brightness drop, so the
	// depth cue reads in grayscale too — light dies blue inside packed snow.
	float crev = smoothstep(0.45, 0.15, n_base);
	albedo = mix(albedo, albedo * vec3(0.84, 0.91, 1.05), crev * 0.25);

	if (dl > 0.001) {
		// Faint cool skylight tint in grain troughs. Wide smoothstep and low
		// strength keep it a gentle tonal shift, never dirt speckle.
		float cavity = 1.0 - smoothstep(0.25, 0.75, grain);
		albedo = mix(albedo, albedo * cavity_tint.rgb, cavity * cavity_strength * dl);
	}

	// Footprint-scale micro bumps: a tighter near-camera fade than the main
	// detail band, so trampled-crust relief exists only where wheels-of-feet
	// scale is actually resolvable. Crest/hollow shading matches the normal
	// tilt so the relief reads even under flat overcast light.
	float micro_fade = 1.0 - smoothstep(micro_fade_start, micro_fade_end, view_dist);
	float md = detail_level * micro_fade;
	if (md > 0.001) {
		vec2 muv = world_pos.xz * micro_bump_scale + vec2(5.2, 77.7);
		float m0 = value_noise(muv);
		float m_x = value_noise(muv + vec2(0.55, 0.0)) - m0;
		float m_z = value_noise(muv + vec2(0.0, 0.55)) - m0;
		bump_world += vec3(-m_x, 0.0, -m_z) * micro_bump_strength * 1.4 * md;
		albedo *= 1.0 + (m0 - 0.5) * 0.14 * md;
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
	// Per-glint prismatic tint: each facet leans its own way off pure white
	// (ice crystals refract), normalized so brightness stays constant.
	vec3 sparkle_tint = mix(vec3(1.0, 1.0, 0.98),
			normalize(vec3(0.6 + hash21(cell + 23.0) * 0.8, 0.75 + hash21(cell + 29.0) * 0.5, 1.0)) * 1.6,
			0.45);
	// Temporal twinkle: each glint breathes at its own phase/rate, so snow
	// still scintillates when the camera holds still (start line, menus) the
	// way real crystals flicker with micro shifts in sun angle. Never drops to
	// zero — the view-dependent lobe stays the primary driver.
	float twinkle = 0.72 + 0.28 * sin(TIME * (1.5 + hash21(cell + 41.0) * 3.5) + hash21(cell + 53.0) * 6.2832);
	vec3 glint_emission = sparkle_tint * glint * step(0.93, pick) * sparkle_strength * glint_gain * sparkle_fade * twinkle * 1.25;

	// Wrapped-diffuse subsurface approximation: when the sun grazes the surface
	// and the camera looks back toward the light, a fraction of it has scattered
	// through the top crust and re-emerges warm. Quadratic graze term keeps the
	// bleed confined to low-sun geometry (drift flanks, ridge shoulders).
	vec3 sun = normalize(sun_direction);
	vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float sun_graze = 1.0 - clamp(dot(n_world, sun), 0.0, 1.0);
	// pow-1.5 tightens the forward lobe: the bleed brightens fastest when the
	// camera looks nearly straight into the low sun, like real thin crust.
	float toward_sun = pow(clamp(dot(view_dir, -sun) * 0.5 + 0.5, 0.0, 1.0), 1.5);
	float sss = sun_graze * sun_graze * toward_sun * sss_strength;
	vec3 sss_emission = albedo * sss_tint.rgb * sss * 0.55;

	EMISSION = glint_emission + sss_emission;
}
