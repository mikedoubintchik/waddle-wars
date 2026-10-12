extends "res://tests/mobile_ui_audit.gd"
## Real shipped menu scenes and button callbacks, with offline transports and
## isolated state. This is navigation verification, not a raster/layout test.

class LoadingProbe extends "res://scripts/utilities/scene_router.gd":
	var requests: Array[String] = []

	func _ready() -> void:
		super._ready()
		set_process(false)

	func _change_now(path: String) -> void:
		requests.append(path)

	func _begin_threaded_load(path: String, _serial: int = -1) -> void:
		requests.append(path)

var _checks := 0
var _out := ""


func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		push_error("menu_navigation_history_test requires isolated user directory")
		get_tree().quit(2)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="): _out = arg.trim_prefix("out=")
	LeaderboardClient.set_script(OfflineLeaderboard)
	CommerceClient.set_script(OfflineCommerce)
	LeaderboardClient.set_process(false)
	CommerceClient.set_process(false)
	LeaderboardClient.force_available = false
	# The harness stays a sibling of real routed scenes, rather than being
	# unloaded when the first menu replaces the test's current scene.
	get_tree().current_scene = null
	SceneRouter.go_to(Game.SCENE_MAIN_MENU)
	await _arrived(Game.SCENE_MAIN_MENU)
	await _settings_chain()
	await _more_destinations()
	await _internal_pages()
	await _direct_entry()
	await _embedded_controls()
	await _loading_transactions()
	get_tree().current_scene.queue_free()
	get_tree().current_scene = null
	await _settle()
	for player: AudioStreamPlayer in [AudioManager._music_a, AudioManager._music_b]:
		player.stop()
		player.stream = null
	for player: AudioStreamPlayer in AudioManager._sfx_pool:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.25).timeout
	var report := {"checks": _checks, "failures": _failures,
		"limit": "Actual shipped menu traversal; offline isolated state. No native window, gameplay build, purchase, auth or network operation."}
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
		var file := FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
	print("[menu-navigation] %d/%d checks passed" % [_checks - _failures.size(), _checks])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _settings_chain() -> void:
	_press(get_tree().current_scene.get("_buttons")[3])
	await _settle()
	_check_panel("base_camp", "Home More button opens More")
	_press(_text_button(get_tree().current_scene, "SETTINGS"))
	await _arrived(Game.SCENE_SETTINGS)
	_check(SceneRouter._menu_history.size() == 1, "More to Settings stores one previous menu")
	var settings := get_tree().current_scene
	# Comfort now exposes every setting directly; its former Advanced
	# disclosure no longer exists. Traverse with a real saved preference.
	var cues := settings.find_child("Settings_accessibility_audio_visual_cues", true, false) as Button
	_check(cues != null, "Comfort preference is directly available")
	var wanted_cues := not bool(SettingsManager.get_setting("accessibility", "audio_visual_cues"))
	if cues != null:
		cues.button_pressed = wanted_cues
	_check(SettingsManager.get_setting("accessibility", "audio_visual_cues") == wanted_cues,
		"Comfort control changes its actual saved preference")
	await _settle()
	_press(settings.find_child("SettingsCategory_gameplay", true, false))
	await _settle()
	var scroll := settings.find_child("SettingsContentScroll", true, false) as ScrollContainer
	scroll.scroll_vertical = 80
	await _settle()
	var old_scroll := scroll.scroll_vertical
	_check(old_scroll > 0, "Settings traversal starts from a genuinely scrolled page")
	_press(_text_button(settings, "KEY & GAMEPAD BINDINGS"))
	await _arrived("res://scenes/menus/controls.tscn")
	_check(SceneRouter._menu_history.size() == 2, "Controls adds Settings once")
	_press(get_tree().current_scene.find_child("Back", true, false))
	await _arrived(Game.SCENE_SETTINGS)
	settings = get_tree().current_scene
	_check(settings.get("_active") == "gameplay", "Controls Back restores Settings category")
	_check(SettingsManager.get_setting("accessibility", "audio_visual_cues") == wanted_cues,
		"Controls Back preserves changed Comfort preference")
	scroll = settings.find_child("SettingsContentScroll", true, false) as ScrollContainer
	_check(scroll.scroll_vertical == old_scroll, "Controls Back restores Settings scroll")
	_check(SceneRouter._menu_history.size() == 1, "Controls Back consumes one entry")
	_press(settings.find_child("Back", true, false))
	await _arrived(Game.SCENE_MAIN_MENU)
	_check_panel("base_camp", "Settings Back restores More, not Home")
	_check(SceneRouter._menu_history.is_empty(), "Return to More leaves no duplicate scene history")
	_press(get_tree().current_scene.find_child("OverlayBack", true, false))
	await _settle()
	_check_panel("home", "More Back returns Home")


