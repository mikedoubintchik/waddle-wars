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
var _governor_steps: int = 0
## How far the web render scale has been walked down by the governor.
var _render_scale_step: int = 0
## True only while apply_all() replays every setting at startup. Anything that
## must happen on a real user gesture checks it.
var _booting: bool = false
var _governor_fps_sum: float = 0.0
var _governor_fps_count: int = 0
## Consecutive healthy windows, counted toward giving resolution back.
var _governor_good_windows: int = 0
## Samples still to discard after a course load (see GOVERNOR_WARMUP_SAMPLES).
var _governor_warmup: int = GOVERNOR_WARMUP_SAMPLES
## Instance identity and readiness edge of the gameplay target being sampled.
## A new race, retry countdown, death, loader, or pause invalidates any partial
## window instead of donating its frames to the next playable interval.
var _governor_target_id: int = 0
var _governor_target_ready: bool = false
## Target lookup is cached by SceneTree.current_scene identity. Race managers
## appear only after their staged course build, so a CourseBase is a temporary
## fallback; while that fallback is cached, only the current scene's direct
## child count is polled. Once a gameplay manager is found there are no more
## recursive tree walks for that scene.
var _governor_cached_scene_id: int = 0
var _governor_cached_scene_child_count: int = -1
var _governor_cached_target: Node = null
var _governor_target_scan_count: int = 0
var _governor_monitoring: bool = false
## Distinguishes a real production adaptation from the long-standing QA seam
## that disables the governor by assigning `_governor_steps = GOVERNOR_MAX_STEPS`
## before any gameplay sample. Production never stops monitoring at the floor.
var _governor_has_adapted: bool = false


## Read-only shared copy of default_settings(), built once. get_setting() is
## called every frame by several systems and every miss used to rebuild the
## whole nested dictionary, which is exactly the per-frame allocation the spec
## forbids on mobile. default_settings() still hands out a fresh mutable copy
## for callers that edit it.
static var _defaults_frozen: Dictionary = {}


static func frozen_defaults() -> Dictionary:
	if _defaults_frozen.is_empty():
		var built: Dictionary = default_settings()
		for section: Variant in built.keys():
			var sect: Dictionary = built[section]
			sect.make_read_only()
		built.make_read_only()
		_defaults_frozen = built
	return _defaults_frozen


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
			# On by default: leaning is the nicer way to play on a phone and a
			# setting nobody discovers may as well not exist. Inert on desktop
			# (PlayerController gates on TiltSteering.supported()).
			"tilt_steering": true,
			"tilt_sensitivity": 1.0,
			"tilt_seen": false,       # one-time "leaning steers" notice
			"tilt_invert": false,
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
		"controls_meta": {"version": 0},
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
	return frozen_defaults().get(section, {}).get(key)


func set_setting(section: String, key: String, value: Variant) -> void:
	var explicit_quality := section == "display" and key == "quality_preset"
	if explicit_quality:
		# Explicit user choice wins over every session-only adaptation, including
		# render-scale and AA steps. A fresh readiness warmup may adapt again only
		# after measuring the newly requested tier in real gameplay.
		_reset_governor_for_user_quality()
	if not settings.has(section):
		settings[section] = {}
	settings[section][key] = value
	_apply_one(section, key, value)
	if explicit_quality:
		_apply_display("msaa", get_setting("display", "msaa"))
	_save_settings()
	setting_changed.emit("%s/%s" % [section, key], value)


func apply_all() -> void:
	_booting = true
	for section: String in ["display", "audio", "gameplay", "accessibility"]:
		var defaults: Dictionary = frozen_defaults()[section]
		for key: Variant in defaults.keys():
			_apply_one(section, key, get_setting(section, key))
	_booting = false
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
	_migrate_arrow_defaults()
	_binding_labels.clear()
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


