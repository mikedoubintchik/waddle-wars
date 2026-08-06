extends Control
## Global leaderboard screen: course tabs, top-20 list from the online API,
## the player's own rank when signed in, and optional Clerk sign-in (web).

const TABS: Array[Dictionary] = [
	{"mode": "time", "course": "glacier", "label": "Glacier"},
	{"mode": "time", "course": "aurora", "label": "Aurora"},
	{"mode": "time", "course": "iceberg", "label": "Iceberg"},
	{"mode": "endless", "course": "endless", "label": "Endless"},
]

var _tab_index: int = 0
var _tab_buttons: Array[Button] = []
var _list_box: VBoxContainer
var _status_label: Label
var _auth_button: Button
var _auth_label: Label
var _name_row: HBoxContainer = null
var _name_edit: LineEdit = null
var _fetch_serial: int = 0


func _ready() -> void:
	UITheme.make_background(self)
	UITheme.apply_ui_scale(self)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", UITheme.spacing(12))
	center.add_child(vbox)

	var title := UITheme.heading("Leaderboard", 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	vbox.add_child(UITheme.accent_rule(320.0))

	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 12)
	vbox.add_child(tabs)
	for i: int in TABS.size():
		var tab: Dictionary = TABS[i]
		var button := UITheme.make_button(String(tab["label"]), Vector2(160, 56), 24)
		button.toggle_mode = true
		UITheme.hook_sounds(button)
		button.pressed.connect(_on_tab.bind(i))
		tabs.add_child(button)
		_tab_buttons.append(button)

	var panel := PanelContainer.new()
	var style := UITheme.make_panel_style(Color(0.075, 0.129, 0.220, 0.92))
	style.content_margin_left = 32.0
	style.content_margin_right = 32.0
	style.content_margin_top = 20.0
	style.content_margin_bottom = 20.0
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(640, 520)
	vbox.add_child(panel)
	var panel_box := VBoxContainer.new()
	panel_box.add_theme_constant_override("separation", 8)
	panel.add_child(panel_box)
	_status_label = UITheme.sub_label("Loading…", 24)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel_box.add_child(_status_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel_box.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_list_box)

	_build_auth_row(vbox)

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 16)
	vbox.add_child(button_row)
	# navigator.share needs the press's user gesture, so share runs directly
	# in the handler; the clipboard fallback confirms with a toast.
	var challenge := ShareManager.make_share_button("Challenge Friends", Vector2(300, 56), 24)
	UITheme.hook_sounds(challenge)
	challenge.pressed.connect(func() -> void:
		ShareManager.share_with_toast(self, ShareManager.compose_challenge_text()))
	button_row.add_child(challenge)
	var back := UITheme.make_button("Back", Vector2(200, 56), 26)
	UITheme.hook_sounds(back)
	back.pressed.connect(_go_back)
	button_row.add_child(back)

	UITheme.attach_swipe_back(self, _go_back)
	var entrance_items: Array[Control] = [title, tabs, panel]
	UITheme.play_entrance(self, entrance_items)
	LeaderboardClient.auth_changed.connect(_on_auth_changed)
	_select_tab(0)
	AudioManager.play_music("music_title")


func _build_auth_row(parent: Control) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	_auth_label = UITheme.sub_label("", 22)
	_auth_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_auth_label)
	if LeaderboardClient.can_sign_in():
		_auth_button = UITheme.make_button("Sign In", Vector2(200, 52), 22)
		UITheme.hook_sounds(_auth_button)
		_auth_button.pressed.connect(func() -> void:
			if LeaderboardClient.signed_in:
				LeaderboardClient.sign_out()
			else:
				_auth_button.text = "Opening…"
				LeaderboardClient.sign_in())
		row.add_child(_auth_button)
	# Signed-in players can pick the name shown on the boards.
	_name_row = HBoxContainer.new()
	_name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_name_row.add_theme_constant_override("separation", 12)
	_name_row.visible = false
	parent.add_child(_name_row)
	var name_label := UITheme.sub_label("Gamer name:", 20)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_row.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.max_length = 20
	_name_edit.placeholder_text = "2-20 letters/numbers"
	_name_edit.custom_minimum_size = Vector2(260, 48)
	_name_edit.add_theme_font_size_override("font_size", 20)
	_name_row.add_child(_name_edit)
	var save_button := UITheme.make_button("Save", Vector2(110, 48), 20)
	UITheme.hook_sounds(save_button)
	save_button.pressed.connect(func() -> void:
		var wanted := _name_edit.text.strip_edges()
		if wanted.length() < 2:
			_status_label.text = "Name needs at least 2 characters."
			return
		save_button.text = "…"
		LeaderboardClient.set_display_name(wanted, func(ok: bool, data: Dictionary) -> void:
			if not is_instance_valid(save_button):
				return
			save_button.text = "Save"
			if ok:
				_status_label.text = "Name saved: %s" % String(data.get("name", wanted))
				_select_tab(_tab_index)
			else:
				_status_label.text = "Couldn't save name: %s" % String(data.get("error", "error"))))
	_name_row.add_child(save_button)
	_refresh_auth_row()


