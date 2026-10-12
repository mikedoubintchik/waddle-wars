class_name ExpeditionMenuStyle
extends RefCounted
## Shared material kit for the art-led menu family. Functional text and state
## stay live controls; the foreground uses the same authored finish as the art.

const INK: Color = Color("10264a")
const INK_MUTED: Color = Color("375573")
const IVORY: Color = Color("fff9ed")
const IVORY_HOVER: Color = Color("ffffff")
const CORAL: Color = Color("f35243")
const CORAL_HOVER: Color = Color("ff6b55")
const CORAL_PRESSED: Color = Color("ce3f35")
const GOLD: Color = Color("ffc34b")

const BACKGROUNDS: Dictionary = {
	"home_portrait": "res://assets/art/ui/menu/home_background_portrait_v1.webp",
	"home_landscape": "res://assets/art/ui/menu/home_background_landscape_v1.webp",
	"missions_portrait": "res://assets/art/ui/menu/missions_background_portrait_v1.webp",
	"penguins_portrait": "res://assets/art/ui/menu/penguins_background_portrait_v1.webp",
	"penguins_landscape": "res://assets/art/ui/menu/penguins_background_landscape_v2.webp",
	"base_camp_portrait": "res://assets/art/ui/menu/base_camp_background_portrait_v1.webp",
	"base_camp_landscape": "res://assets/art/ui/menu/base_camp_desktop_background_v2.webp",
	"leaderboard_portrait": "res://assets/art/ui/menu/leaderboard_background_portrait_v1.webp",
	"leaderboard_landscape": "res://assets/art/ui/menu/leaderboard_desktop_background_v2.webp",
	"runner_results_landscape": "res://assets/art/ui/menu/runner_results_desktop_background_v2.webp",
	"runner_results_portrait": "res://assets/art/ui/menu/runner_results_portrait_background_v3.webp",
	"achievements_portrait": "res://assets/art/ui/menu/achievements_background_portrait_v1.webp",
	"settings_portrait": "res://assets/art/ui/menu/settings_background_portrait_v1.webp",
	"credits_portrait": "res://assets/art/ui/menu/credits_background_portrait_v1.webp",
	"shop_portrait": "res://assets/art/ui/menu/shop_background_portrait_v1.webp",
	"account_portrait": "res://assets/art/ui/menu/account_background_portrait_v1.webp",
	"race_setup_portrait": "res://assets/art/ui/menu/race_setup_background_v1.webp",
	"race_results_portrait": "res://assets/art/ui/menu/race_results_background_v1.webp",
}

static var _textures: Dictionary = {}
static var _menu_display_font: Font = null
const CORAL_MATERIAL := "res://assets/art/ui/menu/coral_cta_blank_v1.webp"
const IVORY_MATERIAL := "res://assets/art/ui/menu/ivory_snow_panel_blank_v1.webp"
const CORAL_SHELF := "res://assets/art/ui/menu/coral_shelf_blank_v1.webp"
const IVORY_SHELF := "res://assets/art/ui/menu/ivory_snow_shelf_blank_v1.webp"
const PaintedSurface := preload("res://scripts/ui/painted_menu_surface.gd")
const EMPEROR_PORTRAIT := "res://assets/art/ui/menu/emperor_portrait_v1.webp"


static func display_font() -> Font:
	if _menu_display_font == null:
		_menu_display_font = load("res://assets/fonts/LilitaOne-Regular.ttf") as Font
	return _menu_display_font


static func title_texture(key: String) -> Texture2D:
	var source := _material_texture("res://assets/art/ui/menu/%s_title_v1.webp" % key)
	var regions := {
		"penguins": Rect2(110, 180, 1930, 365),
		"missions": Rect2(110, 120, 1960, 480),
		"settings": Rect2(40, 80, 2090, 580),
		"leaderboard": Rect2(20, 35, 2110, 689),
		"account": Rect2(35, 125, 2118, 510),
		"controls": Rect2(45, 125, 2080, 465),
	}
	if not regions.has(key):
		return source
	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = regions[key]
	atlas.filter_clip = true
	return atlas
