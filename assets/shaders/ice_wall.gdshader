// Track edge walls: translucent glacial barrier upgrade over the old flat
// StandardMaterial3D. Identity cues, cheapest first:
//   - horizontal pressure-ridge strata (thin bright bands stacked in world Y
//     with a slow lateral wobble) — layered glacier ice, reads as PATTERN,
//   - fresnel rim brightening at grazing view angles (glassy body),
//   - a frosted BRIGHT top lip with a ragged noise boundary and a faint
//     constant glow, so the wall crest — the actual gameplay boundary — reads
//     by BRIGHTNESS in grayscale and on night courses (colorblind-safe).
// UV.x is 0 at the wall base and 1 at the top edge on BOTH track sides
// (TrackBuilder._wall_quad guarantees the orientation); UV.y repeats per
// segment, so all noise uses world_pos instead.
// Mobile-cheap: 3 noise samples, no textures, no branches. cull_disabled to
// match the old double-sided wall material (fresnel uses abs() so back faces
// shade correctly). WebGL2/gl_compatibility-safe: no screen/depth reads.
shader_type spatial;
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 tint : source_color = vec4(0.45, 0.65, 0.88, 1.0);
uniform vec4 strata_tint : source_color = vec4(0.9, 0.96, 1.0, 1.0);
uniform vec4 lip_tint : source_color = vec4(0.95, 0.98, 1.0, 1.0);
uniform float base_alpha : hint_range(0.0, 1.0) = 0.72;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.55;
uniform float rim_power = 2.2;
uniform float strata_strength : hint_range(0.0, 1.0) = 0.4;
// World-space vertical frequency of the strata bands (~1.7 => 0.6 m layers).
uniform float strata_freq = 1.7;
uniform float lip_glow : hint_range(0.0, 1.0) = 0.12;

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
	// abs(): with cull_disabled the geometric normal is unflipped on back
	// faces, and walls are legitimately seen from both sides.
	float facing = abs(dot(NORMAL, VIEW));
	float fresnel = pow(1.0 - clamp(facing, 0.0, 1.0), rim_power);

	// Compression strata: bands are a function of world Y with a gentle
	// lateral drift so layers undulate like real glacial sediment lines.
	float strata_n = value_noise(vec2((world_pos.x + world_pos.z) * 0.18, world_pos.y * strata_freq));
	float strata = smoothstep(0.6, 0.85, strata_n) * strata_strength;

	// Frosted crest lip: bright band along the top edge with a noise-ragged
	// lower boundary and crystalline stipple, mirroring the ice floor's frost
	// border language so track boundaries share one accessibility vocabulary.
	float lip_n = value_noise(world_pos.xz * 1.9 + 7.0);
	float lip = smoothstep(0.58 + lip_n * 0.18, 0.95, UV.x);
	lip *= 0.75 + 0.25 * smoothstep(0.35, 0.75, value_noise(world_pos.xz * 6.0 + 41.0));

	// --- depth absorption ---------------------------------------------------
	// Real glacier ice absorbs red first: the deeper the light has travelled,
	// the harder the body shifts toward saturated teal-blue and the darker it
	// gets. The wall base (UV.x 0) reads as deep ice, the crest as young frost.
	// This gradient is most of the difference between "blue glass slab" and
	// "cut glacier": a single flat tint has no depth story at all.
	float depth = 1.0 - clamp(UV.x, 0.0, 1.0);
	vec3 deep_col = tint.rgb * vec3(0.30, 0.62, 0.86);
	vec3 col = mix(tint.rgb, deep_col, depth * depth * 0.85);

	// --- fracture veins -----------------------------------------------------
	// Vertical crevasse lines: noise squashed hard in X so cells stretch into
	// tall seams. The ridge transform (1-|2n-1|) turns each cell wall into a
	// thin line; deep, they darken like a crack shadow, and a sparse second
	// set brightens like a refraction plane catching the sky. Both fade out
	// near the lip so the frost stays clean.
	float vein_n = value_noise(vec2((world_pos.x + world_pos.z) * 1.6, world_pos.y * 0.22) + 3.7);
	float vein = 1.0 - abs(vein_n * 2.0 - 1.0);
	float crack = smoothstep(0.80, 0.97, vein) * (1.0 - lip);
	float shine_n = value_noise(vec2((world_pos.x + world_pos.z) * 0.9, world_pos.y * 0.15) + 17.0);
	float shine = smoothstep(0.90, 0.99, 1.0 - abs(shine_n * 2.0 - 1.0)) * (1.0 - lip);
	col = mix(col, deep_col * 0.55, crack * 0.6);
	col = mix(col, strata_tint.rgb, shine * 0.5);

	col = mix(col, strata_tint.rgb, strata);
	col = mix(col, lip_tint.rgb, lip);
	ALBEDO = col;

	// --- surface relief -----------------------------------------------------
	// Broad wind-polished facets: a coarse noise gradient tilts the normal in
	// world space (tangent-free, same technique as the snow floor), so the sun
	// lays real moving highlights across the wall instead of one flat sheet of
	// lighting. Projected into the surface plane and kept small; a wall is
	// near-vertical, so even modest tilts read strongly in the specular.
	vec3 geo_n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float fe = 0.3;
	vec2 fuv = vec2((world_pos.x + world_pos.z) * 0.55, world_pos.y * 0.5);
	float f0 = value_noise(fuv);
	float fx = (value_noise(fuv + vec2(fe, 0.0)) - f0) / fe;
	float fy = (value_noise(fuv + vec2(0.0, fe)) - f0) / fe;
	vec3 bump = vec3(fx * 0.5, fy * 0.35, fx * 0.5);
	bump -= geo_n * dot(bump, geo_n);
	float blen = length(bump);
	bump *= 0.22 * (1.0 - exp(-blen / 0.22)) / max(blen, 0.0001);
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(bump, 0.0)).xyz);

	// Body stays see-through for race readability; rim + lip firm up so the
	// silhouette of the wall never dissolves against bright snow. Deep ice is
	// slightly more opaque: light does not make it through the thick base.
	ALPHA = clamp(base_alpha + depth * 0.10 + fresnel * rim_strength * 0.25 + lip * 0.22, 0.0, 1.0);
	// Deep body is wet-glassy; frost lip and strata scatter. Cracks scatter too.
	ROUGHNESS = mix(mix(0.10, 0.20, depth), 0.55, max(lip, max(strata, crack)));
	SPECULAR = 0.5;
	EMISSION = lip_tint.rgb * lip * lip_glow
			+ vec3(0.7, 0.85, 1.0) * fresnel * rim_strength * 0.08
			// Faint internal glow where the body is deepest and the view grazes:
			// scattered skylight finding its way through the wall. Scaled by the
			// body colour so it can never glow on a night course beyond what the
			// scene already put in.
			+ deep_col * (depth * fresnel * 0.10);
}
