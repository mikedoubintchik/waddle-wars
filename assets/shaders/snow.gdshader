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
// NORMAL SAFETY (do not remove): every relief octave adds into one world-space
// bump vector with no knowledge of the others. Unbounded, their sum tilts the
// shading normal past the light terminator, and on a course with a low, dim
// key light (night/moonlit) those fragments lose the key entirely and render
// near-black — discrete dark blobs that read as dirt, not snow. So the bump is
// (a) built from real slope estimates over a SHORT finite-difference step, so
// the tilt follows the noise it shades instead of being a second incoherent
// field, (b) projected into the surface tangent plane, and (c) soft-saturated
// to max_normal_tilt. The shading normal therefore never deviates from the
// geometric normal by more than atan(max_normal_tilt).
// WebGL2/gl_compatibility-safe: basic spatial features only, no screen or
// depth reads.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 tint : source_color = vec4(0.94, 0.97, 1.0, 1.0);
uniform vec4 shadow_tint : source_color = vec4(0.85, 0.91, 0.99, 1.0);
uniform float noise_scale = 0.35;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.32;
uniform float normal_strength : hint_range(0.0, 1.0) = 0.35;
// Hard ceiling on the COMBINED relief tilt (tangent of the maximum shading
// normal deviation). 0.20 => ~11.3 deg peak, against a typical (RMS) tilt of
// ~6 deg from the octave weights below. Must stay well under tan(key light
// elevation) of the dimmest course — aurora's moon sits at ~23.6 deg
// (tan 0.44) — so every fragment stays on the lit side of the terminator even
// on banked track, while drifts still model. Raising this past ~0.3
// reintroduces the black-speckle artifact on night courses.
uniform float max_normal_tilt : hint_range(0.0, 1.0) = 0.2;
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
	// Keep the primary octave separately: the relief gradient below has to be
	// differenced against the SAME field it samples, otherwise the octave
	// mismatch shows up as a standing bias in the normal.
	float n_a = value_noise(uv);
	float n_base = n_a * 0.7 + value_noise(uv * 2.1) * 0.3;
	float n = n_base;
	float grain = 0.5;
	float roughness = roughness_value;

	// Distance fade: micro-detail is only resolvable (and only flattering)
	// near the camera; farther snow goes clean and smooth. Skipping the
	// detail branch entirely at distance is also a small perf win.
	float detail_fade = 1.0 - smoothstep(detail_fade_start, detail_fade_end, view_dist);
	float dl = detail_level * detail_fade;

	// Geometric world normal, captured BEFORE any perturbation: the relief is
	// accumulated in world space and gets projected back into this plane, so a
	// steep face (drift flank, banked wall) can never have its normal shoved
	// through the surface by a horizontal bump.
	vec3 geo_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

	// Soft normal perturbation from the noise SLOPE (view-space tilt, no
	// tangents required — procedural ribbons have none). The step is short
	// relative to the 1-unit noise lattice and the difference is divided by it,
	// so this is a real gradient: crests catch the key light and troughs lose
	// it, matching the tonal noise. A long step (>0.5) stops approximating a
	// derivative and instead samples a second, uncorrelated noise field at near
	// full amplitude — that is what turned this layer into mottle.
	float grad_e = 0.25;
	float nx = (value_noise(uv + vec2(grad_e, 0.0)) - n_a) / grad_e;
	float nz = (value_noise(uv + vec2(0.0, grad_e)) - n_a) / grad_e;
	// Beyond the detail band the 2.9 m relief is sub-pixel; hold a fraction of
	// it for large-scale form and drop the rest so far track cannot shimmer.
	float base_relief = normal_strength * 0.5 * mix(0.35, 1.0, detail_fade);
	vec3 bump_world = vec3(-nx, 0.0, -nz) * base_relief;

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
		float sgrad = (value_noise(suv + vec2(grad_e, 0.0)) - s) / grad_e;
		bump_world += vec3(wperp.x, 0.0, wperp.y) * (-sgrad) * sastrugi_strength * 0.4 * dl;

		// Second, finer sastrugi octave: wind-rippled corduroy riding on the
		// broad ridges — the cross-wind gradient again tilts the normal. Half
		// the weight of the broad octave, as a ripple should be.
		vec2 suv2 = suv * vec2(3.3, 2.2) + 11.0;
		float s2 = value_noise(suv2);
		float sgrad2 = (value_noise(suv2 + vec2(grad_e, 0.0)) - s2) / grad_e;
		bump_world += vec3(wperp.x, 0.0, wperp.y) * (-sgrad2) * sastrugi_strength * 0.18 * dl;
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
		// Sampled in a rotated, anisotropic frame. value_noise lives on a square
		// world-axis lattice, so sampling it straight gives evenly spaced,
		// axis-aligned hollows — a quilted polka-dot grid, the single most
		// synthetic-looking thing this shader can do at footprint scale.
		// Rotating ~31 deg off the world axes (and off the base/sastrugi
		// layers) and squashing one axis turns the cells into scalloped,
		// wind-drawn crust instead.
		vec2 mdir = vec2(0.857, 0.515);
		vec2 mperp = vec2(-mdir.y, mdir.x);
		vec2 muv = vec2(dot(world_pos.xz, mdir), dot(world_pos.xz, mperp) * 0.72)
				* micro_bump_scale + vec2(5.2, 77.7);
		float m0 = value_noise(muv);
		float m_x = (value_noise(muv + vec2(grad_e, 0.0)) - m0) / grad_e;
		float m_z = (value_noise(muv + vec2(0.0, grad_e)) - m0) / grad_e;
		// Rotate the gradient back into world XZ so the tilt matches the shape.
		vec2 mg = mdir * m_x + mperp * (m_z * 0.72);
		bump_world += vec3(-mg.x, 0.0, -mg.y) * micro_bump_strength * 0.24 * md;
		// Matched tonal crunch. Albedo relief is terminator-proof (it is a
		// multiply, it cannot drive a fragment to black), so it carries the
		// near-camera detail that the tilt cap deliberately refuses to.
		albedo *= 1.0 + (m0 - 0.5) * 0.16 * md;
	}

	// --- Combined tilt limiter (see NORMAL SAFETY note at the top) ----------
	// 1. Project into the tangent plane: the bump may only tilt the normal,
	//    never push it through the surface.
	bump_world -= geo_normal * dot(bump_world, geo_normal);
	// 2. Soft-saturate the total length. Exponential saturation is C-infinite
	//    and passes small bumps through untouched (factor -> 1 as len -> 0),
	//    compressing only the rare stacked peaks, so the relief keeps its shape
	//    instead of clipping into flat plateaus the way a hard clamp would.
	float bump_len = length(bump_world);
	float tilt = max(max_normal_tilt, 0.0001);
	bump_world *= tilt * (1.0 - exp(-bump_len / tilt)) / max(bump_len, 0.00001);

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
