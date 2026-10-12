extends "res://scripts/ui/customize_menu.gd"
## Finished outfit illustrations with temporary multi-slot try-on. Real
## ownership, fish confirmation and explicit Equip remain in CustomizeMenu.

var _premium_page: Control = null
const OUTFIT_PREVIEW := preload("res://scripts/ui/wardrobe_outfit_preview.gd")
const OUTFIT_LIBRARY := preload("res://scripts/ui/wardrobe_outfit_library.gd")
const SELECTION_SURFACE := preload("res://scripts/ui/wardrobe_selection_surface.gd")
const CATEGORY_SURFACE := preload("res://scripts/ui/wardrobe_category_surface.gd")
const PORTRAIT_MASK := preload("res://scripts/shaders/wardrobe_card_portrait.gdshader")
const CATEGORY_ATLAS := "res://assets/art/ui/menu/wardrobe_category_icons_v3.png"
const TRY_ON_ICON_SVG := '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><path d="M27 17c0-9 14-9 14-1 0 6-9 6-9 13v3L8 47c-3 2-2 6 2 6h44c4 0 5-4 2-6L32 32" fill="none" stroke="#10264a" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/></svg>'
# Tight alpha bounds retain the approved simple painted silhouettes. The
# generated atlas remains intact; AtlasTexture supplies runtime regions.
const CATEGORY_REGIONS := {
	"body": Rect2(52, 210, 348, 338),
	"hat": Rect2(489, 215, 324, 312),
	"goggles": Rect2(889, 279, 395, 214),
	"scarf": Rect2(1356, 249, 307, 293),
	"trail": Rect2(1745, 233, 382, 280),
}
var _outfit_stage: OUTFIT_PREVIEW = null
var _outfit_library: OUTFIT_LIBRARY = null
var _try_on_loadout: Dictionary = {}
var _try_on_note: Label = null
var _purchase_error := ""
var _reset_try_on_button: Button = null
var _currency_pill: PanelContainer = null
var _gallery_scroll: ScrollContainer = null
var _gallery_inset: MarginContainer = null
var _gallery_dots: HBoxContainer = null
var _gallery_reveal_revision := 0
const PORTRAIT_BY_BODY := {
	"body_classic": "emperor_portrait_v1.webp",
	"body_adelie": "adelie_portrait_v1.webp",
	"body_gentoo": "gentoo_portrait_v1.webp",
	"body_chinstrap": "chinstrap_portrait_v1.webp",
	"body_snowy": "little_blue_portrait_v1.webp",
	"body_midnight": "king_portrait_v1.webp",
	"body_rockhopper": "rockhopper_portrait_v1.webp",
	"body_macaroni": "macaroni_portrait_v1.webp",
}


func _ready() -> void:
	UITheme.apply_ui_scale(self)
	ExpeditionMenuStyle.add_backdrop(self, "penguins")
	_try_on_loadout = Progression.equipped().duplicate(true)
	_outfit_library = OUTFIT_LIBRARY.new()
	add_child(_outfit_library)
	_outfit_library.preview_changed.connect(_on_outfit_preview_changed)
	_build_page()
	Progression.fish_changed.connect(_update_fish_label)
	Progression.cosmetics_changed.connect(_on_cosmetics_changed)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	UITheme.attach_swipe_back(self, _go_back)


func _on_viewport_size_changed() -> void:
	if _orientation_reflow_queued:
		return
	_orientation_reflow_queued = true
	_rebuild_premium_page.call_deferred()


func _rebuild_premium_page() -> void:
	_orientation_reflow_queued = false
	if is_inside_tree():
		_build_page()


