extends Node
## Page controls use real settings/save state in an isolated test user directory.
## No sign-in, account deletion request, browser action, or HTTP call is exercised.

class SettingsFixture:
	extends "res://scripts/ui/settings_premium.gd"
	func _ready() -> void:
		_build()

class AccountFixture:
	extends "res://scripts/ui/main_menu_premium.gd"
	func _ready() -> void:
		_profile = LayoutProfile.for_viewport(get_viewport())
		_open_account_reference_overlay()

var _checks := 0
var _failures := 0


func _ready() -> void:
	LeaderboardClient.force_available = true
	LeaderboardClient.set_process(false)
	var saved := SaveManager.data.duplicate(true)
	for dimensions: Vector2i in [Vector2i(941, 1672), Vector2i(1672, 941), Vector2i(800, 1422), Vector2i(1920, 1080), Vector2i(1920, 1238)]:
		await _check_pages(dimensions)
	SaveManager.data = saved
	for player: AudioStreamPlayer in AudioManager._sfx_pool:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.25).timeout
	print("[settings-account-reference] DONE: %d/%d passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures else 0)


func _check_pages(dimensions: Vector2i) -> void:
	GameConfig.force_touch = dimensions.y > dimensions.x
	LayoutProfile.forced_insets = Vector4.ONE * (24.0 if GameConfig.force_touch else 0.0)
	var viewport := SubViewport.new()
	viewport.size = dimensions
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var settings := SettingsFixture.new()
	settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(settings)
	await _settle()
	_check(settings.find_child("ComfortHeroArtwork", true, false) != null, "comfort illustration mounted")
	var shake := settings.find_child("Settings_accessibility_camera_shake", true, false) as HBoxContainer
	_check(shake != null and shake.get_child_count() == 3, "three native camera choices")
	var low := shake.find_child("Choice_reduced", true, false) as Button
	low.button_pressed = true
	low.pressed.emit()
	_check(SettingsManager.get_setting("accessibility", "camera_shake") == "reduced", "camera choice writes existing setting key")
	var toggle := settings.find_child("Settings_accessibility_reduced_flashing", true, false) as Button
	var before := bool(SettingsManager.get_setting("accessibility", "reduced_flashing"))
	toggle.button_pressed = not before
	_check(bool(SettingsManager.get_setting("accessibility", "reduced_flashing")) != before, "native switch writes setting")
	for key: String in ["colorblind_cues", "audio_visual_cues", "pause_on_disconnect", "hud_scale", "ui_scale"]:
		_check(settings.find_child("Settings_accessibility_" + key, true, false) != null, "complete comfort setting available without a disclosure: " + key)
	var reset := settings.find_child("SettingsReset_accessibility", true, false) as Button
	reset.pressed.emit()
	_check(SettingsManager.get_setting("accessibility", "camera_shake") == "reduced", "reset first press only arms")
	reset.pressed.emit()
	_check(SettingsManager.get_setting("accessibility", "camera_shake") == SettingsManager.default_settings()["accessibility"]["camera_shake"], "second reset restores original section defaults")
	for id: String in ["gameplay", "audio", "online", "display"]:
		settings._active = id
		settings._rebuild()
		_check(settings.find_child("SettingsSection_%s" % id, true, false) != null, "category %s reachable" % id)
	settings._active = "online"
	settings._rebuild()
	var deletion := settings._deletion
	deletion.open_confirmation()
	settings._rebuild()
	_check(settings._deletion == deletion and deletion.is_confirmation_open(), "rebuild preserves confirmation identity")
	settings._back()
	_check(not deletion.is_confirmation_open(), "back dismisses confirmation first")
	settings.free()
	var menu := AccountFixture.new()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(menu)
	await _settle()
	for name: String in ["AccountExplorerPortrait", "AccountJournalStats", "AccountPrivacyCard", "OpenAccountDeletion", "AccountAuthAction", "AccountChangeName"]:
		_check(menu.find_child(name, true, false) != null, "account %s mounted" % name)
	var account_name := menu.find_child("AccountDisplayName", true, false) as Label
	_check_account_text(account_name, "display name")
	_check(account_name.text == LeaderboardClient.player_display_name(), "display name is current chosen handle")
	var name_glyph_width := account_name.get_theme_font("font").get_string_size(account_name.text, HORIZONTAL_ALIGNMENT_LEFT, -1, account_name.get_theme_font_size("font_size")).x
	_check(account_name.size.x >= name_glyph_width - 1.0, "default account name has room for actual glyphs")
	var account_scroll := menu.find_child("AccountReferenceScroll", true, false) as ScrollContainer
	_check(menu.find_child("AccountGuestFooter", true, false) == null, "removed guest footer stays absent")
	var metrics := menu.find_child("AccountMetricColumns", true, false) as HBoxContainer
	var cells: Array[Control] = []
	for child: Node in metrics.get_children():
		if child is VBoxContainer: cells.append(child)
	_check(cells.size() == 3, "three statistic columns")
	for cell: Control in cells:
		_check(absf(cell.size.x - cells[0].size.x) <= 2.0, "equal statistic widths " + cell.name)
		for item: Control in cell.get_children():
			_check(absf(item.get_global_rect().get_center().x - cell.get_global_rect().get_center().x) <= 1.0, "centered statistic " + item.name)
			_check(cell.get_global_rect().grow(1).encloses(item.get_global_rect()), "statistic stays in its column " + item.name)
			if item is Label:
				_check_account_text(item, cell.name + "/" + item.name)
				var glyph_width := item.get_theme_font("font").get_string_size(item.text, HORIZONTAL_ALIGNMENT_LEFT, -1, item.get_theme_font_size("font_size")).x
				_check(glyph_width <= item.size.x + 1, "complete statistic caption/value " + item.text)
	var before_name := LeaderboardClient.player_display_name()
	(menu.find_child("AccountChangeName", true, false) as Button).pressed.emit()
	await _settle()
	var prompt := menu._name_prompt
	_check(is_instance_valid(prompt), "account opens name editor")
	var edit := prompt.find_child("PlayerNameInput", true, false) as LineEdit
	var save := prompt.find_child("SavePlayerName", true, false) as Button
	_check(edit.max_length == 20 and edit.text == before_name, "name editor starts from chosen handle")
	edit.text = "!"
	save.pressed.emit()
	_check(not prompt._busy and LeaderboardClient.player_display_name() == before_name, "invalid name cannot mutate profile")
	var prompt_panel := prompt.find_child("AccountNamePanel", true, false) as PanelContainer
	_check(Rect2(Vector2.ZERO, Vector2(dimensions)).grow(1).encloses(prompt_panel.get_global_rect()), "name modal fits viewport")
	for id: String in ["PlayerNameInput", "SavePlayerName", "CancelPlayerName", "NameDescription", "NameStatus"]:
		var control := prompt.find_child(id, true, false) as Control
		_check(prompt_panel.get_global_rect().grow(1).encloses(control.get_global_rect()), "name field enclosed " + id)
	menu._on_back()
	await _settle()
	_check(menu._name_prompt == null and menu._premium_overlay != null, "back dismisses editor without leaving account")
	_check(LeaderboardClient.player_display_name() == before_name, "cancel leaves name unchanged")
	if dimensions.x < dimensions.y:
		var journal := menu.find_child("AccountJournalStats",true,false) as PanelContainer
		for cell: Node in journal.get_child(0).get_children():
			if cell is VBoxContainer:
				var value := cell.get_child(2) as Label
				_check(journal.get_global_rect().end.y - value.get_global_rect().end.y >= 49 * menu._account_scale(), "phone journal values clear illustrated binding")
	if dimensions.x > dimensions.y:
		var scroll := menu.find_child("AccountReferenceScroll",true,false) as ScrollContainer
		var safe := Rect2(Vector2.ZERO, Vector2(dimensions))
		_check(absf(scroll.position.x - safe.position.x - safe.size.x * 0.50) < 1.0 \
			and absf(scroll.size.x - safe.size.x * 0.44) < 1.0,"desktop account column preserves reference right inset")
		var journal := menu.find_child("AccountJournalStats",true,false) as PanelContainer
		var account_scale: float = menu._account_scale()
		_check(journal.size.y >= 275 * account_scale,"desktop journal has room for enlarged metrics")
		for cell: Node in journal.get_child(0).get_children():
			if cell is VBoxContainer:
				var value := cell.get_child(2) as Label
				_check(value.get_theme_font_size("font_size") == roundi(40 * account_scale) \
					and journal.get_global_rect().end.y - value.get_global_rect().end.y >= 40 * account_scale,"desktop journal value stays above illustrated leather binding")
		_check((menu.find_child("AccountAuthAction",true,false) as Button).find_child("IllustratedAction",true,false) != null,"desktop guest action has centered person icon and label")
	var account_deletion := menu.find_child("AccountPrivacyDeletion", true, false) as AccountDeletionPanel
	account_deletion.open_confirmation()
	var back := menu.find_child("OverlayBack", true, false) as Button
	back.pressed.emit()
	_check(menu._premium_overlay != null and not account_deletion.is_confirmation_open(), "account Back keeps page when dismissing deletion confirmation")
	menu.free()
	viewport.queue_free()
	await _settle()


func _settle() -> void:
	for index: int in 4:
		await get_tree().process_frame


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("[settings-account-reference] %s %s" % ["PASS" if ok else "FAIL", label])


func _check_account_text(label: Label, role: String) -> void:
	_check(label != null and not label.text.strip_edges().is_empty(), "nonempty account text " + role)
	if label == null: return
	_check(label.is_visible_in_tree() and label.modulate.a > 0.99 and label.self_modulate.a > 0.99, "visible account text " + role)
	var line_height := label.get_theme_font("font").get_height(label.get_theme_font_size("font_size"))
	_check(label.size.x > 24.0 and label.size.y >= floorf(line_height), "noncollapsed account text rect " + role)
	_check(label.custom_minimum_size.y >= floorf(line_height), "explicit account line height survives web shaping " + role)
	_check(label.autowrap_mode == TextServer.AUTOWRAP_OFF and label.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "single-line account truncation " + role)