## Old releases saved every action when any one key was rebound. Upgrade only
## recognized old default key sets; a deliberate custom binding stays intact.
func _migrate_arrow_defaults() -> void:
	if int(settings.get("controls_meta", {}).get("version", 0)) >= 1:
		return
	var controls: Dictionary = settings.get("controls", {})
	var legacy := {
		"steer_left": [[KEY_A, KEY_LEFT]],
		"steer_right": [[KEY_D, KEY_RIGHT]],
		"jump": [[KEY_SPACE]],
		"slide": [[KEY_CTRL, KEY_S], [KEY_CTRL, KEY_S, KEY_DOWN]],
	}
	for action: String in legacy:
		if not controls.has(action): continue
		var key_codes: Array = []
		var other: Array = []
		for entry: Dictionary in controls[action]:
			if entry.get("type") == "key": key_codes.append(int(entry.get("code", 0)))
			else: other.append(entry)
		key_codes.sort()
		var matched := false
		for old_codes: Array in legacy[action]:
			var sorted := old_codes.duplicate()
			sorted.sort()
			if key_codes == sorted: matched = true
		if not matched: continue
		var upgraded: Array = []
		for event: InputEvent in _default_bindings.get(action, []):
			if event is InputEventKey: upgraded.append(_serialize_event(event))
		upgraded.append_array(other)
		controls[action] = upgraded
	settings["controls"] = controls
	settings["controls_meta"] = {"version": 1}
	_save_settings()


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
			elif key == "tilt_steering" and bool(value) and not _booting:
				# Ask for sensor access on the toggle's own press.
				#
				# iOS grants DeviceOrientation only to a request made inside a
				# real user gesture, and it asks once. This runs synchronously
				# on the button's handler, so the gesture is still live. The
				# _booting guard matters now that the setting defaults to on:
				# apply_all() runs at startup with no gesture behind it, and
				# spending the one ask there would burn it for the session.
				TiltSteering.request_permission()
		"accessibility":
			if key == "ui_scale":
				_apply_ui_scale(float(value))
			# Other keys read live by camera / HUD / VFX systems.


## Touchscreens get an automatic boost on top of the user's UI-scale setting:
## the 1920x1080 canvas shrunk onto a phone leaves menus physically tiny.
const TOUCH_UI_BOOST: float = 1.35

## How often the design canvas is re-checked against the real window, in
## seconds. Four times a second is invisible to a player and free next to a
## frame.
const ORIENTATION_POLL: float = 0.25

var _orientation_timer: float = 0.0
## Window size the current design canvas was chosen for. Vector2i.ZERO means
## nothing has been applied yet.
var _design_basis: Vector2i = Vector2i.ZERO


## The resize signal is not enough on its own.
##
## On iOS Safari the canvas can be reported landscape-shaped for the first
## frames and then simply BE the right size, with no resize event ever firing —
## so a design canvas chosen from that first reading is never corrected. Every
## menu then lays out for a wide screen on a tall one: on a real iPhone the
## main menu ran about 40% wider than the display, slicing the Sign In button
## and the whole right-hand column off the edge. Desktop never showed it,
## because there the window genuinely resizes and the signal does fire.
##
## Polling the window shape makes the fix independent of whether the event
## arrives.
func _process(delta: float) -> void:
	# SettingsManager normally inherits the paused SceneTree. The web governor
	# switches this autoload to PROCESS_MODE_ALWAYS, so this cheap state check
	# observes even a sub-second pause and prevents samples on either side from
	# being combined. Target resolution is cached after the manager appears.
	if _governor_monitoring:
		_governor_refresh_target_state()
	if GameConfig.is_headless():
		return
	_orientation_timer += delta
	if _orientation_timer < ORIENTATION_POLL:
		return
	_orientation_timer = 0.0
	var window := get_window()
	if window == null:
		return
	if _is_portrait(window.size) == _is_portrait(_design_basis) \
			and _design_basis != Vector2i.ZERO:
		return
	_apply_ui_scale(float(get_setting("accessibility", "ui_scale")))


static func _is_portrait(size: Vector2i) -> bool:
	return size.y > size.x


## Re-applies the UI scale whenever the window changes shape, so rotating a
## phone swaps the design size with it rather than leaving a portrait device on
## a landscape canvas.
func _watch_orientation() -> void:
	if GameConfig.is_headless():
		return
	var window := get_window()
	if window == null or window.size_changed.is_connected(_on_window_resized):
		return
	window.size_changed.connect(_on_window_resized)


