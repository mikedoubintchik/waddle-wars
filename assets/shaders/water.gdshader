// Water: 2-octave sine vertex displacement with analytic normals, scrolling
// noise shading, fresnel toward the horizon, optional foam band via vertex
// color (paint COLOR.r toward 0.0 for foam — unset vertex color = no foam).
// Mobile-cheap: no textures, no screen-space reads.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 deep_color : source_color = vec4(0.08, 0.3, 0.5, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.3, 0.62, 0.78, 1.0);
uniform vec4 foam_color : source_color = vec4(0.96, 0.99, 1.0, 1.0);
uniform float alpha_value : hint_range(0.0, 1.0) = 0.9;
uniform float wave_height = 0.18;
uniform float wave_scale = 0.35;
uniform float wave_speed = 1.1;
uniform float fresnel_power = 3.0;
uniform float crest_foam : hint_range(0.0, 1.0) = 0.25;

varying vec3 world_pos;
varying float wave_h;      // -1..1 relative crest height
varying float foam_mask;   // 1 = foam (from vertex color)

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	float t = TIME * wave_speed;
	vec2 p = VERTEX.xz * wave_scale;
	// Two crossing sine octaves; analytic derivatives give the normal free.
	float w1 = sin(p.x * 1.7 + p.y * 0.8 + t);
	float w2 = sin(p.x * -0.9 + p.y * 2.3 + t * 1.37);
	wave_h = w1 * 0.65 + w2 * 0.35;
	VERTEX.y += wave_h * wave_height;
	float d1x = cos(p.x * 1.7 + p.y * 0.8 + t) * 1.7 * 0.65;
	float d1z = cos(p.x * 1.7 + p.y * 0.8 + t) * 0.8 * 0.65;
	float d2x = cos(p.x * -0.9 + p.y * 2.3 + t * 1.37) * -0.9 * 0.35;
	float d2z = cos(p.x * -0.9 + p.y * 2.3 + t * 1.37) * 2.3 * 0.35;
	float k = wave_height * wave_scale;
	NORMAL = normalize(vec3(-(d1x + d2x) * k, 1.0, -(d1z + d2z) * k));
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	foam_mask = 1.0 - COLOR.r;
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, fresnel_power);

	// Scrolling surface shimmer (fake normal-map shading).
	vec2 uv = world_pos.xz * 0.5 + vec2(TIME * 0.14, TIME * -0.09);
	float n = value_noise(uv) * 0.6 + value_noise(uv * 2.9 - TIME * 0.07) * 0.4;

	vec3 water = mix(deep_color.rgb, shallow_color.rgb, fresnel * 0.8 + n * 0.2);
	float crest = smoothstep(1.0 - crest_foam, 1.0, wave_h * 0.5 + 0.5) * n;
	float foam = clamp(foam_mask + crest, 0.0, 1.0);
	ALBEDO = mix(water, foam_color.rgb, foam);
	ROUGHNESS = mix(0.06, 0.55, foam);
	SPECULAR = 0.7;
	ALPHA = clamp(alpha_value + foam * 0.1 + fresnel * 0.08, 0.0, 1.0);
}
