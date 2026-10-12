extends Node
## Live Settings controls, actual setting writes and responsive bounds; no network/UI.
class SettingsFixture:
	extends "res://scripts/ui/settings_premium.gd"
	func _ready() -> void:
		_build()

var _checks := 0
var _failures := 0

func _ready() -> void:
	LeaderboardClient.force_available = true
	LeaderboardClient.set_process(false)
	var saved := SettingsManager.settings.duplicate(true)
	for dimensions: Vector2i in [Vector2i(941, 1672), Vector2i(1672, 941), Vector2i(444, 792)]:
		await _check_shape(dimensions, Vector4.ONE * (24.0 if dimensions.x < dimensions.y else 0.0))
	await _check_shape(Vector2i(800,1422), Vector4.ONE * 24.0)
	await _check_shape(Vector2i(941,1672), Vector4.ONE * 64.0)
	LayoutProfile.forced_insets = Vector4(-1,-1,-1,-1)
	SettingsManager.settings = saved
	for player: AudioStreamPlayer in [AudioManager._music_a, AudioManager._music_b] + AudioManager._sfx_pool:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.25).timeout
	print("[settings-tabs-reference] DONE: %d/%d passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures else 0)

func _check_shape(dimensions: Vector2i, insets: Vector4) -> void:
	GameConfig.force_touch = dimensions.x < dimensions.y
	LayoutProfile.forced_insets = insets
	var viewport := SubViewport.new()
	viewport.size = dimensions
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var page := SettingsFixture.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(page)
	await _settle()
	for category: String in ["accessibility", "audio", "display", "gameplay", "online"]:
		page._active = category
		page._rebuild()
		await _settle()
		var scroll := page.find_child("SettingsContentScroll", true, false) as ScrollContainer
		var card := page.find_child("SettingsReferenceCard", true, false) as Control
		_check(Rect2(Vector2.ZERO, Vector2(dimensions)).grow(1).encloses(card.get_global_rect()), "%s card within %s" % [category, dimensions])
		_check((page.find_child("SettingsCategoryHeroArtwork", true, false) != null) == (category not in ["online", "accessibility"]), "%s reference header illustration contract" % category)
		if dimensions.x < dimensions.y:
			_check(absf(card.size.x - dimensions.x * 0.96) < 1 and absf(card.position.y - dimensions.y * 0.285) < 1, "%s portrait painted card follows full-viewport reference" % category)
			_check(scroll.global_position.x >= insets.x - 1 and scroll.get_global_rect().end.x <= dimensions.x - insets.z + 1, "%s interactive content respects actual safe insets" % category)
			var footer := page.find_child("SettingsFixedFooter",true,false) as Control
			_check(footer.get_global_rect().end.y <= dimensions.y - insets.w + 1, "%s footer clears actual bottom safe inset" % category)
		if category != "online":
			var reset := page.find_child("SettingsReset_" + category,true,false) as Button
			_check(reset.size.y >= page._s(90 if dimensions.x > dimensions.y else 110) - 1, "%s reset keeps full reference-height action" % category)
			var titles := page.find_children("SettingTitle", "Label", true, false)
			for title: Label in titles:
				_check(title.get_theme_color("font_shadow_color").a == 0.0, "%s row type stays crisp without inherited shadow" % category)
			if dimensions.x < dimensions.y and not titles.is_empty():
				_check(titles[0].global_position.x >= dimensions.x * 0.19, "%s reference icon-label gutter retained" % category)
		if category == "online":
			print("[settings-tabs-reference] Account card=%s scroll=%s panelmin=%s" % [card.get_global_rect(),scroll.get_global_rect(),card.get_combined_minimum_size()])

		var note := page.find_child("SettingsSaveNote", true, false) as Label
		_check(card.get_global_rect().encloses(note.get_global_rect()), "%s autosave note stays visible" % category)
		if category == "accessibility":
			for key: String in ["camera_shake", "reduced_flashing", "high_contrast_pickups", "colorblind_cues", "audio_visual_cues", "pause_on_disconnect", "hud_scale", "ui_scale"]:
				var control := page.find_child("Settings_accessibility_" + key,true,false) as Control
				_check(control != null and scroll.get_global_rect().grow(1).encloses(control.get_global_rect()), "all eight Comfort controls visible: " + key)
		elif category == "audio":
			for key: String in ["master_volume", "music_volume", "sfx_volume"]:
				var slider := page.find_child("Settings_audio_" + key, true, false) as HSlider
				var readout := page.find_child("SettingsValue_audio_" + key, true, false) as Label
				_check(scroll.get_global_rect().grow(1).encloses(slider.get_global_rect()), "sound slider fully visible: " + key)
				_check(slider.min_value == 0.0 and slider.max_value == 1.0 and slider.step == 0.05, "sound numeric domain preserved: " + key)
				slider.value = 0.35
				_check(is_equal_approx(float(SettingsManager.get_setting("audio", key)), 0.35) and readout.text == "35%", "percent presentation writes normalized value: " + key)
				_check(slider.get_theme_stylebox("grabber_area").bg_color == ExpeditionMenuStyle.CORAL and slider.has_theme_icon_override("grabber"), "coral rail and illustrated ivory thumb: " + key)
			for key: String in ["muted", "mute_unfocused"]:
				var toggle := page.find_child("Settings_audio_" + key, true, false) as Button
				_check(scroll.get_global_rect().grow(1).encloses(toggle.get_global_rect()), "sound switch fully visible: " + key)
				var before := bool(SettingsManager.get_setting("audio", key))
				toggle.button_pressed = not before
				_check(bool(SettingsManager.get_setting("audio", key)) == not before, "sound switch writes value: " + key)
			var reset := page.find_child("SettingsReset_audio", true, false) as Button
			reset.pressed.emit()
			_check(is_equal_approx(float(SettingsManager.get_setting("audio", "master_volume")), 0.35), "reset first press only arms")
			reset.pressed.emit()
			_check(is_equal_approx(float(SettingsManager.get_setting("audio", "master_volume")), 0.9), "second reset restores genuine sound defaults")
		elif category == "display":
			for key: String in ["quality_preset", "shadow_quality", "particle_quality", "msaa", "fps_limit"]:
				var choices := page.find_child("Settings_display_" + key, true, false) as HBoxContainer
				_check(choices != null and choices.get_child_count() == page.OPTIONS[key].size(), "all graphics options presented: " + key)
				_check(scroll.get_global_rect().grow(1).encloses(choices.get_global_rect()), "shared Web graphics choices fully visible: " + key)
				var selected := choices.get_child(0) as Button
				selected.button_pressed = true
				selected.pressed.emit()
				_check(SettingsManager.get_setting("display", key) == page.OPTIONS[key][0][0], "choice writes exact typed value: " + key)
			var toggle := page.find_child("Settings_display_vsync", true, false) as Button
			print("[settings-tabs-reference] graphics %s scroll=%s finalcard=%s" % [dimensions,scroll.get_global_rect(),(toggle.get_parent().get_parent() as Control).get_global_rect()])
			_check(scroll.get_global_rect().grow(1).encloses(toggle.get_global_rect()), "V-Sync fits shared six-row graphics view")
			_check(scroll.get_global_rect().grow(1).encloses((toggle.get_parent().get_parent() as Control).get_global_rect()), "complete V-Sync card stays above fixed footer")
		elif category == "gameplay":
			for key: String in ["steer_sensitivity", "slide_toggle_mode", "tutorial_prompts", "vibration", "touch_controls", "touch_scale", "touch_opacity", "gamepad_deadzone"]:
				var control := page.find_child("Settings_gameplay_" + key, true, false) as Control
				_check(control != null, "real Controls setting retained: " + key)
				if dimensions.x > dimensions.y:
					_check(scroll.get_global_rect().grow(1).encloses(control.get_global_rect()), "desktop Controls fits two-column first view: " + key)
					if key in ["touch_scale", "touch_opacity", "gamepad_deadzone"]:
						var caption := control.get_parent().get_node("SettingTitle") as Label
						_check(caption.get_line_count() == 1, "desktop Controls slider caption remains one line: " + key)
			_check(page.find_child("Settings_gameplay_tilt_steering", true, false) != null == TiltSteering.supported(), "tilt controls follow genuine platform availability")
			if dimensions.x > dimensions.y:
				var bindings := page.find_child("SettingsBindingsAction", true, false) as Button
				_check(scroll.get_global_rect().grow(1).encloses(bindings.get_global_rect().grow(2)), "complete desktop bindings action has clearance above fixed footer")
		elif category == "online":
			_check(_text_contains(page, "support@waddlewars.io") and not _text_contains(page, "ninjaconsultingllc@gmail.com"), "Account shows designated support address")
			for element: String in ["SettingsAccountIdentity", "SettingsAccountName", "SettingsAccountPrivacy"]:
				var block := page.find_child(element, true, false) as Control
				_check(block != null and scroll.get_global_rect().grow(1).encloses(block.get_global_rect()), "Account reference card fully visible: " + element)
			var name_action := page.find_child("SettingsAccountDisplayName", true, false) as Button
			_check(name_action != null and name_action.text == "CHANGE NAME"
				and scroll.get_global_rect().grow(1).encloses(name_action.get_global_rect()),
				"Account opens explicit enclosed Change Name action")
			if dimensions.x < dimensions.y:
				var chevrons := page.find_children("AccountLinkChevron", "TextureRect", true, false)
				_check(chevrons.size() == 2, "phone privacy and support keep navigation indicators")
				for chevron: TextureRect in chevrons:
					_check(chevron.size.y > 0 and (chevron.get_parent() as Control).get_global_rect().encloses(chevron.get_global_rect()), "phone navigation chevron has positive enclosed bounds")
			var deletion_title := page._deletion.get_node("DeletionReferenceRow/DeletionReferenceCopy").get_child(0) as Label
			_check(deletion_title.get_theme_font("font") == ExpeditionMenuStyle.display_font(), "Account deletion title uses shared heading face")
			if dimensions.x > dimensions.y:
				var footer := page.find_child("SettingsFixedFooter", true, false) as Control
				_check(footer.size.y >= page._s(70) - 1 and note.get_global_rect().end.y < card.get_global_rect().end.y - page._s(25), "desktop Account footer has readable bottom breathing room")
			name_action.pressed.emit()
			await _settle()
			var prompt := page._name_prompt
			_check(prompt != null and prompt.is_visible_in_tree(), "Change Name opens actual shared editor")
			var edit := prompt.find_child("PlayerNameInput", true, false) as LineEdit
			_check(edit != null and edit.size.x > 100 and edit.size.y > 30
				and edit.get_theme_color("font_color").get_luminance() < 0.35,
				"explicit name editor has readable dark type and positive input bounds")
			edit.text = "Test Explorer"
			edit.text_submitted.emit(edit.text)
			await _settle()
			_check(LeaderboardClient.player_display_name() == "Test Explorer"
				and page._name_prompt == null, "Account name persists through identity-scoped accessor and closes editor")
			var deletion := page._deletion
			deletion.open_confirmation()
			page._rebuild()
			_check(page._deletion == deletion and deletion.is_confirmation_open(), "Account rebuild preserves live deletion confirmation")
			page._back()
			_check(not deletion.is_confirmation_open(), "Account Back closes confirmation first")
	page.free()
	viewport.free()
	GameConfig.force_touch = false
	await _settle()

func _text_contains(node: Node, text: String) -> bool:
	if node is Label and text in (node as Label).text:
		return true
	for child: Node in node.get_children():
		if _text_contains(child, text):
			return true
	return false

func _settle() -> void:
	for index: int in 5:
		await get_tree().process_frame

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("[settings-tabs-reference] %s %s" % ["PASS" if ok else "FAIL", message])