func _build_page() -> void:
	var category := _current_category
	var selected := _selected_id
	if _premium_page != null:
		# Rebuild can run inside viewport.size_changed. Freeing the old tree
		# synchronously invalidates callbacks still on that signal's call stack.
		_premium_page.hide()
		_premium_page.queue_free()
	_preview_pivot = null
	_penguin = null
	_preview_trail = null
	_item_grid = null
	_loadout_box = null
	_detail_action = null
	_outfit_stage = null
	_try_on_note = null
	_reset_try_on_button = null
	_currency_pill = null
	_previewed_equipped.clear()
	_tab_buttons.clear()
	_profile = LayoutProfile.for_viewport(get_viewport())
	_boost = _tall_boost()
	var shell := ExpeditionSubmenuShell.build(self, "penguins", "Penguins", 0.0)
	_premium_page = shell["root"] as Control
	var content := shell["content"] as VBoxContainer
	var scroll := shell["scroll"] as ScrollContainer
	var portrait := bool(shell["portrait"])
	if portrait:
		# The reference category shelf spans the phone safe area. Its header
		# already has its own rounded cap; a second gutter shrank every row.
		for side: String in ["left", "right"]:
			_premium_page.add_theme_constant_override("margin_%s" % side, 0)
		_premium_page.add_theme_constant_override("margin_top", 8)
		_premium_page.add_theme_constant_override("margin_bottom", 8)
	else:
		_premium_page.add_theme_constant_override("margin_top", 12)
		content.add_theme_constant_override("separation", 0)
	# Preserve scroll reachability at larger accessibility text sizes while
	# keeping the reference's clean edge instead of a permanent gray rail.
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	var header := _premium_page.find_child("ExpeditionHeader", true, false) as Control
	_currency_pill = ExpeditionMenuStyle.currency_pill(Progression.get_fish(), false)
	if portrait:
		header.custom_minimum_size.y = _profile.safe_rect.size.x * 0.125
		var back := shell["back"] as Button
		back.custom_minimum_size = Vector2.ONE * header.custom_minimum_size.y
		back.offset_right = header.custom_minimum_size.y
		back.offset_bottom = header.custom_minimum_size.y
	var header_height := header.custom_minimum_size.y
	var fish_icon := _currency_pill.find_child("FishSymbol", true, false) as TextureRect
	fish_icon.custom_minimum_size = Vector2(header_height * (0.40 if portrait else 0.60), header_height * (0.36 if portrait else 0.48))
	var balance := _currency_pill.find_child("FishAmount", true, false) as Label
	balance.add_theme_font_size_override("font_size", roundi(header_height * (0.28 if portrait else 0.35)))
	# The phone cap includes a compact spendable balance; its accessible name
	# retains the exact amount when thousands need abbreviation.
	balance.visible = true
	_currency_pill.tooltip_text = "%s fish" % ExpeditionMenuStyle.grouped_amount(Progression.get_fish())
	_currency_pill.accessibility_name = _currency_pill.tooltip_text
	_currency_pill.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_currency_pill.offset_left = -112.0
	_currency_pill.offset_top = 8.0
	_currency_pill.offset_right = 0.0
	_currency_pill.offset_bottom = header_height * 0.82
	header.add_child(_currency_pill)
	var header_art := header.find_child("ApprovedTitleArtwork", true, false) as TextureRect
	if header_art != null:
		header_art.hide()
	var title_row := HBoxContainer.new()
	title_row.name = "PenguinsReferenceTitle"
	title_row.set_anchors_preset(Control.PRESET_CENTER_TOP)
	var title_width := _profile.safe_rect.size.x * (0.53 if portrait else 0.32)
	title_row.offset_left = -title_width * 0.5
	title_row.offset_right = title_width * 0.5
	title_row.offset_bottom = header_height
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 5)
	header.add_child(title_row)
	var title_icon := TextureRect.new()
	title_icon.texture = ExpeditionMenuStyle._material_texture(
		"res://assets/art/ui/menu/home_profile_icon_exact_v1.webp")
	title_icon.custom_minimum_size = Vector2.ONE * header_height * 0.88
	title_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title_row.add_child(title_icon)
	var title_text := ExpeditionMenuStyle.label("PENGUINS", roundi(header_height * (0.50 if portrait else 0.70)))
	title_text.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	title_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	title_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(title_text)
	_position_currency_pill.call_deferred()
	var hero_host: VBoxContainer = content
	if portrait:
		# Only wardrobe choices scroll on phones. Landscape keeps the whole
		# composition scrollable, since its short height cannot hold a fixed hero.
		var page := scroll.get_parent() as VBoxContainer
		page.add_theme_constant_override("separation", 12)
		var fixed := VBoxContainer.new()
		fixed.name = "FixedPenguinStage"
		fixed.add_theme_constant_override("separation", 8)
		page.add_child(fixed)
		page.move_child(fixed, scroll.get_index())
		hero_host = fixed
	_fish_label = _currency_pill.find_child("FishAmount", true, false) as Label
	_outfit_stage = OUTFIT_PREVIEW.new()
	_outfit_stage.library = _outfit_library
	# Reserve card minima and their selection halo, including layout rounding
	# at the 800x1422 phone canvas, before the fixed dots and try-on footer.
	# Larger accessibility text can still use the wardrobe scroller.
	_outfit_stage.custom_minimum_size.y = _profile.safe_rect.size.y * (0.44 if portrait else 0.435)
	_outfit_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if portrait:
		hero_host.add_child(_outfit_stage)
	else:
		var art_stage := shell["art_stage"] as Control
		art_stage.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		art_stage.custom_minimum_size.x = _profile.safe_rect.size.x * 0.455
		_outfit_stage.custom_minimum_size = Vector2.ZERO
		_outfit_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
		_outfit_stage.offset_top = -_profile.safe_rect.size.y * 0.025
		_outfit_stage.offset_bottom = -_profile.safe_rect.size.y * 0.09
		art_stage.add_child(_outfit_stage)
	_build_detail_bar(hero_host)
	var detail_card := hero_host.get_child(hero_host.get_child_count() - 1) as Control
	_compact_detail_card(detail_card, portrait)
	_build_wardrobe(content, portrait)
	# The finished image is always the preview. Selecting a card does not
	# purchase or equip anything, including across multiple category tabs.
	set_process(false)
	_recolor_labels(detail_card)
	ExpeditionMenuStyle.style_button(_detail_action, true, _f(23))
	_detail_action.add_theme_font_size_override("font_size", roundi(_profile.safe_rect.size.y * (0.029 if portrait else 0.056)))
	_detail_action.resized.connect(_fit_detail_action)
	# Equipped is a real disabled state, but retains the reference's coral
	# action treatment. Ownership text remains truthful.
	_detail_action.add_theme_stylebox_override("disabled",
		ExpeditionMenuStyle.material_box(true, 10.0, 4.0))
	_detail_action.add_theme_color_override("font_disabled_color", Color.WHITE)
	_current_category = category
	_select_category(category)
	if (selected.is_empty() and category != "body") or String(CosmeticsDB.get_item(selected).get(
			"category", "")) == category:
		_select_item(selected)
	_refresh_loadout()
	_update_fish_label(Progression.get_fish())
	_refresh_preview()
	UtilityScreenLayout.defer_header_alignment(self, title_row,
		shell["back"] as Control, [_currency_pill])


