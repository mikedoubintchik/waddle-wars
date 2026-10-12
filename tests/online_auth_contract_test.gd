extends Node
## No network. Execute through run_tests.sh's isolated project/user directory.

const MenuScript = preload("res://scripts/ui/main_menu.gd")
const BoardScript = preload("res://scripts/ui/leaderboard_menu.gd")

class OnlineFixture extends "res://scripts/network/leaderboard_client.gd":
	var requests: Array[Dictionary] = []
	func _ready() -> void:
		set_process(false)
		auth_changed.connect(_on_auth_changed_sync)
	func _dispatch_request(method: String, url: String, body: String, cb: Callable) -> void:
		requests.append({"method": method, "url": url, "body": body, "callback": cb})
	func _local_save_is_pristine() -> bool:
		return false

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	var online := OnlineFixture.new()
	add_child(online)
	var notifications: Array[int] = [0]
	online.auth_changed.connect(func() -> void: notifications[0] += 1)
	online._apply_web_auth_state({"signedIn": true, "token": "", "identityEpoch": 1})
	_check("initial_pending_identity_keeps_one_shot_signin_listener_waiting", notifications[0] == 0
		and online.requests.is_empty() and not online.signed_in)
	online._apply_web_auth_state(_state("account-a", "first"))
	_check("first_owner_starts_one_pull", online.requests.size() == 1
		and online.requests[0].method == "GET" and notifications[0] == 1)
	var first_generation := online._auth_generation
	var old_a: Callable = online.requests[0].callback
	online._apply_web_auth_state(_state("account-a", "refresh"))
	_check("token_refresh_preserves_generation", online._auth_generation == first_generation
		and online.requests.size() == 1 and notifications[0] == 1)
	online._save_push_timer = 5.0
	online._synced_this_session = true
	online._apply_web_auth_state(_state("account-b", "first"))
	_check("signed_in_account_switch_notifies", notifications[0] == 2
		and online._auth_owner_id == "account-b" and online.requests.size() == 2)
	_check("account_switch_clears_pending_save", online._save_push_timer < 0.0
		and not online._synced_this_session)
	old_a.call(true, {"exists": false, "sync_protocol": 2, "revision": "absent"})
	_check("old_owner_pull_cannot_start_new_owner_push", online.requests.size() == 2
		and not online._synced_this_session)
	var old_b: Callable = online.requests[1].callback
	online._apply_web_auth_state(_state("account-a", "returned"))
	_check("returning_owner_gets_new_generation", online._auth_generation > first_generation
		and online.requests.size() == 3)
	old_a.call(true, {"exists": false, "sync_protocol": 2, "revision": "absent"})
	old_b.call(true, {"exists": false, "sync_protocol": 2, "revision": "absent"})
	_check("a_b_a_rejects_both_stale_pulls", online.requests.size() == 3
		and not online._synced_this_session)
	online.requests[2].callback.call(true, {"exists": false, "sync_protocol": 2, "revision": "absent"})
	_check("current_owner_pull_starts_push", online.requests.size() == 4
		and online.requests[3].method == "PUT" and online._synced_this_session)
	online._save_push_timer = 4.0
	online._apply_web_auth_state({"signedIn": false, "token": _token("account-a", "stale")})
	_check("signout_discards_even_stale_bridge_token", online._token.is_empty()
		and online._auth_owner_id.is_empty() and not online._synced_this_session
		and online._save_push_timer < 0.0)
	online._push_save_now()
	_check("signout_cannot_push", online.requests.size() == 4)
	online._apply_web_auth_state({"signedIn": true, "token": "", "ready": true})
	_check("token_pending_cannot_pull_or_announce_usable_signin", online.requests.size() == 4
		and not online.signed_in)
	online._apply_web_auth_state(_state("account-b", "ready"))
	_check("token_arrival_notifies_even_when_already_signed_in", online.requests.size() == 5)
	var pending_b: Callable = online.requests[4].callback
	online._apply_web_auth_state({"signedIn": false})
	pending_b.call(false, {"error": "timeout"})
	_check("late_failure_after_signout_cannot_mark_synced", not online._synced_this_session
		and online.requests.size() == 5)
	online.free()
	_test_auth_loader_feedback()
	_test_cloud_save_choice()
	_test_menu_css_phone_classification()
	_test_invisible_session_switch()
	_test_score_boards_and_save_prompt()
	_test_score_outbox()
	print("[online_auth_contract] DONE: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed else 0)


func _test_auth_loader_feedback() -> void:
	var online := OnlineFixture.new()
	add_child(online)
	var notifications: Array[int] = [0]
	online.auth_changed.connect(func() -> void: notifications[0] += 1)
	online.sign_in_pending = true
	online._apply_web_auth_state({"ready": true, "signedIn": false})
	_check("modal_ready_clears_opening_without_identity_change", not online.sign_in_pending
		and notifications[0] == 1)
	online.sign_in_pending = true
	online._apply_web_auth_state({"ready": false, "error": "script", "signedIn": false})
	_check("clerk_load_error_clears_opening_and_allows_retry", not online.sign_in_pending
		and online.auth_error == "script" and notifications[0] == 2)
	online.free()


func _test_cloud_save_choice() -> void:
	var saved_data := SaveManager.data.duplicate(true)
	SaveManager.data = SaveManager.default_save()
	SaveManager.data["fish"] = 100
	SaveManager.data["xp"] = 100
	var online := OnlineFixture.new()
	add_child(online)
	var conflicts: Array[int] = [0]
	online.cloud_save_conflict.connect(func() -> void: conflicts[0] += 1)
	online._apply_web_auth_state(_state("save-owner", "first"))
	online.requests[0].callback.call(true, {"exists": true, "sync_protocol": 2,
		"revision": "a".repeat(64), "data": "{\"fish\":500,\"xp\":200}"})
	_check("two_played_saves_reconcile_without_chooser", not online.has_cloud_save_conflict()
		and online._synced_this_session and online.requests.size() == 2 and conflicts[0] == 0
		and SaveManager.data["fish"] == 500)
	_check("automatic_upload_is_revision_guarded", online.requests[1].method == "PUT"
		and JSON.parse_string(online.requests[1].body).base_revision == "a".repeat(64))
	_check("legacy_choice_api_cannot_replace_progress", not online.resolve_cloud_save_conflict(true))
	online.requests[1].callback.call(false, {"error": "unavailable"})
	_check("failed_upload_stops_sync_without_repull_loop", online.cloud_sync_error
		and not online._synced_this_session and online.requests.size() == 2)
	online.free()
	var unavailable := OnlineFixture.new()
	add_child(unavailable)
	unavailable._apply_web_auth_state(_state("save-owner", "first"))
	unavailable.requests[0].callback.call(false, {"error": "network"})
	_check("failed_cloud_read_never_pushes_unknown_remote", unavailable.requests.size() == 1
		and unavailable.cloud_sync_error and not unavailable._synced_this_session)
	unavailable.free()
	SaveManager.data = saved_data
	SaveManager.save_now()


func _test_menu_css_phone_classification() -> void:
	var menu := MenuScript.new()
	menu._profile = LayoutProfile.for_view_size(Vector2(1170.0, 1800.0))
	var saved_width := MenuScript.forced_css_width
	MenuScript.forced_css_width = 390.0
	_check("high_dpr_web_phone_gets_narrow_menu", menu._is_narrow_portrait())
	MenuScript.forced_css_width = 768.0
	_check("portrait_tablet_keeps_tablet_menu", not menu._is_narrow_portrait())
	MenuScript.forced_css_width = saved_width
	menu.free()


func _test_invisible_session_switch() -> void:
	var online := OnlineFixture.new()
	add_child(online)
	var first := _state("account-a", "first")
	first["identityEpoch"] = 1
	online._apply_web_auth_state(first)
	var original_pull: Callable = online.requests[0].callback
	var old_generation := online._auth_generation
	var callbacks: Array[Dictionary] = []
	online._request("POST", "fixture/score", "", func(ok: bool, data: Dictionary) -> void:
		callbacks.append({"ok": ok, "data": data}))
	var score: Callable = online.requests[1].callback
	var returned := _state("account-a", "returned")
	returned["identityEpoch"] = 3 # A -> B -> A occurred between Godot polls.
	online._apply_web_auth_state(returned)
	_check("unobserved_session_switch_invalidates_same_owner", online._auth_generation > old_generation
		and online.requests.size() == 3)
	original_pull.call(true, {"exists": false, "sync_protocol": 2, "revision": "absent"})
	_check("unobserved_switch_stale_cloud_pull_dropped", not online._synced_this_session
		and online.requests.size() == 3)
	score.call(true, {"rank": 1})
	score.call(true, {"rank": 2})
	_check("stale_score_settles_once_without_old_rank", callbacks.size() == 1
		and not callbacks[0].ok and callbacks[0].data == {"error": "account_changed"})
	var current_generation := online._auth_generation
	returned["token"] = _token("account-a", "refresh")
	online._apply_web_auth_state(returned)
	_check("same_epoch_token_refresh_does_not_restart_pull", online._auth_generation == current_generation
		and online.requests.size() == 3)
	online.requests[2].callback.call(true, {"exists": false, "sync_protocol": 2, "revision": "absent"})
	_check("fresh_epoch_response_still_pushes", online.requests.size() == 4
		and online.requests[3].method == "PUT")
	online.free()


func _state(owner: String, revision: String) -> Dictionary:
	return {"signedIn": true, "name": "Fixture", "ready": true, "token": _token(owner, revision)}


func _test_score_boards_and_save_prompt() -> void:
	var saved_data := SaveManager.data.duplicate(true)
	var saved_settings := SettingsManager.settings.duplicate(true)
	var saved_available := LeaderboardClient.force_available
	var saved_native := GameConfig.force_native_offline_mvp
	var saved_signed_in := LeaderboardClient.signed_in
	var saved_name := LeaderboardClient.display_name
	var saved_mode := Game.mode
	var saved_course := Game.course_id
	LeaderboardClient.force_available = true
	GameConfig.force_native_offline_mvp = false
	SaveManager.data = SaveManager.default_save()
	SettingsManager.settings["online"] = {"display_name": ""}
	_check("pristine_save_does_not_prompt", not MenuScript.save_prompt_due(SaveManager.data, 0, 1000000))
	SaveManager.data["runner_high_score"] = 12345
	_check("runner_only_progress_prompts_and_is_not_pristine", LeaderboardClient.has_played_progress(SaveManager.data)
		and MenuScript.save_prompt_due(SaveManager.data, 0, 1000000))
	_check("save_prompt_cooldown_blocks_same_day", not MenuScript.save_prompt_due(SaveManager.data, 999999, 1000000))
	_check("save_prompt_returns_after_seven_days", MenuScript.save_prompt_due(SaveManager.data, 1000000,
		1000000 + MenuScript.SAVE_PROMPT_COOLDOWN))
	_check("save_prompt_clock_rollback_does_not_nag", not MenuScript.save_prompt_due(SaveManager.data, 1000001, 1000000))
	var tabs: Array[Dictionary] = BoardScript.tabs()
	_check("runner_board_is_distinct_from_expedition", tabs[0] == {"mode": "runner", "course": "runner", "label": "Waddle Run"}
		and (not GameConfig.RACE_VISIBLE_IN_MVP or (tabs[-1]["mode"] == "endless" and tabs[-1]["course"] == "endless")))
	var courses: Array[String] = []
	for tab: Dictionary in tabs:
		if tab["mode"] == "time":
			courses.append(tab["course"])
	_check("all_race_courses_have_time_boards", PackedStringArray(courses) == (CoursesDB.ORDER if GameConfig.RACE_VISIBLE_IN_MVP else PackedStringArray()))
	Game.mode = Game.Mode.RUNNER
	Game.course_id = "runner"
	_check("runner_visit_opens_runner_board", BoardScript.initial_tab_index() == 0)
	Game.mode = Game.Mode.ENDLESS
	Game.course_id = "endless"
	_check("expedition_visit_opens_expedition_board", BoardScript.initial_tab_index() == tabs.size() - 1)
	var online := OnlineFixture.new()
	add_child(online)
	_check("runner_saved_points_not_distance", online.local_board_value("runner", "runner") == 12345)
	SaveManager.data["best_times"] = {"cinder": 65.25}
	_check("saved_race_time_converts_to_milliseconds", online.local_board_value("time", "cinder") == 65250)
	SaveManager.data["endless_high_score"] = 987
	_check("expedition_saved_points_stay_separate", online.local_board_value("endless", "endless") == 987)
	Game.mode = Game.Mode.QUICK_RACE
	Game.course_id = "cinder"
	_check("race_visit_opens_matching_course", tabs[BoardScript.initial_tab_index()]["course"] == ("cinder" if GameConfig.RACE_VISIBLE_IN_MVP else "runner"))
	online.submit_completed_run("runner", "runner", 12345)
	_check("guest_run_does_not_publish", online.requests.is_empty())
	online._token = _token("synthetic-score-owner", "current")
	online._auth_owner_id = "synthetic-score-owner"
	online.signed_in = true
	online.display_name = "Private Fixture Name"
	online.submit_completed_run("runner", "runner", 12345)
	var body: Variant = JSON.parse_string(online.requests[0]["body"])
	var posted_value: Variant = body.get("value") if body is Dictionary else null
	# JSON numbers decode as floats. Validate exact fields and scalar types,
	# not Dictionary equality against an int-valued GDScript literal.
	_check("signed_in_completed_runner_posts_real_score_without_private_name", online.requests.size() == 1
		and body is Dictionary and body.size() == 3
		and body.has("mode") and body.has("course") and body.has("value")
		and body["mode"] is String and body["mode"] == "runner"
		and body["course"] is String and body["course"] == "runner"
		and (posted_value is int or posted_value is float) and float(posted_value) == 12345.0)
	GameConfig.force_native_offline_mvp = true
	online.submit_completed_run("runner", "runner", 12345)
	_check("native_mvp_does_not_auto_publish_even_with_test_auth", online.requests.size() == 1)
	var rejected: Array[bool] = []
	online.submit_score("runner", "runner", 12345, func(ok: bool, _data: Dictionary) -> void: rejected.append(ok))
	_check("native_mvp_direct_score_post_is_fenced", rejected == [false] and online.requests.size() == 1)
	GameConfig.force_native_offline_mvp = false
	online.free()
	LeaderboardClient.signed_in = true
	LeaderboardClient.display_name = "Private Fixture Name"
	_test_tied_board_owner(tabs[0])
	SaveManager.data = SaveManager.default_save()
	var prompt := MenuScript.new()
	prompt._schedule_save_prompt()
	_check("non_web_prompt_ignores_auth_layout_override", prompt._save_prompt_timer == null)
	prompt.free()
	_check("time_trial_only_save_is_played_progress", LeaderboardClient.has_played_progress({"best_times": {"hollow": 88.0}}))
	SaveManager.data = saved_data
	SaveManager.save_now()
	SettingsManager.settings = saved_settings
	LeaderboardClient.force_available = saved_available
	GameConfig.force_native_offline_mvp = saved_native
	LeaderboardClient.signed_in = saved_signed_in
	LeaderboardClient.display_name = saved_name
	Game.mode = saved_mode
	Game.course_id = saved_course


func _test_tied_board_owner(tab: Dictionary) -> void:
	var board := BoardScript.new()
	board._list_box = VBoxContainer.new()
	board.add_child(board._list_box)
	board._state_box = VBoxContainer.new()
	board.add_child(board._state_box)
	board._header_row = Control.new()
	board.add_child(board._header_row)
	board._own_rank_label = Label.new()
	board.add_child(board._own_rank_label)
	board._status_label = Label.new()
	board._state_box.add_child(board._status_label)
	var parent := VBoxContainer.new()
	board.add_child(parent)
	board._profile = LayoutProfile.for_view_size(Vector2(1920, 1080))
	board._build_auth_card(parent)
	_check("public_name_editor_never_prefills_private_identity", board._name_edit.text.is_empty())
	board._populate(true, {"entries": [
		{"rank": 1, "name": "Penguin", "value": 12345, "is_me": false},
		{"rank": 1, "name": "Penguin", "value": 12345, "is_me": true}],
		"me": {"rank": 1, "value": 12345}}, tab)
	_check("tied_owner_uses_explicit_flag_not_equal_rank", board._list_box.get_child_count() == 2
		and _count_label(board._list_box.get_child(0), "YOU") == 0
		and _count_label(board._list_box.get_child(1), "YOU") == 1)
	_check("own_rank_is_visible_even_when_tied", board._own_rank_label.text == "Your global rank #1 · 12345")
	board._populate(true, {"entries": [
		{"rank": 1, "name": "Penguin", "value": 12345}], "me": {"rank": 1, "value": 12345}}, tab)
	_check("legacy_board_gets_separate_truthful_own_row", board._list_box.get_child_count() == 3
		and _count_label(board._list_box.get_child(0), "YOU") == 0
		and _count_label(board._list_box.get_child(2), "You") == 1)
	if board._status_label.get_parent() == null:
		board._status_label.free()
	board.free()


func _test_score_outbox() -> void:
	var saved_available := LeaderboardClient.force_available
	var saved_native := GameConfig.force_native_offline_mvp
	LeaderboardClient.force_available = true
	GameConfig.force_native_offline_mvp = false
	# Detached fixture deliberately has no auth->cloud-sync listener. Only
	# score requests execute, and transport never reaches a live service.
	var online := OnlineFixture.new()
	var events: Array[String] = []
	online.score_submission_changed.connect(func(mode: String, course: String) -> void:
		events.append(mode + ":" + course + ":" + online.score_submission_status(mode, course)))
	online.submit_completed_run("runner", "runner", 99999)
	_check("score_guest_run_is_not_queued_for_future_account", online.requests.is_empty() and online._score_submissions.is_empty())
	online._apply_web_auth_state(_state("score-a", "first"))
	_check("score_signin_does_not_publish_device_history", online.requests.is_empty())
	online.submit_completed_run("runner", "runner", 1000)
	_check("score_completed_run_exposes_posting", online.requests.size() == 1
		and online.score_submission_status("runner", "runner") == "posting"
		and online.pending_score_value("runner", "runner") == 1000
		and events[-1] == "runner:runner:posting")
	online.submit_completed_run("runner", "runner", 1000)
	online.submit_completed_run("runner", "runner", 3000)
	online.submit_completed_run("runner", "runner", 2000)
	_check("score_inflight_coalesces_only_strongest_run", online.requests.size() == 1
		and online.pending_score_value("runner", "runner") == 3000)
	online.requests[0].callback.call(false, {"error": "synthetic transport detail never retained"})
	_check("score_failure_retains_best_and_surfaces_pending", online.score_submission_status("runner", "runner") == "pending"
		and online.pending_score_value("runner", "runner") == 3000
		and not JSON.stringify(online._score_submissions).contains("synthetic transport detail"))
	_check("score_no_hidden_retry_after_failure", online.requests.size() == 1)
	var callbacks: Array[Dictionary] = []
	var receive := func(ok: bool, data: Dictionary) -> void: callbacks.append({"ok": ok, "data": data})
	_check("score_explicit_retry_started", online.retry_pending_score("runner", "runner", receive))
	_check("score_retry_uses_best_failed_value", online.requests.size() == 2
		and int(JSON.parse_string(online.requests[1].body).value) == 3000)
	_check("score_retry_while_posting_is_rejected", not online.retry_pending_score("runner", "runner") and online.requests.size() == 2)
	online.requests[1].callback.call(true, _score_ack(5000))
	_check("score_acknowledgment_clears_pending_and_exposes_server_best", online.score_submission_status("runner", "runner") == "posted"
		and online.pending_score_value("runner", "runner") == 0 and online.posted_score_value("runner", "runner") == 5000
		and callbacks.size() == 1 and callbacks[0].ok)
	online.submit_score("runner", "runner", 4000, receive)
	_check("score_already_acknowledged_best_does_not_repost", online.requests.size() == 2
		and callbacks.size() == 2 and callbacks[-1].ok and callbacks[-1].data.get("already_posted", false)
		and callbacks[-1].data.get("rank") == 1 and callbacks[-1].data.get("name") == "Penguin")
	online.submit_completed_run("runner", "runner", 6000)
	var stale: Callable = online.requests[2].callback
	online._apply_web_auth_state(_state("score-b", "first"))
	_check("score_new_account_cannot_see_or_retry_previous_account", online.score_submission_status("runner", "runner") == "idle"
		and online.pending_score_value("runner", "runner") == 0 and online.posted_score_value("runner", "runner") == 0
		and not online.retry_pending_score("runner", "runner"))
	online._apply_web_auth_state(_state("score-a", "returned"))
	_check("score_returning_account_retains_pending_without_auto_publish", online.score_submission_status("runner", "runner") == "pending"
		and online.pending_score_value("runner", "runner") == 6000 and online.requests.size() == 3)
	online.retry_pending_score("runner", "runner", receive)
	stale.call(true, _score_ack(6000))
	_check("score_a_b_a_old_success_cannot_ack_new_attempt", online.score_submission_status("runner", "runner") == "posting"
		and online.posted_score_value("runner", "runner") == 5000)
	var gen := online._auth_generation
	online._apply_web_auth_state(_state("score-a", "token-refresh"))
	_check("score_token_refresh_keeps_active_attempt", online._auth_generation == gen
		and online.score_submission_status("runner", "runner") == "posting")
	online.requests[3].callback.call(true, _score_ack(6000, 2))
	_check("score_current_attempt_acknowledges_after_refresh", online.posted_score_value("runner", "runner") == 6000
		and online.score_submission_status("runner", "runner") == "posted")
	online.submit_completed_run("runner", "runner", 7000)
	online.submit_completed_run("runner", "runner", 9000)
	online.requests[4].callback.call(true, _score_ack(7000))
	_check("score_newer_run_not_lost_when_older_request_succeeds", online.pending_score_value("runner", "runner") == 9000
		and online.score_submission_status("runner", "runner") == "pending" and online.requests.size() == 5)
	online.submit_completed_run("time", "glacier", 60000)
	online.submit_completed_run("time", "glacier", 55000)
	online.submit_completed_run("time", "glacier", 65000)
	online.requests[5].callback.call(false, {})
	_check("score_time_board_keeps_fastest_not_largest", online.pending_score_value("time", "glacier") == 55000)
	online.retry_pending_score("time", "glacier")
	_check("score_time_retry_posts_fastest_milliseconds", int(JSON.parse_string(online.requests[6].body).value) == 55000)
	online.requests[6].callback.call(true, _score_ack(54000))
	_check("score_time_server_best_is_lower", online.posted_score_value("time", "glacier") == 54000
		and online.score_submission_status("time", "glacier") == "posted")
	var before := online.requests.size()
	for invalid: Array in [["unknown", "runner", 1], ["runner", "glacier", 1], ["time", "unknown", 30000],
		["runner", "runner", 0], ["runner", "runner", 1000000001], ["time", "glacier", 9999],
		["time", "glacier", 1800001], ["endless", "endless", 1000001]]:
		online.submit_score(invalid[0], invalid[1], invalid[2], Callable())
	_check("score_invalid_boards_and_bounds_never_allocate_or_send", online.requests.size() == before
		and online._score_submissions["score-a".sha256_text()].size() == 2)
	GameConfig.force_native_offline_mvp = true
	_check("score_native_cannot_retry_pending_web_score", not online.retry_pending_score("runner", "runner")
		and online.score_submission_status("runner", "runner") == "idle" and online.requests.size() == before)
	GameConfig.force_native_offline_mvp = false
	online._apply_web_auth_state({"signedIn": false})
	_check("score_signedout_cannot_retry_or_view_pending", not online.retry_pending_score("runner", "runner")
		and online.score_submission_status("runner", "runner") == "idle" and online.requests.size() == before)
	var malformed := OnlineFixture.new()
	malformed._apply_web_auth_state(_state("malformed-score", "first"))
	var bad_replies: Array[Dictionary] = []
	for field: String in ["ok", "best", "rank", "improved", "name"]:
		var payload := _score_ack(1000)
		payload.erase(field)
		bad_replies.append(payload)
	for override: Dictionary in [{"best": 999}, {"best": 1000.5}, {"rank": 0},
		{"rank": "1"}, {"name": "Private\nIdentity"}, {"name": "x".repeat(1000)}, {"ok": false}]:
		var payload := _score_ack(1000)
		payload.merge(override, true)
		bad_replies.append(payload)
	var invalid_results: Array[bool] = []
	for payload: Dictionary in bad_replies:
		malformed.submit_score("runner", "runner", 1000, func(ok: bool, _data: Dictionary) -> void: invalid_results.append(ok))
		malformed.requests[-1].callback.call(true, payload)
	_check("score_malformed_success_never_fakes_acknowledgment", invalid_results.size() == bad_replies.size()
		and not invalid_results.has(true) and malformed.posted_score_value("runner", "runner") == 0
		and malformed.score_submission_status("runner", "runner") == "pending")
	malformed.free()
	var reentrant := OnlineFixture.new()
	reentrant._apply_web_auth_state(_state("reentrant-a", "first"))
	reentrant.score_submission_changed.connect(func(mode: String, course: String) -> void:
		if reentrant.score_submission_status(mode, course) == "posting":
			reentrant._apply_web_auth_state(_state("reentrant-b", "switched")))
	reentrant.submit_completed_run("runner", "runner", 8000)
	_check("score_signal_identity_switch_cannot_send_under_new_owner", reentrant.requests.is_empty()
		and reentrant._auth_owner_id == "reentrant-b")
	reentrant.free()
	for index: int in range(10):
		online._apply_web_auth_state(_state("bounded-%d" % index, "first"))
		online.submit_completed_run("runner", "runner", 100 + index)
		online.requests[-1].callback.call(false, {})
	_check("score_outbox_keeps_at_most_four_accounts", online._score_submissions.size() == 4
		and online._score_account_order.size() == 4 and not online._score_submissions.has("score-a".sha256_text()))
	_check("score_outbox_contains_no_credential_or_raw_owner", not JSON.stringify(online._score_submissions).contains("signature")
		and not JSON.stringify(online._score_submissions).contains("bounded-9"))
	# Retiring an account erases its pending scores as well as credentials.
	LeaderboardClient.force_available = false
	online.retire_account_subject("bounded-9")
	_check("score_account_retirement_erases_pending", not online._score_submissions.has("bounded-9".sha256_text()))
	online.free()
	LeaderboardClient.force_available = saved_available
	GameConfig.force_native_offline_mvp = saved_native


func _score_ack(value: int, rank: int = 1) -> Dictionary:
	return {"ok": true, "best": value, "rank": rank, "improved": false, "name": "Penguin"}


func _count_label(node: Node, text: String) -> int:
	var count := 1 if node is Label and node.text == text else 0
	for child: Node in node.get_children():
		count += _count_label(child, text)
	return count


func _token(owner: String, revision: String) -> String:
	return "header.%s.signature" % Marshalls.utf8_to_base64(JSON.stringify({"sub": owner, "jti": revision}))


func _check(label: String, success: bool) -> void:
	if success:
		_passed += 1
		print("[online_auth_contract] PASS %s" % label)
	else:
		_failed += 1
		print("[online_auth_contract] FAIL %s" % label)
