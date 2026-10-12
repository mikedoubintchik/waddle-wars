extends "res://tests/mobile_ui_audit.gd"
## Deterministic iPhone 15 Pro Max safe-area geometry, with offline transports.
## This tests shipped Control trees; visual captures remain end-of-turn only.

var _checks := 0

func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		get_tree().quit(2)
		return
	LeaderboardClient.set_script(OfflineLeaderboard)
	CommerceClient.set_script(OfflineCommerce)
	LeaderboardClient.set_process(false)
	CommerceClient.set_process(false)
	LeaderboardClient.force_available = false
	_check_physical_conversion()
	for fixture: Array in [
		[Vector2i(800,1734), Vector4(0,59,0,34) * (800.0 / 430.0)],
		[Vector2i(1734,800), Vector4(59,0,59,21) * (800.0 / 430.0)],
		[Vector2i(800,1422), Vector4.ZERO],
		[Vector2i(1280,720), Vector4.ZERO]]:
		await _check_pages(fixture[0], fixture[1])
	LayoutProfile.forced_insets = Vector4(-1,-1,-1,-1)
	for player: AudioStreamPlayer in AudioManager._sfx_pool + [AudioManager._music_a, AudioManager._music_b]:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.25).timeout
	print("[phone-safe-header] %d/%d passed" % [_checks - _failures.size(), _checks])
	get_tree().quit(0 if _failures.is_empty() else 1)

func _check_physical_conversion() -> void:
	var native := LayoutProfile.scale_safe_insets(Vector4(0,177,0,102),
		Vector2(1290,2796), Vector2(800,1734))
	var browser := LayoutProfile.scale_safe_insets(Vector4(0,59,0,34),
		Vector2(430,932), Vector2(800,1734))
	_check(native.is_equal_approx(browser), "native Retina and browser CSS insets resolve to identical canvas geometry")
	_check(absf(native.y - 109.77) < 0.1 and absf(native.w - 63.26) < 0.1,
		"15 Pro Max island and home-indicator are converted once")
	var landscape := LayoutProfile.scale_safe_insets(Vector4(177,0,177,63),
		Vector2(2796,1290), Vector2(1734,800))
	_check(landscape.x > 109 and landscape.z > 109 and landscape.w > 39,
		"landscape left/right island and bottom indicator remain safe")

func _check_pages(shape: Vector2i, insets: Vector4) -> void:
	GameConfig.force_touch = insets != Vector4.ZERO or shape.y > shape.x
	LayoutProfile.forced_insets = insets
	var viewport := SubViewport.new()
	viewport.size = shape
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var menu := load("res://scenes/menus/main_menu.tscn").instantiate() as Control
	viewport.add_child(menu)
	await _settle()
	var safe := LayoutProfile.for_viewport(viewport).safe_rect
	var fish := menu.find_child("HomeFishBalance",true,false) as Control
	var account := menu.find_child("HomeAccountButton",true,false) as Control
	_check(absf(fish.get_global_rect().get_center().y-account.get_global_rect().get_center().y) < 1.0,
		"Home fish/avatar share center line " + str(shape))
	_check(safe.grow(1).encloses(fish.get_global_rect()) and safe.grow(1).encloses(account.get_global_rect()),
		"Home status stays below island and inside safe edges " + str(shape))
	if shape.y > shape.x:
		var shelf := menu.find_child("IvoryDestinationShelf",true,false) as Control
		var destinations: Array = menu.get("_buttons").slice(1,4)
		for button: Control in destinations:
			_check(safe.grow(1).encloses(button.get_global_rect()), "Home destination clears indicator " + button.name)
			var center := button.get_global_rect().get_center().x
			var slot := destinations.find(button)
			_check(absf(center - (safe.position.x + safe.size.x * (float(slot)+0.5)/3.0)) < safe.size.x * 0.02,
				"Home destination centered in its third of shelf " + button.name)
		_check(absf(shelf.get_global_rect().end.y - float(shape.y)) < 1.0, "Home cream backing reaches bottom edge")
	for overlay: String in ["missions","account","base_camp"]:
		menu.call("_show_" + overlay)
		await _settle()
		var title_name := "AccountTitleArtwork" if overlay == "account" else "ApprovedOverlayTitle"
		_check_header(menu, viewport, title_name, "OverlayBack", overlay)
		if overlay == "missions":
			var text := menu.find_child("MilestoneText",true,false) as Label
			var plaque := menu.find_child("MilestonePlaque",true,false) as Control
			var expected := atan2(-123.0 * plaque.size.y/750.0,1530.0*plaque.size.x/1830.0)
			_check(absf(text.rotation - expected) < 0.001 and text.rotation < -0.02,
				"Milestone text follows slanted painted sign in both orientations")
	menu.free()
	for entry: Array in [["settings","SettingsTitleArtwork","Back"],
		["controls","ControlsTitleArt","Back"], ["achievements","ApprovedTitleArtwork","Back"],
		["leaderboard","ApprovedTitleArtwork","Back"], ["cosmetic_shop","ApprovedTitleArtwork","Back"]]:
		var page := load("res://scenes/menus/%s.tscn" % entry[0]).instantiate() as Control
		viewport.add_child(page)
		await _settle()
		_check_header(page,viewport,entry[1],entry[2],entry[0])
		if entry[0] == "achievements" and (shape.y > shape.x or insets != Vector4.ZERO):
			var title := page.find_child("ApprovedTitleArtwork",true,false) as Control
			var counter := page.find_child("CollectionProgress",true,false) as Control
			_check(safe.grow(1).encloses(counter.get_global_rect()), "Achievements counter clears camera and edges " + str(shape))
			_check(absf(counter.get_global_rect().get_center().y-title.get_global_rect().get_center().y)<1.0,
				"Achievements count shares title/back center line " + str(shape))
			_check(not counter.get_global_rect().intersects(title.get_global_rect()),
				"Achievements count and title have separate columns " + str(shape))
		page.free()
	await _check_wardrobe_names(viewport, shape)
	var form := preload("res://scripts/ui/feedback_form.gd").new()
	form.open(viewport)
	await _settle()
	if shape.y > shape.x or insets != Vector4.ZERO:
		_check(safe.grow(1).encloses(form._wordmark.get_global_rect()), "Feedback title clears island")
		_check(absf(form._wordmark.get_global_rect().get_center().y-form._back.get_global_rect().get_center().y)<1,
			"Feedback back/title share center line")
	viewport.queue_free()
	await get_tree().process_frame

