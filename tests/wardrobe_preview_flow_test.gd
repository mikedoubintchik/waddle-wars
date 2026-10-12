extends "res://tests/mobile_ui_audit.gd"
## Real menu/save behavior; only network transport is replaced. Finished outfit
## coverage is a separate strict480 gate, never implied by these UI checks.
const LIBRARY = preload("res://scripts/ui/wardrobe_outfit_library.gd")
var _checks: Array[Dictionary] = []
var _menu: Control
var _output := ""
var _capture_count := 0
var _compact_capture := false

func _ready() -> void:
	if not String(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("waddle-wars-wardrobe-"):
		push_error("Wardrobe fixture requires isolated waddle-wars-wardrobe-* user data")
		get_tree().quit(2)
		return
	LeaderboardClient.set_script(OfflineLeaderboard)
	CommerceClient.set_script(OfflineCommerce)
	LeaderboardClient.set_process(false)
	CommerceClient.set_process(false)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="): _output = arg.trim_prefix("out=")
		if arg == "compact_capture=1": _compact_capture = true
	_run_wardrobe.call_deferred()

func _run_wardrobe() -> void:
	SaveManager.data = SaveManager.default_save()
	SaveManager.data["fish"] = 10000
	_menu = load("res://scenes/menus/customize.tscn").instantiate()
	get_tree().root.add_child(_menu)
	await _wait_preview()
	_assert(_menu.get("_penguin") == null and _menu.find_child("WardrobeWorld", true, false) == null, "no3D avatar or accessory geometry remains in menu preview")
	_assert(_menu.find_children("CompleteOutfitImage", "TextureRect", true, false).size() == 1, "one complete outfit image owns body and garments")
	_assert(_menu.get("_outfit_library").state == "ready", "real bare Emperor asset loads")
	var before := SaveManager.data.duplicate(true)
	for category: String in CosmeticsDB.CATEGORIES:
		_menu.call("_select_category", category)
		var grid := _menu.get("_item_grid") as GridContainer
		_assert(grid.get_child_count() == CosmeticsDB.items_in_category(category).size() + (0 if category == "body" else 1), "%s: full real catalog" % category)
		for tile: Button in grid.get_children():
			var id := String(tile.get_meta("cosmetic_id"))
			tile.pressed.emit()
			_assert((_menu.get("_try_on_loadout") as Dictionary)[category] == id, "%s: tile previews selected slot" % id)
			_assert(SaveManager.data == before and _menu.get("_buy_dialog") == null, "%s: browsing never buys or equips" % id)
		await _settle(1)
	_menu.call("_reset_try_on")
	await _wait_preview()
	_select("hat", "hat_beanie")
	_select("goggles", "goggles_ski")
	_select("scarf", "scarf_red")
	await _wait_preview()
	_assert(_menu.get("_previewed_equipped") == {"body":"body_classic","hat":"hat_beanie","goggles":"goggles_ski","scarf":"scarf_red","trail":""}, "three draft accessories persist across tabs")
	_assert(_menu.get("_outfit_stage").displayed_key == "body_classic__hat_beanie__goggles_ski__scarf_red", "complete image exactly matches temporary multi-slot outfit")
	_assert("TRY-ON · 3 ITEMS" == _menu.get("_try_on_note").text
		and "3 unequipped items" in _menu.get("_try_on_note").accessibility_name
		and SaveManager.data == before, "compact draft status explicitly distinguished from save")
	(_menu.get("_reset_try_on_button") as Button).pressed.emit()
	await _wait_preview()
	_assert(_menu.get("_try_on_loadout") == Progression.equipped() and SaveManager.data == before, "Reset restores equipped preview without writing save")
	_select("body", "body_adelie")
	await _wait_preview()
	(_menu.get("_detail_action") as Button).pressed.emit()
	_assert(Progression.get_equipped("body") == "body_adelie", "explicit Equip commits owned species")
	_select("body", "body_classic")
	await _wait_preview()
	(_menu.get("_detail_action") as Button).pressed.emit()
	_select("hat", "hat_beanie")
	await _wait_preview()
	(_menu.get("_detail_action") as Button).pressed.emit()
	_assert(_menu.get("_buy_dialog") != null and Progression.get_fish() == 10000, "Buy opens actual fish confirmation")
	_menu.call("_close_buy_dialog")
	_assert(not Progression.is_cosmetic_unlocked("hat_beanie"), "Cancel preserves ownership")
	(_menu.get("_detail_action") as Button).pressed.emit()
	var draft_before_failure: Dictionary = _menu.get("_try_on_loadout").duplicate(true)
	SaveManager.data["fish"] = 0
	_menu.call("_commit_buy", "hat_beanie", "hat")
	_assert(not Progression.is_cosmetic_unlocked("hat_beanie") and Progression.get_fish() == 0, "changed balance rejects confirmation without granting item")
	_assert(_menu.get("_try_on_note").is_visible_in_tree() and "Not enough fish" in _menu.get("_try_on_note").text, "failed purchase displayed in visible try-on status")
	_assert(_menu.get("_try_on_loadout") == draft_before_failure and Progression.get_equipped("hat") == "", "failed purchase preserves draft and saved equipment")
	await _settle(3)
	var insufficient_action := _menu.get("_detail_action") as Button
	var action_font := insufficient_action.get_theme_font("font")
	var action_font_size := insufficient_action.get_theme_font_size("font_size")
	_assert(insufficient_action.disabled and insufficient_action.text == "NEED 350 MORE FISH",
		"insufficient balance keeps complete truthful disabled action")
	_assert(action_font.get_string_size(insufficient_action.text, HORIZONTAL_ALIGNMENT_LEFT, -1, action_font_size).x
		<= insufficient_action.size.x * 0.84
		and action_font.get_height(action_font_size) <= insufficient_action.size.y * 0.70,
		"long fish requirement has visible breathing room inside coral action")
	SaveManager.data["fish"] = 10000
	_menu.call("_select_item", "hat_beanie")
	(_menu.get("_detail_action") as Button).pressed.emit()
	var dialog := _menu.get("_buy_dialog") as Control
	for button: Button in dialog.find_children("*", "Button", true, false):
		if button.text == "Buy":
			button.pressed.emit()
			break
	_assert(Progression.is_cosmetic_unlocked("hat_beanie") and Progression.get_fish() == 10000 - int(CosmeticsDB.get_item("hat_beanie")["cost"]), "confirmed Buy spends exact fish cost")
	_assert(Progression.get_equipped("hat") == "" and (_menu.get("_detail_action") as Button).text == "EQUIP", "Buy unlocks; separate Equip remains required")
	(_menu.get("_detail_action") as Button).pressed.emit()
	_assert(Progression.get_equipped("hat") == "hat_beanie", "explicit Equip applies purchased hat")
	_select("hat", "")
	await _wait_preview()
	_assert(Progression.get_equipped("hat") == "hat_beanie", "None only previews removal")
	(_menu.get("_detail_action") as Button).pressed.emit()
	_assert(Progression.get_equipped("hat") == "", "Remove explicitly clears hat")
	var key: String = _menu.get("_outfit_stage").displayed_key
	for id: String in CosmeticsDB.items_in_category("trail"):
		_select("trail", id)
		await _settle(2)
		_assert(_menu.get("_outfit_stage").displayed_key == key, "trail never changes outfit asset key: " + id)
		var trail := _menu.get("_outfit_stage").trail as CPUParticles2D
		_assert(trail != null and trail.get_meta("cosmetic_id") == id and trail.emitting, "separate real trail artwork animates: " + id)
		var card := _menu.call("_tile_for_id", id) as Button
		var portrait := card.find_child("ItemPortrait", true, false) as TextureRect
		_assert(portrait.texture == trail.texture and trail.texture == TrailEffect._particle_texture(id), "card, preview and gameplay share exact authored trail texture: " + id)
		_assert(portrait.modulate == Color.WHITE and trail.color == Color(1, 1, 1, 0.75) and trail.color_ramp == TrailEffect.fade_gradient(), "authored trail colors survive card and preview with shared alpha-only fade: " + id)
		_assert(trail.amount == 12 and is_equal_approx(trail.scale_amount_max * trail.texture.get_width(), _menu.get("_outfit_stage").size.y * 0.06), "illustrated trail modestly enlarged with bounded preview count: " + id)
	_select("trail", "")
	_assert(_menu.get("_outfit_stage").trail == null, "None removes separate trail")
	await _test_selection_paging()
	await _test_library()
	if not _output.is_empty() and not GameConfig.is_headless(): await _capture_catalog()
	var admitted := int(_menu.get("_outfit_library").entries.size())
	_menu.queue_free()
	await _settle(6)
	for player: AudioStreamPlayer in AudioManager._sfx_pool:
		player.stop()
		player.stream = null
	AudioManager.stop_music(0)
	await get_tree().create_timer(0.3).timeout
	var receipt := {"checks":_checks,"passed":_checks.filter(func(c: Dictionary) -> bool: return c.passed).size(),"total":_checks.size(),"captures":_capture_count,"catalog_admitted":admitted,"catalog_required":480,"limits":"Real isolated fish/save behavior; control signals model activation. Only named ready illustrations captured. Full480 coverage requires wardrobe_outfit_catalog_test; gameplay avatar unchanged."}
	if not _output.is_empty():
		DirAccess.make_dir_recursive_absolute(_output)
		var file := FileAccess.open(_output.path_join("wardrobe.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(receipt,"\t"))
	print("[wardrobe-preview] %d/%d passed; %d captures; catalog %d/480" % [receipt.passed,receipt.total,_capture_count,admitted])
	# Exit the entire tree with an undrained request; external stderr check
	# also rejects leaked resources or orphan cleanup nodes at shutdown.
	var exiting := LIBRARY.new()
	add_child(exiting)
	exiting.select_outfit({"body":"body_classic"})
	get_tree().quit(0 if receipt.passed == receipt.total else 1)

func _test_library() -> void:
	var library := LIBRARY.new()
	add_child(library)
	for body: String in CosmeticsDB.items_in_category("body"):
		library.select_outfit({"body":body})
		await _wait_library(library)
		_assert(library.state == "ready" and library.requested_key == body+"__none__none__none", "distinct bare species asset loads: "+body)
		_assert(library._cache.size() <= LIBRARY.CACHE_LIMIT, "full-image cache bounded while browsing")
	library.select_outfit({"body":"body_classic"})
	library.select_outfit({"body":"body_adelie"})
	library.select_outfit({"body":"body_gentoo"})
	await _wait_library(library)
	_assert(library.state == "ready" and library.requested_key == "body_gentoo__none__none__none", "rapid browsing resolves newest selection")
	library.select_outfit({"body":"missing_species"})
	_assert(library.state == "unavailable" and library.current_texture == null, "missing combination never falls back to mismatched bare outfit")
	library.queue_free()
	await _settle(3)
	var retiring := LIBRARY.new()
	add_child(retiring)
	retiring.select_outfit({"body":"body_classic"})
	_assert(not retiring._pending_path.is_empty(), "close test has an undrained texture request")
	retiring.free()
	var reopened := LIBRARY.new()
	add_child(reopened)
	reopened.select_outfit({"body":"body_classic"})
	await _wait_library(reopened)
	_assert(reopened.state == "ready" and reopened.current_texture != null, "immediate reopen loads same path after close drains pending request")
	reopened.free()

func _test_selection_paging() -> void:
	var before := SaveManager.data.duplicate(true)
	var original_size := get_tree().root.size
	for shape: Vector2i in [Vector2i(1672, 941), Vector2i(941, 1672)]:
		get_tree().root.size = shape
		await _settle(6)
		for target: Dictionary in [{"category":"hat", "id":"hat_crown"}, {"category":"body", "id":"body_macaroni"}]:
			_select(target.category, target.id)
			await _wait_preview()
			var scroll := _menu.get("_gallery_scroll") as ScrollContainer
			var tile := _menu.call("_tile_for_id", target.id) as Button
			_assert(scroll.scroll_horizontal > 0 and scroll.get_global_rect().grow(1).encloses(tile.get_global_rect()), "%s %s: programmatic selection reveals complete later-page card" % [shape, target.id])
			_menu.call("_page_gallery", -1)
			var manual_page := scroll.scroll_horizontal
			var library: Node = _menu.get("_outfit_library")
			_menu.call("_on_outfit_preview_changed", library.requested_key, library.current_texture, library.state)
			await _settle(4)
			_assert(_menu.get("_selected_id") == target.id and scroll.scroll_horizontal == manual_page, "%s %s: manual paging and delayed preview keep selection without snapping back" % [shape, target.id])
			_menu.call("_select_category", target.category)
			await _settle(5)
			scroll = _menu.get("_gallery_scroll")
			tile = _menu.call("_tile_for_id", target.id)
			_assert(scroll.get_global_rect().grow(1).encloses(tile.get_global_rect()), "%s %s: category restoration reveals saved draft selection" % [shape, target.id])
		_select("scarf", "scarf_rainbow")
		await _wait_preview()
		var dots := _menu.get("_gallery_dots") as HBoxContainer
		_assert(dots.get_child_count() == 2 and (dots.get_child(1) as Panel).get_theme_stylebox("panel").get("bg_color") == ExpeditionMenuStyle.CORAL, "%s: four-card short last page highlights final dot" % shape)
		_menu.call("_page_gallery", -1)
		await _settle(3)
		dots = _menu.get("_gallery_dots")
		_assert((dots.get_child(0) as Panel).get_theme_stylebox("panel").get("bg_color") == ExpeditionMenuStyle.CORAL and _menu.get("_selected_id") == "scarf_rainbow", "%s: paging back updates first dot without changing selection" % shape)
		_select("hat", "")
		await _settle(5)
		var scroll := _menu.get("_gallery_scroll") as ScrollContainer
		_assert(scroll.scroll_horizontal == 0 and scroll.get_global_rect().grow(1).encloses((_menu.call("_tile_for_id", "") as Control).get_global_rect()), "%s: None returns to first-page card" % shape)
		_select("body", "body_macaroni")
		_menu.call("_reset_try_on")
		await _wait_preview()
		scroll = _menu.get("_gallery_scroll")
		_assert(_menu.get("_selected_id") == Progression.get_equipped("body") and scroll.get_global_rect().grow(1).encloses((_menu.call("_tile_for_id", _menu.get("_selected_id")) as Control).get_global_rect()), "%s: Reset cancels stale later-page reveal and shows equipped card" % shape)
	_assert(SaveManager.data == before, "paging/restoring/None/Reset preserve real save and ownership")
	get_tree().root.size = original_size
	await _settle(6)

func _select(category: String, id: String) -> void:
	_menu.call("_select_category", category)
	(_menu.call("_tile_for_id", id) as Button).pressed.emit()

func _wait_preview() -> void:
	await _wait_library(_menu.get("_outfit_library"))
	await _settle(3)

func _wait_library(library: Node) -> void:
	var deadline := Time.get_ticks_msec()+5000
	while library.state == "loading" and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	_assert(library.state != "loading", "threaded preview resolves within bounded deadline")

func _capture_catalog() -> void:
	var looks: Array[Dictionary] = []
	for body: String in CosmeticsDB.items_in_category("body"):
		looks.append({"body":body,"hat":"","goggles":"","scarf":"","trail":""})
	looks.append({"body":"body_classic","hat":"hat_beanie","goggles":"goggles_ski","scarf":"scarf_red","trail":""})
	looks.append({"body":"body_snowy","hat":"hat_earwarmers","goggles":"goggles_aviator","scarf":"scarf_bowtie","trail":""})
	looks.append({"body":"body_rockhopper","hat":"hat_crown","goggles":"","scarf":"scarf_rainbow","trail":"trail_rainbow"})
	if _compact_capture:
		looks = [looks[8]]
	for shape: Vector2i in [Vector2i(960,540),Vector2i(540,960)]:
		GameConfig.force_touch = shape.y>shape.x
		SettingsManager.settings["display"]["window_mode"]="windowed"
		SettingsManager.settings["display"]["resolution"]="%dx%d" % [shape.x,shape.y]
		SettingsManager.apply_all()
		await _settle(6)
		for look: Dictionary in looks:
			for category: String in CosmeticsDB.CATEGORIES: _select(category,String(look[category]))
			_menu.call("_select_category", "hat" if _compact_capture else "body")
			await _wait_preview()
			_assert(_menu.get("_outfit_library").state=="ready", "capture requires exact completed outfit")
			if _menu.get("_outfit_library").state!="ready": continue
			await _capture(LIBRARY.outfit_key(look),shape)
		if _compact_capture: continue
		_menu.hide()
		var achievements := load("res://scenes/menus/achievements.tscn").instantiate() as Control
		get_tree().root.add_child(achievements)
		await _settle(6)
		await _capture("achievements",shape)
		achievements.queue_free()
		_menu.show()
		await _settle(3)

func _capture(label: String,shape: Vector2i) -> void:
	DisplayServer.window_move_to_foreground()
	await get_tree().create_timer(0.3).timeout
	DisplayServer.window_move_to_foreground()
	await RenderingServer.frame_post_draw
	_assert(get_window().has_focus(), "foreground renderer: "+label)
	if not get_window().has_focus(): return
	DirAccess.make_dir_recursive_absolute(_output)
	var pixels := get_viewport().get_texture().get_image()
	_assert(pixels.save_png(_output.path_join("%s_%dx%d.png" % [label,shape.x,shape.y]))==OK, "native capture saved: "+label)
	_capture_count+=1

func _settle(count: int) -> void:
	for index in count: await get_tree().process_frame

func _assert(ok: bool,message: String) -> void:
	_checks.append({"passed":ok,"description":message})
	if not ok: push_error("[wardrobe-preview] "+message)
