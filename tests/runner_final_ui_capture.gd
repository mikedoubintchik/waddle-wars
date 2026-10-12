extends Node
## Narrow native stills of final HUD labels, same-tick toast/powers and pause.
## Direct real scene construction; no SceneRouter handoff/performance claim.

class PauseFixture extends RunnerGame:
	func _ready() -> void:
		build_finished = true
		_presentation_started = true
		running = true
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass

var _out := ""
var _shape := Vector2i(960,540)
var _captures: Array[Dictionary] = []
var _checks: Array[Dictionary] = []
var _done := false
var _neutral := false
var _game: RunnerGame = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if GameConfig.is_headless():
		print("[runner-final-ui] Parser only; no pixel acceptance")
		get_tree().quit()
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="): _out = arg.trim_prefix("out=")
		elif arg == "portrait=1": _shape = Vector2i(540,960)
		elif arg == "neutral=1": _neutral = true
	if not _out.is_absolute_path() or not ProjectSettings.get_setting("application/config/use_custom_user_dir",false):
		get_tree().quit(2)
		return
	get_tree().create_timer(35.0, true, false, true).timeout.connect(func() -> void:
		if not _done:
			_check(false,"submitted stills completed within35 seconds")
			_finish())
	GameConfig.force_native_offline_mvp = true
	GameConfig.force_touch = _shape.y > _shape.x
	LayoutProfile.forced_insets = Vector4(-1,-1,-1,-1)
	DisplayServer.window_set_size(_shape)
	DisplayServer.window_set_position(Vector2i(40,60))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,false)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP,true)
	DisplayServer.window_move_to_foreground()
	SettingsManager._apply_ui_scale(1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	var background: ColorRect = null
	var hud: RunnerHUD
	if _neutral:
		background = ColorRect.new()
		background.color = Color("55afe0")
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(background)
		hud = RunnerHUD.new()
		add_child(hud)
		hud.setup()
	else:
		# Same direct scene entry as the proven no-PNG performance probe. Let
		# shipped staged construction, warmup and first presentation complete.
		_game = (load(Game.SCENE_RUNNER) as PackedScene).instantiate() as RunnerGame
		_game.generation_seed = 20260907
		add_child(_game)
		while not _done and (not _game.build_finished or not _game._presentation_started \
				or is_instance_valid(_game._startup_warmup) or not _game.running or _game.elapsed < 0.25):
			await get_tree().process_frame
		if _done: return
		_check(_game.track.get_child_count() > 0 and _game.player.distance > 0.0,
			"real direct scene built visible course and advanced player before controlled stills")
		_game.set_process(false)
		_game.player.set_input_enabled(false)
		hud = _game.hud
		hud.show_message("")
	hud.set_missions([
		{"id":"x2","kind":RunnerMissions.Kind.MULTIPLIER_RUN,"mult":4,"text":"Run 650 m at x4 or better in one run","current":50,"target":650},
		{"id":"fish","kind":RunnerMissions.Kind.FISH_TOTAL,"text":"Collect 400 fish","current":13,"target":400},
		{"id":"clean","kind":RunnerMissions.Kind.CLEAN_RUN,"text":"Dodge everything for 1,400 m in one run","current":38,"target":1400}])
	hud.set_stats(245,32,1460,2,3,34.0)
	await _capture("overlays_live",hud)
	var toast := SceneRouter._make_achievement_toast("Power Player · Bronze")
	SceneRouter._toast_layer.add_child(toast)
	SceneRouter._place_achievement_toast(toast,hud)
	# Reproduce the ordering that used stale empty power-column bounds.
	hud.set_powerups({&"magnet":8.0,&"shield":8.0,&"double":8.0})
	await _capture("overlays_active",hud,toast)
	toast.free()
	var pause: RunnerGame = _game
	if _neutral:
		hud.free()
		background.free()
		pause = PauseFixture.new()
		add_child(pause)
	pause._toggle_pause()
	await _capture("overlays_paused",null,null,pause._pause_layer)
	pause._close_pause()
	pause.free()
	for audio_player: AudioStreamPlayer in AudioManager._sfx_pool:
		audio_player.stop()
		audio_player.stream = null
	await get_tree().create_timer(0.15).timeout
	_finish()

func _capture(id: String, hud: RunnerHUD = null, toast: Panel = null, pause: Node = null) -> void:
	await get_tree().create_timer(0.45).timeout
	DisplayServer.window_move_to_foreground()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if _done: return
	var visible := get_window().visible and DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_MINIMIZED
	_check(visible,id+" actual native window visible at submitted draw")
	var record := {"id":id,"window_visible":visible,"window_focused":get_window().has_focus(),
		"process_frame":Engine.get_process_frames(),"draw_frame":Engine.get_frames_drawn(),
		"logical_size":str(get_viewport().get_visible_rect().size),"touch_forced":GameConfig.force_touch,
		"direct_real_scene":not _neutral,"build_finished":_game.build_finished if is_instance_valid(_game) else false}
	if hud != null:
		var labels: Array[Dictionary] = []
		for label: Label in hud._mission_labels:
			_check(label.get_line_count() <= 2 and label.get_line_count() == label.get_visible_line_count(),
				id+" compact mission fully visible: "+label.text)
			labels.append({"text":label.text,"font":label.get_theme_font_size("font_size"),
				"rect":str(label.get_global_rect()),"lines":label.get_line_count()})
		record["mission_labels"] = labels
	if toast != null:
		var excluded: Array[Control] = [hud._mission_panel,hud._headline_column]
		excluded.append_array(hud._powerup_slots)
		var avoids := true
		for control: Control in excluded:
			avoids = avoids and not toast.get_global_rect().intersects(control.get_global_rect())
		_check(avoids,"toast avoids all3 powers, challenges and headline after actual layout")
		_check(get_viewport().get_visible_rect().encloses(toast.get_global_rect()),"toast enclosed by actual viewport")
		_check(hud._powerup_slots.all(func(slot: Control) -> bool: return slot.is_visible_in_tree() and slot.modulate.a >= 0.95),"all3 powers visibly settled")
		record["toast_rect"] = str(toast.get_global_rect())
	if pause != null:
		var card := pause.find_child("PauseCard",true,false) as Control
		_check(get_viewport().get_visible_rect().encloses(card.get_global_rect()),"pause backing enclosed")
		record["pause_card"] = str(card.get_global_rect())
		for button: Button in card.find_children("*","Button",true,false):
			_check(get_viewport().get_visible_rect().encloses(button.get_global_rect()),"pause action enclosed: "+button.accessibility_name)
	var pixels := get_viewport().get_texture().get_image()
	_check(pixels != null and not pixels.is_empty() and pixels.get_size() == _shape,id+" real readback matches requested size")
	DirAccess.make_dir_recursive_absolute(_out)
	var path := _out.path_join("runner_"+id+".png")
	var error := pixels.save_png(path)
	_check(error == OK,id+" PNG saved unchanged")
	record["path"] = path
	_captures.append(record)

func _check(ok: bool, detail: String) -> void:
	_checks.append({"passed":ok,"detail":detail})
	if not ok: push_error("[runner-final-ui] "+detail)

func _finish() -> void:
	if _done: return
	_done = true
	_check(_captures.size() == 3,"all3 scoped UI states rendered")
	var failed := _checks.filter(func(row: Dictionary) -> bool: return not row["passed"]).size()
	var report := {"status":"PASS" if failed == 0 else "FAIL","check_count":_checks.size(),"failed_count":failed,
		"captures":_captures,"checks":_checks,"neutral_background":_neutral,"limitations":"Narrow actual native submitted UI stills. Default directly instantiates production RunnerGame, waits normal staged build/warmup and first running movement, then freezes game processing for controlled presentation. Synthetic stats/missions/power timers/toast; final touch scaling and actual pause builder. Optional neutral mode has no course/startup. No SceneRouter handoff, collision, physical input, animation timing, performance, browser or device acceptance. Earlier v5 owns real route and catch/results evidence. Focus recorded; visible submitted pixels required."}
	DirAccess.make_dir_recursive_absolute(_out)
	var file := FileAccess.open(_out.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")+"\n")
	file.close()
	print("[runner-final-ui] %d checks, %d failures" % [_checks.size(),failed])
	get_tree().quit(1 if failed else 0)
