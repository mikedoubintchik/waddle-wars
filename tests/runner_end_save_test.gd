extends Node
## Focused contract for one durable, complete Waddle Run end-state write.
## Run only through the isolated test harness: this intentionally replaces the
## fixture's SaveManager data and reloads it from user://.

class RunnerGameFixture:
	extends RunnerGame

	var lifecycle_rows: Array[Dictionary] = []
	var save_count: Callable

	func _ready() -> void:
		pass

	func _process(_delta: float) -> void:
		pass

	func _emit_lifecycle(event_name: String, fields: Dictionary = {}) -> void:
		lifecycle_rows.append({
			"name": event_name,
			"fields": fields.duplicate(true),
			"dead": _dead,
			"running": running,
			"save_writes": int(save_count.call()) if save_count.is_valid() else -1,
			"save_dirty": SaveManager._dirty,
			"saved_state": SaveManager.data.duplicate(true),
			"results_shown": (hud as ProbeHud).show_count if hud is ProbeHud else 0,
		})


class ProbeHud:
	extends RunnerHUD

	var save_count: Callable
	var saves_when_shown: int = -1
	var show_count: int = 0
	var mission_refresh_count: int = 0
	var summary: Dictionary = {}

	func set_missions(_rows: Array) -> void:
		mission_refresh_count += 1

	func show_message(_text: String) -> void:
		pass

	func flash_hit() -> void:
		pass

	func show_game_over(value: Dictionary) -> void:
		show_count += 1
		summary = value.duplicate(true)
		saves_when_shown = int(save_count.call()) if save_count.is_valid() else -1


const RUN_DISTANCE: float = 432.5
const RUN_FISH: int = 7
const RUN_SCORE: int = 12345

