shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// Palette lives on GeometryInstance3D, not duplicated ShaderMaterials. Eight
// racers therefore share one atlas/material/RID while retaining species and
// identity color. This also guarantees one shader signature at countdown.
instance uniform vec4 dorsal_color : source_color = vec4(0.063, 0.141, 0.231, 1.0);
instance uniform vec4 ventral_color : source_color = vec4(0.949, 0.875, 0.729, 1.0);
instance uniform vec4 mantle_color : source_color = vec4(0.161, 0.267, 0.369, 1.0);
instance uniform vec4 patch_color : source_color = vec4(0.851, 0.608, 0.220, 1.0);
instance uniform vec4 identity_color : source_color = vec4(0.18, 0.78, 0.92, 1.0);
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.75;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.055;
uniform sampler2D feather_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D feather_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D feather_orm : filter_linear_mipmap_anisotropic, repeat_enable;

varying vec4 painted_vertex;

void vertex() {
	painted_vertex = COLOR;
}

void fragment() {
	vec3 painted;
	bool vertex_keratin = painted_vertex.a < 0.5;
	float identity_mask = vertex_keratin ? 0.0 : min(painted_vertex.r, min(painted_vertex.g, painted_vertex.b));
	vec3 semantic_mask = max(painted_vertex.rgb - vec3(identity_mask), vec3(0.0));
	float authored_ao = vertex_keratin ? 1.0 : clamp(painted_vertex.a, 0.68, 1.0);
	if (vertex_keratin) {
		painted = painted_vertex.rgb;
	} else {
		painted = dorsal_color.rgb;
		painted = mix(painted, mantle_color.rgb, clamp(semantic_mask.b, 0.0, 1.0));
		painted = mix(painted, ventral_color.rgb, clamp(semantic_mask.r, 0.0, 1.0));
		painted = mix(painted, patch_color.rgb, clamp(semantic_mask.g, 0.0, 1.0));
		painted = mix(painted, identity_color.rgb, smoothstep(0.035, 0.31, identity_mask));
	}
	// Atlas already contains one seamless directional field per half. Sampling
	// once over authored UVs keeps close-up strokes larger and removes manual-
	// fract derivative seams down chest/crown.
	vec2 feather_tile = clamp(UV, vec2(0.0), vec2(1.0));
	// Keep bilinear taps inside each 512px half. Exact 0.5/1.0 coordinates can
	// otherwise borrow the opposite palette island despite seamless source art.
	const float HALF_TEXEL = 0.5 / 1024.0;
	vec2 dark_uv = vec2(mix(HALF_TEXEL, 0.5 - HALF_TEXEL, feather_tile.x),
		feather_tile.y);
	vec2 cream_uv = vec2(mix(0.5 + HALF_TEXEL, 1.0 - HALF_TEXEL,
		feather_tile.x), feather_tile.y);
	float cream_feather = clamp(max(semantic_mask.r, semantic_mask.g * 0.62), 0.0, 1.0);
	vec3 detail_albedo = mix(texture(feather_albedo, dark_uv).rgb,
		texture(feather_albedo, cream_uv).rgb, cream_feather) * 1.10;
	vec3 detail_normal = mix(texture(feather_normal, dark_uv).rgb,
		texture(feather_normal, cream_uv).rgb, cream_feather);
	vec3 packed_orm = mix(texture(feather_orm, dark_uv).rgb,
		texture(feather_orm, cream_uv).rgb, cream_feather);
	if (!vertex_keratin) {
		float pigment_depth = mix(0.76, 0.88, cream_feather);
		painted *= mix(vec3(1.0), detail_albedo, pigment_depth);
	}
	float facing = max(dot(normalize(NORMAL), normalize(VIEW)), 0.0);
	float soft_rim = pow(1.0 - facing, 3.3) * rim_strength;
	// Cyan identity exists only in painted jaw seams. Silhouette sheen stays a
	// neutral mantle blue, preventing a glowing cyan collar around every racer.
	ALBEDO = painted * authored_ao + mantle_color.rgb * soft_rim * (vertex_keratin ? 0.0 : 1.0);
	float feather_normal_mix = mix(0.62, 0.70, cream_feather);
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), detail_normal,
		vertex_keratin ? 0.0 : feather_normal_mix);
	NORMAL_MAP_DEPTH = vertex_keratin ? 0.0 : mix(0.42, 0.48, cream_feather);
	AO = vertex_keratin ? 1.0 : packed_orm.r;
	float keratin_response = smoothstep(0.10, 0.28, painted_vertex.a);
	ROUGHNESS = vertex_keratin ? mix(0.24, 0.58, keratin_response) :
		clamp(mix(surface_roughness, packed_orm.g, 0.65), 0.68, 0.92);
	SPECULAR = vertex_keratin ? mix(0.38, 0.20, keratin_response) : 0.15;
}
