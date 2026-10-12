extends Control
## Explicit public handle editing, independent of the sign-in provider's name.

signal dismissed
signal name_saved

var _edit: LineEdit
var _error: Label
var _save: Button
var _cancel: Button
var _panel: PanelContainer
var _busy := false


func _ready() -> void:
	name = "AccountNamePrompt"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.025, 0.08, 0.18, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UtilityScreenLayout.bind_safe_rect(self, safe)
	add_child(safe)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	safe.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	_panel = PanelContainer.new()
	_panel.name = "AccountNamePanel"
	center.add_child(_panel)
	var column := VBoxContainer.new()
	column.name = "NameForm"
	_panel.add_child(column)
	var title := _label("CHANGE NAME", true)
	title.name = "NameTitle"
	column.add_child(title)
	var note := _label("Choose your name in the game and on leaderboards.\nYour sign-in account stays the same.")
	note.name = "NameDescription"
	column.add_child(note)
	_edit = LineEdit.new()
	_edit.name = "PlayerNameInput"
	_edit.accessibility_name = "Player name, 2 to 20 characters"
	_edit.placeholder_text = "Your penguin name"
	_edit.max_length = 20
	_edit.text = LeaderboardClient.player_display_name()
	_edit.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_edit.add_theme_font_override("font", UITheme.bold_font())
	_edit.add_theme_color_override("font_color", ExpeditionMenuStyle.INK)
	_edit.add_theme_color_override("caret_color", ExpeditionMenuStyle.INK)
	_edit.text_submitted.connect(func(_value: String) -> void: _submit())
	column.add_child(_edit)
	_error = _label("2–20 letters, numbers, spaces, . _ or -")
	_error.name = "NameStatus"
	column.add_child(_error)
	_save = ExpeditionMenuStyle.button("SAVE NAME", true)
	_save.name = "SavePlayerName"
	_save.pressed.connect(_submit)
	column.add_child(_save)
	_cancel = ExpeditionMenuStyle.button("CANCEL", false)
	_cancel.name = "CancelPlayerName"
	_cancel.pressed.connect(func() -> void: dismissed.emit())
	column.add_child(_cancel)
	resized.connect(_layout)
	_layout()
	# Avoid opening a mobile keyboard before the player taps the input.
	if not UITheme.is_touch():
		_edit.grab_focus()
		_edit.select_all()


func _label(value: String, heading: bool = false) -> Label:
	var label := ExpeditionMenuStyle.label(value)
	label.add_theme_font_override("font", ExpeditionMenuStyle.display_font() if heading else UITheme.ui_font())
	preload("res://scripts/ui/menu_detail_style.gd").clean_label(label)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _layout() -> void:
	if _panel == null:
		return
	var safe := LayoutProfile.for_viewport(get_viewport()).safe_rect
	var scale := minf(safe.size.x / 941.0, safe.size.y / 850.0)
	scale = minf(scale, 1.35)
	_panel.custom_minimum_size.x = minf(760 * scale, safe.size.x - 32 * scale)
	_panel.add_theme_stylebox_override("panel", ExpeditionMenuStyle.material_card(38 * scale, 32 * scale))
	var column := _panel.get_child(0) as VBoxContainer
	column.add_theme_constant_override("separation", roundi(18 * scale))
	(column.get_node("NameTitle") as Label).add_theme_font_size_override("font_size", roundi(51 * scale))
	for id: String in ["NameDescription", "NameStatus"]:
		(column.get_node(id) as Label).add_theme_font_size_override("font_size", roundi(26 * scale))
	_edit.add_theme_font_size_override("font_size", roundi(38 * scale))
	_edit.custom_minimum_size.y = 92 * scale
	var input_style := preload("res://scripts/ui/menu_detail_style.gd").inset(20 * scale, 12 * scale, 20 * scale)
	_edit.add_theme_stylebox_override("normal", input_style)
	_edit.add_theme_stylebox_override("focus", input_style.duplicate())
	for button: Button in [_save, _cancel]:
		button.add_theme_font_size_override("font_size", roundi(36 * scale))
		button.custom_minimum_size.y = 88 * scale


static func validation_error(value: String) -> String:
	var clean := value.strip_edges()
	if clean.length() < 2 or clean.length() > 20:
		return "Use 2–20 characters."
	for character: String in clean:
		if not character in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 ._-":
			return "Use letters, numbers, spaces, . _ or -"
	return ""


func _submit() -> void:
	if _busy:
		return
	var wanted := _edit.text.strip_edges()
	var error := validation_error(wanted)
	if not error.is_empty():
		_error.text = error
		return
	_busy = true
	_save.disabled = true
	_edit.editable = false
	_save.text = "SAVING…"
	_error.text = "Saving your name…"
	LeaderboardClient.set_display_name(wanted, func(ok: bool, _data: Dictionary) -> void:
		if not is_instance_valid(self) or not is_inside_tree():
			return
		_busy = false
		_save.disabled = false
		_edit.editable = true
		_save.text = "SAVE NAME"
		if ok:
			name_saved.emit()
		else:
			_error.text = "Couldn’t save. Check your connection and try again.")


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		dismissed.emit()
