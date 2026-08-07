shader_type spatial;

// Penguin plumage. ONE compiled program covers every racer: the species
// palette, baked countershading, mantle break and markings all live in the
// mesh vertex colors, and the solid sub-meshes (tail wedge, shoulder mounds,
// brow ridges, crest quills) reuse this same program with `tint` set and
// COLOR left white, so they batch with the body and inherit the identical
// form/rim treatment instead of reading as flat patches welded onto it.
//
// The problem this shader exists to solve: at the 8-30 m the game is actually
// played at, an unhelped penguin is a featureless dark egg -- one value
// against white snow, one value against a night sky. Everything below is
// aimed at internal contrast and edge definition that SURVIVES that distance,
// rather than close-up detail that only pays off in the dressing room.
//
//  1. FORM. A world-space up/down term from the normal multiplies the baked
//     color: sky-facing plumage lifts, ground-facing plumage sinks. It is
//     multiplicative and roughly mean-preserving, so the body does not go
//     gray -- the tonal RANGE across it widens, which is what turns a flat
//     egg into a rounded, weighted mass.
//  2. EDGE, in two opposite polarities, because no single polarity works on
//     both courses. An INK line loses value in the outermost sliver (the only
//     edge cue that reads against bright snow -- an additive rim is invisible
//     on white) and a broader emissive RIM sits just inside it (the only cue
//     that reads against a near-black sky). Together they read as an outlined
//     lit edge on any background. The rim is deliberately BROADENED and
//     strengthened with distance: a 1-pixel rim is nothing on a racer that is
//     30 px tall.
//  3. FEATHER STRUCTURE at two scales: fine barb striations (inside ~15 m)
//     and broad overlapping tracts big enough to survive to ~40 m.
//  4. SHEEN. Feathers are not matte plastic. A broad grazing streak rides the
//     sky-facing dorsal -- a cheap stand-in for the anisotropic sweep along a
//     bird's back -- plus roughness tightening toward the back so the sun
//     lays a real specular there, plus the green-blue-violet structural
//     iridescence of real penguin plumage at grazing angles.
//  5. IDENTITY. `ident` tints the rim per racer, so eight racers stop reading
//     as eight identical dark eggs and you can tell who just shoved you.
//
// WebGL2 / gl_compatibility-safe: pure closed-form math on COLOR / NORMAL /
// VIEW / VERTEX. No screen-space reads, no depth texture, no compute, no
// derivative tricks. Detail is object-space so nothing swims when the body
// animates.

// Deliberately NOT ": source_color". That hint applies an sRGB->linear decode,
// but mesh vertex colors are handed to the shader raw. Tagging it would put
// the solid parts roughly a stop and a half below the body they are welded to
// -- which is exactly what made the shoulder mounds read as dark lumps and the
// tail as a black hole back when they used StandardMaterial3D.albedo_color
// (which does decode). Raw keeps every plumage part in one color space.
uniform vec4 tint = vec4(1.0, 1.0, 1.0, 1.0);
// Per-racer identity color. Mixed into the rim light by ident_amt, so each
// racer's silhouette carries its own hue without repainting the plumage.
uniform vec4 ident = vec4(0.64, 0.79, 1.0, 1.0);
uniform float ident_amt : hint_range(0.0, 1.0) = 0.45;
// Scales BOTH edge treatments (ink line and rim) together. Small flat props
// welded onto the body -- the tail wedge above all -- are nearly all grazing
// angle, so at full strength they outline THEMSELVES and read as separate
// objects stuck to the back rather than as part of it. They get a low
// edge_gain; the body and the parts that actually own silhouette keep 1.0.
uniform float edge_gain : hint_range(0.0, 3.0) = 1.0;
// Distance contrast hold. Bright sun plus the ACES shoulder compresses the
// head/mantle break exactly where it matters most: near the racer there is
// plenty of screen area to read detail from, and past ~20 m the body converges
// to one cool grey and identity falls back on whatever hat is on top. This
// expands local contrast about a fixed pivot as distance rises, so the break
// that carries the whole silhouette survives to the range it is needed at.
uniform float contrast_far : hint_range(1.0, 1.8) = 1.26;
// Value the expansion pivots around -- between the near-black head and the
// pale mantle, so one goes down and the other goes up rather than both sliding.
uniform float contrast_pivot : hint_range(0.0, 1.0) = 0.34;
// How far the body itself takes the racer's identity colour once feather
// detail has stopped resolving. Identity has to migrate from texture to hue as
// range increases, or eight racers converge on the same grey again.
uniform float ident_body : hint_range(0.0, 1.0) = 0.26;

