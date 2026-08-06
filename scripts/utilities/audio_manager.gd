extends Node
## Music crossfade, pooled SFX playback, bus volume control.

const SFX_POOL_SIZE: int = 14
const SFX_3D_POOL_SIZE: int = 10
const AUDIO_DIR: String = "res://assets/audio/"

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_active_a: bool = true
var _current_music: String = ""
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_3d_pool: Array[AudioStreamPlayer3D] = []
var _sfx_next: int = 0
var _sfx_3d_next: int = 0
var _library: Dictionary = {}
var _missing_reported: Dictionary = {}
var _muted: bool = false
var _fade_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_a = AudioStreamPlayer.new()
	_music_b = AudioStreamPlayer.new()
	for player: AudioStreamPlayer in [_music_a, _music_b]:
		player.bus = &"Music"
		add_child(player)
	for i: int in SFX_POOL_SIZE:
		var sfx := AudioStreamPlayer.new()
		sfx.bus = &"SFX"
		add_child(sfx)
		_sfx_pool.append(sfx)
	for i: int in SFX_3D_POOL_SIZE:
		var sfx3d := AudioStreamPlayer3D.new()
		sfx3d.bus = &"SFX"
		sfx3d.max_distance = 60.0
		add_child(sfx3d)
		_sfx_3d_pool.append(sfx3d)
	_scan_library()


func _scan_library() -> void:
	_library.clear()
	var dir := DirAccess.open(AUDIO_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var base := file_name.trim_suffix(".import")
			if base.ends_with(".wav") or base.ends_with(".ogg"):
				var key := base.get_basename()
				if not _library.has(key):
					_library[key] = AUDIO_DIR + base
		file_name = dir.get_next()
	dir.list_dir_end()


func has_sound(name_key: String) -> bool:
	return _library.has(name_key)


func _get_stream(name_key: String) -> AudioStream:
	if not _library.has(name_key):
		if not _missing_reported.has(name_key):
			_missing_reported[name_key] = true
		return null
	var value: Variant = _library[name_key]
	if value is String:
		var stream: AudioStream = load(value)
		_library[name_key] = stream
		return stream
	return value


## --- Music ----------------------------------------------------------------

func play_music(name_key: String, fade_time: float = 1.2) -> void:
	if _current_music == name_key:
		return
	var stream := _get_stream(name_key)
	if stream == null:
		return
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			# Frame size depends on the actual format/channel layout — the old
			# /4 assumed 16-bit stereo and mis-looped mono or 8-bit sources.
			var bytes_per_sample := 2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1
			var channels := 2 if wav.stereo else 1
			wav.loop_end = wav.data.size() / (bytes_per_sample * channels)
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_current_music = name_key
	var incoming := _music_b if _music_active_a else _music_a
	var outgoing := _music_a if _music_active_a else _music_b
	_music_active_a = not _music_active_a
	incoming.stream = stream
	incoming.volume_db = -40.0
	incoming.play()
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween().set_parallel(true)
	_fade_tween.tween_property(incoming, "volume_db", 0.0, fade_time)
	if outgoing.playing:
		_fade_tween.tween_property(outgoing, "volume_db", -40.0, fade_time)
		_fade_tween.chain().tween_callback(outgoing.stop)


func stop_music(fade_time: float = 0.8) -> void:
	_current_music = ""
	for player: AudioStreamPlayer in [_music_a, _music_b]:
		if player.playing:
			var tween := create_tween()
			tween.tween_property(player, "volume_db", -40.0, fade_time)
			tween.tween_callback(player.stop)


## --- SFX ------------------------------------------------------------------

func play_sfx(name_key: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	var stream := _get_stream(name_key)
	if stream == null:
		return
	var player := _sfx_pool[_sfx_next]
	_sfx_next = (_sfx_next + 1) % SFX_POOL_SIZE
	player.stream = stream
	player.pitch_scale = pitch
	player.volume_db = volume_db
	player.play()


func play_sfx_varied(name_key: String, volume_db: float = 0.0) -> void:
	play_sfx(name_key, randf_range(0.92, 1.08), volume_db)


func play_sfx_3d(name_key: String, position: Vector3, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	var stream := _get_stream(name_key)
	if stream == null:
		return
	var player := _sfx_3d_pool[_sfx_3d_next]
	_sfx_3d_next = (_sfx_3d_next + 1) % SFX_3D_POOL_SIZE
	player.global_position = position
	player.stream = stream
	player.pitch_scale = pitch
	player.volume_db = volume_db
	player.play()


func ui_hover() -> void:
	play_sfx("sfx_ui_hover", 1.0, -8.0)


func ui_click() -> void:
	ensure_unmuted()
	play_sfx("sfx_ui_select", 1.0, -4.0)


## --- Buses ----------------------------------------------------------------

func set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0001, 1.0)))
	AudioServer.set_bus_mute(idx, linear <= 0.001 or (_muted and bus_name == "Master"))


func set_muted(muted: bool) -> void:
	_muted = muted
	AudioServer.set_bus_mute(0, muted)


func _notification(what: int) -> void:
	if GameConfig.is_headless():
		return
	# Browsers duck background tabs themselves, and on mobile web FOCUS_IN
	# often never re-fires after load — focus-muting there leaves the game
	# permanently silent. Web builds skip it entirely.
	if OS.has_feature("web"):
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if bool(SettingsManager.get_setting("audio", "mute_unfocused")):
			AudioServer.set_bus_mute(0, true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		AudioServer.set_bus_mute(0, _muted or bool(SettingsManager.get_setting("audio", "muted")))


## Re-assert the user's mute setting; safe to call from any input handler.
## On web this also doubles as an in-gesture audio poke so the browser's
## suspended AudioContext resumes with sound actually audible.
func ensure_unmuted() -> void:
	if GameConfig.is_headless():
		return
	AudioServer.set_bus_mute(0, _muted or bool(SettingsManager.get_setting("audio", "muted")))
