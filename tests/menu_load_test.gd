extends Node
## Headless menu smoke test. Launch with:
##   godot --headless res://tests/menu_load_test.tscn
## Instantiates every menu scene, verifies each builds a real UI tree, then
## drives SceneRouter to the main menu to prove headless navigation works.
## Prints "[menu] PASS/FAIL/SKIP <name>", exits 0 only when nothing failed.

const MENU_SCENES: PackedStringArray = [
	"res://scenes/ui/title.tscn",
	"res://scenes/menus/main_menu.tscn",
	"res://scenes/menus/mode_select.tscn",
	"res://scenes/menus/results.tscn",
	"res://scenes/menus/settings.tscn",
	"res://scenes/menus/controls.tscn",
	"res://scenes/menus/customize.tscn",
	"res://scenes/menus/cosmetic_shop.tscn",
	"res://scenes/menus/achievements.tscn",
	"res://scenes/menus/credits.tscn",
]

var _failures: int = 0
var _customize_checks: int = 0


func _ready() -> void:
	print("[menu] menu load test starting")
	await get_tree().process_frame
	_prefill_game_state()

	for path: String in MENU_SCENES:
		var short := path.get_file()
		if not ResourceLoader.exists(path):
			print("[menu] SKIP %s: scene not written yet (parallel stream)" % short)
			push_warning("menu load test skipped %s" % short)
			continue
		var packed: PackedScene = load(path)
		if packed == null:
			_fail(short, "load() returned null")
			continue
		var instance := packed.instantiate()
		add_child(instance)
		await get_tree().process_frame
		await get_tree().process_frame
		var node_count := _count_nodes(instance)
		if instance.get_script() == null:
			_fail(short, "root node has no script")
		elif node_count <= 3:
			_fail(short, "only %d nodes built" % node_count)
		else:
			print("[menu] PASS %s (%d nodes)" % [short, node_count])
		if path == "res://scenes/menus/customize.tscn":
			await _check_customize(instance)
		instance.queue_free()
		await get_tree().process_frame

	# Navigation check: SceneRouter must reach the main menu headlessly.
	# The monitor lives under the tree root so it survives the scene swap
	# (this scene is freed by change_scene_to_file).
	var monitor := NavMonitor.new()
	monitor.prior_failures = _failures
	get_tree().root.add_child(monitor)
	SceneRouter.go_to(Game.SCENE_MAIN_MENU)


func _prefill_game_state() -> void:
	Game.mode = Game.Mode.QUICK_RACE
	Game.course_id = "glacier"
	var rows: Array[Dictionary] = []
	for i: int in 8:
		rows.append({
			"key": "player" if i == 0 else "rival_%d" % i,
			"name": "You" if i == 0 else "Rival %d" % i,
			"is_player": i == 0,
			"position": i + 1,
			"time": 95.0 + float(i) * 3.5,
			"fish": 18 - i,
			"dnf": false,
		})
	Game.last_race_results = rows
	Game.last_rewards = {"fish": 63, "xp": 145, "unlocks": []}


func _fail(short: String, reason: String) -> void:
	_failures += 1
	print("[menu] FAIL %s: %s" % [short, reason])


func _count_nodes(node: Node) -> int:
	var count := 1
	for child: Node in node.get_children():
		count += _count_nodes(child)
	return count


