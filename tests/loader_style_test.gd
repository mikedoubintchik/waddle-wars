extends Node
## Cheap geometry/progress contracts; raster matching is a separate capture.

var _passes := 0
var _failures := 0


class LayoutRouter:
	extends "res://scripts/utilities/scene_router.gd"

	func _ready() -> void:
		# Real loading controls/layout; no routing, telemetry or platform setup.
		_fade_rect = ColorRect.new()
		_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_fade_rect)


func _ready() -> void:
	for canvas: Vector2 in [Vector2(486.0, 232.0), Vector2(760.0, 361.0), Vector2(176.0, 176.0)]:
		var loader := PenguinLoader.new(176.0)
		loader.size = canvas
		add_child(loader)
		loader.set_reduced_motion(true)
		loader._update_pivots()
		var label := "%dx%d" % [canvas.x, canvas.y]
		_check(label + "_authored_track_loaded", loader._track_art.texture != null
			and PenguinLoader.loader_texture() != null)
		_check(label + "_all_art_inside_loader", Rect2(Vector2.ZERO, canvas).encloses(
			loader._track_art.get_rect()) and Rect2(Vector2.ZERO, canvas).encloses(
			loader._character_holder.get_rect()))
		_check(label + "_empty_is_really_empty", not loader._bar_fill.visible)
		loader.set_progress(0.63)
		_check(label + "_real_progress_controls_fill", is_equal_approx(loader.get_progress(), 0.63)
			and is_equal_approx(loader._bar_fill.anchor_right, 0.63) and loader._bar_fill.visible)
		loader.set_progress(-1.0)
		loader.set_progress(0.12)
		_check(label + "_unknown_or_earlier_phase_never_reverses", is_equal_approx(loader.get_progress(), 0.63))
		loader._process(3.0)
		_check(label + "_elapsed_time_never_invents_progress", is_equal_approx(loader.get_progress(), 0.63)
			and is_equal_approx(loader._shown_progress, 0.63))
		loader.set_progress(1.0)
		_check(label + "_completed_fills_recess", is_equal_approx(loader._bar_fill.anchor_right, 1.0))
		loader.reset_progress()
		_check(label + "_next_load_empty_and_static", not loader._bar_fill.visible
			and is_zero_approx(loader.get_progress()) and not loader.is_motion_active())
		loader.free()
	var glossy := PenguinLoader.progress_fill_texture().get_image()
	_check("progress_tube_transparent_corners", glossy.get_pixel(0, 0).a < 0.01)
	_check("progress_tube_smooth_gloss", glossy.get_pixel(512, 22).g > glossy.get_pixel(512, 90).g
		and glossy.get_pixel(512, 22).r > 0.9 and glossy.get_pixel(512, 90).a > 0.99)
	await _check_route_composition()
	print("[loader_style] DONE: %d passed, %d failed" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _check_route_composition() -> void:
	for shape: Vector2i in [Vector2i(540, 960), Vector2i(1280, 720), Vector2i(800, 1422), Vector2i(1920, 1080)]:
		var viewport := SubViewport.new()
		viewport.size = shape
		add_child(viewport)
		var host := Control.new()
		host.size = Vector2(shape)
		viewport.add_child(host)
		var router := LayoutRouter.new()
		host.add_child(router)
		router._ensure_loading_controls()
		router._loading_box.visible = true
		router._loading_mascot = PenguinLoader.new(320.0)
		router._loading_box.add_child(router._loading_mascot)
		router._loading_box.move_child(router._loading_mascot, 2)
		router._layout_loading_card()
		await get_tree().process_frame
		await get_tree().process_frame
		var label := "%dx%d" % [shape.x, shape.y]
		var bounds := Rect2(Vector2.ZERO, Vector2(shape))
		var card := router._loading_card.get_global_rect()
		_check(label + "_card_inside_view", bounds.encloses(card))
		_check(label + "_wordmark_inside_view", bounds.encloses(router._loading_wordmark.get_global_rect()))
		_check(label + "_courier_and_message_inside_card", card.encloses(router._loading_mascot.get_global_rect())
			and card.encloses(router._loading_label.get_global_rect()))
		router._loading_box.hide()
		_check(label + "_top_level_wordmark_hides_with_loader", not router._loading_wordmark.is_visible_in_tree())
		router._loading_box.show()
		_check(label + "_top_level_wordmark_returns_with_loader", router._loading_wordmark.is_visible_in_tree())
		var backdrop := FrontEndBackdrop.new()
		backdrop.size = Vector2(shape)
		backdrop.set_presentation(FrontEndBackdrop.Context.LOADING, 0.08, false)
		if shape.y > shape.x:
			_check(label + "_portrait_scene_selected", backdrop.selected_texture_path() == FrontEndBackdrop.LOADING_PORTRAIT_PATH
				and ResourceLoader.exists(backdrop.selected_texture_path()))
			_check(label + "_portrait_card_has_room_for_art", card.size.y >= shape.y * 0.37
				and router._loading_wordmark.size.x >= card.size.x * 0.65)
		else:
			_check(label + "_landscape_scene_preserved", backdrop.selected_texture_path() == FrontEndBackdrop.LOADING_PATH)
		print("[loader_style] geometry ", label, " card=", card,
			" wordmark=", router._loading_wordmark.get_global_rect(), " courier=", router._loading_mascot.get_global_rect())
		backdrop.free()
		viewport.queue_free()
		await get_tree().process_frame


func _check(label: String, passed: bool) -> void:
	if passed:
		_passes += 1
	else:
		_failures += 1
	print("[loader_style] %s %s" % ["PASS" if passed else "FAIL", label])