const WARDROBE_ATLAS := "res://assets/art/ui/menu/wardrobe_sprite_atlas_v1.png"
const WARDROBE_REGIONS := {
	# Keep the complete painted button/shadow, excluding empty atlas gutters.
	# The hit target stays unchanged; only the visible artwork fills it.
	"back": Rect2(46, 90, 276, 286),
	"hat_beanie": Rect2(375, 40, 340, 350),
	"hat_earwarmers": Rect2(722, 65, 355, 330),
	"hat_headset": Rect2(1090, 65, 350, 330),
	"hat_crown": Rect2(26, 416, 323, 294),
	"scarf_red": Rect2(385, 406, 345, 339),
	"scarf_rainbow": Rect2(750, 403, 337, 347),
	"scarf_bowtie": Rect2(1096, 470, 330, 235),
	"goggles_ski": Rect2(10, 785, 346, 220),
	"goggles_aviator": Rect2(369, 805, 369, 205),
	"trail_snowflake": Rect2(752, 730, 335, 334),
	"trail_rainbow": Rect2(1100, 720, 341, 340),
}


static func wardrobe_sprite(id: String) -> Texture2D:
	if not WARDROBE_REGIONS.has(id):
		return null
	var key := "wardrobe:%s" % id
	if not _textures.has(key):
		var atlas := AtlasTexture.new()
		atlas.atlas = _material_texture(WARDROBE_ATLAS)
		atlas.region = WARDROBE_REGIONS[id]
		atlas.filter_clip = true
		_textures[key] = atlas
	return _textures[key] as Texture2D


static func _material_texture(path: String) -> Texture2D:
	if not _textures.has(path):
		_textures[path] = ResourceLoader.load(path) as Texture2D
	return _textures[path] as Texture2D


static func material_box(primary: bool = false, pad_h: float = 18.0,
		pad_v: float = 10.0, tint: Color = Color.WHITE) -> PaintedSurface:
	var box := PaintedSurface.new()
	box.texture = _material_texture("res://assets/art/ui/menu/%s_capsule_v3.webp" % ("coral" if primary else "ivory"))
	box.region = Rect2(88, 85, 1996, 522) if primary else Rect2(82, 122, 2010, 484)
	box.content_margin_left = pad_h
	box.content_margin_right = pad_h
	box.content_margin_top = pad_v
	box.content_margin_bottom = pad_v
	box.modulate_color = tint
	return box


static func material_card(pad_h: float = 18.0,
		pad_v: float = 14.0) -> PaintedSurface:
	var box := material_box(false, pad_h, pad_v)
	box.capsule = false
	box.texture = _material_texture("res://assets/art/ui/menu/ivory_card_v4.webp")
	box.region = Rect2(15, 32, 1420, 1025)
	return box


static func _trimmed_material(path: String, region: Rect2) -> Texture2D:
	var key := "trim:%s" % path
	if not _textures.has(key):
		var atlas := AtlasTexture.new()
		atlas.atlas = _material_texture(path)
		atlas.region = region
		atlas.filter_clip = true
		_textures[key] = atlas
	return _textures[key] as Texture2D


static func species_portrait() -> Texture2D:
	return _material_texture(EMPEROR_PORTRAIT)


static func back_button(size: float = 60.0) -> Button:
	var back := Button.new()
	back.name = "Back"
	back.accessibility_name = "Back"
	back.custom_minimum_size = Vector2(size, size)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.icon = wardrobe_sprite("back")
	back.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back.expand_icon = true
	back.add_theme_constant_override("icon_max_width", roundi(size))
	var normal := surface(IVORY, roundi(size * 0.5), true)
	normal.border_color = Color("d8e4ed")
	normal.set_border_width_all(2)
	normal.set_content_margin_all(0)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = IVORY_HOVER
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("d8eafa")
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		back.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = GOLD
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(roundi(size * 0.5))
	back.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	UITheme.hook_sounds(back)
	return back


