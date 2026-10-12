extends Node
## End-state geometry/authority checks. No native raster or input claims.

class GameFixture:
	extends RunnerGame
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass

const END_ART = preload("res://scripts/ui/runner_end_art.gd")
var _passed := 0
var _failed := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for key: String in ["caught_background_desktop_v5", "caught_background_portrait_v5",
		"avalanche_wordmark_v5", "avalanche_wordmark_desktop_v5", "pause_blank_card_v5"]:
		var texture := load(END_ART.ROOT + key + ".webp") as Texture2D
		_check(texture != null and texture.get_image() != null and texture.get_image().has_mipmaps(),
			"new end-state art decodes with mipmaps: " + key)
	for shape: Vector2i in [Vector2i(1920,1080), Vector2i(1080,1920), Vector2i(792,1408)]:
		var viewport := SubViewport.new()
		viewport.size = shape
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(viewport)
		var bounds := Rect2(Vector2.ZERO, Vector2(shape))
		var hud := RunnerHUD.new()
		viewport.add_child(hud)
		hud.setup()
		for count: int in [1,2,3]:
			var missions := ["Collect 15 fish"]
			if count >= 2: missions.append("Run 150 m at x2 or better in one run")
			if count == 3: missions.append("Run 8,000 m in total")
			hud.show_game_over({"score":1460,"distance":245.0,"fish":32,"best":1200,
				"is_new_best":true,"missions":missions})
			for frame: int in 6: await get_tree().process_frame
			var label := str(shape) + " / " + str(count) + " completed"
			_check_result_paints(hud, label)
			_check(bounds.encloses(hud._results_card.get_global_rect()), "results all controls fit first view " + label)
			_check(hud._results_mission_labels.size() == count, "every completed mission retained " + label)
			for mission: Label in hud._results_mission_labels:
				_check(mission.get_visible_line_count() == mission.get_line_count()
					and bounds.encloses(mission.get_global_rect()), "full mission label visible " + label)
				var tile := mission.get_parent().get_parent().get_parent() as PanelContainer
				var face := tile.get_global_rect()
				var safe := Rect2(face.position + Vector2(face.size.x * 0.04, face.size.y * 0.18),
					Vector2(face.size.x * 0.92, face.size.y * 0.70))
				var progress := mission.get_parent().get_child(1) as Control
				_check(safe.encloses(mission.get_global_rect()) and safe.encloses(progress.get_global_rect())
					and mission.get_line_count() <= 2 and mission.text in missions,
					"exact completed goal and bar fit painted ivory interior " + label + " " + mission.text)
			var rows := hud._results_card.find_child("ResultsCompletedMissions", true, false).get_children()
			for index: int in range(1, rows.size()):
				_check(rows[index].get_global_rect().position.y > rows[index - 1].get_global_rect().end.y,
					"completed goal tiles keep separate visible gaps " + label)
			for button: Button in hud._game_over_buttons.get_children():
				_check(bounds.encloses(button.get_global_rect()) and button.get_global_rect().size.y > 70,
					"result action touch target enclosed " + label + " " + button.accessibility_name)
			print("[runner_end_fidelity] geometry ", JSON.stringify({"shape":str(shape),"missions":count,
				"card":str(hud._results_card.get_global_rect()),"summary":str(hud._results_summary.get_global_rect()),
				"actions":str(hud._game_over_buttons.get_global_rect())}))
			if count == 2:
				var card_id := hud._results_card.get_instance_id()
				var rotated := Vector2i(shape.y,shape.x)
				viewport.size = rotated
				hud._relayout() # Headless setup intentionally omits resize subscriptions.
				for frame: int in 6: await get_tree().process_frame
				_check_result_paints(hud, "rotated " + str(shape))
				print("[runner_end_fidelity] rotated geometry ", JSON.stringify({"shape":str(rotated),
					"card":str(hud._results_card.get_global_rect()),"actual_view":str(hud._view_size)}))
				_check(hud._results_card.get_instance_id() == card_id and hud._results_mission_labels.size() == 2
					and Rect2(Vector2.ZERO,Vector2(rotated)).encloses(hud._results_card.get_global_rect()),
					"rotation retains results nodes/data and enclosed actions " + str(shape))
				viewport.size = shape
				hud._relayout()
				for frame: int in 6: await get_tree().process_frame
				_check_result_paints(hud, "round-trip " + str(shape))
				_check(bounds.encloses(hud._results_card.get_global_rect()), "round-trip result scale has no layout drift " + str(shape))
			hud.hide_game_over()
			await get_tree().process_frame
		hud.show_game_over({"score":1460,"distance":245.0,"fish":32,"missions":[],
			"mission_rows":[{"text":"Collect 300 fish in total","current":300,"target":300,"progress":1.0,"done":true},
				{"text":"Run 8,000 m in total","current":2000,"target":8000,"progress":0.25,"done":false}]})
		for frame: int in 6: await get_tree().process_frame
		var partial_rows := hud._results_card.find_child("ResultsCompletedMissions",true,false)
		var partial_bar := partial_rows.find_children("*","ProgressBar",true,false)[0] as ProgressBar
		var amount := partial_rows.find_child("ResultMissionProgress",true,false) as Label
		_check(hud._results_mission_labels[0].text == "Run 8,000 m in total"
			and is_equal_approx(partial_bar.value,0.25) and amount.text == "2,000 / 8,000"
			and partial_rows.find_child("CompletionCheck",true,false) == null,
			"prior-run completion excluded; unfinished goal retains real label/count/progress " + str(shape))
		print("[runner_end_fidelity] partial geometry ",JSON.stringify({"shape":str(shape),
			"card":str(hud._results_card.get_global_rect()),"amount":str(amount.get_global_rect()),
			"amount_lines":amount.get_line_count(),"title":str(hud._results_mission_labels[0].get_global_rect())}))
		_check(bounds.encloses(hud._results_card.get_global_rect())
			and amount.get_line_count() == 1
			and not amount.get_global_rect().intersects(hud._results_mission_labels[0].get_global_rect()),
			"partial goal and Results actions fit without overlap " + str(shape))
		hud.hide_game_over()
		await get_tree().process_frame
		hud.show_game_over({"score":1460,"distance":245.0,"fish":32,"missions":[],
			"mission_rows":[{"text":"Collect 300 fish in total","current":300,"target":300,"progress":1.0,"done":true},
				{"text":"Run 8,000 m in total","current":8000,"target":8000,"progress":1.0,"done":true},
				{"text":"Jump 40 times in total","current":40,"target":40,"progress":1.0,"done":true}]})
		for frame: int in 6: await get_tree().process_frame
		var status := hud._results_card.find_child("ResultsGoalsStatus",true,false) as Label
		_check(status != null and status.text == "New goals on your next run"
			and hud._results_mission_labels.is_empty()
			and hud._results_card.find_child("CompletionCheck",true,false) == null,
			"previously completed board shows neutral next-run status without duplicate completion " + str(shape))
		_check(bounds.encloses(hud._results_card.get_global_rect())
			and status.get_visible_line_count() == status.get_line_count(),
			"neutral next-run status and all Results controls fit " + str(shape))
		hud.hide_game_over()
		await get_tree().process_frame
		var game := GameFixture.new()
		viewport.add_child(game)
		game.build_finished = true
		game._presentation_started = true
		game.running = true
		# Match a real touch viewport's floor; raw viewport and usable width
		# differ, which previously made the painted pause plate too narrow.
		LayoutProfile.forced_insets = Vector4(24,24,24,24) if shape.y > shape.x else Vector4.ZERO
		game._toggle_pause()
		for frame: int in 6: await get_tree().process_frame
		var card := game._pause_layer.find_child("PauseCard", true, false) as Control
		_check(card != null and bounds.encloses(card.get_global_rect()), "pause panel fits " + str(shape))
		if shape.y > shape.x:
			_check(card.size.x >= shape.x * 0.735 and card.size.x <= shape.x * 0.745,
				"portrait pause backing uses reference width inside touch safe area " + str(shape))
		for button: Button in card.find_children("*", "Button", true, false):
			_check(bounds.encloses(button.get_global_rect()), "pause control enclosed " + button.accessibility_name + " " + str(shape))
		game._close_pause()
		LayoutProfile.forced_insets = Vector4(-1,-1,-1,-1)
		var chaser := RunnerChaser.new()
		game.add_child(chaser)
		game.chaser = chaser
		chaser._build_catch_spray(load(RunnerHUDArt.POWDER))
		chaser.overrun()
		for fraction: float in [0.5,0.875]:
			chaser.present_overrun(fraction)
			_check(chaser._catch_title.modulate.a >= 0.95
				and bounds.encloses(chaser._catch_title.get_global_rect()), "sustained headline fits " + str(shape))
		for fraction: float in [0.5, 1.7 / RunnerGame.CATCH_TIME]:
			chaser.present_overrun(fraction)
			var crest := (chaser._catch_snow.position.y + chaser._catch_snow.size.y * RunnerHUDArt.POWDER_CREST) / shape.y
			_check(crest >= 0.73, "early painted crest stays below hero region " + str(shape) + " / " + str(fraction))
		chaser.present_overrun(1.0)
		_check(is_zero_approx(chaser.gap) and is_zero_approx(chaser._catch_title.modulate.a)
			and is_equal_approx(chaser._catch_illustration.modulate.a,1.0), "catch ends in complete illustration " + str(shape))
		chaser.reset()
		_check(not chaser._catch_canvas.visible and is_zero_approx(chaser._catch_title.modulate.a),
			"retry clears title and powder " + str(shape))
		game.player = RunnerPlayer.new()
		game.add_child(game.player)
		game.player._visual = PenguinVisual.new()
		game.player.add_child(game.player._visual)
		game.player.state = RunnerPlayer.State.DEAD
		game.player.distance = 245.0
		game.player.set_input_enabled(false)
		game._dead = true
		game._catch_elapsed = 0.14
		game._pending_results = {"score":1460}
		game._advance_catch(0.02)
		_check(game.player._visual.pose == PenguinVisual.Pose.SLIDE and game.player.state == RunnerPlayer.State.DEAD
			and not game.player._input_enabled and is_equal_approx(game.player.distance,245.0),
			"catch prone pose preserves dead player authority " + str(shape))
		viewport.queue_free()
		await get_tree().process_frame
	# Focused pause controls can enqueue one UI-hover WAV. Stop it before the
	# fixture's immediate shutdown so the dummy audio thread releases playback.
	for audio_player: AudioStreamPlayer in AudioManager._sfx_pool:
		audio_player.stop()
		audio_player.stream = null
	await get_tree().create_timer(0.25).timeout
	print("[runner_end_fidelity] DONE: %d passed, %d failed" % [_passed,_failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _check(ok: bool, detail: String) -> void:
	if ok: _passed += 1
	else: _failed += 1
	print("[runner_end_fidelity] %s %s" % ["PASS" if ok else "FAIL",detail])

func _check_result_paints(hud: RunnerHUD, detail: String) -> void:
	var panels: Array[Node] = [hud._results_card.find_child("ResultsScorePanel", true, false)]
	panels.append_array(hud._results_card.find_child("ResultsStats", true, false).get_children())
	panels.append_array(hud._results_card.find_child("ResultsCompletedMissions", true, false).get_children())
	var intact := panels.size() == 4 + hud._results_mission_labels.size()
	for panel: Node in panels:
		var face := (panel as Control).get_theme_stylebox("panel")
		intact = intact and face.get("texture") is Texture2D
	_check(intact, "all score/stat/mission painted textures survive layout " + detail)
	if hud._view_size.y >= hud._view_size.x:
		var unit := hud._view_size.x / 1080.0
		var captions_safe := true
		for panel: Node in panels.slice(0, 4):
			var score := panel.name == "ResultsScorePanel"
			var caption := panel.find_child("ResultsScoreCaption" if score else "ResultsStatCaption", true, false) as Label
			var rect := (panel as Control).get_global_rect()
			captions_safe = captions_safe and caption != null
			if caption != null:
				var caption_rect := caption.get_global_rect()
				captions_safe = captions_safe and caption_rect.position.y >= rect.position.y + (34.0 if score else 26.0) * unit \
					and rect.encloses(caption_rect) and caption.get_line_count() == 1
		_check(captions_safe, "portrait SCORE and metric captions clear painted snow crest " + detail)
