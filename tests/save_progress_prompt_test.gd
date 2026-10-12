extends Node
## Local control input and responsive bounds. No sign-in provider is invoked.

const Prompt := preload("res://scripts/ui/save_progress_prompt.gd")
var checks := 0
var failures := 0
var sign_in_callbacks := 0
var dismiss_callbacks := 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	LeaderboardClient.set_process(false)
	var original_touch: bool = GameConfig.force_touch
	var original_insets: Vector4 = LayoutProfile.forced_insets
	var saved := SaveManager.data.duplicate(true)
	for dimensions: Vector2i in [Vector2i(1672, 941), Vector2i(941, 1672),
			Vector2i(1470, 900), Vector2i(390, 844), Vector2i(844, 390), Vector2i(568, 320)]:
		GameConfig.force_touch = dimensions.y > dimensions.x
		LayoutProfile.forced_insets = Vector4.ONE * (24.0 if GameConfig.force_touch else 0.0)
		var viewport := SubViewport.new()
		viewport.size = dimensions
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(viewport)
		var prompt := Prompt.new()
		prompt.sign_in_requested.connect(func() -> void: sign_in_callbacks += 1)
		prompt.dismissed.connect(func() -> void: dismiss_callbacks += 1)
		viewport.add_child(prompt)
		await _frames(3)
		_check_layout(prompt, viewport, str(dimensions))
		var sign_ins_before := sign_in_callbacks
		var dismissals_before := dismiss_callbacks
		await _click(viewport, prompt.get_node("SaveProgressDismiss") as Button)
		check(dismiss_callbacks == dismissals_before + 1 and sign_in_callbacks == sign_ins_before,
			"Not now click emits dismissal only at " + str(dimensions))
		check(SaveManager.data == saved, "dismissal preserves guest save at " + str(dimensions))
		await _click(viewport, prompt.get_node("SaveProgressSignIn") as Button)
		check(sign_in_callbacks == sign_ins_before + 1 and dismiss_callbacks == dismissals_before + 1,
			"sign-in click invokes only supplied callback at " + str(dimensions))
		check(prompt.find_children("*", "HTTPRequest", true, false).is_empty(),
			"prompt itself owns no auth/network request")
		var cancel := InputEventAction.new()
		cancel.action = "ui_cancel"
		cancel.pressed = true
		prompt._unhandled_key_input(cancel)
		check(dismiss_callbacks == dismissals_before + 2 and sign_in_callbacks == sign_ins_before + 1,
			"cancel dismissal never signs in")
		# Resize the same instance, rather than remounting a different layout.
		viewport.size = Vector2i(dimensions.y, dimensions.x)
		GameConfig.force_touch = viewport.size.y > viewport.size.x
		LayoutProfile.forced_insets = Vector4.ONE * (24.0 if GameConfig.force_touch else 0.0)
		await _frames(3)
		_check_layout(prompt, viewport, "rotated " + str(viewport.size))
		check(viewport.get_child_count() == 1 and SaveManager.data == saved,
			"rotation preserves one prompt and guest save")
		viewport.free()
	GameConfig.force_touch = original_touch
	LayoutProfile.forced_insets = original_insets
	for player: AudioStreamPlayer in AudioManager._sfx_pool:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.15).timeout
	print("[save-progress-prompt] %d/%d passed" % [checks - failures, checks])
	get_tree().quit(0 if failures == 0 else 1)


func _check_layout(prompt: Control, viewport: SubViewport, context: String) -> void:
	var safe := LayoutProfile.for_viewport(viewport).safe_rect
	var panel := prompt.get_node("SaveProgressPanel") as Control
	check(safe.grow(1).encloses(panel.get_global_rect()), "complete panel inside safe view: " + context)
	var previous_end := -INF
	for node_name: String in ["SaveProgressTitle", "SaveProgressDescription", "SaveProgressNotice",
			"SaveProgressSignIn", "SaveProgressDismiss"]:
		var control := prompt.get_node(node_name) as Control
		var rect := control.get_global_rect()
		check(control.is_visible_in_tree() and panel.get_global_rect().grow(1).encloses(rect),
			"panel encloses " + node_name + ": " + context)
		check(rect.position.y >= previous_end - 1.0, "copy/actions do not overlap: " + node_name + ": " + context)
		previous_end = rect.end.y
		if control is Label:
			var label := control as Label
			check(label.get_visible_line_count() == label.get_line_count()
				and label.get_line_count() * label.get_line_height() <= rect.size.y + 1.0,
				"all text lines visible: " + node_name + ": " + context)
			var widest_line := 0.0
			for line: String in label.text.split("\n"):
				widest_line = maxf(widest_line, label.get_theme_font("font").get_string_size(
					line, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")).x)
			check(widest_line <= rect.size.x + 1.0, "complete authored line fits: " + node_name + ": " + context)
		elif control is Button:
			var button := control as Button
			var font := button.get_theme_font("font")
			var font_size := button.get_theme_font_size("font_size")
			check(font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= rect.size.x * 0.90
				and font.get_height(font_size) <= rect.size.y * 0.80,
				"complete button label fits with padding: " + node_name + ": " + context)
	var avatar := prompt.get_node("SaveProgressAvatar") as TextureRect
	check(avatar.texture != null and safe.grow(1).encloses(avatar.get_global_rect()),
		"complete illustrated avatar visible: " + context)
	check(avatar.get_global_rect().end.y <= (prompt.get_node("SaveProgressTitle") as Control).get_global_rect().position.y,
		"avatar does not overlap prompt title: " + context)


func _click(viewport: SubViewport, button: Button) -> void:
	var position := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	viewport.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		event.pressed = pressed
		event.position = position
		event.global_position = position
		viewport.push_input(event, true)
		await _frames(1)


func _frames(count: int) -> void:
	for index: int in count:
		await get_tree().process_frame


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("[save-progress-prompt] " + message)
