extends CanvasLayer
## Opens over Base Camp or a paused run without changing its pause state.

const Client := preload("res://scripts/network/feedback_client.gd")
const ART := "res://assets/art/ui/menu/feedback_penguin_v1.png"
const MUTED_INK := Color("50627e")

var _root: Control
var _background: TextureRect
var _wordmark: TextureRect
var _page: MarginContainer
var _columns: BoxContainer
var _hero: TextureRect
var _card: PanelContainer
var _form: VBoxContainer
var _form_heading: VBoxContainer
var _welcome: Label
var _intro: Label
var _message_gap: Control
var _send_gap: Control
var _email_label: Label
var _header: Label
var _back: Button
var _types: Array[Button] = []
var _type_pictures: Array[TextureRect] = []
var _type_captions: Array[Label] = []
var _email: LineEdit
var _email_picture: TextureRect
var _message: TextEdit
var _count: Label
var _status: Label
var _send: Button
var _send_caption: Label
var _send_picture: TextureRect
var _client: FeedbackClient
var _selected := "bug"
var _sent := false
var _prior_focus: WeakRef


func open(host: Node) -> void:
	name = "FeedbackForm"
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	var prior := host.get_viewport().gui_get_focus_owner()
	if prior != null:
		_prior_focus = weakref(prior)
	host.add_child(self)


func _ready() -> void:
	_client = Client.new()
	add_child(_client)
	_client.completed.connect(_completed)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_background = TextureRect.new()
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_background)
	_wordmark = TextureRect.new()
	_wordmark.texture = load("res://assets/art/ui/menu/feedback_title_v3.webp")
	_wordmark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wordmark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_wordmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_wordmark)
	_back = ExpeditionMenuStyle.back_button(72)
	_back.name = "FeedbackBack"
	_back.pressed.connect(_close)
	_root.add_child(_back)
	_header = ExpeditionMenuStyle.label("FEEDBACK", 56)
	_header.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.hide()
	_root.add_child(_header)
	_page = MarginContainer.new()
	_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_page)
	var stack := VBoxContainer.new()
	_page.add_child(stack)
	var scroll := ScrollContainer.new()
	scroll.name = "FeedbackScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	TouchScroll.attach(scroll)
	stack.add_child(scroll)
	_columns = BoxContainer.new()
	_columns.add_theme_constant_override("separation", 32)
	_columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_columns)
	_hero = TextureRect.new()
	_hero.name = "FeedbackPenguin"
	_hero.texture = load(ART)
	_hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_columns.add_child(_hero)
	_hero.hide()
	_card = PanelContainer.new()
	_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_card.size_flags_stretch_ratio = 1.4
	_card.add_theme_stylebox_override("panel", ExpeditionMenuStyle.material_card(32, 32))
	_columns.add_child(_card)
	_form = VBoxContainer.new()
	_form.add_theme_constant_override("separation", 10)
	_card.add_child(_form)
	_form_heading = VBoxContainer.new()
	_form_heading.name = "FeedbackHeading"
	_form_heading.add_theme_constant_override("separation", 0)
	_form.add_child(_form_heading)
	_welcome = ExpeditionMenuStyle.label("HELP MAKE WADDLE WARS BETTER", UITheme.scaled_font(28))
	_welcome.name = "FeedbackWelcome"
	_welcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_welcome.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	_form_heading.add_child(_welcome)
	_intro = ExpeditionMenuStyle.label("Found a bug or have an idea?", UITheme.scaled_font(22), ExpeditionMenuStyle.INK)
	_intro.name = "FeedbackIntro"
	_intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_form_heading.add_child(_intro)
	var type_row := HBoxContainer.new()
	type_row.name = "FeedbackCategories"
	type_row.add_theme_constant_override("separation", 12)
	_form.add_child(type_row)
	var names := ["BUG", "IDEA", "OTHER"]
	for i: int in names.size():
		var button := ExpeditionMenuStyle.button(names[i], i == 0, UITheme.scaled_font(22), UITheme.scaled(72))
		button.name = "FeedbackType%d" % i
		button.icon = _category_icon(i)
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_pressed = i == 0
		button.pressed.connect(_select_type.bind(i))
		type_row.add_child(button)
		_types.append(button)
		ExpeditionMenuStyle.illustrated_action(button, names[i], button.icon, 30, 90, false,
			Color.WHITE if i == 0 else ExpeditionMenuStyle.INK)
		var action := button.get_node("IllustratedAction") as HBoxContainer
		_type_pictures.append(action.get_child(0) as TextureRect)
		_type_captions.append(action.get_child(1) as Label)
	_message_gap = Control.new()
	_message_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_form.add_child(_message_gap)
	_form.add_child(_field_label("YOUR MESSAGE"))
	_message = TextEdit.new()
	_message.name = "FeedbackMessage"
	_message.placeholder_text = "What happened, or what would you like to see?"
	_message.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_message.custom_minimum_size.y = 190
	_message.text_changed.connect(_text_changed)
	_style_input(_message)
	_form.add_child(_message)
	_count = ExpeditionMenuStyle.label("0 / 2,000", UITheme.scaled_font(17), ExpeditionMenuStyle.INK_MUTED)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_form.add_child(_count)
	_email_label = _field_label("EMAIL (OPTIONAL)")
	_form.add_child(_email_label)
	_email = LineEdit.new()
	_email.name = "FeedbackEmail"
	_email.placeholder_text = "So we can reply to you"
	_email.max_length = 254
	_email.custom_minimum_size.y = UITheme.scaled_size(Vector2(0, 68)).y
	_email.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	_style_input(_email)
	_form.add_child(_email)
	_email_picture = TextureRect.new()
	_email_picture.name = "FeedbackEmailIcon"
	_email_picture.texture = UITheme.make_icon('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><rect x="5" y="12" width="54" height="40" rx="5" fill="#13365c"/><path d="m9 17 23 19 23-19" fill="none" stroke="#faf8f2" stroke-width="4" stroke-linejoin="round"/></svg>')
	_email_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_email_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_email_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_email.add_child(_email_picture)
	_status = ExpeditionMenuStyle.label("Your message will include the game version and platform.", UITheme.scaled_font(18), ExpeditionMenuStyle.INK_MUTED)
	_status.name = "FeedbackStatus"
	_form.add_child(_status)
	_send_gap = Control.new()
	_send_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_form.add_child(_send_gap)
	_send = ExpeditionMenuStyle.button("SEND FEEDBACK", true, UITheme.scaled_font(26), UITheme.scaled(92))
	_send.name = "FeedbackSend"
	_send.icon = UITheme.make_icon('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><path d="M5 26 58 6 42 57 28 36 5 26Z" fill="white"/><path d="m28 36 19-20" stroke="#f45b48" stroke-width="3"/></svg>')
	_send.expand_icon = true
	_send.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_send.pressed.connect(_submit)
	_form.add_child(_send)
	ExpeditionMenuStyle.illustrated_action(_send, "SEND FEEDBACK", _send.icon, UITheme.scaled_font(26), UITheme.scaled(92), false)
	var send_row := _send.get_node("IllustratedAction") as HBoxContainer
	_send_picture = send_row.get_child(0) as TextureRect
	_send_caption = send_row.get_child(1) as Label
	_root.resized.connect(_layout)
	_clear_label_shadows(_form)
	_layout()
	_back.grab_focus()


