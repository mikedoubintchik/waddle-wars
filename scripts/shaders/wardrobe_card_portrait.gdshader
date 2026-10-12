shader_type canvas_item;
render_mode unshaded;

uniform vec2 card_size = vec2(1.0);
uniform vec2 source_size = vec2(512.0);
uniform float corner_radius = 24.0;
uniform vec4 sky_color : source_color = vec4(0.773, 0.890, 0.973, 1.0);
varying vec2 card_position;

void vertex() {
	card_position = VERTEX;
}

void fragment() {
	vec2 half_size = card_size * 0.5;
	float radius = min(corner_radius, min(half_size.x, half_size.y));
	vec2 edge = abs(card_position - half_size) - (half_size - vec2(radius));
	float distance_to_edge = length(max(edge, vec2(0.0))) + min(max(edge.x, edge.y), 0.0) - radius;
	float coverage = 1.0 - smoothstep(-0.75, 0.75, distance_to_edge);
	// Fill the card's width, keeping the source top and entire head visible.
	// Centered cover cropped the crown whenever the image area was landscape.
	// Small side/headroom insets also keep crests clear of the rounded mask.
	float image_width = card_size.x * 0.95;
	float image_height = image_width * source_size.y / max(source_size.x, 1.0);
	vec2 image_origin = vec2(card_size.x * 0.025, card_size.x * 0.012);
	vec2 source_uv = (card_position - image_origin) / max(vec2(image_width, image_height), vec2(1.0));
	vec4 portrait = texture(TEXTURE, clamp(source_uv, vec2(0.0), vec2(1.0)));
	if (any(lessThan(source_uv, vec2(0.0))) || any(greaterThan(source_uv, vec2(1.0)))) {
		portrait.a = 0.0;
	}
	COLOR = vec4(mix(sky_color.rgb, portrait.rgb, portrait.a), coverage);
}
