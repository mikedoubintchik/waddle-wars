class_name PremiumCosmeticShop
extends "res://scripts/commerce/cosmetic_shop.gd"
## New storefront; reuses CosmeticShop's commerce/auth state machine and
## purchase methods, but owns an art-led responsive view from scratch.

# Newly added helpers must also load in an already-running checkout whose
# global script-class cache predates the helper.
const DetailStyle = preload("res://scripts/ui/menu_detail_style.gd")
const SceneBackground = preload("res://scripts/ui/menu_composition_background.gd")

var _page: Control = null
var _selected_product_id: String = ""
var _detail_cards: Dictionary = {}
var _selector_buttons: Dictionary = {}
var _selected_banner: Label = null
var _tile_width: float = 290.0
var _purchase_rows: Dictionary = {}
var _purchase_footer: VBoxContainer = null
var _portrait_page := false
var _purchase_info: Control = null
var _fish_buttons: Dictionary = {}
var _fish_prices: Dictionary = {}
var _store_rows: Dictionary = {}
var _fish_balance: Label = null
var _currency_cap: PanelContainer = null
var _confirmed_product: String = ""
var _confirmed_cost: int = -1
var _confirmed_items: Array[String] = []
var _purchase_return_focus: Control = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	UITheme.apply_ui_scale(self)
	var backdrop := get_parent().get_node_or_null("ExpeditionMenuArt") as TextureRect
	if backdrop != null:
		SceneBackground.bind(backdrop,
			"res://assets/art/ui/menu/shop_background_portrait_v3.webp",
			"res://assets/art/ui/menu/shop_background_desktop_v3.webp")
	_client = get_node_or_null("/root/CommerceClient")
	_build()
	if _client != null:
		_client.connect("store_changed", _update)
		_client.connect("entitlements_changed", _update)
		_client.connect("status_changed", _update_status)
		_client.call("refresh_store")
	var native_auth := get_node_or_null("/root/NativeAuthClient")
	if not OS.has_feature("web") and native_auth != null:
		native_auth.connect("auth_changed", _update)
		native_auth.connect("status_changed", _on_auth_status_changed)
	_update()
	Progression.fish_changed.connect(_on_fish_changed)
	Progression.cosmetics_changed.connect(_update)
	get_viewport().size_changed.connect(_rebuild)


func _rebuild() -> void:
	_close_purchase_information()
	if _page != null:
		_page.free()
	_buttons.clear()
	_price_labels.clear()
	_ownership_labels.clear()
	_detail_cards.clear()
	_selector_buttons.clear()
	_purchase_rows.clear()
	_fish_buttons.clear()
	_fish_prices.clear()
	_store_rows.clear()
	_build()
	_update()