func _more_destinations() -> void:
	for entry: Array in [
		["LEADERBOARD", Game.SCENE_LEADERBOARD], ["ACHIEVEMENTS", Game.SCENE_ACHIEVEMENTS],
		["SHOP", Game.SCENE_COSMETIC_SHOP], ["CREDITS", Game.SCENE_CREDITS],
	]:
		_press(get_tree().current_scene.get("_buttons")[3])
		await _settle()
		_press(_text_button(get_tree().current_scene, entry[0]))
		await _arrived(entry[1])
		if entry[0] == "SHOP":
			# Real shop Close signal -> host Back callback -> router.
			var shop := get_tree().current_scene.get_child(-1)
			_check(shop.has_signal("closed"), "Shop runtime script loaded")
			shop.call("_close")
		elif entry[0] == "CREDITS":
			_cancel(get_tree().current_scene)
		else:
			_press(get_tree().current_scene.find_child("Back", true, false))
		await _arrived(Game.SCENE_MAIN_MENU)
		_check_panel("base_camp", String(entry[0]) + " Back restores More")
		_cancel(get_tree().current_scene)
		await _settle()
		_check_panel("home", "Escape dismisses restored More")
	# Wardrobe header shares the same history callback as other premium pages.
	_press(get_tree().current_scene.get("_buttons")[1])
	await _arrived(Game.SCENE_CUSTOMIZE)
	_press(get_tree().current_scene.find_child("Back", true, false))
	await _arrived(Game.SCENE_MAIN_MENU)
	_check_panel("home", "Wardrobe Back restores Home origin")
	_press(get_tree().current_scene.get("_buttons")[3])
	await _settle()
	Game.setup_entry_step = ""
	SceneRouter.go_to(Game.SCENE_MODE_SELECT)
	await _arrived(Game.SCENE_MODE_SELECT)
	_press(get_tree().current_scene.find_child("RaceSetupBack", true, false))
	await _arrived(Game.SCENE_MAIN_MENU)
	_check_panel("base_camp", "Race setup first-step Back restores More origin")
	_cancel(get_tree().current_scene)
	await _settle()


func _internal_pages() -> void:
	var menu := get_tree().current_scene
	_press(menu.get("_buttons")[3])
	await _settle()
	_press(_text_button(menu, "SIGN IN"))
	await _settle()
	_check_panel("account", "More account button opens Account locally")
	SceneRouter.go_to(Game.SCENE_CREDITS)
	await _arrived(Game.SCENE_CREDITS)
	_cancel(get_tree().current_scene)
	await _arrived(Game.SCENE_MAIN_MENU)
	menu = get_tree().current_scene
	_check_panel("account", "Account route round trip restores its nested page")
	_press(menu.find_child("OverlayBack", true, false))
	await _settle()
	_check_panel("base_camp", "Account Back restores previous More panel")
	_cancel(menu)
	await _settle()
	_press(menu.get("_buttons")[2])
	await _settle()
	_check_panel("missions", "Home Missions button opens Missions")
	SceneRouter.go_to(Game.SCENE_CREDITS)
	await _arrived(Game.SCENE_CREDITS)
	_cancel(get_tree().current_scene)
	await _arrived(Game.SCENE_MAIN_MENU)
	_check_panel("missions", "Routed child restores Missions origin")
	_cancel(get_tree().current_scene)
	await _settle()
	_check_panel("home", "Escape closes Missions to previous Home")
	_press(get_tree().current_scene.find_child("HomeAccountButton", true, false))
	await _settle()
	SceneRouter.go_to(Game.SCENE_SETTINGS)
	await _arrived(Game.SCENE_SETTINGS)
	_cancel(get_tree().current_scene)
	await _arrived(Game.SCENE_MAIN_MENU)
	_check_panel("account", "Routed child restores Account origin")
	_cancel(get_tree().current_scene)
	await _settle()
	_check_panel("home", "Account Escape returns Home origin")
	# A pending layout rebuild must not reopen a page already dismissed.
	menu = get_tree().current_scene
	_press(menu.get("_buttons")[3])
	await _settle()
	menu.call("_apply_safe_area")
	_cancel(menu)
	await _settle()
	_check_panel("home", "Back wins over deferred panel layout rebuild")
	_check(menu.get("_premium_overlay") == null, "Deferred redraw leaves Home unobscured")


func _direct_entry() -> void:
	# Direct controls entry has no prior route: Settings is its useful parent.
	SceneRouter._menu_history.clear()
	get_tree().current_scene.queue_free()
	get_tree().current_scene = null
	await _settle()
	SceneRouter.go_to("res://scenes/menus/controls.tscn")
	await _arrived("res://scenes/menus/controls.tscn")
	_cancel(get_tree().current_scene)
	await _arrived(Game.SCENE_SETTINGS)
	_check(SceneRouter._menu_history.is_empty(), "Direct Controls fallback does not invent history")
	_cancel(get_tree().current_scene)
	await _arrived(Game.SCENE_MAIN_MENU)
	_check_panel("home", "Direct Settings fallback reaches Home")


