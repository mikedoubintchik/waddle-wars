class_name RaceHUD
extends CanvasLayer
## In-race HUD: position, progress, item, fish, speed, countdown, time,
## messages. Scales with the accessibility HUD-scale setting.

var manager: RaceManager = null
var player: Racer = null

var _position_label: Label
var _position_suffix: Label
var _time_label: Label
var _fish_label: Label
var _item_panel: PanelContainer
var _item_label: Label
var _item_icon: ColorRect
var _speed_bar: ProgressBar
var _progress_bar: ProgressBar
var _center_label: Label
var _checkpoint_label: Label
var _root: Control


func setup(p_manager: RaceManager, p_player: Racer) -> void:
	manager = p_manager
	player = p_player
	_build()
	manager.countdown_tick.connect(_on_countdown)
	manager.positions_updated.connect(_on_positions)
	manager.message.connect(show_message)
	player.fish_collected.connect(_on_fish)
	player.item_received.connect(_on_item_received)
	player.item_used.connect(_on_item_used)
	player.checkpoint_reached.connect(_on_checkpoint)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hud_scale := float(SettingsManager.get_setting("accessibility", "hud_scale"))
	add_child(_root)

	# Position (top left).
	var pos_box := HBoxContainer.new()
	pos_box.position = Vector2(30, 24)
	_root.add_child(pos_box)
	_position_label = Label.new()
	_position_label.text = "8"
	_position_label.add_theme_font_size_override("font_size", int(76 * hud_scale))
	_position_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_position_label.add_theme_constant_override("outline_size", 8)
	_position_label.add_theme_color_override("font_outline_color", Color(0.1, 0.2, 0.4))
	pos_box.add_child(_position_label)
	_position_suffix = Label.new()
	_position_suffix.text = "th / 8"
	_position_suffix.add_theme_font_size_override("font_size", int(30 * hud_scale))
	_position_suffix.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	pos_box.add_child(_position_suffix)

	# Time (top center).
	_time_label = Label.new()
	_time_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_time_label.anchor_left = 0.5
	_time_label.anchor_right = 0.5
	_time_label.offset_left = -80
	_time_label.offset_right = 80
	_time_label.offset_top = 22
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.add_theme_font_size_override("font_size", int(34 * hud_scale))
	_time_label.add_theme_constant_override("outline_size", 6)
	_time_label.add_theme_color_override("font_outline_color", Color(0.1, 0.2, 0.4))
	_root.add_child(_time_label)

	# Item slot (top right).
	_item_panel = PanelContainer.new()
	_item_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_item_panel.offset_left = -170
	_item_panel.offset_top = 22
	_item_panel.offset_right = -28
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.12, 0.22, 0.75)
	style.set_corner_radius_all(12)
	style.set_border_width_all(2)
	style.border_color = Color(0.5, 0.7, 0.95)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_item_panel.add_theme_stylebox_override("panel", style)
	var item_box := VBoxContainer.new()
	_item_panel.add_child(item_box)
	_item_icon = ColorRect.new()
	_item_icon.custom_minimum_size = Vector2(46 * hud_scale, 46 * hud_scale)
	_item_icon.color = Color(0.2, 0.3, 0.45)
	item_box.add_child(_item_icon)
	_item_label = Label.new()
	_item_label.text = "No Item"
	_item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_item_label.add_theme_font_size_override("font_size", int(17 * hud_scale))
	item_box.add_child(_item_label)
	_root.add_child(_item_panel)

	# Fish (bottom left).
	var fish_box := HBoxContainer.new()
	fish_box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	fish_box.offset_left = 30
	fish_box.offset_top = -76
	_root.add_child(fish_box)
	var fish_icon := Label.new()
	fish_icon.text = "><>"
	fish_icon.add_theme_font_size_override("font_size", int(30 * hud_scale))
	fish_icon.add_theme_color_override("font_color", Color(0.55, 0.85, 0.95))
	fish_box.add_child(fish_icon)
	_fish_label = Label.new()
	_fish_label.text = " 0"
	_fish_label.add_theme_font_size_override("font_size", int(34 * hud_scale))
	_fish_label.add_theme_constant_override("outline_size", 6)
	_fish_label.add_theme_color_override("font_outline_color", Color(0.1, 0.2, 0.4))
	fish_box.add_child(_fish_label)

	# Speed bar (bottom right).
	_speed_bar = ProgressBar.new()
	_speed_bar.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_speed_bar.offset_left = -230
	_speed_bar.offset_top = -56
	_speed_bar.offset_right = -30
	_speed_bar.offset_bottom = -36
	_speed_bar.max_value = 1.0
	_speed_bar.show_percentage = false
	_root.add_child(_speed_bar)

	# Course progress (bottom center).
	_progress_bar = ProgressBar.new()
	_progress_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_progress_bar.anchor_left = 0.32
	_progress_bar.anchor_right = 0.68
	_progress_bar.offset_top = -44
	_progress_bar.offset_bottom = -30
	_progress_bar.max_value = 1.0
	_progress_bar.show_percentage = false
	_root.add_child(_progress_bar)

	_checkpoint_label = Label.new()
	_checkpoint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_checkpoint_label.anchor_left = 0.5
	_checkpoint_label.anchor_right = 0.5
	_checkpoint_label.offset_left = -150
	_checkpoint_label.offset_right = 150
	_checkpoint_label.offset_top = -80
	_checkpoint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_checkpoint_label.add_theme_font_size_override("font_size", int(24 * hud_scale))
	_checkpoint_label.modulate.a = 0.0
	_root.add_child(_checkpoint_label)

	# Center message / countdown.
	_center_label = Label.new()
	_center_label.set_anchors_preset(Control.PRESET_CENTER)
	_center_label.anchor_left = 0.5
	_center_label.anchor_right = 0.5
	_center_label.anchor_top = 0.35
	_center_label.anchor_bottom = 0.35
	_center_label.offset_left = -320
	_center_label.offset_right = 320
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.add_theme_font_size_override("font_size", int(120 * hud_scale))
	_center_label.add_theme_constant_override("outline_size", 12)
	_center_label.add_theme_color_override("font_outline_color", Color(0.1, 0.2, 0.4))
	_root.add_child(_center_label)