func _build() -> void:
	var shell := ExpeditionSubmenuShell.build(self, "shop", "Shop", 0.235)
	_page = shell["root"] as Control
	var back := shell["back"] as Button
	for connection in back.pressed.get_connections():
		back.pressed.disconnect(connection["callable"])
	back.pressed.connect(_close)
	var content := shell["content"] as VBoxContainer
	var profile := shell["profile"] as LayoutProfile
	_portrait_page = bool(shell["portrait"])
	# One authored gutter measured from the full canvas, never safe+gutter.
	var margins := _page as MarginContainer
	var authored := profile.viewport_size.x * (0.035 if _portrait_page else 0.02)
	for side: String in ["left", "right", "top", "bottom"]:
		var inset := profile.safe_insets.x if side == "left" else profile.safe_insets.z if side == "right" else profile.safe_insets.y if side == "top" else profile.safe_insets.w
		margins.add_theme_constant_override("margin_" + side, roundi(maxf(authored, inset) - inset))

	# Leave space for the rounded selected-card ends above the fixed footer.
	content.add_theme_constant_override("separation", 12 if _portrait_page else 22)
	(_page.find_child("ExpeditionPage", true, false) as VBoxContainer).add_theme_constant_override("separation", 12)
	_currency_cap = ExpeditionMenuStyle.currency_pill(Progression.get_fish(), false)
	_currency_cap.name = "ShopCurrencyCap"
	var header_height := (shell["header"] as Control).custom_minimum_size.y
	var fish_symbol := _currency_cap.find_child("FishSymbol",true,false) as TextureRect
	fish_symbol.custom_minimum_size = Vector2(header_height * 0.40, header_height * 0.36)
	_currency_cap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_currency_cap.offset_left = -profile.viewport_size.x * (0.23 if _portrait_page else 0.13)
	_currency_cap.offset_right = 0.0
	_currency_cap.offset_bottom = header_height * 0.82
	(shell["header"] as Control).add_child(_currency_cap)
	UtilityScreenLayout.defer_header_alignment(self,
		(shell["header"] as Control).find_child("ApprovedTitleArtwork", true, false) as Control,
		back, [_currency_cap])
	if _portrait_page:
		(shell["header"] as Control).custom_minimum_size.y = profile.viewport_size.x * 0.225
		var title := (shell["header"] as Control).find_child("ApprovedTitleArtwork",true,false) as TextureRect
		title.offset_bottom = profile.viewport_size.x * 0.245
		title.offset_top = -profile.viewport_size.y * 0.010
		var hero_space := (shell["scroll"] as Control).get_parent().get_child(0) as Control
		hero_space.custom_minimum_size.y = profile.viewport_size.y * 0.227
	else:
		var art_stage := shell["art_stage"] as Control
		art_stage.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		art_stage.custom_minimum_size.x = profile.viewport_size.x * 0.43
		var header := shell["header"] as Control
		header.custom_minimum_size.y = profile.viewport_size.y * 0.072
		header.z_index = 1
		var title := header.find_child("ApprovedTitleArtwork", true, false) as TextureRect
		title.set_anchors_preset(Control.PRESET_TOP_LEFT)
		title.offset_left = profile.viewport_size.x * 0.095
		title.offset_right = profile.viewport_size.x * 0.435
		title.offset_top = 0.0
		title.offset_bottom = profile.viewport_size.y * 0.24
		var scroll := shell["scroll"] as ScrollContainer
		var page := scroll.get_parent()
		var enclosure := PanelContainer.new()
		enclosure.name = "ShopBundleEnclosure"
		enclosure.size_flags_vertical = Control.SIZE_EXPAND_FILL
		enclosure.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		enclosure.add_theme_stylebox_override("panel", ExpeditionMenuStyle.material_card(24.0, 2.0))
		page.add_child(enclosure)
		scroll.reparent(enclosure)
	_purchase_footer = VBoxContainer.new()
	_purchase_footer.name = "ShopStatusActions"
	_purchase_footer.add_theme_constant_override("separation", 6)
	_tile_width = minf(profile.viewport_size.x * (0.245 if _portrait_page else 0.127), 290.0)
	var products := CommerceCatalog.products()
	if _selected_product_id.is_empty() and not products.is_empty():
		_selected_product_id = String((products[0] as Dictionary)["id"])
	var banner := PanelContainer.new()
	banner.name = "SelectedBundleBanner"
	banner.custom_minimum_size.y = _tile_width * (0.47 if _portrait_page else 0.42)
	banner.add_theme_stylebox_override("panel", ExpeditionMenuStyle.material_box(true, 24.0, 12.0))
	banner.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	banner.custom_minimum_size.x = profile.viewport_size.x * (0.72 if _portrait_page else 0.42)
	content.add_child(banner)
	_selected_banner = ExpeditionMenuStyle.label("", maxi(28, roundi(_tile_width * 0.23)), Color.WHITE)
	_selected_banner.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	_selected_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_selected_banner.autowrap_mode = TextServer.AUTOWRAP_OFF
	_selected_banner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var banner_row := HBoxContainer.new()
	banner_row.alignment = BoxContainer.ALIGNMENT_CENTER
	banner_row.add_theme_constant_override("separation", roundi(_tile_width * 0.09))
	banner.add_child(banner_row)
	for side: int in 3:
		if side == 1:
			banner_row.add_child(_selected_banner)
		else:
			var mountain := TextureRect.new()
			mountain.texture = UITheme.make_icon('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><path d="m3 55 24-40 12 19 8-13 14 34z" fill="#fff9ef"/><path d="m19 29 8-14 8 14-8-4z" fill="#ffd9ce"/></svg>')
			mountain.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			mountain.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			mountain.custom_minimum_size = Vector2.ONE * _tile_width * 0.20
			banner_row.add_child(mountain)
	var shelf_plate := ExpeditionMenuStyle.panel(content)
	shelf_plate.name = "BundleShelfBacking"
	shelf_plate.add_theme_stylebox_override("panel", ExpeditionMenuStyle.material_card(20.0 if _portrait_page else 0.0, 10.0 if _portrait_page else 0.0))
	var shelf := GridContainer.new()
	shelf.name = "BundleShelf"
	shelf.columns = 3 if bool(shell["portrait"]) else 3
	shelf.add_theme_constant_override("h_separation", 8)
	shelf_plate.add_child(shelf)
	for product: Dictionary in products:
		_build_selector(shelf, product)
	_cards = GridContainer.new()
	_cards.columns = 1
	_cards.add_theme_constant_override("h_separation", 10)
	_cards.add_theme_constant_override("v_separation", 10)
	content.add_child(_cards)
	for product: Dictionary in products:
		_build_card(product)
	_select_product(_selected_product_id)
	var footer := _purchase_footer
	var content_parent := (shell["scroll"] as ScrollContainer).get_parent()
	if not _portrait_page: content_parent = content_parent.get_parent()
	content_parent.add_child(footer)
	_fish_balance = ExpeditionSubmenuShell.note((_fish_prices[_selected_product_id] as Label).get_parent().get_parent(), "", PortraitSceneFraming.readable_size(16))
	_fish_balance.add_theme_font_size_override("font_size", maxi(21, roundi(_tile_width * 0.105)))
	_fish_balance.name = "ShopFishBalance"
	_fish_balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label = ExpeditionSubmenuShell.note(footer,
		"Checking shop…", PortraitSceneFraming.readable_size(17))
	_status_label.add_theme_font_size_override("font_size", maxi(21, roundi(_tile_width * 0.115)))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	footer.add_child(actions)
	_refresh = ExpeditionMenuStyle.button("RESTORE PURCHASES", false, _font(PortraitSceneFraming.readable_size(17)), 44.0)
	_refresh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_refresh.pressed.connect(func() -> void:
		if _client != null:
			_client.call("restore_purchases"))
	actions.add_child(_refresh)
	_sign_in = ExpeditionMenuStyle.button("SIGN IN", false, _font(PortraitSceneFraming.readable_size(17)), 44.0)
	_sign_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sign_in.pressed.connect(_request_sign_in)
	actions.add_child(_sign_in)
	for button: Button in [_refresh, _sign_in]:
		button.add_theme_font_size_override("font_size", maxi(21, roundi(_tile_width * 0.105)))
		button.custom_minimum_size.y = 44.0
		for state: String in ["normal", "hover", "pressed", "disabled"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())


