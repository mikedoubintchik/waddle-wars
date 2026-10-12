extends Node
## Silent integration: real bus rules and player state-entry signals. Does not
## claim audible output, physical browser focus or iOS behavior.

class MissionCounter:
	extends RunnerMissions
	var jumps: int = 0
	var slides: int = 0
	func note_jump() -> void: jumps += 1
	func note_slide() -> void: slides += 1

class GameFixture:
	extends RunnerGame
	func _on_presentation_event(_event: StringName, _context: Dictionary) -> void:
		pass

class QuietFixture:
	extends "res://scripts/utilities/audio_manager.gd"
	var query_reads: int = 0
	func _read_session_quiet() -> bool:
		query_reads += 1
		return true

var passed: int = 0
var failed: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	_check("silent_headless_logic_fixture", GameConfig.is_headless())
	_test_bus_rules()
	await _test_session_quiet()
	_test_movement_audio()
	# Dummy still owns an audio mixer thread. Let stopped one-shot playback
	# retire before engine exit instead of mistaking pending mixer work for leaks.
	await get_tree().create_timer(0.1).timeout
	await get_tree().process_frame
	print("[audio_focus_runner] %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _test_bus_rules() -> void:
	var saved_audio: Dictionary = SettingsManager.settings.get("audio", {}).duplicate(true)
	var saved_state := [AudioManager._muted, AudioManager._master_silent, AudioManager._window_focused]
	var buses: Array = []
	for name: String in ["Master", "Music", "SFX"]:
		var index := AudioServer.get_bus_index(name)
		buses.append([index, AudioServer.get_bus_volume_db(index), AudioServer.is_bus_mute(index)])
	SettingsManager.settings["audio"] = {"mute_unfocused": true, "muted": false, "master_volume": 0.8}
	AudioManager._muted = false
	AudioManager.set_bus_volume("Master", 0.8)
	AudioManager.set_bus_volume("Music", 0.37)
	AudioManager.set_bus_volume("SFX", 0.62)
	AudioManager._on_browser_focus_changed([true])
	_check("focused_normal_master_audible", not AudioServer.is_bus_mute(0))
	AudioManager._on_browser_focus_changed([false])
	_check("browser_callback_mutes_master_immediately", AudioServer.is_bus_mute(0))
	AudioManager.set_muted(false)
	AudioManager.set_bus_volume("Master", 0.5)
	_check("unmute_or_slider_cannot_override_focus", AudioServer.is_bus_mute(0))
	SettingsManager.settings["audio"]["mute_unfocused"] = false
	SettingsManager._apply_audio("mute_unfocused", false)
	_check("disabling_focus_preference_applies_immediately", not AudioServer.is_bus_mute(0))
	SettingsManager.settings["audio"]["mute_unfocused"] = true
	SettingsManager._apply_audio("mute_unfocused", true)
	_check("enabling_focus_preference_applies_immediately", AudioServer.is_bus_mute(0))
	AudioManager._on_browser_focus_changed([true])
	_check("focus_restore_unmutes_only_temporary_state", not AudioServer.is_bus_mute(0))
	AudioManager.set_muted(true)
	AudioManager._on_browser_focus_changed([false])
	AudioManager._on_browser_focus_changed([true])
	_check("explicit_mute_survives_focus_return", AudioServer.is_bus_mute(0))
	AudioManager.set_muted(false)
	AudioManager.set_bus_volume("Master", 0.0)
	AudioManager._on_browser_focus_changed([false])
	AudioManager._on_browser_focus_changed([true])
	_check("zero_master_survives_focus_return", AudioServer.is_bus_mute(0))
	_check("music_level_preserved", is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), linear_to_db(0.37)))
	_check("effects_level_preserved", is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")), linear_to_db(0.62)))
	AudioManager.set_bus_volume("SFX", 0.0)
	AudioManager.set_bus_volume("Master", 0.8)
	AudioManager._on_browser_focus_changed([false])
	AudioManager._on_browser_focus_changed([true])
	_check("zero_effects_survives_focus_return", AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")))
	_check("focus_changes_never_write_explicit_mute", SettingsManager.settings["audio"]["muted"] == false)
	SettingsManager.settings["audio"] = saved_audio
	AudioManager._muted = saved_state[0]
	AudioManager._master_silent = saved_state[1]
	AudioManager._window_focused = saved_state[2]
	for saved: Array in buses:
		AudioServer.set_bus_volume_db(saved[0], saved[1])
		AudioServer.set_bus_mute(saved[0], saved[2])

func _test_session_quiet() -> void:
	var saved_audio: Dictionary = SettingsManager.settings.get("audio", {}).duplicate(true)
	var buses: Array = []
	for name: String in ["Master", "Music", "SFX"]:
		var index := AudioServer.get_bus_index(name)
		buses.append([index, AudioServer.get_bus_volume_db(index), AudioServer.is_bus_mute(index)])
	SettingsManager.settings["audio"] = {"mute_unfocused": false, "muted": false, "master_volume": 0.8}
	var before_settings := JSON.stringify(SettingsManager.settings)
	AudioServer.set_bus_mute(0, false)
	var quiet := QuietFixture.new()
	add_child(quiet)
	_check("quiet_applied_during_ready_before_first_play", quiet._session_quiet and AudioServer.is_bus_mute(0))
	_check("quiet_query_read_once_at_startup", quiet.query_reads == 1)
	_check("native_without_web_query_keeps_existing_behavior", not AudioManager._read_session_quiet() and not AudioManager._session_quiet)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = 8000
	var samples := PackedByteArray()
	samples.resize(8000)
	samples.fill(128)
	stream.data = samples
	quiet._library = {"fixture_first": stream, "fixture_second": stream.duplicate(), "sfx_ui_select": stream.duplicate()}
	for focused: bool in [false, true]:
		for explicit_mute: bool in [false, true]:
			for volume: float in [0.0, 0.8]:
				quiet._on_browser_focus_changed([focused])
				quiet.set_muted(explicit_mute)
				quiet.set_bus_volume("Master", volume)
				_check("quiet_survives_focus_mute_volume_%s_%s_%s" % [focused, explicit_mute, volume], AudioServer.is_bus_mute(0))
	quiet.set_muted(false)
	quiet.set_bus_volume("Master", 0.8)
	quiet._on_browser_focus_changed([true])
	quiet.play_music("fixture_first", 0.0)
	_check("quiet_music_still_runs_normal_player", quiet._music_a.playing or quiet._music_b.playing)
	quiet.ui_click()
	_check("quiet_ui_click_keeps_master_muted", AudioServer.is_bus_mute(0) and quiet._sfx_next == 1)
	quiet.play_sfx_3d("sfx_ui_select", Vector3.ZERO)
	_check("quiet_positional_sfx_keeps_master_muted", AudioServer.is_bus_mute(0) and quiet._sfx_3d_next == 1)
	quiet.stop_music(0.0)
	quiet.play_music("fixture_second", 0.0)
	_check("quiet_survives_music_restart_and_focus", AudioServer.is_bus_mute(0) and quiet._current_music == "fixture_second")
	_check("quiet_actions_never_reread_query", quiet.query_reads == 1)
	_check("quiet_does_not_write_saved_settings", JSON.stringify(SettingsManager.settings) == before_settings)
	for child: Node in quiet.get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			child.stop()
			child.stream = null
	await get_tree().create_timer(0.1).timeout
	quiet.free()
	SettingsManager.settings["audio"] = saved_audio
	for saved: Array in buses:
		AudioServer.set_bus_volume_db(saved[0], saved[1])
		AudioServer.set_bus_mute(saved[0], saved[2])

func _test_movement_audio() -> void:
	var fixture := Node3D.new()
	add_child(fixture)
	var player := RunnerPlayer.new()
	fixture.add_child(player)
	player.setup({})
	var game := GameFixture.new()
	var missions := MissionCounter.new()
	game.player = player
	game.missions = missions
	game.running = true
	game._connect_player()
	player.set_input_enabled(true)
	var next := AudioManager._sfx_next
	player.jump()
	_check("real_jump_advances_audio_pool_once", AudioManager._sfx_next == (next + 1) % AudioManager.SFX_POOL_SIZE)
	var jump_player := AudioManager._sfx_pool[next]
	_check("jump_binds_existing_jump_asset", jump_player.stream == AudioManager._one_shot_stream("sfx_jump"))
	_check("jump_uses_effects_bus", jump_player.bus == &"SFX")
	_check("jump_is_nonlooping", (jump_player.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED)
	next = AudioManager._sfx_next
	player.jump()
	_check("rejected_midair_jump_no_duplicate_sound", AudioManager._sfx_next == next and missions.jumps == 1)
	player.slide()
	_check("air_slide_queues_without_early_scrape", AudioManager._sfx_next == next)
	player.position.y = 0.01
	player._advance_vertical(0.1)
	_check("landing_enters_slide_and_plays_once", player.state == RunnerPlayer.State.SLIDE and AudioManager._sfx_next == (next + 1) % AudioManager.SFX_POOL_SIZE and missions.slides == 1)
	var slide_player := AudioManager._sfx_pool[next]
	_check("slide_binds_distinct_existing_scrape", slide_player.stream == AudioManager._one_shot_stream("sfx_slide") and slide_player.stream != jump_player.stream)
	_check("slide_uses_effects_bus_nonlooping", slide_player.bus == &"SFX" and (slide_player.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED)
	next = AudioManager._sfx_next
	player.slide()
	_check("slide_refresh_does_not_layer_scrapes", AudioManager._sfx_next == next and missions.slides == 1)
	player.jump()
	_check("jump_from_slide_has_one_sound", AudioManager._sfx_next == (next + 1) % AudioManager.SFX_POOL_SIZE and missions.jumps == 2)
	game.running = false
	next = AudioManager._sfx_next
	game._on_player_jumped()
	game._on_player_slid()
	_check("inactive_run_handlers_do_not_play_audio", AudioManager._sfx_next == next)
	player.state = RunnerPlayer.State.DEAD
	player.slide()
	_check("dead_slide_has_no_audio", AudioManager._sfx_next == next)
	for audio_player: AudioStreamPlayer in AudioManager._sfx_pool:
		audio_player.stop()
		audio_player.stream = null
	game.player = null
	game.free()
	fixture.queue_free()

func _check(label: String, condition: bool) -> void:
	if condition:
		passed += 1
		print("[audio_focus_runner] PASS " + label)
	else:
		failed += 1
		push_error("[audio_focus_runner] FAIL " + label)
