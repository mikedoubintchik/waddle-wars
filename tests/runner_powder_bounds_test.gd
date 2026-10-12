extends Node
## Projection/property regression for the countdown powder cutoff. This does
## not replace raster review: it verifies below-frame geometry and unchanged
## painted crest, using the actual Sprite3D texture and camera projection.

var _passes: int = 0
var _failures: int = 0


func _ready() -> void:
	for size: Vector2i in [Vector2i(960, 540), Vector2i(540, 960)]:
		var viewport := SubViewport.new()
		viewport.size = size
		viewport.own_world_3d = true
		add_child(viewport)
		var camera := Camera3D.new()
		viewport.add_child(camera)
		camera.make_current()
		var chaser := RunnerChaser.new()
		viewport.add_child(chaser)
		chaser._build_intro_wave()
		for opening: bool in [true, false]:
			camera.position = Vector3(0.0, 5.425, 8.282635) if opening else Vector3(0.0, 3.1, 5.678635)
			camera.fov = 80.0 if opening else 72.0
			camera.look_at(Vector3(0.0, 1.35, -12.0), Vector3.UP)
			chaser._intro_wave.position = Vector3(0.0, 0.0, 3.2)
			var crests: Array[float] = []
			for spray: Sprite3D in [chaser._intro_back, chaser._intro_front]:
				spray.position.y = 0.96
				spray.scale.y = 0.47
				crests.append(spray.global_position.y + _height(spray) * (0.5 - RunnerHUDArt.POWDER_CREST))
			chaser._extend_powder_below_frame(camera)
			for index: int in 2:
				var spray: Sprite3D = chaser._intro_back if index == 0 else chaser._intro_front
				var label := "%dx%d_%s_layer%d" % [size.x, size.y, "opening" if opening else "running", index]
				var height := _height(spray)
				var bottom := camera.unproject_position(spray.global_position - Vector3.UP * height * 0.5)
				_check(label + "_not_cut_by_floor", spray.no_depth_test)
				_check(label + "_bottom_below_view", bottom.y >= float(size.y) * 1.04 - 0.01)
				_check(label + "_crest_preserved", is_equal_approx(
					spray.global_position.y + height * (0.5 - RunnerHUDArt.POWDER_CREST), crests[index]))
		_test_catch_handoff(chaser, camera, size)
		viewport.queue_free()
	await get_tree().process_frame
	print("[runner_powder_bounds] DONE: %d passed, %d failed" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _height(spray: Sprite3D) -> float:
	return spray.texture.get_height() * spray.pixel_size * spray.scale.y


func _test_catch_handoff(chaser: RunnerChaser, camera: Camera3D, size: Vector2i) -> void:
	var label := "%dx%d_catch" % [size.x, size.y]
	chaser._time = 1.0
	chaser.set_intro_preview(1.0, 0.0, 0.01)
	var crest := camera.unproject_position(chaser._intro_front.global_position \
		+ Vector3.UP * _height(chaser._intro_front) * (0.5 - RunnerHUDArt.POWDER_CREST))
	var expected_crest := clampf(crest.y / float(size.y), 0.90, 0.98)
	chaser.overrun()
	_check(label + "_retires_moving_3d_preview", not chaser._intro_wave.visible)
	_check(label + "_canvas_is_immediately_opaque", chaser._catch_canvas.visible
		and is_equal_approx(chaser._catch_snow.modulate.a, 1.0))
	_check(label + "_canvas_starts_at_previous_crest", is_equal_approx(
		(chaser._catch_snow.position.y + chaser._catch_snow.size.y * RunnerHUDArt.POWDER_CREST) / float(size.y), expected_crest))
	_check(label + "_caught_scene_not_premature", is_zero_approx(chaser._catch_illustration.modulate.a))
	chaser.present_overrun(0.45)
	_check(label + "_no_old_snow_ribbon_mid_catch", not chaser._intro_wave.visible)
	_check(label + "_canvas_bottom_stays_beyond_view", chaser._catch_snow.position.y
		+ chaser._catch_snow.size.y > float(size.y))
	chaser.present_overrun(0.90)
	_check(label + "_caught_scene_dissolves_after_surge", chaser._catch_illustration.modulate.a > 0.0
		and chaser._catch_illustration.modulate.a < 1.0)
	chaser.present_overrun(1.0)
	_check(label + "_caught_scene_matches_results_art", is_equal_approx(chaser._catch_illustration.modulate.a, 1.0)
		and chaser._catch_illustration.texture == RunnerHUDArt.caught_background(size.y >= size.x))
	chaser.reset()
	chaser._time = 1.0
	chaser.set_intro_preview(1.0, 0.0, 0.01)
	var powder_position := chaser._intro_wave.global_position
	var initial_alpha := chaser._intro_front.modulate.a
	chaser.overrun(true)
	_check(label + "_reduced_retains_initial_powder", chaser._intro_wave.visible
		and is_zero_approx(chaser._catch_snow.modulate.a))
	chaser.present_overrun(0.45)
	_check(label + "_reduced_powder_stays_stationary", chaser._intro_wave.global_position.is_equal_approx(powder_position))
	_check(label + "_reduced_crossfade_is_gentle", chaser._intro_front.modulate.a > 0.0
		and chaser._intro_front.modulate.a < initial_alpha
		and chaser._catch_snow.modulate.a > 0.0 and chaser._catch_snow.modulate.a < 1.0)
	chaser.present_overrun(1.0)
	_check(label + "_reduced_retires_old_powder_after_dissolve", not chaser._intro_wave.visible
		and is_equal_approx(chaser._catch_snow.modulate.a, 1.0))
	_check(label + "_reduced_caught_scene_stays_fixed", chaser._catch_illustration.position == Vector2.ZERO
		and chaser._catch_illustration.scale == Vector2.ONE
		and is_equal_approx(chaser._catch_illustration.modulate.a, 1.0))
	chaser.reset()
	_check(label + "_retry_clears_both_layers", not chaser._catch_canvas.visible
		and not chaser._intro_wave.visible and not chaser._overrunning)
	_check(label + "_retry_clears_caught_illustration", is_zero_approx(chaser._catch_illustration.modulate.a))


func _check(label: String, passed: bool) -> void:
	if passed:
		_passes += 1
	else:
		_failures += 1
	print("[runner_powder_bounds] %s %s" % ["PASS" if passed else "FAIL", label])