func _process(_delta: float) -> void:
	if manager == null or player == null or not is_instance_valid(player):
		return
	if manager.started:
		_time_label.text = format_time(manager.race_time)
	_speed_bar.value = clampf(player.current_speed / Racer.SLIDE_MAX_SPEED, 0.0, 1.0)
	if player.course != null and player.course is CourseBase:
		var course := player.course as CourseBase
		if course.main_guide != null and course.main_guide.length > 1.0:
			_progress_bar.value = clampf(player.progress / course.finish_offset, 0.0, 1.0)


static func format_time(seconds: float) -> String:
	var minutes := int(seconds) / 60
	var secs := fmod(seconds, 60.0)
	return "%d:%05.2f" % [minutes, secs]


func _on_countdown(value: int) -> void:
	_center_label.text = str(value) if value > 0 else "GO!"
	_center_label.modulate = Color(1, 1, 1) if value > 0 else Color(0.4, 1.0, 0.5)
	_center_label.scale = Vector2.ONE * 1.4
	_center_label.pivot_offset = _center_label.size * 0.5
	var tween := create_tween()
	tween.tween_property(_center_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if value == 0:
		tween.tween_interval(0.5)
		tween.tween_property(_center_label, "modulate:a", 0.0, 0.4)
		tween.tween_callback(func() -> void:
			_center_label.text = ""
			_center_label.modulate.a = 1.0)


func show_message(text: String) -> void:
	_center_label.text = text
	_center_label.modulate = Color(1.0, 0.9, 0.4)
	var tween := create_tween()
	tween.tween_interval(1.6)
	tween.tween_property(_center_label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func() -> void:
		_center_label.text = ""
		_center_label.modulate.a = 1.0)


func _on_positions(_standings: Array[Racer]) -> void:
	var pos := player.race_position
	_position_label.text = str(pos)
	var suffix := "th"
	match pos:
		1: suffix = "st"
		2: suffix = "nd"
		3: suffix = "rd"
	_position_suffix.text = "%s / %d" % [suffix, manager.racers.size()]
	var colors := [Color(1.0, 0.85, 0.2), Color(0.8, 0.85, 0.9), Color(0.8, 0.6, 0.4)]
	_position_label.add_theme_color_override("font_color",
		colors[pos - 1] if pos <= 3 else Color(1, 1, 1))


func _on_fish(_racer: Racer, _value: int) -> void:
	_fish_label.text = " %d" % player.fish_count
	var tween := create_tween()
	_fish_label.scale = Vector2.ONE * 1.3
	tween.tween_property(_fish_label, "scale", Vector2.ONE, 0.18)


func _on_item_received(_racer: Racer, item_id: String) -> void:
	var info := PowerupsDB.get_item(item_id)
	_item_label.text = String(info.get("name", item_id))
	_item_icon.color = info.get("color", Color.WHITE)
	var tween := create_tween()
	_item_panel.scale = Vector2.ONE * 1.15
	_item_panel.pivot_offset = _item_panel.size * 0.5
	tween.tween_property(_item_panel, "scale", Vector2.ONE, 0.2)


func _on_item_used(_racer: Racer, _item_id: String) -> void:
	_item_label.text = "No Item"
	_item_icon.color = Color(0.2, 0.3, 0.45)


func _on_checkpoint(_racer: Racer, index: int) -> void:
	_checkpoint_label.text = "Checkpoint %d" % (index + 1)
	_checkpoint_label.modulate = Color(0.6, 0.95, 1.0, 1.0)
	AudioManager.play_sfx("sfx_checkpoint", 1.0, -6.0)
	var tween := create_tween()
	tween.tween_interval(1.0)
	tween.tween_property(_checkpoint_label, "modulate:a", 0.0, 0.5)