func _compact_detail_card(card: Control, portrait: bool) -> void:
	_detail_swatch.hide()
	_detail_desc.hide()
	var old_stack := card.get_child(0)
	var layout := Control.new()
	layout.name = "ReferenceEquipLayout"
	var height := _profile.safe_rect.size.y * (0.105 if portrait else 0.21)
	layout.custom_minimum_size.y = height
	card.add_child(layout)
	card.name = "ReferenceEquipPanel"
	card.custom_minimum_size = Vector2(_profile.safe_rect.size.x * (0.52 if portrait else 0.43), height)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER if portrait else Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", StyleBoxEmpty.new() if portrait
		else ExpeditionMenuStyle.material_card(10.0, 3.0))
	var name_plate := PanelContainer.new()
	name_plate.name = "OutfitNamePlate"
	name_plate.set_anchors_preset(Control.PRESET_TOP_WIDE)
	name_plate.offset_bottom = height * (0.59 if portrait else 0.47)
	name_plate.add_theme_stylebox_override("panel", ExpeditionMenuStyle.material_box(false, 8.0, 2.0)
		if portrait else StyleBoxEmpty.new())
	layout.add_child(name_plate)
	_detail_name.reparent(name_plate)
	_detail_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_detail_name.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_name.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	_detail_name.add_theme_font_size_override("font_size", roundi(_profile.safe_rect.size.y * (0.030 if portrait else 0.074)))
	_detail_name.resized.connect(_fit_detail_name)
	name_plate.resized.connect(_fit_detail_name)
	_detail_action.reparent(layout)
	_detail_action.name = "OutfitEquipAction"
	_detail_action.clip_text = true
	_detail_action.custom_minimum_size = Vector2(0, height * (0.54 if portrait else 0.44))
	_detail_action.anchor_left = 0.095 if portrait else 0.18
	_detail_action.anchor_right = 0.905 if portrait else 0.82
	_detail_action.anchor_top = 0.46 if portrait else 0.49
	_detail_action.anchor_bottom = 1.0 if portrait else 0.94
	_detail_action.set_offset(SIDE_LEFT, 0)
	_detail_action.set_offset(SIDE_RIGHT, 0)
	_detail_action.set_offset(SIDE_TOP, 0)
	_detail_action.set_offset(SIDE_BOTTOM, 0)
	# Base selection still updates these metadata controls.
	_detail_swatch.reparent(layout)
	_detail_desc.reparent(layout)
	old_stack.queue_free()


func _refresh_preview() -> void:
	if _outfit_stage == null:
		return
	_previewed_equipped = _preview_equipped()
	_outfit_stage.show_equipped(_previewed_equipped)
	_update_try_on_note()


func _preview_equipped() -> Dictionary:
	return _try_on_loadout.duplicate(true)


func _update_try_on_note() -> void:
	if _try_on_note == null:
		return
	var changed := 0
	for category: String in CosmeticsDB.CATEGORIES:
		changed += int(String(_try_on_loadout.get(category, "")) != Progression.get_equipped(category))
	_try_on_note.text = "EQUIPPED OUTFIT" if changed == 0 else "TRY-ON · %d %s" % [changed, "ITEM" if changed == 1 else "ITEMS"]
	_try_on_note.tooltip_text = "Your saved outfit." if changed == 0 else "Temporary preview: %d unequipped %s. Use Equip to save each item." % [changed, "item" if changed == 1 else "items"]
	if not _purchase_error.is_empty():
		_try_on_note.text = _purchase_error
		_try_on_note.tooltip_text = _purchase_error
	_try_on_note.accessibility_name = _try_on_note.tooltip_text
	_try_on_note.add_theme_color_override("font_color", ExpeditionMenuStyle.INK if _purchase_error.is_empty() else Color("962d2d"))
	_reset_try_on_button.disabled = changed == 0


func _reset_try_on() -> void:
	_purchase_error = ""
	_try_on_loadout = Progression.equipped().duplicate(true)
	_select_category(_current_category)


func _on_outfit_preview_changed(_key: String, _texture: Texture2D, _state: String) -> void:
	if _detail_action != null:
		# Re-evaluate cost/ownership only after the selected illustration is
		# ready. _select_item reuses the same key, so this does not load again.
		_update_selected_item(_selected_id, false)


func _category_icon(category: String) -> Texture2D:
	if category == "none":
		return _cached_icon(_swatch_svg(""))
	var atlas := ExpeditionMenuStyle._material_texture(CATEGORY_ATLAS)
	if atlas == null:
		return null
	var texture := AtlasTexture.new()
	texture.atlas = atlas
	var region: Rect2 = CATEGORY_REGIONS.get(category, CATEGORY_REGIONS["body"])
	var scale := atlas.get_size() / Vector2(2172, 724)
	texture.region = Rect2(region.position * scale, region.size * scale)
	texture.filter_clip = true
	return texture


func _portrait_texture(body_id: String) -> Texture2D:
	var portrait_path := String(PORTRAIT_BY_BODY.get(body_id,
		"emperor_portrait_v1.webp"))
	return ExpeditionMenuStyle._material_texture(
		"res://assets/art/ui/menu/%s" % portrait_path)


func _select_item(id: String) -> void:
	_update_selected_item(id, true)


func _update_selected_item(id: String, reveal_card: bool) -> void:
	if (id.is_empty() and _current_category == "body") or (not id.is_empty() and String(CosmeticsDB.get_item(id).get("category", "")) != _current_category):
		return
	if id != _selected_id:
		_purchase_error = ""
	_try_on_loadout[_current_category] = id
	super._select_item(id)
	if _detail_name != null:
		_detail_name.text = _detail_name.text.to_upper()
		_fit_detail_name()
		_detail_action.text = _detail_action.text.to_upper()
		if id.is_empty() and not _detail_action.disabled:
			_detail_action.text = "REMOVE"
		if _outfit_library != null and _outfit_library.state != "ready":
			_detail_action.disabled = true
			_detail_action.text = "LOADING PREVIEW" if _outfit_library.state == "loading" else "PREVIEW UNAVAILABLE"
		_detail_action.accessibility_name = _detail_action.text
		_fit_detail_action()
	if _item_grid != null:
		for tile: Button in _item_grid.get_children():
			var rim := tile.get_node_or_null("EquippedRim") as Control
			if rim != null:
				var surface := rim.get_theme_stylebox("panel") as SELECTION_SURFACE
				surface.selected = String(tile.get_meta("cosmetic_id", "")) == id
				rim.queue_redraw()
	if _detail_swatch != null and PORTRAIT_BY_BODY.has(id):
		_detail_swatch.texture = _portrait_texture(id)
	if reveal_card:
		_gallery_reveal_revision += 1
		_reveal_selected_card.call_deferred(id, _current_category, _gallery_reveal_revision)