func _on_window_resized() -> void:
	# ui_scale lives under "accessibility", not "display" -- reading the wrong
	# section returns null and float(null) throws on every resize.
	_apply_ui_scale(float(get_setting("accessibility", "ui_scale")))


func _apply_ui_scale(user_scale: float) -> void:
	if GameConfig.is_headless():
		return
	_watch_orientation()
	var boost := TOUCH_UI_BOOST if GameConfig.has_touchscreen() or is_mobile_web() else 1.0
	var window := get_window()
	if window == null:
		return
	# With canvas_items stretch, Godot recomputes content_scale_factor on
	# every resize — writing it is a no-op. Shrinking the design size is the
	# reliable lever: smaller content_scale_size => larger on-screen UI.
	var scale := clampf(user_scale, 0.8, 1.6) * boost
	# Orientation-aware design size. The canvas is scaled by the narrow axis,
	# so a fixed 1920-wide design on a 900-wide portrait phone renders every
	# logical unit at 0.47 physical pixels: a 120-unit touch button lands near
	# 33 CSS px, well under the ~44 pt a finger needs. Turning the design size
	# on its side in portrait scales by 900/1080 instead, which is the
	# difference between a usable phone layout and a doll's-house one.
	var base := Vector2(1920.0, 1080.0)
	var win_size := window.size
	if win_size.y > win_size.x:
		base = Vector2(1080.0, 1920.0)
	window.content_scale_size = Vector2i(
		roundi(base.x / scale), roundi(base.y / scale))
	_design_basis = win_size


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
				viewport.msaa_3d = msaa_3d_mode() as Viewport.MSAA
		"fps_limit":
			Engine.max_fps = effective_fps_limit(int(value))
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
			AudioManager.refresh_focus_mute()


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
## Web starts at full native resolution and only gives it up if the device
## proves it cannot hold a frame. Shipping 0.75 unconditionally was the wrong
## trade: it bought the frame budget on every machine, including the many that
## never needed it, and made the browser visibly softer than the desktop build.
## The governor below is the safety net, and it now trims resolution before it
## touches anything the player would notice as a loss of content.
const WEB_RENDER_SCALE: Dictionary = {
	"high": 1.0,
	"medium": 0.85,
	"low": 0.7,
}
## Steps the governor walks down before it starts cutting the quality preset.
##
## The FIRST step keeps full resolution and removes MSAA's per-frame resolve.
## Compatibility/Web does not support FXAA, so this step accepts a little more
## edge aliasing while the image stays pixel-for-pixel native. Resolution only
## starts going at step 2, only after a second sustained slow window. This
## changes the 3D scene buffer, never the canvas backing size or UI resolution.
## Desktop stops at 0.72; mobile can take the final 0.62 step. Starting native
## and restoring gradually keeps healthy clients sharp without pinning a
## struggling Retina desktop to millions of unnecessary 3D fragments.
const RENDER_SCALE_STEPS: PackedFloat32Array = [1.0, 1.0, 0.85, 0.72, 0.62]
## Compatibility/Web has no supported screen-space AA path. Edge coverage is
## supplied by MSAA only while the device can afford it.
const WEB_SCREEN_SPACE_AA: int = Viewport.SCREEN_SPACE_AA_DISABLED
## Native Compatibility uses the same costly multisample resolve path as web.
## 4x produced >100 ms frames on an M2 at 1600x900 while 2x retained clean
## silhouettes and removed most pacing stalls. Mobile/Forward renderers keep
## honoring the player's full desktop setting.
const COMPATIBILITY_MAX_MSAA: int = Viewport.MSAA_2X
## macOS Compatibility cannot consistently sustain a 120 Hz swap cadence at
## the high preset: one missed refresh falls to 60 Hz, then it repeatedly
## bounces between the two. Keep "Uncapped" smooth on this fallback renderer;
## an explicit 120 FPS choice remains an opt-in and is honored unchanged.
const COMPATIBILITY_UNCAPPED_FPS: int = 60


