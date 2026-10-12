shader_type spatial;
render_mode cull_back, diffuse_burley;
// Tiny crossed yarn ridges are anchored in mesh UVs, never in screen space.
uniform vec4 yarn_color : source_color = vec4(0.7, 0.08, 0.1, 1.0);
uniform bool rainbow = false;
void fragment() {
	vec2 weave = UV * vec2(42.0, 34.0);
	vec2 cell = fract(weave);
	float strand = cos((cell.x + abs(cell.y - 0.5) * 0.8) * 6.28318);
	float rib = 0.88 + 0.12 * strand;
	vec3 pigment = yarn_color.rgb;
	if (rainbow) {
		pigment = 0.42 + 0.35 * cos(6.28318 * (UV.y * 1.7 + vec3(0.0, 0.67, 0.33)));
	}
	ALBEDO = pigment * rib;
	NORMAL_MAP = normalize(vec3(-sin(cell.x * 6.28318) * 0.16,
		cos(cell.y * 6.28318) * 0.10, 1.0)) * 0.5 + 0.5;
	ROUGHNESS = 0.94;
	SPECULAR = 0.18;
}
