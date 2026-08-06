extends Node
## Persistent settings with immediate application and headless-safe guards.

signal setting_changed(key: String, value: Variant)

const SETTINGS_PATH: String = "user://settings.json"
const SETTINGS_TMP_PATH: String = "user://settings.json.tmp"

const REMAPPABLE_ACTIONS: PackedStringArray = [
	"steer_left", "steer_right", "jump", "slide", "shove", "use_item", "pause",
]

## Godot 4 JoyButton indices -> Xbox-style labels for the rebind UI.
const JOY_BUTTON_NAMES: Dictionary = {
	JOY_BUTTON_A: "A",
	JOY_BUTTON_B: "B",
	JOY_BUTTON_X: "X",
	JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Select",
	JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_STICK: "L3",
	JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "LB",
	JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-Pad Up",
	JOY_BUTTON_DPAD_DOWN: "D-Pad Down",
	JOY_BUTTON_DPAD_LEFT: "D-Pad Left",
	JOY_BUTTON_DPAD_RIGHT: "D-Pad Right",
}

var settings: Dictionary = {}
var _default_bindings: Dictionary = {}
## action|family -> display label, rebuilt on rebind/reset.
var _binding_labels: Dictionary = {}
## Web auto-quality governor state (see _start_web_governor). The override
## lives outside `settings` so it can never reach disk — only an explicit
## user choice persists a quality change.
var _governor_override: String = ""
var _governor_stepped: bool = false
var _governor_fps_sum: float = 0.0
var _governor_fps_count: int = 0


static func default_settings() -> Dictionary:
	return {
		"display": {
			"window_mode": "windowed",  # windowed | fullscreen | borderless
			"resolution": "1600x900",
			"vsync": true,
			"quality_preset": "high",  # low | medium | high
			"shadow_quality": "high",  # off | low | medium | high
			"particle_quality": "high",  # low | medium | high
			"msaa": "4x",  # off | 2x | 4x
			"fps_limit": 0,  # 0 = uncapped
		},
		"audio": {
			"master_volume": 0.9,
			"music_volume": 0.8,
			"sfx_volume": 0.9,
			"muted": false,
			"mute_unfocused": true,
		},
		"gameplay": {
			"steer_sensitivity": 1.0,
			"vibration": true,
			"slide_toggle_mode": false,  # false = hold to slide
			"tutorial_prompts": true,
			"touch_controls": "auto",  # auto | on | off
			"touch_scale": 1.0,
			"touch_opacity": 0.55,
			"gamepad_deadzone": 0.2,
		},
		"accessibility": {
			"camera_shake": "full",  # full | reduced | off
			"high_contrast_pickups": false,
			"reduced_flashing": false,
			"colorblind_cues": false,
			"hud_scale": 1.0,
			"ui_scale": 1.0,
			"pause_on_disconnect": true,
			"audio_visual_cues": false,
		},
		"online": {
			"display_name": "",  # optional leaderboard name (server-sanitized)
		},
		"controls": {},  # action -> array of serialized input events
	}


func _ready() -> void:
	_capture_default_bindings()
	_load_settings()
	apply_all()
	_start_web_governor()


func get_setting(section: String, key: String) -> Variant:
	if section == "display" and key == "quality_preset" and _governor_override != "":
		return _governor_override
	var sect: Dictionary = settings.get(section, {})
	if sect.has(key):
		return sect[key]
	return default_settings().get(section, {}).get(key)


func set_setting(section: String, key: String, value: Variant) -> void:
	if section == "display" and key == "quality_preset":
		_governor_override = ""  # explicit user choice wins over the governor
	if not settings.has(section):
		settings[section] = {}
	settings[section][key] = value
	_apply_one(section, key, value)
	_save_settings()
	setting_changed.emit("%s/%s" % [section, key], value)


func apply_all() -> void:
	for section: String in ["display", "audio", "gameplay", "accessibility"]:
		var defaults: Dictionary = default_settings()[section]
		for key: Variant in defaults.keys():
			_apply_one(section, key, get_setting(section, key))
	_apply_control_remaps()


func touch_controls_enabled() -> bool:
	var mode: String = get_setting("gameplay", "touch_controls")
	if mode == "on":
		return true
	if mode == "off":
		return false
	# Auto: native mobile builds, any available touchscreen (covers mobile web
	# browsers via DisplayServer.is_touchscreen_available), or a web export
	# running on a phone/tablet OS in case the touchscreen probe fails.
	return GameConfig.is_mobile() or GameConfig.has_touchscreen() or is_mobile_web()