func _reveal_selected_card(id: String, category: String, revision: int) -> void:
	# New category tiles need their container widths before paging. A newer
	# selection or explicit page arrow invalidates this pending reveal.
	for _frame: int in 2:
		if not is_inside_tree():
			return
		await get_tree().process_frame
	if revision != _gallery_reveal_revision or category != _current_category or id != _selected_id:
		return
	var tile := _tile_for_id(id)
	if tile == null or _gallery_scroll == null:
		return
	if not _gallery_scroll.get_global_rect().grow(1.0).encloses(tile.get_global_rect()):
		_set_gallery_page(tile.get_index() / 3)


func _fit_detail_name() -> void:
	if _detail_name == null or _profile == null or _detail_name.size.x <= 0.0:
		return
	# Tall phones need a width constraint as well as the authored height scale.
	# Keep the entire item name, including the widest hats/trails, inside its pill.
	var font := _detail_name.get_theme_font("font")
	var available_width := maxf(1.0, _detail_name.size.x - 16.0)
	var plate := _detail_name.get_parent() as PanelContainer
	if plate == null or plate.size.y <= 0.0:
		return
	var available_height := (plate.size.y - plate.get_theme_stylebox("panel").get_minimum_size().y) * 0.90
	var font_size := maxi(1, roundi(_profile.safe_rect.size.y * (0.030 if _profile.is_portrait() else 0.074)))
	while font_size > 1 and (font.get_string_size(_detail_name.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > available_width
			or font.get_height(font_size) > available_height):
		font_size -= 1
	_detail_name.add_theme_font_size_override("font_size", font_size)


func _fit_detail_action() -> void:
	if _detail_action == null or _profile == null or _detail_action.size.x <= 0.0:
		return
	var portrait := _profile.is_portrait()
	var short_action := _detail_action.text in ["EQUIP", "EQUIPPED", "REMOVE"]
	var preferred := roundi(_profile.safe_rect.size.y * (
		(0.029 if portrait else 0.056) if short_action else (0.021 if portrait else 0.033)))
	var font := _detail_action.get_theme_font("font")
	var available_width := _detail_action.size.x * 0.82
	var available_height := _detail_action.size.y * 0.68
	var font_size := maxi(1, preferred)
	while font_size > 1 and (font.get_string_size(_detail_action.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > available_width
			or font.get_height(font_size) > available_height):
		font_size -= 1
	_detail_action.add_theme_font_size_override("font_size", font_size)


func _open_buy_dialog(id: String, category: String, item_name: String, cost: int) -> void:
	super._open_buy_dialog(id, category, item_name, cost)
	_recolor_labels(_buy_dialog)
	for panel: PanelContainer in _buy_dialog.find_children("*", "PanelContainer", true, false):
		panel.add_theme_stylebox_override("panel", ExpeditionMenuStyle.material_card(20, 18))
	for button: Button in _buy_dialog.find_children("*", "Button", true, false):
		ExpeditionMenuStyle.style_button(button, button.text == "Buy", _f(22))


func _on_item_pressed(id: String) -> void:
	if _outfit_library == null or _outfit_library.state != "ready" or id != _selected_id:
		return
	super._on_item_pressed(id)


func _commit_buy(id: String, _category: String) -> void:
	# Buying grants ownership. Wearing it is a separate, clearly labelled
	# action; neither browsing nor the purchase confirmation changes loadout.
	_close_buy_dialog()
	_purchase_error = ""
	if not Progression.try_unlock_cosmetic(id):
		_purchase_error = "Not enough fish. Outfit remains a try-on."
	_select_item(id)


func _update_fish_label(total: int) -> void:
	super._update_fish_label(total)
	if _fish_label != null:
		_fish_label.text = _compact_fish_amount(total) if _profile.is_portrait() else ExpeditionMenuStyle.grouped_amount(total)
	if _currency_pill != null:
		_currency_pill.tooltip_text = "%s fish" % ExpeditionMenuStyle.grouped_amount(total)
		_currency_pill.accessibility_name = _currency_pill.tooltip_text
	_position_currency_pill.call_deferred()


static func _compact_fish_amount(total: int) -> String:
	if total < 1000:
		return str(total)
	if total < 1000000:
		return "%sK" % ("%.1f" % (float(total) / 1000.0)).trim_suffix(".0")
	return "%sM" % ("%.1f" % (float(total) / 1000000.0)).trim_suffix(".0")


func _position_currency_pill() -> void:
	if _currency_pill == null or not is_instance_valid(_currency_pill):
		return
	var width := _currency_pill.get_combined_minimum_size().x
	_currency_pill.offset_left = -width
	_currency_pill.offset_right = 0.0


func _build_wardrobe(parent: BoxContainer, portrait: bool) -> void:
	var wardrobe_parent: Control = parent
	if not portrait:
		var enclosure := ExpeditionMenuStyle.panel(parent)
		enclosure.name = "WardrobeEnclosure"
		enclosure.add_theme_stylebox_override("panel", ExpeditionMenuStyle.material_card(
			_profile.safe_rect.size.x * 0.009, _profile.safe_rect.size.y * 0.025))
		wardrobe_parent = enclosure
	var wardrobe := VBoxContainer.new()
	wardrobe.name = "WardrobeChoices"
	wardrobe.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wardrobe.add_theme_constant_override("separation", 10)
	wardrobe_parent.add_child(wardrobe)
	var tab_shelf := ExpeditionMenuStyle.panel(wardrobe)
	tab_shelf.name = "WardrobeCategoryShelf"
	# End-cap selections follow the ivory shelf, with a visible ivory gutter.
	tab_shelf.add_theme_stylebox_override("panel", ExpeditionMenuStyle.material_box(false,
		_profile.safe_rect.size.x * 0.016, _profile.safe_rect.size.y * 0.007) if portrait else StyleBoxEmpty.new())
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", _gap(4))
	tab_shelf.add_child(tab_row)
	var category_scroll := ScrollContainer.new()
	category_scroll.name = "WardrobeCategoryScroll"
	category_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	category_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	category_scroll.custom_minimum_size.y = _v(66.0) if portrait else _v(54.0)
	category_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	TouchScroll.attach(category_scroll)
	tab_row.add_child(category_scroll)
	var tabs := HBoxContainer.new()
	tabs.name = "WardrobeCategories"
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_theme_constant_override("separation", 0)
	category_scroll.add_child(tabs)
	for category: String in ["body", "hat", "goggles", "scarf", "trail"]:
		var tab := Button.new()
		tab.name = "Category_%s" % category
		tab.custom_minimum_size.x = _profile.safe_rect.size.x * (0.18 if portrait else 0.075)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.toggle_mode = true
		tab.add_theme_font_override("font", UITheme.bold_font())
		UITheme.hook_sounds(tab)
		tab.pressed.connect(_select_category.bind(category))
		tabs.add_child(tab)
		var tab_content := VBoxContainer.new()
		tab_content.set_anchors_preset(Control.PRESET_FULL_RECT)
		var tab_inset := _profile.safe_rect.size.y * (0.006 if portrait else 0.007)
		tab_content.offset_top = tab_inset
		tab_content.offset_bottom = -tab_inset
		tab_content.alignment = BoxContainer.ALIGNMENT_CENTER
		tab_content.add_theme_constant_override("separation", 3)
		tab_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tab.add_child(tab_content)
		var category_icon := TextureRect.new()
		category_icon.name = "CategoryIcon"
		category_icon.texture = _category_icon(category)
		category_icon.custom_minimum_size.y = _profile.safe_rect.size.y * (0.033 if portrait else 0.050)
		category_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		category_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		category_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tab_content.add_child(category_icon)
		var category_label := ExpeditionMenuStyle.label(String(
			"Penguin" if category == "body" and portrait else CosmeticsDB.CATEGORY_NAMES[category]).to_upper(), roundi(_profile.safe_rect.size.y * (0.015 if portrait else 0.023)), ExpeditionMenuStyle.INK)
		category_label.name = "CategoryLabel"
		category_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		category_label.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
		category_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		category_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tab_content.add_child(category_label)
		# Button does not derive a minimum from its manually anchored children.
		# Reserve their full icon/label stack and both insets inside the shelf.
		tab.custom_minimum_size.y = tab_content.get_combined_minimum_size().y + tab_inset * 2.0
		_tab_buttons[category] = tab
		if category != "trail":
			var divider_host := Control.new()
			divider_host.custom_minimum_size.x = 1.0
			divider_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tabs.add_child(divider_host)
			var divider := ColorRect.new()
			divider.name = "CategoryDivider"
			divider.color = Color("ded5c5")
			divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
			divider.anchor_top = 0.12
			divider.anchor_bottom = 0.88
			divider.offset_right = 1.0
			divider_host.add_child(divider)
	var gallery := HBoxContainer.new()
	gallery.name = "WardrobeCarousel"
	gallery.add_theme_constant_override("separation", _gap(5))
	wardrobe.add_child(gallery)
	var arrow_extent := maxf(_profile.safe_rect.size.x * (0.065 if portrait else 0.025),
		48.0 * _profile.viewport_size.x / maxf(1.0, float(get_window().size.x)))
	for direction: int in [-1, 1]:
		if direction == 1:
			_gallery_scroll = ScrollContainer.new()
			_gallery_scroll.name = "WardrobeGalleryScroll"
			_gallery_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
			_gallery_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			_gallery_scroll.follow_focus = true
			_gallery_scroll.scroll_started.connect(func() -> void:
				# A pending keyboard/selection reveal must not undo a finger swipe.
				_gallery_reveal_revision += 1)
			_gallery_scroll.resized.connect(_layout_gallery_tiles)
			_gallery_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_gallery_scroll.custom_minimum_size.y = _profile.safe_rect.size.y * (0.155 if portrait else 0.30)
			TouchScroll.attach(_gallery_scroll)
			gallery.add_child(_gallery_scroll)
			_gallery_inset = MarginContainer.new()
			_gallery_inset.name = "WardrobeSelectionHaloSpace"
			for side: String in ["left", "right", "top", "bottom"]:
				_gallery_inset.add_theme_constant_override("margin_%s" % side, 10)
			_gallery_scroll.add_child(_gallery_inset)
			_item_grid = GridContainer.new()
			_item_grid.name = "WardrobeItems"
			_item_grid.columns = 99
			_item_grid.add_theme_constant_override("h_separation", _gap(8))
			_gallery_inset.add_child(_item_grid)
		var arrow := ExpeditionMenuStyle.back_button(arrow_extent)
		arrow.name = "PreviousPenguins" if direction < 0 else "NextPenguins"
		arrow.accessibility_name = "Previous wardrobe choices" if direction < 0 else "Next wardrobe choices"
		arrow.custom_minimum_size = Vector2(arrow_extent, maxf(arrow_extent, _profile.safe_rect.size.y * 0.07))
		arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		arrow.icon = null
		var arrow_art := TextureRect.new()
		arrow_art.name = "PaintedGalleryArrow"
		arrow_art.texture = ExpeditionMenuStyle.wardrobe_sprite("back")
		arrow_art.flip_h = direction > 0
		arrow_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		arrow_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		arrow_art.set_anchors_preset(Control.PRESET_FULL_RECT)
		arrow_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		arrow.add_child(arrow_art)
		arrow.pressed.connect(_page_gallery.bind(direction))
		gallery.add_child(arrow)
	_gallery_dots = HBoxContainer.new()
	_gallery_dots.name = "WardrobePages"
	_gallery_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	_gallery_dots.add_theme_constant_override("separation", _gap(8))
	wardrobe.add_child(_gallery_dots)
	_build_try_on_footer(wardrobe, portrait)
	if portrait:
		# Keep pagination and Reset outside the clipped item scroller. Reserve
		# both rows so page dots cannot be reduced to a sliver above the footer.
		var fixed_page := parent.get_parent().get_parent()
		_gallery_dots.reparent(fixed_page)
		var footer := wardrobe.get_node("TryOnFooterInset")
		footer.reparent(fixed_page)
	_gallery_scroll.get_h_scroll_bar().value_changed.connect(func(_value: float) -> void:
		_update_gallery_dots())


func _build_try_on_footer(parent: Control, portrait: bool) -> void:
	var inset := MarginContainer.new()
	inset.name = "TryOnFooterInset"
	for side: String in ["left", "right"]:
		inset.add_theme_constant_override("margin_%s" % side,
			roundi(_profile.safe_rect.size.x * (0.04 if portrait else 0.004)))
	parent.add_child(inset)
	var plate := PanelContainer.new()
	plate.name = "TryOnFooter"
	plate.add_theme_stylebox_override("panel", ExpeditionMenuStyle.material_box(false,
		_profile.safe_rect.size.x * (0.025 if portrait else 0.012), _profile.safe_rect.size.y * 0.008))
	inset.add_child(plate)
	var row := HBoxContainer.new()
	row.name = "TemporaryTryOnStatus"
	row.add_theme_constant_override("separation", roundi(_profile.safe_rect.size.x * (0.018 if portrait else 0.010)))
	plate.add_child(row)
	var hanger := TextureRect.new()
	hanger.name = "TryOnHanger"
	hanger.texture = _cached_icon(TRY_ON_ICON_SVG)
	hanger.custom_minimum_size = Vector2.ONE * _profile.safe_rect.size.y * (0.023 if portrait else 0.045)
	hanger.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hanger.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hanger.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hanger)
	_try_on_note = ExpeditionMenuStyle.label("", roundi(_profile.safe_rect.size.y * (0.0145 if portrait else 0.022)))
	_try_on_note.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	_try_on_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_try_on_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_try_on_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_try_on_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_try_on_note.custom_minimum_size.y = _profile.safe_rect.size.y * (0.032 if portrait else 0.050)
	row.add_child(_try_on_note)
	var divider := VSeparator.new()
	divider.name = "TryOnResetDivider"
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(divider)
	_reset_try_on_button = ExpeditionMenuStyle.button("RESET", false, roundi(_profile.safe_rect.size.y * (0.0145 if portrait else 0.022)), 0.0)
	_reset_try_on_button.custom_minimum_size.y = maxf(44.0,
		_profile.safe_rect.size.y * (0.032 if portrait else 0.050))
	_reset_try_on_button.name = "ResetTryOn"
	_reset_try_on_button.custom_minimum_size.x = _profile.safe_rect.size.x * (0.13 if portrait else 0.065)
	_reset_try_on_button.tooltip_text = "Return preview to your equipped outfit. No purchases or equipment changes."
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		_reset_try_on_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_reset_try_on_button.add_theme_color_override("font_disabled_color", ExpeditionMenuStyle.INK_MUTED)
	_reset_try_on_button.pressed.connect(_reset_try_on)
	row.add_child(_reset_try_on_button)


func _layout_gallery_tiles() -> void:
	if _gallery_scroll == null or _item_grid == null or _gallery_inset == null:
		return
	var pad := ceili(_gallery_scroll.size.x / 3.0 * 0.055)
	for side: String in ["left", "right", "top", "bottom"]:
		_gallery_inset.add_theme_constant_override("margin_%s" % side, pad)
	var tile_width := maxf(1.0, (_gallery_scroll.size.x - float(pad * 2 + _gap(8) * 2)) / 3.0)
	for tile: Control in _item_grid.get_children():
		tile.custom_minimum_size.x = tile_width
		_fit_item_contents(tile)


func _fit_item_contents(tile: Control) -> void:
	if not is_instance_valid(tile) or tile.size.x <= 0.0 or tile.size.y <= 0.0:
		return
	var stack := tile.get_node_or_null("ItemContent") as VBoxContainer
	if stack == null:
		return
	var short_side := minf(tile.size.x, tile.size.y)
	var inset := ceilf(short_side * 0.064)
	stack.offset_left = inset
	stack.offset_right = -inset
	stack.offset_top = inset
	stack.offset_bottom = -inset
	var card := tile.get_theme_stylebox("normal") as StyleBoxFlat
	card.set_corner_radius_all(roundi(short_side * (0.18 if _profile.is_portrait() else 0.13)))
	tile.custom_minimum_size.y = maxf(float(tile.get_meta("reference_card_height")),
		stack.get_combined_minimum_size().y + inset * 2.0)


func _update_portrait_mask(icon_id: int, tile_id: int, portrait: bool) -> void:
	# A category/orientation rebuild may retire a card before deferred layout.
	# IDs avoid capturing freed Nodes in a lambda even before its body runs.
	var icon := instance_from_id(icon_id) as TextureRect
	var tile := instance_from_id(tile_id) as Control
	if icon == null or tile == null or icon.is_queued_for_deletion() or tile.is_queued_for_deletion():
		return
	var stack := icon.get_parent() as Control
	var mask := icon.material as ShaderMaterial
	if stack == null or mask == null:
		return
	mask.set_shader_parameter("card_size", icon.size)
	mask.set_shader_parameter("corner_radius", maxf(1.0, minf(tile.size.x, tile.size.y) * (0.18 if portrait else 0.13) - stack.offset_left))


func _page_gallery(direction: int) -> void:
	_gallery_reveal_revision += 1
	# Preserve the existing arrow step even after a partial touch swipe.
	_scroll_gallery_to(_gallery_scroll.scroll_horizontal + roundi(_gallery_scroll.size.x) * direction)


func _set_gallery_page(page: int) -> void:
	var pages := maxi(1, ceili(float(_item_grid.get_child_count()) / 3.0))
	_scroll_gallery_to(roundi(_gallery_scroll.size.x) * clampi(page, 0, pages - 1))


func _scroll_gallery_to(offset: int) -> void:
	_gallery_scroll.scroll_horizontal = offset


func _update_gallery_dots() -> void:
	if _gallery_dots == null or _gallery_scroll == null or _item_grid == null:
		return
	for child in _gallery_dots.get_children():
		child.queue_free()
	var pages := maxi(1, ceili(float(_item_grid.get_child_count()) / 3.0))
	# The last page may contain fewer than three cards, so its scroll anchor
	# is clamped before a full viewport step (four cards end at ~1/3 width).
	var bar := _gallery_scroll.get_h_scroll_bar()
	var end := maxf(0.0, bar.max_value - bar.page)
	var page := 0
	var nearest := INF
	for index: int in pages:
		var anchor := minf(float(index) * _gallery_scroll.size.x, end)
		var distance := absf(float(_gallery_scroll.scroll_horizontal) - anchor)
		if distance < nearest:
			nearest = distance
			page = index
	for index: int in pages:
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2.ONE * _profile.safe_rect.size.y * 0.012
		dot.add_theme_stylebox_override("panel", ExpeditionMenuStyle.surface(
			ExpeditionMenuStyle.CORAL if index == page else Color("91a9c4"), 20, false))
		_gallery_dots.add_child(dot)


func _make_card(parent: Control, pad: float = 16.0) -> PanelContainer:
	var panel := ExpeditionMenuStyle.panel(parent,
		Color(ExpeditionMenuStyle.IVORY, 0.97))
	var style := panel.get_theme_stylebox("panel")
	style.content_margin_left = _u(pad)
	style.content_margin_right = _u(pad)
	style.content_margin_top = _u(pad * 0.8)
	style.content_margin_bottom = _u(pad * 0.8)
	return panel


func _select_category(category: String) -> void:
	_current_category = category
	for key: String in _tab_buttons.keys():
		(_tab_buttons[key] as Button).set_pressed_no_signal(key == category)
	_rebuild_items()
	_select_item(String(_try_on_loadout.get(category, Progression.get_equipped(category))))
	if _gallery_scroll != null:
		_gallery_scroll.scroll_horizontal = 0
		_update_gallery_dots.call_deferred()
		_layout_gallery_tiles.call_deferred()
	for key: String in _tab_buttons.keys():
		var tab := _tab_buttons[key] as Button
		_style_category_tab(tab, key == category)


func _style_category_tab(tab: Button, selected: bool) -> void:
	var portrait := _profile != null and _profile.is_portrait()
	var size := maxi(_f(18), 15 if portrait else 18)
	var height := _profile.safe_rect.size.y * (0.071 if portrait else 0.102)
	tab.custom_minimum_size.y = maxf(height, tab.custom_minimum_size.y)
	tab.add_theme_font_size_override("font_size", size)
	for state: String in ["normal", "pressed", "hover_pressed", "hover"]:
		tab.add_theme_stylebox_override(state, _category_selected_surface(String(tab.name).trim_prefix("Category_"))
			if selected else StyleBoxEmpty.new())
	var ink := Color.WHITE if selected else ExpeditionMenuStyle.INK
	var category_label := tab.find_child("CategoryLabel", true, false) as Label
	if category_label != null:
		category_label.add_theme_color_override("font_color", ink)
	for state: String in ["font_color", "font_pressed_color",
			"font_hover_color", "font_hover_pressed_color"]:
		tab.add_theme_color_override(state, ink)
	tab.add_theme_stylebox_override("focus", StyleBoxEmpty.new() if UITheme.is_touch()
		else _category_focus())


func _category_selected_surface(category: String) -> StyleBox:
	var surface := CATEGORY_SURFACE.new()
	surface.category = category
	surface.portrait = _profile != null and _profile.is_portrait()
	return surface


func _category_focus() -> StyleBoxFlat:
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = ExpeditionMenuStyle.GOLD
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(24)
	return focus


func _refresh_loadout() -> void:
	super._refresh_loadout()
	if _loadout_box != null:
		_recolor_labels(_loadout_box)


func _make_item_tile(id: String) -> Button:
	var none := id.is_empty()
	var info := CosmeticsDB.get_item(id) if not none else {}
	var owned := none or Progression.is_cosmetic_unlocked(id)
	var equipped := Progression.get_equipped(_current_category) == id
	var portrait := _profile.is_portrait()
	var tile_width := _profile.safe_rect.size.x * (0.243 if portrait else 0.122)
	var tile_height := _profile.safe_rect.size.y * (0.145 if portrait else 0.28)
	var tile := ExpeditionMenuStyle.button("", false, _f(18), tile_height)
	tile.custom_minimum_size.x = tile_width
	var card := StyleBoxFlat.new()
	card.bg_color = Color("fffaf0")
	card.set_corner_radius_all(roundi(tile_width * (0.18 if portrait else 0.13)))
	card.anti_aliasing = true
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		tile.add_theme_stylebox_override(state, card)
	tile.set_meta("cosmetic_id", id)
	tile.set_meta("reference_card_height", tile_height)
	tile.tooltip_text = "Preview no accessory" if none else "Preview %s" % String(info.get("name", id))
	tile.accessibility_name = tile.tooltip_text
	# Every card owns one reusable selection rim. Updating selection never
	# rebuilds the entire grid or accidentally highlights the None entry gold.
	var rim := Panel.new()
	rim.name = "EquippedRim"
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var line := SELECTION_SURFACE.new()
	line.portrait = portrait
	line.selected = id == _selected_id
	rim.add_theme_stylebox_override("panel", line)
	# Added after content below, so its white/coral bands stay above the image.
	tile.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var stack := VBoxContainer.new()
	stack.name = "ItemContent"
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.offset_left = _u(5.0)
	stack.offset_right = -_u(5.0)
	stack.offset_top = _v(6.0)
	stack.offset_bottom = -_v(6.0)
	stack.add_theme_constant_override("separation", _gap(6))
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(stack)
	var icon := TextureRect.new()
	icon.name = "ItemPortrait"
	icon.texture = _category_icon("none") if none else (
		_portrait_texture(id) if PORTRAIT_BY_BODY.has(id) \
		else ExpeditionMenuStyle.wardrobe_sprite(id))
	if String(info.get("category", "")) == "trail":
		# The card, animated preview and equipped trail share one authored design.
		icon.texture = TrailEffect._particle_texture(id)
	if icon.texture == null:
		icon.texture = _cached_icon(_swatch_svg(id))
	icon.custom_minimum_size = Vector2(0.0, tile_height * (0.86 if portrait else 0.56))
	if portrait:
		icon.custom_minimum_size.y = 0.0
		icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE if PORTRAIT_BY_BODY.has(id) else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.clip_contents = true
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(icon)
	if PORTRAIT_BY_BODY.has(id):
		var mask := ShaderMaterial.new()
		mask.shader = PORTRAIT_MASK
		mask.set_shader_parameter("source_size", icon.texture.get_size())
		icon.material = mask
		var update_mask := _update_portrait_mask.bind(icon.get_instance_id(), tile.get_instance_id(), portrait)
		icon.resized.connect(update_mask)
		update_mask.call_deferred()
	var sky := Panel.new()
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.show_behind_parent = true
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sky_style := StyleBoxFlat.new()
	sky_style.bg_color = Color("c5e3f8")
	sky_style.set_corner_radius_all(18)
	sky.add_theme_stylebox_override("panel", sky_style)
	if not PORTRAIT_BY_BODY.has(id):
		icon.add_child(sky)
	else:
		sky.free()
	var name := ExpeditionMenuStyle.label("None" if none else String(info.get(
		"name", id)), roundi(_profile.safe_rect.size.y * 0.032), ExpeditionMenuStyle.INK)
	name.autowrap_mode = TextServer.AUTOWRAP_OFF
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.visible = not portrait
	name.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(name)
	var state := "EQUIPPED" if equipped else (
		"OWNED" if owned else ExpeditionMenuStyle.grouped_amount(int(info.get("cost", 0))))
	var badge := PanelContainer.new()
	badge.name = "ItemStatusBadge"
	badge.visible = not portrait
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_style := ExpeditionMenuStyle.surface(
		Color("278859") if owned else Color("267dc2"), 18, false)
	badge_style.content_margin_left = _u(12.0)
	badge_style.content_margin_right = _u(12.0)
	badge_style.content_margin_top = _v(5.0)
	badge_style.content_margin_bottom = _v(5.0)
	badge.add_theme_stylebox_override("panel", badge_style)
	stack.add_child(badge)
	var status_row := HBoxContainer.new()
	status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(status_row)
	if not owned:
		var fish := TextureRect.new()
		fish.texture = ExpeditionMenuStyle._material_texture(
			"res://assets/art/ui/menu/home_fish_symbol_clean_v2.png")
		fish.custom_minimum_size = Vector2(_u(29.0), _v(23.0))
		fish.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fish.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		fish.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status_row.add_child(fish)
	var caption := ExpeditionMenuStyle.label(state, roundi(_profile.safe_rect.size.y * 0.025),
		Color.WHITE)
	caption.autowrap_mode = TextServer.AUTOWRAP_OFF
	caption.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_row.add_child(caption)
	tile.custom_minimum_size.y = maxf(tile.custom_minimum_size.y,
		stack.get_combined_minimum_size().y + _v(12.0))
	tile.add_child(rim)
	tile.resized.connect(_fit_item_contents.bind(tile))
	# Pointer movement must not rebuild the rig or silently change the try-on.
	# Click/tap selects; keyboard focus remains a useful accessible preview.
	tile.focus_entered.connect(func() -> void:
		# Touch focus arrives on finger-down, before a swipe can be identified.
		# Select on the eventual tap release; keyboard focus still previews.
		if not GameConfig.has_touchscreen():
			_select_item(id))
	tile.pressed.connect(func() -> void: _select_item(id))
	return tile


func _recolor_labels(node: Node) -> void:
	if node is Label:
		var label_node := node as Label
		label_node.add_theme_color_override("font_color", ExpeditionMenuStyle.INK)
		label_node.add_theme_color_override("font_outline_color", Color.TRANSPARENT)
		label_node.add_theme_constant_override("outline_size", 0)
	for child in node.get_children():
		_recolor_labels(child)
