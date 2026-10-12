extends Node
## Isolated, synthetic launch-policy fixture. No HTTP, auth presentation,
## billing, provider calls or player save writes are permitted by this test.

const MenuScript = preload("res://scripts/ui/main_menu.gd")
const SettingsScene = preload("res://scenes/menus/settings.tscn")
const LegacySettingsScript = preload("res://scripts/ui/settings_menu.gd")

class AuthFixture:
	extends "res://scripts/commerce/native_auth_client.gd"
	var dispatched: int = 0
	func _request(_path: String, _body: Dictionary, _callback: Callable) -> void:
		dispatched += 1

class BillingFixture extends WaddleNativeBilling:
	var availability_calls: int = 0
	var purchase_calls: int = 0
	var restore_calls: int = 0
	func available(_product_id: String) -> bool:
		availability_calls += 1
		return true
	func purchase(_product_id: String) -> void:
		purchase_calls += 1
	func restore() -> void:
		restore_calls += 1

class CommerceFixture:
	extends "res://scripts/commerce/commerce_client.gd"
	var dispatched: int = 0
	func _ready() -> void:
		set_process(false)
	func _auth_context() -> Dictionary:
		return {"user_id": "native-mvp-fixture", "token": "synthetic-token"}
	func _dispatch_request(_method: String, _path: String, _body: Dictionary,
			_token: String, _complete: Callable) -> void:
		dispatched += 1

class BoardFixture:
	extends "res://scripts/network/leaderboard_client.gd"
	var response: Dictionary = {}
	var response_ok: bool = true
	var defer_response: bool = false
	var pending_completion: Callable
	var requests: Array[Dictionary] = []
	func _ready() -> void:
		set_process(false)
	func _dispatch_request(method: String, url: String, body: String, complete: Callable) -> void:
		requests.append({"method": method, "url": url, "body": body})
		if defer_response:
			pending_completion = complete
		else:
			complete.call(response_ok, response)

