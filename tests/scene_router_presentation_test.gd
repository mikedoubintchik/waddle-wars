extends Node
## Headless sequencing test: simulated draw signals, real process-frame yield.
## It proves ordering/cancellation, not browser paint or load-time smoothness.

class RouterProbe:
	extends "res://scripts/utilities/scene_router.gd"

	var events: Array[String] = []
	var requested_paths: Array[String] = []
	var stage_progress: float = -1.0

	func _ready() -> void:
		set_process(false)

	func _ensure_loading_presentation() -> void:
		events.append("presentation")

	func _set_loading_stage(text: String, progress: float) -> void:
		events.append(text)
		stage_progress = progress

	func _request_threaded_load(scene_path: String) -> void:
		events.append("request")
		requested_paths.append(scene_path)


class LazyControlsProbe:
	extends "res://scripts/utilities/scene_router.gd"

	var reset_saw_controls: Array[bool] = []
	var route_saw_controls: Array[bool] = []
	var routed_paths: Array[String] = []

	func _ready() -> void:
		super._ready()
		set_process(false)

	func _reset_loading_recovery() -> void:
		reset_saw_controls.append(_loading_card != null and _loading_box != null
			and _retry_button != null and _back_button != null)
		super._reset_loading_recovery()

	func _change_now(scene_path: String) -> void:
		# Keep the production accepted-route ordering, but never replace this test.
		route_saw_controls.append(_loading_card != null and _loading_box != null)
		routed_paths.append(scene_path)

	func _request_threaded_load(scene_path: String) -> void:
		_change_now(scene_path)


class BootProbe:
	extends "res://scripts/ui/boot.gd"

	var events: Array[String] = []
	var route_calls: int = 0

	func _ready() -> void:
		# Only the upgrade coroutine is under test, not cache decoding or routing.
		set_process(false)
		set_process_input(false)
		_build_first_frame()
		_upgrade_after_first_present()

	func _build_first_frame() -> void:
		events.append("first")
		super._build_first_frame()

	func _route() -> void:
		route_calls += 1
		events.append("route")


var _checks: int = 0
var _failed: int = 0


