// Runner-only painted ice/snow. One filtered tile replaces the procedural
// crack web; world coordinates keep both chunk joins and the start apron
// continuous. Opaque, no screen/depth reads, no time animation or extra draws.
shader_type spatial;
render_mode depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D painted_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform bool painted_enabled = false;
uniform vec4 tint : source_color = vec4(0.34, 0.53, 0.69, 1.0);
// Normalize the tile's average colour so biome tint stays the albedo authority.
// Paint supplies authored brushwork/veins without doubling the blue tint.
uniform vec4 paint_reference : source_color = vec4(0.3778, 0.7594, 0.9547, 1.0);
uniform float tile_metres = 16.0;
uniform float paint_strength : hint_range(0.0, 1.0) = 0.72;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.44;
uniform float specular_amount : hint_range(0.0, 1.0) = 0.26;
uniform float emission_lift : hint_range(0.0, 0.15) = 0.055;

varying vec3 world_pos;
varying float view_dist;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	view_dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
	vec3 paint = vec3(1.0);
	if (painted_enabled) {
		// Triangle-wave UVs mirror every other tile. Generated opposing edges
		// need not match: neighbouring tiles always meet at the same texels.
		vec2 tile_uv = abs(fract(world_pos.xz / (tile_metres * 2.0)) * 2.0 - 1.0);
		vec3 tile = texture(painted_albedo, tile_uv).rgb;
		paint = clamp(tile / max(paint_reference.rgb, vec3(0.04)), vec3(0.58), vec3(1.5));
	}
	// Mid/far ground stays quiet enough for the semantic obstacle colours and
	// gold pickups to read. Mipmaps handle minification; this only calms tone.
	float far = smoothstep(22.0, 75.0, view_dist);
	vec3 body = tint.rgb * mix(vec3(1.0), paint, paint_strength * (1.0 - far * 0.28));
	ALBEDO = clamp(body, vec3(0.0), vec3(1.0));
	ROUGHNESS = min(roughness_base + far * 0.12, 0.96);
	SPECULAR = specular_amount;
	METALLIC = 0.0;
	EMISSION = ALBEDO * emission_lift;
}
