// The authored generator gives every face one guttered 4x4 semantic atlas
// cell. glTF flips Blender V: runtime row 3 is source palette row 0. These
// role IDs were checked against COLOR_0/TEXCOORD_0 in the committed GLBs.
// Remap paint only; preserve vertex face shading, instance variation, UVs,
// geometry and gameplay bounds. Values below are linear, like COLOR_0.
vec3 runner_painted_role(vec3 vertex_paint, vec2 uv) {
	ivec2 cell = clamp(ivec2(floor(uv * 4.0)), ivec2(0), ivec2(3));
	int role = cell.x + (3 - cell.y) * 4;
	vec3 source = vec3(1.0);
	vec3 target = vec3(1.0);
	if (role == 0) { // deep marine recess
		source = vec3(0.120, 0.275, 0.390); target = vec3(0.105, 0.255, 0.345);
	} else if (role == 1) { // navy hardware
		source = vec3(0.390, 0.580, 0.650); target = vec3(0.180, 0.395, 0.475);
	} else if (role == 2) { // teal painted steel
		source = vec3(0.500, 0.675, 0.735); target = vec3(0.245, 0.485, 0.545);
	} else if (role == 3) { // softer teal highlights
		source = vec3(0.745, 0.855, 0.865); target = vec3(0.490, 0.690, 0.715);
	} else if (role == 4) { // pale ice equipment casing
		source = vec3(0.865, 0.930, 0.925); target = vec3(0.835, 0.935, 0.970);
	} else if (role == 5) { // warm ivory snow
		source = vec3(0.965, 0.987, 0.972); target = vec3(0.990, 0.980, 0.945);
	} else if (role == 7) { // coral: warm dodge livery remains warm
		source = vec3(0.960, 0.255, 0.035); target = vec3(0.970, 0.225, 0.115);
	} else if (role == 8) { // amber/brass trim and lamp collars
		source = vec3(1.000, 0.420, 0.055); target = vec3(0.990, 0.565, 0.125);
	} else if (role == 11) { // brass beacon hardware
		source = vec3(1.000, 0.820, 0.200); target = vec3(0.970, 0.710, 0.235);
	} else if (role == 14) { // rail body/service panels; snow has its own role
		source = vec3(0.805, 0.855, 0.825); target = vec3(0.145, 0.365, 0.490);
	} else {
		// Cyan duck, green launch, glass and rubber keep authored semantics.
		return vertex_paint;
	}
	return clamp(vertex_paint / source, vec3(0.72), vec3(1.12)) * target;
}
