class_name UtilityReferenceArt
extends RefCounted
## Native symbols extend the existing navy settings icon vocabulary.

const SYMBOLS := {
	"reset": '<path d="M50 24A20 20 0 0 0 15 15l-7 8m0-15v16h16M14 40a20 20 0 0 0 35 9l7-8m0 15V40H40" fill="none" stroke="#173c60" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>',
	"back": '<path d="M41 8 17 32l24 24" fill="none" stroke="#173c60" stroke-width="13" stroke-linecap="round" stroke-linejoin="round"/>',
	"colorblind": '<circle cx="23" cy="24" r="16"/><circle cx="43" cy="24" r="16" opacity=".8"/><circle cx="33" cy="43" r="16" opacity=".85"/>',
	"sound": '<path d="M9 24h10L34 12v40L19 40H9z"/><path d="M42 23q12 9 0 18M49 15q22 17 0 34" fill="none" stroke="#173c60" stroke-width="5" stroke-linecap="round"/>',
	"disconnect": '<path d="M8 22q24-22 48 0M17 32q15-14 30 0M25 42q7-6 14 0" fill="none" stroke="#173c60" stroke-width="6" stroke-linecap="round"/><path d="m43 39 13 15m0-15-13 15" fill="none" stroke="#f35243" stroke-width="6" stroke-linecap="round"/>',
	"hud": '<path d="M10 10h44v34H10zM28 44h8v8h10v5H18v-5h10z" fill="none" stroke="#173c60" stroke-width="5" stroke-linejoin="round"/>',
	"ui": '<rect x="7" y="7" width="22" height="22" rx="5"/><rect x="35" y="7" width="22" height="22" rx="5"/><rect x="7" y="35" width="22" height="22" rx="5"/><rect x="35" y="35" width="22" height="22" rx="5"/>',
	"mountain": '<path d="m1 48 21-26 9 10 12-19 20 35-15-7-5-10-8 16-11-11-10 10z" fill="#668daf"/>',
	"controller": '<path d="M17 18h30q8 0 12 26 1 9-7 7L40 39H24L12 51Q2 53 5 43q4-25 12-25z"/><path d="M18 24v13m-6-6h13" fill="none" stroke="#fff9ed" stroke-width="4"/><circle cx="44" cy="27" r="3" fill="#fff9ed"/><circle cx="50" cy="33" r="3" fill="#fff9ed"/>',
	"shield": '<path d="M32 5 56 13v19q-2 18-24 29Q10 50 8 32V13z"/>',
	"book": '<path d="M31 12Q18 4 5 11v42q15-6 26 1zM35 12q13-8 26-1v42q-15-6-26 1z"/>',
}
static var _icons: Dictionary = {}


static func icon(key: String) -> Texture2D:
	if key == "back":
		return ExpeditionMenuStyle.wardrobe_sprite("back")
	if not _icons.has(key):
		_icons[key] = UITheme.make_icon('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><g fill="#173c60">'+String(SYMBOLS[key])+'</g></svg>', 2.0)
	return _icons[key]


static func bind_background(owner: Control, portrait: String, landscape: String) -> TextureRect:
	var art := TextureRect.new()
	art.name = "ReferenceSceneArtwork"
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	owner.add_child(art)
	var apply := func() -> void:
		var view := owner.get_viewport_rect().size
		art.texture = ExpeditionMenuStyle._material_texture(portrait if view.y >= view.x else landscape)
	owner.resized.connect(apply)
	apply.call()
	return art


static func slider_thumb(size: int) -> Texture2D:
	var key := "thumb_%d" % size
	if not _icons.has(key):
		_icons[key] = UITheme.make_icon('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 64 64"><defs><linearGradient id="ivory" x2="0" y2="1"><stop stop-color="#fffef9"/><stop offset="1" stop-color="#e5decd"/></linearGradient></defs><circle cx="32" cy="35" r="27" fill="#afaa9c" opacity=".4"/><circle cx="32" cy="30" r="26" fill="url(#ivory)" stroke="#fffdf7" stroke-width="3"/></svg>' % [size,size], 1.0)
	return _icons[key]


static func centered_button(button: Button, caption: String, texture: Texture2D,
		font_size: int, height: float, primary: bool = false, arrow: bool = false) -> void:
	# Keep native text for accessibility and existing input contracts; the grouped
	# child renders icon and label together instead of separating them at edges.
	ExpeditionMenuStyle.illustrated_action(button, caption, texture, font_size,
		height, arrow, Color.WHITE if primary else ExpeditionMenuStyle.INK)
	button.text = caption
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color", "font_shadow_color"]:
		button.add_theme_color_override(state, Color.TRANSPARENT)
	var group := button.get_node("IllustratedAction") as HBoxContainer
	var picture := group.get_child(0) as TextureRect
	if not primary:
		picture.custom_minimum_size = Vector2.ONE * height * 0.56
