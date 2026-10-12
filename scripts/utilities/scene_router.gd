extends Node
## Scene transitions with a fade overlay and an achievement toast layer.

signal scene_changed(path: String)
## Warmup nodes process ALWAYS; a tree pause alone cannot contain their work.
signal loading_recovery_started

const FADE_TIME: float = 0.35
## Thirty seconds without completed work is a stall. Native Compatibility can
## need more than thirty seconds for *advancing* shader/geometry warmup.
const WARMUP_TIMEOUT_MSEC: int = 30000
const WARMUP_MAX_TOTAL_MSEC: int = 120000
const LOADING_MESSAGES: PackedStringArray = [
	"Packing extra fish…",
	"Checking the penguin map…",
	"Polishing the ice…",
	"Gathering the fish snacks…",
]

var _overlay_layer: CanvasLayer
var _fade_rect: ColorRect
var _loading_backdrop: FrontEndBackdrop
var _loading_card: PanelContainer
var _loading_label: Label
var _loading_route: Label
var _loading_wordmark: TextureRect
var _loading_progress: ProgressBar
var _loading_mascot: PenguinLoader
var _loading_box: VBoxContainer
var _loading_recovery: VBoxContainer
var _retry_button: Button
var _back_button: Button
var _toast_layer: CanvasLayer
var _busy: bool = false
var _presenting: bool = false
var _queued_scene_path: String = ""
# History describes visited menu pages, including state inside a scene. A
# pending load owns one proposed change, committed only when its page is ready.
var _menu_history: Array[Dictionary] = []
var _pending_menu_history: Array[Dictionary] = []
var _navigation_path := ""
var _navigation_state: Dictionary = {}
var _pending_scene_path: String = ""
var _abandoned_scene_paths: Array[String] = []
var _active_scene_path: String = ""
var _transition_serial: int = 0
var _transition_tween: Tween
var _loading_deadline_msec: int = -1
var _loading_started_msec: int = -1
var _loading_work_signature: String = ""
var _scene_swapped: bool = false
var _recovery_active: bool = false
var _recovery_back_armed: bool = false
var _holds_tree_pause: bool = false
var _thread_progress: Array = []
var _from_boot: bool = false
var _mute_layer: CanvasLayer
var _mute_toast: Label = null
var _perf: PerfTicker = null


