extends Node
## Synthetic resources only: no audio file loading, playback, or web latency
## claim. Actual Chrome loading/contact timings require a separate gate.

class AudioFixture:
	extends "res://scripts/utilities/audio_manager.gd"

	var stream_lookups: int = 0

	func _get_stream(key: String) -> AudioStream:
		stream_lookups += 1
		return super._get_stream(key)


var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check("isolated_fixture_requires_headless", GameConfig.is_headless())
	if not GameConfig.is_headless():
		get_tree().quit(1)
		return
	for looping: bool in [false, true]:
		var wav := AudioStreamWAV.new()
		wav.data = PackedByteArray([0, 0, 0, 0])
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if looping else AudioStreamWAV.LOOP_DISABLED
		_test_stream("wav_%s" % looping, wav, looping)
		var ogg := AudioStreamOggVorbis.new()
		ogg.loop = looping
		_test_stream("ogg_%s" % looping, ogg, looping)
	_test_missing_key()
	_test_runner_inventory_and_boundary()
	await _test_headless_skip()
	print("[runner_audio_warmup] %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _test_stream(key: String, source: AudioStream, looping: bool) -> void:
	# Do not add to the tree: no _ready scan, pooled players, mixer, or real IO.
	var audio := AudioFixture.new()
	audio._library[key] = source
	var unrelated := AudioStreamWAV.new()
	audio._library["unrelated"] = unrelated
	audio.preload_sfx(key)
	var warmed := audio._one_shot_cache.get(key) as AudioStream
	_check("%s_cached" % key, warmed != null)
	_check("%s_copy_only_if_looping" % key,
		(warmed != source) if looping else (warmed == source))
	_check("%s_non_looping" % key, warmed != null and not _is_looping(warmed))
	_check("%s_source_preserved" % key,
		audio._library[key] == source and _is_looping(source) == looping)
	if source is AudioStreamWAV:
		var warmed_wav := warmed as AudioStreamWAV
		_check("%s_samples_preserved" % key,
			warmed_wav != null and warmed_wav.data == (source as AudioStreamWAV).data)
	else:
		_check("%s_stream_type_preserved" % key, warmed is AudioStreamOggVorbis)
	audio.preload_sfx(key)
	_check("%s_repeat_reuses_exact_cache" % key,
		audio._one_shot_stream(key) == warmed and audio.stream_lookups == 1)
	_check("%s_no_playback_pool_or_unrelated_mutation" % key,
		audio.get_child_count() == 0 and audio._sfx_next == 0 and audio._sfx_3d_next == 0
		and audio._sfx_pool.is_empty() and audio._sfx_3d_pool.is_empty()
		and audio._library["unrelated"] == unrelated
		and not audio._one_shot_cache.has("unrelated") and not audio._muted)
	audio.free()


func _test_missing_key() -> void:
	var audio := AudioFixture.new()
	audio.preload_sfx("missing")
	audio.preload_sfx("missing")
	_check("missing_key_not_cached", audio._one_shot_cache.is_empty())
	_check("missing_key_diagnostic_deduplicated", audio._missing_reported.size() == 1
		and audio._missing_reported.has("missing"))
	_check("missing_key_no_library_or_playback_mutation", audio._library.is_empty()
		and audio.get_child_count() == 0 and audio._sfx_next == 0 and audio._sfx_3d_next == 0)
	audio.free()


func _test_runner_inventory_and_boundary() -> void:
	var game_source := FileAccess.get_file_as_string("res://scripts/runner/runner_game.gd")
	var hud_source := FileAccess.get_file_as_string("res://scripts/ui/runner_hud.gd")
	var player_source := FileAccess.get_file_as_string("res://scripts/runner/runner_player.gd")
	var theme_source := FileAccess.get_file_as_string("res://scripts/ui/ui_theme.gd")
	var audio_source := FileAccess.get_file_as_string("res://scripts/utilities/audio_manager.gd")
	_check("runtime_sources_present", not game_source.is_empty() and not hud_source.is_empty()
		and not player_source.is_empty() and not theme_source.is_empty() and not audio_source.is_empty())
	# Exclude the inventory constant itself; adding an un-warmed gameplay sound
	# must fail coverage rather than finding that same key in its declaration.
	var runtime_game := game_source.substr(game_source.find("func _ready()"))
	var ui_feedback := _function_source(audio_source, "ui_hover") \
		+ _function_source(audio_source, "ui_click")
	var regex := RegEx.new()
	_check("sound_key_regex_valid", regex.compile("\"(sfx_[a-z0-9_]+)\"") == OK)
	var used: Dictionary = {}
	for match_result: RegExMatch in regex.search_all(runtime_game + hud_source + player_source + ui_feedback):
		used[match_result.get_string(1)] = true
	var configured: Dictionary = {}
	for key: String in RunnerGame.RUNNER_SFX_KEYS:
		configured[key] = true
		_check("inventory_key_used_%s" % key, used.has(key))
		# The autoload scans names without loading audio. Catch missing packaged
		# resources too; source coverage alone would allow silent missing sounds.
		_check("inventory_key_available_%s" % key, AudioManager.has_sound(key))
	_check("all_runner_event_and_button_sounds_covered", used == configured)
	_check("inventory_has_no_duplicates_or_global_preload", configured.size() == 13
		and RunnerGame.RUNNER_SFX_KEYS.size() == configured.size())
	_check("shared_buttons_use_audited_feedback", theme_source.contains("connect(AudioManager.ui_hover)")
		and theme_source.contains("connect(AudioManager.ui_click)"))
	var ready_source := _function_source(game_source, "_ready")
	var warm_position := ready_source.find("await _warm_runner_audio()")
	_check("warmup_precedes_countdown_release", warm_position >= 0
		and warm_position < ready_source.find("build_finished = true")
		and warm_position < ready_source.find("_build_environment()"))
	var warm_source := _function_source(game_source, "_warm_runner_audio")
	_check("one_sound_per_stage", warm_source.contains("for key: String in RUNNER_SFX_KEYS:")
		and warm_source.contains("AudioManager.preload_sfx(key)\n\t\tawait _stage()")
		and warm_source.count("await _stage()") == 1)
	_check("ordinary_retry_does_not_rewarm", not _function_source(game_source, "restart").contains("_warm_runner_audio"))
	_check("hit_uses_existing_collision_sound", _function_source(game_source, "_on_hit_taken").contains('play_sfx("sfx_impact")'))
	_check("death_uses_existing_snow_impact_sound", _function_source(game_source, "_on_death").contains('play_sfx("sfx_snowball_hit")'))
	_check("preload_uses_existing_exact_one_shot_path", _function_source(audio_source, "preload_sfx").contains("_one_shot_stream(name_key)")
		and not _function_source(audio_source, "preload_sfx").contains(".play("))


func _test_headless_skip() -> void:
	var library_before := AudioManager._library.duplicate()
	var cache_before := AudioManager._one_shot_cache.duplicate()
	var game := RunnerGame.new()
	await game._warm_runner_audio()
	_check("headless_skips_sound_loading_and_copies", AudioManager._library == library_before
		and AudioManager._one_shot_cache == cache_before)
	_check("headless_warmup_does_not_release_game", not game.build_finished and not game.running)
	game.free()


func _function_source(source: String, method: String) -> String:
	var start := source.find("func %s(" % method)
	if start < 0:
		return ""
	var end := source.find("\nfunc ", start + 1)
	return source.substr(start) if end < 0 else source.substr(start, end - start)


func _is_looping(stream: AudioStream) -> bool:
	if stream is AudioStreamWAV:
		return (stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
	if stream is AudioStreamOggVorbis:
		return (stream as AudioStreamOggVorbis).loop
	return false


func _check(name: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("[runner_audio_warmup] PASS %s" % name)
	else:
		_failed += 1
		push_error("[runner_audio_warmup] FAIL %s" % name)
