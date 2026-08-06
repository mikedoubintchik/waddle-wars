// Aurora ribbon: unshaded additive curtain built from THREE independently
// drifting filament layers (coarse folds, a finer counter-scrolled layer,
// and a finest slow gauze sheet — three drift rates make the interior
// parallax like stacked fabric) with altitude color banding — green hem,
// teal mid, violet crown, plus a thin magenta nitrogen fringe on the bottom
// edge, faint horizontal emission strata, and a slow hue drift. The lower
// hem billows on its own noise clock instead of ending in a straight line.
// Soft alpha edges all around. Map onto any ribbon/plane mesh: UV.x runs
// along the ribbon, UV.y down it (UV.y = 0 at the top edge). High-detail
// additions (gated by detail_level, skipped entirely at 0): fine vertical
// ray striations inside the curtain folds, per-filament vertical shimmer
// (each ray breathes on its own clock), a brighter core band partway down,
// and gentle per-height horizontal drift so the curtain sways instead of
// sliding. Mobile-cheap: 4 noise octaves base + 2 extra samples inside the
// uniform detail branch, no textures.
shader_type spatial;
// fog_disabled: distance fog must never gray the curtains out — ribbons sit
// 300-700m away, where even thin haze desaturates additive color to a flat
// gray-blue smudge. Additive blend: the curtain only ever adds light.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled;

uniform vec4 color_green : source_color = vec4(0.2, 1.0, 0.5, 1.0);
uniform vec4 color_cyan : source_color = vec4(0.25, 0.85, 1.0, 1.0);
uniform vec4 color_violet : source_color = vec4(0.62, 0.4, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 4.0) = 1.3;
uniform float scroll_speed = 0.05;
uniform float hue_speed = 0.1;
uniform float band_scale = 3.0;
uniform float curtain_frequency = 26.0;
// Subtler default coverage: real aurora reads as translucent gauze, not a
// solid painted sheet — courses that want a hero curtain override this.
uniform float max_alpha : hint_range(0.0, 1.0) = 0.45;
// 0 = base look (cheapest), 1 = full micro-detail. Set by VisualLibrary from
// the display quality preset (low=0, medium=0.5, high=1).
uniform float detail_level : hint_range(0.0, 1.0) = 1.0;
uniform float ray_frequency = 90.0;
uniform float ray_strength : hint_range(0.0, 1.0) = 0.7;
// Per-filament brightness shimmer: rays flicker on independent clocks like
// real precipitation pulses walking along the curtain. 0 disables.
uniform float shimmer_strength : hint_range(0.0, 1.0) = 0.55;
uniform float core_position : hint_range(0.0, 1.0) = 0.42;
uniform float core_width : hint_range(0.05, 1.0) = 0.3;
uniform float core_boost : hint_range(0.0, 2.0) = 0.8;
uniform float drift_variation : hint_range(0.0, 1.0) = 0.6;

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