func _ready() -> void:
	# Latch an expired deadline before the -100 warmup helpers submit another
	# cold draw. This cannot interrupt a draw/resource call already in flight.
	process_priority = -200
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Arm the motion-permission request at BOOT, not on the main menu.
	#
	# Arm before the first menu gesture. Deferred so the settings autoload is
	# ready to be read when the player first interacts with the app.
	(func() -> void: TiltSteering.arm_permission_on_first_gesture(self)).call_deferred()
	# Profiling only: a frame-time line every couple of seconds, labelled with
	# the current scene, so in-game performance can be read off the console
	# instead of inferred from a browser task manager.
	_perf = PerfTicker.attach(self)
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 100
	add_child(_overlay_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.03, 0.06, 0.12, 1.0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.modulate.a = 0.0
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_layer.add_child(_fade_rect)
	_toast_layer = CanvasLayer.new()
	_toast_layer.layer = 99
	add_child(_toast_layer)
	Progression.achievement_unlocked.connect(_on_achievement_unlocked)
	_mute_layer = CanvasLayer.new()
	_mute_layer.layer = 98
	add_child(_mute_layer)


func _ensure_loading_controls() -> void:
	if _loading_card != null:
		return
	# An autoload runs before Boot can draw its minimal wordmark. Keep custom
	# fonts and hidden rich controls out of that critical path. The first
	# accepted transition builds these once, normally from warmed font caches.
	# Compact expedition card. The mascot is a cached 2D cutout with no second
	# 3D renderer. Single-threaded web loads can still block its animation.
	_loading_card = PanelContainer.new()
	_loading_card.set_anchors_preset(Control.PRESET_CENTER)
	_loading_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_loading_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_loading_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card_style := PenguinLoader.card_style()
	_loading_card.add_theme_stylebox_override("panel", card_style)
	_fade_rect.add_child(_loading_card)

	_loading_box = VBoxContainer.new()
	_loading_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_loading_box.add_theme_constant_override("separation", 8)
	_loading_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_box.modulate.a = 0.0
	_loading_box.visible = false
	_loading_card.add_child(_loading_box)
	var route := Label.new()
	_loading_route = route
	route.text = "WADDLE WARS"
	route.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	route.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	route.add_theme_font_size_override("font_size", 22)
	route.add_theme_color_override("font_color", ExpeditionMenuStyle.INK)
	route.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_box.add_child(route)
	route.visible = false
	_loading_wordmark = TextureRect.new()
	_loading_wordmark.texture = ExpeditionMenuStyle._material_texture(
		PenguinLoader.LOGO_TEXTURE_PATH)
	_loading_wordmark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_loading_wordmark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_loading_wordmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wordmark_slot := Control.new()
	wordmark_slot.name = "LoadingWordmarkSlot"
	wordmark_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_box.add_child(wordmark_slot)
	wordmark_slot.add_child(_loading_wordmark)
	# The wordmark straddles the card edge. Keep its screen alignment independent
	# of the VBox's message height and automatic minimum-size redistribution.
	_loading_wordmark.set_as_top_level(true)
	_loading_label = Label.new()
	_loading_label.text = "Preparing expedition…"
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_loading_label.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	_loading_label.add_theme_font_size_override("font_size", 22)
	_loading_label.add_theme_color_override("font_color", ExpeditionMenuStyle.INK)
	_loading_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_box.add_child(_loading_label)
	_loading_progress = ProgressBar.new()
	_loading_progress.custom_minimum_size = Vector2(320.0, 12.0)
	_loading_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loading_progress.show_percentage = false
	_loading_progress.min_value = 0.0
	_loading_progress.max_value = 1.0
	_loading_progress.value = 0.0
	var rail := StyleBoxFlat.new()
	rail.bg_color = Color(0.02, 0.05, 0.10, 0.82)
	rail.set_corner_radius_all(8)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.32, 0.88, 0.74)
	fill.set_corner_radius_all(8)
	_loading_progress.add_theme_stylebox_override("background", rail)
	_loading_progress.add_theme_stylebox_override("fill", fill)
	_loading_box.add_child(_loading_progress)
	# PenguinLoader owns the one visible forward-only milestone bar. This hidden
	# phase value remains available to QA.
	_loading_progress.visible = false
	_loading_recovery = VBoxContainer.new()
	_loading_recovery.add_theme_constant_override("separation", 8)
	_loading_recovery.visible = false
	_loading_box.add_child(_loading_recovery)
	_retry_button = ExpeditionMenuStyle.button("Retry loading", true, 20, 48.0)
	_back_button = ExpeditionMenuStyle.button("Back to Menu", false, 18, 48.0)
	for button: Button in [_retry_button, _back_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_ALL
		button.clip_text = true
		_loading_recovery.add_child(button)
	_retry_button.pressed.connect(_retry_loading)
	_back_button.pressed.connect(_back_to_menu)
	_layout_loading_card()
	get_viewport().size_changed.connect(_layout_loading_card)


func go_to(scene_path: String) -> void:
	_route_to(scene_path, false)


func go_back(fallback: String = Game.SCENE_MAIN_MENU) -> void:
	# Back cannot overtake a loading page or consume two entries from one tap.
	if is_busy():
		return
	var destination := fallback
	if not _menu_history.is_empty():
		destination = String(_menu_history.back()["path"])
	_route_to(destination, true)


func _route_to(scene_path: String, backwards: bool) -> void:
	if _busy:
		return
	if _presenting:
		# A newly entered scene may discover an invalid course and redirect to
		# the menu from _ready(). Do not lose that recovery behind the fade or
		# start overlapping transitions; first queued destination wins.
		if _queued_scene_path.is_empty():
			_queued_scene_path = scene_path
		return
	_begin_navigation(scene_path, backwards)
	_busy = true
	var current := get_tree().current_scene
	_from_boot = current != null and current.scene_file_path == "res://scenes/ui/main.tscn"
	_scene_swapped = false
	_transition_serial += 1
	_active_scene_path = scene_path
	_emit_lifecycle("loading_started", {
		"path": scene_path, "serial": _transition_serial, "route": "go_to"})
	_ensure_loading_controls()
	_reset_loading_recovery()
	get_tree().paused = false
	if GameConfig.is_headless():
		_change_now(scene_path)
		return
	_presenting = true
	_start_loading_deadline()
	_fade_rect.visible = true
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	# Loading text rides the fade so heavy scene builds (course generation,
	# first-run WebGL shader compiles) never leave an unlabeled blank screen.
	_loading_box.visible = true
	_loading_box.modulate.a = 1.0
	_set_loading_stage("Preparing expedition…", -1.0)
	_kill_transition_tween()
	# Boot and the iOS launch screen use this same artwork. Present the one
	# authored loader immediately; only later scene changes need an entry fade.
	if _from_boot:
		_fade_rect.modulate.a = 1.0
		_begin_threaded_load(scene_path, _transition_serial)
		return
	_transition_tween = create_tween()
	_transition_tween.tween_property(_fade_rect, "modulate:a", 1.0, FADE_TIME)
	_transition_tween.tween_callback(_begin_threaded_load.bind(scene_path, _transition_serial))


func _is_menu_page(path: String) -> bool:
	return path.begins_with("res://scenes/menus/") and path != Game.SCENE_RESULTS


func _begin_navigation(path: String, backwards: bool) -> void:
	_navigation_path = path
	_navigation_state = {}
	_pending_menu_history = _menu_history.duplicate(true)
	if backwards:
		if not _pending_menu_history.is_empty():
			var previous: Dictionary = _pending_menu_history.pop_back()
			_navigation_state = previous.get("state", {}).duplicate(true)
		return
	# Home is an explicit root destination. Gameplay/results never enter menu
	# history, so Retry or leaving a run cannot resurrect a previous game.
	if path == Game.SCENE_MAIN_MENU or not _is_menu_page(path):
		_pending_menu_history.clear()
		return
	var current := get_tree().current_scene
	if current == null or not _is_menu_page(current.scene_file_path) \
			or current.scene_file_path == path:
		return
	var state: Dictionary = {}
	if current.has_method("get_navigation_state"):
		state = current.call("get_navigation_state").duplicate(true)
	_pending_menu_history.append({"path": current.scene_file_path, "state": state})


func _retarget_navigation(path: String) -> void:
	# Retry reuses the transaction; recovery/redirect replaces its destination
	# without treating the failed or still-covered scene as a visited page.
	if path == _navigation_path:
		return
	_navigation_path = path
	_navigation_state = {}
	if path == Game.SCENE_MAIN_MENU or not _is_menu_page(path):
		_pending_menu_history.clear()


func _restore_navigation_after_swap(path: String, serial: int) -> void:
	await get_tree().scene_changed
	if serial != _transition_serial or path != _navigation_path:
		return
	var current := get_tree().current_scene
	if current == null or current.scene_file_path != path:
		return
	if current.has_method("restore_navigation_state"):
		current.call("restore_navigation_state", _navigation_state.duplicate(true))
	if GameConfig.is_headless():
		_commit_navigation(path)


func _commit_navigation(path: String) -> void:
	if path != _navigation_path:
		return
	_menu_history = _pending_menu_history.duplicate(true)
	_navigation_path = ""
	_navigation_state = {}


func is_busy() -> bool:
	return _busy or _presenting


## Scene swap completion precedes build/warmup and the final fade. Gameplay
## must not consume its countdown until that whole presentation has finished.
func is_presenting() -> bool:
	return _presenting


func is_loading_recovery_active() -> bool:
	return _recovery_active


## Hidden-background work is safe only under this router's fully opaque,
## full-viewport cover. Busy/presenting alone also includes the fade-in/out.
func has_opaque_loading_cover(scene_root: Node) -> bool:
	if not is_inside_tree() or not is_instance_valid(scene_root) \
			or not scene_root.is_inside_tree() or get_tree().current_scene != scene_root \
			or not _presenting or _recovery_active \
			or not is_instance_valid(_fade_rect) or not is_instance_valid(_overlay_layer) \
			or not _overlay_layer.visible \
			or _fade_rect.get_parent() != _overlay_layer \
			or not _fade_rect.is_visible_in_tree() \
			or scene_root.get_viewport() != get_viewport():
		return false
	var alpha := _fade_rect.color.a * _fade_rect.modulate.a * _fade_rect.self_modulate.a
	return alpha >= 1.0 and _fade_rect.get_global_rect().encloses(get_viewport().get_visible_rect())


## Local readiness matters for direct scene entry too (without a router fade).
## Call only while startup is pending, not every frame of active gameplay.
func is_gameplay_ready(scene_root: Node) -> bool:
	return is_instance_valid(scene_root) and BootWarmup.is_finished() \
			and not is_busy() and not _subtree_is_building(scene_root)


func _ensure_loading_presentation() -> void:
	# SceneRouter is an autoload, so constructing texture-backed Controls in
	# `_ready()` would decode them before the boot scene presents. BootWarmup
	# primes these caches after the first visible frame; create the actual nodes
	# only when the first transition asks for them.
	if GameConfig.is_headless():
		return
	_ensure_loading_controls()
	if _loading_backdrop == null:
		_loading_backdrop = FrontEndBackdrop.new()
		_loading_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
		_loading_backdrop.set_presentation(
			FrontEndBackdrop.Context.LOADING, 0.08, false)
		_fade_rect.add_child(_loading_backdrop)
		_fade_rect.move_child(_loading_backdrop, 0)
	if _loading_mascot == null:
		_loading_mascot = PenguinLoader.new(320.0)
		_loading_mascot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_loading_box.add_child(_loading_mascot)
		# The painted wordmark precedes the courier, bar, and friendly message.
		_loading_box.move_child(_loading_mascot, 2)
	_layout_loading_card()


func _process(_delta: float) -> void:
	if _from_boot and _presenting and not BootWarmup.is_finished() \
			and _loading_mascot != null:
		_loading_mascot.set_progress(BootWarmup.progress() * 0.2)
	_refresh_loading_progress()
	_poll_loading_watchdog()
	_drain_abandoned_loads()
	if _pending_scene_path.is_empty():
		return
	_thread_progress.clear()
	var status := _threaded_load_status(
		_pending_scene_path, _thread_progress)
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			var fraction := 0.0
			if not _thread_progress.is_empty():
				fraction = clampf(float(_thread_progress[0]), 0.0, 1.0)
			_set_loading_stage("Packing route assets…", fraction)
			_note_loading_work("resource:%s:%d" % [
				_pending_scene_path, floori(fraction * 100.0)])
		ResourceLoader.THREAD_LOAD_LOADED:
			var path := _pending_scene_path
			_pending_scene_path = ""
			_set_loading_stage("Opening the route…", -1.0)
			var packed := _threaded_load_result(path)
			if packed == null:
				push_error("SceneRouter: threaded load returned no PackedScene for %s" % path)
				_change_now(path)
			else:
				_change_to_packed(packed, path)
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			var path := _pending_scene_path
			_pending_scene_path = ""
			if status == ResourceLoader.THREAD_LOAD_FAILED:
				# Godot 4.7.1 retains failed request tokens too. Consume the
				# terminal result before retrying, otherwise a duplicate request
				# reuses the old failed token and increments its user count.
				_threaded_load_result(path)
			push_warning("SceneRouter: threaded load failed; retrying %s synchronously" % path)
			_change_now(path)


func _begin_threaded_load(scene_path: String, serial: int = -1) -> void:
	if serial < 0:
		serial = _transition_serial
	if not _transition_is_current(serial):
		return
	_start_loading_deadline()
	# Build texture-backed presentation only after the plain fade is opaque, so
	# an early boot-skip can never stall the first visible splash frame.
	_ensure_loading_presentation()
	_set_loading_stage("Packing route assets…", 0.0)
	# A threaded request can execute inline in a single-threaded web export.
	# Submit the authored loader first, then leave that frame's post-draw callback
	# before starting resource work. Awaiting post-draw alone resumes before the
	# browser has an opportunity to present the canvas. The next process frame
	# supplies that boundary; it does not make a synchronous load animate.
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	if not _transition_is_current(serial):
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return
	if not _transition_is_current(serial):
		return
	# _busy and _presenting stay set throughout both awaits. go_to() therefore
	# cannot start a second request while this presentation is pending.
	# Slow phones can reach the splash duration/skip before front-end uploads
	# finish. Keep that preparation alive and covered, rather than cancelling it
	# then paying its remaining first-use work in the title/menu.
	while not BootWarmup.is_finished():
		await get_tree().process_frame
		if not is_inside_tree() or not _transition_is_current(serial):
			return
	_request_threaded_load(scene_path)


func _request_threaded_load(scene_path: String) -> void:
	# Worker-enabled builds can load resource dependencies off the main thread.
	# No-thread web builds perform this request inline; instantiation is always
	# main-thread work. Keep the already-presented loader until both are complete.
	var reuse_request := false
	if _abandoned_scene_paths.has(scene_path):
		_abandoned_scene_paths.erase(scene_path)
		var status := _threaded_load_status(scene_path)
		reuse_request = status == ResourceLoader.THREAD_LOAD_IN_PROGRESS or status == ResourceLoader.THREAD_LOAD_LOADED
		if status == ResourceLoader.THREAD_LOAD_FAILED:
			# Release the failed token before requesting a fresh attempt. Never
			# get IN_PROGRESS (blocks) or INVALID (owns no request token).
			_threaded_load_result(scene_path)
	# Retry adopts an outstanding request; it cannot cancel or duplicate that
	# job, and must never block on load_threaded_get while it runs.
	var err: Error = OK
	if not reuse_request:
		err = _threaded_load_request(scene_path)
	if err != OK:
		push_warning("SceneRouter: could not request scene load for %s (%d)" \
			% [scene_path, err])
		_change_now(scene_path)
		return
	_pending_scene_path = scene_path


## Narrow backend seams keep recovery bookkeeping testable without starting
## real resource jobs or pretending an in-progress get is non-blocking.
func _threaded_load_status(scene_path: String, progress: Array = []) -> int:
	return ResourceLoader.load_threaded_get_status(scene_path, progress)


func _threaded_load_request(scene_path: String) -> Error:
	return ResourceLoader.load_threaded_request(scene_path, "PackedScene", true)


func _threaded_load_result(scene_path: String) -> PackedScene:
	return ResourceLoader.load_threaded_get(scene_path) as PackedScene


func _abandon_pending_load() -> void:
	if not _pending_scene_path.is_empty():
		if not _abandoned_scene_paths.has(_pending_scene_path):
			_abandoned_scene_paths.append(_pending_scene_path)
		_pending_scene_path = ""


func _drain_abandoned_loads() -> void:
	# Godot 4.7.1 ResourceLoader retains both LOADED and FAILED request tokens
	# until load_threaded_get decrements their user count. It has no cancellation
	# API. Consume terminal results without swapping; never get an IN_PROGRESS
	# job (blocks), or INVALID_RESOURCE (no token). Retry can adopt pending work.
	for path: String in _abandoned_scene_paths.duplicate():
		var status := _threaded_load_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		if status == ResourceLoader.THREAD_LOAD_LOADED or status == ResourceLoader.THREAD_LOAD_FAILED:
			_threaded_load_result(path)
		_abandoned_scene_paths.erase(path)


func _change_now(scene_path: String) -> void:
	# A pause trigger (Escape, focus loss, controller disconnect) during the
	# fade would leave the next scene permanently paused; force unpause here
	# and again after the deferred swap change_scene_to_file performs.
	get_tree().paused = false
	_holds_tree_pause = false
	var err := get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("SceneRouter: failed to change scene to %s (%d)" % [scene_path, err])
		_show_loading_recovery("This route could not load. Retry or return to the menu.")
		return
	_finish_scene_swap(scene_path)


func _change_to_packed(packed: PackedScene, scene_path: String) -> void:
	get_tree().paused = false
	_holds_tree_pause = false
	var err := get_tree().change_scene_to_packed(packed)
	if err != OK:
		push_error("SceneRouter: failed to instantiate %s (%d)" % [scene_path, err])
		_show_loading_recovery("This route could not load. Retry or return to the menu.")
		return
	_finish_scene_swap(scene_path)


func _finish_scene_swap(scene_path: String) -> void:
	_restore_navigation_after_swap(scene_path, _transition_serial)
	_scene_swapped = true
	_note_loading_work("scene_swapped:%s" % scene_path)
	_qa_native_load_mark("scene_swapped", scene_path)
	_unpause_transition.call_deferred(_transition_serial)
	_busy = false
	scene_changed.emit(scene_path)
	if _perf != null:
		_perf.set_scene_label(scene_path.get_file().get_basename())
	if not GameConfig.is_headless():
		_fade_out_when_scene_drawn()


## Wait for actual draws and build/warmup completion. The fixed wall watchdog
## bounds this wait; its recovery invalidates the serial without uncovering.
func _fade_out_when_scene_drawn() -> void:
	var serial := _transition_serial
	if not _transition_is_current(serial):
		return
	_start_loading_deadline()
	_qa_native_load_mark("scene_draw_wait", _active_scene_path)
	_set_loading_stage("Preparing the route…", -1.0)
	for i: int in 3:
		await RenderingServer.frame_post_draw
		if not _transition_is_current(serial):
			return
	while _scene_is_building():
		await RenderingServer.frame_post_draw
		if not _transition_is_current(serial):
			return
	if not _queued_scene_path.is_empty():
		_restart_under_cover(_queued_scene_path)
		return
	_set_loading_stage("Expedition ready", 1.0)
	_kill_transition_tween()
	_transition_tween = create_tween()
	_transition_tween.tween_property(_fade_rect, "modulate:a", 0.0, FADE_TIME)
	_transition_tween.parallel().tween_property(_loading_box, "modulate:a", 0.0, FADE_TIME * 0.6)
	_transition_tween.tween_callback(_finish_presentation.bind(serial))


func _finish_presentation(serial: int = -1) -> void:
	if serial < 0:
		serial = _transition_serial
	if not _transition_is_current(serial):
		return
	if _scene_is_building():
		_show_loading_recovery()
		return
	if not _queued_scene_path.is_empty():
		_restart_under_cover(_queued_scene_path)
		return
	# Tween completion only changes state; it does not prove that the final
	# unobscured frame reached the renderer/browser. Keep gameplay gated until
	# the hidden overlay has drawn and we have left the post-draw callback.
	_fade_rect.visible = false
	_loading_box.visible = false
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	if not _transition_is_current(serial):
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return
	if not _transition_is_current(serial):
		return
	if _scene_is_building():
		_show_loading_recovery()
		return
	if not _queued_scene_path.is_empty():
		_restart_under_cover(_queued_scene_path)
		return
	_loading_deadline_msec = -1
	_loading_started_msec = -1
	_qa_native_load_mark("presentation_complete", _active_scene_path)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_presenting = false
	_commit_navigation(_active_scene_path)
	_release_tree_pause()
	_emit_lifecycle("loading_finished", {
		"path": _active_scene_path, "serial": serial})


func _emit_lifecycle(event_name: String, fields: Dictionary = {}) -> void:
	BootProfiler.lifecycle_event(event_name, fields)


func _transition_is_current(serial: int) -> bool:
	return is_inside_tree() and serial == _transition_serial and _presenting and not _recovery_active


func _unpause_transition(serial: int) -> void:
	# Headless swaps intentionally have no presentation phase.
	if is_inside_tree() and serial == _transition_serial and not _recovery_active:
		get_tree().paused = false


func _kill_transition_tween() -> void:
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	_transition_tween = null


func _now_msec() -> int:
	return Time.get_ticks_msec()


func _qa_native_load_mark(stage: String, scene_path: String) -> void:
	if not OS.has_feature("android") or not (OS.is_debug_build() or bool(ProjectSettings.get_setting(
		"application/qa/native_load_trace", false))):
		return
	print("[router_load_qa] stage=%s scene=%s tick_ms=%d frame=%d" % [
		stage, scene_path.get_file(), _now_msec(), Engine.get_process_frames()])


func _start_loading_deadline() -> void:
	if _loading_deadline_msec < 0:
		_loading_started_msec = _now_msec()
		_loading_deadline_msec = _loading_started_msec + WARMUP_TIMEOUT_MSEC
		_loading_work_signature = ""
		_qa_native_load_mark("deadline_started", _active_scene_path)


func _note_loading_work(signature: String) -> void:
	if signature == _loading_work_signature or _loading_started_msec < 0:
		return
	_loading_work_signature = signature
	_loading_deadline_msec = mini(_loading_started_msec + WARMUP_MAX_TOTAL_MSEC,
		_now_msec() + WARMUP_TIMEOUT_MSEC)


func _refresh_loading_progress() -> void:
	if not _scene_swapped or not _presenting or _recovery_active \
			or not _pending_scene_path.is_empty():
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var shader := _find_shader_warmup(scene)
	if shader != null:
		var total := shader._queue.size()
		var completed := shader._completed_queue_cursor
		_set_loading_stage("Warming materials %d/%d" % [completed, total],
			float(completed) / float(total) if total > 0 else -1.0)
		_note_loading_work("shader:%d:%d" % [completed, total])
		return
	var visual := _find_initial_visual_warmup(scene)
	if visual != null:
		if not visual._reveal_started:
			_set_loading_stage("Preparing scenery…", -1.0)
			return
		var total := visual._visible_queue.size()
		var completed := visual._drawn_count
		_set_loading_stage("Bringing scenery into view %d/%d" % [completed, total],
			float(completed) / float(total) if total > 0 else -1.0)
		_note_loading_work("visual:%d:%d" % [completed, total])
		return
	if scene is RunnerGame and not (scene as RunnerGame).build_finished:
		_set_loading_stage("Assembling the route…", -1.0)
		_note_loading_work("runner_setup")


func _find_shader_warmup(node: Node) -> ShaderWarmup:
	if node is ShaderWarmup:
		return node as ShaderWarmup
	for child: Node in node.get_children():
		var found := _find_shader_warmup(child)
		if found != null:
			return found
	return null


func _find_initial_visual_warmup(node: Node) -> InitialVisualWarmup:
	if node is InitialVisualWarmup:
		return node as InitialVisualWarmup
	for child: Node in node.get_children():
		var found := _find_initial_visual_warmup(child)
		if found != null:
			return found
	return null


func _poll_loading_watchdog(now_msec: int = -1) -> void:
	# Draw signals can stop while process callbacks continue (occlusion/device
	# trouble). This watchdog can latch recovery then; UI still needs a draw to
	# become visible. It cannot interrupt blocked synchronous resource work.
	if not _presenting or _recovery_active or _loading_deadline_msec < 0:
		return
	if now_msec < 0:
		now_msec = _now_msec()
	if now_msec >= _loading_deadline_msec:
		_show_loading_recovery()


func _show_loading_recovery(message: String = "Loading took longer than expected. Retry or return to the menu.") -> void:
	if not is_inside_tree() or _recovery_active:
		return
	_qa_native_load_mark("recovery_building=%s_pending=%s" % [
		str(_scene_is_building()), str(not _pending_scene_path.is_empty())],
		_active_scene_path)
	if OS.has_feature("android") and OS.is_debug_build():
		var current := get_tree().current_scene
		print("[router_load_qa] blockers scene=%s boot=%s details=%s" % [
			str(current), str(BootWarmup.is_finished()),
			str(_loading_blockers(current))])
	# A destination's own _ready redirect must not be stranded by its unfinished
	# build. Honor the first queued route without uncovering the rejected scene.
	if not _queued_scene_path.is_empty():
		_restart_under_cover(_queued_scene_path)
		return
	_transition_serial += 1
	_kill_transition_tween()
	_loading_deadline_msec = -1
	_loading_started_msec = -1
	_recovery_active = true
	Telemetry.client_error("scene_load")
	_recovery_back_armed = false
	_busy = false
	_presenting = true
	# Suspend synchronously: Retry can reset recovery before the helpers' next
	# process callback. Their old queues must remain frozen until scene exit.
	loading_recovery_started.emit()
	# Startup managers already hold their actors; pause also covers a failed
	# navigation away from an old scene whose gameplay had previously started.
	# This autoload and its controls process ALWAYS, so recovery stays usable.
	get_tree().paused = true
	_holds_tree_pause = true
	_abandon_pending_load()
	_fade_rect.visible = true
	_fade_rect.modulate.a = 1.0
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading_box.visible = true
	_loading_box.modulate.a = 1.0
	_loading_label.text = message
	_loading_progress.visible = false
	if _loading_mascot != null:
		_loading_mascot.visible = false
	if _loading_recovery != null:
		_loading_recovery.visible = true
		_retry_button.disabled = _active_scene_path.is_empty()
		_back_button.disabled = false
		_back_button.text = "Back to Menu"
		if not _retry_button.disabled:
			_retry_button.grab_focus()
		else:
			_back_button.grab_focus()
	_layout_loading_card()


func _reset_loading_recovery() -> void:
	_loading_deadline_msec = -1
	_loading_started_msec = -1
	_loading_work_signature = ""
	_recovery_active = false
	_recovery_back_armed = false
	if _loading_recovery != null:
		_loading_recovery.visible = false
		_retry_button.disabled = true
		_back_button.disabled = true
		_back_button.text = "Back to Menu"
	if _loading_progress != null:
		_loading_progress.visible = false
	if _loading_mascot != null:
		_loading_mascot.visible = true
		_loading_mascot.reset_progress()
	_layout_loading_card()


func _retry_loading() -> void:
	if not _recovery_active or _active_scene_path.is_empty():
		return
	_restart_under_cover(_active_scene_path if _queued_scene_path.is_empty() else _queued_scene_path)


func _back_to_menu() -> void:
	if not _recovery_active:
		return
	# Match PauseMenu: abandoning an unfinished Grand Prix needs a second press.
	if _active_scene_path == Game.SCENE_RACE and Game.mode == Game.Mode.GRAND_PRIX \
			and not _recovery_back_armed:
		_recovery_back_armed = true
		_loading_label.text = "Returning to the menu abandons this Grand Prix. Press Confirm Back to leave."
		if _back_button != null:
			_back_button.text = "Confirm Back"
		return
	# Same cleanup as Game.quit_race_to_menu(), but use the covered route seam
	# because ordinary go_to() intentionally queues while presentation is held.
	Game.daily_active = false
	# Explicit recovery exit is Home even when a failed Back was already
	# loading this same scene with a saved More/Account panel.
	_pending_menu_history.clear()
	_navigation_state = {}
	_restart_under_cover(Game.SCENE_MAIN_MENU)


func _restart_under_cover(scene_path: String) -> void:
	if not is_inside_tree() or scene_path.is_empty():
		return
	_retarget_navigation(scene_path)
	_transition_serial += 1
	_kill_transition_tween()
	_active_scene_path = scene_path
	_from_boot = false
	_queued_scene_path = ""
	_abandon_pending_load()
	_busy = true
	_scene_swapped = false
	_presenting = true
	_reset_loading_recovery()
	_start_loading_deadline()
	# Keep any already-running rejected scene frozen through resource loading.
	# _change_now/_change_to_packed unpause atomically with the actual swap.
	get_tree().paused = true
	_holds_tree_pause = true
	_fade_rect.visible = true
	_fade_rect.modulate.a = 1.0
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading_box.visible = true
	_loading_box.modulate.a = 1.0
	_emit_lifecycle("loading_started", {
		"path": scene_path, "serial": _transition_serial, "route": "under_cover"})
	_begin_threaded_load(scene_path, _transition_serial)


func _exit_tree() -> void:
	_transition_serial += 1
	_loading_deadline_msec = -1
	_loading_started_msec = -1
	_kill_transition_tween()
	_release_tree_pause()


func _release_tree_pause() -> void:
	if _holds_tree_pause:
		_holds_tree_pause = false
		if get_tree() != null:
			get_tree().paused = false


func _set_loading_stage(text: String, progress: float) -> void:
	if _loading_label != null:
		var start_ms := _loading_started_msec if _loading_started_msec >= 0 else _now_msec()
		var elapsed := maxi(0, _now_msec() - start_ms)
		_loading_label.text = "Ready to waddle!" if text == "Expedition ready" else \
			LOADING_MESSAGES[floori(float(elapsed) / 3200.0) % LOADING_MESSAGES.size()]
	if _loading_progress != null:
		_loading_progress.visible = false
		if progress >= 0.0:
			_loading_progress.value = clampf(progress, 0.0, 1.0)
	if _loading_mascot != null:
		_loading_mascot.set_progress(_overall_loading_progress(text, progress))


func _overall_loading_progress(stage: String, part: float) -> float:
	# Fractions represent completed work inside each phase, not elapsed time.
	# Unknown build/upload phases hold their last fill. No reset or bouncing bar.
	var fraction := clampf(part, 0.0, 1.0) if part >= 0.0 else 0.0
	if stage == "Expedition ready":
		return 1.0
	if stage == "Preparing expedition…":
		return BootWarmup.progress() * 0.2 if _from_boot else 0.0
	if stage == "Packing route assets…":
		return BootWarmup.progress() * 0.2 if _from_boot \
			and not BootWarmup.is_finished() else 0.2 + fraction * 0.25
	if stage == "Opening the route…":
		return 0.45
	if stage.begins_with("Warming materials"):
		return 0.55 + fraction * 0.23
	if stage.begins_with("Bringing scenery"):
		return 0.78 + fraction * 0.17
	return 0.5


func _layout_loading_card() -> void:
	if _loading_card == null:
		return
	var view := get_viewport().get_visible_rect().size
	var style := _loading_card.get_theme_stylebox("panel")
	if _loading_wordmark != null:
		_loading_wordmark.visible = not _recovery_active
		_loading_wordmark.get_parent().visible = not _recovery_active
	if _loading_route != null:
		_loading_route.visible = _recovery_active
	if _recovery_active:
		var safe := LayoutProfile.for_viewport(get_viewport()).safe_rect
		# The design canvas can be twice the client window on a phone. Keep
		# recovery targets 48 client pixels, not 48 shrinking logical units.
		var scale := 1.0
		var window := get_window()
		if window != null and window.size.x > 0 and window.size.y > 0:
			scale = maxf(1.0, maxf(view.x / float(window.size.x), view.y / float(window.size.y)))
		var width := minf(520.0 * scale, maxf(1.0, safe.size.x - 24.0 * scale))
		var height := minf(300.0 * scale, maxf(1.0, safe.size.y - 24.0 * scale))
		var center := safe.get_center() - view * 0.5
		if style != null:
			style.content_margin_left = 16.0 * scale
			style.content_margin_right = 16.0 * scale
			style.content_margin_top = 16.0 * scale
			style.content_margin_bottom = 16.0 * scale
		if _loading_label != null:
			_loading_label.add_theme_font_size_override("font_size", roundi(18.0 * scale))
		if _loading_route != null:
			_loading_route.add_theme_font_size_override("font_size", roundi(22.0 * scale))
		if _loading_box != null:
			_loading_box.add_theme_constant_override("separation", roundi(8.0 * scale))
		if _loading_recovery != null:
			_loading_recovery.add_theme_constant_override("separation", roundi(8.0 * scale))
			_retry_button.custom_minimum_size.y = 48.0 * scale
			_back_button.custom_minimum_size.y = 48.0 * scale
			_retry_button.add_theme_font_size_override("font_size", roundi(20.0 * scale))
			_back_button.add_theme_font_size_override("font_size", roundi(18.0 * scale))
		_loading_card.offset_left = center.x - width * 0.5
		_loading_card.offset_right = center.x + width * 0.5
		_loading_card.offset_top = center.y - height * 0.5
		_loading_card.offset_bottom = center.y + height * 0.5
		return
	var portrait := view.y > view.x
	var width := minf(1000.0, minf(view.x * 0.90, view.y * (1.0 if portrait else 1.025)))
	var scale := width / 840.0
	var height := width * (0.77 if portrait else 0.667)
	if style != null:
		style.content_margin_left = 42.0 * scale
		style.content_margin_right = 42.0 * scale
		style.content_margin_top = 35.0 * scale
		style.content_margin_bottom = 42.0 * scale
	if _loading_label != null:
		_loading_label.add_theme_font_size_override("font_size", maxi(19, roundi((55.0 if portrait else 54.0) * scale)))
	if _loading_route != null:
		_loading_route.add_theme_font_size_override("font_size", 24)
	if _loading_box != null:
		_loading_box.add_theme_constant_override("separation", roundi(8.0 * scale))
	if _loading_wordmark != null:
		var slot := _loading_wordmark.get_parent() as Control
		slot.custom_minimum_size.y = 24.0 * scale
		_loading_wordmark.size = Vector2(width * (0.72 if portrait else 0.64),
			width * (0.375 if portrait else 0.332))
		_loading_wordmark.position = Vector2((view.x - _loading_wordmark.size.x) * 0.5,
			view.y * (0.22 if portrait else 0.055))
	if _loading_mascot != null:
		_loading_mascot.custom_minimum_size = Vector2(width * 0.90, width * (0.54 if portrait else 0.46))
		_loading_mascot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loading_card.offset_left = -width * 0.5
	_loading_card.offset_right = width * 0.5
	_loading_card.offset_top = -height * 0.5 + view.y * (0.03 if portrait else 0.045)
	_loading_card.offset_bottom = height * 0.5 + view.y * (0.03 if portrait else 0.045)


## True while the incoming scene is still assembling itself: a staged course
## build, a staged Waddle Run build, or a ShaderWarmup pass still linking
## programs. Web splits construction across frames so this overlay's penguins
## keep dancing through it; either way the scene underneath is not presentable
## yet.
func _scene_is_building() -> bool:
	var tree := get_tree()
	return not BootWarmup.is_finished() or tree == null or tree.current_scene == null \
			or _subtree_is_building(tree.current_scene)


func _subtree_is_building(node: Node) -> bool:
	if node == null:
		return false
	# RunnerGame is the actual scene root, while courses and warmup passes can
	# be nested. Direct-child-only inspection released the runner loader early.
	if node is ShaderWarmup:
		return true
	if node is CourseBase and not (node as CourseBase).build_finished:
		return true
	if node is RunnerGame and not (node as RunnerGame).build_finished:
		return true
	# Course geometry can finish before its actors are even added to the tree.
	# Their finalizers install warmup before lifting these latches, so the
	# overlay remains held through both deferred and staged setup paths.
	if node is RaceManager and not (node as RaceManager)._grid_placed:
		return true
	if node is TutorialManager and not (node as TutorialManager)._spawn_ready:
		return true
	for child: Node in node.get_children():
		if _subtree_is_building(child):
			return true
	return false


func _loading_blockers(node: Node) -> Array[String]:
	var blockers: Array[String] = []
	if node == null:
		return blockers
	if node is ShaderWarmup:
		blockers.append("shader:%d/%d awaiting=%s" % [
			(node as ShaderWarmup)._queue_cursor, (node as ShaderWarmup)._queue.size(),
			str((node as ShaderWarmup)._awaiting_draw)])
	if node is InitialVisualWarmup:
		blockers.append("visual:%d/%d awaiting=%s" % [
			(node as InitialVisualWarmup)._cursor, (node as InitialVisualWarmup)._visible_queue.size(),
			str((node as InitialVisualWarmup)._awaiting_draw)])
	if node is RunnerGame:
		blockers.append("runner_finished=%s" % str((node as RunnerGame).build_finished))
	if node is CourseBase:
		blockers.append("course_finished=%s" % str((node as CourseBase).build_finished))
	if node is RaceManager:
		blockers.append("race_grid=%s" % str((node as RaceManager)._grid_placed))
	if node is TutorialManager:
		blockers.append("tutorial_spawn=%s" % str((node as TutorialManager)._spawn_ready))
	for child: Node in node.get_children():
		blockers.append_array(_loading_blockers(child))
	return blockers


func _on_achievement_unlocked(id: String) -> void:
	if GameConfig.is_headless():
		return
	var info := AchievementsDB.get_item(id)
	if info.is_empty():
		return
	# One owned toast, so simultaneous tier awards cannot cover each other.
	for previous: Node in _toast_layer.get_children():
		previous.queue_free()
	var panel := _make_achievement_toast(String(info["name"]))
	_toast_layer.add_child(panel)
	var hud: RunnerHUD = null
	if get_tree().current_scene is RunnerGame:
		hud = (get_tree().current_scene as RunnerGame).hud
	_place_achievement_toast(panel, hud)
	panel.resized.connect(_place_achievement_toast.bind(panel, hud))
	panel.modulate.a = 0.0
	# Bind animation lifetime to its panel, including early replacement/free.
	var tween := panel.create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.18)
	tween.tween_interval(2.6)
	tween.tween_property(panel, "modulate:a", 0.0, 0.35)
	tween.tween_callback(panel.queue_free)


