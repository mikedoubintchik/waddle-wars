extends "res://tests/home_missions_fidelity_test.gd"
## Save-backed discovery, route placement and actual mission-page actions.
var _pages_checked := 0

func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir",false):
		get_tree().quit(2)
		return
	LeaderboardClient.set_script(OfflineLeaderboard)
	CommerceClient.set_script(OfflineCommerce)
	LeaderboardClient.set_process(false)
	CommerceClient.set_process(false)
	LeaderboardClient.force_available = false
	AudioManager._library = {}
	AudioManager._one_shot_cache = {}
	_test_boundaries()
	_test_reward_once()
	await _test_mission_pages()
	_check(_pages_checked == 15,"all fifteen actual UI states completed without aborted coroutine")
	for player: AudioStreamPlayer in [AudioManager._music_a,AudioManager._music_b]: player.stop()
	for player: AudioStreamPlayer in AudioManager._sfx_pool:
		player.stop()
		player.stream = null
	await get_tree().process_frame
	print("[mission-map] %d/%d passed" % [_checks-_failures.size(),_checks])
	get_tree().quit(0 if _failures.is_empty() else 1)

func _reset_map() -> void:
	SaveManager.data = SaveManager.default_save()
	SaveManager._dirty = false
	SaveManager.set_value(RunnerMissions.SAVE_KEY_PACING,RunnerMissions.PACING_VERSION)

func _test_boundaries() -> void:
	for metres: float in [0.0,600.0,1799.99,1800.0,3599.99,3600.0,5399.99,5400.0,7200.0]:
		_reset_map()
		if metres > 0.0: Progression.record_runner_activity(0.1,metres,metres,metres)
		var expected := clampi(floori(metres/1800.0),0,3)
		var state := RunnerMissions.map_progress()
		_check(state["current_region"] == expected,"exact %.2fm current destination" % metres)
		for index: int in 4:
			_check(state["regions"][index]["unlocked"] == (index <= expected),"%.2fm region%d unlock only at real threshold" % [metres,index])
		_check(is_equal_approx(state["route_position"],clampf(metres/1800.0,0.0,3.0)),"marker records partial real distance")
		SaveManager.save_now()
		SaveManager.data = SaveManager.default_save()
		SaveManager.load_save()
		_check(RunnerMissions.map_progress() == state,"%.2fm discovery and marker survive disk reload" % metres)
		Progression.record_runner_activity(0.1,1.0,1.0,1.0)
		_check(RunnerMissions.map_progress() == state if metres >= 1.0 else RunnerMissions.map_progress()["current_region"] == 0,"short retry never regresses discovered route")
	_reset_map()
	SaveManager.set_value("runner_biome_milestone",2)
	_check(RunnerMissions.map_progress()["current_region"] == 2,"legacy earned milestones survive absent best-distance metric")
	_reset_map()
	SaveManager.set_value("stats",{"runner_distance_total":250000.0})
	SaveManager.set_value(RunnerMissions.SAVE_KEY_STARS,999)
	_check(RunnerMissions.map_progress()["current_region"] == 0,"currency and cumulative distance cannot unlock run regions")

func _test_reward_once() -> void:
	_reset_map()
	SaveManager.set_value(RunnerMissions.SAVE_KEY_SET,[
		{"id":"dist_run","target":1.0,"progress":0.0,"done":false},
		{"id":"dist_total","target":1.0,"progress":0.0,"done":false},
		{"id":"clean_run","target":1.0,"progress":0.0,"done":false}])
	var model := RunnerMissions.new()
	model.load_state()
	model.begin_run()
	model.note_distance(1.0)
	_check(model.stars()==1 and Progression.get_fish()==25,"three goals auto-award exact set reward once")
	var xp := Progression.get_xp()
	SaveManager.load_save()
	var copy := RunnerMissions.new()
	copy.load_state()
	copy.begin_run()
	copy.note_distance(0.0)
	_check(copy.stars()==1 and Progression.get_fish()==25 and Progression.get_xp()==xp,"reload and retry cannot claim reward again")

