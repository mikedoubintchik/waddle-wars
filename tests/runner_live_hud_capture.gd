extends "res://tests/runner_presentation_capture.gd"
## Bounded foreground proof of real mission progress and authoritative timers.
## Only synthetic action: one grant of each power after first real movement.
## Production route, countdown, movement and elapsed clocks remain unchanged.

var _live_armed := false
var _live_complete := false
var _grant_elapsed := -1.0


func _ready() -> void:
	if _monitor:
		GameConfig.force_native_offline_mvp = true
	super._ready()


func _process(delta: float) -> void:
	# macOS can stop submitted frames when another window covers the game.
	# Reacquire visibility before a normal draw; never force a render or clock.
	if _monitor and not _finished and not get_window().has_focus():
		DisplayServer.window_move_to_foreground()
	super._process(delta)


func _snapshot(phase: String) -> Dictionary:
	var row := super._snapshot(phase)
	var game := get_tree().current_scene as RunnerGame
	if game == null or game.hud == null or game.player == null:
		return row
	var counts: Array[String] = []
	var timers: Array[String] = []
	var labels: Array[String] = []
	for label: Label in game.hud._mission_pcts:
		counts.append(label.text)
	for label: Label in game.hud._mission_labels:
		labels.append(label.text)
	for label: Label in game.hud._powerup_times:
		timers.append(label.text)
	row.merge({"mission_rows": game.missions.rows(), "mission_counts": counts,
		"mission_labels": labels, "powerup_timers": timers,
		"powerup_remaining": game.player.powerups.duplicate(true),
		"dead": game._dead, "grant_elapsed": _grant_elapsed})
	return row


func _on_frame_post_draw() -> void:
	super._on_frame_post_draw()
	if _finished or not _live_armed:
		return
	var game := get_tree().current_scene as RunnerGame
	if game == null or not game.running or game._dead:
		return
	if _grant_elapsed < 0.0:
		for id: StringName in RunnerConfig.POWERUP_IDS:
			game.player.grant_powerup(id)
		_grant_elapsed = game.elapsed
		return
	if game.elapsed - _grant_elapsed < 2.25:
		return
	if not get_window().has_focus() or not get_window().visible:
		DisplayServer.window_move_to_foreground()
		return
	var row := _snapshot("live_hud_post_draw")
	_check(not game._dead and game.elapsed > 2.25 and game.player.distance > 0.0,
		"real gameplay advanced distance after first motion without clock edits")
	var mission_rows := game.missions.rows()
	_check(not mission_rows.is_empty() and float(mission_rows[0].get("current", 0.0)) > 0.0,
		"live distance mission has nonzero authority")
	for i: int in mission_rows.size():
		var entry: Dictionary = mission_rows[i]
		var expected := "%s / %s" % [RunnerHUD.group_digits(int(entry.get("current", 0.0))),
			RunnerHUD.group_digits(int(entry.get("target", 0.0)))]
		_check(game.hud._mission_pcts[i].text == expected,
			"mission %d displayed counts match live authority" % i)
	for i: int in RunnerConfig.POWERUP_IDS.size():
		var remaining := float(game.player.powerups.get(RunnerConfig.POWERUP_IDS[i], 0.0))
		_check(remaining > 6.0 and remaining <= 7.0
			and game.hud._powerup_times[i].text == "7s"
			and game.hud._powerup_slots[i].is_visible_in_tree(),
			"powerup %d displays seven authoritative remaining seconds" % i)
	_check(bool(row["window_focused"]) and bool(row["window_visible"]),
		"final live HUD frame submitted by visible foreground game")
	_capture("hud_live", row)
	_live_complete = true
	_finish(false)


func _required_capture_ids() -> PackedStringArray:
	var ids := super._required_capture_ids()
	ids.append("hud_live")
	return ids


func _finish(timed_out: bool) -> void:
	if not timed_out and not _live_armed:
		_live_armed = true
		return
	if not timed_out and not _live_complete:
		return
	_check(_live_complete, "live mission and seven-second powerup raster completed")
	super._finish(timed_out)
	var report_path := _out.get_basename() + ".json"
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(report_path))
	if report is Dictionary:
		report["kind"] = "runner_live_missions_powerup_hud"
		report["limits"] = "Real SceneRouter/countdown/gameplay and native foreground submitted frame. Three synthetic grant_powerup calls after first movement; natural collection is not verified. No mission injection, clock changes, force_draw, physical input, browser/device or performance claim. PNG readbacks perturb timing."
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
