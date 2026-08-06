// Water: 3-octave gerstner-style vertex displacement (vertical sine plus a
// choppy horizontal crest pinch) with analytic height-field normals, scrolling
// noise shading, Schlick fresnel reflectance toward the horizon, view-angle
// absorption gradient (red dies first with depth), view-distance deepening
// toward navy before fog takes over, and optional foam band via vertex color
// (paint COLOR.r toward 0.0 for foam — unset vertex color = no foam).
// Always-on realism terms (near-free math): backlit crest translucency (sun
// through thin wave tops transmits a green-teal glow against the light) and
// a wet shoreline rim (the half-wet band just outside painted foam darkens
// slightly, separating the foam line from open water).
// High-detail additions (gated by detail_level AND a snow-shader-style view
// distance fade, skipped entirely when either is 0): secondary fine ripple
// octave, animated whitecap lifecycle on crests (caps form, break and
// dissolve instead of gluing to wave phase), softened noise-broken foam
// edges, an anisotropic glitter-broken specular sun streak elongated toward
// the sun azimuth (the sun lane itself survives to the horizon; only its
// per-pixel glitter calms with distance), and finite-difference micro-facet
// tilt so each sparkle is a real facet catching the sun, not brightness
// noise. Mobile-cheap: no textures, no screen-space reads; up to 6 extra
// noise samples inside the distance-faded detail branch.
// WebGL2/gl_compatibility-safe: basic spatial features only, no screen or
// depth reads.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.08, 0.3, 0.5, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.3, 0.62, 0.78, 1.0);
uniform vec4 foam_color : source_color = vec4(0.96, 0.99, 1.0, 1.0);
uniform float alpha_value : hint_range(0.0, 1.0) = 0.9;
uniform float wave_height = 0.18;
uniform float wave_scale = 0.35;
uniform float wave_speed = 1.1;
// Gerstner pinch strength: how far verts crowd toward crests. 0 = pure
// vertical sines (old look). Keep below ~0.8 or steep waves self-intersect.
uniform float choppiness : hint_range(0.0, 1.0) = 0.4;
// Legacy shaping exponent for the deep->shallow color gradient (kept for
// existing callers); the reflectance term itself now uses Schlick.
uniform float fresnel_power = 3.0;
// Schlick F0: normal-incidence reflectance of water (~0.02 physically).
uniform float fresnel_f0 : hint_range(0.0, 0.1) = 0.02;
// How strongly the deep color absorbs toward a red-poor spectrum when looking
// down into the volume (0 = old flat deep color).
uniform float absorption : hint_range(0.0, 1.0) = 0.5;
uniform float crest_foam : hint_range(0.0, 1.0) = 0.25;
// Distance deepening: far water sinks toward a red-poor navy before fog wins,
// the way a cold sea darkens toward the horizon. 0 disables.
uniform float distance_deep : hint_range(0.0, 1.0) = 0.35;
// Micro-detail (ripple octave, foam lace, whitecap lifecycle) fades to zero
// across [detail_fade_start, detail_fade_end] metres of view distance — same
// pattern as the snow shader, wider band because water spans the horizon.
uniform float detail_fade_start = 30.0;
uniform float detail_fade_end = 120.0;
// 0 = base look (cheapest), 1 = full micro-detail. Set by VisualLibrary from
// the display quality preset (low=0, medium=0.5, high=1).
uniform float detail_level : hint_range(0.0, 1.0) = 1.0;
uniform vec3 sun_direction = vec3(-0.4, 0.55, -0.3);
uniform float sun_glint_strength : hint_range(0.0, 3.0) = 1.1;
uniform float sun_glint_power = 180.0;
// Anisotropy of the sun path: damps facet tilt along the sun azimuth so the
// glint lane stretches toward the sun instead of a round hotspot.
uniform float sun_streak : hint_range(0.0, 1.0) = 0.65;
uniform float foam_break_scale = 2.6;
// Backlit crest translucency: how strongly a low sun shining through raised
// crests toward the camera lifts a green-teal transmission glow — the glassy
// against-the-light band real cold seas show. 0 disables.
uniform float sss_strength : hint_range(0.0, 1.0) = 0.5;

