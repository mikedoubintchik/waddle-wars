extends Control
## Responsive, illustrated save reminder. Dismissal never changes guest access.

signal sign_in_requested
signal dismissed

const DetailStyle := preload("res://scripts/ui/menu_detail_style.gd")
var _panel: Panel
var _avatar: TextureRect
var _title: Label
var _body: Label
var _note: Label
var _sign_in: Button
var _later: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.025, 0.08, 0.18, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = Panel.new()
	_panel.name = "SaveProgressPanel"
	_panel.add_theme_stylebox_override("panel", ExpeditionMenuStyle.material_card(0, 0))
	add_child(_panel)
	_avatar = TextureRect.new()
	_avatar.name = "SaveProgressAvatar"
	_avatar.texture = ExpeditionMenuStyle._material_texture("res://assets/art/ui/menu/home_profile_icon_exact_v1.webp")
	_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_avatar)
	_title = _copy("KEEP YOUR PROGRESS", true)
	_title.name = "SaveProgressTitle"
	_body = _copy("Save your fish, outfits and achievements.\nSign in to back up your progress online.", false)
	_body.name = "SaveProgressDescription"
	_note = _copy("Clearing browser data can remove local saves.", false)
	_note.name = "SaveProgressNotice"
	DetailStyle.clean_label(_note, ExpeditionMenuStyle.INK_MUTED)
	_sign_in = ExpeditionMenuStyle.button("SIGN IN TO SAVE", true)
	_sign_in.name = "SaveProgressSignIn"
	_sign_in.pressed.connect(func() -> void: sign_in_requested.emit())
	add_child(_sign_in)
	_later = ExpeditionMenuStyle.button("NOT NOW", false)
	_later.name = "SaveProgressDismiss"
	_later.pressed.connect(func() -> void: dismissed.emit())
	add_child(_later)
	resized.connect(_layout)
	_layout()
	_sign_in.grab_focus()

func _copy(value: String, heading: bool) -> Label:
	var label := ExpeditionMenuStyle.label(value)
	label.add_theme_font_override("font", ExpeditionMenuStyle.display_font() if heading else UITheme.bold_font())
	DetailStyle.clean_label(label)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# This short copy has explicit line breaks. Wrapping at the initial zero
	# width inflated Label's minimum height before the first placement.
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

func _place(control: Control, rect: Rect2) -> void:
	control.custom_minimum_size = Vector2.ZERO
	control.update_minimum_size()
	control.position = rect.position
	control.size = rect.size

func _layout() -> void:
	if _panel == null: return
	var profile := LayoutProfile.for_viewport(get_viewport())
	var safe := profile.safe_rect
	var portrait := profile.is_portrait()
	var unit := minf(safe.size.x / (941.0 if portrait else 1672.0), safe.size.y / (1672.0 if portrait else 941.0))
	var width := (770.0 if portrait else 808.0) * unit
	var height := (800.0 if portrait else 640.0) * unit
	var origin := safe.position + Vector2((safe.size.x - width) * 0.5, safe.size.y * (0.55 if portrait else 0.54) - height * 0.5)
	_place(_panel, Rect2(origin, Vector2(width, height)))
	_place(_avatar, Rect2(origin + Vector2(width * 0.5 - 115.0 * unit, -120.0 * unit), Vector2.ONE * 230.0 * unit))
	_title.text = "KEEP YOUR\nPROGRESS" if portrait else "KEEP YOUR PROGRESS"
	_title.add_theme_font_size_override("font_size", roundi((74.0 if portrait else 58.0) * unit))
	_body.add_theme_font_size_override("font_size", roundi((34.0 if portrait else 30.0) * unit))
	_note.add_theme_font_size_override("font_size", roundi((28.0 if portrait else 24.0) * unit))
	for button: Button in [_sign_in, _later]:
		# Set font before placement so the old, larger glyph minimum cannot
		# stretch a small/rotated button beyond its intended rectangle.
		button.add_theme_font_size_override("font_size", roundi((50 if button == _sign_in else 40) * unit))
	_place(_title, Rect2(origin + Vector2(36, 126) * unit, Vector2(width - 72 * unit, (166 if portrait else 80) * unit)))
	_place(_body, Rect2(origin + Vector2(38, 310 if portrait else 220) * unit, Vector2(width - 76 * unit, (105 if portrait else 84) * unit)))
	_place(_note, Rect2(origin + Vector2(40, 417 if portrait else 311) * unit, Vector2(width - 80 * unit, 52 * unit)))
	_place(_sign_in, Rect2(origin + Vector2(width * 0.10, (482 if portrait else 375) * unit), Vector2(width * 0.80, (144 if portrait else 132) * unit)))
	_place(_later, Rect2(origin + Vector2(width * 0.20, (644 if portrait else 516) * unit), Vector2(width * 0.60, (110 if portrait else 92) * unit)))
	for button: Button in [_sign_in, _later]:
		var focus := StyleBoxFlat.new()
		focus.draw_center = false
		focus.border_color = Color("7398b8")
		focus.set_border_width_all(maxi(1, roundi(2 * unit)))
		focus.set_corner_radius_all(roundi(button.size.y * 0.45))
		button.add_theme_stylebox_override("focus", focus)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		dismissed.emit()
