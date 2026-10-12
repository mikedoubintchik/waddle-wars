shader_type canvas_item;
render_mode unshaded;

// TextureRect supplies atlas UVs. Only the neighboring scarf's corner is
// excluded; the complete blue/white snow trail is left untouched.
void fragment() {
    vec2 atlas_pixel = UV / TEXTURE_PIXEL_SIZE;
    if (atlas_pixel.x > 925.0 && atlas_pixel.y < 805.0) {
        COLOR.a = 0.0;
    }
}
