shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float strength = 0.0;
uniform float haze_opacity = 0.0;
uniform float motion_scale = 1.0;
uniform float effect_clock = 0.0;
void fragment() {
	// Clearly visible, temporary whiteout across the world, with curling rear
	// snow. HUD draws on the next CanvasLayer, after this pass.
	float edge = smoothstep(0.24, 0.49, abs(SCREEN_UV.x - 0.5));
	float lower = smoothstep(0.15, 0.65, SCREEN_UV.y);
	float frost = edge * lower * strength;
	vec2 drift = vec2(sin(SCREEN_UV.y * 17.0 + effect_clock * 1.7),
		cos(SCREEN_UV.y * 11.0 - effect_clock * 1.25) * 0.35);
	// Keep displacement proportional to height, not wider desktop width.
	drift.x *= SCREEN_PIXEL_SIZE.x / SCREEN_PIXEL_SIZE.y;
	vec2 warped = clamp(SCREEN_UV + drift * frost * motion_scale * 0.004,
		SCREEN_PIXEL_SIZE, vec2(1.0) - SCREEN_PIXEL_SIZE);
	vec3 world = texture(screen_texture, warped).rgb;
	// First loss: 31–38% whiteout; second: 47–57%. Central route keeps at
	// least half its contrast. Slow cloud density makes the haze read as snow
	// blowing past, without extra texture reads, particles or a blur buffer.
	// Comfort motion off freezes both cloud density and edge displacement.
	float cloud = 0.5 + 0.5 * sin(SCREEN_UV.x * 8.0 + SCREEN_UV.y * 6.0
		+ effect_clock * motion_scale * 0.45);
	float haze = min(0.57, haze_opacity + strength * (edge * 0.08 + lower * cloud * 0.025));
	COLOR = vec4(mix(world, vec3(0.94, 0.975, 1.0), haze), 1.0);
}
