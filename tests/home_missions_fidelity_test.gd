extends "res://tests/mobile_ui_audit.gd"
## Isolated real saved-state/layout checks. Native runs additionally preserve
## reference-review stills; geometry checks alone do not establish fidelity.

var _checks := 0
var _frames: Array[Dictionary] = []
var _out := ""

func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		push_error("Requires isolated user directory")
		get_tree().quit(2)
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="): _out = arg.trim_prefix("out=")
	LeaderboardClient.set_script(OfflineLeaderboard)
	CommerceClient.set_script(OfflineCommerce)
	LeaderboardClient.set_process(false)
	CommerceClient.set_process(false)
	LeaderboardClient.force_available = false
	LayoutProfile.forced_insets = Vector4.ZERO
	_check_destination_atlas()
	for shape: Vector2i in [Vector2i(540, 960), Vector2i(1280, 720)]:
		GameConfig.force_touch = shape.y > shape.x
		SettingsManager.settings["display"]["window_mode"] = "windowed"
		SettingsManager.settings["display"]["resolution"] = "%dx%d" % [shape.x, shape.y]
		SettingsManager.settings["accessibility"]["reduced_flashing"] = true
		SettingsManager.apply_all()
		if GameConfig.is_headless():
			get_window().size = shape
			get_window().content_scale_size = Vector2i(800,1422) if shape.y > shape.x else Vector2i(1920,1080)
		if not GameConfig.is_headless(): DisplayServer.window_move_to_foreground()
		await get_tree().process_frame
		_check(LayoutProfile.for_viewport(get_viewport()).is_portrait() == (shape.y > shape.x), "fixture uses requested actual orientation")
		for late: bool in [false, true]:
			SaveManager.set_value("fish", 9999999 if late else 38290)
			SaveManager.set_value("runner_biome_milestone", 3 if late else 0)
			SaveManager.set_value(RunnerMissions.SAVE_KEY_STARS, 320 if late else 0)
			var rows := [
				{"id":"multi_run","target":900.0,"progress":457.5,"mult":4,"done":false},
				{"id":"fish_total","target":600.0,"progress":600.0,"done":true},
				{"id":"power_specific","target":9.0,"progress":4.0,"param":"double","done":false},
			] if late else [
				{"id":"dist_run","target":700.0,"progress":0.0,"done":false},
				{"id":"fish_run","target":12.0,"progress":0.0,"done":false},
				{"id":"clean_run","target":400.0,"progress":0.0,"done":false},
			]
			SaveManager.set_value(RunnerMissions.SAVE_KEY_SET, rows)
			var menu := load("res://scenes/menus/main_menu.tscn").instantiate() as Control
			add_child(menu)
			await _settle()
			var tag := "late" if late else "fresh"
			_check_home(menu)
			await _save_frame("home-" + tag, shape)
			if GameConfig.is_headless() and shape.y > shape.x and not late:
				LayoutProfile.forced_insets = Vector4(0, 44, 0, 34)
				menu.call("_apply_safe_area")
				await _settle()
				_check_home(menu)
				var safe := LayoutProfile.for_viewport(get_viewport()).safe_rect
				for destination: Button in menu.get("_buttons").slice(1,4):
					_check(destination.get_global_rect().end.y <= safe.end.y + 1.0,
						"home-indicator safe inset protects destination touch targets")
				LayoutProfile.forced_insets = Vector4.ZERO
				menu.call("_apply_safe_area")
				await _settle()
			menu.call("_show_missions")
			await _settle()
			_check_missions(menu, late)
			await _save_frame("missions-" + tag, shape)
			menu.call("_show_base_camp")
			await _settle()
			var feedback := menu.find_child("BaseCampFeedback", true, false) as Button
			_check(feedback != null and feedback.pressed.get_connections().size() > 0,
				"More exposes connected Feedback action")
			_check_base_camp(menu)
			menu.queue_free()
			await get_tree().process_frame
	for player: AudioStreamPlayer in [AudioManager._music_a, AudioManager._music_b]:
		player.stop()
		player.stream = null
	for player: AudioStreamPlayer in AudioManager._sfx_pool:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.25).timeout
	var report := {"checks":_checks,"failures":_failures,"frames":_frames,
		"limits":"Synthetic isolated saved state, shipped UI. Geometry/live-state checks only until actual PNG reference comparison. No account, network, purchase or feedback submission."}
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
		var file := FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"\t"))
	print("[home-missions] %d/%d checks passed; %d captures" % [_checks-_failures.size(),_checks,_frames.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)

func _settle() -> void:
	for i in 4: await get_tree().process_frame

func _check_home(menu: Control) -> void:
	var safe := LayoutProfile.for_viewport(get_viewport()).safe_rect
	var portrait := safe.size.y > safe.size.x
	var run := menu.find_child("RunDeparture", true, false) as Button
	var width_fraction := run.size.x / safe.size.x
	print("[home-missions] Run geometry: safe=%s action=%s ratio=%.3f portrait=%s" % [safe,run.get_global_rect(),width_fraction,portrait])
	_check(safe.grow(1.0).encloses(run.get_global_rect()), "complete Run action stays inside first view")
	_check(width_fraction >= (0.83 if portrait else 0.38) and width_fraction <= (0.92 if portrait else 0.45),
		"Run action matches reference width range without stretching across shelf")
	var balance := menu.find_child("HomeFishBalance", true, false) as Control
	var symbol := balance.find_child("FishSymbol", true, false) as Control
	var number := balance.find_child("FishAmount", true, false) as Label
	_check(number.text == ExpeditionMenuStyle.grouped_amount(Progression.get_fish()), "home shows full actual currency")
	_check(absf(symbol.get_global_rect().get_center().y - number.get_global_rect().get_center().y) < 2.0,
		"currency symbol and amount vertically centered together")
	var shelf := menu.find_child("IvoryDestinationShelf", true, false) as Control
	if portrait:
		_check(absf(shelf.get_global_rect().end.y - get_viewport().get_visible_rect().size.y) < 2.0,
			"portrait cream shelf reaches physical bottom")
	_check(shelf.size.y >= safe.size.y * (0.145 if portrait else 0.175),
		"destination shelf has reference breathing room")
	for button: Button in menu.get("_buttons").slice(1,4):
		_check(button.get_theme_stylebox("hover") is StyleBoxEmpty,
			"destination hover preserves illustrated shelf without flat tile")
		var visual := button.get_child(0) as Control
		for child: Control in visual.get_children():
			_check(button.get_global_rect().grow(1.0).encloses(child.get_global_rect()),
				"destination art/caption stays inside its native button")
			_check(shelf.get_global_rect().grow(-1.0).encloses(child.get_global_rect()),
				"destination roundel and caption remain below cream shelf top")

func _check_destination_atlas() -> void:
	# These original Home roundels match the approved symbols and have complete
	# silhouettes. Base Camp keeps the newer atlas whose old crops were clipped.
	for key: String in ["penguins", "missions", "more"]:
		var texture: Texture2D = load("res://assets/art/ui/menu/home_%s_icon_exact_v1.webp" % key)
		var image := texture.get_image()
		var edge_alpha := 0.0
		for x in image.get_width():
			edge_alpha = maxf(edge_alpha, maxf(image.get_pixel(x,0).a,image.get_pixel(x,image.get_height()-1).a))
		for y in image.get_height():
			edge_alpha = maxf(edge_alpha, maxf(image.get_pixel(0,y).a,image.get_pixel(image.get_width()-1,y).a))
		_check(edge_alpha < 0.125, "exact Home roundel retains a complete silhouette: " + key)
	var art := preload("res://scripts/ui/menu_destination_art.gd")
	var shared: Texture2D = null
	var pixels: Image = null
	for key: String in art.REGIONS:
		var icon := art.icon(key)
		if shared == null:
			shared = icon.atlas
			pixels = shared.get_image()
		_check(icon.atlas == shared and icon.filter_clip,
			"destination regions reuse one filtered atlas: " + key)
		var r := Rect2i(icon.region)
		_check(Rect2i(Vector2i.ZERO, pixels.get_size()).encloses(r), "icon crop within source: " + key)
		var edge_alpha := 0.0
		for x in range(r.position.x, r.end.x):
			edge_alpha = maxf(edge_alpha, maxf(pixels.get_pixel(x,r.position.y).a, pixels.get_pixel(x,r.end.y-1).a))
		for y in range(r.position.y, r.end.y):
			edge_alpha = maxf(edge_alpha, maxf(pixels.get_pixel(r.position.x,y).a, pixels.get_pixel(r.end.x-1,y).a))
		_check(edge_alpha < 0.125, "complete icon silhouette clears crop edge: " + key)

func _check_base_camp(menu: Control) -> void:
	var column := menu.find_child("BaseCampDestinations", true, false) as Control
	for row: Node in column.get_children():
		if not row is Button: continue
		var button := row as Button
		var icon := button.get_node("BaseCampDestinationIcon") as TextureRect
		_check(button.get_global_rect().encloses(icon.get_global_rect()), "Base Camp icon remains inside row: " + button.name)
		_check(icon.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
			"Base Camp icon keeps authored proportions: " + button.name)
		var normal := button.get_theme_stylebox("normal")
		_check(icon.position.x + icon.size.x < normal.content_margin_left,
			"Base Camp icon clears destination caption: " + button.name)
		for state: String in ["hover", "pressed", "hover_pressed"]:
			var skin := button.get_theme_stylebox(state)
			_check(skin.texture == normal.texture and skin.region == normal.region
				and skin.content_margin_left == normal.content_margin_left,
				"Base Camp interaction preserves card silhouette and text position: " + button.name + "/" + state)

func _check_missions(menu: Control, late: bool) -> void:
	var overlay := menu.get("_premium_overlay") as Control
	var map := overlay.find_child("MissionRouteMap", true, false) as Control
	var status := overlay.find_child("MilestonePlaque", true, false) as Control
	var scroll := overlay.find_child("MissionCardsScroll", true, false) as Control
	for i in 4:
		var label := overlay.find_child("RouteName%d" % i, true, false) as Control
		_check(map.get_global_rect().grow(1.0).encloses(label.get_global_rect()), "route landmark remains inside complete map")
		_check(not label.get_global_rect().intersects(status.get_global_rect()), "route landmark does not overlap milestone")
		_check(not label.get_global_rect().intersects(scroll.get_global_rect()), "route landmark does not overlap mission cards")
	var model := RunnerMissions.new()
	model.load_state(false)
	for i in 3:
		var card := overlay.find_child("MissionStrip%d" % i, true, false) as Control
		var description := card.find_child("MissionDescription", true, false) as Label
		var progress := card.find_child("MissionProgress", true, false) as ProgressBar
		_check(description.text == String(model.rows()[i]["text"]).to_upper(), "full mission semantics preserved")
		_check(is_equal_approx(progress.value,float(model.rows()[i]["progress"])), "fractional progress matches saved authority")
		var fill := progress.get_theme_stylebox("fill") as StyleBoxFlat
		_check(fill != null and fill.bg_color.is_equal_approx(ExpeditionMenuStyle.GOLD if model.rows()[i]["done"] else Color("3d94dd")), "mission page uses smooth blue partial fill and gold completion")
		_check(description.get_visible_line_count() == description.get_line_count(), "mission wraps without hidden lines")
	var next_label := overlay.find_child("MilestoneText", true, false) as Label
	_check(next_label.text == ("ALL REGIONS\nDISCOVERED" if late else "NEXT: TWILIGHT\n1,800 M · ONE RUN"), "milestone reflects actual discovery state")
	var run := overlay.find_child("MissionRunNow", true, false) as Button
	_check(scroll.get_global_rect().grow(1.0).encloses(run.get_global_rect()), "run action fits first mission view")

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error("[home-missions] " + message)

func _save_frame(page: String, shape: Vector2i) -> void:
	if GameConfig.is_headless() or _out.is_empty(): return
	DisplayServer.window_move_to_foreground()
	await get_tree().create_timer(0.5).timeout
	for attempt in 3:
		DisplayServer.window_move_to_foreground()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if get_window().has_focus(): break
	var pixels := get_viewport().get_texture().get_image()
	var path := _out.path_join("%s-%dx%d.png" % [page,shape.x,shape.y])
	DirAccess.make_dir_recursive_absolute(_out)
	_check(get_window().has_focus() and pixels != null and pixels.get_size() == shape,
		"%s %s native frame uses requested foreground window" % [page, shape])
	if pixels != null and get_window().has_focus() and pixels.get_size() == shape:
		var code := pixels.save_png(path)
		_check(code == OK,"native PNG saved")
		_frames.append({"path":path,"width":shape.x,"height":shape.y,"page":page,
			"focused":get_window().has_focus(),"visible":get_window().visible})