func _ready() -> void:
	await _check_opaque_loading_cover()
	await _check_lazy_loading_controls()
	await _check_boot_upgrade_boundary()
	await _check_boot_removed_before_draw()
	await _check_boot_removed_after_draw()
	await _check_presentation_boundary()
	await _check_pending_boot_preparation()
	await _check_removed_before_draw()
	await _check_removed_after_draw()
	await _check_dismissal_boundary()
	print("[scene_router_presentation] %d checks, %d failures" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check_opaque_loading_cover() -> void:
	# Use the actual current scene and viewport, but only lightweight Canvas
	# controls. No scene load, GPU warmup, recovery dispatch or draw wait here.
	# A second root child cannot be added while root propagates readiness.
	# Leave that construction stack before testing current-scene identity.
	await get_tree().process_frame
	var current := get_tree().current_scene
	_check(is_instance_valid(current) and current.is_inside_tree(),
		"opaque cover fixture has actual current scene")
	if not is_instance_valid(current):
		return
	var probe := RouterProbe.new()
	_check(not probe.has_opaque_loading_cover(current), "detached router cannot own loading cover")
	add_child(probe)
	probe._overlay_layer = CanvasLayer.new()
	probe.add_child(probe._overlay_layer)
	probe._fade_rect = ColorRect.new()
	probe._fade_rect.color = Color(0.03, 0.06, 0.12, 1.0)
	probe._fade_rect.modulate = Color.WHITE
	probe._fade_rect.self_modulate = Color.WHITE
	probe._fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	probe._overlay_layer.add_child(probe._fade_rect)
	var visible_rect := get_viewport().get_visible_rect()
	probe._fade_rect.position = visible_rect.position
	probe._fade_rect.size = visible_rect.size
	probe._busy = true
	_check(not probe.has_opaque_loading_cover(current), "busy without presentation is not opaque loading")
	probe._presenting = true
	probe._busy = false
	_check(probe.has_opaque_loading_cover(current),
		"presenting opaque full viewport cover accepts actual current scene")
	_check(not probe.has_opaque_loading_cover(null), "null scene cannot use loading cover")
	var detached := Node.new()
	_check(not probe.has_opaque_loading_cover(detached), "detached scene cannot use loading cover")
	detached.free()
	var other := Node.new()
	get_tree().root.add_child(other)
	_check(not probe.has_opaque_loading_cover(other), "different attached root cannot use loading cover")
	get_tree().current_scene = other
	_check(not probe.has_opaque_loading_cover(current), "previous scene rejected after current-scene identity changes")
	_check(probe.has_opaque_loading_cover(other), "new actual current scene accepted under same cover")
	get_tree().current_scene = current
	other.free()
	probe._recovery_active = true
	_check(not probe.has_opaque_loading_cover(current), "loading recovery forbids deferred background")
	probe._recovery_active = false
	probe._fade_rect.visible = false
	_check(not probe.has_opaque_loading_cover(current), "hidden fade cannot cover scene")
	probe._fade_rect.visible = true
	probe._overlay_layer.visible = false
	_check(not probe.has_opaque_loading_cover(current), "hidden CanvasLayer cannot cover scene")
	probe._overlay_layer.visible = true
	for channel: String in ["color", "modulate", "self_modulate"]:
		var original: Color = probe._fade_rect.get(channel)
		var translucent := original
		translucent.a = 0.999
		probe._fade_rect.set(channel, translucent)
		_check(not probe.has_opaque_loading_cover(current), channel + " alpha below one rejects cover")
		probe._fade_rect.set(channel, original)
		_check(probe.has_opaque_loading_cover(current), channel + " exact opaque alpha restores cover")
	for uncovered: Rect2 in [
		Rect2(visible_rect.position + Vector2(1.0, 0.0), visible_rect.size - Vector2(1.0, 0.0)),
		Rect2(visible_rect.position + Vector2(0.0, 1.0), visible_rect.size - Vector2(0.0, 1.0)),
		Rect2(visible_rect.position, visible_rect.size - Vector2(1.0, 0.0)),
		Rect2(visible_rect.position, visible_rect.size - Vector2(0.0, 1.0)),
	]:
		probe._fade_rect.position = uncovered.position
		probe._fade_rect.size = uncovered.size
		_check(not probe.has_opaque_loading_cover(current), "one-pixel viewport edge gap rejects cover")
	probe._fade_rect.position = visible_rect.position
	probe._fade_rect.size = visible_rect.size
	_check(probe.has_opaque_loading_cover(current), "all viewport edges covered again")
	var fade := probe._fade_rect
	probe._fade_rect = null
	_check(not probe.has_opaque_loading_cover(current), "missing fade rejected")
	probe._fade_rect = fade
	var layer := probe._overlay_layer
	probe._overlay_layer = null
	_check(not probe.has_opaque_loading_cover(current), "missing overlay layer rejected")
	probe._overlay_layer = layer
	layer.remove_child(fade)
	probe.add_child(fade)
	_check(not probe.has_opaque_loading_cover(current), "fade outside owned CanvasLayer rejected")
	probe.remove_child(fade)
	layer.add_child(fade)
	_check(probe.has_opaque_loading_cover(current), "restored owned CanvasLayer accepts cover")
	probe.free()


func _check_lazy_loading_controls() -> void:
	# Empty caches make an eager font lookup observable even if another autoload
	# or test already warmed them. Restore all references before leaving fixture.
	var fonts := [UITheme._ui_font, UITheme._runtime_theme, UITheme._display_font,
		UITheme._button_font, UITheme._caption_font]
	UITheme._ui_font = null
	UITheme._runtime_theme = null
	UITheme._display_font = null
	UITheme._button_font = null
	UITheme._caption_font = null
	var probe := LazyControlsProbe.new()
	add_child(probe)
	_check(probe._fade_rect != null and probe._overlay_layer != null
		and probe._toast_layer != null and probe._mute_layer != null,
		"router ready retains lightweight fade and toast layers")
	_check(probe._loading_card == null and probe._loading_box == null
		and probe._loading_label == null and probe._loading_route == null
		and probe._retry_button == null and probe._loading_backdrop == null,
		"router ready does not build hidden rich loading controls")
	_check(_font_caches_empty(), "router ready does not warm custom fonts")
	probe._busy = true
	probe.go_to("res://tests/rejected_route.tscn")
	_check(probe._loading_card == null and probe.reset_saw_controls.is_empty()
		and probe.routed_paths.is_empty() and _font_caches_empty(),
		"busy route does not build rich controls or fonts")
	probe._busy = false
	probe._presenting = true
	probe.go_to("res://tests/queued_route.tscn")
	_check(probe._loading_card == null and probe.reset_saw_controls.is_empty()
		and probe.routed_paths.is_empty() and _font_caches_empty()
		and probe._queued_scene_path == "res://tests/queued_route.tscn",
		"queued route does not build rich controls or fonts")
	probe._presenting = false
	probe._queued_scene_path = ""
	probe.go_to("res://tests/accepted_route.tscn")
	_check(probe._loading_card != null and probe._loading_card.get_parent() == probe._fade_rect
		and probe._loading_label != null and probe._loading_progress != null
		and probe._retry_button != null and probe._back_button != null,
		"accepted route lazily creates complete loading controls")
	_check(probe.reset_saw_controls == [true],
		"accepted route builds controls before recovery state reset")
	if GameConfig.is_headless():
		_check(probe.routed_paths == ["res://tests/accepted_route.tscn"]
			and probe.route_saw_controls == [true],
			"accepted route builds controls before headless scene dispatch")
	else:
		var tween := probe._transition_tween
		if tween != null and tween.is_valid():
			tween.custom_step(1.0)
		RenderingServer.frame_post_draw.emit()
		await get_tree().process_frame
		_check(probe.routed_paths == ["res://tests/accepted_route.tscn"]
			and probe.route_saw_controls == [true],
			"accepted route builds controls before rendered scene dispatch")
	var card := probe._loading_card
	var children := probe._fade_rect.get_child_count()
	probe._ensure_loading_controls()
	probe._ensure_loading_controls()
	_check(probe._loading_card == card and probe._fade_rect.get_child_count() == children,
		"loading controls reuse one card on repeated ensure")
	var retry_callbacks := 0
	var back_callbacks := 0
	for connection: Dictionary in probe._retry_button.pressed.get_connections():
		if connection["callable"] == Callable(probe, "_retry_loading"):
			retry_callbacks += 1
	for connection: Dictionary in probe._back_button.pressed.get_connections():
		if connection["callable"] == Callable(probe, "_back_to_menu"):
			back_callbacks += 1
	_check(retry_callbacks == 1 and back_callbacks == 1,
		"repeated ensure never duplicates recovery callbacks")
	# Let the real ready() deferred permission hook finish before destruction.
	await get_tree().process_frame
	probe.free()
	UITheme._ui_font = fonts[0] as Font
	UITheme._runtime_theme = fonts[1] as Theme
	UITheme._display_font = fonts[2] as FontVariation
	UITheme._button_font = fonts[3] as FontVariation
	UITheme._caption_font = fonts[4] as FontVariation


func _font_caches_empty() -> bool:
	return (UITheme._ui_font == null and UITheme._runtime_theme == null
		and UITheme._display_font == null and UITheme._button_font == null
		and UITheme._caption_font == null)


func _check_boot_upgrade_boundary() -> void:
	var probe := BootProbe.new()
	add_child(probe)
	_check(probe.events == ["first"] and probe._first_frame != null,
		"boot first frame contains only immediate presentation")
	RenderingServer.frame_post_draw.emit()
	_check(probe.events == ["first"] and probe.route_calls == 0
		and probe._first_frame != null,
		"boot never routes inside post-draw callback")
	await get_tree().process_frame
	_check(probe.events == ["first", "route"] and probe.route_calls == 1
		and probe._first_frame != null,
		"boot routes on following process frame while retaining launch still")
	RenderingServer.frame_post_draw.emit()
	await get_tree().process_frame
	_check(probe.route_calls == 1,
		"later draws never duplicate boot route")
	probe.free()


func _check_boot_removed_before_draw() -> void:
	var probe := BootProbe.new()
	add_child(probe)
	remove_child(probe)
	RenderingServer.frame_post_draw.emit()
	await get_tree().process_frame
	_check(probe.events == ["first"] and probe.route_calls == 0
		and probe._first_frame != null,
		"boot removed before draw never routes or removes launch still")
	probe.free()


func _check_boot_removed_after_draw() -> void:
	var probe := BootProbe.new()
	add_child(probe)
	RenderingServer.frame_post_draw.emit()
	remove_child(probe)
	await get_tree().process_frame
	_check(probe.events == ["first"] and probe.route_calls == 0
		and probe._first_frame != null,
		"boot removed after draw never routes on following process frame")
	probe.free()


func _new_probe() -> RouterProbe:
	var probe := RouterProbe.new()
	add_child(probe)
	# go_to() owns these flags before its fade invokes _begin_threaded_load().
	# Set the same precondition without requiring a window or changing scenes.
	probe._busy = true
	probe._presenting = true
	return probe


func _check_presentation_boundary() -> void:
	var probe := _new_probe()
	_check(is_equal_approx(probe._overall_loading_progress("Packing route assets…", 0.0), 0.2),
		"resource phase starts after the completed warmup share")
	_check(is_equal_approx(probe._overall_loading_progress("Packing route assets…", 0.5),
		0.325), "resource fraction maps into one route-wide fill")
	_check(is_equal_approx(probe._overall_loading_progress("Warming materials 2/4", 0.5),
		0.665), "shader fraction follows resource phase")
	_check(is_equal_approx(probe._overall_loading_progress("Bringing scenery into view 1/2", 0.5),
		0.865), "visible draw fraction follows shader phase")
	probe._begin_threaded_load("res://tests/intended_scene.tscn")
	_check(probe.events == ["presentation", "Packing route assets…"],
		"authored presentation and stage prepared before waiting")
	_check(is_equal_approx(probe.stage_progress, 0.0), "initial resource progress starts at zero")
	_check(probe.requested_paths.is_empty(), "request waits for completed draw")
	_check(probe._pending_scene_path.is_empty(), "polling not armed before request")
	_check(probe.is_busy() and probe.is_presenting(), "transition remains guarded")
	probe.go_to("res://tests/unwanted_scene.tscn")
	_check(probe._queued_scene_path.is_empty() and probe.requested_paths.is_empty(),
		"second transition ignored while initial request awaits presentation")
	RenderingServer.frame_post_draw.emit()
	_check(probe.requested_paths.is_empty(), "request never runs inside post-draw callback")
	_check(probe.is_busy() and probe.is_presenting(), "guards survive post-draw callback")
	await get_tree().process_frame
	_check(probe.requested_paths == ["res://tests/intended_scene.tscn"],
		"exact destination requested on following process frame")
	_check(probe.events == ["presentation", "Packing route assets…", "request"],
		"no duplicate load or late stage change")
	RenderingServer.frame_post_draw.emit()
	await get_tree().process_frame
	_check(probe.requested_paths.size() == 1, "later frames do not restart request")
	probe.queue_free()
	await get_tree().process_frame


func _check_pending_boot_preparation() -> void:
	var was_finished := BootWarmup._finished
	BootWarmup._finished = false
	var probe := _new_probe()
	probe._begin_threaded_load("res://tests/after_boot_uploads.tscn")
	RenderingServer.frame_post_draw.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(probe.requested_paths.is_empty() and probe.is_presenting(),
		"early splash route remains covered until front-end uploads finish")
	_check(not probe.is_gameplay_ready(self), "unfinished boot prep blocks direct gameplay")
	BootWarmup._finished = true
	await get_tree().process_frame
	_check(probe.requested_paths == ["res://tests/after_boot_uploads.tscn"],
		"finished boot prep releases exactly one scene request")
	probe.free()
	BootWarmup._finished = was_finished


func _check_removed_before_draw() -> void:
	var probe := _new_probe()
	probe._begin_threaded_load("res://tests/removed_before_draw.tscn")
	remove_child(probe)
	RenderingServer.frame_post_draw.emit()
	await get_tree().process_frame
	_check(probe.requested_paths.is_empty(), "removed router never requests after draw")
	probe.free()


func _check_removed_after_draw() -> void:
	var probe := _new_probe()
	probe._begin_threaded_load("res://tests/removed_after_draw.tscn")
	RenderingServer.frame_post_draw.emit()
	remove_child(probe)
	await get_tree().process_frame
	_check(probe.requested_paths.is_empty(), "removed router never requests on next frame")
	probe.free()


func _check_dismissal_boundary() -> void:
	var probe := _new_probe()
	probe._busy = false
	probe._fade_rect = ColorRect.new()
	probe._fade_rect.modulate.a = 0.5
	probe._fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	probe.add_child(probe._fade_rect)
	probe._loading_box = VBoxContainer.new()
	probe._fade_rect.add_child(probe._loading_box)
	probe._finish_presentation()
	_check(probe.is_presenting(), "dismissal waits for a cleared draw")
	_check(not probe._fade_rect.visible and not probe._loading_box.visible,
		"dismissal explicitly hides the whole overlay")
	RenderingServer.frame_post_draw.emit()
	_check(probe.is_presenting(), "post-draw callback cannot release gameplay")
	await get_tree().process_frame
	_check(not probe.is_presenting() and not probe.is_busy(),
		"following process frame releases presentation")
	_check(probe._fade_rect.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"completed overlay no longer intercepts input")
	probe.free()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failed += 1
		push_error("[scene_router_presentation] FAIL " + message)
