// Ice surface: fresnel rim brightening, view-angle interior darkening (fake
// depth), noise-driven roughness variation, blue-green tint controls.
// ALWAYS-ON ice identity (so ice reads as ice at a glance on every quality
// preset, and stays colorblind-accessible via brightness + pattern, not hue):
//   - voronoi crack plates: bright hairline veins along cell borders,
//   - a toward-camera stretched sun specular streak (skating-rink gleam),
//   - a frosted WHITE edge border with ragged noise boundary and crystalline
//     stipple, driven by UV.x (lateral) + UV2.x (run-end proximity) and gated
//     by the UV2.y == 1 "track floor" flag TrackBuilder writes, so only track
//     ribbons get outlined (bergs/props with no UV2 are unaffected).
// High-detail additions (gated by detail_level, skipped entirely at 0):
// internal depth veins (two view-parallaxed noise layers), a deep strongly
// parallaxed absorption layer that pulls the interior toward a colder tint
// (pseudo-refraction depth), a finer hairline crack web, sparse sharp specular
// glint facets, and a stronger spectral fresnel rim (blue -> cyan at grazing).
// Mobile-cheap: opaque, no textures; base = 1 noise octave + one 3x3 voronoi
// (sin-free hash) + streak ALU; frost adds 3 samples only on track floors;
// detail branch adds 6 noise samples + one finer voronoi.
// DISTANCE DISCIPLINE (do not remove): the plate veins, hairline web, glint
// facets and frost stipple are all sub-metre features. Left at full strength
// they fall below a pixel at race-camera range and alias into crawling
// speckle, which reads as dirty ice rather than ice. So the vein edge widens
// with view distance (a poor-man's mip: veins go soft, never stroboscopic),
// the sub-decimetre layers fade out entirely, and roughness rises with
// distance to keep the specular lobe from aliasing into sparkle noise.
// WebGL2/gl_compatibility-safe: basic spatial features only, no screen or
// depth reads.
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
// Voronoi crack plates: crack_scale = plate frequency (0.45 => ~2.2 m slabs),
// crack_strength = vein brightness, crack_sharpness = line half-width.
uniform float crack_scale = 0.45;
uniform float crack_strength : hint_range(0.0, 1.0) = 0.6;
uniform float crack_sharpness = 0.09;
// Pseudo-refraction depth layer: how far the deep layer parallax-shifts with
// the view (bigger = reads deeper) and the cold color it absorbs toward.
uniform float depth_parallax = 2.6;
uniform vec4 depth_tint : source_color = vec4(0.12, 0.3, 0.52, 1.0);
uniform float depth_strength : hint_range(0.0, 1.0) = 0.28;
// Sparse mirror-facet glints: sharp micro-highlights that fire as the camera
// sweeps past, like real polished ice.
uniform float glint_strength : hint_range(0.0, 2.0) = 0.6;
uniform float glint_density = 2.2;
// Frosted white edge border (accessibility outline: brightness + pattern).
// Width is a fraction of UV.x, so ~0.075 => ~0.5-1 m band on a 7-14 m ribbon.
uniform float frost_strength : hint_range(0.0, 1.0) = 0.9;
uniform float frost_edge_width : hint_range(0.0, 0.3) = 0.075;
uniform vec4 frost_tint : source_color = vec4(0.96, 0.99, 1.0, 1.0);
// Toward-camera stretched sun streak (elliptical gaussian specular smear).
// Direction TOWARD the sun; pairs with the course sun light.
uniform float streak_strength : hint_range(0.0, 2.0) = 0.7;
uniform vec3 sun_direction = vec3(-0.35, 0.72, -0.55);

varying vec3 world_pos;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Sin-free 2D->2D hash (Hoskins-style) for voronoi cell offsets: cheaper and
// more precision-stable on mobile GPUs than nested sin hashes.
vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
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