## Effective native frame cap. Optional renderer/web arguments make the policy
## deterministic in contract tests without pretending a headless renderer is
## Compatibility. Saved/UI choice remains untouched for renderer portability.
static func effective_fps_limit(requested: int, renderer: String = "",
		web_override: int = -1) -> int:
	var effective := maxi(0, requested)
	var method := renderer if not renderer.is_empty() \
			else RenderingServer.get_current_rendering_method()
	var is_web := OS.has_feature("web") if web_override < 0 else web_override == 1
	if effective == 0 and not is_web and method == "gl_compatibility":
		return COMPATIBILITY_UNCAPPED_FPS
	return effective


## Linear scale the 3D pass should render at, for this platform and preset.
func render_scale_3d() -> float:
	if not OS.has_feature("web") or GameConfig.is_headless():
		return 1.0
	return effective_web_render_scale(_governor_render_base_tier(), _render_scale_step)


## Deterministic web 3D-buffer policy shared with headless contract tests.
## The preferred tier and UI canvas remain outside this session-only scale.
static func effective_web_render_scale(base_tier: String, render_scale_step: int) -> float:
	var base := float(WEB_RENDER_SCALE.get(base_tier, 1.0))
	# A governor step overrides the preset's own scale, never upward.
	if render_scale_step > 0:
		var stepped := RENDER_SCALE_STEPS[mini(render_scale_step, RENDER_SCALE_STEPS.size() - 1)]
		return minf(base, stepped)
	return base


## Base tier used for web render resolution. Optional mobile argument makes
## native-desktop invariants deterministic in headless contract tests.
func _governor_render_base_tier(mobile_override: int = -1) -> String:
	var tier := String(get_setting("display", "quality_preset"))
	# Desktop resolution follows the separate measured render-scale ladder, not
	# the effective scene-complexity tier. The saved preference remains intact;
	# only sustained slow windows may reduce the 3D buffer. Mobile web keeps its
	# existing preset-derived base scaling as well as the fill-rate ladder.
	if not _governor_override.is_empty() \
			and not _governor_mobile_client(mobile_override):
		tier = _saved_quality_preset()
	return tier


func _apply_web_render_scale() -> void:
	var viewport := get_viewport()
	if viewport == null or GameConfig.is_headless():
		return
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	var scale := render_scale_3d()
	viewport.scaling_3d_scale = scale
	viewport.screen_space_aa = WEB_SCREEN_SPACE_AA as Viewport.ScreenSpaceAA


## Multisample level every 3D viewport should use.
##
## A render target's sample count is part of its pipeline key, so this has to be
## one decision shared by the main viewport, the menu dioramas and BootWarmup's
## offscreen stage -- a warm-up that disagreed would link programs the real
## scenes never use, and every material would stall again on first sight.
func msaa_3d_mode() -> int:
	return effective_msaa_3d(
			String(get_setting("display", "msaa")),
			String(get_setting("display", "quality_preset")),
			_render_scale_step)


## Deterministic effective policy shared with contract tests. Most importantly,
## an explicit user `off` is authoritative on web; high quality may cap a
## requested 2x/4x mode at 2x, but may never turn disabled AA back on.
static func effective_msaa_3d(requested: String, quality: String,
		render_scale_step: int, renderer: String = "", web_override: int = -1) -> int:
	if requested == "off":
		return Viewport.MSAA_DISABLED
	var is_web := OS.has_feature("web") if web_override < 0 else web_override == 1
	# Multisampling resolves the whole colour buffer every frame, and on web that
	# buffer is already the most expensive thing in the frame. The desktop
	# default of 4x on a dpr-2 canvas was a large part of why Chrome sat one
	# notch over its frame budget, and the 3D pass is bilinear-upscaled there
	# anyway, which hides most of what MSAA would have bought.
	if is_web:
		# Web keeps 2x on the high tier: at native resolution the aliasing on
		# ice edges and track rails is exactly what made the browser build read
		# as lower fidelity than desktop. 4x is still refused -- it resolves the
		# whole buffer every frame for a difference nobody sees at this scale --
		# and any tier below high drops it entirely.
		if quality == "high" and render_scale_step == 0:
			return Viewport.MSAA_2X
		return Viewport.MSAA_DISABLED
	# Godot's Compatibility renderer resolves the whole multisampled buffer and
	# specializes pipelines by sample count. Native testing showed 4x creating
	# large frame-time spikes even when average GPU load was otherwise healthy.
	# Keep requested setting in save/UI for renderer portability; cap only the
	# effective mode in this renderer.
	var method := renderer if not renderer.is_empty() \
			else RenderingServer.get_current_rendering_method()
	if method == "gl_compatibility":
		return COMPATIBILITY_MAX_MSAA
	match requested:
		"4x":
			return Viewport.MSAA_4X
		_:
			return Viewport.MSAA_2X


