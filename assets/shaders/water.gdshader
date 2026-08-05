// Water: 2-octave sine vertex displacement with analytic normals, scrolling
// noise shading, Schlick fresnel reflectance toward the horizon, view-angle
// absorption gradient (red dies first with depth), optional foam band via
// vertex color (paint COLOR.r toward 0.0 for foam — unset vertex color = no
// foam). High-detail additions (gated by detail_level, skipped entirely at 0):
// secondary fine ripple octave, softened noise-broken foam edges, and an
// anisotropic glitter-broken specular sun streak elongated toward the sun
// azimuth. Mobile-cheap: no textures, no screen-space reads; 2 extra noise
// samples inside the uniform detail branch. WebGL2/gl_compatibility-safe:
// basic spatial features only, no screen or depth reads.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.08, 0.3, 0.5, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.3, 0.62, 0.78, 1.0);
uniform vec4 foam_color : source_color = vec4(0.96, 0.99, 1.0, 1.0);
uniform float alpha_value : hint_range(0.0, 1.0) = 0.9;
uniform float wave_height = 0.18;
uniform float wave_scale = 0.35;
uniform float wave_speed = 1.1;
// Legacy shaping exponent for the deep->shallow color gradient (kept for
// existing callers); the reflectance term itself now uses Schlick.
uniform float fresnel_power = 3.0;
// Schlick F0: normal-incidence reflectance of water (~0.02 physically).
uniform float fresnel_f0 : hint_range(0.0, 0.1) = 0.02;
// How strongly the deep color absorbs toward a red-poor spectrum when looking
// down into the volume (0 = old flat deep color).
uniform float absorption : hint_range(0.0, 1.0) = 0.5;
uniform float crest_foam : hint_range(0.0, 1.0) = 0.25;
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

varying vec3 world_pos;
varying float wave_h;      // -1..1 relative crest height
varying float foam_mask;   // 1 = foam (from vertex color)

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
	// Two crossing sine octaves; analytic derivatives give the normal free.
	float w1 = sin(p.x * 1.7 + p.y * 0.8 + t);
	float w2 = sin(p.x * -0.9 + p.y * 2.3 + t * 1.37);
	wave_h = w1 * 0.65 + w2 * 0.35;
	VERTEX.y += wave_h * wave_height;
	float d1x = cos(p.x * 1.7 + p.y * 0.8 + t) * 1.7 * 0.65;
	float d1z = cos(p.x * 1.7 + p.y * 0.8 + t) * 0.8 * 0.65;
	float d2x = cos(p.x * -0.9 + p.y * 2.3 + t * 1.37) * -0.9 * 0.35;
	float d2z = cos(p.x * -0.9 + p.y * 2.3 + t * 1.37) * 2.3 * 0.35;
	float k = wave_height * wave_scale;
	NORMAL = normalize(vec3(-(d1x + d2x) * k, 1.0, -(d1z + d2z) * k));
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
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

	// Scrolling surface shimmer (fake normal-map shading).
	vec2 uv = world_pos.xz * 0.5 + vec2(TIME * 0.14, TIME * -0.09);
	float n = value_noise(uv) * 0.6 + value_noise(uv * 2.9 - TIME * 0.07) * 0.4;
	float ripple = 0.5;
	if (detail_level > 0.001) {
		// Secondary fine ripple octave: counter-scrolled so the surface keeps
		// texture up close instead of dissolving into flat color.
		ripple = value_noise(world_pos.xz * 3.4 + vec2(TIME * -0.21, TIME * 0.26));
		n = mix(n, n * 0.75 + ripple * 0.25, detail_level);
	}

	// Absorption gradient: looking down the view path plunges through more
	// water, so the deep end loses red first, then green — the classic
	// cold-ocean falloff instead of one flat deep color.
	vec3 deep_abs = deep_color.rgb * vec3(0.42, 0.66, 0.9);
	vec3 deep_grad = mix(deep_color.rgb, deep_abs, absorption * facing);
	vec3 water = mix(deep_grad, shallow_color.rgb, clamp(horizon_mix * 0.8 + n * 0.2, 0.0, 1.0));
	// Grazing reflectance lifts the surface toward the pale sky tone.
	water = mix(water, shallow_color.rgb * 1.05, fresnel * 0.3);
	float crest = smoothstep(1.0 - crest_foam, 1.0, wave_h * 0.5 + 0.5) * n;
	float foam = clamp(foam_mask + crest, 0.0, 1.0);
	if (detail_level > 0.001) {
		// Break the foam band edge with noise: lacy fringe instead of a solid
		// stripe, with slight interior density variation. Wider smoothstep
		// band than before = softer dissolve at the fringe.
		float ftex = value_noise(world_pos.xz * foam_break_scale + vec2(TIME * 0.11, TIME * -0.07));
		float broken = smoothstep(0.12, 0.9, foam + (ftex - 0.5) * 0.8);
		foam = mix(foam, broken * (0.75 + 0.25 * ftex), detail_level);
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
		vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 view_world = normalize(CAMERA_POSITION_WORLD - world_pos);
		vec3 sun = normalize(sun_direction);
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
