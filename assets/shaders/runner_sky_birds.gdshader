shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;
uniform float flight_clock = 0.0;
uniform float wing_motion = 1.0;
void vertex() {
	float phase = flight_clock * 1.5 + INSTANCE_CUSTOM.r * 5.0;
	VERTEX.y += sin(phase) * abs(VERTEX.x) * 0.12 * wing_motion;
}
void fragment() {
	ALBEDO = vec3(0.97, 0.95, 0.87);
}
