extends Node
## Explicit posting UX, lifecycle and footer bounds. No network or score writes.

class SampleBoard extends "res://scripts/ui/leaderboard_premium.gd":
	var requests: Array[Dictionary] = []
	var refreshes: int = 0
	func _fetch() -> void:
		refreshes += 1
	func _send_local_score(value: int, retry_pending: bool, deliver: Callable) -> void:
		requests.append({"value": value, "retry": retry_pending, "callback": deliver})

var passed := 0
var failed := 0

func _ready() -> void:
	LeaderboardClient.set_process(false)
	var original_data := SaveManager.data.duplicate(true)
	var original_signed_in := LeaderboardClient.signed_in
	var original_available := LeaderboardClient.force_available
	var original_owner := LeaderboardClient._auth_owner_id
	var original_native := GameConfig.force_native_offline_mvp
	LeaderboardClient.force_available = true
	GameConfig.force_native_offline_mvp = false
	for shape: Vector2i in [Vector2i(800, 1422), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		GameConfig.force_touch = shape.y > shape.x
		LayoutProfile.forced_insets = Vector4.ONE * (24.0 if GameConfig.force_touch else 0.0)
		SaveManager.data = SaveManager.default_save()
		SaveManager.data["runner_high_score"] = 12345
		LeaderboardClient.signed_in = false
		LeaderboardClient._auth_owner_id = ""
		var viewport := SubViewport.new()
		viewport.size = shape
		add_child(viewport)
		var board := SampleBoard.new()
		viewport.add_child(board)
		board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await settle()
		check(board._post_button == null and not board._post_status.visible, "guest sees no score-post action")
		board._post_local_best()
		check(board.requests.is_empty(), "guest cannot post historical score implicitly")
		LeaderboardClient.signed_in = true
		LeaderboardClient._auth_owner_id = "synthetic-board-ui-a"
		board._on_auth_changed()
		await settle()
		check(board._post_button.visible and not board._post_button.disabled and board._post_button.text == "POST LOCAL BEST", "signed-in player sees explicit Post Local Best")
		check(board._post_status.text.contains("12,345"), "post action describes actual local high score")
		check_bounds(board, shape, "ready")
		board._receive(board._serial, true, {"entries": []})
		await settle()
		check_bounds(board, shape, "signed-in empty board")
		board._receive(board._serial, false, {})
		await settle()
		check_bounds(board, shape, "signed-in unavailable board")
		SaveManager.data["runner_high_score"] = 0
		board._update_post_controls()
		board._post_local_best()
		check(not board._post_button.visible and board.requests.is_empty(), "zero score cannot be posted")
		SaveManager.data["runner_high_score"] = 12345
		board._update_post_controls()
		board._post_local_best()
		board._post_local_best()
		check(board.requests.size() == 1 and int(board.requests[0]["value"]) == 12345, "double click posts one actual saved score")
		check(board._post_button.disabled and board._post_button.text == "POSTING…" and board._post_status.text.contains("Posting"), "in-flight post has visible pending state")
		await settle()
		check_bounds(board, shape, "posting")
		var first: Callable = board.requests[0]["callback"]
		first.call(false, {"error": "timeout"})
		check(not board._post_button.disabled and board._post_status.text.contains("Post failed"), "failed post enables explicit retry and explains local safety")
		check(Progression.runner_high_score() == 12345, "network failure cannot alter saved best")
		board._post_local_best()
		var retry: Callable = board.requests[1]["callback"]
		board._rebuild()
		await settle()
		check(board._post_button.disabled and board._post_status.text.contains("Posting"), "resize preserves in-flight post state")
		first.call(true, {"best": 12345, "rank": 99})
		check(board._post_busy and board._known_server_best == 0, "late earlier callback cannot complete newer post for same account")
		var before_refresh := board.refreshes
		retry.call(true, {"best": 12345, "rank": 7})
		check(board.refreshes == before_refresh + 1, "successful post refreshes authoritative ranks")
		check(board._post_button.disabled and board._post_button.text == "BEST POSTED" and board._post_status.text.contains("#7"), "successful post shows server rank and suppresses duplicate")
		retry.call(false, {"error": "duplicate late callback"})
		check(board.refreshes == before_refresh + 1 and board._post_status.text.contains("#7"), "duplicate callback cannot overwrite accepted success")
		board._post_local_best()
		check(board.requests.size() == 2, "already posted best cannot be posted repeatedly")
		var entries: Array[Dictionary] = []
		for i: int in 20:
			entries.append({"rank": i + 1, "name": "Explorer %02d" % (i + 1), "value": 20000 - i * 100, "is_me": i == 6})
		board._receive(board._serial, true, {"entries": entries, "me": {"rank": 7, "value": 12345}})
		await settle()
		check(board._local_rank.text == "YOUR RANK\n7" and board._local_score.text == "12,345", "server response supplies pinned rank and score")
		check_bounds(board, shape, "posted populated board")
		SaveManager.data["runner_high_score"] = 15000
		board._update_post_controls()
		board._post_local_best()
		var old_account: Callable = board.requests[2]["callback"]
		LeaderboardClient._auth_owner_id = "synthetic-board-ui-b"
		board._on_auth_changed()
		await settle()
		var replacement_refreshes := board.refreshes
		old_account.call(true, {"best": 15000, "rank": 1})
		check(board._known_server_best == 0 and board._post_message.is_empty() and board.refreshes == replacement_refreshes, "late old-account completion cannot change new account UI")
		board._post_local_best()
		var after_exit: Callable = board.requests[3]["callback"]
		viewport.free()
		after_exit.call(true, {"best": 15000, "rank": 1})
		check(true, "post completion after screen destruction is safely ignored")
	SaveManager.data = original_data
	LeaderboardClient.signed_in = original_signed_in
	LeaderboardClient.force_available = original_available
	LeaderboardClient._auth_owner_id = original_owner
	GameConfig.force_native_offline_mvp = original_native
	GameConfig.force_touch = false
	LayoutProfile.forced_insets = Vector4(-1, -1, -1, -1)
	for player: AudioStreamPlayer in AudioManager._sfx_pool:
		player.stop()
		player.stream = null
	for player: AudioStreamPlayer in [AudioManager._music_a, AudioManager._music_b]:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.1).timeout
	print("[leaderboard-post-action] DONE: %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)

func check(ok: bool, description: String) -> void:
	passed += int(ok)
	failed += int(not ok)
	print("[leaderboard-post-action] %s %s" % ["PASS" if ok else "FAIL", description])

func settle() -> void:
	for frame: int in 5:
		await get_tree().process_frame

func check_bounds(board: Control, shape: Vector2i, state: String) -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(shape))
	for key: String in ["ChallengeFriends", "BoardRefresh", "BoardPostLocalBest", "BoardPostStatus", "LocalBestRow"]:
		var control := board.find_child(key, true, false) as Control
		check(control != null and control.is_visible_in_tree() and bounds.encloses(control.get_global_rect()), "%s %s stays inside first view at %s" % [state, key, shape])
		if control != null:
			check(_inside_clipping_ancestors(control), "%s %s clears every clipping ancestor at %s" % [state, key, shape])
	var status := board.find_child("BoardPostStatus", true, false) as Label
	var action := board.find_child("BoardPostLocalBest", true, false) as Button
	check(not status.get_global_rect().intersects(action.get_global_rect()), state + " feedback and post action do not overlap")

func _inside_clipping_ancestors(control: Control) -> bool:
	var rect := control.get_global_rect()
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is Control and ((ancestor as Control).clip_contents or ancestor is ScrollContainer):
			var clip := (ancestor as Control).get_global_rect()
			if not clip.grow(0.5).encloses(rect):
				print("[leaderboard-post-action] CLIPPED %s %s by %s %s" % [control.name, rect, ancestor.name, clip])
				return false
		ancestor = ancestor.get_parent()
	return true
