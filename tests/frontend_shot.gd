extends Node
## Windowed capture for title, loader, or pre-route boot.
## godot res://tests/frontend_shot.tscn -- screen=title out=/tmp/title.png w=1920 h=1080

var _screen: String = "title"
var _out: String = "qa_shots/frontend/title.png"
var _wait: float = 1.2
var _customize_item: String = ""
var _elapsed: float = 0.0
var _captured: bool = false


## Populated layout fixture replaces fetching at its screen boundary. All
## displayed names/scores are synthetic and never reach production transport.
class SyntheticLeaderboard extends "res://scripts/ui/leaderboard_premium.gd":
	var fixture_data: Dictionary = {}
	var fixture_ok: bool = true
	func _fetch() -> void:
		if not fixture_data.is_empty():
			_receive(_serial, fixture_ok, fixture_data)


func _ready() -> void:
	var width := 1920
	var height := 1080
	var reduced := false
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.split("=", true, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"screen": _screen = parts[1]
			"item": _customize_item = parts[1]
			"out": _out = parts[1]
			"wait": _wait = float(parts[1])
			"w": width = int(parts[1])
			"h": height = int(parts[1])
			"reduced": reduced = parts[1] == "1"
	SettingsManager.set_setting("accessibility", "reduced_flashing", reduced)
	DisplayServer.window_set_size(Vector2i(width, height))
	DisplayServer.window_move_to_foreground()
	match _screen:
		"store_menu":
			# Phone-sized free native edition preview. Keep web account controls
			# hidden and avoid optional network requests during capture.
			GameConfig.force_touch = true
			GameConfig.force_native_offline_mvp = true
			LeaderboardClient.force_available = false
			LeaderboardClient.set_process(false)
			var menu: Control = (load("res://scenes/menus/main_menu.tscn") as PackedScene).instantiate()
			add_child(menu)
		"cloud_choice":
			# Offline account/save conflict fixture. Never contacts Clerk or Worker.
			GameConfig.force_touch = true
			LeaderboardClient.force_available = true
			LeaderboardClient.set_process(false)
			SaveManager.data = SaveManager.default_save()
			SaveManager.data["fish"] = 100
			LeaderboardClient.signed_in = true
			LeaderboardClient.display_name = "Fixture"
			LeaderboardClient._auth_owner_id = "synthetic-qa-owner"
			LeaderboardClient._auth_generation = 1
			LeaderboardClient._cloud_conflict_owner = "synthetic-qa-owner"
			LeaderboardClient._cloud_conflict_generation = 1
			LeaderboardClient._cloud_conflict_data = {"fish": 500}
			var menu: Control = (load("res://scenes/menus/main_menu.tscn") as PackedScene).instantiate()
			add_child(menu)
		"menu":
			# Reproduce phone composition, including widest web-only sign-in chip,
			# without touching a real account or the player's user:// directory.
			GameConfig.force_touch = true
			LeaderboardClient.force_available = true
			var menu: Control = (load("res://scenes/menus/main_menu.tscn") as PackedScene).instantiate()
			add_child(menu)
		"menu_desktop":
			LeaderboardClient.force_available = true
			var menu: Control = (load("res://scenes/menus/main_menu.tscn") as PackedScene).instantiate()
			add_child(menu)
		"base_camp", "base_camp_desktop":
			GameConfig.force_touch = _screen == "base_camp"
			LeaderboardClient.force_available = true
			var menu: Control = (load("res://scenes/menus/main_menu.tscn") as PackedScene).instantiate()
			add_child(menu)
			menu.call("_show_base_camp")
		"missions", "account":
			GameConfig.force_touch = true
			LeaderboardClient.force_available = true
			var menu: Control = (load("res://scenes/menus/main_menu.tscn") as PackedScene).instantiate()
			add_child(menu)
			menu.call("_show_%s" % _screen)
		"leaderboard_populated_desktop":
			GameConfig.force_touch = false
			LeaderboardClient.force_available = false
			LeaderboardClient.set_process(false)
			var board := SyntheticLeaderboard.new()
			board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var entries: Array[Dictionary] = []
			for index: int in 20:
				entries.append({"rank": index + 1,
					"name": "QA Explorer %02d" % (index + 1),
					"value": 95000 - index * 2731, "is_me": index == 3})
			entries[1]["name"] = "QA Explorer With An Intentionally Very Long Display Name"
			entries[3]["name"] = "You · QA Fixture"
			board.fixture_data = {"entries": entries, "me": {"rank": 4, "value": 86807}}
			add_child(board)
		"leaderboard", "leaderboard_desktop":
			GameConfig.force_touch = _screen != "leaderboard_desktop"
			LeaderboardClient.force_available = false
			LeaderboardClient.set_process(false)
			var board := SyntheticLeaderboard.new()
			board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			board.fixture_ok = false
			board.fixture_data = {"error": "synthetic_offline_fixture"}
			add_child(board)
		"achievements", "credits", "shop":
			GameConfig.force_touch = true
			LeaderboardClient.force_available = false
			var scene_path := "res://scenes/menus/%s.tscn" % (
				"cosmetic_shop" if _screen == "shop" else _screen.replace("_desktop", ""))
			var screen_node := (load(scene_path) as PackedScene).instantiate()
			add_child(screen_node)
		"settings":
			GameConfig.force_touch = true
			LeaderboardClient.force_available = true
			var settings: Control = (load("res://scenes/menus/settings.tscn") as PackedScene).instantiate()
			add_child(settings)
		"customize", "customize_desktop":
			GameConfig.force_touch = _screen == "customize"
			var locker: Control = (load("res://scenes/menus/customize.tscn") as PackedScene).instantiate()
			add_child(locker)
			if not _customize_item.is_empty():
				var item_info := CosmeticsDB.get_item(_customize_item)
				var category := String(item_info.get("category", ""))
				if category != "":
					locker.call("_select_category", category)
					locker.call("_select_item", _customize_item)
		"runner_results", "runner_results_desktop":
			GameConfig.force_touch = _screen == "runner_results"
			var hud := RunnerHUD.new()
			add_child(hud)
			hud.setup()
			hud.show_game_over({"distance":363.0, "fish":27, "score":1038,
				"best":6692, "missions":["Run 250 m at x2 or better", "Collect 60 fish"]})
		"loader":
			_build_loader()
		"router_loader":
			# SceneRouter replaces current scene before rich loading card finishes
			# fading in. Root-owned monitor survives that swap long enough to grab
			# actual cached mascot/backdrop composition.
			var monitor := PersistentCapture.new()
			monitor.out_path = _out
			monitor.wait_seconds = _wait
			get_tree().root.add_child.call_deferred(monitor)
			set_process(false)
			SceneRouter.go_to.call_deferred(Game.SCENE_TITLE)
		"boot":
			var boot: Node = (load("res://scenes/ui/main.tscn") as PackedScene).instantiate()
			add_child(boot)
		_:
			var title: Node = (load("res://scenes/ui/title.tscn") as PackedScene).instantiate()
			add_child(title)


func _build_loader() -> void:
	# Deliberate 65% style fixture. Real request-entry and handoff authority are
	# covered separately by scene_router_loader_capture; no download claim.
	SceneRouter._ensure_loading_presentation()
	SceneRouter.set_process(false)
	SceneRouter._fade_rect.visible = true
	SceneRouter._fade_rect.modulate.a = 1.0
	SceneRouter._loading_box.visible = true
	SceneRouter._loading_box.modulate.a = 1.0
	SceneRouter._loading_label.text = "Packing extra fish…"
	SceneRouter._loading_mascot.set_reduced_motion(true)
	SceneRouter._loading_mascot.set_progress(0.65)
	SceneRouter._layout_loading_card()
	print("[frontend-shot] synthetic loader progress=0.65; production UI, no loading-timing claim")


func _process(delta: float) -> void:
	_elapsed += delta
	if _captured or _elapsed < _wait:
		return
	_captured = true
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	var error := image.save_png(_out)
	print("[frontend-shot] %s %dx%d err=%d" % [
		_out, image.get_width(), image.get_height(), error])
	get_tree().quit(0 if error == OK else 1)


class PersistentCapture:
	extends Node

	var out_path: String = ""
	var wait_seconds: float = 0.55
	var elapsed: float = 0.0
	var captured: bool = false

	func _process(delta: float) -> void:
		elapsed += delta
		if captured or elapsed < wait_seconds:
			return
		captured = true
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var error := image.save_png(out_path)
		print("[frontend-shot] %s %dx%d err=%d" % [
			out_path, image.get_width(), image.get_height(), error])
		get_tree().quit(0 if error == OK else 1)