varying vec3 v_obj;

void vertex() {
	v_obj = VERTEX;
}

void fragment() {
	float dist = length(VERTEX);                       // view-space depth
	float near_k = 1.0 - smoothstep(5.0, 15.0, dist);  // barb scale
	float mid_k = 1.0 - smoothstep(16.0, 40.0, dist);  // feather-tract scale
	float far_k = smoothstep(3.0, 18.0, dist);         // edge-treatment ramp

	vec3 base = COLOR.rgb * tint.rgb;
	// Hold the head/mantle break open with distance, on the ALBEDO.
	//
	// The first attempt expanded the LIT colour, which on a sunlit course sits
	// almost entirely above the pivot -- so it pushed nearly every fragment up
	// and washed the racer out instead of separating it. The break is a
	// property of the plumage, not of the lighting, so the expansion belongs
	// here, before the light touches it: head albedo goes down, mantle albedo
	// goes up, and every mask derived from lum below inherits the wider gap.
	base = clamp(mix(vec3(contrast_pivot), base, mix(1.0, contrast_far, far_k)),
		vec3(0.0), vec3(1.0));
	float lum = dot(base, vec3(0.299, 0.587, 0.114));
	// 1 on the dark head/rump feathers, fading off across the pale mantle and
	// gone on the white belly.
	float dark_m = 1.0 - smoothstep(0.22, 0.66, lum);
	// Rim mask: everything that is not near-white takes an edge light, so the
	// orange feet and bill zones separate too; only the bright belly opts out.
	float rim_m = 1.0 - smoothstep(0.62, 0.95, lum);
	// Feather structure must NOT be masked by dark_m. The pale mantle is the
	// largest single area on screen and the one the eye lands on; leaving it
	// untextured is what made the back read as glazed ceramic. Only the white
	// belly opts out.
	float feather_m = 1.0 - smoothstep(0.58, 0.90, lum);

	// --- feather structure, two scales -------------------------------------
	float barbs = sin(v_obj.x * 340.0 + v_obj.y * 110.0) * sin(v_obj.z * 300.0 - v_obj.y * 70.0);
	float rows = sin(v_obj.y * 96.0 + sin(v_obj.x * 34.0 + v_obj.z * 27.0) * 2.2);
	float grain = (barbs * 0.55 + rows * 0.45) * near_k;
	float tract = sin(v_obj.y * 27.0 + sin(v_obj.x * 8.0 + v_obj.z * 7.0) * 1.8)
		* (0.55 + 0.45 * sin(v_obj.x * 14.0 - v_obj.z * 11.0));
	float group = tract * mid_k;

	// --- form: hemispheric countershading ----------------------------------
	// World "up" component of the (view-space) fragment normal, for one dot
	// product and no extra varying: the second row of the inverse-view
	// rotation IS world up expressed in view space.
	// NOTE: do NOT reach for MODEL_NORMAL_MATRIX in vertex() here -- it is not
	// emitted in every gl_compatibility vertex specialization, and the aurora
	// course's additive light passes then fail to link ("input of fragment
	// shader not written by vertex shader"), dropping every racer to an
	// unshaded black silhouette.
	vec3 world_up = vec3(INV_VIEW_MATRIX[0][1], INV_VIEW_MATRIX[1][1], INV_VIEW_MATRIX[2][1]);
	float up = clamp(dot(NORMAL, world_up) * 0.5 + 0.5, 0.0, 1.0);
	float shade = up * up * (3.0 - 2.0 * up);
	// Bright surfaces (white belly, orange feet and bill zones) take the
	// downward darkening for grounding but only a muted upward lift -- pushed
	// the full amount they wash out toward paper white instead of reading as
	// saturated feet against snow.
	float form = mix(0.42, mix(1.12, 1.46, dark_m), shade);
	vec3 col = base * (form + (grain * 0.075 + group * 0.095) * feather_m);
	col += vec3(0.09, 0.13, 0.22) * (shade * shade * shade * 0.18) * dark_m;

	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float graze = 1.0 - ndv;

	// --- ink line ----------------------------------------------------------
	// The outermost sliver of every surface loses value. Against the bright
	// glacier this is the ONLY edge cue that works, and against the aurora
	// night it hides harmlessly inside an already dark silhouette. It also
	// gives the emissive rim below something to sit against, so the two read
	// as "outlined, lit edge" instead of cancelling into mush.
	// Kept tight and light on purpose. A thin object (the flipper blades) is
	// ALL grazing angle, so a wide or heavy ink band does not outline them --
	// it paints them out, and the racer sprouts two black wires.
	float ink = smoothstep(0.87, 1.0, graze) * mix(0.55, 1.0, far_k) * edge_gain;
	col *= 1.0 - ink * 0.26;

	// --- rim / edge light, distance-adaptive --------------------------------
	// Emissive (so it survives any light direction, including the aurora
	// course's near-black key), weighted to the upper silhouette so it reads
	// as sky light spilling over the back rather than a sticker outline, and
	// suppressed under the ink line so the edge stays defined.
	float rim = pow(graze, mix(3.4, 1.7, far_k)) * (1.0 - ink * 0.8);
	float rim_w = mix(0.80, 1.35, far_k) * (0.40 + 0.60 * up) * edge_gain;
	vec3 rim_col = mix(vec3(0.64, 0.79, 1.0), ident.rgb, ident_amt);

	// --- dorsal sheen -------------------------------------------------------
	// A broad grazing streak riding the sky-facing back. Real plumage throws a
	// directional sweep along the spine; a matte lambert body is the single
	// loudest "untextured primitive" tell left on a racer.
	float sheen = pow(up, 6.0) * pow(graze, 1.5);

	// --- structural iridescence ---------------------------------------------
	float fres = pow(graze, 3.0);
	vec3 irid = vec3(
		0.30 + 0.30 * sin(fres * 9.0 + 1.8),
		0.50 + 0.30 * sin(fres * 9.0 + 3.6),
		0.70 + 0.25 * sin(fres * 9.0 + 5.2));

	// --- distance identity hold ---------------------------------------------
	// Both of these are no-ops up close (far_k is 0) and ramp in with range.
	float body_lum = dot(col, vec3(0.299, 0.587, 0.114));
	// Re-tint toward the racer's colour at constant luminance, so the hue
	// carries identity without disturbing the value structure above.
	float ident_lum = max(dot(ident.rgb, vec3(0.299, 0.587, 0.114)), 0.05);
	vec3 id_col = ident.rgb * (body_lum / ident_lum);
	col = mix(col, id_col, far_k * ident_body * rim_m);
	ALBEDO = clamp(col, vec3(0.0), vec3(1.0));
	// Rim + sheen + a tiny light-independent skylight floor on the sky-facing
	// dorsal. The floor exists for the aurora course: with only a dim night
	// key, an albedo-0.1 back renders as literal black no matter how good the
	// albedo gradient is, so the form has to be carried by something that does
	// not go through the light loop. It is far below the direct sun on
	// glacier, where it changes nothing.
	// The skylight floor is scaled by the fragment's OWN base luminance rather
	// than applied flat. On the aurora course the key light is so dim that this
	// term is most of what you actually see on a racer, and a flat floor there
	// paints the carefully built head/mantle/rump break back out again — every
	// racer returns to being one even mass, which is the exact bug this whole
	// pass exists to kill. Proportional, it behaves like real ambient (sky
	// times albedo) and the value break survives into the dark course.
	float floor_k = clamp(lum * 4.5, 0.20, 1.8);
	EMISSION = rim_col * (rim * rim_w * rim_m)
		+ vec3(0.30, 0.42, 0.62) * (0.135 * shade * dark_m * floor_k)
		+ vec3(0.82, 0.88, 1.0) * (sheen * 0.22 * feather_m)
		+ irid * (dark_m * 0.09 * fres);
	// Dorsal feathers carry a satin sheen that tightens toward the sky-facing
	// back, where the sun lays its highlight; the belly stays matte.
	ROUGHNESS = mix(0.74, mix(0.70, 0.48, shade) + grain * 0.10, feather_m);
	SPECULAR = mix(0.34, 0.44, dark_m);
}
