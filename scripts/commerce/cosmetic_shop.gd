class_name CosmeticShop
extends Control
## Reusable menu overlay. Store cards use existing cosmetics and explicit
## non-consumable disclosures. Payment controls never appear during gameplay.

signal closed

var _client: Node = null
var _status_label: Label
var _cards: GridContainer
var _buttons: Dictionary = {}
var _price_labels: Dictionary = {}
var _ownership_labels: Dictionary = {}
var _refresh: Button
var _sign_in: Button
var _panel: PanelContainer
var _safe_margin: MarginContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	UITheme.apply_ui_scale(self)
	_client = get_node_or_null("/root/CommerceClient")
	var shade := ColorRect.new()
	shade.color = Color(0.018, 0.032, 0.065, 0.94)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var safe := MarginContainer.new()
	_safe_margin = safe
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var profile := LayoutProfile.for_viewport(get_viewport())
	for key: String in ["left", "top", "right", "bottom"]:
		var index: int = {"left": 0, "top": 1, "right": 2, "bottom": 3}[key]
		safe.add_theme_constant_override("margin_%s" % key, roundi(profile.safe_insets[index]) + 24)
	add_child(safe)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	safe.add_child(center)
	_panel = PanelContainer.new()
	var surface := StyleBoxFlat.new()
	surface.bg_color = UITheme.COLOR_PANEL
	surface.border_color = UITheme.COLOR_RIM
	surface.set_border_width_all(1)
	surface.set_corner_radius_all(22)
	surface.content_margin_left = 24
	surface.content_margin_right = 24
	surface.content_margin_top = 22
	surface.content_margin_bottom = 22
	_panel.add_theme_stylebox_override("panel", surface)
	center.add_child(_panel)
	var frame := VBoxContainer.new()
	frame.add_theme_constant_override("separation", UITheme.scaled_int(18))
	_panel.add_child(frame)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UITheme.scaled_int(18))
	frame.add_child(header)
	var title := _label("Expedition wardrobe", 30, UITheme.COLOR_TEXT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back := UITheme.make_button("Close", UITheme.scaled_size(Vector2(110, 52)), UITheme.scaled_font(20))
	back.name = "CloseShop"
	back.pressed.connect(_close)
	header.add_child(back)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	TouchScroll.attach(scroll)
	frame.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 18)
	scroll.add_child(content)
	var description := _label("Choose a look. Every item also unlocks by playing and earning fish.", 21, UITheme.COLOR_ACCENT)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(description)
	_cards = GridContainer.new()
	_cards.add_theme_constant_override("h_separation", 16)
	_cards.add_theme_constant_override("v_separation", 16)
	content.add_child(_cards)
	for product: Dictionary in CommerceCatalog.products():
		_build_card(product)
	var disclosure := _label(CommerceCatalog.disclosure(), 17, UITheme.COLOR_TEXT_DIM)
	disclosure.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(disclosure)
	_status_label = _label("Checking shop…", 19, UITheme.COLOR_TEXT)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status_label)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	content.add_child(actions)
	_refresh = UITheme.make_button("Refresh purchases", UITheme.scaled_size(Vector2(210, 56)), UITheme.scaled_font(20))
	_refresh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_refresh.pressed.connect(func() -> void:
		if _client != null:
			_client.call("restore_purchases"))
	actions.add_child(_refresh)
	_sign_in = UITheme.make_button("Sign in", UITheme.scaled_size(Vector2(140, 56)), UITheme.scaled_font(20))
	_sign_in.pressed.connect(_request_sign_in)
	actions.add_child(_sign_in)
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
	get_viewport().size_changed.connect(_layout)
	_layout()
	back.grab_focus()


func _build_card(product: Dictionary) -> void:
	var id := String(product["id"])
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = UITheme.COLOR_CARD_TOP
	style.border_color = UITheme.COLOR_HAIRLINE
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 22
	style.content_margin_bottom = 20
	card.add_theme_stylebox_override("panel", style)
	_cards.add_child(card)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 14)
	card.add_child(stack)
	var name_label := _label(String(product["name"]), 25, UITheme.COLOR_GOLD)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(name_label)
	var items: Array[String] = []
	for cosmetic: String in product["cosmetics"]:
		items.append(String(CosmeticsDB.get_item(cosmetic).get("name", cosmetic)))
	var items_label := _label("\n".join(items), 20, UITheme.COLOR_TEXT)
	stack.add_child(items_label)
	var ownership := _label("", 16, UITheme.COLOR_TEXT_DIM)
	ownership.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(ownership)
	_ownership_labels[id] = ownership
	var price := _label("Price unavailable", 23, UITheme.COLOR_TEXT)
	stack.add_child(price)
	_price_labels[id] = price
	var action := UITheme.make_button("Unavailable", UITheme.scaled_size(Vector2(0, 56)), UITheme.scaled_font(20))
	action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action.pressed.connect(func() -> void: _purchase(id))
	stack.add_child(action)
	_buttons[id] = action