func _check_customize(menu: Node) -> void:
	var saved_before := SaveManager.data.duplicate(true)
	var equipped_before := Progression.equipped()
	var failures_before := _failures
	var page := menu.find_child("ExpeditionContentScroll", true, false) as ScrollContainer
	var content := menu.find_child("ExpeditionContent", true, false) as VBoxContainer
	var gallery := menu.find_child("WardrobeGalleryScroll", true, false) as ScrollContainer
	var grid := menu.get("_item_grid") as GridContainer
	var detail := menu.get("_detail_action") as Button
	var stage := menu.get("_outfit_stage") as Control
	var library := menu.get("_outfit_library") as Node
	_customize_check(page != null and content != null and content.get_parent() == page,
		"main choices use the current submenu scroll")
	_customize_check(gallery != null and grid != null and gallery.is_ancestor_of(grid)
		and grid.get_parent() is MarginContainer
		and grid.get_parent().name == "WardrobeSelectionHaloSpace"
		and gallery.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
		"independent horizontal gallery owns selectable items inside dedicated selection-halo container")
	_customize_check(stage != null and page != null and not page.is_ancestor_of(stage),
		"finished outfit remains visible outside the choices scroll")
	_customize_check(detail != null and detail.is_visible_in_tree(),
		"separate purchase/equip action remains visible")
	_customize_check(menu.get("_penguin") == null and menu.find_child("WardrobeWorld", true, false) == null,
		"wardrobe has no obsolete3D rig or layered accessories")
	var images := menu.find_children("CompleteOutfitImage", "TextureRect", true, false)
	_customize_check(images.size() == 1 and library != null,
		"one complete image and one bounded library own outfit preview")
	if stage == null or library == null or images.size() != 1:
		return
	var image := images[0] as TextureRect
	_customize_check(image.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
		"complete character preserves original proportions")
	_customize_check(menu.find_child("PreviousPenguins", true, false) != null
		and menu.find_child("NextPenguins", true, false) != null,
		"both gallery paging controls exist")

	# All bare species are required even while the complete480 matrix grows.
	# Clear only the temporary accessory slots; never alter saved equipment.
	for category: String in ["hat", "goggles", "scarf", "trail"]:
		menu.call("_select_category", category)
		menu.call("_select_item", "")
	menu.call("_select_category", "body")
	var paths: Dictionary = {}
	for id: String in CosmeticsDB.items_in_category("body"):
		var tile := menu.call("_tile_for_id", id) as Button
		_customize_check(tile != null, "real species has selectable tile: " + id)
		if tile == null:
			continue
		tile.pressed.emit()
		await _wait_customize_preview(library)
		var try_on: Dictionary = menu.call("_preview_equipped")
		var key := id + "__none__none__none"
		_customize_check(String(try_on.get("body", "")) == id,
			"tile previews exact species: " + id)
		_customize_check(library.get("state") == "ready" and library.get("requested_key") == key
			and stage.get("displayed_key") == key and image.texture != null,
			"finished image matches selected bare species: " + id)
		_customize_check(image.visible and image.modulate == Color.WHITE,
			"preview stays readable for owned and locked species: " + id)
		var entries: Dictionary = library.get("entries")
		var path := String((entries.get(key, {}) as Dictionary).get("runtime", ""))
		_customize_check(not path.is_empty() and not paths.has(path),
			"species owns distinct complete illustration: " + id)
		paths[path] = true
		_customize_check((library.get("_cache") as Dictionary).size() <= 4,
			"browsing species respects four-texture cache")
		for category: String in ["hat", "goggles", "scarf", "trail"]:
			_customize_check(String(try_on.get(category, "missing")) == "",
				"species change preserves temporary empty slot: " + category)
		if not Progression.is_cosmetic_unlocked(id):
			var note := menu.get("_try_on_note") as Label
			_customize_check(note != null and "TRY-ON" in note.text
				and (detail.text.begins_with("BUY") or detail.text.begins_with("NEED")),
				"locked species separates visible try-on from purchase")
		_customize_check(menu.get("_buy_dialog") == null and SaveManager.data == saved_before,
			"species selection neither buys nor writes save")

	var draft_body := String((menu.call("_preview_equipped") as Dictionary)["body"])
	menu.call("_select_category", "hat")
	menu.call("_select_item", "hat_crown")
	await _wait_customize_preview(library)
	var accessory_preview: Dictionary = menu.call("_preview_equipped")
	_customize_check(String(accessory_preview.get("body", "")) == draft_body
		and String(accessory_preview.get("hat", "")) == "hat_crown",
		"accessory selection preserves temporary species and adds selected garment")
	if library.get("state") == "unavailable":
		_customize_check(image.texture == null and not image.visible and detail.disabled,
			"unadmitted combination hides stale artwork and blocks action")
		_customize_check((stage.get("message") as Label).visible
			and "unavailable" in (stage.get("message") as Label).text,
			"missing complete outfit has an honest visible status")
	else:
		_customize_check(stage.get("displayed_key") == draft_body + "__hat_crown__none__none",
			"available accessory combination resolves exact complete illustration")
	var texture_before := image.texture
	menu.call("_select_item", "hat_crown")
	_customize_check(menu.get("_outfit_stage") == stage and menu.get("_outfit_library") == library
		and image.texture == texture_before,
		"repeated selection reuses preview and loaded texture")
	menu.call("_select_item", "")
	await _wait_customize_preview(library)
	_customize_check(String((menu.call("_preview_equipped") as Dictionary).get("hat", "missing")) == "",
		"None only previews empty accessory")
	var outfit_key := String(stage.get("displayed_key"))
	menu.call("_select_category", "trail")
	menu.call("_select_item", CosmeticsDB.items_in_category("trail")[0])
	_customize_check(stage.get("displayed_key") == outfit_key and stage.get("trail") != null,
		"trail preview remains independent of complete outfit image")
	(menu.get("_reset_try_on_button") as Button).pressed.emit()
	await _wait_customize_preview(library)
	_customize_check(menu.call("_preview_equipped") == equipped_before,
		"Reset restores equipped preview")
	_customize_check(SaveManager.data == saved_before and Progression.equipped() == equipped_before,
		"all browsing preserves save, fish, unlocks and equipped loadout")
	print("[menu] wardrobe checks: %d/%d passed" % [_customize_checks - (_failures - failures_before), _customize_checks])


func _wait_customize_preview(library: Node) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while library.get("state") == "loading" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_customize_check(library.get("state") != "loading", "threaded image resolves within five seconds")


func _customize_check(condition: bool, reason: String) -> void:
	_customize_checks += 1
	if condition:
		return
	_fail("customize.tscn", reason)


class NavMonitor:
	extends Node
	## Waits for SceneRouter to land on the main menu, then reports and quits.

	var prior_failures: int = 0
	var _frames: int = 0

	func _process(_delta: float) -> void:
		_frames += 1
		var scene := get_tree().current_scene
		if scene != null and scene.name == "MainMenu":
			print("[menu] PASS scene_router_navigation")
			print("[menu] DONE: %d failures" % prior_failures)
			await _finish(1 if prior_failures > 0 else 0)
			return
		if _frames > 300:
			var current := scene.name if scene != null else &"null"
			print("[menu] FAIL scene_router_navigation: current_scene=%s" % current)
			print("[menu] DONE: %d failures" % (prior_failures + 1))
			await _finish(1)

	func _finish(exit_code: int) -> void:
		set_process(false)
		# The real navigation starts title music and focus sounds. Let Dummy
		# release their playback before shutdown; no production audio bypass.
		AudioManager.stop_music(0)
		for player: AudioStreamPlayer in AudioManager._sfx_pool:
			player.stop()
			player.stream = null
		await get_tree().create_timer(0.3).timeout
		get_tree().quit(exit_code)
