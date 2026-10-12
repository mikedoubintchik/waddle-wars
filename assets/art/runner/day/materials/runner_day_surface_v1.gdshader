shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;
#include "res://assets/art/runner/day/materials/runner_day_palette_v2.gdshaderinc"

// One shared Compatibility-safe painted response for every DAY surface.
// Weak hue-preserving emission keeps semantic paint readable under a portal
// without flattening normals or requiring screen/depth textures.
uniform sampler2D painted_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D painted_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D packed_orm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.82;
uniform float emission_lift : hint_range(0.0, 0.08) = 0.065;

void fragment() {
	vec3 atlas_albedo = texture(painted_albedo, UV).rgb;
	vec3 painted = atlas_albedo * runner_painted_role(COLOR.rgb, UV);
	vec3 orm = texture(packed_orm, UV).rgb;
	ALBEDO = painted;
	NORMAL_MAP = texture(painted_normal, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	AO = orm.r;
	ROUGHNESS = clamp(orm.g * 0.85 + 0.16, 0.42, 0.95);
	METALLIC = orm.b * 0.45;
	SPECULAR = 0.19;
	EMISSION = painted * emission_lift;
}