func _update() -> void:
	if _status_label == null:
		return
	var signed_in := _client != null and bool(_client.call("signed_in"))
	_sign_in.visible = not signed_in or not OS.has_feature("web")
	_sign_in.text = "Sign out" if signed_in and not OS.has_feature("web") else "Sign in"
	var auth := get_node_or_null("/root/NativeAuthClient")
	if not OS.has_feature("web") and auth != null and bool(auth.get("pending")):
		_sign_in.text = "Cancel sign-in"
	_refresh.disabled = _client == null or bool(_client.get("busy"))
	for product: Dictionary in CommerceCatalog.products():
		var id := String(product["id"])
		var action: Button = _buttons[id]
		var all_owned := true
		var owned_count := 0
		for cosmetic: String in product["cosmetics"]:
			if Progression.is_cosmetic_unlocked(cosmetic):
				owned_count += 1
			else:
				all_owned = false
		var product_owned := _client != null and bool(_client.call("owns_product", id))
		var checkout_ready := _client != null and bool(_client.call("checkout_prepared_for", id))
		var price := String(_client.call("localized_price", id)) if _client != null else ""
		_price_labels[id].text = price if not price.is_empty() else "Price unavailable"
		_ownership_labels[id].text = "%d of 3 items already owned" % owned_count if owned_count > 0 else "3 permanent cosmetic unlocks"
		if all_owned or product_owned:
			action.text = "Owned"
			action.disabled = true
		elif checkout_ready:
			action.text = "Continue to payment"
			action.disabled = false
		else:
			action.text = "Buy bundle" if signed_in else "Sign in to buy"
			action.disabled = _client == null or not bool(_client.call("can_purchase", id))
	_update_status(String(_client.get("status")) if _client != null else "Shop unavailable on this build. Cosmetics still unlock with fish.")


func _purchase(product_id: String) -> void:
	if _client == null:
		return
	if bool(_client.call("checkout_prepared_for", product_id)):
		_client.call("open_checkout", product_id)
		return
	# Actual store/payment UI shows the final localized price and confirms the
	# charge. Preparing a Checkout URL never charges or grants items itself.
	_client.call("purchase", product_id)
	_update()


func _request_sign_in() -> void:
	_update_status("Opening secure sign-in…")
	var online := get_node_or_null("/root/LeaderboardClient")
	if OS.has_feature("web") and online != null:
		online.call("sign_in")
	else:
		var auth := get_node_or_null("/root/NativeAuthClient")
		if auth != null:
			if bool(auth.call("signed_in")):
				auth.call("sign_out")
			elif bool(auth.get("pending")):
				auth.call("cancel_sign_in")
			else:
				auth.call("sign_in")
		else:
			_update_status("Account sign-in unavailable on this build. Cosmetics still unlock with fish.")


func _update_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message


func _on_auth_status_changed(message: String) -> void:
	# NativeAuth changes pending before reporting status; refresh the action
	# immediately so sign-in can be cancelled while authorization is pending.
	_update()
	_update_status(message)


func _layout() -> void:
	if _panel == null:
		return
	var profile := LayoutProfile.for_viewport(get_viewport())
	var edge := UITheme.scaled(24.0)
	var width := minf(1120.0, maxf(profile.safe_rect.size.x - edge * 2.0, 240.0))
	for key: String in ["left", "top", "right", "bottom"]:
		var index: int = {"left": 0, "top": 1, "right": 2, "bottom": 3}[key]
		_safe_margin.add_theme_constant_override("margin_%s" % key, roundi(profile.safe_insets[index] + edge))
	_panel.custom_minimum_size = Vector2(width, minf(760.0, maxf(profile.safe_rect.size.y - 48.0, 200.0)))
	_cards.columns = 1 if profile.is_portrait() or width < 800.0 else 3
	for card: Control in _cards.get_children():
		card.custom_minimum_size.x = maxf((width - 48.0 - 16.0 * (_cards.columns - 1)) / _cards.columns, 180.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	closed.emit()
	queue_free()


static func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UITheme.ui_font())
	label.add_theme_font_size_override("font_size", UITheme.scaled_font(size))
	label.add_theme_color_override("font_color", color)
	return label
