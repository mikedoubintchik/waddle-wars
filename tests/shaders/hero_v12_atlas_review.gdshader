shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// QA-only: unique-UV atlas. Does not replace the live PenguinVisual material.
// Albedo is already pigmented, sRGB encoded, with no stage lighting baked in.
// ORM and masks are linear data. Masks contain mutually exclusive coverage:
// R=ivory, G=gold, B=identity cyan; A=feather (hard parts/eyes have A=0).
// No COLOR dependency: Blender/Godot vertex-color import is not this contract.
uniform sampler2D atlas_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D atlas_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D atlas_orm : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D atlas_masks : filter_linear_mipmap_anisotropic, repeat_disable;

// Explicit LINEAR pigment values from source M, not display-space hex colors.
// Identical default palettes give an exact ratio of one, preserving the bake.
uniform vec3 reference_dorsal_linear = vec3(0.017, 0.027, 0.040);
uniform vec3 reference_ventral_linear = vec3(0.760, 0.665, 0.490);
uniform vec3 reference_patch_linear = vec3(0.630, 0.270, 0.037);
uniform vec3 reference_identity_linear = vec3(0.065, 0.340, 0.380);
instance uniform vec3 dorsal_linear = vec3(0.017, 0.027, 0.040);
instance uniform vec3 ventral_linear = vec3(0.760, 0.665, 0.490);
instance uniform vec3 patch_linear = vec3(0.630, 0.270, 0.037);
instance uniform vec3 identity_linear = vec3(0.065, 0.340, 0.380);
// Godot dielectric F0 = 0.16 * specular^2. 0.40 gives 2.56%, near
// source feather IOR 1.42 with its 0.42 IOR-level multiplier (about 2.53%).
uniform float feather_specular : hint_range(0.0, 1.0) = 0.40;
uniform float hard_specular : hint_range(0.0, 1.0) = 0.50;
uniform float normal_strength : hint_range(0.0, 1.0) = 1.0;

vec3 atlas_srgb_to_linear(vec3 value) {
	return mix(value / 12.92, pow((value + vec3(0.055)) / 1.055, vec3(2.4)),
		step(vec3(0.04045), value));
}

vec3 atlas_linear_to_srgb(vec3 value) {
	value = max(value, vec3(0.0));
	return mix(value * 12.92, 1.055 * pow(value, vec3(1.0 / 2.4)) - vec3(0.055),
		step(vec3(0.0031308), value));
}

void fragment() {
	vec4 masks = texture(atlas_masks, UV);
	vec3 weights = max(masks.rgb, vec3(0.0));
	// Filtering/compression may move their sum slightly above one.
	weights /= max(1.0, weights.r + weights.g + weights.b);
	float dark = max(0.0, 1.0 - weights.r - weights.g - weights.b);
	vec3 reference = reference_dorsal_linear * dark
		+ reference_ventral_linear * weights.r
		+ reference_patch_linear * weights.g
		+ reference_identity_linear * weights.b;
	vec3 desired = dorsal_linear * dark + ventral_linear * weights.r
		+ patch_linear * weights.g + identity_linear * weights.b;
	float feather = smoothstep(0.25, 0.75, masks.a);
	vec3 pigment_ratio = desired / max(reference, vec3(0.0001));
	vec3 baked = texture(atlas_albedo, UV).rgb;
	// GLES3 exposes sRGB albedo to the custom fragment, then decodes ALBEDO
	// before lighting. Mobile/Forward+ already expose linear source_color.
	// Recolor in LINEAR pigment space on both; never multiply a linear ratio
	// directly into sRGB. Actual Compatibility regression caught up to39/255
	// channel error without this boundary conversion.
	if (OUTPUT_IS_SRGB) {
		baked = atlas_srgb_to_linear(baked);
	}
	vec3 recolored = baked * mix(vec3(1.0), pigment_ratio, feather);
	ALBEDO = OUTPUT_IS_SRGB ? atlas_linear_to_srgb(recolored) : recolored;
	vec3 orm = texture(atlas_orm, UV).rgb;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.0;
	ROUGHNESS = clamp(orm.g, 0.04, 1.0);
	METALLIC = orm.b;
	SPECULAR = mix(hard_specular, feather_specular, feather);
	NORMAL_MAP = texture(atlas_normal, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
}
