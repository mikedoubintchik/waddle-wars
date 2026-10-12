extends Node
## Regression for the synchronous retry handoff from a completed run to the
## live gameplay. The HUD must show the new run before another frame ticks.


class RunnerGameFixture:
	extends RunnerGame

	var lifecycle_rows: Array[Dictionary] = []
	var camera_reset_count: int = 0

	func _ready() -> void:
		pass

	func _process(_delta: float) -> void:
		pass

	func step_process(delta: float) -> void:
		super._process(delta)

	func _place_camera(delta: float, snap: bool) -> void:
		super._place_camera(delta, snap)
		if snap:
			camera_reset_count += 1

	func _emit_lifecycle(event_name: String, fields: Dictionary = {}) -> void:
		var row := {
			"name": event_name,
			"fields": fields.duplicate(true),
			"dead": _dead,
			"running": running,
			"presentation_started": _presentation_started,
			"countdown": _countdown,
			"camera_resets": camera_reset_count,
			"input_enabled": player._input_enabled if player != null else false,
			"track_processing": track.process_mode if track != null else -1,
		}
		if hud != null:
			row["distance"] = hud._distance_label.text
			row["score"] = hud._score_label.text
			row["fish"] = hud._fish_label.text
			row["hits"] = hud._shown_hits
			row["multiplier"] = hud._shown_multiplier
			row["gap"] = hud._shown_gap
			row["speed_ratio"] = hud._speed_ratio
		lifecycle_rows.append(row)


class TrackProbe:
	extends RunnerTrack

	var reset_count: int = 0

	func reset(_seed_value: int, _dressing_density: float = -1.0) -> void:
		reset_count += 1
	func update_stream(_player_z: float, _difficulty: float) -> void:
		pass


class MissionProbe:
	extends RunnerMissions

	var begin_count: int = 0
	var fixture_rows: Array = [{
		"id": "retry_goal",
		"text": "Collect 5 fish",
		"progress": 0.2,
		"done": false,
	}]

	func begin_run() -> void:
		begin_count += 1

	func rows() -> Array:
		return fixture_rows
	func note_distance(metres: float) -> void:
		fixture_rows[0]["current"] = metres
		fixture_rows[0]["target"] = 700.0
		fixture_rows[0]["progress"] = metres / 700.0


const OLD_DISTANCE: float = 236.0
const OLD_FISH: int = 25
const OLD_SCORE: int = 876

var _passes: int = 0
var _failures: int = 0