## Web export running in a browser on a mobile OS.
static func is_mobile_web() -> bool:
	return OS.has_feature("web_android") or OS.has_feature("web_ios")


## --- Control remapping ---------------------------------------------------

func rebind_action(action: String, event: InputEvent) -> void:
	_binding_labels.clear()
	if action not in REMAPPABLE_ACTIONS:
		return
	# Replace events of the same device family, keep the rest.
	var kept: Array[InputEvent] = []
	for existing: InputEvent in InputMap.action_get_events(action):
		if not _same_family(existing, event):
			kept.append(existing)
	InputMap.action_erase_events(action)
	for ev: InputEvent in kept:
		InputMap.action_add_event(action, ev)
	InputMap.action_add_event(action, event)
	_store_bindings()


func reset_bindings() -> void:
	_binding_labels.clear()
	for action: String in REMAPPABLE_ACTIONS:
		InputMap.action_erase_events(action)
		for ev: InputEvent in _default_bindings.get(action, []):
			InputMap.action_add_event(action, ev)
	settings["controls"] = {}
	_save_settings()


## Human-readable label for a binding, e.g. "Q" or "LT".
##
## Cached: HUD hints re-read the live binding every frame they are visible, and
## the lookup is neither free nor, on web, silent — see _physical_key_name().
## The cache is cleared whenever bindings actually change.
func describe_action_binding(action: String, family: String) -> String:
	var cache_key := action + "|" + family
	if _binding_labels.has(cache_key):
		return String(_binding_labels[cache_key])
	var label := _describe_action_binding_uncached(action, family)
	_binding_labels[cache_key] = label
	return label


## Maps a physical key to the label the player's layout actually prints.
##
## The web display server does not implement keyboard_get_keycode_from_physical
## and pushes an error every call; a HUD hint asking once per frame turned that
## into hundreds of console errors a second, enough to lock up devtools. Web and
## headless both fall back to the physical code's own name, which is correct for
## QWERTY and merely approximate elsewhere.
func _physical_key_name(code: int) -> String:
	if GameConfig.is_headless() or OS.has_feature("web"):
		return OS.get_keycode_string(code)
	return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(code))


func _describe_action_binding_uncached(action: String, family: String) -> String:
	for ev: InputEvent in InputMap.action_get_events(action):
		if family == "key" and ev is InputEventKey:
			var key_ev := ev as InputEventKey
			var code := key_ev.physical_keycode
			if code == KEY_NONE:
				code = key_ev.keycode
			return _physical_key_name(code)
		if family == "joy" and (ev is InputEventJoypadButton or ev is InputEventJoypadMotion):
			if ev is InputEventJoypadButton:
				var index := (ev as InputEventJoypadButton).button_index
				return String(JOY_BUTTON_NAMES.get(index, "Pad %d" % index))
			var motion := ev as InputEventJoypadMotion
			# Triggers are axes in Godot 4, not JoyButton entries.
			if motion.axis == JOY_AXIS_TRIGGER_LEFT and motion.axis_value > 0.0:
				return "LT"
			if motion.axis == JOY_AXIS_TRIGGER_RIGHT and motion.axis_value > 0.0:
				return "RT"
			return "Axis %d%s" % [motion.axis, "+" if motion.axis_value > 0.0 else "-"]
	return "—"


func _same_family(a: InputEvent, b: InputEvent) -> bool:
	var a_joy := a is InputEventJoypadButton or a is InputEventJoypadMotion
	var b_joy := b is InputEventJoypadButton or b is InputEventJoypadMotion
	return a_joy == b_joy


func _capture_default_bindings() -> void:
	for action: String in REMAPPABLE_ACTIONS:
		var events: Array[InputEvent] = []
		for ev: InputEvent in InputMap.action_get_events(action):
			events.append(ev.duplicate())
		_default_bindings[action] = events


func _store_bindings() -> void:
	var controls: Dictionary = {}
	for action: String in REMAPPABLE_ACTIONS:
		var stored: Array = []
		for ev: InputEvent in InputMap.action_get_events(action):
			var entry := _serialize_event(ev)
			if not entry.is_empty():
				stored.append(entry)
		controls[action] = stored
	settings["controls"] = controls
	_save_settings()


func _apply_control_remaps() -> void:
	var controls: Dictionary = settings.get("controls", {})
	for action: String in controls.keys():
		if action not in REMAPPABLE_ACTIONS or not InputMap.has_action(action):
			continue
		var events: Array = controls[action]
		if events.is_empty():
			continue
		InputMap.action_erase_events(action)
		for entry: Variant in events:
			var ev := _deserialize_event(entry)
			if ev != null:
				InputMap.action_add_event(action, ev)