// F1/F2 cellular distances; F2-F1 -> 0 along plate borders = crack veins.
vec2 voronoi_f12(vec2 p) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + hash22(ip + g) - fp;
			float d = dot(r, r);
			if (d < f1) {
				f2 = f1;
				f1 = d;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return vec2(sqrt(f1), sqrt(f2));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, rim_power);
	float n = value_noise(world_pos.xz * noise_scale + world_pos.y * 0.1);
	vec3 to_cam = CAMERA_POSITION_WORLD - world_pos;
	float view_dist = length(to_cam);
	vec3 view_world = to_cam / max(view_dist, 0.0001);
	vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// 0 near the camera, 1 out past the point where sub-metre detail stops
	// being resolvable. Drives every anti-aliasing fade below.
	float far = smoothstep(20.0, 60.0, view_dist);

	// Looking straight down = "deeper" ice color; grazing angle = pale rim.
	// clarity pushes toward the deep look (clear ice reads darker inside).
	vec3 body = mix(tint.rgb, deep_tint.rgb, clarity * facing * 0.9);
	// Glassy interior: deepening also cools toward cyan-blue with a matched
	// brightness drop, so the depth cue survives grayscale.
	body = mix(body, body * vec3(0.82, 1.0, 1.12), clarity * facing * 0.35);
	body = mix(body, body * 0.92, n * 0.6); // subtle mottling

	// Voronoi crack plates (always on): bright hairline veins where adjacent
	// cell distances tie. Low-frequency noise varies vein intensity so the
	// network reads organic, not tiled.
	vec2 vor = voronoi_f12(world_pos.xz * crack_scale);
	// Widen the vein edge with distance instead of letting a fixed hairline
	// width thin out below a pixel: the network stays legible far down the
	// track but resolves as a soft line rather than a dashed, crawling one.
	float crack_w = crack_sharpness * (1.0 + far * 2.5);
	float crack_line = 1.0 - smoothstep(0.0, crack_w, vor.y - vor.x);
	float crack_var = 0.55 + 0.45 * value_noise(world_pos.xz * 0.07 + 13.1);
	float crack = crack_line * crack_strength * crack_var * (1.0 - far * 0.35);
	body = mix(body, vec3(0.9, 0.96, 1.0), crack * 0.75);

	vec3 rim_col = rim_tint.rgb;
	float rim_amt = rim_strength;
	vec3 glint_emission = vec3(0.0);

	if (detail_level > 0.001) {
		// Internal depth veins: two noise layers pushed opposite amounts along
		// the view vector; the differential parallax reads as structure
		// suspended below the surface. Very slow scroll = live glacial shimmer.
		vec2 base_uv = world_pos.xz * vein_scale + world_pos.y * 0.31;
		float v1 = value_noise(base_uv - view_world.xz * 0.55 + vec2(TIME * 0.015, 0.0));
		float v2 = value_noise(base_uv * 1.9 - view_world.xz * 1.35 + vec2(0.0, TIME * -0.011));
		float veins = smoothstep(0.52, 0.78, v1 * 0.6 + v2 * 0.4);
		body = mix(body, vein_tint.rgb * mix(0.55, 0.85, facing),
				veins * vein_strength * clarity * detail_level * 0.6 * (1.0 - far * 0.7));

		// Deep absorption layer: low-frequency noise pushed far along the view
		// vector. The strong differential parallax against the vein layers
		// reads as thickness, and its cold tint sells light dying with depth.
		float v3 = value_noise(base_uv * 0.55 - view_world.xz * depth_parallax + vec2(27.3, 9.1));
		body = mix(body, depth_tint.rgb,
				smoothstep(0.3, 0.85, v3) * depth_strength * clarity * detail_level);

		// Finer hairline web between the main plates, sparsely masked so most
		// slabs stay clean glass. ~0.7 m plates with a ~4 cm vein: only ever
		// resolvable up close, so it fades out well before the main network
		// does, widening as it goes. The sparse mask is a smoothstep rather
		// than a step() — a hard threshold on a noise field draws a visible
		// seam across the slabs wherever it flips.
		float hair_fade = 1.0 - smoothstep(10.0, 30.0, view_dist);
		vec2 vor2 = voronoi_f12(world_pos.xz * crack_scale * 3.1 + 7.7);
		float hair = 1.0 - smoothstep(0.0, 0.05 + (1.0 - hair_fade) * 0.06, vor2.y - vor2.x);
		hair *= smoothstep(0.42, 0.58, value_noise(world_pos.xz * 0.11 + 3.7))
				* 0.35 * detail_level * hair_fade;
		body = mix(body, vec3(0.85, 0.94, 1.0), hair * 0.5);
		crack = max(crack, hair);

		// Spectral rim: blue base shifting toward cyan at grazing angles.
		rim_col = mix(rim_tint.rgb, vec3(0.55, 1.0, 1.0), clamp(fresnel * detail_level * 0.7, 0.0, 1.0));
		rim_amt = rim_strength * (1.0 + 0.4 * detail_level);

		// Sparse sharp glint facets: per-cell random mirror direction, tight
		// pow-96 lobe so highlights snap on/off as the camera moves — polished
		// ice glitter rather than a broad plastic sheen. Only ~10% of cells
		// host a facet; the rest of the surface stays calm.
		vec2 cell = floor(world_pos.xz * glint_density);
		vec3 facet = normalize(vec3(
			hash21(cell) - 0.5,
			hash21(cell + 3.0) * 0.5 + 0.6,
			hash21(cell + 7.0) - 0.5));
		// Cut off with distance like the snow sparkle does: a pow-96 lobe on
		// 0.45 m cells is pure aliasing once a cell is smaller than a pixel.
		float glint_fade = 1.0 - smoothstep(16.0, 34.0, view_dist);
		float g = pow(clamp(dot(view_world, facet), 0.0, 1.0), 96.0);
		glint_emission = vec3(0.9, 0.97, 1.0) * g * step(0.9, hash21(cell + 17.0))
				* glint_strength * detail_level * glint_fade;
	}

	// Frosted edge border: only on meshes flagged as track floors via
	// UV2.y == 1 (TrackBuilder ribbons). Lateral band from UV.x, end band from
	// UV2.x run-end proximity; both edges are noise-ragged, and a crystalline
	// stipple modulates the band so it reads as PATTERN + BRIGHTNESS, never
	// hue — outlining every ice patch for colorblind players.
	float frost = 0.0;
	if (UV2.y > 0.5) {
		float frost_n = value_noise(world_pos.xz * 2.3);
		float lat = min(UV.x, 1.0 - UV.x);
		float ragged_w = frost_edge_width * (0.55 + 0.9 * frost_n);
		float frost_side = 1.0 - smoothstep(ragged_w * 0.45, ragged_w, lat);
		float frost_end = smoothstep(0.3, 0.85, UV2.x * (0.7 + 0.6 * frost_n));
		frost = max(frost_side, frost_end) * frost_strength;
		// Crystalline stipple: ~14 cm cells, so its contrast is annealed out
		// with distance — otherwise the band edge boils along the track.
		float stip = value_noise(world_pos.xz * 7.0 + 31.0);
		frost *= 1.0 - (0.3 - 0.3 * far) * (1.0 - smoothstep(0.35, 0.75, stip));
	}

	// Toward-camera stretched sun streak: elliptical gaussian around the half
	// vector, wide along the view-projected axis and tight across it — the
	// long gleam a low sun drags over a rink. Fades where the surface frosts
	// or the projected view axis degenerates (camera looking straight down).
	vec3 sun = normalize(sun_direction);
	vec3 h = normalize(sun + view_world);
	vec3 vt = view_world - n_world * dot(view_world, n_world);
	float vt_len = length(vt);
	vec3 vdir = vt / max(vt_len, 0.0001);
	vec3 sdir = normalize(cross(n_world, vdir) + vec3(0.00001));
	vec3 dev = h - n_world * dot(h, n_world);
	float d_along = dot(dev, vdir);
	float d_perp = dot(dev, sdir);
	float streak = exp(-(d_perp * d_perp * 1400.0 + d_along * d_along * 60.0));
	streak *= smoothstep(0.04, 0.18, vt_len) * (0.3 + 0.7 * clarity);
	vec3 streak_emission = vec3(0.95, 0.99, 1.0) * streak * streak_strength * (1.0 - frost);

	vec3 albedo = mix(body, rim_col, clamp(fresnel * rim_amt, 0.0, 1.0));
	albedo = mix(albedo, frost_tint.rgb, frost);
	ALBEDO = albedo;
	EMISSION = rim_col * fresnel * rim_amt * 0.25 * (1.0 - frost)
			+ glint_emission * (1.0 - frost)
			+ streak_emission
			+ frost_tint.rgb * frost * 0.08;

	// Specular anti-aliasing: a near-mirror roughness on a surface whose
	// normal-and-noise detail is shrinking below a pixel makes the highlight
	// flicker. Widening the lobe with distance is the standard cheap fix and
	// also matches how a rink actually reads far away — a broad sheen, not
	// point sparkle.
	float rough = clamp(roughness_base + (n - 0.5) * roughness_variation * (1.0 - far * 0.6)
			+ crack * 0.25, 0.02, 1.0);
	rough = clamp(rough + far * 0.14, 0.02, 1.0);
	ROUGHNESS = mix(rough, 0.75, frost);
	SPECULAR = specular_amount;
	METALLIC = 0.0;
}