void fragment() {
	float ux = UV.x;
	float rays = 1.0;
	float shimmer = 1.0;
	float core = 0.0;
	if (detail_level > 0.001) {
		// Gentle horizontal drift that varies with height: the curtain sways
		// like fabric instead of sliding as one rigid sheet.
		ux += (value_noise(vec2(UV.y * 1.7, TIME * 0.05)) - 0.5)
				* 0.08 * drift_variation * detail_level;
	}

	// Layer 1: slow-drifting coarse brightness bands along the ribbon.
	float n = value_noise(vec2(ux * band_scale + TIME * scroll_speed, TIME * 0.04));
	float band = smoothstep(0.25, 0.85, n);
	// Layer 2: finer filaments counter-scrolling at their own speed, so the
	// curtain interior visibly shears instead of translating as one sheet.
	float n2 = value_noise(vec2(ux * band_scale * 2.35 - TIME * scroll_speed * 1.6,
			7.31 + TIME * 0.026));
	float band2 = smoothstep(0.3, 0.9, n2);
	// Layer 3: finest gauze sheet creeping WITH the flow at roughly half
	// speed — a third independent drift rate, so the interior parallaxes
	// like stacked translucent fabric instead of two rigid sheets.
	float n3 = value_noise(vec2(ux * band_scale * 4.3 + TIME * scroll_speed * 0.55,
			13.9 - TIME * 0.017));
	float band3 = smoothstep(0.35, 0.95, n3);
	// Fold combs at two frequencies, each phase-warped by its own layer's
	// noise: interference between them folds the fabric irregularly.
	float curtain = 0.6 + 0.4 * sin(ux * curtain_frequency + n * 7.0 + TIME * 0.6);
	curtain *= 0.75 + 0.25 * sin(ux * curtain_frequency * 0.53 - n2 * 5.0 - TIME * 0.37);

	if (detail_level > 0.001) {
		// Vertical ray striations inside each curtain fold: fine sin comb with
		// noise-jittered phase so rays cluster and break naturally. pow-shaped
		// comb sharpens each ray into a distinct vertical filament (bright
		// spine, wide dim gap) instead of a soft sine wash.
		float rn = value_noise(vec2(ux * ray_frequency * 0.12, UV.y * 0.9 - TIME * 0.07));
		float rs = 0.5 + 0.5 * sin(ux * ray_frequency + rn * 9.0);
		rs = rs * rs * rs;
		rays = mix(1.0, 0.4 + 0.75 * rs + 0.25 * rn, ray_strength * detail_level);
		// Vertical ray shimmer: rn doubles as a per-filament phase seed, so
		// neighbouring rays breathe out of step and a faint brightness pulse
		// appears to run down the curtain (UV.y term tilts the phase).
		shimmer = mix(1.0,
				1.0 - shimmer_strength * (0.22 + 0.2 * sin(TIME * 1.6 + rn * 12.6 + UV.y * 2.4)),
				detail_level);
		// Brighter core band partway down the curtain (gaussian falloff).
		float dc = (UV.y - core_position) / max(core_width, 0.05);
		core = exp(-dc * dc * 3.0) * core_boost * detail_level;
	}

	// Ragged billowing hem: warp the vertical coordinate with slow noise so
	// the lower edge undulates instead of cutting off on a straight line —
	// the bottom border of a real curtain billows as the sheet drifts. Top
	// edge (UV.y = 0) is untouched by construction.
	float hem = (value_noise(vec2(ux * 2.2 + TIME * 0.03, 4.7)) - 0.5) * 0.16;
	float vy = clamp(UV.y * (1.0 + hem), 0.0, 1.0);
	// Soft fade at top and bottom edges, plus soft ends.
	float edge_v = sin(vy * 3.14159265);
	float edge_h = sin(clamp(UV.x, 0.0, 1.0) * 3.14159265);
	float fade = edge_v * edge_v * clamp(edge_h * 2.2, 0.0, 1.0);

	// Altitude color banding, the way real emission stratifies: oxygen green
	// at the bright lower hem, teal through the middle, violet at the crown.
	// The slow hue drift now modulates the green->teal transition width, so
	// bands migrate over minutes instead of the whole sheet cycling hue.
	float m = 0.5 + 0.5 * sin(TIME * hue_speed + ux * 2.4);
	float alt = clamp(1.0 - UV.y, 0.0, 1.0);  // 1 at the curtain top
	vec3 col = mix(color_green.rgb, color_cyan.rgb,
			smoothstep(0.12, 0.62, alt) * (0.5 + 0.5 * m));
	col = mix(col, color_violet.rgb, smoothstep(0.52, 0.95, alt) * 0.8);
	// Thin nitrogen fringe: a faint magenta hem right at the bottom edge
	// (follows the billowed hem coordinate so the fringe rides the wobble).
	col = mix(col, color_violet.rgb * vec3(1.0, 0.62, 0.95),
			smoothstep(0.86, 1.0, vy) * 0.35);
	// Faint horizontal emission strata: real curtains stack in thin altitude
	// shelves, not one smooth ramp. Phase-warped by the coarse layer so the
	// shelves tilt with the folds instead of ruling straight lines.
	col *= 0.94 + 0.06 * sin(alt * 17.0 + n * 3.5 - TIME * 0.11);

	// Brightness lives in ALBEDO (additive HDR), coverage in ALPHA. The old
	// form multiplied band*curtain into BOTH, so the added light fell off
	// quadratically and typical pixels sat ~0.1 HDR: flat dim smudges. Now the
	// color keeps a lit floor across the curtain and the core band multiplies
	// it up to ~3.4x, pushing the curtain heart past the glow HDR threshold
	// (~1.05) so it visibly blooms against the twilight sky.
	float energy = (band * 0.6 + band2 * 0.36 + band3 * 0.2) * curtain * rays * shimmer;
	float core_gain = 1.0 + core * 3.0;
	ALBEDO = col * intensity * (0.3 + 1.05 * energy) * core_gain;
	// Coverage follows the ray filaments too (0.85 + 0.15 * rays): the curtain
	// thins between rays so vertical structure survives into the silhouette,
	// and a lower floor (0.28) keeps the sheet gauzy instead of solid. All
	// three band layers feed coverage so every filament sheet shapes the edge.
	ALPHA = clamp(max_alpha * fade
			* (0.28 + 0.65 * clamp(band * 0.7 + band2 * 0.4 + band3 * 0.22, 0.0, 1.0) * curtain)
			* (0.85 + 0.15 * rays) * (1.0 + core * 0.5), 0.0, 1.0);
}