func _refresh_auth_row() -> void:
	if LeaderboardClient.can_sign_in():
		if LeaderboardClient.signed_in:
			_auth_label.text = "Signed in as %s" % LeaderboardClient.display_name
			_auth_button.text = "Sign Out"
		else:
			_auth_label.text = "Sign in to post times and back up progress"
			_auth_button.text = "Opening…" if LeaderboardClient.sign_in_pending else "Sign In"
	else:
		_auth_label.text = "Play the web version to post scores"
	if _name_row != null:
		_name_row.visible = LeaderboardClient.can_sign_in() and LeaderboardClient.signed_in
		if _name_row.visible and _name_edit.text.is_empty():
			var stored := String(SettingsManager.get_setting("online", "display_name"))
			_name_edit.text = stored if not stored.is_empty() else LeaderboardClient.display_name


func _on_auth_changed() -> void:
	_refresh_auth_row()
	_select_tab(_tab_index)


func _on_tab(index: int) -> void:
	AudioManager.ui_click()
	_select_tab(index)


func _select_tab(index: int) -> void:
	_tab_index = index
	for i: int in _tab_buttons.size():
		_tab_buttons[i].button_pressed = i == index
	var tab: Dictionary = TABS[index]
	_status_label.text = "Loading…"
	for child in _list_box.get_children():
		child.queue_free()
	_fetch_serial += 1
	var serial := _fetch_serial
	LeaderboardClient.fetch_board(String(tab["mode"]), String(tab["course"]), 20,
		func(ok: bool, data: Dictionary) -> void:
			if not is_inside_tree() or serial != _fetch_serial:
				return
			_populate(ok, data, tab))


func _populate(ok: bool, data: Dictionary, tab: Dictionary) -> void:
	if not ok:
		_status_label.text = "Couldn't reach the leaderboard. Check your connection."
		return
	var entries: Array = data.get("entries", [])
	if entries.is_empty():
		_status_label.text = "No times posted yet — be the first!"
		return
	var mode := String(tab["mode"])
	_status_label.text = "Top %d — %s" % [entries.size(), String(tab["label"])]
	var me: Variant = data.get("me")
	var my_rank := int((me as Dictionary).get("rank", -1)) if me is Dictionary else -1
	for entry: Variant in entries:
		if not (entry is Dictionary):
			continue
		var row := entry as Dictionary
		var rank := int(row.get("rank", 0))
		_list_box.add_child(_make_row(
			rank, String(row.get("name", "?")),
			LeaderboardClient.format_value(mode, int(row.get("value", 0))),
			rank == my_rank and LeaderboardClient.signed_in))
	if me is Dictionary and my_rank > entries.size():
		_list_box.add_child(UITheme.accent_rule(200.0))
		_list_box.add_child(_make_row(
			my_rank, "You",
			LeaderboardClient.format_value(mode, int((me as Dictionary).get("value", 0))),
			true))


func _make_row(rank: int, name_text: String, value_text: String, highlight: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var color := Color(1.0, 0.9, 0.4) if highlight else Color(0.9, 0.94, 1.0)
	if rank >= 1 and rank <= 3 and not highlight:
		color = [Color(0.961, 0.773, 0.259), Color(0.788, 0.824, 0.863), Color(0.804, 0.561, 0.353)][rank - 1]
	var rank_label := Label.new()
	rank_label.text = "%d." % rank
	rank_label.custom_minimum_size = Vector2(56, 0)
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var name_label := Label.new()
	name_label.text = name_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var value_label := Label.new()
	value_label.text = value_text
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for label: Label in [rank_label, name_label, value_label]:
		label.add_theme_font_size_override("font_size", 24)
		label.add_theme_color_override("font_color", color)
		if highlight or (rank <= 3):
			label.add_theme_font_override("font", UITheme.bold_font())
		row.add_child(label)
	return row


func _go_back() -> void:
	SceneRouter.go_to(Game.SCENE_MAIN_MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		AudioManager.ui_click()
		_go_back()