func _serialize_event(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		var key_ev := ev as InputEventKey
		return {"type": "key", "code": int(key_ev.physical_keycode if key_ev.physical_keycode != KEY_NONE else key_ev.keycode)}
	if ev is InputEventJoypadButton:
		return {"type": "joy_button", "index": int((ev as InputEventJoypadButton).button_index)}
	if ev is InputEventJoypadMotion:
		var motion := ev as InputEventJoypadMotion
		return {"type": "joy_axis", "axis": int(motion.axis), "value": motion.axis_value}
	return {}


func _deserialize_event(entry: Variant) -> InputEvent:
	if not entry is Dictionary:
		return null
	var dict: Dictionary = entry
	match String(dict.get("type", "")):
		"key":
			var key_ev := InputEventKey.new()
			key_ev.physical_keycode = int(dict.get("code", 0)) as Key
			return key_ev
		"joy_button":
			var btn := InputEventJoypadButton.new()
			btn.button_index = int(dict.get("index", 0)) as JoyButton
			return btn
		"joy_axis":
			var motion := InputEventJoypadMotion.new()
			motion.axis = int(dict.get("axis", 0)) as JoyAxis
			motion.axis_value = float(dict.get("value", 1.0))
			return motion
	return null


## --- Application ----------------------------------------------------------

func _apply_one(section: String, key: String, value: Variant) -> void:
	if GameConfig.is_headless() and section == "display":
		return
	match section:
		"display":
			_apply_display(key, value)
		"audio":
			_apply_audio(key, value)
		"gameplay":
			if key == "gamepad_deadzone":
				for action: String in ["steer_left", "steer_right"]:
					if InputMap.has_action(action):
						InputMap.action_set_deadzone(action, clampf(float(value), 0.05, 0.6))
		"accessibility":
			if key == "ui_scale":
				_apply_ui_scale(float(value))
			# Other keys read live by camera / HUD / VFX systems.


## Touchscreens get an automatic boost on top of the user's UI-scale setting:
## the 1920x1080 canvas shrunk onto a phone leaves menus physically tiny.
const TOUCH_UI_BOOST: float = 1.35

func _apply_ui_scale(user_scale: float) -> void:
	if GameConfig.is_headless():
		return
	var boost := TOUCH_UI_BOOST if GameConfig.has_touchscreen() or is_mobile_web() else 1.0
	var window := get_window()
	if window == null:
		return
	# With canvas_items stretch, Godot recomputes content_scale_factor on
	# every resize — writing it is a no-op. Shrinking the design size is the
	# reliable lever: smaller content_scale_size => larger on-screen UI.
	var scale := clampf(user_scale, 0.8, 1.6) * boost
	window.content_scale_size = Vector2i(
		roundi(1920.0 / scale), roundi(1080.0 / scale))


func _apply_display(key: String, value: Variant) -> void:
	match key:
		"window_mode":
			match String(value):
				"fullscreen":
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
				"borderless":
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
					DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
				_:
					DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
					DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
					_apply_display("resolution", get_setting("display", "resolution"))
		"resolution":
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED and not GameConfig.is_mobile():
				var parts := String(value).split("x")
				if parts.size() == 2:
					var size := Vector2i(int(parts[0]), int(parts[1]))
					DisplayServer.window_set_size(size)
		"vsync":
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ENABLED if bool(value) else DisplayServer.VSYNC_DISABLED
			)
		"msaa":
			var viewport := get_viewport()
			if viewport != null:
				match String(value):
					"off":
						viewport.msaa_3d = Viewport.MSAA_DISABLED
					"4x":
						viewport.msaa_3d = Viewport.MSAA_4X
					_:
						viewport.msaa_3d = Viewport.MSAA_2X
		"fps_limit":
			Engine.max_fps = maxi(0, int(value))
		"quality_preset":
			# Courses read the preset live on scene load; drop VisualLibrary's
			# cached quality-derived values so the next build sees the new tier.
			VisualLibrary.reset_quality_cache()
			_apply_web_render_scale()
		"shadow_quality", "particle_quality":
			pass  # Read live by course lighting / VFX systems on scene load.


func _apply_audio(key: String, value: Variant) -> void:
	match key:
		"master_volume":
			AudioManager.set_bus_volume("Master", float(value))
		"music_volume":
			AudioManager.set_bus_volume("Music", float(value))
		"sfx_volume":
			AudioManager.set_bus_volume("SFX", float(value))
		"muted":
			AudioManager.set_muted(bool(value))
		"mute_unfocused":
			pass  # AudioManager reads this on focus notifications.