## Whether a scene may enable Environment glow.
##
## Glow is not one pass: it downsamples and blurs the frame across several
## levels, so it scales with the same buffer that already costs the most on
## web. It stays on for desktop and for web clients still on the 'high' tier,
## and the governor below takes it away as soon as one proves it cannot hold a
## frame rate. Every environment builder must ask through here, including
## BootWarmup -- glow changes the shader program set, so a warm-up that
## disagreed with the real scene would warm the wrong programs.
func glow_allowed() -> bool:
	if GameConfig.is_headless():
		return false
	if String(get_setting("display", "particle_quality")) == "low":
		return false
	if OS.has_feature("web"):
		return String(get_setting("display", "quality_preset")) == "high"
	return true


## --- Web auto-quality governor ---------------------------------------------

const GOVERNOR_SAMPLE_WINDOW: int = 8  # mobile seconds of 1 Hz samples per decision
## Desktop runs commonly end after 9–17 seconds. The mobile 3+8 sample delay
## never reached a render-scale fallback in those runs. Desktop takes one full
## 4-second window after a 1-second readiness warmup, then one step per window.
const GOVERNOR_DESKTOP_SAMPLE_WINDOW: int = 4
## A web client pinned at 30 fps is not "playing badly", it is one notch over
## its frame budget and being halved by vsync -- exactly the case this governor
## exists to rescue. The old 22 fps trigger sat below that, so it never fired on
## the most common failure. 45 catches a halved 60 Hz client while staying clear
## of a healthy one.
const GOVERNOR_MIN_FPS: float = 45.0
## Desktop's 45–56 FPS dead band could leave a Retina client below its 57 FPS
## acceptance target indefinitely. Require sustained <54, not a single hitch;
## 57 FPS and two complete windows are still required before each recovery.
const GOVERNOR_DESKTOP_MIN_FPS: float = 54.0
## Comfortably above the trigger, so restoring resolution cannot immediately
## re-trip the governor and leave the image oscillating.
const GOVERNOR_RESTORE_FPS: float = 57.0
## Consecutive healthy windows before resolution is given back. One good window
## is noise (a shader finally linked, the tab regained focus); two is a trend.
const GOVERNOR_RESTORE_WINDOWS: int = 2
## Samples discarded after a course loads. The first seconds of a race are
## shader links and streaming, not steady-state cost, and judging the whole
## session on them was permanently softening healthy clients.
const GOVERNOR_WARMUP_SAMPLES: int = 3
const GOVERNOR_DESKTOP_WARMUP_SAMPLES: int = 1
## Desktop keeps more detail than the mobile floor, but still has a fill-rate
## escape hatch: 0.72 renders about 52% of native 3D pixels. MSAA-off remains
## the first action; each lower scale requires another full slow window.
const GOVERNOR_DESKTOP_RENDER_STEP_FLOOR: int = 3
## high -> medium -> low, at most.
const GOVERNOR_MAX_STEPS: int = 2
const GOVERNOR_QUALITY_ORDER: PackedStringArray = ["low", "medium", "high"]

## Browsers vary wildly: the desktop 'high' profile can melt a phone GPU while
## looking fine in Chrome on an M-series Mac. On web builds only, sample the
## FPS at 1 Hz while a race course OR the standalone runner is playable. Mobile
## retains its 8-sample <45 FPS policy; desktop uses 4 samples and <54 FPS.
## The override is applied through the normal _apply_one path but never saved:
## settings.json keeps the user's own choice, healthy play restores toward it,
## and a manual quality change clears every session-only step immediately.
func _start_web_governor() -> void:
	if not OS.has_feature("web") or GameConfig.is_headless():
		return
	_governor_monitoring = true
	# Pause is itself a readiness edge. Both this node and its timer must keep
	# processing while SceneTree.paused, otherwise a short pause can bridge two
	# halves of one FPS window without ever being observed.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var timer := Timer.new()
	timer.name = "QualityGovernor"
	timer.wait_time = 1.0
	timer.autostart = true
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	timer.timeout.connect(_governor_tick.bind(timer))
	add_child(timer)


