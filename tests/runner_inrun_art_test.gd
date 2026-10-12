extends Node
## Authored in-run materials are actually consumed; live state stays native.

var _passes := 0
var _failed := 0

func _ready() -> void:
	_test_compact_mission_titles()
	var atlas := load(RunnerHUDArt.CHROME) as Texture2D
	_check(atlas != null and atlas.get_size() == Vector2(1536, 1024), "authored atlas decodes")
	for key: String in RunnerHUDArt.CHROME_REGIONS:
		var sprite := RunnerHUDArt.chrome(key) as AtlasTexture
		_check(sprite != null and Rect2(Vector2.ZERO, atlas.get_size()).encloses(sprite.region), key + " source region valid")
		var panel := RunnerHUDArt.panel(key, 12, 6, 8)
		_check(panel.get("texture") == sprite and panel.get_minimum_size() == Vector2(24, 14),
			key + " consumes generated texture without oversized minimum")
	var powder := (load(RunnerHUDArt.POWDER) as Texture2D).get_image()
	var center := powder.get_width() / 2
	var crest := roundi(powder.get_height() * RunnerHUDArt.POWDER_CREST)
	_check(powder.get_pixel(center, 0).a < 0.01 and powder.get_pixel(center, crest + 4).a > 0.75,
		"powder anchor follows real transparent-to-painted crest")
	var wordmark := RunnerHUDArt.paused_wordmark() as AtlasTexture
	_check(wordmark != null and wordmark.region.size.x / wordmark.region.size.y > 4.0,
		"pause consumes complete wide sculpted wordmark")
	var reference_atlas := load(RunnerHUDArt.HUD_CHROME) as Texture2D
	for key: String in RunnerHUDArt.HUD_REGIONS:
		var region := RunnerHUDArt.hud_chrome(key) as AtlasTexture
		_check(region != null and Rect2(Vector2.ZERO, reference_atlas.get_size()).encloses(region.region),
			"reference surface region contained " + key)
	var reference_icons := load(RunnerHUDArt.HUD_ICONS) as Texture2D
	for key: String in RunnerHUDArt.HUD_ICON_REGIONS:
		var region := RunnerHUDArt.hud_sprite(key) as AtlasTexture
		_check(region != null and Rect2(Vector2.ZERO, reference_icons.get_size()).encloses(region.region),
			"reference icon region contained " + key)
	for shape: Vector2i in [Vector2i(1920, 1080), Vector2i(1080, 1920), Vector2i(792, 1408)]:
		var viewport := SubViewport.new()
		viewport.size = shape
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(viewport)
		var hud := RunnerHUD.new()
		viewport.add_child(hud)
		hud.setup()
		hud.set_missions([
			{"id":"x2","kind":RunnerMissions.Kind.MULTIPLIER_RUN,"mult":4,"text":"Run 650 m at x4 or better in one run","current":0,"target":650},
			{"id":"fish","kind":RunnerMissions.Kind.FISH_TOTAL,"text":"Collect 400 fish","current":13,"target":400},
			{"id":"distance","kind":RunnerMissions.Kind.CLEAN_RUN,"text":"Dodge everything for 1,400 m in one run","current":38,"target":1400}])
		for frame: int in 3:
			await get_tree().process_frame
		var headline := hud._headline_column.get_global_rect()
		_check(headline.position.y >= shape.y * 0.035 and headline.position.y <= shape.y * 0.08,
			"headline occupies reference top inset rather than screen edge " + str(shape))
		_check(not headline.intersects(hud._pause_button.get_global_rect()),
			"real compact portrait score bounds remain clear of pause " + str(shape))
		var gauge := hud._gauge_holder.get_global_rect()
		var bottom_margin := float(shape.y) - gauge.end.y
		_check(bottom_margin >= (90.0 if shape.y > shape.x else 36.0)
			and Rect2(Vector2.ZERO, Vector2(shape)).encloses(gauge),
			"avalanche meter clears reference bottom snow region " + str(shape))
		_check(hud._mission_panel.get_theme_stylebox("panel").get("texture") == RunnerHUDArt.hud_chrome("card")
			and hud._pause_button.icon == RunnerHUDArt.hud_sprite("pause"),
			"actual live controls consume reference-specific surfaces and bare pause bars " + str(shape))
		_check(hud._pip_spent.texture == RunnerHUDArt.hud_sprite("heart_spent")
			and hud._pip_spent.texture != hud._pip_alive.texture,
			"spent lives use empty gray artwork rather than pink-tinted filled hearts " + str(shape))
		for gap: float in [0.0, 34.0, 64.0]:
			hud.set_stats(0, 0, 0, 1, 3, gap)
			for frame: int in 2: await get_tree().process_frame
			_check(is_equal_approx(hud._gauge_bar.value, gap / 64.0)
				and hud._gauge_value.text == "%d m BEHIND" % int(gap),
				"fixed metre scale preserves absolute gap " + str(gap) + " " + str(shape))
			var face := hud._gauge_holder.get_global_rect()
			var bar := (hud._gauge_bar.get_parent() as Control).get_global_rect()
			for caption: Label in [hud._gauge_tag, hud._gauge_value]:
				var ink := caption.get_global_rect()
				_check(ink.position.y >= face.position.y + face.size.y * 0.25
					and ink.position.x >= face.position.x + face.size.x * 0.07
					and ink.end.x <= face.end.x - face.size.x * 0.07
					and ink.end.y < bar.position.y and caption.get_line_count() == 1,
					"gauge caption stays below snow crest and inside ivory rim " + str(shape) + " " + caption.text)
		for index: int in 3:
			var goal_label := hud._mission_labels[index]
			_check(goal_label.get_line_count() <= 2 and goal_label.get_visible_line_count() == goal_label.get_line_count()
				and goal_label.accessibility_name == goal_label.tooltip_text
				and goal_label.get_theme_font("font") == ExpeditionMenuStyle.display_font(),
				"typed compact goal fully visible with complete accessible wording " + str(shape) + " row" + str(index))
			var inner := hud._mission_panel.get_global_rect().grow(-18.0 * hud._hud_scale)
			var metric := hud._mission_pcts[index].get_global_rect()
			_check(metric.end.x <= inner.end.x + 0.1,
				"challenge counter stays inside painted right edge " + str(shape) + " row" + str(index))
		# Actual phone screenshot regression: counters previously orphaned the m
		# in DODGE250m and forced short RUN3,000m onto another line.
		hud.set_missions([
			{"id":"phone_dodge","kind":RunnerMissions.Kind.CLEAN_RUN,"text":"Dodge everything for 250 m in one run","current":173,"target":250},
			{"id":"phone_run","kind":RunnerMissions.Kind.DISTANCE_TOTAL,"text":"Run 3,000 m","current":567,"target":3000},
			{"id":"phone_fish","kind":RunnerMissions.Kind.FISH_TOTAL,"text":"Collect 40 fish","current":40,"target":40,"done":true}])
		for frame: int in 3: await get_tree().process_frame
		for index: int in 2:
			var compact := hud._mission_labels[index]
			_check(compact.get_line_count() == 1 and compact.text.contains("\u00a0m"),
				"actual short distance goal keeps single line with indivisible unit " + str(shape) + " row" + str(index))
			_check(not compact.get_global_rect().intersects(hud._mission_pcts[index].get_global_rect())
				and hud._mission_pcts[index].get_line_count() == 1,
				"real counter remains readable without colliding with title " + str(shape))
		# Real Chrome regression: the same row grows from 999 to 1,146 without
		# a parent resize. Its current counter width must move below the full
		# distance title, not break the non-breaking unit into a lone second line.
		for current: int in [999, 1146, 7999]:
			hud.set_missions([{"id":"growing_total","kind":RunnerMissions.Kind.DISTANCE_TOTAL,
				"text":"Run 8,000 m in total","current":current,"target":8000}])
			for frame: int in 4: await get_tree().process_frame
			var intact := hud._mission_labels[0]
			_check(intact.get_line_count() == 1 and intact.get_visible_line_count() == 1
				and intact.text == "RUN 8,000\u00a0m"
				and not intact.get_global_rect().intersects(hud._mission_pcts[0].get_global_rect()),
				"growing actual count preserves whole RUN8,000m title " + str(shape) + " " + str(current))
		hud.set_missions([
			{"id":"large_total","kind":RunnerMissions.Kind.DISTANCE_TOTAL,"text":"Run 24,000 m in total","current":18777,"target":24000},
			{"id":"large_multiplier","kind":RunnerMissions.Kind.MULTIPLIER_RUN,"mult":4,"text":"Run 1,600 m at x4 or better in one run","current":1222,"target":1600},
			{"id":"large_fish","kind":RunnerMissions.Kind.FISH_TOTAL,"text":"Collect 1,000 fish in total","current":999,"target":1000}])
		for frame: int in 6: await get_tree().process_frame
		for index: int in 3:
			var title := hud._mission_labels[index]
			var metric := hud._mission_pcts[index]
			var card_inner := hud._mission_panel.get_global_rect().grow(-18.0 * hud._hud_scale)
			print("[runner_inrun_art] large row ",str(shape)," ",index," ",title.text," title=",title.get_global_rect(),
				" metric=",metric.get_global_rect()," inner=",card_inner," lines=",title.get_line_count(),
				" vertical=",title.get_parent().vertical)
			_check(card_inner.encloses(title.get_global_rect()) and card_inner.encloses(metric.get_global_rect())
				and not title.get_global_rect().intersects(metric.get_global_rect())
				and title.get_line_count() <= 2 and title.get_line_count() == title.get_visible_line_count(),
				"large actual totals preserve full title/counter inside tracker " + str(shape) + " row" + str(index))
			var font := title.get_theme_font("font")
			var widest := 0.0
			for word: String in title.text.split(" "):
				widest = maxf(widest,font.get_string_size(word,HORIZONTAL_ALIGNMENT_LEFT,-1,title.get_theme_font_size("font_size")).x)
			_check(widest <= title.size.x + 0.1,
				"distance plus unit remains intact rather than broken into glyph fragments " + str(shape))
		var existing_observers := hud._powerup_box.resized.get_connections().size()
		var toast := SceneRouter._make_achievement_toast("Power Player · Bronze")
		viewport.add_child(toast)
		SceneRouter._place_achievement_toast(toast, hud)
		_check(toast.size.y == 128.0 and toast.size.x <= 600.0,
			"first-frame toast remains bounded before any container sort " + str(shape))
		# Reproduce a grant arriving after the toast's initial empty-column read.
		hud.set_powerups({&"magnet": 8.0, &"shield": 8.0, &"double": 8.0})
		for frame: int in 3:
			await get_tree().process_frame
		for slot: Control in hud._powerup_slots:
			var face := slot.get_child(0) as Control
			var icon := face.get_child(1) as TextureRect
			var timer := face.get_child(2) as Control
			var inner := Rect2(Vector2.ZERO, slot.size).grow(-5.0 * hud._hud_scale)
			_check(inner.encloses(Rect2(face.position + icon.position,icon.size))
				and inner.encloses(Rect2(face.position + timer.position,timer.size)),
				"boost art and real countdown retain interior padding " + str(shape))
			_check(hud._powerup_times[hud._powerup_slots.find(slot)].get_line_count() == 1,
				"boost countdown stays on one line " + str(shape))
		var no_hud_overlap := not toast.get_global_rect().intersects(hud._mission_panel.get_global_rect())
		for power_slot: Control in hud._powerup_slots:
			no_hud_overlap = no_hud_overlap and not toast.get_global_rect().intersects(power_slot.get_global_rect())
		_check(no_hud_overlap, "toast follows newly visible powers without hiding any HUD state " + str(shape))
		if not Rect2(Vector2.ZERO, Vector2(shape)).encloses(toast.get_global_rect()):
			print("[runner_inrun_art] toast_bounds ", shape, " ", toast.get_global_rect(),
				" headline=", hud._headline_column.get_global_rect())
		_check(not toast.get_global_rect().intersects(hud._headline_column.get_global_rect()),
			"achievement notice does not cover live score " + str(shape))
		_check(Rect2(Vector2.ZERO, Vector2(shape)).encloses(toast.get_global_rect()),
			"achievement notice remains in viewport " + str(shape))
		_check(toast.mouse_filter == Control.MOUSE_FILTER_IGNORE
			and toast.get_theme_stylebox("panel").get("texture") == RunnerHUDArt.chrome("gauge"),
			"achievement notice uses painted art without blocking input " + str(shape))
		var name_label := toast.get_node("AchievementName") as Label
		_check(toast.get_global_rect().encloses(name_label.get_global_rect())
			and name_label.get_line_count() <= 2,
			"complete achievement name fits bounded two-line notice " + str(shape))
		toast.free()
		_check(hud._powerup_box.resized.get_connections().size() == existing_observers,
			"toast releases HUD layout subscriptions on exit " + str(shape))
		hud.set_stats(245, 32, 1460, 1, 0, 0.0)
		_check(hud._distance_label.text == "245 m" and hud._fish_label.text == "32"
			and hud._shown_hits == 0 and is_zero_approx(hud._gauge_bar.value),
			"generated materials retain true native counters " + str(shape))
		var normal := hud._pause_button.get_theme_stylebox("normal")
		var hover := hud._pause_button.get_theme_stylebox("hover")
		_check(normal.get("texture") != null and hover.get("texture") == normal.get("texture"),
			"pause hover preserves painted artwork " + str(shape))
		var earned_before := hud._completed_missions.duplicate()
		hud.show_mission_complete("SET COMPLETE — 1★")
		_check(hud._completed_missions == earned_before,
			"aggregate celebration is never recorded as a completed challenge " + str(shape))
		hud.show_game_over({"distance":245.0, "score":1460, "fish":32, "missions":[]})
		hud._relayout()
		_check(hud._results_background.texture == RunnerHUDArt.caught_background(shape.y >= shape.x),
			"results use same final catch illustration " + str(shape))
		_check(hud._results_background.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED,
			"caught illustration preserves proportions " + str(shape))
		hud.hide_game_over()
		_check(hud._results_background == null, "retry releases result illustration node " + str(shape))
		viewport.free()
	await get_tree().process_frame
	print("[runner_inrun_art] DONE: %d passed, %d failed" % [_passes, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_compact_mission_titles() -> void:
	var expected := {
		"dist_run":"RUN 2,200 m", "dist_total":"RUN 10,000 m", "clean_run":"DODGE 1,400 m",
		"multi_run":"RUN 650 m AT x4+", "fish_total":"COLLECT 400 FISH", "fish_run":"COLLECT 90 FISH",
		"jump_total":"JUMP 100 TIMES", "jump_run":"JUMP 14 TIMES", "slide_total":"SLIDE 80 TIMES",
		"slide_run":"SLIDE 10 TIMES", "lane_total":"220 LANE CHANGES", "lane_run":"40 LANE CHANGES",
		"near_total":"25 NEAR MISSES", "near_run":"3 NEAR MISSES", "power_total":"USE 30 POWER-UPS",
		"power_run":"USE 4 POWER-UPS", "power_specific":"6 MAGNETS", "ramp_total":"TAKE 30 RAMPS",
		"ramp_run":"TAKE 4 RAMPS"}
	# Formatting inputs are explicit: pacing changes must not rewrite the title
	# contract or turn this UI test into a calibration snapshot.
	var targets := [2200,10000,1400,650,400,90,100,14,80,10,220,40,25,3,30,4,6,30,4]
	for index: int in RunnerMissions.TEMPLATES.size():
		var template: Dictionary = RunnerMissions.TEMPLATES[index]
		var row := {"id":template["id"], "kind":template["kind"], "target":targets[index],
			"mult":4, "param":"magnet", "text":"Complete authoritative goal wording"}
		_check(RunnerHUD.compact_mission_title(row) == expected[row["id"]]
			and row["text"] == "Complete authoritative goal wording",
			"typed HUD title retains supplied target and authoritative full wording " + String(row["id"]))
	for pair: Array in [["shield", "6 SHIELDS"], ["double", "6 DOUBLE POINTS"]]:
		_check(RunnerHUD.compact_mission_title({"kind":RunnerMissions.Kind.POWERUP_SPECIFIC,
			"target":6,"param":pair[0]}) == pair[1],
			"specific power title retains exact pickup type " + pair[0])
	_check(RunnerHUD.compact_mission_title({"id":"future", "text":"New goal 123 m", "target":123}) == "NEW GOAL 123 m",
		"unknown goal retains complete supplied wording without guessing a type")

func _check(ok: bool, message: String) -> void:
	if ok:
		_passes += 1
	else:
		_failed += 1
	print("[runner_inrun_art] %s %s" % ["PASS" if ok else "FAIL", message])