var _passes: int = 0
var _failures: int = 0
var _save_writes: int = 0
var _fixture_nodes: Array[WeakRef] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var audio_idle := _audio_is_stopped()
	_check("fixture_starts_with_idle_audio", audio_idle)
	if not audio_idle:
		get_tree().quit(1)
		return
	# This fixture verifies save transactions, not sound playback. Keep the
	# real death/Progression calls intact but isolate their one-shot lookup so
	# a headless mixer cannot retain a playback at process exit. Real asset and
	# cache behavior is tested separately by runner_audio_warmup_test.gd.
	var library_before := AudioManager._library
	var cache_before := AudioManager._one_shot_cache
	var missing_before := AudioManager._missing_reported
	var pool_cursor_before := AudioManager._sfx_next
	var spatial_cursor_before := AudioManager._sfx_3d_next
	AudioManager._library = {}
	AudioManager._one_shot_cache = {}
	AudioManager._missing_reported = {}
	SaveManager.save_written.connect(_on_save_written)
	_test_orchestrated_end_state()
	_test_explicit_deferred_flush_scope()
	_test_standalone_default_flush()
	SaveManager.save_written.disconnect(_on_save_written)
	_check("save_fixture_does_not_start_audio", _audio_is_stopped()
		and AudioManager._sfx_next == pool_cursor_before
		and AudioManager._sfx_3d_next == spatial_cursor_before
		and AudioManager._one_shot_cache.is_empty())
	AudioManager._library = library_before
	AudioManager._one_shot_cache = cache_before
	AudioManager._missing_reported = missing_before
	_check("fixture_audio_state_restored", AudioManager._library == library_before
		and AudioManager._one_shot_cache == cache_before
		and AudioManager._missing_reported == missing_before)
	# Required queue_free barrier, not an arbitrary mixer timing delay.
	await get_tree().process_frame
	_check("queued_runner_fixture_nodes_freed", _fixture_nodes.size() == 3
		and _fixture_nodes.all(func(ref: WeakRef) -> bool: return ref.get_ref() == null))
	print("[runner_end_save] DONE: %d passed, %d failed" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_orchestrated_end_state() -> void:
	_reset_save()
	var missions := _clearable_missions()
	_persist_fixture(missions)

	var game := RunnerGameFixture.new()
	game.save_count = Callable(self, "_current_save_writes")
	add_child(game)
	game.set_process(false)
	var player := RunnerPlayer.new()
	player.distance = RUN_DISTANCE
	game.add_child(player)
	var hud := ProbeHud.new()
	hud.save_count = Callable(self, "_current_save_writes")
	game.add_child(hud)
	game.player = player
	game.hud = hud
	game.missions = missions
	_fixture_nodes.assign([weakref(game), weakref(player), weakref(hud)])
	game.fish = RUN_FISH
	game._score = float(RUN_SCORE)
	game.running = true
	player.set_input_enabled(true)
	player.hit_taken.connect(game._on_hit_taken)
	player.died.connect(game._on_death)

	player.powerups[RunnerConfig.POWERUP_SHIELD] = 5.0
	player.take_hit()
	_check("shield_does_not_spend_life", player.hits_left == 3 and game.hits_taken == 0
		and not player.has_powerup(RunnerConfig.POWERUP_SHIELD) and not game._dead)
	player.invulnerable_for = 0.0
	player.take_hit()
	_check("first_hit_survived", player.hits_left == 2 and not game._dead and _save_writes == 0)
	player.take_hit()
	_check("same_impact_iframe_cannot_spend_second_life", player.hits_left == 2 and game.hits_taken == 1)
	player.invulnerable_for = 0.0
	player.take_hit()
	_check("second_hit_survived", player.hits_left == 1 and not game._dead and _save_writes == 0)
	player.invulnerable_for = 0.0
	player.take_hit()
	_check("third_hit_starts_catch", player.hits_left == 0 and game.hits_taken == 3
		and player.state == RunnerPlayer.State.DEAD and not player._input_enabled
		and game._pending_results.has_all(["score", "distance", "fish", "best", "is_new_best", "missions", "mission_rows"])
		and is_zero_approx(game._catch_elapsed))
	_check("results_snapshot_uses_real_completed_goals", game._pending_results["missions"] == missions.completed_this_run()
		and not (game._pending_results["missions"] as PackedStringArray).is_empty()
		and not "SET COMPLETE" in " ".join(game._pending_results["missions"])
		and game._pending_results["mission_rows"] == missions.rows())
	_check("orchestrator_writes_once", _save_writes == 1,
		"writes=%d" % _save_writes)
	_check("catch_precedes_result_panel", hud.show_count == 0 and hud.saves_when_shown == -1,
		"shows=%d saves_at_show=%d" % [hud.show_count, hud.saves_when_shown])
	_check("missions_refresh_before_result", hud.mission_refresh_count == 1)
	_check("death_latched", game._dead and not game.running)
	_check("orchestrator_leaves_no_autosave_work", not SaveManager._dirty)
	_check_complete_end_state("orchestrator_memory", SaveManager.data)
	_check("no_results_lifecycle_during_catch", _lifecycle_names(game) == ["runner_death"])
	game._on_death()
	_check("repeat_death_during_catch_does_not_rebank", _save_writes == 1 and hud.show_count == 0)
	# Drive real presentation time explicitly. One long stalled frame must not
	# jump over all visible snow and expose results immediately.
	game._advance_catch(5.0)
	_check("stalled_frame_cannot_skip_catch", hud.show_count == 0
		and is_equal_approx(game._catch_elapsed, 0.05))
	for step: int in 10:
		game._advance_catch(0.05)
	_check("mid_catch_retains_world_and_frozen_result", hud.show_count == 0
		and is_equal_approx(player.distance, RUN_DISTANCE)
		and int(game._score) == RUN_SCORE and _save_writes == 1)
	for step: int in 13:
		game._advance_catch(0.05)
	_check("catch_remains_visible_beyond_old_one_second_end", hud.show_count == 0
		and game._catch_elapsed >= 1.19 and _save_writes == 1)
	while game._catch_elapsed < 2.29:
		game._advance_catch(0.05)
	_check("catch_gets_full_two_second_readable_interval", hud.show_count == 0
		and RunnerGame.CATCH_TIME >= 2.2 and RunnerGame.CATCH_TIME <= 2.6)
	for step: int in 3:
		game._advance_catch(0.05)
	_check("results_follow_complete_catch", hud.show_count == 1
		and hud.saves_when_shown == 1 and game._pending_results.is_empty()
		and is_equal_approx(game._catch_elapsed, RunnerGame.CATCH_TIME))
	_check("death_lifecycle_order", _lifecycle_names(game) == [
		"runner_death", "runner_results_ready"])
	if game.lifecycle_rows.size() == 2:
		var death: Dictionary = game.lifecycle_rows[0]
		var ready: Dictionary = game.lifecycle_rows[1]
		_check("death_event_observes_latched_state", death["dead"] and not death["running"]
			and int(death["save_writes"]) == 0)
		_check("results_event_follows_complete_save", ready["dead"] and not ready["running"]
			and int(ready["save_writes"]) == 1 and not ready["save_dirty"]
			and int(ready["results_shown"]) == 1)
		_check_complete_end_state("results_event_snapshot", ready["saved_state"])

	var fish_after := int(SaveManager.data.get("fish", -1))
	var stars_after := int(SaveManager.data.get(RunnerMissions.SAVE_KEY_STARS, -1))
	game._on_death()
	_check("repeat_death_no_second_save", _save_writes == 1,
		"writes=%d" % _save_writes)
	_check("repeat_death_no_second_award",
		int(SaveManager.data.get("fish", -1)) == fish_after
		and int(SaveManager.data.get(RunnerMissions.SAVE_KEY_STARS, -1)) == stars_after)
	_check("repeat_death_no_second_panel", hud.show_count == 1)
	_check("repeat_death_emits_no_duplicate_lifecycle", _lifecycle_names(game) == [
		"runner_death", "runner_results_ready"])

	SaveManager.data = {}
	SaveManager.load_save()
	_check_complete_end_state("orchestrator_disk", SaveManager.data)
	game.queue_free()


func _test_explicit_deferred_flush_scope() -> void:
	_reset_save()
	var missions := _clearable_missions()
	_persist_fixture(missions)
	missions.note_run_ended(1.0, 1, 0, false)
	_check("explicit_deferred_end_does_not_save", _save_writes == 0,
		"writes=%d" % _save_writes)
	_check("deferred_scope_restored", missions._flush_suppression_depth == 0)

	_force_clearable(missions, false)
	missions._persist()
	missions.note_distance(2.0)
	_check("later_ordinary_mission_clear_still_saves", _save_writes == 1,
		"writes=%d" % _save_writes)


func _test_standalone_default_flush() -> void:
	_reset_save()
	var missions := _clearable_missions()
	_persist_fixture(missions)
	missions.note_run_ended(1.0, 1, 0)
	_check("standalone_clear_flushes_once", _save_writes == 1,
		"writes=%d" % _save_writes)
	_check("standalone_clear_awards_once",
		int(SaveManager.data.get(RunnerMissions.SAVE_KEY_STARS, -1)) == 1
		and int(SaveManager.data.get("fish", -1)) == RunnerMissions.STAR_FISH
		and Progression.get_stat("runner_missions_done") == RunnerMissions.SET_SIZE)
	SaveManager.data = {}
	SaveManager.load_save()
	_check("standalone_clear_persisted",
		int(SaveManager.data.get(RunnerMissions.SAVE_KEY_STARS, -1)) == 1
		and int(SaveManager.data.get("fish", -1)) == RunnerMissions.STAR_FISH
		and Progression.get_stat("runner_missions_done") == RunnerMissions.SET_SIZE)


func _clearable_missions() -> RunnerMissions:
	var missions := RunnerMissions.new()
	missions.load_state()
	_force_clearable(missions, true)
	return missions


func _force_clearable(missions: RunnerMissions, reset_stars: bool) -> void:
	var distance_run_index := RunnerMissions._template_index("dist_run")
	for slot: int in RunnerMissions.SET_SIZE:
		missions._fill_slot(slot, distance_run_index, 0, "")
		missions._target[slot] = 1.0
		missions._progress[slot] = 0.0
		missions._done[slot] = 0
		missions._announced[slot] = 0
	if reset_stars:
		missions._stars = 0
	missions._pending = false
	missions._refresh_watch()


func _persist_fixture(missions: RunnerMissions) -> void:
	missions._persist()
	SaveManager.save_now()
	_save_writes = 0


func _reset_save() -> void:
	SaveManager.data = SaveManager.default_save()
	SaveManager.save_now()
	_save_writes = 0


func _check_complete_end_state(label: String, data: Dictionary) -> void:
	var stats: Dictionary = data.get("stats", {})
	var stored_missions: Variant = data.get(RunnerMissions.SAVE_KEY_SET, [])
	_check("%s_score" % label, int(data.get("runner_high_score", -1)) == RUN_SCORE)
	_check("%s_distance" % label,
		is_equal_approx(float(stats.get("runner_best_distance", -1.0)), RUN_DISTANCE))
	_check("%s_fish" % label,
		int(data.get("fish", -1)) == RunnerMissions.STAR_FISH + RUN_FISH)
	_check("%s_mission" % label,
		int(data.get(RunnerMissions.SAVE_KEY_STARS, -1)) == 1
		and stored_missions is Array
		and (stored_missions as Array).size() == RunnerMissions.SET_SIZE)
	_check("%s_stats" % label,
		int(stats.get("fish_total", -1)) == RunnerMissions.STAR_FISH + RUN_FISH
		and int(stats.get("runner_missions_done", -1)) == RunnerMissions.SET_SIZE)


func _on_save_written() -> void:
	_save_writes += 1


func _current_save_writes() -> int:
	return _save_writes


func _audio_is_stopped() -> bool:
	for child: Node in AudioManager.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).playing:
			return false
		if child is AudioStreamPlayer3D and (child as AudioStreamPlayer3D).playing:
			return false
	return true


func _lifecycle_names(game: RunnerGameFixture) -> Array[String]:
	var names: Array[String] = []
	for row: Dictionary in game.lifecycle_rows:
		names.append(String(row["name"]))
	return names


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("[runner_end_save] PASS %s" % label)
		return
	_failures += 1
	print("[runner_end_save] FAIL %s%s" % [
		label, ": %s" % detail if not detail.is_empty() else ""])