static func currency_pill(amount: int, compact: bool = true) -> PanelContainer:
	var pill := PanelContainer.new()
	pill.name = "FishBalance"
	pill.size_flags_horizontal = Control.SIZE_SHRINK_END
	var box := material_box(false, UITheme.scaled(10.0 if compact else 13.0),
		UITheme.scaled(5.0))
	pill.add_theme_stylebox_override("panel", box)
	var row := HBoxContainer.new()
	row.name = "FishBalanceContent"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_theme_constant_override("separation",
		roundi(UITheme.scaled(4.0 if compact else 6.0)))
	pill.add_child(row)
	var fish := TextureRect.new()
	fish.name = "FishSymbol"
	fish.texture = _material_texture(
		"res://assets/art/ui/menu/home_fish_symbol_clean_v2.png")
	fish.custom_minimum_size = Vector2(UITheme.scaled(48.0 if compact else 56.0),
		UITheme.scaled(38.0 if compact else 44.0))
	fish.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fish.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fish.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fish.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(fish)
	var number := label(grouped_amount(amount),
		roundi(float(UITheme.scaled_font(22 if compact else 25)) * 1.20), INK)
	number.name = "FishAmount"
	number.add_theme_font_override("font", display_font())
	number.autowrap_mode = TextServer.AUTOWRAP_OFF
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(number)
	return pill


static func grouped_amount(amount: int) -> String:
	var digits := str(amount)
	var grouped := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			grouped += ","
		grouped += digits[i]
	return grouped


static func background_texture(key: String, portrait: bool) -> Texture2D:
	var lookup := "%s_%s" % [key, "portrait" if portrait else "landscape"]
	if not BACKGROUNDS.has(lookup):
		lookup = "%s_portrait" % key
	if not BACKGROUNDS.has(lookup):
		lookup = "home_landscape" if not portrait else "base_camp_portrait"
	if not _textures.has(lookup):
		_textures[lookup] = ResourceLoader.load(String(BACKGROUNDS[lookup])) as Texture2D
	return _textures[lookup] as Texture2D


static func add_backdrop(parent: Control, key: String) -> TextureRect:
	var art := TextureRect.new()
	art.name = "ExpeditionMenuArt"
	var viewport_size := parent.get_viewport_rect().size
	art.texture = background_texture(key, viewport_size.y >= viewport_size.x)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(art)
	parent.resized.connect(func() -> void:
		art.texture = background_texture(key, parent.size.y >= parent.size.x))
	return art


static func surface(fill: Color = IVORY, radius: int = 32,
		shadow: bool = true) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_corner_radius_all(radius)
	box.anti_aliasing = true
	box.content_margin_left = 16.0
	box.content_margin_right = 16.0
	box.content_margin_top = 12.0
	box.content_margin_bottom = 12.0
	if shadow:
		box.shadow_color = Color(0.03, 0.10, 0.19, 0.26)
		box.shadow_size = 7
		box.shadow_offset = Vector2(0.0, 3.0)
	return box


static func landscape_pill(primary: bool = false) -> StyleBoxFlat:
	var box := surface(CORAL if primary else IVORY, 30, true)
	box.border_color = Color("ffe7c6") if primary else Color("e1f0f7")
	box.border_width_top = 3
	box.border_width_left = 1
	box.border_width_right = 1
	box.border_width_bottom = 2
	box.content_margin_left = 18.0
	box.content_margin_right = 18.0
	box.content_margin_top = 9.0
	box.content_margin_bottom = 9.0
	return box