## --- Web render scale ------------------------------------------------------

## Linear 3D render scale on web, by quality preset. 1.0 elsewhere.
##
## Measured in Chrome on an M2: a race sat at exactly 30.0 fps / 33.3 ms, which
## is not a coincidental number -- it is vsync halving 60 Hz because frames land
## just over the 16.6 ms budget. The dominant cost is fill rate. The canvas runs
## at devicePixelRatio 2 (2940x1984 here), and rendering the 3D world at every
## one of those pixels through ANGLE, with MSAA and glow on top, does not fit.
##
## Scaling only the 3D pass keeps the fix off the UI: text, HUD and menus still
## rasterise at full device resolution, so this does not undo the earlier
## pixelation work. At 0.75 the world still resolves ~1.5 device pixels per CSS
## pixel -- visibly sharper than the unscaled 1.0 the build used to ship -- for
## a little over half the fragment work.
const WEB_RENDER_SCALE: Dictionary = {
	"high": 0.75,
	"medium": 0.7,
	"low": 0.6,
}


## Linear scale the 3D pass should render at, for this platform and preset.
func render_scale_3d() -> float:
	if not OS.has_feature("web") or GameConfig.is_headless():
		return 1.0
	return float(WEB_RENDER_SCALE.get(String(get_setting("display", "quality_preset")), 0.75))


func _apply_web_render_scale() -> void:
	var viewport := get_viewport()
	if viewport == null or GameConfig.is_headless():
		return
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = render_scale_3d()


## --- Web auto-quality governor ---------------------------------------------

const GOVERNOR_SAMPLE_WINDOW: int = 8  # seconds of 1 Hz samples per decision
const GOVERNOR_MIN_FPS: float = 22.0

## Browsers vary wildly: the desktop 'high' profile can melt a phone GPU while
## looking fine in Chrome on an M-series Mac. On web builds only, sample the
## FPS at 1 Hz while a course is loaded (group "course") and, if an 8-sample
## average drops below 22 FPS, step the quality preset down ONE tier for the
## rest of the session. The override is applied through the normal _apply_one
## path but never saved: settings.json keeps the user's own choice, and a
## manual quality change clears the override immediately.
func _start_web_governor() -> void:
	if not OS.has_feature("web") or GameConfig.is_headless():
		return
	var timer := Timer.new()
	timer.name = "QualityGovernor"
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_governor_tick.bind(timer))
	add_child(timer)


func _governor_tick(timer: Timer) -> void:
	if _governor_stepped:
		timer.stop()
		timer.queue_free()
		return
	if get_tree().get_first_node_in_group(&"course") == null:
		# Menus and loading screens say nothing about gameplay cost — restart
		# the sampling window whenever no course is active.
		_governor_fps_sum = 0.0
		_governor_fps_count = 0
		return
	_governor_fps_sum += Engine.get_frames_per_second()
	_governor_fps_count += 1
	if _governor_fps_count < GOVERNOR_SAMPLE_WINDOW:
		return
	var average := _governor_fps_sum / float(_governor_fps_count)
	_governor_fps_sum = 0.0
	_governor_fps_count = 0
	if average >= GOVERNOR_MIN_FPS:
		return
	var lower := ""
	match String(get_setting("display", "quality_preset")):
		"high":
			lower = "medium"
		"medium":
			lower = "low"
	_governor_stepped = true  # one step per session, even when already "low"
	if lower != "":
		_governor_override = lower
		_apply_one("display", "quality_preset", lower)
		setting_changed.emit("display/quality_preset", lower)


## --- Persistence ----------------------------------------------------------

func _load_settings() -> void:
	settings = {}
	if FileAccess.file_exists(SETTINGS_PATH):
		var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				settings = parsed
	if settings.is_empty():
		settings = default_settings()
		# Phone browsers cannot sustain the desktop 'high' profile. First run
		# only — once a settings file exists, the user's saved choices win.
		if is_mobile_web():
			var display: Dictionary = settings["display"]
			display["quality_preset"] = "medium"
			display["shadow_quality"] = "medium"
			display["particle_quality"] = "medium"
			display["msaa"] = "2x"


func _save_settings() -> void:
	var file := FileAccess.open(SETTINGS_TMP_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(settings, "\t"))
	file.close()
	DirAccess.rename_absolute(
		ProjectSettings.globalize_path(SETTINGS_TMP_PATH),
		ProjectSettings.globalize_path(SETTINGS_PATH)
	)