func _field_label(value: String) -> Label:
	var label := ExpeditionMenuStyle.label(value, UITheme.scaled_font(21))
	label.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	return label


func _clear_label_shadows(node: Node) -> void:
	if node is Label:
		node.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
		node.add_theme_constant_override("shadow_offset_x", 0)
		node.add_theme_constant_override("shadow_offset_y", 0)
	for child: Node in node.get_children():
		_clear_label_shadows(child)


func _style_input(control: Control) -> void:
	control.add_theme_font_override("font", UITheme.ui_font())
	control.add_theme_font_size_override("font_size", UITheme.scaled_font(23))
	control.add_theme_color_override("font_color", ExpeditionMenuStyle.INK)
	control.add_theme_color_override("font_placeholder_color", Color("697c91"))
	control.add_theme_color_override("caret_color", ExpeditionMenuStyle.INK)
	var normal := ExpeditionMenuStyle.surface(Color("fffdf5"), 18, false)
	normal.border_color = Color("c6d2da")
	normal.set_border_width_all(2)
	control.add_theme_stylebox_override("normal", normal)
	var focused := normal.duplicate() as StyleBoxFlat
	focused.border_color = Color("3983af")
	focused.set_border_width_all(3)
	control.add_theme_stylebox_override("focus", focused)
	control.add_theme_stylebox_override("read_only", normal)


