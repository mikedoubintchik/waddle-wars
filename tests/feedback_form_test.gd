extends Node
## No external mail. Exercises real form controls with a deterministic transport.

class FakeClient extends FeedbackClient:
	var calls := 0
	func submit(_category: String, _message: String, _email: String) -> void:
		if busy:
			return
		calls += 1
		busy = true

var passed := 0
var failed := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	LeaderboardClient.set_process(false)
	check(FeedbackClient.validation_error("bug", "The jump failed at the ice cave.", "").is_empty(), "optional email is accepted")
	check(FeedbackClient.validation_error("idea", "More penguin colors please!", "player@example.com").is_empty(), "valid email accepted")
	for sample: Array in [["unknown", "Valid detail here.", ""], ["bug", "  short ", ""],
		["bug", "Valid detail here.", "bad address"], ["bug", "x".repeat(2001), ""],
		["bug", "🐧".repeat(1001), ""], ["bug", "Valid detail here.", "a@b.com\nBcc:x@y.com"]]:
		check(not FeedbackClient.validation_error(sample[0], sample[1], sample[2]).is_empty(), "reject malformed input before transport")
	var cases := [
		[Vector2i(941, 1672), Vector4.ZERO], [Vector2i(1672, 941), Vector4.ZERO],
		[Vector2i(800, 1422), Vector4.ZERO], [Vector2i(1280, 720), Vector4.ZERO],
		[Vector2i(1920, 1080), Vector4.ZERO],
		[Vector2i(941, 1672), Vector4(36, 36, 36, 36)],
		[Vector2i(941, 1672), Vector4(64, 56, 64, 48)],
	]
	for sample: Array in cases:
		var dimensions: Vector2i = sample[0]
		LayoutProfile.forced_insets = sample[1]
		var viewport := SubViewport.new()
		viewport.size = dimensions
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(viewport)
		var form = preload("res://scripts/ui/feedback_form.gd").new()
		form.open(viewport)
		await get_tree().process_frame
		await get_tree().process_frame
		check(form._columns.vertical == (dimensions.y > dimensions.x), "orientation selects readable form composition")
		check(form._message.is_visible_in_tree() and form._send.accessibility_name == "SEND FEEDBACK", "message and send mounted")
		check(form._hero.texture != null, "generated support artwork loaded")
		check(not form._sent and not form._status.text.contains("Sent") and not form._status.text.contains("Delivered"), "unsent form never claims delivery")
		var screen := Rect2(Vector2.ZERO, Vector2(dimensions))
		var safe := LayoutProfile.for_viewport(viewport).safe_rect
		var visible_form := form.find_child("FeedbackScroll", true, false) as ScrollContainer
		print("[feedback-form] geometry %s card=%s form=%s send=%s welcome=%s" % [dimensions,
			form._card.get_global_rect(), form._form.get_global_rect(), form._send.get_global_rect(),
			form._welcome.get_global_rect()])
		for control: Control in [form._welcome, form._message, form._email, form._status, form._send]:
			check(screen.grow(1.0).encloses(control.get_global_rect()) and visible_form.get_global_rect().grow(1.0).encloses(control.get_global_rect()), "complete feedback control fits first view: " + control.name)
			check(safe.grow(1.0).encloses(control.get_global_rect()), "feedback content respects actual safe bounds: " + control.name)
		check(form._card.get_global_rect().grow(1.0).encloses(form._send.get_global_rect()), "send remains inside enclosing form panel")
		check(screen.grow(1.0).encloses(form._card.get_global_rect()), "complete feedback panel fits viewport")
		check(not visible_form.get_v_scroll_bar().visible, "reference-sized form fits without an unnecessary vertical scrollbar")
		check(form._email_picture.visible == (dimensions.x > dimensions.y), "email envelope follows each orientation's reference")
		if form._email_picture.visible:
			check(form._email.get_global_rect().encloses(form._email_picture.get_global_rect()), "email icon remains inside padded input")
			check(form._email_picture.position.x + form._email_picture.size.x < form._email.get_theme_stylebox("normal").content_margin_left,
				"email icon clears placeholder and entered text")
		else:
			check(form._message.get_global_rect().position.x <= maxf(dimensions.x * 0.058, safe.position.x) + 1.0,
				"phone input uses larger of reference padding and safe inset, never their sum")
		check(form._send.get_global_rect().grow(1.0).encloses(form._send_caption.get_global_rect()) and form._send.get_global_rect().grow(1.0).encloses(form._send_picture.get_global_rect()), "enlarged send icon and caption fit the native action")
		check(form._count.get_theme_font("font") == UITheme.ui_font(), "character count uses quiet body typography")
		for i in form._types.size():
			var button: Button = form._types[i]
			var picture: TextureRect = form._type_pictures[i]
			var caption: Label = form._type_captions[i]
			check(button.get_global_rect().grow(1.0).encloses(picture.get_global_rect()) and button.get_global_rect().grow(1.0).encloses(caption.get_global_rect()), "category icon and caption fit native button")
			var combined := picture.get_global_rect().merge(caption.get_global_rect())
			check(absf(combined.get_center().x - button.get_global_rect().get_center().x) <= 2.0, "category icon/text group centered")
			check(caption.get_theme_color("font_shadow_color").a == 0.0, "category captions have no dark drop shadow")
		var client := FakeClient.new()
		form._client.free()
		form.add_child(client)
		form._client = client
		client.completed.connect(form._completed)
		form._send.pressed.emit()
		check(client.calls == 0 and not form._status.text.is_empty(), "empty submission stays local with useful validation")
		form._types[1].pressed.emit()
		check(form._selected == "idea" and form._types[1].button_pressed, "category selection uses real control")
		check(form._type_captions[1].get_theme_color("font_color") == Color.WHITE and form._type_captions[0].get_theme_color("font_color") == ExpeditionMenuStyle.INK, "selected category updates visible icon-caption color")
		form._message.text = "Please add a nighttime ice tunnel."
		form._email.text = "player@example.com"
		get_tree().paused = true
		form._send.pressed.emit()
		form._send.pressed.emit()
		check(client.calls == 1 and form._send.disabled and form._back.disabled, "one in-flight request prevents double send and uncertain close")
		check(get_tree().paused and form.process_mode == Node.PROCESS_MODE_ALWAYS, "form works over pause without resuming gameplay")
		client._finish(false, "Network unavailable; try again.")
		check(form._message.text == "Please add a nighttime ice tunnel." and form._email.text == "player@example.com", "failed send preserves complete draft")
		check(not form._send.disabled and form._status.text.contains("Network"), "failure is visible and retry enabled")
		await get_tree().process_frame
		check(screen.grow(1.0).encloses(form._send.get_global_rect()) and form._status.get_visible_line_count() == form._status.get_line_count(), "visible retry and complete failure message after response")
		form._send.pressed.emit()
		check(client.calls == 2, "retry sends only after explicit click")
		client._finish(true, "Delivered to support@waddlewars.io.")
		check(form._sent and not form._message.visible and form._send.accessibility_name == "BACK TO GAME", "success shows confirmation instead of another submit")
		form._send.pressed.emit()
		await get_tree().process_frame
		check(not is_instance_valid(form) and get_tree().paused, "close leaves previous pause state unchanged")
		get_tree().paused = false
		viewport.free()
	LayoutProfile.forced_insets = Vector4(-1, -1, -1, -1)
	var transport := FeedbackClient.new()
	add_child(transport)
	var replies: Array = []
	transport.completed.connect(func(ok: bool, message: String) -> void: replies.append([ok, message]))
	transport._received(HTTPRequest.RESULT_SUCCESS, 200, [], '{"ok":true}'.to_utf8_buffer())
	check(replies.back()[0], "only acknowledged SES success confirms send")
	transport._received(HTTPRequest.RESULT_SUCCESS, 200, [], '{}'.to_utf8_buffer())
	check(not replies.back()[0], "malformed success never claims delivered")
	transport._received(HTTPRequest.RESULT_SUCCESS, 429, [], '{}'.to_utf8_buffer())
	check(not replies.back()[0] and String(replies.back()[1]).contains("minute"), "rate limit gives retry guidance")
	transport._received(HTTPRequest.RESULT_TIMEOUT, 0, [], PackedByteArray())
	check(not replies.back()[0] and String(replies.back()[1]).contains("Could not confirm"), "timeout does not falsely claim delivery")
	transport.free()
	# Dispose pooled GUI one-shots before immediate Dummy-driver shutdown.
	for player: Node in AudioManager.get_children():
		if player is AudioStreamPlayer or player is AudioStreamPlayer3D:
			player.stop()
			player.stream = null
	await get_tree().create_timer(0.1).timeout
	print("[feedback-form] DONE: %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)

func check(ok: bool, label: String) -> void:
	passed += int(ok)
	failed += int(not ok)
	print("[feedback-form] %s %s" % ["PASS" if ok else "FAIL", label])