func _build_selector(parent: GridContainer, product: Dictionary) -> void:
	var id := String(product["id"])
	var selector_height := _tile_width * (1.20 if _portrait_page else 1.10)
	var selector := ExpeditionMenuStyle.button("", false, _font(16), selector_height)
	selector.name = "Bundle_%s" % id
	selector.custom_minimum_size.y = selector_height
	selector.clip_contents = true
	parent.add_child(selector)
	var stack := VBoxContainer.new()
	stack.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.offset_left = 10.0
	stack.offset_right = -10.0
	stack.offset_top = 6.0
	stack.offset_bottom = -6.0
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selector.add_child(stack)
	var art := TextureRect.new()
	art.texture = _bundle_character(id, true)
	# Caption owns its complete one/two-line height; portrait fills the
	# remaining card space without pushing a long product name off its card.
	art.custom_minimum_size.y = 0.0
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var portrait_frame := PanelContainer.new()
	# This is decoration inside a Button. STOP here swallowed taps on the
	# portrait, leaving only the caption/card border able to select a bundle.
	portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var portrait_skin := ExpeditionMenuStyle.surface(Color("c8e7fa"), 16, false)
	portrait_skin.set_content_margin_all(0.0)
	portrait_frame.add_theme_stylebox_override("panel", portrait_skin)
	stack.add_child(portrait_frame)
	portrait_frame.add_child(art)
	var label := ExpeditionMenuStyle.label(String(product["name"]).to_upper(),
		maxi(21, roundi(_tile_width * 0.115)), ExpeditionMenuStyle.INK)
	label.name = "BundleName"
	label.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	# Catalog names remain whole. Size the longest real name to its card.
	var available := (_tile_width * (1.08 if _portrait_page else 1.16)) - 20.0
	var caption_size := label.get_theme_font_size("font_size")
	while caption_size > 18 and ExpeditionMenuStyle.display_font().get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, caption_size).x > available:
		caption_size -= 1
	label.add_theme_font_size_override("font_size", caption_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(label)
	selector.pressed.connect(_select_product.bind(id))
	_selector_buttons[id] = selector


func _select_product(id: String) -> void:
	if CommerceCatalog.product(id).is_empty():
		return
	_selected_product_id = id
	if is_instance_valid(_fish_balance) and _fish_prices.has(id):
		_fish_balance.reparent((_fish_prices[id] as Label).get_parent().get_parent())
	if _selected_banner != null:
		_selected_banner.text = String(CommerceCatalog.product(id).get("name", "")).to_upper()
	for key: String in _detail_cards.keys():
		(_detail_cards[key] as Control).visible = key == id
		(_purchase_rows[key] as Control).visible = key == id
	for key: String in _selector_buttons.keys():
		var selector := _selector_buttons[key] as Button
		var style := DetailStyle.inset(8, 8, 24, Color("fff4ed") if key == id else Color("faf7ef"))
		selector.add_theme_stylebox_override("normal", style)
		selector.add_theme_stylebox_override("hover", style)
		selector.add_theme_stylebox_override("pressed", style)
		var rim := selector.get_node_or_null("SelectedRim") as Panel
		if rim == null:
			rim = Panel.new()
			rim.name = "SelectedRim"
			rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rim.set_anchors_preset(Control.PRESET_FULL_RECT)
			var line := StyleBoxFlat.new()
			line.draw_center = false
			line.border_color = ExpeditionMenuStyle.CORAL
			line.set_border_width_all(7)
			line.set_corner_radius_all(24)
			rim.add_theme_stylebox_override("panel", line)
			selector.add_child(rim)
		rim.visible = key == id


func _build_card(product: Dictionary) -> void:
	var id := String(product["id"])
	var card := ExpeditionSubmenuShell.card(_cards)
	var unit := _tile_width / (249.0 if _portrait_page else 212.0)
	var detail_surface := DetailStyle.inset(22.0 * unit, (16.0 if _portrait_page else 10.0) * unit, 36.0 * unit)
	detail_surface.content_margin_top = (16.0 if _portrait_page else 10.0) * unit
	(card.get_parent() as PanelContainer).add_theme_stylebox_override("panel", detail_surface)
	card.custom_minimum_size.y = _tile_width * 0.55
	_detail_cards[id] = card.get_parent()
	var title_row := HBoxContainer.new()
	card.add_child(title_row)
	var heading := ExpeditionSubmenuShell.heading(title_row, String(product["name"]).to_upper(), PortraitSceneFraming.readable_size(25))
	heading.add_theme_font_size_override("font_size", maxi(30, roundi(_tile_width * 0.20)))
	heading.name = "BundleTitle"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	DetailStyle.clean_label(heading)
	var detail := HBoxContainer.new()
	detail.add_theme_constant_override("separation", 16)
	card.add_child(detail)
	var art := TextureRect.new()
	art.texture = _bundle_upper_body(id)
	art.name = "BundleOutfitPreview"
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var information := VBoxContainer.new()
	information.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	information.add_theme_constant_override("separation", 6)
	detail.add_child(information)
	var item_row := HBoxContainer.new()
	item_row.add_theme_constant_override("separation", 10)
	information.add_child(item_row)
	var items: Array[String] = []
	for cosmetic: String in product["cosmetics"]:
		items.append(String(CosmeticsDB.get_item(cosmetic).get("name", cosmetic)))
		var icon_texture := ExpeditionMenuStyle.wardrobe_sprite(cosmetic)
		if cosmetic == "trail_aurora":
			icon_texture = ExpeditionMenuStyle._material_texture("res://assets/art/ui/menu/shop_aurora_trail_v3.webp")
		if icon_texture == null and String(CosmeticsDB.get_item(cosmetic).get("category", "")) == "trail":
			icon_texture = TrailEffect._particle_texture(cosmetic)
		if icon_texture != null:
			var item_plate := PanelContainer.new()
			item_plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			item_plate.add_theme_stylebox_override("panel", DetailStyle.inset(6.0, 6.0, 20.0))
			item_row.add_child(item_plate)
			var icon := TextureRect.new()
			icon.name = "BundleItem_" + cosmetic
			icon.tooltip_text = String(CosmeticsDB.get_item(cosmetic).get("name", cosmetic))
			icon.accessibility_name = icon.tooltip_text
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.texture = icon_texture
			icon.custom_minimum_size = Vector2(_tile_width * 0.35, _tile_width * (0.55 if _portrait_page else 0.48))
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			item_plate.add_child(icon)
	var contents := ExpeditionSubmenuShell.note(information, "  •  ".join(items), PortraitSceneFraming.readable_size(17))
	contents.add_theme_font_size_override("font_size", maxi(21, roundi(_tile_width * 0.105)))
	contents.name = "BundleContents"
	# The desktop reference names the bundle above its individual item pictures.
	# Keep each item named for assistive technology and hover inspection.
	contents.visible = _portrait_page
	var ownership := ExpeditionSubmenuShell.note(information, "", PortraitSceneFraming.readable_size(15))
	ownership.name = "BundleOwnership"
	ownership.hide()
	_ownership_labels[id] = ownership
	var art_space := Control.new()
	art_space.custom_minimum_size.x = _tile_width * 0.90
	detail.add_child(art_space)
	art_space.add_child(art)
	art.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	art.offset_left = -_tile_width * 1.12
	art.offset_right = -12.0 * unit
	art.offset_top = -_tile_width * 0.22
	art.offset_bottom = _tile_width * 0.86
	var purchase := VBoxContainer.new()
	purchase.name = "Purchase_" + id
	purchase.add_theme_constant_override("separation", 8)
	card.add_child(purchase)
	_purchase_rows[id] = purchase
	var fish_row := HBoxContainer.new()
	fish_row.name = "FishPurchase_" + id
	fish_row.add_theme_constant_override("separation", 8)
	purchase.add_child(fish_row)
	var price_stack := VBoxContainer.new()
	price_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price_stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	price_stack.add_theme_constant_override("separation", 3)
	var price_plate := PanelContainer.new()
	price_plate.name = "BundleFishPricePlate"
	price_plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price_plate.add_theme_stylebox_override("panel", DetailStyle.inset(12 * unit, 4 * unit, 32 * unit))
	fish_row.add_child(price_plate)
	price_plate.add_child(price_stack)
	var price_row := HBoxContainer.new()
	price_row.alignment = BoxContainer.ALIGNMENT_CENTER
	price_row.add_theme_constant_override("separation", 8)
	price_stack.add_child(price_row)
	var price_icon := TextureRect.new()
	price_icon.texture = ExpeditionMenuStyle._material_texture("res://assets/art/ui/menu/home_fish_symbol_clean_v2.png")
	price_icon.custom_minimum_size = Vector2(_tile_width * 0.42, _tile_width * (0.31 if _portrait_page else 0.23))
	price_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	price_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	price_row.add_child(price_icon)
	var fish_price := ExpeditionSubmenuShell.heading(price_row, "", PortraitSceneFraming.readable_size(21))
	fish_price.add_theme_font_size_override("font_size", maxi(30, roundi(_tile_width * 0.23)))
	fish_price.name = "FishCost"
	fish_price.autowrap_mode = TextServer.AUTOWRAP_OFF
	fish_price.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	fish_price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fish_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fish_prices[id] = fish_price
	var fish_action := ExpeditionMenuStyle.button("VIEW BUNDLE", true, _font(PortraitSceneFraming.readable_size(18)), 66.0)
	fish_action.add_theme_font_size_override("font_size", maxi(28, roundi(_tile_width * 0.19)))
	fish_action.custom_minimum_size.y = _tile_width * 0.45
	fish_action.name = "UnlockWithFish_" + id
	fish_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fish_action.pressed.connect(_preview_fish_purchase.bind(id))
	fish_row.add_child(fish_action)
	_fish_buttons[id] = fish_action
	var store_row := HBoxContainer.new()
	store_row.name = "StorePurchase_" + id
	store_row.add_theme_constant_override("separation", 8)
	purchase.add_child(store_row)
	_store_rows[id] = store_row
	var price := ExpeditionSubmenuShell.heading(store_row, "Price unavailable", PortraitSceneFraming.readable_size(21))
	price.custom_minimum_size.x = _tile_width * 1.05
	price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_price_labels[id] = price
	var info := ExpeditionMenuStyle.button("i", false, 24, 44.0)
	info.name = "PurchaseInformation"
	info.accessibility_name = "Purchase information"
	info.tooltip_text = CommerceCatalog.disclosure()
	info.custom_minimum_size.x = 52.0
	info.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var face := StyleBoxFlat.new()
	face.bg_color = ExpeditionMenuStyle.IVORY
	face.set_corner_radius_all(12)
	face.set_content_margin_all(6.0)
	for state: String in ["normal","hover","pressed"]:
		info.add_theme_stylebox_override(state,face)
	info.pressed.connect(_show_purchase_information)
	title_row.add_child(info)
	var action := ExpeditionMenuStyle.button("Unavailable", true, _font(PortraitSceneFraming.readable_size(19)), 60.0)
	action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action.size_flags_stretch_ratio = 1.6
	action.pressed.connect(func() -> void: _purchase(id))
	store_row.add_child(action)
	_buttons[id] = action


func _on_fish_changed(_total: int) -> void:
	_update()


func _payments_supported() -> bool:
	return _client != null and bool(_client.call("payment_platform_supported"))


func _update() -> void:
	super._update()
	if _fish_balance == null:
		return
	_fish_balance.text = "YOUR FISH: %s" % Progression.get_fish()
	_currency_cap.tooltip_text = "%s fish" % ExpeditionMenuStyle.grouped_amount(Progression.get_fish())
	_currency_cap.accessibility_name = _currency_cap.tooltip_text
	var amount := _currency_cap.find_child("FishAmount", true, false) as Label
	amount.text = ExpeditionMenuStyle.grouped_amount(Progression.get_fish())
	var amount_size := _font(25)
	var available := _currency_cap.size.x - (_currency_cap.find_child("FishSymbol", true, false) as Control).custom_minimum_size.x - 40.0
	while amount_size > 18 and amount.get_theme_font("font").get_string_size(amount.text, HORIZONTAL_ALIGNMENT_LEFT, -1, amount_size).x > available:
		amount_size -= 1
	amount.add_theme_font_size_override("font_size", amount_size)
	var payments := _payments_supported()
	var signed_in := _client != null and bool(_client.call("signed_in"))
	_refresh.text = "RESTORE PURCHASES" if payments else "SYNC PURCHASES"
	_refresh.disabled = _client == null or bool(_client.get("busy")) or not signed_in
	_refresh.tooltip_text = "Refresh verified purchases for your signed-in account. Earned fish unlocks stay on this device."
	if GameConfig.native_offline_mvp():
		_refresh.hide()
		_sign_in.hide()
	for product: Dictionary in CommerceCatalog.products():
		var id := String(product["id"])
		var quote := _fish_quote(id)
		var action := _fish_buttons[id] as Button
		var owned := (quote.get("items", []) as Array).is_empty()
		var cost := int(quote.get("cost", 0))
		(_fish_prices[id] as Label).text = "ALL OWNED" if owned else ExpeditionMenuStyle.grouped_amount(cost)
		(_fish_prices[id] as Label).add_theme_font_size_override("font_size", maxi(28, roundi(_tile_width * (0.16 if owned else 0.23))))
		(_fish_prices[id] as Label).accessibility_name = "All owned" if owned else "%d fish" % cost
		action.text = "OWNED" if owned else "VIEW BUNDLE"
		action.disabled = owned or not bool(quote.get("valid", false))
		action.tooltip_text = "Only unowned items are charged, at their individual fish prices. Unlocks do not equip items."
		# Web supports payments before an authenticated, priced catalog exists.
		# Keep that unavailable state in the status/footer, not an empty checkout
		# row that pushes the usable fish action beyond the selected card.
		var checkout_ready := payments and bool(_client.call("checkout_prepared_for", id))
		var priced_store := payments and signed_in and bool(_client.get("store_available")) \
			and not String(_client.call("localized_price", id)).is_empty()
		(_store_rows[id] as Control).visible = not owned and (checkout_ready or priced_store)
	_refresh_fish_confirmation()


func _fish_quote(product_id: String) -> Dictionary:
	var product := CommerceCatalog.product(product_id)
	var missing: Array[String] = []
	var cost := 0
	if product.is_empty():
		return {"valid": false, "items": missing, "cost": 0}
	for id: String in product.get("cosmetics", []):
		var item := CosmeticsDB.get_item(id)
		if item.is_empty() or int(item.get("cost", -1)) < 0:
			return {"valid": false, "items": [], "cost": 0}
		if not Progression.is_cosmetic_unlocked(id) and not missing.has(id):
			missing.append(id)
			cost += int(item["cost"])
	return {"valid": true, "items": missing, "cost": cost}


func _preview_fish_purchase(product_id: String) -> void:
	var quote := _fish_quote(product_id)
	if not bool(quote["valid"]) or (quote["items"] as Array).is_empty():
		_update()
		return
	_close_purchase_information()
	_confirmed_product = product_id
	_confirmed_cost = int(quote["cost"])
	_confirmed_items.assign(quote["items"])
	var lines: Array[String] = []
	for id: String in _confirmed_items:
		var item := CosmeticsDB.get_item(id)
		lines.append("%s — %d fish" % [item["name"], item["cost"]])
	var body := _information_card("UNLOCK WITH FISH", "\n".join(lines) + "\n\nSpend %d fish? Owned items are excluded. Equip your new items in Penguins." % _confirmed_cost)
	var balance := ExpeditionMenuStyle.label("", _font(PortraitSceneFraming.readable_size(18)))
	balance.name = "FishPurchaseBalance"
	balance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(balance)
	var confirm := ExpeditionMenuStyle.button("SPEND %d FISH" % _confirmed_cost, true, _font(PortraitSceneFraming.readable_size(23)), 78.0)
	confirm.name = "ConfirmFishPurchase"
	confirm.pressed.connect(_confirm_fish_purchase)
	body.add_child(confirm)
	_add_information_close(body, "CANCEL")
	_refresh_fish_confirmation()


func _refresh_fish_confirmation() -> void:
	if not is_instance_valid(_purchase_info) or _confirmed_product.is_empty():
		return
	var balance := _purchase_info.find_child("FishPurchaseBalance", true, false) as Label
	var confirm := _purchase_info.find_child("ConfirmFishPurchase", true, false) as Button
	if balance == null or confirm == null:
		return
	var quote := _fish_quote(_confirmed_product)
	var unchanged: bool = quote.get("items", []) == _confirmed_items and int(quote.get("cost", -1)) == _confirmed_cost
	var shortfall := maxi(0, _confirmed_cost - Progression.get_fish())
	confirm.disabled = not unchanged or shortfall > 0
	balance.text = "Your fish: %s" % ExpeditionMenuStyle.grouped_amount(Progression.get_fish())
	if not unchanged:
		balance.text += "\nOwned items changed. Close and review the updated bundle."
	elif shortfall > 0:
		balance.text += "\nEarn %s more fish in runs to unlock this bundle." % ExpeditionMenuStyle.grouped_amount(shortfall)
	else:
		balance.text += "\nFish remaining: %s" % ExpeditionMenuStyle.grouped_amount(Progression.get_fish() - _confirmed_cost)


func _confirm_fish_purchase() -> void:
	if _confirmed_product.is_empty():
		return
	var product_id := _confirmed_product
	var cost := _confirmed_cost
	var expected_items := _confirmed_items.duplicate()
	var quote := _fish_quote(product_id)
	_close_purchase_information()
	if quote.get("items", []) != expected_items or int(quote.get("cost", -1)) != cost:
		_update()
		_update_status("Your ownership changed. Review the updated fish price before unlocking.")
		return
	var ids: Array[String] = []
	ids.assign(CommerceCatalog.product(product_id).get("cosmetics", []))
	var unlocked := Progression.try_unlock_cosmetics(ids, cost)
	_update()
	_update_status("Items unlocked. Equip them in Penguins." if unlocked else "Could not unlock these items. Check your fish balance and try again.")


func _show_purchase_information() -> void:
	if is_instance_valid(_purchase_info):
		return
	var body := _information_card("PURCHASE INFORMATION", CommerceCatalog.disclosure())
	_add_information_close(body, "CLOSE")


func _information_card(title_text: String, copy_text: String) -> VBoxContainer:
	_purchase_return_focus = get_viewport().gui_get_focus_owner()
	_purchase_info = Control.new()
	_purchase_info.name = "PurchaseInfoOverlay"
	_purchase_info.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_purchase_info.z_index = 100
	_purchase_info.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_purchase_info)
	var scrim := ColorRect.new()
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(0.04,0.09,0.16,0.70)
	_purchase_info.add_child(scrim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_purchase_info.add_child(center)
	var card := PanelContainer.new()
	card.custom_minimum_size.x = minf(get_viewport_rect().size.x * 0.88, 860.0)
	card.add_theme_stylebox_override("panel", ExpeditionMenuStyle.material_card(32.0,32.0))
	center.add_child(card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 24)
	card.add_child(body)
	var title := ExpeditionMenuStyle.label(title_text, _font(PortraitSceneFraming.readable_size(24)))
	title.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	var copy := ExpeditionMenuStyle.label(copy_text,_font(PortraitSceneFraming.readable_size(18)))
	copy.name = "PurchaseDisclosure"
	copy.add_theme_font_override("font",UITheme.ui_font())
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(copy)
	return body


func _add_information_close(body: VBoxContainer, text: String) -> void:
	var close := ExpeditionMenuStyle.button(text,false,_font(PortraitSceneFraming.readable_size(24)),78.0)
	close.name = "ClosePurchaseInformation"
	close.pressed.connect(_close_purchase_information)
	body.add_child(close)
	var confirm := body.get_node_or_null("ConfirmFishPurchase") as Button
	close.focus_next = confirm.get_path() if confirm != null else close.get_path()
	close.focus_previous = close.focus_next
	if confirm != null:
		confirm.focus_next = close.get_path()
		confirm.focus_previous = close.get_path()
	close.grab_focus()


func _close_purchase_information() -> void:
	_confirmed_product = ""
	_confirmed_cost = -1
	_confirmed_items.clear()
	if not is_instance_valid(_purchase_info):
		return
	# Hiding the active GUI control can dispatch a second input/focus callback.
	# Detach the modal state first so closing stays idempotent under real taps.
	var closing := _purchase_info
	_purchase_info = null
	closing.hide()
	closing.queue_free()
	if is_instance_valid(_purchase_return_focus) and _purchase_return_focus.is_visible_in_tree():
		_purchase_return_focus.grab_focus()
	elif _fish_buttons.has(_selected_product_id):
		(_fish_buttons[_selected_product_id] as Button).grab_focus()
	_purchase_return_focus = null


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(_purchase_info) and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close_purchase_information()
		return
	super._unhandled_input(event)


func _bundle_character(id: String, portrait_crop: bool = false) -> Texture2D:
	var outfits := {
		"cozy_expedition": "body_classic__hat_beanie__none__scarf_red",
		"research_crew": "body_classic__hat_headset__goggles_ski__scarf_bowtie",
		"aurora_celebration": "body_classic__hat_crown__none__scarf_rainbow",
	}
	var key := String(outfits.get(id, ""))
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/wardrobe/outfits_v1.json"))
	var entry: Dictionary = manifest.get("entries", {}).get(key, {}) if manifest is Dictionary else {}
	var path := String(entry.get("runtime", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return ExpeditionMenuStyle._material_texture(_bundle_art(id))
	var texture := ExpeditionMenuStyle._material_texture(path)
	if not portrait_crop or texture == null:
		return texture
	var crop := AtlasTexture.new()
	crop.atlas = texture
	# Close portrait of the exact reviewed outfit, keeping headgear and neckwear.
	crop.region = Rect2(texture.get_width() * 0.14, 0,
		texture.get_width() * 0.72, minf(texture.get_height(), texture.get_width() * 0.83))
	crop.filter_clip = true
	return crop


func _bundle_upper_body(id: String) -> Texture2D:
	var texture := _bundle_character(id)
	if texture == null: return null
	var crop := AtlasTexture.new()
	crop.atlas = texture
	crop.region = Rect2(0, 0, texture.get_width(), texture.get_height() * 0.76)
	crop.filter_clip = true
	return crop


func _bundle_art(id: String) -> String:
	match id:
		"cozy_expedition":
			return "res://assets/art/ui/menu/shop_cozy_bundle_v1.webp"
		"research_crew":
			return "res://assets/art/ui/menu/shop_research_bundle_v1.webp"
		_:
			return "res://assets/art/ui/menu/shop_aurora_bundle_v1.webp"


func _font(size: int) -> int:
	return maxi(1, roundi(float(UITheme.scaled_font(size)) *
		(1.25 if UITheme.is_touch() else 1.0)))
