// Pickup glow: pulsing emission + fresnel rim so fish/items read from a
// distance. Pair with a high glow HDR threshold — only the pulse peak blooms.
// Mobile-cheap: no textures, no noise.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(0.9, 0.65, 0.25, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.85, 0.4, 1.0);
uniform float pulse_speed = 3.2;
uniform float pulse_min : hint_range(0.0, 2.0) = 0.35;
uniform float pulse_max : hint_range(0.0, 4.0) = 1.15;
uniform float rim_power = 2.2;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.4;

void fragment() {
	float pulse = mix(pulse_min, pulse_max, 0.5 + 0.5 * sin(TIME * pulse_speed));
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	ALBEDO = base_color.rgb;
	ROUGHNESS = roughness_value;
	EMISSION = glow_color.rgb * (pulse * 0.5 + rim * pulse);
}