func _governor_tick(timer: Timer) -> void:
	# Existing fixed-tier QA probes set this exact untouched state to suspend the
	# production governor. A real client that reached its floor has adapted and
	# remains monitored so later healthy windows can restore quality.
	if _governor_steps >= GOVERNOR_MAX_STEPS and not _governor_has_adapted \
			and _governor_override.is_empty() and _render_scale_step == 0:
		_governor_monitoring = false
		timer.stop()
		timer.queue_free()
		return
	# Refresh once more at sample time in case Timer dispatch precedes this
	# node's _process callback for the frame. Cached resolution makes this O(1).
	_governor_refresh_target_state()
	if not _governor_target_ready:
		return
	_governor_record_sample(Engine.get_frames_per_second())


## Records one 1 Hz sample only after readiness has remained stable. Kept
## separate from Timer/Engine reads for deterministic state-machine coverage.
func _governor_record_sample(fps: float, mobile_override: int = -1,
		apply_render_changes: bool = true) -> void:
	if not _governor_target_ready:
		return
	if _governor_warmup > 0:
		_governor_warmup -= 1
		return
	_governor_fps_sum += fps
	_governor_fps_count += 1
	var sample_window := GOVERNOR_SAMPLE_WINDOW if _governor_mobile_client(mobile_override) \
			else GOVERNOR_DESKTOP_SAMPLE_WINDOW
	if _governor_fps_count < sample_window:
		return
	var average := _governor_fps_sum / float(_governor_fps_count)
	_governor_fps_sum = 0.0
	_governor_fps_count = 0
	_governor_apply_average(average, mobile_override, apply_render_changes)


## Applies one complete steady-state window. Kept separate from Timer/Engine
## reads so the quality state machine has deterministic headless coverage.
func _governor_apply_average(average: float, mobile_override: int = -1,
		apply_render_changes: bool = true) -> void:
	var mobile_client := _governor_mobile_client(mobile_override)
	var minimum_fps := GOVERNOR_MIN_FPS if mobile_client else GOVERNOR_DESKTOP_MIN_FPS
	if average >= minimum_fps:
		# Restore in reverse order after two healthy windows: effective preset
		# first, then render scale/MSAA. Neither change touches the saved user tier.
		if _governor_has_degradation() and average >= GOVERNOR_RESTORE_FPS:
			_governor_good_windows += 1
			if _governor_good_windows >= GOVERNOR_RESTORE_WINDOWS:
				_governor_good_windows = 0
				_governor_recover_one(apply_render_changes)
		else:
			_governor_good_windows = 0
		return
	_governor_good_windows = 0
	# Step 1 drops MSAA while retaining native pixels. Further sustained slow
	# windows lower only the 3D buffer, with a less aggressive desktop floor.
	# The page-owned canvas and HUD stay native; saved preferences never change.
	var scale_floor := RENDER_SCALE_STEPS.size() - 1 \
		if mobile_client \
		else mini(GOVERNOR_DESKTOP_RENDER_STEP_FLOOR, RENDER_SCALE_STEPS.size() - 1)
	if _render_scale_step < scale_floor:
		_render_scale_step += 1
		_governor_has_adapted = true
		if apply_render_changes:
			_apply_web_render_scale()
			_apply_display("msaa", get_setting("display", "msaa"))
		return
	_governor_lower_quality(apply_render_changes)


func _governor_lower_quality(apply_render_changes: bool) -> bool:
	var current_rank := GOVERNOR_QUALITY_ORDER.find(String(get_setting(
			"display", "quality_preset")))
	if current_rank <= 0:
		return false
	var next_rank := current_rank - 1
	_governor_override = GOVERNOR_QUALITY_ORDER[next_rank]
	_governor_steps = clampi(
			_governor_quality_rank(_saved_quality_preset()) - next_rank,
			0, GOVERNOR_MAX_STEPS)
	_governor_has_adapted = true
	if apply_render_changes:
		_apply_one("display", "quality_preset", _governor_override)
		# Shadow/particle settings remain independent today. This governor fix does
		# not redesign that preset contract; current scenes retain those authored
		# nodes until a separately reviewed live-quality migration exists.
		setting_changed.emit("display/quality_preset", _governor_override)
	return true


