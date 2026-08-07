// Rock / cliff / massif surface. The problem it solves: a procedural ice course
// is white geometry under a white key light, and a StandardMaterial3D with one
// albedo and one roughness gives every face of a 200 m massif the same value.
// Flat albedo + flat roughness is exactly what reads as "untextured grey paper
// cutout", and at the horizon it merges into the sky as one pale mass.
//
// Four cheap terms fix that, all uniform-gated so a call site pays only for the
// ones it turns on:
//   1. STRATA   - long-wavelength world-Y banding (sedimentary/compression
//      layers). Driven by WORLD height, not UV or local height, so a MultiMesh
//      of slabs stretched to different heights keeps a consistent band scale
//      instead of smearing its baked bands into ribbons.
//   2. FACE SHADE - vertical faces read darker than up-facing ones. This is the
//      single biggest value-structure win: it separates wall from ledge even
//      when the sun is behind the form.
//   3. SNOW CATCH - up-facing faces above a slope threshold gain snow. Real
//      alpine value structure is "white on top, dark on the wall".
//   4. AERIAL PERSPECTIVE - view-distance desaturation toward a haze colour
//      that is deliberately DARKER than the sky. Engine fog alone drives far
//      geometry toward the sky value, which is what made the horizon dissolve;
//      this ramp is independent of fog so the track can stay clear while the
//      far field still recedes and stays readable as silhouette.
//
// Cost: no textures, no loops, no screen/depth reads, three sin() and a handful
// of mixes on the branch that is enabled. Safe on gl_compatibility / WebGL2
// through ANGLE.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.92;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform float specular_value : hint_range(0.0, 1.0) = 0.3;

// --- Internal value structure (0 = off, skips the whole branch) --------------
uniform float structure : hint_range(0.0, 1.0) = 0.0;
// Band amplitude and cycles per metre of world Y. 0.16 => ~6 m primary layers,
// which reads as strata on a 20 m cliff and on a 200 m massif alike.
uniform float strata_strength : hint_range(0.0, 1.0) = 0.35;
uniform float strata_scale = 0.16;
// Colour the dark half of a band leans toward (shadowed compressed ice).
uniform vec4 strata_tint : source_color = vec4(0.58, 0.72, 0.9, 1.0);
// How much darker a dead-vertical face is than a dead-flat one.
uniform float face_shade : hint_range(0.0, 1.0) = 0.34;
// Snow held on up-facing faces.
uniform float snow_catch : hint_range(0.0, 1.0) = 0.55;
uniform vec4 snow_tint : source_color = vec4(0.97, 0.98, 1.0, 1.0);

// --- Aerial perspective (0 = off) -------------------------------------------
uniform float haze_strength : hint_range(0.0, 1.0) = 0.0;
uniform float haze_start = 90.0;
uniform float haze_end = 800.0;
// Deliberately below sky value: distant terrain must recede WITHOUT climbing to
// the sky's brightness, or the horizon reads as one undifferentiated mass.
uniform vec4 haze_color : source_color = vec4(0.30, 0.42, 0.60, 1.0);
uniform float haze_desat : hint_range(0.0, 1.0) = 0.55;

varying vec3 world_pos;
varying float view_dist;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	view_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	// World normal from the view-space NORMAL: correct under the non-uniform
	// instance scales the cliff slabs use, where transforming the model-space
	// normal by MODEL_MATRIX would not be.
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float up = clamp(n.y, 0.0, 1.0);
	vec3 albedo = tint.rgb * COLOR.rgb;
	float rough = roughness_value;

	if (structure > 0.001) {
		// Two vertical octaves plus a slow lateral drift, so layers undulate
		// across a face instead of ringing it at one dead height.
		float y = world_pos.y * strata_scale * 6.2831853;
		float band = sin(y) * 0.62
				+ sin(y * 2.7 + 1.7) * 0.26
				+ sin((world_pos.x + world_pos.z) * 0.05 + y * 0.31) * 0.2;
		// Bands belong on walls; a flat snow table has no exposed section.
		float wall = 1.0 - up;
		float amt = strata_strength * structure * wall;
		albedo *= 1.0 + band * 0.22 * amt;
		albedo = mix(albedo, albedo * strata_tint.rgb, clamp(-band, 0.0, 1.0) * amt * 0.7);
		rough = clamp(rough + band * 0.14 * amt, 0.05, 1.0);

		// Vertical faces darker than horizontal ones: the cheapest real form
		// modelling there is, and it survives any sun angle.
		albedo *= mix(1.0 - face_shade * structure, 1.0, up);

		// Snow only sticks where the slope allows it to.
		float caught = smoothstep(0.42, 0.86, up) * snow_catch * structure;
		albedo = mix(albedo, snow_tint.rgb * (1.0 + band * 0.05), caught);
		rough = mix(rough, 0.88, caught);
	}

	if (haze_strength > 0.001) {
		float haze = smoothstep(haze_start, haze_end, view_dist) * haze_strength;
		float lum = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
		// Desaturate first (distance eats chroma), then settle onto the haze
		// tone. Two mixes, no branch.
		albedo = mix(albedo, vec3(lum), haze * haze_desat);
		albedo = mix(albedo, haze_color.rgb, haze);
		rough = mix(rough, 0.9, haze * 0.6);
	}

	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = metallic_value;
	SPECULAR = specular_value;
}