func _ready() -> void:
	_test_avalanche_presentation()
	_test_retry_resets_hud_synchronously()
	_test_initial_countdown_lifecycle()
	await get_tree().process_frame
	print("[runner_retry_hud] DONE: %d passed, %d failed" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_avalanche_presentation() -> void:
	var hud := RunnerHUD.new()
	add_child(hud)
	hud.setup()
	var fish_glyph_size := RunnerHUD.FISH_FLOATER_SIZE * hud._hud_scale
	var fish_glyphs_fit := not hud._float_fish_icons.is_empty()
	for icon: TextureRect in hud._float_fish_icons:
		fish_glyphs_fit = fish_glyphs_fit and icon.size.is_equal_approx(fish_glyph_size) \
			and icon.get_combined_minimum_size().x <= fish_glyph_size.x \
			and icon.get_combined_minimum_size().y <= fish_glyph_size.y
	_check("fish_reward_glyphs_fit_compact_rendered_bounds", fish_glyphs_fit)
	_check("initial_countdown_has_true_avalanche_gap",
		hud._gauge_tag.text == "AVALANCHE GAP"
		and hud._gauge_value.text == "%d m BEHIND" % int(RunnerConfig.CHASER_BASE_GAP)
		and is_equal_approx(hud._gauge_bar.value, RunnerConfig.CHASER_BASE_GAP / RunnerHUD.GAUGE_DISPLAY_RANGE))

	# The meter is the wall's real separation from the player, not metres run
	# or a percentage mislabeled as distance. Feed the actual chaser scalar.
	var chaser := RunnerChaser.new()
	add_child(chaser)
	chaser.tick(1.0, 120.0, 1.0)
	_check("hit_immediately_closes_gap", chaser.gap <= \
		RunnerConfig.CHASER_BASE_GAP - RunnerConfig.CHASER_GAP_PER_HIT)
	_check("snow_front_remains_visible_but_translucent_after_opening",
		chaser.chase_preview_strength(120.0) >= 0.55
		and chaser.chase_preview_strength(120.0) <= 0.75)
	hud.set_stats(120.0, 0, 0, 1, RunnerConfig.MAX_HITS - 1, chaser.gap)
	_check("avalanche_readout_tracks_world_gap",
		is_equal_approx(chaser.global_position.z + 120.0, chaser.gap)
		and hud._distance_label.text == "120 m"
		and hud._gauge_value.text == "%d m BEHIND" % int(chaser.gap)
		and is_equal_approx(hud._gauge_bar.value, chaser.gap / RunnerHUD.GAUGE_DISPLAY_RANGE))
	hud.set_stats(120.0, 0, 0, 1, 1, RunnerHUD.DANGER_GAP - 0.1)
	_check("closing_avalanche_has_explicit_danger_text",
		hud._gauge_tag.text == "AVALANCHE CLOSE!" and hud._in_danger)

	for message: String in ["3", "2", "1", "GO!"]:
		hud.show_message(message)
		_check("countdown_%s_states_chase_objective" % message,
			hud._message_label.text == message and hud._objective_label.visible
			and hud._objective_label.text == "Stay ahead of the avalanche")
	hud.show_message("2 left")
	_check("gameplay_callout_hides_intro_objective", not hud._objective_label.visible)
	hud.show_message("")
	_check("empty_callout_hides_intro_objective", not hud._objective_label.visible)

	# Exercise the real tween without waiting for wall time or rendering. Both
	# labels fade in the same slot, including the reduced-motion path.
	hud._headless = false
	hud._reduced = true
	hud.show_message("3")
	var countdown_tween := hud._message_tween
	hud.show_message("3")
	_check("repeated_countdown_reuses_tween", hud._message_tween == countdown_tween)
	countdown_tween.custom_step(0.90)
	_check("countdown_objective_shares_fade",
		hud._objective_label.visible and hud._objective_label.modulate.a < 1.0
		and is_equal_approx(hud._objective_label.modulate.a, hud._message_label.modulate.a)
		and hud._message_label.scale == Vector2.ONE)
	countdown_tween.custom_step(0.30)
	_check("finished_countdown_clears_objective",
		not hud._objective_label.visible and hud._message_label.text.is_empty())
	hud._headless = true
	hud.show_message("3")
	_check("retry_countdown_restores_objective_alpha",
		hud._objective_label.visible and is_equal_approx(hud._objective_label.modulate.a, 1.0))
	chaser.queue_free()
	hud.queue_free()
	var clean_chaser := RunnerChaser.new()
	add_child(clean_chaser)
	for index: int in 120:
		clean_chaser.tick(1.0, float(index) * 20.0, 0.0)
	_check("clean_run_has_changing_storm_gap", clean_chaser.gap < RunnerConfig.CHASER_BASE_GAP)
	_check("ambient_storm_cannot_catch_clean_runner", clean_chaser.gap >= RunnerConfig.CHASER_BASE_GAP - 6.01)
	clean_chaser.reset()
	_check("retry_resets_storm_pressure", is_equal_approx(clean_chaser.gap,
		RunnerConfig.CHASER_BASE_GAP) and is_zero_approx(clean_chaser._last_pressure))
	clean_chaser.queue_free()


func _test_retry_resets_hud_synchronously() -> void:
	var game := RunnerGameFixture.new()
	add_child(game)
	game.set_process(false)

	var track := TrackProbe.new()
	game.add_child(track)
	game.track = track

	var old_player := RunnerPlayer.new()
	old_player.distance = OLD_DISTANCE
	old_player.hits_left = 0
	old_player.state = RunnerPlayer.State.DEAD
	old_player.powerups[RunnerConfig.POWERUP_MAGNET] = 7.5
	game.add_child(old_player)
	game.player = old_player

	var chaser := RunnerChaser.new()
	chaser.gap = 0.1
	game.add_child(chaser)
	chaser.overrun()
	game.chaser = chaser

	var hud := RunnerHUD.new()
	game.add_child(hud)
	hud.setup()
	game.hud = hud

	var missions := MissionProbe.new()
	game.missions = missions
	game._rng.seed = 0x51A7E
	game._dead = true
	game._catch_elapsed = 0.65
	game._pending_results = {"score": OLD_SCORE}
	game.running = false
	game.elapsed = 12.0
	game.fish = OLD_FISH
	game.hits_taken = RunnerConfig.MAX_HITS
	game.clean_metres = 73.0
	game._score = float(OLD_SCORE)

	# Reproduce the exact covered result state seen in Chrome: completed-run
	# numbers, no lives, avalanche at the camera and a live power-up slot.
	hud.set_stats(OLD_DISTANCE, OLD_FISH, OLD_SCORE, 4, 0, chaser.gap)
	hud.set_powerups(old_player.powerups)
	hud.set_speed_ratio(0.9)
	hud._process(1.0)
	hud.show_mission_complete("OLD COMPLETE")
	_check("aggregate_banner_does_not_invent_completed_goal", hud._completed_missions.is_empty())
	# Actual goal rows, rather than the aggregate celebration channel, own the
	# completed-run list consumed by Results and cleared synchronously on Retry.
	hud.set_missions([{"id":"old_goal","text":"Collect 15 fish","done":true,
		"progress":1.0,"current":15.0,"target":15.0}])
	_check("fixture_has_stale_run_stats",
		hud._distance_label.text == "236 m"
		and hud._score_label.text == "876"
		and hud._fish_label.text == "25"
		and hud._shown_hits == 0
		and hud._shown_multiplier == 4)
	_check("fixture_has_stale_danger_and_powerup",
		hud._in_danger and hud._shown_gap == 0
		and hud._powerup_on[0] and hud._powerup_slots[0].visible)
	_check("fixture_has_completed_mission", hud._completed_missions.size() == 1)

	var saved_busy := SceneRouter._busy
	var saved_presenting := SceneRouter._presenting
	SceneRouter._busy = true
	SceneRouter._presenting = false
	game.restart()
	_check("busy_retry_emits_no_lifecycle_or_world_reset",
		game.lifecycle_rows.is_empty() and track.reset_count == 0 and game.player == old_player)
	SceneRouter._busy = false
	SceneRouter._presenting = true
	game.restart()
	_check("covered_retry_emits_no_lifecycle_or_world_reset",
		game.lifecycle_rows.is_empty() and track.reset_count == 0 and game.player == old_player)
	SceneRouter._busy = false
	SceneRouter._presenting = false
	var callback_frame := Engine.get_process_frames()
	game.restart()
	var returned_frame := Engine.get_process_frames()
	SceneRouter._busy = saved_busy
	SceneRouter._presenting = saved_presenting

	_check("retry_hud_reset_same_callback", returned_frame == callback_frame
		and hud._distance_label.text == "0 m"
		and hud._score_label.text == "0"
		and hud._fish_label.text == "0")
	_check("retry_restores_lives_and_multiplier", hud._shown_hits == RunnerConfig.MAX_HITS
		and _all_life_pips_use(hud, hud._pip_alive)
		and hud._shown_multiplier == 1
		and hud._multiplier_label.text == "x1")
	_check("retry_resets_avalanche_readout", not hud._in_danger
		and is_zero_approx(hud._veil_base)
		and is_equal_approx(hud._danger_gap, RunnerConfig.CHASER_BASE_GAP)
		and hud._shown_gap == int(RunnerConfig.CHASER_BASE_GAP)
		and hud._gauge_value.text == "%d m BEHIND" % int(RunnerConfig.CHASER_BASE_GAP)
		and hud._gauge_tag.text == "AVALANCHE GAP")
	_check("retry_hides_previous_powerups", not _any_powerup_active_or_visible(hud))
	_check("retry_clears_speed_presentation", is_zero_approx(hud._speed_ratio))
	_check("retry_preserves_mission_intent", missions.begin_count == 1
		and hud._mission_ids[0] == "retry_goal"
		and hud._mission_rows[0].visible)
	_check("retry_clears_completed_run_missions", hud._completed_missions.is_empty())
	_check("retry_enters_running_same_callback", not game._dead and game.running
		and game.player._input_enabled and game._countdown <= 0.0
		and is_zero_approx(game.elapsed)
		and game.fish == 0 and game.hits_taken == 0)
	_check("retry_pause_available_immediately", hud._pause_button.visible)
	_check("retry_resets_world_once", track.reset_count == 1
		and game.player != old_player
		and game.player.hits_left == RunnerConfig.MAX_HITS
		and game.player.powerups.is_empty()
		and is_equal_approx(chaser.gap, RunnerConfig.CHASER_BASE_GAP))
	_check("retry_cancels_pending_catch", game._pending_results.is_empty()
		and is_zero_approx(game._catch_elapsed) and not chaser._overrunning)
	game._advance_catch(RunnerGame.CATCH_TIME)
	_check("cancelled_catch_cannot_reopen_results", game._pending_results.is_empty()
		and is_zero_approx(game._catch_elapsed) and hud._game_over == null)
	_check("retry_lifecycle_order", _lifecycle_names(game) == [
		"runner_retry_started", "runner_running"])
	if game.lifecycle_rows.size() == 2:
		var started: Dictionary = game.lifecycle_rows[0]
		var ready: Dictionary = game.lifecycle_rows[1]
		_check("retry_start_precedes_previous_run_reset", started["dead"]
			and started["distance"] == "236 m" and started["score"] == "876"
			and int(started["camera_resets"]) == 0)
		_check("retry_running_event_observes_zero_hud", ready["fields"].get("retry") == true
			and ready["distance"] == "0 m" and ready["score"] == "0" and ready["fish"] == "0"
			and int(ready["hits"]) == RunnerConfig.MAX_HITS and int(ready["multiplier"]) == 1
			and int(ready["gap"]) == int(RunnerConfig.CHASER_BASE_GAP)
			and is_zero_approx(float(ready["speed_ratio"])))
		_check("retry_running_follows_camera_reset", not ready["dead"]
			and ready["running"] and ready["input_enabled"]
			and int(ready["camera_resets"]) == 1
			and float(ready["countdown"]) <= 0.0)

	game.queue_free()


func _test_initial_countdown_lifecycle() -> void:
	var game := RunnerGameFixture.new()
	add_child(game)
	game.set_process(false)
	game.track = TrackProbe.new()
	game.add_child(game.track)
	game.track.process_mode = Node.PROCESS_MODE_DISABLED
	game.player = RunnerPlayer.new()
	game.add_child(game.player)
	game.player.set_input_enabled(false)
	game.missions = MissionProbe.new()
	var saved_busy := SceneRouter._busy
	var saved_presenting := SceneRouter._presenting
	SceneRouter._busy = false
	SceneRouter._presenting = true
	game.build_finished = true
	game.step_process(RunnerGame.COUNTDOWN_TIME)
	_check("covered_start_has_no_countdown_lifecycle", game.lifecycle_rows.is_empty())
	SceneRouter._presenting = false
	game.build_finished = false
	game.step_process(RunnerGame.COUNTDOWN_TIME)
	_check("unfinished_start_has_no_countdown_lifecycle", game.lifecycle_rows.is_empty())
	game.build_finished = true
	game.step_process(RunnerGame.COUNTDOWN_TIME)
	_check("initial_release_emits_only_countdown_ready",
		_lifecycle_names(game) == ["runner_countdown_ready"])
	if game.lifecycle_rows.size() == 1:
		var ready: Dictionary = game.lifecycle_rows[0]
		_check("initial_ready_observes_released_presentation", ready["fields"].get("retry") == false
			and ready["presentation_started"] and not ready["running"]
			and not ready["input_enabled"]
			and int(ready["track_processing"]) == Node.PROCESS_MODE_INHERIT
			and is_equal_approx(float(ready["countdown"]), RunnerGame.COUNTDOWN_TIME))
	game.step_process(RunnerGame.COUNTDOWN_TIME * 0.5)
	_check("partial_countdown_emits_no_running_event",
		_lifecycle_names(game) == ["runner_countdown_ready"])
	game.step_process(RunnerGame.COUNTDOWN_TIME * 0.5)
	_check("running_follows_visible_countdown", _lifecycle_names(game) == [
		"runner_countdown_ready", "runner_running"])
	if game.lifecycle_rows.size() == 2:
		var running_row: Dictionary = game.lifecycle_rows[1]
		_check("running_event_observes_active_input", running_row["running"]
			and not running_row["dead"] and running_row["input_enabled"]
			and float(running_row["countdown"]) <= 0.0)
	# Exercise the real running feed before any completion signal. A static
	# initial mission card must not remain at zero while distance increases.
	game.hud = RunnerHUD.new()
	game.add_child(game.hud)
	game.hud.setup()
	game.hud.set_missions(game.missions.rows())
	game.chaser = RunnerChaser.new()
	game.add_child(game.chaser)
	game.step_process(0.25)
	_check("running_mission_count_follows_distance_before_completion",
		game.player.distance > 1.0 and game.hud._mission_pcts[0].text == "%d / 700" % int(game.player.distance))
	game.step_process(0.25)
	game.hud._tick_missions(0.25)
	_check("running_mission_bar_updates_before_completion",
		game.hud._mission_bars[0].value > 0.0
		and is_equal_approx(game.hud._mission_target[0], game.player.distance / 700.0))
	SceneRouter._busy = saved_busy
	SceneRouter._presenting = saved_presenting
	game.queue_free()


func _lifecycle_names(game: RunnerGameFixture) -> Array[String]:
	var names: Array[String] = []
	for row: Dictionary in game.lifecycle_rows:
		names.append(String(row["name"]))
	return names


func _all_life_pips_use(hud: RunnerHUD, expected: StyleBox) -> bool:
	for pip: Panel in hud._life_pips:
		if pip.get_theme_stylebox("panel") != expected:
			return false
	return true


func _any_powerup_active_or_visible(hud: RunnerHUD) -> bool:
	for i: int in hud._powerup_on.size():
		if hud._powerup_on[i] or hud._powerup_slots[i].visible:
			return true
	return false


func _check(label: String, ok: bool) -> void:
	if ok:
		_passes += 1
		print("[runner_retry_hud] PASS %s" % label)
		return
	_failures += 1
	print("[runner_retry_hud] FAIL %s" % label)