func _check_wardrobe_names(viewport: Viewport, shape: Vector2i) -> void:
	var wardrobe := load("res://scenes/menus/customize.tscn").instantiate() as Control
	viewport.add_child(wardrobe)
	await _settle()
	for category: String in CosmeticsDB.CATEGORIES:
		wardrobe.call("_select_category", category)
		var choices := CosmeticsDB.items_in_category(category).duplicate()
		if category != "body": choices.append("")
		for id: String in choices:
			wardrobe.call("_select_item", id)
			await _settle()
			var name_label := wardrobe.get("_detail_name") as Label
			var plate := wardrobe.find_child("OutfitNamePlate",true,false) as Control
			var font := name_label.get_theme_font("font")
			var font_size := name_label.get_theme_font_size("font_size")
			if id in ["body_classic", "hat_headset", "hat_crown", "trail_snowflake"]:
				print("[phone-safe-header] name %s %s font=%d label=%s plate=%s" % [shape, id, font_size, name_label.size, plate.size])
			var slot := "" if id.is_empty() else String(CosmeticsDB.get_item(id).get("name",id))
			_check(not name_label.text.is_empty() and (id.is_empty() or name_label.text == slot.to_upper()),
				"Complete wardrobe name preserved " + str(shape) + " " + id)
			_check(font_size >= 16 and font.get_string_size(name_label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x <= name_label.size.x - 8.0,
				"All wardrobe names readable with horizontal breathing room " + str(shape) + " " + name_label.text)
			_check(font.get_height(font_size) <= name_label.size.y and plate.get_global_rect().grow(1).encloses(name_label.get_global_rect()),
				"Wardrobe name stays inside plaque vertically " + str(shape) + " " + name_label.text)
	wardrobe.free()
	await get_tree().process_frame

func _check_header(page: Control, viewport: Viewport, title_name: String, back_name: String, key: String) -> void:
	var title := page.find_child(title_name,true,false) as Control
	var back := page.find_child(back_name,true,false) as Control
	_check(title != null and back != null, key + " uses live shared header controls")
	if title == null or back == null: return
	var profile := LayoutProfile.for_viewport(viewport)
	if not profile.is_portrait() and profile.safe_insets == Vector4.ZERO: return
	print("[phone-safe-header] %s %s title=%s back=%s" % [key,profile.viewport_size,title.get_global_rect(),back.get_global_rect()])
	_check(profile.safe_rect.grow(1).encloses(title.get_global_rect()), key + " title clears camera/screen edges")
	_check(profile.safe_rect.grow(1).encloses(back.get_global_rect()), key + " back clears camera/screen edges")
	_check(absf(title.get_global_rect().get_center().y-back.get_global_rect().get_center().y)<1.0,
		key + " back/title share center line")
	_check(not title.get_global_rect().intersects(back.get_global_rect()), key + " title and Back occupy separate columns")

func _settle() -> void:
	for frame: int in 6: await get_tree().process_frame

func _check(ok: bool, description: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(description)
		push_error("[phone-safe-header] " + description)