func _embedded_controls() -> void:
	var owner := get_tree().current_scene
	var settings := load(Game.SCENE_SETTINGS).instantiate() as Control
	settings.process_mode = Node.PROCESS_MODE_ALWAYS
	settings.set("on_back", func() -> void: settings.queue_free())
	owner.add_child(settings)
	await _settle()
	get_tree().paused = true
	_press(settings.find_child("SettingsCategory_gameplay", true, false))
	await _settle()
	_press(_text_button(settings, "KEY & GAMEPAD BINDINGS"))
	await _settle()
	var controls := settings.get("_bindings_panel") as Control
	_check(is_instance_valid(controls), "Paused embedded Settings opens Controls in place")
	_check(get_tree().paused and get_tree().current_scene == owner,
		"Opening bindings preserves existing scene and pause")
	if controls != null: _cancel(controls)
	await _settle()
	_check(settings.get("_bindings_panel") == null and settings.get("_page").visible,
		"Embedded Controls Back restores Settings")
	_check(get_tree().paused and get_tree().current_scene == owner,
		"Embedded Back preserves pause and owner scene")
	_cancel(settings)
	await _settle()
	_check(not is_instance_valid(settings), "Embedded Settings keeps its host close callback")
	get_tree().paused = false


func _loading_transactions() -> void:
	var menu := get_tree().current_scene
	_press(menu.get("_buttons")[3])
	await _settle()
	var router := LoadingProbe.new()
	add_child(router)
	router.go_to(Game.SCENE_SETTINGS)
	_check(router._menu_history.is_empty() and router._pending_menu_history.size() == 1,
		"Loading stages previous More without prematurely committing")
	router.go_to(Game.SCENE_SETTINGS)
	router.go_back()
	_check(router.requests.size() == 1 and router._pending_menu_history.size() == 1,
		"Repeated navigation during load cannot duplicate history")
	router._show_loading_recovery()
	router._retry_loading()
	_check(router._pending_menu_history.size() == 1 and router.requests.size() == 2,
		"Recovery retry reuses one pending history entry")
	router._show_loading_recovery()
	router._back_to_menu()
	_check(router._navigation_path == Game.SCENE_MAIN_MENU and router._pending_menu_history.is_empty(),
		"Explicit recovery Back to Menu resets history")
	router._commit_navigation(Game.SCENE_MAIN_MENU)
	_check(router._menu_history.is_empty(), "Recovery completion creates no phantom page")
	router._busy = false
	router._presenting = false
	router._menu_history = [
		{"path": Game.SCENE_MAIN_MENU, "state": {"panel": "base_camp"}},
		{"path": Game.SCENE_SETTINGS, "state": {"category": "gameplay"}},
	]
	router.go_back()
	_check(router._menu_history.size() == 2 and router._pending_menu_history.size() == 1,
		"Back stages a single pop until destination succeeds")
	router._show_loading_recovery()
	router._retry_loading()
	_check(router._pending_menu_history.size() == 1 and router._navigation_state.get("category") == "gameplay",
		"Failed Back retry preserves previous page state without another pop")
	router._commit_navigation(Game.SCENE_SETTINGS)
	_check(router._menu_history.size() == 1, "Successful Back retry commits exactly one pop")
	router._busy = false
	router._presenting = false
	router.go_back()
	_check(router._navigation_state.get("panel") == "base_camp", "Back can restore an internal MainMenu page")
	router._show_loading_recovery()
	router._back_to_menu()
	_check(router._navigation_state.is_empty() and router._pending_menu_history.is_empty(),
		"Explicit recovery Home clears saved panel even when destination path is unchanged")
	router._menu_history = [{"path": Game.SCENE_SETTINGS, "state": {}}]
	for path: String in [Game.SCENE_RUNNER, Game.SCENE_RACE, Game.SCENE_RESULTS]:
		router._begin_navigation(path, false)
		router._commit_navigation(path)
		_check(router._menu_history.is_empty(), "Gameplay/results route clears stale history: " + path)
	router._begin_navigation(Game.SCENE_RUNNER, false)
	router._retarget_navigation(Game.SCENE_RUNNER)
	router._commit_navigation(Game.SCENE_RUNNER)
	_check(router._menu_history.is_empty(), "Run retry never inserts a gameplay history entry")
	router.queue_free()
	await _settle()
	get_tree().paused = false


func _arrived(path: String) -> void:
	for _i in 120:
		await get_tree().process_frame
		var scene := get_tree().current_scene
		if scene != null and scene.scene_file_path == path and not SceneRouter.is_busy():
			await _settle()
			_check(true, "Arrived " + path)
			return
	_check(false, "Timed out waiting for " + path)


func _settle() -> void:
	for _i in 4: await get_tree().process_frame


func _text_button(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == text: return child
		var found := _text_button(child, text)
		if found != null: return found
	return null


func _press(button: Button) -> void:
	_check(button != null, "Shipped navigation control exists")
	if button != null: button.pressed.emit()


func _cancel(page: Node) -> void:
	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	page.call("_unhandled_input", event)


func _check_panel(panel: String, message: String) -> void:
	var menu := get_tree().current_scene
	_check(menu != null and menu.has_method("get_navigation_state")
		and menu.call("get_navigation_state").get("panel") == panel, message)
	if panel != "home":
		_check(menu.get("_premium_overlay") != null and menu.get("_premium_overlay").is_visible_in_tree(),
			"Restored panel is mounted and visible: " + panel)


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error("[menu-navigation] " + message)
	print("[menu-navigation] %s %s" % ["PASS" if ok else "FAIL", message])