func _category_icon(index: int) -> Texture2D:
	var portrait := LayoutProfile.for_viewport(get_viewport()).is_portrait()
	var paths := [
		'<path d="M18 30c0-17 28-17 28 0v12c0 24-28 24-28 0zM25 17q7-10 14 0z"/><path d="m25 14-5-7m19 7 5-7M18 29 8 23M18 40H6m13 10-9 8M46 29l10-6M46 40h12m-13 10 9 8" fill="none" stroke="currentColor" stroke-width="5" stroke-linecap="round"/>',
		'<path d="M32 5c-20 0-25 25-10 37v8h20v-8C57 30 52 5 32 5Z"/><rect x="24" y="53" width="16" height="6" rx="3"/>',
		'<circle cx="12" cy="32" r="7"/><circle cx="32" cy="32" r="7"/><circle cx="52" cy="32" r="7"/>'
	]
	if portrait:
		paths[2] = '<path d="M32 6C9 6-2 31 12 47L8 60l17-8C58 61 73 6 32 6Z"/><g fill="%s"><circle cx="20" cy="30" r="4"/><circle cx="33" cy="30" r="4"/><circle cx="46" cy="30" r="4"/></g>' % ("#f45b48" if _selected == "other" else "#fff7e9")
	var color := "#ffffff" if index == Client.CATEGORIES.find(_selected) else "#13365c"
	return UITheme.make_icon('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64" fill="%s" color="%s">%s</svg>' % [color, color, paths[index]])