static func style_button(button: Button, primary: bool = false,
		font_size: int = 24) -> Button:
	button.add_theme_font_override("font", display_font())
	button.add_theme_font_size_override("font_size", font_size)
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, font_size * 2.5)
	button.add_theme_color_override("font_color", Color.WHITE if primary else INK)
	button.add_theme_color_override("font_hover_color", Color.WHITE if primary else INK)
	button.add_theme_color_override("font_pressed_color", Color.WHITE if primary else INK)
	button.add_theme_color_override("font_focus_color", Color.WHITE if primary else INK)
	button.add_theme_color_override("font_disabled_color", Color(0.38, 0.46, 0.52))
	button.add_theme_stylebox_override("normal", material_box(primary))
	button.add_theme_stylebox_override("hover", material_box(primary, 18.0, 10.0,
		Color(1.08, 1.08, 1.08)))
	button.add_theme_stylebox_override("pressed", material_box(primary, 18.0,
		10.0, Color(0.84, 0.86, 0.88)))
	button.add_theme_stylebox_override("disabled", surface(Color("cdd5da"), 32, false))
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = GOLD
	focus.set_border_width_all(4)
	focus.set_corner_radius_all(32)
	focus.set_expand_margin_all(3.0)
	# Touching a button must not leave the desktop keyboard-focus halo over
	# the painted snow edge. Desktop/gamepad focus keeps its visible ring.
	button.add_theme_stylebox_override("focus",
		StyleBoxEmpty.new() if UITheme.is_touch() else focus)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button


static func button(label: String, primary: bool = false,
		font_size: int = 24, height: float = 64.0) -> Button:
	var control := Button.new()
	control.text = label
	control.custom_minimum_size.y = height
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	style_button(control, primary, font_size)
	UITheme.hook_sounds(control)
	return control


static func label(value: String, font_size: int = 28,
		color: Color = INK) -> Label:
	var control := Label.new()
	control.text = value
	control.add_theme_font_override("font", UITheme.bold_font())
	control.add_theme_font_size_override("font_size", font_size)
	control.add_theme_color_override("font_color", color)
	if font_size >= 24:
		control.add_theme_color_override("font_shadow_color",
			Color(0.02, 0.08, 0.16, 0.22))
		control.add_theme_constant_override("shadow_offset_y", 2)
	control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return control


static func illustrated_action(control: Button, caption: String, icon: Texture2D,
		font_size: int, height: float, arrow: bool = true, ink: Color = Color.WHITE) -> void:
	control.text = ""
	control.icon = null
	control.accessibility_name = caption
	var row := HBoxContainer.new()
	row.name = "IllustratedAction"
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = height * 0.16
	row.offset_right = -height * 0.16
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", roundi(height * 0.12))
	control.add_child(row)
	var picture := TextureRect.new()
	picture.texture = _trimmed_material("res://assets/art/ui/menu/run_action_icon_v5.webp", Rect2(80, 210, 1090, 840)) if icon != null and icon.resource_path.ends_with("run_action_icon_v5.webp") else icon
	picture.custom_minimum_size = Vector2(height * 1.03, height * 0.90)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(picture)
	var text_label := label(caption, font_size, ink)
	text_label.add_theme_font_override("font", display_font())
	text_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	text_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text_label)
	if arrow:
		var chevron := TextureRect.new()
		chevron.texture = UITheme.make_icon('<svg xmlns="http://www.w3.org/2000/svg" width="40" height="64" viewBox="0 0 40 64"><path d="m10 12 20 20-20 20" fill="none" stroke="#fff9eb" stroke-width="12" stroke-linecap="round" stroke-linejoin="round"/></svg>')
		chevron.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		chevron.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		chevron.custom_minimum_size = Vector2(height * 0.32, height * 0.56)
		chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(chevron)


static func panel(parent: Control, fill: Color = IVORY) -> PanelContainer:
	var control := PanelContainer.new()
	if fill.a >= 0.85 and fill.r >= 0.85 and fill.g >= 0.85:
		control.add_theme_stylebox_override("panel", material_card())
	else:
		control.add_theme_stylebox_override("panel", surface(fill))
	parent.add_child(control)
	return control