func _governor_recover_one(apply_render_changes: bool) -> void:
	if not _governor_override.is_empty():
		var saved_rank := _governor_quality_rank(_saved_quality_preset())
		var current_rank := _governor_quality_rank(_governor_override)
		var next_rank := mini(current_rank + 1, saved_rank)
		_governor_override = "" if next_rank >= saved_rank \
				else GOVERNOR_QUALITY_ORDER[next_rank]
		_governor_steps = maxi(saved_rank - next_rank, 0)
		var effective := String(get_setting("display", "quality_preset"))
		if apply_render_changes:
			_apply_one("display", "quality_preset", effective)
			setting_changed.emit("display/quality_preset", effective)
	elif _render_scale_step > 0:
		_render_scale_step -= 1
		if apply_render_changes:
			_apply_web_render_scale()
			_apply_display("msaa", get_setting("display", "msaa"))
	if not _governor_has_degradation():
		_governor_steps = 0
		_governor_has_adapted = false


func _governor_has_degradation() -> bool:
	return not _governor_override.is_empty() or _render_scale_step > 0


func _saved_quality_preset() -> String:
	var display: Dictionary = settings.get("display", {})
	return String(display.get("quality_preset", frozen_defaults()["display"]["quality_preset"]))


static func _governor_quality_rank(tier: String) -> int:
	return maxi(GOVERNOR_QUALITY_ORDER.find(tier), 0)


func _governor_mobile_client(mobile_override: int = -1) -> bool:
	if mobile_override >= 0:
		return mobile_override == 1
	return GameConfig.has_touchscreen() or is_mobile_web()


func _reset_governor_sampling(mobile_override: int = -1) -> void:
	_governor_fps_sum = 0.0
	_governor_fps_count = 0
	_governor_good_windows = 0
	_governor_warmup = GOVERNOR_WARMUP_SAMPLES if _governor_mobile_client(mobile_override) \
			else GOVERNOR_DESKTOP_WARMUP_SAMPLES


func _reset_governor_for_user_quality() -> void:
	_governor_override = ""
	_governor_steps = 0
	_render_scale_step = 0
	_governor_has_adapted = false
	_reset_governor_sampling()


## Cheap every-frame edge detector. A pause shorter than the 1 Hz Timer period
## still resets the partial window because SettingsManager processes while
## paused. No Dictionary is allocated on this production path.
func _governor_refresh_target_state() -> void:
	var tree := get_tree()
	if tree == null:
		_governor_observe_target_state(0, false)
		return
	var target := _governor_resolve_target(tree.current_scene)
	var target_id := target.get_instance_id() if target != null else 0
	var ready := _quality_governor_target_ready(
			target, tree.paused, SceneRouter.is_busy())
	_governor_observe_target_state(target_id, ready)


func _governor_observe_target_state(target_id: int, ready: bool, mobile_override: int = -1) -> void:
	if target_id == _governor_target_id and ready == _governor_target_ready:
		return
	_governor_target_id = target_id
	_governor_target_ready = ready
	_reset_governor_sampling(mobile_override)


## Resolve once per current scene, then validate one cached Node. Race scenes
## stage CourseBase before creating their manager; while that temporary course
## fallback is cached, only direct-child-count changes trigger a new DFS.
func _governor_resolve_target(root: Node) -> Node:
	if root == null:
		_governor_cached_scene_id = 0
		_governor_cached_scene_child_count = -1
		_governor_cached_target = null
		return null
	var root_id := root.get_instance_id()
	var child_count := root.get_child_count()
	var needs_scan := root_id != _governor_cached_scene_id
	if not needs_scan and _governor_cached_target != null:
		needs_scan = not is_instance_valid(_governor_cached_target) \
				or not _governor_cached_target.is_inside_tree() \
				or (_governor_cached_target != root \
					and not root.is_ancestor_of(_governor_cached_target))
	# A stable non-gameplay scene stays O(1). A staged race is rescanned only
	# when Race adds another direct child; manager creation is one such edge.
	if not needs_scan and (_governor_cached_target == null \
			or _governor_cached_target is CourseBase):
		needs_scan = child_count != _governor_cached_scene_child_count
	if needs_scan:
		_governor_cached_scene_id = root_id
		_governor_cached_scene_child_count = child_count
		_governor_cached_target = _find_governed_target(root)
		_governor_target_scan_count += 1
	return _governor_cached_target