func _layout() -> void:
	if _page == null:
		return
	var profile := LayoutProfile.for_viewport(get_viewport())
	# Reference artwork/card geometry fills the viewport. Safe insets constrain
	# interactive content once; adding them to every authored margin also shrank
	# the whole form on touch browsers whose safe-area policy includes a floor.
	var view := get_viewport().get_visible_rect()
	var portrait := profile.is_portrait()
	var w := view.size.x
	var h := view.size.y
	var base := minf(w / 941.0, h / 1672.0) if portrait else minf(w / 1672.0, h / 941.0)
	var art := "res://assets/art/ui/menu/feedback_background_%s_v3.webp" % ("portrait" if portrait else "desktop")
	if ResourceLoader.exists(art):
		_background.texture = ExpeditionMenuStyle._material_texture(art)
	else:
		_background.texture = ExpeditionMenuStyle._material_texture("res://assets/art/ui/menu/settings_cabin_blank_v2.webp")
	var outer := Vector4(w * (0.020 if portrait else 0.518),
		h * (0.358 if portrait else 0.182), w * (0.020 if portrait else 0.035),
		h * (0.014 if portrait else 0.055))
	_page.add_theme_constant_override("margin_left", roundi(outer.x))
	_page.add_theme_constant_override("margin_right", roundi(outer.z))
	_page.add_theme_constant_override("margin_top", roundi(outer.y))
	_page.add_theme_constant_override("margin_bottom", roundi(outer.w))
	_columns.vertical = portrait
	_columns.add_theme_constant_override("separation", 0)
	_back.position = Vector2(maxf(w * 0.022, profile.safe_insets.x), maxf(h * 0.025, profile.safe_insets.y))
	_back.custom_minimum_size = Vector2.ONE * base * (132.0 if portrait else 94.0)
	_back.size = _back.custom_minimum_size
	_back.add_theme_constant_override("icon_max_width", roundi(_back.size.x))
	_wordmark.position = Vector2(w * (0.205 if portrait else 0.295), h * (0.015 if portrait else -0.010))
	_wordmark.size = Vector2(w * (0.60 if portrait else 0.404), h * (0.125 if portrait else 0.195))
	UtilityScreenLayout.align_header_controls(profile, _wordmark, _back)
	_header.position = _wordmark.position
	_header.size = _wordmark.size
	var card_skin := ExpeditionMenuStyle.material_card((30.0 if portrait else 42.0) * base, 0.0)
	card_skin.content_margin_left = maxf(card_skin.content_margin_left, profile.safe_insets.x - outer.x)
	card_skin.content_margin_right = maxf(card_skin.content_margin_right, profile.safe_insets.z - outer.z)
	card_skin.content_margin_top = maxf((82.0 if portrait else 63.0) * base, profile.safe_insets.y - outer.y)
	card_skin.content_margin_bottom = maxf((32.0 if portrait else 26.0) * base, profile.safe_insets.w - outer.w)
	_card.add_theme_stylebox_override("panel", card_skin)
	_form.add_theme_constant_override("separation", roundi((11.0 if portrait else 4.0) * base))
	_welcome.add_theme_font_size_override("font_size", roundi((51.0 if portrait else 41.0) * base))
	_intro.add_theme_font_size_override("font_size", roundi((37.0 if portrait else 26.0) * base))
	_message_gap.visible = portrait and not _sent
	_message_gap.custom_minimum_size.y = 3.0 * base
	_send_gap.visible = not _sent
	_send_gap.custom_minimum_size.y = 3.0 * base if portrait else 0.0
	_email_label.custom_minimum_size.y = 43.0 * base if portrait else 0.0
	for label: Node in _form.get_children():
		if label is Label:
			var size := 32.0 if portrait else 24.0
			if label == _status or label == _count: size = 25.0 if portrait else 20.0
			label.add_theme_font_size_override("font_size", maxi(12, roundi(size * base)))
			if label == _status or label == _count:
				label.add_theme_font_override("font", UITheme.ui_font())
			else:
				label.add_theme_stylebox_override("normal", _field_label_inset(10.0 * base))
			preload("res://scripts/ui/menu_detail_style.gd").clean_label(label, label.get_theme_color("font_color"))
	_form.get_node("FeedbackCategories").add_theme_constant_override("separation", roundi(14.0 * base))
	for i: int in _types.size():
		var button := _types[i]
		var selected := i == Client.CATEGORIES.find(_selected)
		var font_size := roundi((38.0 if portrait else 28.0) * base)
		ExpeditionMenuStyle.style_button(button, selected, font_size)
		button.custom_minimum_size.y = base * (124.0 if portrait else 82.0)
		_style_feedback_button(button, selected, base)
		var action := button.get_node("IllustratedAction") as HBoxContainer
		action.offset_left = 9.0 * base
		action.offset_right = -9.0 * base
		action.add_theme_constant_override("separation", roundi(20.0 * base))
		_type_pictures[i].texture = _category_icon(i)
		_type_pictures[i].custom_minimum_size = Vector2.ONE * (62.0 if portrait else 42.0) * base
		_type_captions[i].add_theme_font_size_override("font_size", font_size)
		_type_captions[i].add_theme_color_override("font_color", Color.WHITE if selected else ExpeditionMenuStyle.INK)
	_message.custom_minimum_size.y = base * (200.0 if portrait else 136.0)
	_message.add_theme_font_size_override("font_size", roundi((30.0 if portrait else 26.0) * base))
	_email.custom_minimum_size.y = base * (80.0 if portrait else 62.0)
	_email.add_theme_font_size_override("font_size", roundi(28.0 * base))
	for field: Control in [_message, _email]:
		var input_skin := ExpeditionMenuStyle.surface(Color("faf8f2"), roundi(30.0 * base), false)
		input_skin.border_color = Color("d5cec4")
		input_skin.set_border_width_all(maxi(1, roundi(2.0 * base)))
		input_skin.content_margin_left = (78.0 if field == _email and not portrait else 28.0) * base
		input_skin.content_margin_right = 28.0 * base
		input_skin.content_margin_top = 20.0 * base if field == _message else 9.0 * base
		input_skin.content_margin_bottom = input_skin.content_margin_top
		field.add_theme_stylebox_override("normal", input_skin)
		field.add_theme_stylebox_override("read_only", input_skin)
		var focus_skin := input_skin.duplicate() as StyleBoxFlat
		focus_skin.border_color = Color("7696b2")
		field.add_theme_stylebox_override("focus", focus_skin)
		field.add_theme_color_override("font_placeholder_color", Color("737d91"))
	_email_picture.position = Vector2(28.0 * base, (_email.custom_minimum_size.y - 42.0 * base) * 0.5)
	_email_picture.size = Vector2.ONE * 42.0 * base
	_email_picture.visible = not portrait
	_send.custom_minimum_size.y = base * (150.0 if portrait else 98.0)
	_style_feedback_button(_send, true, base)
	_send.add_theme_font_size_override("font_size", roundi((50.0 if portrait else 38.0) * base))
	_send.add_theme_constant_override("icon_max_width", roundi((86.0 if portrait else 62.0) * base))
	_send_caption.add_theme_font_size_override("font_size", roundi((50.0 if portrait else 38.0) * base))
	_send_picture.custom_minimum_size = Vector2.ONE * (86.0 if portrait else 62.0) * base
	var send_row := _send.get_node("IllustratedAction") as HBoxContainer
	send_row.add_theme_constant_override("separation", roundi(30.0 * base))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if portrait else HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_stylebox_override("normal", _field_label_inset(12.0 * base if portrait else 0.0))
	for label: Label in [_welcome, _intro, _send_caption]:
		preload("res://scripts/ui/menu_detail_style.gd").clean_label(label, label.get_theme_color("font_color"))


