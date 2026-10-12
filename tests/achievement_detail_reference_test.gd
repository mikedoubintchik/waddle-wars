extends Node
## Real catalog and selection; no fabricated progress or rewards.
var checks := 0
var failures := 0

func _ready() -> void:
	LeaderboardClient.set_process(false)
	var saved := SaveManager.data.duplicate(true)
	SaveManager.data = SaveManager.default_save()
	_check_catalog_rules()
	for shape: Vector2i in [Vector2i(941,1672), Vector2i(1672,941), Vector2i(444,792)]:
		GameConfig.force_touch = shape.y > shape.x
		LayoutProfile.forced_insets = Vector4.ONE * (24.0 if GameConfig.force_touch else 0.0)
		var viewport := SubViewport.new()
		viewport.size = shape
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(viewport)
		var page := load("res://scenes/menus/achievements.tscn").instantiate() as Control
		viewport.add_child(page)
		for frame: int in 5: await get_tree().process_frame
		var guide := page.find_child("AchievementExplanation", true, false) as Label
		check(guide != null and guide.text.contains("across runs") and guide.text.contains("Select a badge"), "achievement scope and interaction explained")
		var rail := page.find_child("AchievementScrollRail", true, false) as VScrollBar
		check(rail != null and rail.has_theme_stylebox_override("grabber"), "collection has illustrated blue scroll rail")
		var first: Button = page._achievement_buttons["runner_fish_bronze"]
		var screen := Rect2(Vector2.ZERO,Vector2(shape))
		check(screen.encloses(first.get_global_rect()), "first collection row visible at " + str(shape))
		check(absf(first.get_global_rect().position.x / shape.x - (0.035 if GameConfig.force_touch else 0.45)) < 0.055, "collection column matches authored reference gutter")
		var before := SaveManager.data.duplicate(true)
		for id: String in AchievementsDB.RUNNER_ORDER:
			page._select_achievement(id)
			for frame: int in 3: await get_tree().process_frame
			var reward := page.find_child("AchievementReward",true,false) as Control
			var value := page.find_child("AchievementRewardValue",true,false) as Label
			var detail := page._detail.get_parent() as Control
			check(value.text == "%d XP" % int(AchievementsDB.get_item(id).get("xp",150)), "authoritative reward " + id)
			check(value.get_line_count() == 1 and reward.get_global_rect().grow(1).encloses(value.get_global_rect()), "complete one-line reward " + id)
			check(detail.get_global_rect().grow(1).encloses(reward.get_global_rect()), "reward enclosed within detail " + id)
			var description := page.find_child("AchievementDescription",true,false) as Label
			check(description.get_theme_font_size("font_size") <= maxi(16, roundi(page._tile_width * 0.14)), "body avoids repeated touch font scaling " + id)
			check(description.get_line_count() <= 3 and detail.get_global_rect().grow(1).encloses(description.get_global_rect()), "description readable and enclosed " + id)
			var scope := page.find_child("AchievementScope",true,false) as Label
			var counts := page.find_child("AchievementWhatCounts",true,false) as Label
			var next := page.find_child("AchievementNextTier",true,false) as Label
			check(scope.text == AchievementsDB.get_item(id)["scope"] and counts.text == AchievementsDB.get_item(id)["counts"], "selected badge explains its actual counting rule " + id)
			check(next.text == AchievementsDB.next_tier_requirement(id), "next tier requirement uses real next target " + id)
			for explanation: Label in [scope, counts, next]:
				check(explanation.visible and explanation.max_lines_visible == -1 and not explanation.clip_text, "all explanation text available " + explanation.name)
				check(detail.get_global_rect().grow(1).encloses(explanation.get_global_rect()), "explanation enclosed without truncation " + explanation.name)
			check(counts.get_line_count() <= 6 and next.get_line_count() <= 3, "explanation readable in available width " + id)

		check(SaveManager.data == before, "selection never awards progress or XP")
		SaveManager.set_value("achievements", {"runner_fish_bronze":true,"runner_fish_silver":true})
		page._select_achievement("runner_fish_bronze")
		for frame: int in 3: await get_tree().process_frame
		check((page.find_child("AchievementNextTier",true,false) as Label).text.ends_with("Already earned."), "next tier already earned remains truthful")
		check((page.find_child("AchievementProgressValue",true,false) as Label).text == "EARNED · PREVIOUS GOAL", "migrated earned goal remains earned")
		SaveManager.data = SaveManager.default_save()
		page.free()
		viewport.free()
	SaveManager.data = saved
	GameConfig.force_touch = false
	LayoutProfile.forced_insets = Vector4(-1,-1,-1,-1)
	for player: AudioStreamPlayer in AudioManager._sfx_pool:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.1).timeout
	print("[achievement-detail] DONE: %d/%d passed" % [checks-failures,checks])
	get_tree().quit(1 if failures else 0)

func _check_catalog_rules() -> void:
	var expected := {
		"distance": ["runner_distance_total", [12000,80000,300000,800000], "ACROSS ALL RUNS", "Every metre"],
		"fish": ["runner_fish_collected", [750,4000,16000,45000], "ACROSS ALL RUNS", "Mission rewards and other fish grants do not count"],
		"missions": ["runner_missions_done", [6,24,60,120], "ACROSS ALL RUNS", "Each completed mission counts once"],
		"time": ["runner_active_seconds", [900,5400,18000,36000], "ACROSS ALL RUNS", "Menus, countdowns, pauses"],
		"run": ["runner_best_distance", [3000,4500,6500,9000], "IN ONE RUN", "separate runs are not added"],
		"clean": ["runner_best_clean_distance", [2000,3000,4500,6500], "ONE HIT-FREE STREAK", "a shield save does not break it"],
		"near": ["runner_near_misses", [12,60,250,600], "ACROSS ALL RUNS", "when CLOSE! appears"],
		"power": ["runner_powerups_collected", [12,60,250,600], "ACROSS ALL RUNS", "Repeated types count"],
	}
	for family: String in expected:
		var rule: Array = expected[family]
		for tier: int in 4:
			var id := "runner_%s_%s" % [family,AchievementsDB.TIERS[tier]]
			var item := AchievementsDB.get_item(id)
			check(item["metric"] == rule[0] and item["target"] == rule[1][tier], "explanation preserves actual metric and pacing " + id)
			check(item["scope"] == rule[2] and String(item["counts"]).contains(rule[3]), "specific counting semantics " + id)
			var next_id := AchievementsDB.next_tier_id(id)
			check(next_id == ("runner_%s_%s" % [family,AchievementsDB.TIERS[tier+1]] if tier < 3 else ""), "next tier follows same family " + id)
			if tier == 3:
				check(AchievementsDB.next_tier_requirement(id) == "Diamond is the final tier.", "no invented fifth tier " + id)
	check(AchievementsDB.next_tier_id("first_win").is_empty(), "legacy goals do not invent runner tiers")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("[achievement-detail] FAIL " + label)