func _test_mission_pages() -> void:
	for fixture: Dictionary in [{"shape":Vector2i(540,960),"inset":0.0},
		{"shape":Vector2i(540,960),"inset":24.0},
		{"shape":Vector2i(1280,720),"inset":0.0},
		{"shape":Vector2i(1280,720),"inset":24.0},
		{"shape":Vector2i(1468,947),"inset":0.0}]:
		var shape: Vector2i = fixture["shape"]
		LayoutProfile.forced_insets = Vector4.ONE * float(fixture["inset"])
		GameConfig.force_touch = shape.y > shape.x
		SettingsManager.settings["display"]["window_mode"] = "windowed"
		SettingsManager.settings["display"]["resolution"] = "%dx%d" % [shape.x,shape.y]
		SettingsManager.apply_all()
		get_window().size = shape
		get_window().content_scale_size = Vector2i(800,1422) if shape.y > shape.x else Vector2i(1920,1080)
		await get_tree().process_frame
		for metres: float in [0.0,2700.0,5400.0]:
			_reset_map()
			if metres > 0: Progression.record_runner_activity(0.1,metres,metres,metres)
			var menu := load("res://scenes/menus/main_menu.tscn").instantiate() as Control
			add_child(menu)
			await _settle()
			menu.call("_show_missions")
			await _settle()
			var overlay := menu.get("_premium_overlay") as Control
			var map := overlay.find_child("MissionRouteMap",true,false) as Control
			var hero := map.find_child("MissionMapPenguin",true,false) as TextureRect
			var twilight := map.find_child("TwilightLandmark",true,false) as TextureRect
			_check(twilight != null and twilight.texture != null and map.get_global_rect().encloses(twilight.get_global_rect()), "Twilight has an explicit complete landmark")
			var header_back := overlay.find_child("OverlayBack",true,false) as Button
			_check(header_back.icon == ExpeditionMenuStyle.wardrobe_sprite("back") and is_equal_approx(header_back.size.x,header_back.size.y), "Missions uses unwarped shared back artwork")
			_check(is_equal_approx(hero.get_meta("route_position"),metres/1800.0),"live character binds real save progression")
			_check(hero.texture != null and map.get_global_rect().encloses(hero.get_global_rect()),"complete character artwork remains inside map")
			var milestone_copy := overlay.find_child("MilestoneText", true, false) as Label
			_check(milestone_copy.text.contains("ONE RUN") if metres < 5400 else milestone_copy.text.contains("ALL REGIONS"), "plaque distinguishes single-run discovery from mission progression")
			for line: String in milestone_copy.text.split("\n"):
				_check(milestone_copy.get_theme_font("font").get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, milestone_copy.get_theme_font_size("font_size")).x <= milestone_copy.size.x + 1, "complete milestone copy fits plaque")
			var position_before := hero.position
			var save_before := SaveManager.data.duplicate(true)
			for index: int in 4:
				var button := map.find_child("RouteDestination%d" % index,true,false) as Button
				_check(button != null and button.get_meta("unlocked") == (index <= floori(metres/1800.0)),"live lock icon binds region state")
				_check(button.size.x >= 48 and button.size.y >= 48,"route destination retains touch target")
				var plaque := map.find_child("RouteName%d" % index,true,false) as Control
				_check(get_viewport().get_visible_rect().grow(1).encloses(plaque.get_global_rect()),"all destination labels remain on screen at actual aspect")
				button.pressed.emit()
				var text := overlay.find_child("MilestoneText",true,false) as Label
				_check(text.text.contains("DISCOVERED") if button.get_meta("unlocked") else text.text.contains("ONE RUN"),"selecting region explains actual discovered/locked state")
			_check(hero.position == position_before and SaveManager.data == save_before,"selection does not move progress, award currency or unlock")
			var model := RunnerMissions.new()
			model.load_state(false)
			for index: int in 3:
				var card := overlay.find_child("MissionStrip%d" % index,true,false) as Control
				var label := card.find_child("MissionDescription",true,false) as Label
				var bar := card.find_child("MissionProgress",true,false) as ProgressBar
				_check(label.text == String(model.rows()[index]["text"]).to_upper(),"first page persists identical next-run mission board")
				_check(label.get_visible_line_count() == label.get_line_count() and card.get_global_rect().encloses(label.get_global_rect()),"full mission description remains visible inside card")
				_check(is_equal_approx(bar.value,float(model.rows()[index]["progress"])),"mission progress comes from model")
				var fill := bar.get_theme_stylebox("fill") as StyleBoxFlat
				_check(fill != null and fill.bg_color.is_equal_approx(ExpeditionMenuStyle.GOLD if model.rows()[index]["done"] else Color("3d94dd")),"mission fill is smooth blue or completed gold, without runner ice frame")
			var scroll := overlay.find_child("MissionCardsScroll",true,false) as Control
			var run := overlay.find_child("MissionRunNow",true,false) as Button
			_check(scroll.get_global_rect().grow(1).encloses(run.get_global_rect()),"Run Now visible in first view")
			var safe := LayoutProfile.for_viewport(get_viewport()).safe_rect
			var back := overlay.find_child("OverlayBack",true,false) as Button
			_check(safe.grow(1).encloses(run.get_global_rect()) and safe.grow(1).encloses(back.get_global_rect()),"Run and Back hitboxes respect real safe insets")
			_check(is_equal_approx(scroll.size.x/get_viewport().get_visible_rect().size.x,0.97 if shape.y>shape.x else 0.39),"reference card width independent of touch safe-floor shrink")
			_check(run.pressed.is_connected(Game.start_runner),"Run Now connects actual game entry point alongside button sound")
			(overlay.find_child("OverlayBack",true,false) as Button).pressed.emit()
			await _settle()
			_check(menu.get("_active_menu_panel")=="home","Back returns prior menu")
			menu.queue_free()
			await get_tree().process_frame
			_pages_checked += 1
	LayoutProfile.forced_insets = Vector4(-1,-1,-1,-1)