func _style_feedback_button(button: Button, primary: bool, unit: float) -> void:
	# Uniform painted silhouette; hover remains a small warm change, with no
	# enlarged background, dark pressed patch, or inherited icon gutter.
	for state: String in ["normal", "hover", "pressed", "hover_pressed"]:
		var tint := Color(1.025, 1.02, 1.01) if state == "hover" else Color.WHITE
		if state in ["pressed", "hover_pressed"]: tint = Color(0.96, 0.97, 0.98)
		button.add_theme_stylebox_override(state, ExpeditionMenuStyle.material_box(primary, 10.0 * unit, 4.0 * unit, tint))
	var highlight := button.get_node_or_null("ReferenceHighlight") as Panel
	if highlight == null:
		highlight = Panel.new()
		highlight.name = "ReferenceHighlight"
		highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(highlight)
		highlight.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		highlight.offset_left = 6 * unit
		highlight.offset_right = -6 * unit
		highlight.offset_top = 5 * unit
		highlight.offset_bottom = -7 * unit
	var line := StyleBoxFlat.new()
	line.draw_center = false
	line.border_color = Color(1, 0.98, 0.90, 0.70)
	line.set_border_width_all(maxi(1, roundi(2 * unit)))
	line.set_corner_radius_all(roundi(button.custom_minimum_size.y * 0.5))
	highlight.add_theme_stylebox_override("panel", line)
	highlight.visible = primary



func _select_type(index: int) -> void:
	if _client.busy or _sent:
		return
	_selected = Client.CATEGORIES[index]
	for i: int in _types.size():
		_types[i].set_pressed_no_signal(i == index)
	_layout()


func _text_changed() -> void:
	var length := _message.text.strip_edges().to_utf16_buffer().size() / 2
	_count.text = "%s / 2,000" % ExpeditionMenuStyle.grouped_amount(length)
	_count.add_theme_color_override("font_color", Color("b43332") if length > Client.MAX_MESSAGE else MUTED_INK)


func _submit() -> void:
	if _sent:
		_close()
		return
	if _client.busy:
		return
	var invalid := Client.validation_error(_selected, _message.text, _email.text)
	if not invalid.is_empty():
		_status.text = invalid
		_status.add_theme_color_override("font_color", Color("a52b30"))
		return
	_set_busy(true)
	_status.text = "Sending your message…"
	_status.add_theme_color_override("font_color", ExpeditionMenuStyle.INK_MUTED)
	_client.submit(_selected, _message.text, _email.text)


func _set_busy(value: bool) -> void:
	_send.disabled = value
	_back.disabled = value
	_message.editable = not value
	_email.editable = not value
	for button: Button in _types:
		button.disabled = value
	_send_caption.text = "SENDING…" if value else "SEND FEEDBACK"
	_send.accessibility_name = _send_caption.text


func _completed(ok: bool, message: String) -> void:
	_set_busy(false)
	_status.text = message
	_status.add_theme_color_override("font_color", Color("20724c") if ok else Color("a52b30"))
	if not ok:
		return
	_sent = true
	_header.text = "THANK YOU!"
	_header.show()
	_wordmark.hide()
	for child: Node in _form.get_children():
		if child is Control and child != _status and child != _send:
			child.hide()
	_send_caption.text = "BACK TO GAME"
	_send.accessibility_name = _send_caption.text
	_send.grab_focus()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if not _client.busy:
			_close()


func _close() -> void:
	if _client.busy:
		return
	if _prior_focus != null:
		var prior: Control = _prior_focus.get_ref() as Control
		if is_instance_valid(prior):
			prior.grab_focus()
	queue_free()


func _field_label_inset(amount: float) -> StyleBoxEmpty:
	var skin := StyleBoxEmpty.new()
	skin.content_margin_left = amount
	return skin