## True while a scene whose rendering cost we govern is live.
##
## Race courses already share the `course` group. Waddle Run intentionally
## imports none of CourseBase, so making it join that gameplay-specific group
## would couple two otherwise independent modes. Recognising its packed-scene
## root keeps that boundary intact while putting both modes behind the same web
## quality safety net. The nested lookup also covers test harnesses, which mount
## the real runner below their own scene root.
func _quality_governor_gameplay_active() -> bool:
	var tree := get_tree()
	if tree != null and _governor_resolve_target(tree.current_scene) != null:
		return true
	# Compatibility for existing course-group callers/tests. Sampling itself uses
	# typed manager readiness below and never treats this fallback as measurable.
	if tree == null:
		return false
	if tree.get_first_node_in_group(&"course") != null:
		return true
	return _is_quality_governed_scene(tree.current_scene)


func _is_quality_governed_scene(root: Node) -> bool:
	if root == null:
		return false
	return int(_quality_governor_target_for(root, false, false).get("identity", 0)) != 0


func _quality_governor_sample_target() -> Dictionary:
	var tree := get_tree()
	if tree == null:
		return {"identity": 0, "ready": false}
	var target := _governor_resolve_target(tree.current_scene)
	return {"identity": target.get_instance_id() if target != null else 0,
		"ready": _quality_governor_target_ready(
			target, tree.paused, SceneRouter.is_busy())}


## Typed gameplay readiness only: no node-name or scene-path inference. The
## helper accepts pause/presentation state explicitly for deterministic tests.
static func _quality_governor_target_for(root: Node, tree_paused: bool,
		presentation_blocked: bool) -> Dictionary:
	var target := _find_governed_target(root)
	return {"identity": target.get_instance_id() if target != null else 0,
		"ready": _quality_governor_target_ready(
			target, tree_paused, presentation_blocked)}


## One DFS for every governed type. Manager targets outrank the CourseBase
## fallback even if the course is visited first.
static func _find_governed_target(root: Node) -> Node:
	if root == null:
		return null
	if root is RunnerGame or root is TutorialManager or root is RaceManager:
		return root
	var fallback: Node = root if root is CourseBase else null
	for child_index: int in root.get_child_count():
		var found := _find_governed_target(root.get_child(child_index))
		if found == null:
			continue
		if not found is CourseBase:
			return found
		if fallback == null:
			fallback = found
	return fallback


static func _quality_governor_target_ready(target: Node, tree_paused: bool,
		presentation_blocked: bool) -> bool:
	if target == null or tree_paused or presentation_blocked:
		return false
	if target is RunnerGame:
		var runner := target as RunnerGame
		return runner.build_finished and runner._presentation_started \
				and runner.running and not runner._dead
	if target is TutorialManager:
		var tutorial := target as TutorialManager
		return tutorial._spawn_ready and tutorial._presentation_started \
				and not tutorial._finished
	if target is RaceManager:
		var manager := target as RaceManager
		var ready := manager._grid_placed and manager._presentation_started \
				and manager.started and not manager._completed
		if manager is EndlessManager:
			ready = ready and not (manager as EndlessManager)._ended
		return ready
	return false


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
			# MSAA off rather than 2x. Multisampling on a mobile tiler costs
			# bandwidth proportional to the sample count over the whole frame,
			# and a phone is already spending its entire budget on a ~1.2
			# megapixel canvas. The governor's first quality step is exactly
			# this trade — drop MSAA, keep full resolution, cover the edges
			# with FXAA — so phones simply start where it would have put them.
			display["msaa"] = "off"


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