class BoardReceiver extends Node:
	var calls: int = 0
	func receive(_ok: bool, _data: Dictionary) -> void:
		calls += 1

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	var saved_process_mode := process_mode
	var saved_paused := get_tree().paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	var saved_force := GameConfig.force_native_offline_mvp
	var saved_touch := GameConfig.force_touch
	var saved_online := LeaderboardClient.force_available
	var saved_data := SaveManager.data.duplicate(true)
	var saved_settings := SettingsManager.settings.duplicate(true)
	var saved_music: Variant = AudioManager._library.get("music_title")
	# Menu structure is under test, not dummy AudioServer playback at exit.
	AudioManager._library.erase("music_title")
	_test_platform_policy()
	LeaderboardClient.force_available = true
	GameConfig.force_native_offline_mvp = true
	await _test_menu(true)
	await _test_settings(true)
	await _test_premium_settings(true)
	await _test_pause_support()
	_test_native_dispatch_guards()
	_test_native_board_projection()
	GameConfig.force_native_offline_mvp = false
	await _test_menu(false)
	await _test_settings(false)
	await _test_premium_settings(false)
	_check("earned_progress_and_cached_save_unchanged", SaveManager.data == saved_data)
	_check("existing_settings_unchanged", SettingsManager.settings == saved_settings)
	GameConfig.force_native_offline_mvp = saved_force
	GameConfig.force_touch = saved_touch
	LeaderboardClient.force_available = saved_online
	get_tree().paused = saved_paused
	process_mode = saved_process_mode
	if saved_music != null:
		AudioManager._library["music_title"] = saved_music
	await get_tree().process_frame
	print("[native_offline_mvp] DONE: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_platform_policy() -> void:
	GameConfig.force_native_offline_mvp = false
	var expected := not OS.has_feature("web") \
		and (OS.has_feature("android") or OS.has_feature("ios"))
	_check("real_platform_guard_cannot_be_enabled_by_false_qa_flag",
		GameConfig.native_offline_mvp() == expected)
	GameConfig.force_touch = true
	_check("touchscreen_is_not_native_identity", GameConfig.native_offline_mvp() == expected)
	GameConfig.force_touch = false
	GameConfig.force_native_offline_mvp = true
	_check("qa_can_only_force_offline_and_never_targets_web",
		GameConfig.native_offline_mvp() == not OS.has_feature("web"))
	var source := FileAccess.get_file_as_string("res://scripts/utilities/game_config.gd")
	var policy := source.split("static func native_offline_mvp() -> bool:")[1].split("\n\n")[0]
	_check("policy_uses_exact_android_ios_and_not_web",
		'not OS.has_feature("web")' in policy \
		and 'OS.has_feature("android") or OS.has_feature("ios")' in policy \
		and '"mobile"' not in policy and "force_touch" not in policy)


func _test_menu(native_mvp: bool) -> void:
	var menu := MenuScript.new()
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	var texts: Array[String] = []
	for button: Button in menu._buttons:
		texts.append(button.text)
	_check("runner_and_earned_customize_remain_%s" % native_mvp,
		"WADDLE RUN   ›" in texts and "Penguin" in texts)
	_check("runner_only_mvp_entry_%s" % native_mvp,
		texts.size() >= 1 and texts[0] == "WADDLE RUN   ›"
		and "WADDLE RACE" not in texts and "Waddle School" not in texts
		and "Daily Challenge" not in texts)
	_check("menu_rank_has_visual_progress_%s" % native_mvp,
		menu._xp_bar is ProgressBar
		and is_equal_approx(menu._xp_bar.value, Progression.level_progress()))
	_check("native_hides_auth_even_with_web_qa_hook" if native_mvp else "web_auth_surface_preserved",
		(menu._auth_chip_button == null) == native_mvp)
	# Secondary destinations live in the Base Camp overlay, not the Home dock.
	menu._show_base_camp()
	await get_tree().process_frame
	_check("native_hides_shop" if native_mvp else "optional_shop_preserved_off_native",
		(_find_button(menu._base_camp_overlay, "Cosmetic bundles") != null) == not native_mvp)
	var settings_entry := _find_button(menu._base_camp_overlay, "Settings & access")
	_check("main_settings_entry_remains_connected_%s" % native_mvp,
		settings_entry != null and settings_entry.is_visible_in_tree() \
		and not settings_entry.get_signal_connection_list("pressed").is_empty())
	var menu_source := FileAccess.get_file_as_string("res://scripts/ui/main_menu.gd")
	_check("main_settings_entry_uses_shared_scene_%s" % native_mvp,
		"SceneRouter.go_to(Game.SCENE_SETTINGS)" in menu_source \
		and Game.SCENE_SETTINGS == SettingsScene.resource_path)
	menu.queue_free()
	await get_tree().process_frame


func _test_settings(native_mvp: bool) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	add_child(viewport)
	# Keep legacy support/legal content coverage independently of the current
	# premium scene. The production scene is exercised separately below.
	var settings = LegacySettingsScript.new()
	settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(settings)
	await get_tree().process_frame
	await get_tree().process_frame
	for size: Vector2i in [Vector2i(960, 540), Vector2i(540, 960), Vector2i(960, 540)]:
		viewport.size = size
		await get_tree().process_frame
		await get_tree().process_frame
		var online := settings._section_cards.get("online") as Control
		var status: String = settings._account_status()
		_check("native_support_only_%s_%dx%d" % [native_mvp, size.x, size.y],
			settings._section_cards.has("support") == native_mvp \
			and _find_button(settings, "Account") != null \
			and (settings.find_child("SupportPrivacyHeading", true, false) != null) == native_mvp)
		_check("settings_policy_%s_%dx%d" % [native_mvp, size.x, size.y],
			online != null and ((_count_line_edits(online) == 0) == native_mvp) \
			and ((settings._account_deletion_panel == null) == native_mvp))
		if native_mvp:
			_check("native_copy_truthful_%dx%d" % [size.x, size.y],
				status.contains("Progress saves on this device") \
				and status.contains("No account is needed") and status.contains("no purchases") \
				and not status.contains("Cosmetic Shop") and not status.contains("Cloud backup") \
				and not (settings._reset_buttons["online"] as Button).visible)
	if native_mvp:
		_check_support_content(settings, "main")
		await _test_support_layout(settings, viewport)
		await _test_support_version(viewport)
	viewport.queue_free()
	await get_tree().process_frame


func _test_premium_settings(native_mvp: bool) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	add_child(viewport)
	var screen := SettingsScene.instantiate()
	viewport.add_child(screen)
	for _frame: int in 3:
		await get_tree().process_frame
	screen.restore_navigation_state({"category": "online"})
	for size: Vector2i in [Vector2i(960, 540), Vector2i(540, 960), Vector2i(960, 540)]:
		viewport.size = size
		for _frame: int in 4:
			await get_tree().process_frame
		_check_premium_account(screen, native_mvp, "main_%dx%d" % [size.x, size.y])
	viewport.queue_free()
	await get_tree().process_frame


func _check_premium_account(screen: Control, native_mvp: bool, context: String) -> void:
	var native_note := "Progress saves on this device. No account or purchase is required."
	var name_action := screen.find_child("SettingsAccountDisplayName", true, false) as Button
	_check("premium_account_policy_%s_%s" % [native_mvp, context],
		(name_action == null) == native_mvp
		and (screen.get("_deletion") == null) == native_mvp
		and ((native_note in _label_text(screen)) == native_mvp))
	if native_mvp:
		_check("premium_native_no_account_or_purchase_actions_%s" % context,
			screen.find_child("SettingsAccountAuth", true, false) == null
			and screen.find_child("SettingsReset_online", true, false) == null
			and _count_line_edits(screen) == 0)
	for caption: String in ["PRIVACY POLICY", "SUPPORT WEBSITE"]:
		var link := _find_button(screen, caption)
		_check("premium_published_link_%s_%s_%s" % [native_mvp, context, caption],
			link != null and link.is_visible_in_tree()
			and not link.get_signal_connection_list("pressed").is_empty())
	_check("premium_designated_support_address_%s_%s" % [native_mvp, context],
		"support@waddlewars.io" in _label_text(screen))


func _check_support_content(settings: Control, context: String) -> void:
	var cards: Dictionary = settings.get("_section_cards")
	var support := cards.get("support") as Control
	_check("support_card_exists_%s" % context, support != null)
	if support == null:
		return
	var text := _label_text(support)
	var version: Variant = ProjectSettings.get_setting("application/config/version", GameConfig.GAME_VERSION)
	var expected_version := String(version).strip_edges() if version is String else ""
	if expected_version.is_empty():
		expected_version = GameConfig.GAME_VERSION
	_check("support_contact_and_build_%s" % context,
		"Ninja Consulting LLC" in text and "ninjaconsultingllc@gmail.com" in text \
		and ("Version %s" % expected_version) in text \
		and ("Build %s" % GameConfig.BUILD_ID) in text)
	_check("support_guidance_and_safety_%s" % context,
		"device model" in text and "OS version" in text and "steps to repeat" in text \
		and "passwords" in text and "payment credentials" in text and "account tokens" in text \
		and "erase local progress" in text)
	_check("privacy_local_data_and_native_feature_scope_%s" % context,
		"Privacy & local data" in text and "stored on this device" in text \
		and "runner missions, settings and Time Trial ghosts" in text \
		and "Core gameplay works offline" in text \
		and "no account sign-in, game-account cloud sync, purchases or score posting" in text)
	_check("privacy_board_requests_and_provider_address_%s" % context,
		"selected board over HTTPS: mode, course and result limit" in text \
		and "Requests do not send your local save" in text \
		and "Cloudflare" in text and "can see your network address" in text \
		and "Avoid Leaderboard to skip these game-service requests" in text)
	_check("privacy_support_retention_and_provider_limits_%s" % context,
		"details you choose to send" in text \
		and "publisher's active mailbox within 90 days after resolution" in text \
		and "only for legal obligations or necessary fraud or security handling" in text \
		and "Gmail/Google processes email separately" in text \
		and "provider backup copies have no fixed deletion deadline from us" in text)
	_check("privacy_app_deletion_and_separate_browser_account_%s" % context,
		"Deleting the app or clearing app data can erase local progress" in text \
		and "Device backups may retain a separate copy" in text \
		and "does not delete a separate browser-game account" in text)
	_check("support_has_no_mutation_or_draft_policy_%s" % context,
		_find_button(support, "Reset") == null and not settings.get("_reset_buttons").has("support") \
		and _count_line_edits(support) == 0 and not "://" in text \
		and not "Unpublished draft" in text \
		and not "no data collected" in text and not "[PUBLICATION_DATE]" in text)
	_check("published_native_links_are_explicit_buttons_%s" % context,
		_find_button(support, "Privacy Policy") != null \
		and _find_button(support, "Support Website") != null \
		and "open in your browser" in text and "do not need to open them to play" in text)
	_check("published_native_link_destinations_are_exact_%s" % context,
		GameConfig.NATIVE_PRIVACY_URL == "https://waddlewars.io/native/privacy.html" \
		and GameConfig.NATIVE_SUPPORT_URL == "https://waddlewars.io/native/support.html")
	var source := FileAccess.get_file_as_string("res://scripts/ui/settings_menu.gd")
	var support_source := source.split("func _build_support_section() -> void:")[1].split("\n\n")[0]
	_check("privacy_information_has_no_request_launch_or_save_side_effect_%s" % context,
		not "HTTPRequest" in support_source and not "LeaderboardClient." in support_source \
		and not "JavaScriptBridge" in support_source and not "OS.shell_open" in support_source \
		and not "SaveManager." in support_source and not "SettingsManager.set" in support_source)


func _test_support_layout(settings: Control, viewport: SubViewport) -> void:
	var saved_insets := LayoutProfile.forced_insets
	var saved_touch := GameConfig.force_touch
	var accessibility: Dictionary = SettingsManager.settings["accessibility"]
	var saved_ui: Variant = accessibility["ui_scale"]
	var saved_hud: Variant = accessibility["hud_scale"]
	GameConfig.force_touch = true
	for scale: float in [1.0, 1.4]:
		accessibility["ui_scale"] = scale
		accessibility["hud_scale"] = scale
		for insets: Vector4 in [Vector4(24, 36, 24, 34), Vector4(40, 24, 12, 32)]:
			for physical_size: Vector2i in [Vector2i(540, 960), Vector2i(960, 540)]:
				# Headless geometry only: model the reduced logical canvas of a
				# larger menu scale, not actual rendered/phone-size acceptance.
				viewport.size = Vector2i(roundi(physical_size.x / scale), roundi(physical_size.y / scale))
				LayoutProfile.forced_insets = insets / scale
				# Let queued orientation rebuild/scroll restoration finish before
				# explicitly refreshing the same class for the changed insets.
				for _frame: int in 3:
					await get_tree().process_frame
				settings.call("_build_layout", LayoutProfile.for_viewport(viewport), false, 0.0)
				for _frame: int in 3:
					await get_tree().process_frame
				var case := "%dx%d_scale%.1f_insets%s" % [physical_size.x, physical_size.y, scale, insets]
				var support := (settings.get("_section_cards") as Dictionary).get("support") as Control
				var scroll := settings.get("_scroll") as ScrollContainer
				var help := _find_button(settings, "Account")
				_check("support_jump_target_%s" % case, support != null and help != null)
				if support == null or help == null:
					continue
				help.pressed.emit()
				await get_tree().process_frame
				# Account now owns the bundled support section. Scroll its real
				# content into view after choosing that category.
				scroll.scroll_vertical = roundi(support.position.y)
				await get_tree().process_frame
				var profile := LayoutProfile.for_viewport(viewport)
				var bounds := support.get_global_rect()
				_check("support_safe_horizontal_fit_%s" % case,
					bounds.position.x >= profile.safe_rect.position.x - 1.0 \
					and bounds.end.x <= profile.safe_rect.end.x + 1.0 \
					and _labels_fit_horizontally(support, bounds))
				_check("support_jump_reaches_readable_top_%s" % case,
					scroll.scroll_vertical > 0 \
					and bounds.position.y >= scroll.get_global_rect().position.y - 1.0 \
					and bounds.position.y < scroll.get_global_rect().end.y)
				var safety := support.find_child("SupportSafety", true, false) as Label
				if safety != null:
					scroll.ensure_control_visible(safety)
				await get_tree().process_frame
				_check("support_safety_scrolls_into_view_%s" % case,
					safety != null \
					and safety.get_global_rect().position.y >= scroll.get_global_rect().position.y - 1.0 \
					and safety.get_global_rect().end.y <= scroll.get_global_rect().end.y + 1.0)
				var deletion := support.find_child("SupportPrivacyDeletionWarning", true, false) as Label
				if deletion != null:
					scroll.ensure_control_visible(deletion)
				await get_tree().process_frame
				_check("privacy_final_warning_scrolls_into_view_%s" % case,
					deletion != null \
					and deletion.get_global_rect().position.y >= scroll.get_global_rect().position.y - 1.0 \
					and deletion.get_global_rect().end.y <= scroll.get_global_rect().end.y + 1.0)
	accessibility["ui_scale"] = saved_ui
	accessibility["hud_scale"] = saved_hud
	LayoutProfile.forced_insets = saved_insets
	GameConfig.force_touch = saved_touch


func _test_support_version(viewport: SubViewport) -> void:
	var original: Variant = ProjectSettings.get_setting("application/config/version", null)
	for version: Variant in ["9.8.7", "", 123]:
		ProjectSettings.set_setting("application/config/version", version)
		var screen = LegacySettingsScript.new()
		screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		viewport.add_child(screen)
		for _frame: int in 3:
			await get_tree().process_frame
		var support := (screen.get("_section_cards") as Dictionary).get("support") as Control
		var expected := "9.8.7" if version is String and version == "9.8.7" else GameConfig.GAME_VERSION
		_check("support_stamped_version_or_safe_fallback_%s" % str(version),
			support != null and ("Version %s" % expected) in _label_text(support))
		screen.queue_free()
		await get_tree().process_frame
	ProjectSettings.set_setting("application/config/version", original)


func _test_pause_support() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	add_child(viewport)
	var pause := PauseMenu.new()
	viewport.add_child(pause)
	pause._open(null, 0.0, false, true)
	var entry := _find_button(pause, "Settings")
	_check("pause_settings_entry_exists", entry != null and get_tree().paused)
	if entry != null:
		entry.pressed.emit()
		for _frame: int in 3:
			await get_tree().process_frame
		var settings := pause._settings_panel
		_check("pause_settings_preserves_paused_scene", settings != null and get_tree().paused \
			and settings.get("on_back") == Callable(pause, "_close_settings"))
		if settings != null:
			settings.restore_navigation_state({"category": "online"})
			for _frame: int in 3:
				await get_tree().process_frame
			_check_premium_account(settings, true, "pause")
			for size: Vector2i in [Vector2i(540, 960), Vector2i(960, 540)]:
				viewport.size = size
				for _frame: int in 3:
					await get_tree().process_frame
				_check_premium_account(settings, true, "pause_%dx%d" % [size.x, size.y])
				_check("pause_support_survives_rotation_%dx%d" % [size.x, size.y],
					settings.get_navigation_state().get("category") == "online" and get_tree().paused)
			var back := settings.find_child("Back", true, false) as Button
			_check("premium_pause_back_action_connected", back != null
				and not back.get_signal_connection_list("pressed").is_empty())
			if back != null:
				back.pressed.emit()
			await get_tree().process_frame
			_check("support_back_returns_to_paused_game", pause._settings_panel == null \
				and pause._paused and get_tree().paused)
	pause._close()
	_check("support_pause_teardown_unpauses", not get_tree().paused)
	viewport.queue_free()
	await get_tree().process_frame


func _find_button(node: Node, caption: String) -> Button:
	if node is Button and (node as Button).text == caption:
		return node as Button
	for child: Node in node.get_children():
		var found := _find_button(child, caption)
		if found != null:
			return found
	return null


func _label_text(node: Node) -> String:
	var text := (node as Label).text + "\n" if node is Label else ""
	for child: Node in node.get_children():
		text += _label_text(child)
	return text


func _labels_fit_horizontally(node: Node, bounds: Rect2) -> bool:
	if node is Label:
		var label := node as Label
		var rect := label.get_global_rect()
		if rect.position.x < bounds.position.x - 1.0 or rect.end.x > bounds.end.x + 1.0:
			return false
		if String(label.name).begins_with("Support") \
				and label.autowrap_mode != TextServer.AUTOWRAP_WORD_SMART:
			return false
	for child: Node in node.get_children():
		if not _labels_fit_horizontally(child, bounds):
			return false
	return true


func _test_native_dispatch_guards() -> void:
	var auth := AuthFixture.new()
	add_child(auth)
	auth.sign_in()
	_check("direct_native_signin_cannot_dispatch_or_start_timers",
		auth.dispatched == 0 and not auth.pending and auth._poll_timer == null \
		and auth._refresh_timer == null and auth._verifier.is_empty())
	auth.free()
	var billing := BillingFixture.new()
	var commerce := CommerceFixture.new()
	add_child(commerce)
	commerce._session_owner = "native-mvp-fixture"
	commerce._owner_id = "native-mvp-fixture"
	commerce._native = billing
	commerce.store_available = true
	commerce.prices = {"cozy_expedition": "synthetic price"}
	commerce._cache = {"last_account": "native-mvp-fixture", "accounts": {
		"native-mvp-fixture": {"product_ids": ["research_crew"], "verified_at": "fixture"}}}
	var before := commerce._cache.duplicate(true)
	GameConfig.force_native_offline_mvp = false
	_check("off_native_existing_purchase_gate_remains", commerce.can_purchase("cozy_expedition"))
	var availability_before := billing.availability_calls
	GameConfig.force_native_offline_mvp = true
	_check("native_purchase_unavailable_before_adapter", not commerce.can_purchase("cozy_expedition") \
		and billing.availability_calls == availability_before)
	commerce.refresh_store()
	commerce.purchase("cozy_expedition")
	commerce.restore_purchases()
	_check("direct_shop_actions_cannot_request_or_bill", commerce.dispatched == 0 \
		and billing.purchase_calls == 0 and billing.restore_calls == 0 \
		and commerce._requests.is_empty() and not commerce.busy)
	_check("native_shop_copy_has_no_account_or_restore_prompt",
		commerce.status == commerce.NATIVE_OFFLINE_STATUS \
		and not commerce.store_available and commerce.prices.is_empty())
	_check("cached_verified_cosmetics_preserved", commerce._cache == before \
		and commerce.owns_cosmetic("hat_headset"))
	commerce._native = null
	billing.free()
	commerce.free()


func _test_native_board_projection() -> void:
	var client := BoardFixture.new()
	add_child(client)
	var remote := {
		"mode": "time", "course": "glacier",
		"entries": [
			{"rank": 1, "value": 81234, "name": "REMOTE_UNREVIEWED_NAME",
				"avatar_url": "https://invalid.example/avatar", "user_id": "remote-id"},
			{"rank": 3.0, "value": 99123.0, "name": "SECOND_REMOTE_NAME"},
		],
		"me": {"rank": 7.0, "value": 112233.0, "name": "REMOTE_ME", "extra": "remote-text"},
		"notice": "REMOTE_TOP_LEVEL_TEXT",
	}
	var original := remote.duplicate(true)
	GameConfig.force_native_offline_mvp = true
	var native_reply := _board_reply(client, true, remote)
	var expected := {"entries": [
		{"rank": 1, "value": 81234, "name": "Penguin #1"},
		{"rank": 3, "value": 99123, "name": "Penguin #3"},
	], "me": {"rank": 7, "value": 112233}}
	_check("native_board_success_callback_once", native_reply["calls"] == 1 and native_reply["ok"])
	_check("native_board_projects_only_authored_aliases_and_numeric_fields", native_reply["data"] == expected)
	_check("native_board_keeps_response_source_unchanged", remote == original)
	_check("native_board_read_only_request_unchanged", client.requests.size() == 1 \
		and client.requests[0] == {"method": "GET",
			"url": "%s/api/leaderboard?mode=time&course=glacier&limit=20" % client.API_BASE, "body": ""} \
		and client._token.is_empty())
	var projected_entries: Array = native_reply["data"]["entries"]
	var projected_row: Dictionary = projected_entries[0]
	projected_row["name"] = "LOCAL_TEST_MUTATION"
	_check("native_board_projection_does_not_alias_source_rows", remote == original)
	var malformed := {"entries": "REMOTE_NOT_AN_ARRAY", "me": {"name": "REMOTE_ME"},
		"extra": "REMOTE_EXTRA"}
	var empty_expected := {"entries": [], "me": null}
	_check("native_board_nonarray_entries_fail_closed", _board_reply(client, true, malformed)["data"] == empty_expected)
	_check("native_board_missing_entries_and_me_safe", _board_reply(client, true, {})["data"] == empty_expected)
	var mixed := {"entries": [
		null, "REMOTE_TEXT_ROW", 12, [], {},
		{"rank": 0, "value": 1}, {"rank": -1, "value": 1},
		{"rank": 1.5, "value": 1}, {"rank": "1", "value": 1},
		{"rank": true, "value": 1}, {"rank": INF, "value": 1},
		{"rank": NAN, "value": 1}, {"rank": 9223372036854775808.0, "value": 1},
		{"rank": 1, "value": -1}, {"rank": 1, "value": 1.5},
		{"rank": 1, "value": "1"}, {"rank": 1, "value": true},
		{"rank": 1, "value": INF}, {"rank": 1, "value": NAN},
		{"rank": 1, "value": 9223372036854775808.0}, {"rank": 1}, {"value": 1},
		{"rank": 2, "value": 0, "name": "REMOTE_ZERO_SCORE"},
		{"rank": 5.0, "value": 42.0, "name": "REMOTE_FLOAT_ROW"},
		{"rank": 8, "value": 77},
	], "me": {"rank": 11, "value": "42", "name": "REMOTE_ME"}}
	_check("native_board_drops_malformed_rows_without_reindexing", _board_reply(client, true, mixed)["data"] == {
		"entries": [{"rank": 2, "value": 0, "name": "Penguin #2"},
			{"rank": 5, "value": 42, "name": "Penguin #5"},
			{"rank": 8, "value": 77, "name": "Penguin #8"}], "me": null})
	var invalid_me_safe := true
	for me: Variant in [null, [], "REMOTE_ME", {"rank": 0, "value": 1},
			{"rank": 1.5, "value": 1}, {"rank": 1, "value": -1},
			{"rank": 1, "value": INF}, {"rank": 1, "name": "REMOTE_ME"}]:
		var reply := _board_reply(client, true, {"entries": [], "me": me})
		invalid_me_safe = invalid_me_safe and reply["data"] == empty_expected
	_check("native_board_optional_or_malformed_me_safe", invalid_me_safe)
	GameConfig.force_native_offline_mvp = false
	var web_reply := _board_reply(client, true, remote)
	_check("non_native_board_payload_exactly_preserved", web_reply["calls"] == 1 \
		and web_reply["ok"] and web_reply["data"] == original)
	var failure := {"error": "synthetic offline", "entries": original["entries"], "extra": "remote-error-text"}
	for native_mvp: bool in [false, true]:
		GameConfig.force_native_offline_mvp = native_mvp
		var failed := _board_reply(client, false, failure)
		_check("board_failure_payload_unchanged_%s" % native_mvp,
			failed["calls"] == 1 and not failed["ok"] and failed["data"] == failure)
	GameConfig.force_native_offline_mvp = true
	client.defer_response = true
	var observed := {"calls": 0, "ok": false, "data": {}}
	client.fetch_board("time", "glacier", 20, func(ok: bool, data: Dictionary) -> void:
		observed["calls"] += 1
		observed["ok"] = ok
		observed["data"] = data)
	client.pending_completion.call(true, remote)
	client.pending_completion.call(true, remote)
	_check("native_board_existing_one_shot_delivery_preserved", observed["calls"] == 1 \
		and observed["ok"] and observed["data"] == expected)
	var changed_account := {"calls": 0, "ok": false, "data": {}}
	client.fetch_board("time", "glacier", 20, func(ok: bool, data: Dictionary) -> void:
		changed_account["calls"] += 1
		changed_account["ok"] = ok
		changed_account["data"] = data)
	client._auth_generation += 1
	client.pending_completion.call(true, remote)
	_check("native_board_existing_auth_generation_gate_preserved", changed_account["calls"] == 1 \
		and not changed_account["ok"] and changed_account["data"] == {"error": "account_changed"})
	var departed := BoardReceiver.new()
	var departed_callback := departed.receive
	client.fetch_board("time", "glacier", 20, departed_callback)
	departed.free()
	_check("native_board_original_bound_callback_invalidated", not departed_callback.is_valid())
	# The engine stderr gate must also stay clean when the wrapped original target
	# has disappeared; checking only the wrapper's validity loses that protection.
	client.pending_completion.call(true, remote)
	_check("native_board_late_reply_keeps_freed_callback_invalid", not departed_callback.is_valid())
	_check("board_fixture_never_signs_in_or_starts_cloud_sync", not client.signed_in \
		and not client.is_processing() and client._pending_bridge.is_empty() \
		and client._save_push_timer == -1.0 and client._token.is_empty())
	client.free()


func _board_reply(client: BoardFixture, ok: bool, response: Dictionary) -> Dictionary:
	client.response_ok = ok
	client.response = response
	var observed := {"calls": 0, "ok": false, "data": {}}
	client.fetch_board("time", "glacier", 20, func(reply_ok: bool, data: Dictionary) -> void:
		observed["calls"] += 1
		observed["ok"] = reply_ok
		observed["data"] = data)
	return observed


func _count_line_edits(node: Node) -> int:
	var count := 1 if node is LineEdit else 0
	for child: Node in node.get_children():
		count += _count_line_edits(child)
	return count


func _check(label: String, ok: bool) -> void:
	if ok:
		_passed += 1
		print("[native_offline_mvp] PASS %s" % label)
	else:
		_failed += 1
		print("[native_offline_mvp] FAIL %s" % label)
