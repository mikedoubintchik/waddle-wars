extends Node
## Deterministic, headless loader recovery regression. Draw signals are emitted
## explicitly; this proves state/ordering, not displayed pixels or GPU timing.
## Main test harness supplies the copied project and isolated user://.

class PendingCourse:
	extends CourseBase

	func _ready() -> void:
		pass


class InertRunner:
	extends RunnerGame

	func _ready() -> void:
		# Exercise the real pause callbacks and exit cleanup without building a
		# runner world. These callbacks still consult the actual autoload router.
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_process(false)
		set_physics_process(false)
		set_process_unhandled_input(false)


class RouterProbe:
	extends "res://scripts/utilities/scene_router.gd"

	var clock_msec: int = 1000
	var requested_paths: Array[String] = []
	var immediate_paths: Array[String] = []
	var record_requests_only: bool = true
	var course: PendingCourse
	var recovery_ui: VBoxContainer
	var retry_ui: Button
	var back_ui: Button
	var lifecycle_rows: Array[Dictionary] = []

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		# This fixture replaces production UI setup, not scheduler authority.
		process_priority = SceneRouter.process_priority
		set_process(false)
		_fade_rect = ColorRect.new()
		_fade_rect.color = Color(0.03, 0.06, 0.12, 1.0)
		_fade_rect.modulate.a = 1.0
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(_fade_rect)
		_loading_card = PanelContainer.new()
		_fade_rect.add_child(_loading_card)
		_loading_box = VBoxContainer.new()
		_loading_card.add_child(_loading_box)
		_loading_label = Label.new()
		_loading_box.add_child(_loading_label)
		_loading_progress = ProgressBar.new()
		_loading_progress.max_value = 1.0
		_loading_box.add_child(_loading_progress)
		recovery_ui = VBoxContainer.new()
		recovery_ui.visible = false
		_loading_box.add_child(recovery_ui)
		retry_ui = Button.new()
		back_ui = Button.new()
		recovery_ui.add_child(retry_ui)
		recovery_ui.add_child(back_ui)
		# Dynamic assignment keeps this fixture parseable against the pre-fix
		# router. Missing recovery contract is an assertion failure, never a skip.
		_set_if_present(&"_loading_recovery", recovery_ui)
		_set_if_present(&"_retry_button", retry_ui)
		_set_if_present(&"_back_button", back_ui)
		course = PendingCourse.new()
		add_child(course)

	func _set_if_present(property: StringName, value: Variant) -> void:
		for info: Dictionary in get_property_list():
			if StringName(info["name"]) == property:
				set(property, value)
				return

	func _now_msec() -> int:
		return clock_msec

	func _ensure_loading_presentation() -> void:
		pass

	func _request_threaded_load(scene_path: String) -> void:
		if record_requests_only:
			requested_paths.append(scene_path)
		else:
			super._request_threaded_load(scene_path)

	func _change_now(scene_path: String) -> void:
		# Only the backend is stopped: queued redirects still exercise go_to's
		# real serial/guard logic without replacing the test's current scene.
		immediate_paths.append(scene_path)

	func _emit_lifecycle(event_name: String, fields: Dictionary = {}) -> void:
		lifecycle_rows.append({
			"name": event_name,
			"fields": fields.duplicate(true),
			"busy": _busy,
			"presenting": _presenting,
			"path": _active_scene_path,
			"serial": _transition_serial,
			"paused": get_tree().paused,
			"holds_pause": _holds_tree_pause,
			"overlay_visible": _fade_rect.visible,
			"overlay_alpha": _fade_rect.modulate.a,
			"mouse_filter": _fade_rect.mouse_filter,
			"loading_visible": _loading_box.visible,
			"deadline": _loading_deadline_msec,
			"backend_requests": requested_paths.size() + immediate_paths.size(),
		})


class WarmupOrderProbe:
	extends Node
	## A cheap submission callback at the real helpers' priority. Helper fixtures
	## separately exercise their actual queue and draw guards; no GPU claim here.

	var suspended: bool = false
	var process_ticks: int = 0
	var submissions: int = 0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = -100

	func suspend_for_recovery() -> void:
		suspended = true

	func _process(_delta: float) -> void:
		process_ticks += 1
		if not suspended:
			submissions += 1


class JobProbe:
	extends RouterProbe

	var statuses: Dictionary = {}
	var result_paths: Array[String] = []
	var swapped_paths: Array[String] = []
	var backend_events: Array[String] = []
	var unsafe_result_calls: int = 0

	func _ready() -> void:
		super._ready()
		record_requests_only = false

	func _threaded_load_status(scene_path: String, progress: Array = []) -> int:
		progress.clear()
		progress.append(0.5)
		return int(statuses.get(scene_path, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE))

	func _threaded_load_request(scene_path: String) -> Error:
		backend_events.append("request:" + scene_path)
		requested_paths.append(scene_path)
		statuses[scene_path] = ResourceLoader.THREAD_LOAD_IN_PROGRESS
		return OK

	func _threaded_load_result(scene_path: String) -> PackedScene:
		backend_events.append("result:" + scene_path)
		result_paths.append(scene_path)
		var status := int(statuses.get(scene_path, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE))
		if status != ResourceLoader.THREAD_LOAD_LOADED and status != ResourceLoader.THREAD_LOAD_FAILED:
			# Never call a real potentially blocking get() in this test. Record
			# attempted misuse as an assertion failure rather than hanging RED.
			unsafe_result_calls += 1
			return null
		statuses.erase(scene_path)
		# Godot retains a user token for FAILED jobs too. Reading its null
		# result releases that token; only then may the same path be re-requested.
		if status == ResourceLoader.THREAD_LOAD_FAILED:
			return null
		var node := Node.new()
		var packed := PackedScene.new()
		packed.pack(node)
		node.free()
		return packed

	func _change_to_packed(_packed: PackedScene, scene_path: String) -> void:
		# Common request/poll/drain bookkeeping is real; only destructive scene
		# replacement is stopped so the current test scene survives the check.
		swapped_paths.append(scene_path)

	func _change_now(scene_path: String) -> void:
		backend_events.append("fallback:" + scene_path)
		super._change_now(scene_path)