func _make_achievement_toast(achievement_name: String) -> Panel:
	# Explicit bounds avoid a wrapped Container retaining its initial zero-width
	# minimum height when an achievement arrives during a native draw frame.
	var panel := Panel.new()
	panel.name = "AchievementToast"
	panel.size = Vector2(600.0, 128.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.add_theme_stylebox_override("panel", RunnerHUDArt.panel("gauge", 30.0, 22.0, 18.0))
	var trophy := TextureRect.new()
	trophy.name = "Trophy"
	trophy.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	trophy.texture = RunnerHUDArt.sprite("trophy")
	trophy.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	trophy.position = Vector2(24.0, 36.0)
	trophy.size = Vector2(56.0, 56.0)
	trophy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(trophy)
	var title := Label.new()
	title.name = "Heading"
	title.position = Vector2(94.0, 18.0)
	title.size = Vector2(478.0, 28.0)
	title.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", ExpeditionMenuStyle.INK_MUTED)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = "ACHIEVEMENT UNLOCKED"
	panel.add_child(title)
	var name_label := Label.new()
	name_label.name = "AchievementName"
	name_label.position = Vector2(94.0, 46.0)
	name_label.size = Vector2(478.0, 72.0)
	name_label.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	name_label.add_theme_font_size_override("font_size", 30)
	name_label.add_theme_color_override("font_color", ExpeditionMenuStyle.INK)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = achievement_name
	panel.add_child(name_label)
	return panel


func _place_achievement_toast(panel: Panel, hud: RunnerHUD = null) -> void:
	if not is_instance_valid(panel):
		return
	var view := panel.get_viewport_rect().size
	var width := minf(600.0, view.x - 48.0)
	var center_x := view.x * 0.5
	var top := 24.0
	if is_instance_valid(hud) and is_instance_valid(hud._headline_column):
		# Achievements can arrive in the same tick that powers become visible.
		# Containers have not sorted yet; follow their final bounds rather than
		# keeping the first-frame empty power-column measurement for the toast.
		if not panel.has_meta("hud_bounds_observers"):
			var controls: Array[Control] = [hud._root, hud._headline_column,
				hud._mission_panel, hud._powerup_box]
			var place := _place_achievement_toast.bind(panel, hud)
			for control: Control in controls:
				control.resized.connect(place)
			panel.set_meta("hud_bounds_observers", true)
			panel.tree_exiting.connect(func() -> void:
				for control: Control in controls:
					if is_instance_valid(control) and control.resized.is_connected(place):
						control.resized.disconnect(place))
		var headline := hud._headline_column.get_global_rect()
		center_x = headline.get_center().x
		top = headline.end.y + 20.0
		# The portrait middle column is deliberately clear between challenges
		# and powerups. Keep this temporary notice inside that same column.
		if view.y > view.x:
			var left := hud._mission_panel.get_global_rect().end.x + 14.0
			var right := hud._powerup_box.get_global_rect().position.x - 14.0
			if right - left >= 400.0:
				width = minf(width, right - left)
				center_x = clampf(center_x, left + width * 0.5, right - width * 0.5)
			else:
				top = maxf(top, maxf(hud._mission_panel.get_global_rect().end.y,
					hud._powerup_box.get_global_rect().end.y) + 20.0)
	panel.size = Vector2(width, 128.0)
	var title := panel.get_node("Heading") as Label
	title.size.x = width - 122.0
	title.add_theme_font_size_override("font_size", 18 if width < 500.0 else 20)
	var name_label := panel.get_node("AchievementName") as Label
	name_label.size = Vector2(width - 122.0, 72.0)
	name_label.add_theme_font_size_override("font_size", 26 if width < 500.0 else 30)
	panel.position = Vector2(clampf(center_x - width * 0.5, 24.0,
		maxf(24.0, view.x - width - 24.0)), top)


## Global mute hotkey (M). Lives here rather than in the race scene so it
## works on menus, results and mid-race alike; the pause-menu toggle writes
## the same setting.
func _unhandled_input(event: InputEvent) -> void:
	if GameConfig.is_headless() or not event.is_action_pressed("mute_audio"):
		return
	var now_muted := not bool(SettingsManager.get_setting("audio", "muted"))
	SettingsManager.set_setting("audio", "muted", now_muted)
	_show_mute_toast("Sound muted" if now_muted else "Sound on")
	get_viewport().set_input_as_handled()


func _show_mute_toast(text: String) -> void:
	if _mute_toast != null and is_instance_valid(_mute_toast):
		_mute_toast.queue_free()
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.offset_top = 96.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.03, 0.06, 0.12, 0.85))
	label.add_theme_constant_override("outline_size", 8)
	_mute_layer.add_child(label)
	_mute_toast = label
	var tween := label.create_tween()
	tween.tween_interval(1.0)
	tween.tween_property(label, "modulate:a", 0.0, 0.4)
	tween.tween_callback(label.queue_free)