varying vec3 world_pos;
varying float wave_h;      // -1..1 relative crest height
varying float foam_mask;   // 1 = foam (from vertex color)
varying float view_dist;   // view-space metres, drives detail distance fade

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
	float t = TIME * wave_speed;
	vec2 p = VERTEX.xz * wave_scale;
	// Three crossing gerstner-style octaves; analytic derivatives give the
	// normal free. Weights sum to 1 so wave_height stays the true amplitude
	// and existing course tuning is preserved.
	float ph1 = p.x * 1.7 + p.y * 0.8 + t;
	float ph2 = p.x * -0.9 + p.y * 2.3 + t * 1.37;
	float ph3 = p.x * 2.9 + p.y * -2.1 + t * 1.83;
	float c1 = cos(ph1);
	float c2 = cos(ph2);
	float c3 = cos(ph3);
	wave_h = sin(ph1) * 0.55 + sin(ph2) * 0.30 + sin(ph3) * 0.15;
	VERTEX.y += wave_h * wave_height;
	// Gerstner horizontal pinch: verts crowd toward crests, sharpening peaks
	// and widening troughs — the choppy profile pure sines cannot make.
	// Direction constants are the normalized octave wave vectors.
	vec2 pinch = vec2(0.9048, 0.4258) * (c1 * 0.55)
			+ vec2(-0.3644, 0.9312) * (c2 * 0.30)
			+ vec2(0.8100, -0.5865) * (c3 * 0.15);
	VERTEX.xz += pinch * wave_height * choppiness;
	float dx = c1 * 1.7 * 0.55 + c2 * -0.9 * 0.30 + c3 * 2.9 * 0.15;
	float dz = c1 * 0.8 * 0.55 + c2 * 2.3 * 0.30 + c3 * -2.1 * 0.15;
	// Crest steepening: the pinch compresses the surface near peaks, so the
	// effective slope (and thus shading contrast) rises there too.
	float k = wave_height * wave_scale * (1.0 + choppiness * max(wave_h, 0.0));
	NORMAL = normalize(vec3(-dx * k, 1.0, -dz * k));
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	view_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	foam_mask = 1.0 - COLOR.r;
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	// Schlick reflectance: near-zero looking straight down (see into the
	// volume), rising steeply only near grazing — real water, not the soft
	// omnidirectional sheen of the old plain power curve.
	float fresnel = clamp(fresnel_f0 + (1.0 - fresnel_f0) * pow(1.0 - facing, 5.0), 0.0, 1.0);
	// Legacy gentler curve kept for the color gradient so the horizon still
	// picks up shallow/sky tones over a usable angle range.
	float horizon_mix = pow(1.0 - facing, fresnel_power);

	// Detail distance fade (snow-shader pattern): micro-noise is only
	// resolvable near the camera; past detail_fade_end every fragment skips
	// the detail branch entirely — visual calm and a perf win in one.
	float dfade = 1.0 - smoothstep(detail_fade_start, detail_fade_end, view_dist);
	float dl = detail_level * dfade;

	// Shared world-space view/sun vectors (translucency + sun path).
	vec3 view_world = normalize(CAMERA_POSITION_WORLD - world_pos);
	vec3 sun = normalize(sun_direction);

	// Scrolling surface shimmer (fake normal-map shading).
	vec2 uv = world_pos.xz * 0.5 + vec2(TIME * 0.14, TIME * -0.09);
	float n = value_noise(uv) * 0.6 + value_noise(uv * 2.9 - TIME * 0.07) * 0.4;
	float ripple = 0.5;
	float ripple_raw = 0.5;
	vec2 ripple_uv = world_pos.xz * 3.4 + vec2(TIME * -0.21, TIME * 0.26);
	if (dl > 0.001) {
		// Secondary fine ripple octave: counter-scrolled so the surface keeps
		// texture up close instead of dissolving into flat color. Blends back
		// to its own mean (0.5) with distance so the sun lane stays stable.
		ripple_raw = value_noise(ripple_uv);
		ripple = mix(0.5, ripple_raw, dl);
		n = mix(n, n * 0.75 + ripple * 0.25, dl);
	}

	// Absorption gradient: looking down the view path plunges through more
	// water, so the deep end loses red first, then green — the classic
	// cold-ocean falloff instead of one flat deep color.
	vec3 deep_abs = deep_color.rgb * vec3(0.42, 0.66, 0.9);
	vec3 deep_grad = mix(deep_color.rgb, deep_abs, absorption * facing);
	vec3 water = mix(deep_grad, shallow_color.rgb, clamp(horizon_mix * 0.8 + n * 0.2, 0.0, 1.0));
	// Distance deepening: shallow teal near the camera sinking toward a
	// red-poor navy at range (applied before the grazing sky lift so the
	// horizon sheen still wins at the far edge).
	water = mix(water, deep_color.rgb * vec3(0.45, 0.6, 0.9),
			smoothstep(30.0, 380.0, view_dist) * distance_deep);
	// Grazing reflectance lifts the surface toward the pale sky tone.
	water = mix(water, shallow_color.rgb * 1.05, fresnel * 0.3);
	// Backlit crest translucency: looking toward a low sun through a raised
	// crest, thin water transmits instead of reflecting — a green-teal glow
	// band rides the crests facing away from the camera. Crest-height gated
	// (troughs stay opaque) and strongest near grazing where real SSS lives.
	float sun_through = pow(clamp(dot(-view_world, sun), 0.0, 1.0), 4.0);
	water += shallow_color.rgb * vec3(0.55, 1.0, 0.85)
			* (sun_through * clamp(wave_h, 0.0, 1.0) * sss_strength * 0.6);
	// Wet shoreline rim: the half-wet band just outside the painted foam edge
	// darkens slightly (soaked ice/shore under a thin film), visually seating
	// the foam line against open water. Vertex-color driven — meshes that
	// paint no foam pay only the two smoothsteps.
	float rim = smoothstep(0.04, 0.35, foam_mask) * (1.0 - smoothstep(0.35, 0.9, foam_mask));
	water *= 1.0 - rim * 0.16;
	float crest = smoothstep(1.0 - crest_foam, 1.0, wave_h * 0.5 + 0.5) * n;
	if (dl > 0.001) {
		// Whitecap lifecycle: two independently drifting noise fields gate the
		// crest foam, so caps form, break apart and dissolve over time instead
		// of riding every crest as a permanent painted stripe.
		float cap_a = value_noise(world_pos.xz * 1.4 + vec2(TIME * 0.06, TIME * -0.04));
		float cap_b = value_noise(world_pos.xz * 1.4 + vec2(31.7 - TIME * 0.05, 8.2 + TIME * 0.08));
		crest *= mix(1.0, smoothstep(0.22, 0.68, cap_a * cap_b * 1.9), dl * 0.85);
	}
	float foam = clamp(foam_mask + crest, 0.0, 1.0);
	if (dl > 0.001) {
		// Break the foam band edge with noise: lacy fringe instead of a solid
		// stripe, with slight interior density variation. Wider smoothstep
		// band than before = softer dissolve at the fringe.
		float ftex = value_noise(world_pos.xz * foam_break_scale + vec2(TIME * 0.11, TIME * -0.07));
		float broken = smoothstep(0.12, 0.9, foam + (ftex - 0.5) * 0.8);
		foam = mix(foam, broken * (0.75 + 0.25 * ftex), dl);
	}
	// Foam softening: hermite-shape the mask (gentle toe and shoulder) and cap
	// the mix below 1 so foam keeps a faint water tint instead of paper-white.
	foam = clamp(foam, 0.0, 1.0);
	foam = foam * foam * (3.0 - 2.0 * foam);
	ALBEDO = mix(water, foam_color.rgb, foam * 0.92);
	ROUGHNESS = mix(0.06, 0.55, foam);
	SPECULAR = 0.7;

	if (detail_level > 0.001) {
		// Sharp specular sun path: mirror-reflection glint off the analytic
		// wave normal, broken up by the fine ripple into a glittering lane.
		// Anisotropic streak: damping the normal's tilt along the sun azimuth
		// forgives along-path deviation, so glints survive in a long lane
		// stretched toward the sun while cross-path tilts still kill them —
		// the elongated sun path real water shows, not a round hotspot.
		// Gated on detail_level (not dl): the lane must run to the horizon;
		// ripple already relaxes to 0.5 there so the far lane renders calm.
		vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		if (dl > 0.001) {
			// Micro-facet tilt: finite-difference the fine ripple field so the
			// lane's glitter comes from real normal jitter — each sparkle is a
			// facet momentarily catching the sun — instead of brightness noise
			// alone. Near-field only (dl), so the far lane stays a calm streak.
			float rx = value_noise(ripple_uv + vec2(0.3, 0.0));
			float rz = value_noise(ripple_uv + vec2(0.0, 0.3));
			n_world = normalize(n_world
					+ vec3(ripple_raw - rx, 0.0, ripple_raw - rz) * (0.35 * dl));
		}
		vec2 az = normalize(sun.xz + vec2(1e-4, 0.0));
		vec3 along = vec3(az.x, 0.0, az.y);
		vec3 n_streak = normalize(n_world - along * dot(n_world, along) * sun_streak);
		float glint = pow(clamp(dot(reflect(-sun, n_streak), view_world), 0.0, 1.0), sun_glint_power);
		// Schlick gain: the lane brightens toward grazing angles like a real
		// reflection instead of holding constant intensity.
		float graze_gain = 0.45 + 0.55 * clamp(fresnel * 6.0, 0.0, 1.0);
		EMISSION = vec3(1.0, 0.98, 0.9) * glint * sun_glint_strength * graze_gain
				* (0.35 + 0.65 * ripple) * (1.0 - foam) * detail_level;
	}

	ALPHA = clamp(alpha_value + foam * 0.1 + fresnel * 0.08, 0.0, 1.0);
}