var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	var context := _game_context()
	var saved_paused := get_tree().paused
	var probe := _new_probe()
	var contract := true
	for method: StringName in [&"_start_loading_deadline", &"_poll_loading_watchdog",
		&"_show_loading_recovery", &"_retry_loading", &"_back_to_menu", &"_restart_under_cover",
		&"_threaded_load_status", &"_threaded_load_request", &"_threaded_load_result",
		&"is_loading_recovery_active"]:
		var exists := probe.has_method(method)
		_check("required_recovery_method_" + str(method), exists)
		contract = contract and exists
	var has_recovery_signal := probe.has_signal("loading_recovery_started")
	_check("required_loading_recovery_started_signal", has_recovery_signal)
	contract = contract and has_recovery_signal
	_dispose(probe)
	_test_route_lifecycle_acceptance()
	await _test_draws_do_not_replace_deadline()
	await _test_clear_draw_boundary()
	if contract:
		_test_recovery_signal_boundary()
		await _test_watchdog_precedes_warmup_submission()
		await _test_no_draw_deadline()
		_test_completed_work_extends_watchdog()
		await _test_request_deadline_without_manual_arm()
		await _test_inflight_job_retry()
		await _test_late_abandoned_job()
		await _test_terminal_failed_jobs()
		await _test_ready_fade()
		await _test_retry_and_back_context()
		await _test_stale_draw_await(false)
		await _test_stale_draw_await(true)
		await _test_stale_request_await()
		await _test_stale_fade_tween()
		await _test_removed_router()
		await _test_null_scene()
		await _test_queued_redirect()
		await _test_queued_redirect_during_final_await()
		_test_loader_pause_ownership()
	else:
		# The independent draw/deadline case still demonstrates the failure.
		# Do not call absent methods and turn useful RED into a script exception.
		_check("recovery_cases_require_missing_contract_not_a_headless_pass", false)
	for key: String in context:
		Game.set(key, context[key])
	get_tree().paused = saved_paused
	await get_tree().process_frame
	print("[scene_router_recovery] DONE: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _new_probe() -> RouterProbe:
	var probe := RouterProbe.new()
	add_child(probe)
	# Real post-swap preconditions; no ResourceLoader request is pending.
	probe._busy = false
	probe._presenting = true
	probe._set_if_present(&"_active_scene_path", Game.SCENE_RUNNER)
	return probe


func _new_job_probe() -> JobProbe:
	var probe := JobProbe.new()
	add_child(probe)
	probe._busy = false
	probe._presenting = true
	probe._set_if_present(&"_active_scene_path", Game.SCENE_RUNNER)
	return probe


func _dispose(probe: RouterProbe) -> void:
	if is_instance_valid(probe):
		probe.free()


func _draws(count: int) -> void:
	for _index: int in count:
		RenderingServer.frame_post_draw.emit()


func _covered(probe: RouterProbe) -> bool:
	return probe.is_busy() and probe.is_presenting() and probe._fade_rect.visible \
		and is_equal_approx(probe._fade_rect.modulate.a, 1.0) \
		and probe._fade_rect.mouse_filter == Control.MOUSE_FILTER_STOP


func _recovering(probe: RouterProbe) -> bool:
	return probe.get("_recovery_active") == true


func _test_completed_work_extends_watchdog() -> void:
	var probe := _new_probe()
	probe._busy = true
	probe._start_loading_deadline()
	var first_deadline := probe._loading_deadline_msec
	probe.clock_msec = first_deadline - 1000
	probe._note_loading_work("shader:4/128")
	var advanced_deadline := probe._loading_deadline_msec
	_check("completed_work_extends_inactivity_deadline",
		advanced_deadline == probe.clock_msec + SceneRouter.WARMUP_TIMEOUT_MSEC
		and advanced_deadline > first_deadline)
	probe._note_loading_work("shader:4/128")
	_check("unchanged_work_does_not_extend_deadline",
		probe._loading_deadline_msec == advanced_deadline)
	probe.clock_msec = first_deadline
	probe._poll_loading_watchdog()
	_check("old_wall_deadline_does_not_abort_advancing_work", not _recovering(probe))
	probe.clock_msec = advanced_deadline
	probe._poll_loading_watchdog()
	_check("stalled_work_still_recovers", _recovering(probe))
	_dispose(probe)


func _test_recovery_signal_boundary() -> void:
	var probe := _new_probe()
	var rows: Array[Dictionary] = []
	probe.loading_recovery_started.connect(func() -> void:
		rows.append({"active": probe.is_loading_recovery_active(), "busy": probe._busy,
			"presenting": probe._presenting, "serial": probe._transition_serial,
			"deadline": probe._loading_deadline_msec}))
	_check("recovery_getter_false_before_deadline", not probe.is_loading_recovery_active())
	probe._busy = true
	probe._start_loading_deadline()
	var serial := probe._transition_serial
	probe.clock_msec = probe._loading_deadline_msec
	probe._process(0.0)
	_check("deadline_emits_exactly_one_recovery_signal", rows.size() == 1)
	if rows.size() == 1:
		var row: Dictionary = rows[0]
		_check("recovery_signal_observes_latched_flags_and_invalidated_epoch",
			row["active"] and not row["busy"] and row["presenting"]
			and int(row["serial"]) == serial + 1 and int(row["deadline"]) == -1)
	probe._process(0.0)
	probe._show_loading_recovery("Duplicate recovery request")
	probe._show_loading_recovery("Another duplicate recovery request")
	_check("duplicate_polls_and_requests_do_not_reemit_recovery", rows.size() == 1
		and probe.is_loading_recovery_active())
	probe._reset_loading_recovery()
	_check("retry_style_reset_clears_getter_without_recovery_signal",
		not probe.is_loading_recovery_active() and rows.size() == 1)
	probe._show_loading_recovery("Second recovery attempt")
	probe._show_loading_recovery("Duplicate second attempt")
	_check("distinct_attempt_emits_one_new_recovery_signal", rows.size() == 2
		and probe.is_loading_recovery_active())
	_dispose(probe)


func _test_watchdog_precedes_warmup_submission() -> void:
	var probe := _new_probe()
	var initial := WarmupOrderProbe.new()
	var shader := WarmupOrderProbe.new()
	add_child(initial)
	add_child(shader)
	probe.loading_recovery_started.connect(initial.suspend_for_recovery)
	probe.loading_recovery_started.connect(shader.suspend_for_recovery)
	_check("production_watchdog_priority_precedes_both_minus100_helpers",
		SceneRouter.process_priority == -200 and probe.process_priority == -200
		and initial.process_priority == -100 and shader.process_priority == -100
		and probe.process_priority < initial.process_priority
		and probe.process_priority < shader.process_priority)
	probe._start_loading_deadline()
	probe.clock_msec = probe._loading_deadline_msec
	probe.set_process(true)
	# process_frame precedes node processing. The next signal guarantees at
	# least one real scheduler pass; no manual call imposes the desired order.
	await get_tree().process_frame
	await get_tree().process_frame
	probe.set_process(false)
	initial.set_process(false)
	shader.set_process(false)
	_check("real_scheduler_latches_recovery_before_new_helper_submissions",
		probe.is_loading_recovery_active() and initial.suspended and shader.suspended
		and initial.process_ticks > 0 and shader.process_ticks > 0
		and initial.submissions == 0 and shader.submissions == 0)
	initial.free()
	shader.free()
	_dispose(probe)


func _test_route_lifecycle_acceptance() -> void:
	var probe := _new_probe()
	probe._presenting = false
	probe.go_to(Game.SCENE_RUNNER)
	_check("accepted_route_emits_one_loading_start",
		_lifecycle_names(probe) == ["loading_started"])
	if probe.lifecycle_rows.size() == 1:
		var started: Dictionary = probe.lifecycle_rows[0]
		var fields: Dictionary = started["fields"]
		_check("accepted_route_event_follows_identity_and_guard",
			started["busy"] and started["path"] == Game.SCENE_RUNNER
			and int(started["serial"]) == 1
			and fields.get("path") == Game.SCENE_RUNNER
			and int(fields.get("serial", -1)) == int(started["serial"])
			and fields.get("route") == "go_to"
			and int(started["backend_requests"]) == 0)
	probe.go_to(Game.SCENE_MAIN_MENU)
	_check("busy_route_emits_no_duplicate_loading_start",
		_lifecycle_names(probe) == ["loading_started"])
	_dispose(probe)
	probe = _new_probe()
	probe.go_to(Game.SCENE_MAIN_MENU)
	probe.go_to(Game.SCENE_TITLE)
	_check("queued_route_waits_for_actual_start_before_emitting",
		probe.lifecycle_rows.is_empty() and probe._queued_scene_path == Game.SCENE_MAIN_MENU)
	_dispose(probe)


func _lifecycle_names(probe: RouterProbe) -> Array[String]:
	var names: Array[String] = []
	for row: Dictionary in probe.lifecycle_rows:
		names.append(String(row["name"]))
	return names


func _test_draws_do_not_replace_deadline() -> void:
	var probe := _new_probe()
	probe._fade_out_when_scene_drawn()
	var deadline := int(probe.get("_loading_deadline_msec"))
	_draws(302)
	_check("302_draw_callbacks_keep_pending_world_covered", _covered(probe))
	_draws(1)
	_check("303rd_draw_is_not_a_wall_deadline", not _recovering(probe) and _covered(probe))
	_draws(700)
	_check("over_1000_draws_keep_original_deadline_without_recovery",
		not _recovering(probe) and _covered(probe)
		and int(probe.get("_loading_deadline_msec")) == deadline)
	probe.clock_msec = deadline - 1
	probe._process(0.0)
	_check("many_draws_cannot_advance_wall_deadline", not _recovering(probe) and _covered(probe))
	probe.clock_msec = deadline
	probe._process(0.0)
	_check("unchanged_wall_deadline_latches_recovery_after_many_draws", _recovering(probe))
	_check("recovery_pauses_underlying_gameplay", get_tree().paused)
	_check("expired_wall_deadline_never_marks_world_ready",
		probe._loading_label.text != "Expedition ready" and _covered(probe))
	_check("recovery_has_visible_enabled_actions", probe.recovery_ui.visible \
		and not probe.retry_ui.disabled and not probe.back_ui.disabled)
	probe.course.build_finished = true
	_draws(2)
	await get_tree().process_frame
	_check("late_completion_after_wall_timeout_cannot_dismiss",
		_recovering(probe) and _covered(probe))
	_dispose(probe)


func _test_clear_draw_boundary() -> void:
	var probe := _new_probe()
	probe.course.build_finished = true
	probe._holds_tree_pause = true
	get_tree().paused = true
	probe._finish_presentation()
	_check("ready_dismissal_hides_overlay_but_keeps_gate",
		probe.is_presenting() and not probe._fade_rect.visible and not probe._loading_box.visible)
	_draws(1)
	_check("cleared_draw_alone_never_releases_gameplay", probe.is_presenting())
	_check("clear_draw_alone_emits_no_loading_finished", probe.lifecycle_rows.is_empty())
	await get_tree().process_frame
	_check("following_process_frame_releases_ready_gameplay",
		not probe.is_busy() and not probe.is_presenting() \
		and probe._fade_rect.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	_check("released_presentation_emits_one_loading_finished",
		_lifecycle_names(probe) == ["loading_finished"])
	if probe.lifecycle_rows.size() == 1:
		var finished: Dictionary = probe.lifecycle_rows[0]
		var fields: Dictionary = finished["fields"]
		_check("loading_finished_observes_released_gate_and_pause",
			not finished["busy"] and not finished["presenting"]
			and not finished["paused"] and not finished["holds_pause"]
			and not finished["overlay_visible"] and not finished["loading_visible"]
			and int(finished["mouse_filter"]) == Control.MOUSE_FILTER_IGNORE
			and int(finished["deadline"]) == -1
			and fields.get("path") == Game.SCENE_RUNNER
			and int(fields.get("serial", -1)) == int(finished["serial"]))
	probe._finish_presentation()
	_check("finished_presentation_emits_no_duplicate_finish",
		_lifecycle_names(probe) == ["loading_finished"])
	_dispose(probe)


func _test_no_draw_deadline() -> void:
	var probe := _new_probe()
	probe._fade_out_when_scene_drawn()
	var deadline := int(probe.get("_loading_deadline_msec"))
	_check("deadline_uses_injected_monotonic_clock", deadline == probe.clock_msec + 30000)
	probe.clock_msec = deadline - 1
	probe._process(0.0)
	_check("no_draw_deadline_not_early", not _recovering(probe) and _covered(probe))
	probe.clock_msec = deadline
	probe._process(0.0)
	_check("process_watchdog_triggers_at_deadline_without_any_draw", _recovering(probe) and _covered(probe))
	var serial := int(probe.get("_transition_serial"))
	probe._process(0.0)
	_check("repeated_deadline_poll_is_idempotent", int(probe.get("_transition_serial")) == serial)
	probe.course.build_finished = true
	_draws(4)
	await get_tree().process_frame
	_check("stale_initial_draw_wait_cannot_finish_after_wall_timeout", _recovering(probe) and _covered(probe))
	_dispose(probe)


func _test_ready_fade() -> void:
	var probe := _new_probe()
	probe.course.build_finished = true
	probe._fade_out_when_scene_drawn()
	_draws(3)
	var tween := probe.get("_transition_tween") as Tween
	_check("ready_world_creates_real_fade_tween", tween != null and tween.is_valid())
	if tween != null and tween.is_valid():
		tween.custom_step(1.0)
	_check("completed_fade_waits_for_clear_draw", probe.is_presenting() and not probe._fade_rect.visible)
	_draws(1)
	_check("actual_fade_completion_still_waits_for_next_process", probe.is_presenting())
	await get_tree().process_frame
	_check("actual_ready_fade_releases_and_disarms_watchdog",
		not probe.is_busy() and int(probe.get("_loading_deadline_msec")) == -1)
	_dispose(probe)


func _test_request_deadline_without_manual_arm() -> void:
	var probe := _new_probe()
	# Enter the real covered replacement path. Do not call the clock/deadline
	# helper: production must arm it before the first submitted loader draw.
	probe.call("_restart_under_cover", Game.SCENE_RUNNER)
	var deadline := int(probe.get("_loading_deadline_msec"))
	_check("covered_route_emits_one_loading_start",
		_lifecycle_names(probe) == ["loading_started"])
	if probe.lifecycle_rows.size() == 1:
		var started: Dictionary = probe.lifecycle_rows[0]
		var fields: Dictionary = started["fields"]
		_check("covered_start_observes_complete_cover_before_backend",
			started["busy"] and started["presenting"] and started["paused"]
			and started["holds_pause"] and started["overlay_visible"]
			and started["loading_visible"] and is_equal_approx(float(started["overlay_alpha"]), 1.0)
			and int(started["mouse_filter"]) == Control.MOUSE_FILTER_STOP
			and int(started["deadline"]) == probe.clock_msec + 30000
			and int(started["backend_requests"]) == 0
			and started["path"] == Game.SCENE_RUNNER
			and fields.get("path") == Game.SCENE_RUNNER
			and fields.get("route") == "under_cover"
			and int(fields.get("serial", -1)) == int(started["serial"]))
	_check("covered_request_arms_deadline_before_any_draw", deadline == probe.clock_msec + 30000)
	_check("covered_request_does_not_enter_backend_before_loader_draw", probe.requested_paths.is_empty())
	probe.clock_msec += 29999
	probe._process(0.0)
	_check("predraw_request_deadline_not_early", not _recovering(probe) and _covered(probe))
	probe.clock_msec += 1
	probe._process(0.0)
	_check("predraw_request_deadline_fails_closed_without_manual_arm", _recovering(probe) and _covered(probe))
	_draws(1)
	await get_tree().process_frame
	_check("timed_out_predraw_request_cannot_dispatch_later", probe.requested_paths.is_empty() and _recovering(probe))
	_dispose(probe)


func _test_retry_and_back_context() -> void:
	Game.mode = Game.Mode.QUICK_RACE
	Game.course_id = "sapphire"
	Game.difficulty_id = "competitive"
	Game.daily_active = true
	Game.daily_result = {"fixture": true}
	var before := _game_context()
	var probe := _new_probe()
	probe.call("_show_loading_recovery", "Fixture recovery")
	probe.call("_retry_loading")
	probe.call("_retry_loading")
	probe.call("_back_to_menu")
	_check("retry_preserves_daily_and_all_game_context", _game_context() == before)
	_check("retry_immediately_reholds_loader_and_closes_actions",
		_covered(probe) and not _recovering(probe) and not probe.recovery_ui.visible \
		and get_tree().paused)
	_draws(1)
	await get_tree().process_frame
	_check("double_retry_and_back_dispatch_only_once", probe.requested_paths == [Game.SCENE_RUNNER])
	_dispose(probe)
	probe = _new_probe()
	probe.call("_show_loading_recovery", "Fixture recovery")
	probe.call("_back_to_menu")
	probe.call("_back_to_menu")
	probe.call("_retry_loading")
	_draws(1)
	await get_tree().process_frame
	_check("daily_back_clears_daily_flag_and_routes_menu_once",
		not Game.daily_active and probe.requested_paths == [Game.SCENE_MAIN_MENU] \
		and _covered(probe) and get_tree().paused)
	before["daily_active"] = false
	_check("daily_back_preserves_other_context", _game_context() == before)
	_dispose(probe)
	Game.mode = Game.Mode.GRAND_PRIX
	Game.gp_round = 1
	Game.gp_points = {"player": 10, "gus": 8}
	Game.gp_times = {"player": 42.5, "gus": 43.0}
	Game.gp_cup_complete = false
	Game.gp_cup_place = 2
	Game.daily_active = true
	before = _game_context()
	probe = _new_probe()
	probe._set_if_present(&"_active_scene_path", Game.SCENE_RACE)
	probe.call("_show_loading_recovery", "Fixture GP retry")
	probe.call("_retry_loading")
	probe.call("_retry_loading")
	_draws(1)
	await get_tree().process_frame
	_check("gp_retry_preserves_round_points_times_rewards_and_daily_context", _game_context() == before)
	_check("gp_retry_dispatches_current_race_exactly_once_under_cover",
		probe.requested_paths == [Game.SCENE_RACE] and _covered(probe))
	_dispose(probe)
	probe = _new_probe()
	probe._set_if_present(&"_active_scene_path", Game.SCENE_RACE)
	probe.call("_show_loading_recovery", "Fixture recovery")
	probe.call("_back_to_menu")
	_check("gp_first_back_requires_confirmation_without_mutation",
		probe.get("_recovery_back_armed") == true and _game_context() == before \
		and probe.requested_paths.is_empty() and probe.back_ui.text == "Confirm Back" \
		and get_tree().paused)
	probe.call("_back_to_menu")
	probe.call("_back_to_menu")
	probe.call("_retry_loading")
	_draws(1)
	await get_tree().process_frame
	before["daily_active"] = false
	_check("confirmed_gp_back_matches_existing_quit_context_semantics", _game_context() == before)
	_check("confirmed_gp_back_dispatches_once_without_uncovering", probe.requested_paths == [Game.SCENE_MAIN_MENU] and _covered(probe))
	_dispose(probe)
	Game.mode = Game.Mode.QUICK_RACE


func _test_inflight_job_retry() -> void:
	var probe := _new_job_probe()
	probe.call("_restart_under_cover", Game.SCENE_RUNNER)
	_draws(1)
	await get_tree().process_frame
	_check("real_request_bookkeeping_starts_one_job", probe.requested_paths == [Game.SCENE_RUNNER] \
		and probe._pending_scene_path == Game.SCENE_RUNNER)
	var deadline := int(probe.get("_loading_deadline_msec"))
	_check("inflight_job_retains_production_armed_deadline", deadline == probe.clock_msec + 30000)
	probe.clock_msec = deadline
	probe._process(0.0)
	_check("inflight_timeout_is_covered_paused_recovery", _recovering(probe) \
		and _covered(probe) and get_tree().paused)
	_check("inflight_timeout_never_blocks_on_resource_result",
		probe.result_paths.is_empty() and probe.unsafe_result_calls == 0)
	probe.call("_retry_loading")
	probe.call("_retry_loading")
	_draws(1)
	await get_tree().process_frame
	_check("retry_reuses_inflight_path_without_second_request",
		probe.requested_paths == [Game.SCENE_RUNNER] and probe._pending_scene_path == Game.SCENE_RUNNER \
		and probe.result_paths.is_empty())
	_check("retry_rearms_deadline_from_current_monotonic_time",
		int(probe.get("_loading_deadline_msec")) == probe.clock_msec + 30000)
	probe._process(0.0)
	_check("expired_previous_deadline_cannot_recover_new_attempt",
		not _recovering(probe) and _covered(probe) and get_tree().paused)
	probe.statuses[Game.SCENE_RUNNER] = ResourceLoader.THREAD_LOAD_LOADED
	probe._process(0.0)
	probe._process(0.0)
	_check("reused_job_resolves_and_dispatches_exactly_once",
		probe.result_paths == [Game.SCENE_RUNNER] and probe.swapped_paths == [Game.SCENE_RUNNER] \
		and probe.requested_paths == [Game.SCENE_RUNNER] and probe.unsafe_result_calls == 0)
	_dispose(probe)
	_check("router_exit_releases_its_owned_recovery_pause", not get_tree().paused)


func _test_late_abandoned_job() -> void:
	Game.mode = Game.Mode.QUICK_RACE
	var probe := _new_job_probe()
	probe.call("_restart_under_cover", Game.SCENE_RUNNER)
	_draws(1)
	await get_tree().process_frame
	probe.clock_msec = int(probe.get("_loading_deadline_msec"))
	probe._process(0.0)
	probe.call("_back_to_menu")
	probe.call("_back_to_menu")
	_draws(1)
	await get_tree().process_frame
	_check("back_starts_only_one_replacement_job",
		probe.requested_paths == [Game.SCENE_RUNNER, Game.SCENE_MAIN_MENU])
	probe.statuses[Game.SCENE_RUNNER] = ResourceLoader.THREAD_LOAD_LOADED
	probe._process(0.0)
	_check("late_abandoned_result_drains_without_instantiating_old_scene",
		probe.result_paths == [Game.SCENE_RUNNER] and probe.swapped_paths.is_empty() \
		and probe._pending_scene_path == Game.SCENE_MAIN_MENU \
		and probe.get("_active_scene_path") == Game.SCENE_MAIN_MENU)
	_check("old_completion_cannot_release_replacement_guard",
		_covered(probe) and get_tree().paused and not _recovering(probe))
	probe.statuses[Game.SCENE_MAIN_MENU] = ResourceLoader.THREAD_LOAD_LOADED
	probe._process(0.0)
	probe._process(0.0)
	_check("only_current_replacement_scene_is_dispatched_once",
		probe.result_paths == [Game.SCENE_RUNNER, Game.SCENE_MAIN_MENU] \
		and probe.swapped_paths == [Game.SCENE_MAIN_MENU] and probe.unsafe_result_calls == 0)
	_dispose(probe)


func _test_terminal_failed_jobs() -> void:
	var path := Game.SCENE_RUNNER
	for release_path: String in ["drain", "retry", "active_poll"]:
		var probe := _new_job_probe()
		probe.call("_restart_under_cover", path)
		_draws(1)
		await get_tree().process_frame
		if release_path != "active_poll":
			probe.call("_show_loading_recovery", "Fixture abandons resource job")
		probe.statuses[path] = ResourceLoader.THREAD_LOAD_FAILED
		if release_path == "drain":
			probe._process(0.0)
			probe._process(0.0)
			_check("abandoned_failed_job_releases_token_exactly_once_without_scene_change",
				probe.result_paths == [path] and probe.swapped_paths.is_empty() \
				and probe.immediate_paths.is_empty() and not probe.statuses.has(path))
		if release_path == "active_poll":
			# Production emits its expected fallback warning. The engine scene
			# replacement itself remains intercepted, not claimed as verified.
			probe._process(0.0)
			probe._process(0.0)
			_check("active_failed_job_releases_token_before_fallback_exactly_once",
				probe.backend_events == ["request:" + path, "result:" + path, "fallback:" + path] \
				and probe.immediate_paths == [path] and probe.swapped_paths.is_empty())
		else:
			probe.call("_retry_loading")
			_draws(1)
			await get_tree().process_frame
			_check(release_path + "_failed_token_is_released_before_fresh_request",
				probe.backend_events == ["request:" + path, "result:" + path, "request:" + path] \
				and probe.requested_paths == [path, path] and probe.result_paths == [path] \
				and probe._pending_scene_path == path and probe.swapped_paths.is_empty())
		_check(release_path + "_failed_cleanup_never_gets_inprogress_or_invalid_job",
			probe.unsafe_result_calls == 0)
		_dispose(probe)
	var invalid := _new_job_probe()
	invalid.call("_restart_under_cover", path)
	_draws(1)
	await get_tree().process_frame
	invalid.call("_show_loading_recovery", "Fixture invalid resource job")
	invalid.statuses.erase(path)
	invalid._process(0.0)
	_check("invalid_abandoned_job_is_forgotten_without_result_get",
		invalid.result_paths.is_empty() and invalid.unsafe_result_calls == 0 \
		and invalid.swapped_paths.is_empty() and invalid.immediate_paths.is_empty())
	_dispose(invalid)


func _test_stale_draw_await(after_draw: bool) -> void:
	var probe := _new_probe()
	probe.course.build_finished = true
	probe._finish_presentation()
	if after_draw:
		_draws(1)
	probe.call("_show_loading_recovery", "Fixture replaces pending dismissal")
	probe.call("_retry_loading")
	var replacement_serial := int(probe.get("_transition_serial"))
	_draws(1)
	await get_tree().process_frame
	var label := "post_draw" if after_draw else "pre_draw"
	_check(label + "_stale_dismissal_cannot_release_replacement", _covered(probe) \
		and int(probe.get("_transition_serial")) == replacement_serial)
	_check(label + "_replacement_request_occurs_once", probe.requested_paths == [Game.SCENE_RUNNER])
	_dispose(probe)


func _test_stale_request_await() -> void:
	var probe := _new_probe()
	probe._busy = true
	probe._begin_threaded_load("res://tests/stale_destination.tscn")
	probe.call("_show_loading_recovery", "Fixture cancels pending request")
	probe.call("_retry_loading")
	_draws(1)
	await get_tree().process_frame
	_check("old_request_await_never_reaches_backend", probe.requested_paths == [Game.SCENE_RUNNER] and _covered(probe))
	_dispose(probe)


func _test_stale_fade_tween() -> void:
	var probe := _new_probe()
	probe.course.build_finished = true
	probe._fade_out_when_scene_drawn()
	_draws(3)
	var tween := probe.get("_transition_tween") as Tween
	var old_serial := int(probe.get("_transition_serial"))
	_check("stale_tween_fixture_has_real_active_fade", tween != null and tween.is_valid())
	probe.call("_show_loading_recovery", "Fixture interrupts fade")
	_check("recovery_kills_old_fade_tween", tween != null and not tween.is_valid())
	probe.call("_retry_loading")
	# Emulate a callback already queued before Tween.kill(). Epoch must reject
	# it even though the new transition itself is otherwise healthy.
	probe.call("_finish_presentation", old_serial)
	_draws(1)
	await get_tree().process_frame
	_check("stale_fade_callback_cannot_hide_or_release_retry", _covered(probe) \
		and probe.requested_paths == [Game.SCENE_RUNNER])
	_dispose(probe)


func _test_removed_router() -> void:
	var probe := _new_probe()
	probe._fade_out_when_scene_drawn()
	remove_child(probe)
	_draws(4)
	await get_tree().process_frame
	_check("removed_router_cannot_create_recovery_or_dispatch",
		probe.requested_paths.is_empty() and not _recovering(probe) \
		and probe.get("_transition_tween") == null)
	probe.free()
	probe = _new_probe()
	probe.course.build_finished = true
	probe._finish_presentation()
	_draws(1)
	remove_child(probe)
	await get_tree().process_frame
	_check("removed_router_cannot_release_after_cleared_draw", probe.is_presenting())
	probe.free()


func _test_null_scene() -> void:
	var probe := _new_probe()
	var original := get_tree().current_scene
	get_tree().current_scene = null
	_check("missing_scene_is_not_gameplay_ready", not probe.is_gameplay_ready(null))
	probe._fade_out_when_scene_drawn()
	_draws(303)
	_check("missing_scene_stays_covered_before_wall_deadline", not _recovering(probe) and _covered(probe))
	probe.clock_msec = int(probe.get("_loading_deadline_msec"))
	probe._process(0.0)
	_check("missing_scene_never_fades_to_empty_world", _recovering(probe) and _covered(probe))
	get_tree().current_scene = original
	_dispose(probe)


func _test_queued_redirect() -> void:
	var probe := _new_probe()
	probe._fade_out_when_scene_drawn()
	probe.go_to(Game.SCENE_MAIN_MENU)
	probe.go_to(Game.SCENE_TITLE)
	_check("queued_redirect_first_destination_wins", probe._queued_scene_path == Game.SCENE_MAIN_MENU)
	_draws(303)
	_check("queued_redirect_not_dispatched_by_draw_count", probe.requested_paths.is_empty()
		and probe._queued_scene_path == Game.SCENE_MAIN_MENU and _covered(probe))
	probe.clock_msec = int(probe.get("_loading_deadline_msec"))
	probe._process(0.0)
	_check("timed_out_rejected_world_starts_queued_route_under_cover",
		_covered(probe) and not _recovering(probe) and probe._queued_scene_path.is_empty())
	probe.call("_retry_loading")
	probe.call("_back_to_menu")
	_draws(1)
	await get_tree().process_frame
	_check("queued_redirect_and_double_actions_dispatch_only_first_route",
		probe.requested_paths == [Game.SCENE_MAIN_MENU] and _covered(probe))
	_dispose(probe)


func _test_queued_redirect_during_final_await() -> void:
	var probe := _new_probe()
	probe.course.build_finished = true
	probe._finish_presentation()
	_draws(1)
	probe.go_to(Game.SCENE_MAIN_MENU)
	probe.go_to(Game.SCENE_TITLE)
	await get_tree().process_frame
	_check("redirect_during_final_await_restarts_without_uncovering",
		_covered(probe) and probe.immediate_paths.is_empty() \
		and probe.requested_paths.is_empty() and probe._queued_scene_path.is_empty())
	_draws(1)
	_check("final_await_redirect_still_waits_after_replacement_draw", probe.requested_paths.is_empty() and _covered(probe))
	await get_tree().process_frame
	_check("final_await_redirect_requests_once_only_after_replacement_draw_and_process",
		probe.requested_paths == [Game.SCENE_MAIN_MENU] and probe.immediate_paths.is_empty() and _covered(probe))
	_dispose(probe)


func _new_paused_menu() -> PauseMenu:
	var menu := PauseMenu.new()
	add_child(menu)
	menu._panel = Control.new()
	menu.add_child(menu._panel)
	menu._paused = true
	get_tree().paused = true
	return menu


func _new_paused_runner() -> InertRunner:
	var runner := InertRunner.new()
	add_child(runner)
	runner._presentation_started = true
	runner._pause_layer = CanvasLayer.new()
	runner.add_child(runner._pause_layer)
	get_tree().paused = true
	return runner


func _test_loader_pause_ownership() -> void:
	# No await here: even RED's erroneous quit can only queue a route, which is
	# restored before the real autoload can process it. No manager is mocked.
	var saved_busy := SceneRouter._busy
	var saved_presenting := SceneRouter._presenting
	var saved_queue := SceneRouter._queued_scene_path
	var saved_paused := get_tree().paused
	var saved_mode := Game.mode
	var saved_daily := Game.daily_active
	SceneRouter._busy = false
	SceneRouter._presenting = true
	SceneRouter._queued_scene_path = ""

	var menu := _new_paused_menu()
	_check("old_pause_menu_remains_always_processing", menu.process_mode == Node.PROCESS_MODE_ALWAYS)
	menu.toggle()
	_check("old_pause_toggle_cannot_release_presenting_router_pause",
		get_tree().paused and menu._paused and menu._panel != null)
	menu.free()
	menu = _new_paused_menu()
	menu._close()
	_check("old_pause_resume_callback_cannot_release_presenting_router_pause",
		get_tree().paused and menu._paused and menu._panel != null)
	menu.free()
	menu = _new_paused_menu()
	Game.mode = Game.Mode.QUICK_RACE
	Game.daily_active = true
	menu._on_quit_pressed()
	_check("old_pause_quit_cannot_resume_or_change_daily_or_queue_route",
		get_tree().paused and menu._paused and Game.daily_active \
		and SceneRouter._queued_scene_path.is_empty())
	# Reset all preconditions independently, including after a genuine RED.
	SceneRouter._queued_scene_path = ""
	menu._paused = true
	get_tree().paused = true
	menu.free()
	_check("old_pause_teardown_cannot_release_presenting_router_pause", get_tree().paused)

	var runner := _new_paused_runner()
	runner._close_pause()
	_check("old_runner_resume_callback_cannot_release_presenting_router_pause",
		get_tree().paused and runner._pause_layer != null)
	runner.free()
	runner = _new_paused_runner()
	runner._toggle_pause()
	_check("old_runner_pause_toggle_cannot_release_presenting_router_pause",
		get_tree().paused and runner._pause_layer != null)
	get_tree().paused = true
	runner.free()
	_check("old_runner_teardown_cannot_release_presenting_router_pause", get_tree().paused)

	# Do not solve ownership by disabling ordinary pause/resume or exit cleanup.
	SceneRouter._busy = false
	SceneRouter._presenting = false
	menu = _new_paused_menu()
	menu._close()
	_check("idle_router_allows_normal_pause_resume",
		not get_tree().paused and not menu._paused and menu._panel == null)
	menu.free()
	menu = _new_paused_menu()
	menu.free()
	_check("idle_router_allows_normal_pause_teardown_cleanup", not get_tree().paused)
	runner = _new_paused_runner()
	runner._close_pause()
	_check("idle_router_allows_normal_runner_resume",
		not get_tree().paused and runner._pause_layer == null)
	runner.free()
	runner = _new_paused_runner()
	runner._toggle_pause()
	_check("idle_router_allows_normal_runner_toggle_resume",
		not get_tree().paused and runner._pause_layer == null)
	runner.free()
	runner = _new_paused_runner()
	runner.free()
	_check("idle_router_allows_normal_runner_teardown_cleanup", not get_tree().paused)

	SceneRouter._busy = saved_busy
	SceneRouter._presenting = saved_presenting
	SceneRouter._queued_scene_path = saved_queue
	Game.mode = saved_mode
	Game.daily_active = saved_daily
	get_tree().paused = saved_paused


func _game_context() -> Dictionary:
	return {"mode": Game.mode, "course_id": Game.course_id, "difficulty_id": Game.difficulty_id,
		"daily_active": Game.daily_active, "daily_result": Game.daily_result.duplicate(true),
		"gp_round": Game.gp_round, "gp_points": Game.gp_points.duplicate(true),
		"gp_times": Game.gp_times.duplicate(true), "gp_cup_complete": Game.gp_cup_complete,
		"gp_cup_place": Game.gp_cup_place, "last_rewards": Game.last_rewards.duplicate(true),
		"last_race_results": Game.last_race_results.duplicate(true),
		"last_endless_result": Game.last_endless_result.duplicate(true)}


func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("[scene_router_recovery] PASS ", label)
	else:
		_failed += 1
		print("[scene_router_recovery] FAIL ", label)
