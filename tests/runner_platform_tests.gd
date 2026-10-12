extends Node
## Runner platform, quality-governor and accessibility contract checks.
## These are deliberately cheap enough for every headless suite run.

var _passes: int = 0
var _failures: int = 0


class PauseFixture:
	extends RunnerGame

	func _ready() -> void:
		pass

	func _process(_delta: float) -> void:
		pass


func _ready() -> void:
	print("[runner_platform] contract checks starting")
	_test_mobile_orientation()
	_test_layout_profiles()
	_test_portrait_gameplay_layout()
	_test_accessibility_contract()
	_test_runner_accessibility_effects()
	_test_quality_ladder()
	_test_intro_pacing_contract()
	_test_endless_milestones()
	_test_mvp_wardrobe_contract()
	_test_shader_warmup_contract()
	await _test_runner_visible_countdown()
	await _test_runner_touch_pause()
	await _test_runner_pause_feedback()
	_test_runner_tunnel_static_light_contract()
	_test_runner_stream_trace_contract()
	_test_quality_governor_registration()
	# GUI checks can leave pooled one-shot playback alive at immediate headless
	# shutdown. Release that test audio before the Dummy driver is destroyed.
	for player: Node in AudioManager.get_children():
		if player is AudioStreamPlayer or player is AudioStreamPlayer3D:
			player.stop()
			player.stream = null
	await get_tree().create_timer(0.1).timeout
	print("[runner_platform] DONE: %d passed, %d failed" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(check_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("[runner_platform] PASS %s" % check_name)
		return
	_failures += 1
	var suffix := ": %s" % detail if detail != "" else ""
	print("[runner_platform] FAIL %s%s" % [check_name, suffix])


func _test_intro_pacing_contract() -> void:
	_check("gentle_speed_at_two_minutes", RunnerConfig.speed_at(120.0) <= 23.0)
	_check("speed_ceiling_below_reflex_spike", RunnerConfig.speed_at(600.0) <= 27.0)
	var track := RunnerTrack.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 419
	var safe := [RunnerTrack.Pattern.OPEN, RunnerTrack.Pattern.FISH_ARC,
		RunnerTrack.Pattern.LANE_WEAVE, RunnerTrack.Pattern.RAMP_RUN]
	var opening_clear := true
	var intro_safe := true
	for index: int in RunnerTrack.INTRO_CHUNKS:
		var pattern := track._pick_pattern(rng, 0.0, index)
		if index < RunnerTrack.WARMUP_CHUNKS:
			opening_clear = opening_clear and pattern == RunnerTrack.Pattern.OPEN
		else:
			intro_safe = intro_safe and pattern in safe
	_check("four_obstacle_free_opening_chunks", opening_clear)
	_check("intro_has_no_compulsory_jump_slide_or_seal", intro_safe)
	track.free()


func _test_endless_milestones() -> void:
	var original := SaveManager.data.duplicate(true)
	SaveManager.data = SaveManager.default_save()
	var run := PauseFixture.new()
	run._update_biome_milestone(RunnerTrack.BIOME_LENGTH - 1.0)
	_check("biome_not_awarded_early", int(SaveManager.get_value("runner_biome_milestone", 0)) == 0)
	run._update_biome_milestone(RunnerTrack.BIOME_LENGTH + 1.0)
	_check("dusk_milestone_persists", int(SaveManager.get_value("runner_biome_milestone", 0)) == 1)
	var xp := Progression.get_xp()
	run._update_biome_milestone(RunnerTrack.BIOME_LENGTH + 2.0)
	_check("biome_reward_once", Progression.get_xp() == xp)
	var board_script := load("res://scripts/ui/leaderboard_menu.gd") as Script
	var tabs: Array = board_script.call("tabs") if board_script != null else []
	_check("runner_only_leaderboard", tabs.size() == 1)
	run.free()
	SaveManager.data = original


func _test_mvp_wardrobe_contract() -> void:
	var look := CharacterLook.from_equipped({
		"body": "body_rockhopper", "hat": "hat_beanie",
		"scarf": "scarf_red", "goggles": "goggles_ski",
		"trail": "trail_snowflake",
	}, CharacterLook.RenderRole.HERO)
	var visual := PenguinVisual.new()
	visual.setup_look(look)
	_check("mvp_species_uses_visible_legacy_silhouette",
		visual._scale_root != null and visual._scale_root.visible
		and not visual.is_authored_backend_active())
	for socket_id: StringName in [&"head", &"face", &"neck"]:
		var socket := visual.get_socket(socket_id)
		_check("mvp_cosmetic_attached_%s" % socket_id,
			socket != null and socket.get_child_count() > 0)
	var trail := TrailEffect.create("trail_snowflake")
	var trail_mat := (trail.draw_pass_1 as PrimitiveMesh).material as StandardMaterial3D \
		if trail != null else null
	_check("mvp_trail_has_readable_particle_art",
		trail_mat != null and trail_mat.albedo_texture != null)
	if trail != null:
		trail.free()
	var rainbow := TrailEffect.create("trail_rainbow")
	_check("rainbow_trail_has_gradient", rainbow != null and
		(rainbow.process_material as ParticleProcessMaterial).color_ramp != null)
	if rainbow != null:
		rainbow.free()
	var ear_look := CharacterLook.from_equipped({"body": "body_classic",
		"hat": "hat_earwarmers"}, CharacterLook.RenderRole.HERO)
	var ear_visual := PenguinVisual.new()
	ear_visual.setup_look(ear_look)
	var head := ear_visual.get_socket(&"head")
	var has_front_torus := false
	var arch := head.find_child("Headband",true,false) as MeshInstance3D if head != null else null
	if head != null:
		for child: Node in head.find_children("*","MeshInstance3D",true,false):
			if (child as MeshInstance3D).mesh is TorusMesh:
				has_front_torus = true
	# Geometry contract, not the obsolete eight-cylinder implementation: a
	# vertical crown arch spans both ears and rises above the hat socket while
	# staying near its ear plane. A horizontal face-halo cannot satisfy it.
	var arch_bounds := arch.transform * arch.mesh.get_aabb() if arch != null else AABB()
	_check("earwarmers_use_crown_arch_not_face_halo", arch != null and not has_front_torus
		and arch_bounds.size.x >= 0.44 and arch_bounds.size.y >= 0.20
		and arch_bounds.position.y <= -0.07 and arch_bounds.end.y >= 0.08
		and arch_bounds.position.z >= -0.04 and arch_bounds.end.z <= 0.08)
	ear_visual.free()
	visual.free()


func _test_mobile_orientation() -> void:
	var orientation := int(ProjectSettings.get_setting(
		"display/window/handheld/orientation", -1))
	_check("full_sensor_orientation", orientation == DisplayServer.SCREEN_SENSOR,
		"orientation=%d expected=%d" % [orientation, DisplayServer.SCREEN_SENSOR])
	_check("expand_stretch_for_both_aspects",
		String(ProjectSettings.get_setting("display/window/stretch/aspect", "")) == "expand")


func _test_layout_profiles() -> void:
	var cases: Array[Dictionary] = [
		{"size": Vector2(540.0, 960.0), "class": LayoutProfile.ViewClass.PORTRAIT_NARROW,
			"name": "portrait_narrow"},
		{"size": Vector2(1600.0, 1200.0), "class": LayoutProfile.ViewClass.LANDSCAPE_WIDE,
			"name": "landscape_wide"},
		{"size": Vector2(960.0, 540.0), "class": LayoutProfile.ViewClass.LANDSCAPE_COMPACT,
			"name": "landscape_compact"},
		{"size": Vector2(1080.0, 1920.0), "class": LayoutProfile.ViewClass.PORTRAIT_TABLET,
			"name": "portrait_tablet"},
	]
	var insets := Vector4(13.0, 29.0, 17.0, 31.0)
	for row: Dictionary in cases:
		var size: Vector2 = row["size"]
		var expected: LayoutProfile.ViewClass = row["class"]
		var label := String(row["name"])
		var profile := LayoutProfile.for_view_size(size, insets)
		_check("layout_class_%s" % label,
			profile.view_class == expected,
			"got=%s" % profile.class_name_text())
		var expected_safe := Rect2(
			Vector2(insets.x, insets.y),
			Vector2(size.x - insets.x - insets.z, size.y - insets.y - insets.w))
		_check("safe_rect_%s" % label,
			profile.safe_rect.is_equal_approx(expected_safe),
			"got=%s expected=%s" % [profile.safe_rect, expected_safe])
		_check("touch_left_bounded_%s" % label,
			_rect_contains(profile.safe_rect, profile.touch_left_zone),
			str(profile.touch_left_zone))
		_check("touch_right_bounded_%s" % label,
			_rect_contains(profile.safe_rect, profile.touch_right_zone),
			str(profile.touch_right_zone))
		_check("touch_zones_separated_%s" % label,
			profile.touch_left_zone.end.x <= profile.touch_right_zone.position.x)
		_check("presentation_geometry_%s" % label,
			profile.hero_frame_height > 0.0
			and profile.decision_horizon_m > profile.chase_distance
			and profile.base_fov >= 60.0 and profile.base_fov <= 90.0)

	# Raw framebuffer class must downgrade when cutouts/fold/split-view insets
	# leave only compact usable geometry. These are deliberately much larger
	# than ordinary notches so a future regression to `classify(size)` is loud.
	var inset_downgrades: Array[Dictionary] = [
		{
			"name": "landscape_wide_to_compact",
			"size": Vector2(1600.0, 1200.0),
			"insets": Vector4(110.0, 20.0, 110.0, 20.0),
			"class": LayoutProfile.ViewClass.LANDSCAPE_COMPACT,
		},
		{
			"name": "portrait_tablet_to_narrow",
			"size": Vector2(1080.0, 1920.0),
			"insets": Vector4(110.0, 80.0, 110.0, 80.0),
			"class": LayoutProfile.ViewClass.PORTRAIT_NARROW,
		},
	]
	for row: Dictionary in inset_downgrades:
		var downgraded_profile := LayoutProfile.for_view_size(row["size"], row["insets"])
		var downgraded_expected: LayoutProfile.ViewClass = row["class"]
		var downgrade_label := String(row["name"])
		_check("safe_inset_class_%s" % downgrade_label,
			downgraded_profile.view_class == downgraded_expected,
			"got=%s safe=%s" % [downgraded_profile.class_name_text(),
				downgraded_profile.safe_rect])
		_check("safe_inset_touch_bounded_%s" % downgrade_label,
			downgraded_profile.contains_safe_rect(downgraded_profile.touch_left_zone)
			and downgraded_profile.contains_safe_rect(downgraded_profile.touch_right_zone),
			"safe=%s left=%s right=%s" % [
				downgraded_profile.safe_rect, downgraded_profile.touch_left_zone,
				downgraded_profile.touch_right_zone])


func _rect_contains(outer: Rect2, inner: Rect2) -> bool:
	const EPSILON: float = 0.001
	return inner.position.x >= outer.position.x - EPSILON \
		and inner.position.y >= outer.position.y - EPSILON \
		and inner.end.x <= outer.end.x + EPSILON \
		and inner.end.y <= outer.end.y + EPSILON


func _test_portrait_gameplay_layout() -> void:
	_check("portrait_overlay_policy_unblocked",
		not RotateOverlay.blocks_view_size(Vector2(540.0, 960.0)))
	var legacy_overlay := RotateOverlay.new()
	add_child(legacy_overlay)
	_check("portrait_overlay_has_no_input_tree",
		not legacy_overlay.is_input_blocking()
		and legacy_overlay.get_child_count() == 0
		and not legacy_overlay.is_processing_input())
	legacy_overlay.free()

	var cases: Array[Dictionary] = [
		{"name": "portrait", "size": Vector2(540.0, 960.0),
			"insets": Vector4(13.0, 29.0, 17.0, 31.0)},
		{"name": "landscape", "size": Vector2(960.0, 540.0),
			"insets": Vector4(31.0, 13.0, 29.0, 17.0)},
	]
	for row: Dictionary in cases:
		var label := String(row["name"])
		var profile := LayoutProfile.for_view_size(row["size"], row["insets"])
		var runner_zone := RunnerTouch.input_zone_for_profile(profile)
		_check("runner_touch_zone_%s" % label,
			runner_zone.is_equal_approx(profile.safe_rect), str(runner_zone))
		_check("runner_touch_center_allowed_%s" % label,
			RunnerTouch.can_start_at(profile, profile.safe_rect.get_center()))
		_check("runner_touch_unsafe_rejected_%s" % label,
			not RunnerTouch.can_start_at(profile, Vector2.ZERO))
		for scale: float in [0.5, 1.0, 2.0]:
			var rects := TouchControls.button_rects_for_profile(profile, scale)
			for control_id: String in ["shove", "item", "back", "pause"]:
				var rect: Rect2 = rects.get(control_id, Rect2())
				_check("race_touch_%s_%s_x%.1f" % [control_id, label, scale],
					profile.contains_safe_rect(rect) and rect.has_area(),
					"safe=%s rect=%s" % [profile.safe_rect, rect])

	# Zero-inset landscape remains the authored layout, not a new reflow.
	var baseline := LayoutProfile.for_view_size(Vector2(960.0, 540.0))
	var baseline_rects := TouchControls.button_rects_for_profile(baseline)
	var shove_rect: Rect2 = baseline_rects["shove"]
	var item_rect: Rect2 = baseline_rects["item"]
	var back_rect: Rect2 = baseline_rects["back"]
	var pause_rect: Rect2 = baseline_rects["pause"]
	_check("landscape_touch_layout_preserved_shove",
		shove_rect.is_equal_approx(Rect2(680.0, 400.0, 120.0, 120.0)), str(shove_rect))
	_check("landscape_touch_layout_preserved_item",
		item_rect.is_equal_approx(Rect2(820.0, 400.0, 120.0, 120.0)), str(item_rect))
	_check("landscape_touch_layout_preserved_back",
		back_rect.is_equal_approx(Rect2(842.8, 324.4, 74.4, 74.4)), str(back_rect))
	_check("landscape_touch_layout_preserved_pause",
		pause_rect.is_equal_approx(Rect2(694.0, 24.0, 72.0, 72.0)), str(pause_rect))

	# Runtime builder consumes the same pure geometry seam used above.
	var portrait := LayoutProfile.for_view_size(Vector2(540.0, 960.0),
		Vector4(13.0, 29.0, 17.0, 31.0))
	var controller := PlayerController.new()
	add_child(controller)
	var controls := TouchControls.new()
	add_child(controls)
	controls.setup(controller, portrait)
	for control_id: String in ["shove", "item", "back", "pause"]:
		var actual: Rect2 = controls.button_rects().get(control_id, Rect2())
		_check("race_touch_runtime_%s_portrait" % control_id,
			portrait.contains_safe_rect(actual) and actual.has_area(), str(actual))
	controls.free()
	controller.free()
	var runner_player := RunnerPlayer.new()
	var runner_touch := RunnerTouch.new()
	add_child(runner_touch)
	runner_touch.setup(runner_player, portrait)
	runner_touch._begin(Vector2.ZERO)
	_check("runner_touch_runtime_rejects_unsafe_portrait", not runner_touch._tracking)
	runner_touch._begin(portrait.safe_rect.get_center())
	_check("runner_touch_runtime_accepts_safe_portrait", runner_touch._tracking)
	runner_touch.free()
	runner_player.free()


func _test_accessibility_contract() -> void:
	var access: Dictionary = SettingsManager.default_settings().get("accessibility", {})
	_check("camera_shake_mode_valid",
		String(access.get("camera_shake", "")) in ["full", "reduced", "off"])
	for key: String in [
		"high_contrast_pickups", "reduced_flashing", "colorblind_cues",
		"pause_on_disconnect", "audio_visual_cues",
	]:
		_check("accessibility_%s_boolean" % key, access.get(key) is bool)
	var hud_scale := float(access.get("hud_scale", 0.0))
	var ui_scale := float(access.get("ui_scale", 0.0))
	_check("hud_scale_usable", hud_scale >= 0.8 and hud_scale <= 1.6,
		"hud_scale=%.2f" % hud_scale)
	_check("ui_scale_usable", ui_scale >= 0.8 and ui_scale <= 1.6,
		"ui_scale=%.2f" % ui_scale)


func _test_runner_accessibility_effects() -> void:
	var access: Dictionary = SettingsManager.settings.get("accessibility", {})
	var original_shake: Variant = access.get("camera_shake", "full")
	var original_flashing: Variant = access.get("reduced_flashing", false)

	var game := RunnerGame.new()
	access["camera_shake"] = "off"
	game._camera_shake = 0.0
	game._add_camera_shake(0.8)
	_check("runner_camera_shake_off", is_zero_approx(game._camera_shake),
		"shake=%.3f" % game._camera_shake)
	access["camera_shake"] = "reduced"
	game._add_camera_shake(0.8)
	_check("runner_camera_shake_reduced",
		is_equal_approx(game._camera_shake, 0.28),
		"shake=%.3f" % game._camera_shake)
	access["camera_shake"] = "full"
	game._camera_shake = 0.0
	game._add_camera_shake(0.8)
	_check("runner_camera_shake_full",
		is_equal_approx(game._camera_shake, 0.8),
		"shake=%.3f" % game._camera_shake)
	game.free()

	var player := RunnerPlayer.new()
	player.setup({})
	player.invulnerable_for = 0.05  # Inside the normal blink's hidden phase.
	access["reduced_flashing"] = false
	player._drive_visual(0.0)
	_check("runner_mvp_uses_distinct_legacy_species",
		player._visual._root != null and not player._visual.is_authored_backend_active())
	_check("runner_go_starts_run_without_recovery_delay",
		player._visual.pose == PenguinVisual.Pose.RUN)
	_check("runner_iframe_blink_default", not player._visual.visible)
	access["reduced_flashing"] = true
	player._drive_visual(0.0)
	_check("runner_iframe_visible_reduced_flashing", player._visual.visible)
	player.free()

	access["camera_shake"] = original_shake
	access["reduced_flashing"] = original_flashing


func _test_quality_ladder() -> void:
	var web: Dictionary = SettingsManager.WEB_RENDER_SCALE
	var high := float(web.get("high", 0.0))
	var medium := float(web.get("medium", 0.0))
	var low := float(web.get("low", 0.0))
	_check("web_quality_scale_order",
		high >= medium and medium >= low and low > 0.5,
		"high=%.2f medium=%.2f low=%.2f" % [high, medium, low])
	var steps: PackedFloat32Array = SettingsManager.RENDER_SCALE_STEPS
	var monotonic := steps.size() >= 3
	for i: int in range(1, steps.size()):
		monotonic = monotonic and steps[i] <= steps[i - 1]
	_check("governor_scale_steps_monotonic", monotonic, str(steps))
	_check("governor_preserves_native_first",
		steps.size() >= 2 and is_equal_approx(steps[0], 1.0)
		and is_equal_approx(steps[1], 1.0))
	_check("web_screen_space_aa_disabled",
		SettingsManager.WEB_SCREEN_SPACE_AA == Viewport.SCREEN_SPACE_AA_DISABLED)
	_check("governor_targets_halved_vsync",
		SettingsManager.GOVERNOR_MIN_FPS > 30.0
		and SettingsManager.GOVERNOR_MIN_FPS < SettingsManager.GOVERNOR_RESTORE_FPS)
	_check("native_compat_uncapped_is_stable_60",
		SettingsManager.effective_fps_limit(0, "gl_compatibility", 0) == 60)
	_check("native_compat_explicit_120_preserved",
		SettingsManager.effective_fps_limit(120, "gl_compatibility", 0) == 120)
	_check("mobile_uncapped_preserved",
		SettingsManager.effective_fps_limit(0, "mobile", 0) == 0)
	_check("web_browser_pacing_preserved",
		SettingsManager.effective_fps_limit(0, "gl_compatibility", 1) == 0)


func _test_shader_warmup_contract() -> void:
	var track := RunnerTrack.new()
	track._prime_art_cache()
	var streamed_ice_mesh := RunnerTrack._deck_mesh()
	var streamed_ice_material := RunnerTrack._deck_material(
			RunnerTrack.Biome.DUSK, false)
	var tunnel_mesh := RunnerTrack._tunnel_mesh()
	var tunnel_material := RunnerTrack._tunnel_material()
	var tunnel_cue_mesh := RunnerTrack._tunnel_light_cue_mesh()
	var first_count := ShaderWarmup.external_probe_count(RunnerTrack.SHADER_WARMUP_SCOPE)
	track._prime_art_cache()
	var second_count := ShaderWarmup.external_probe_count(RunnerTrack.SHADER_WARMUP_SCOPE)
	_check("runner_warmup_external_probes_registered", first_count > 0,
		"count=%d" % first_count)
	_check("runner_warmup_registration_idempotent", second_count == first_count,
		"first=%d second=%d" % [first_count, second_count])
	_check("runner_warmup_registration_bounded",
		second_count <= ShaderWarmup.MAX_EXTERNAL_PROBES,
		"count=%d max=%d" % [second_count, ShaderWarmup.MAX_EXTERNAL_PROBES])
	_check("runner_warmup_contains_exact_tunnel_pair",
		ShaderWarmup.has_external_probe(tunnel_mesh, tunnel_material, [],
				RunnerTrack.SHADER_WARMUP_SCOPE))
	_check("runner_warmup_contains_exact_tunnel_cue_pair",
		ShaderWarmup.has_external_probe(tunnel_cue_mesh, RunnerTrack._mark_material(), [],
				RunnerTrack.SHADER_WARMUP_SCOPE))
	_check("runner_warmup_contains_exact_streamed_ice_pair",
		ShaderWarmup.has_external_probe(streamed_ice_mesh, streamed_ice_material, [],
				RunnerTrack.SHADER_WARMUP_SCOPE))
	_check("runner_warmup_streamed_ice_shader_exact",
		streamed_ice_material.shader != null
		and streamed_ice_material.shader.resource_path.ends_with("/runner_painted_surface_v1.gdshader"),
		"shader=%s" % (streamed_ice_material.shader.resource_path
				if streamed_ice_material.shader != null else "null"))
	_check("runner_warmup_tunnel_reuses_prop_signature",
		tunnel_material == RunnerTrack._prop_material()
		and tunnel_material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL
		and tunnel_material.cull_mode != BaseMaterial3D.CULL_DISABLED
		and tunnel_material.vertex_color_use_as_albedo)
	_check("runner_warmup_no_extra_two_sided_vertex_colour_signature",
		"2v" not in ShaderWarmup.PROBE_FLAGS)

	# Queue must be stable, exact streamed pairs must own the prefix, and its
	# hard cap must survive any future scene growth.
	var warmup := ShaderWarmup.new()
	var anchor := Node3D.new()
	warmup._world = track
	warmup._external_scope = RunnerTrack.SHADER_WARMUP_SCOPE
	warmup._anchor = anchor
	warmup._build_queue()
	var sequence := PackedStringArray()
	for item: Dictionary in warmup._queue:
		sequence.append("%s:%s" % [item.get("type", ""), item.get("key", "")])
	var external_prefix := mini(first_count, warmup._queue.size())
	var exact_first := external_prefix > 0
	for index: int in warmup._queue.size():
		var item_type := String(warmup._queue[index].get("type", ""))
		exact_first = exact_first and (item_type == "external" if index < external_prefix \
				else item_type != "external")
	var streamed_key := "external:%d:%d" % [streamed_ice_mesh.get_instance_id(),
			streamed_ice_material.get_instance_id()]
	var tunnel_key := "external:%d:%d" % [tunnel_mesh.get_instance_id(),
			tunnel_material.get_instance_id()]
	var queued_keys: PackedStringArray = []
	for item: Dictionary in warmup._queue:
		queued_keys.append(String(item.get("key", "")))
	_check("runner_warmup_exact_streamed_prefix", exact_first,
		"external=%d queue=%d" % [external_prefix, warmup._queue.size()])
	_check("runner_warmup_queue_contains_streamed_keys",
		streamed_key in queued_keys and tunnel_key in queued_keys)
	_check("runner_warmup_queue_bounded",
		warmup._queue.size() <= ShaderWarmup.MAX_INSTANCES,
		"queue=%d max=%d" % [warmup._queue.size(), ShaderWarmup.MAX_INSTANCES])
	warmup._build_queue()
	var rebuilt_sequence := PackedStringArray()
	for item: Dictionary in warmup._queue:
		rebuilt_sequence.append("%s:%s" % [item.get("type", ""), item.get("key", "")])
	_check("runner_warmup_queue_deterministic_rebuild",
		rebuilt_sequence == sequence)

	# Submission owns one rendered-frame slot. Immediate second request cannot
	# add another node; next-frame simulation retains first probe and adds one.
	ShaderWarmup.perf_trace_enabled = true
	ShaderWarmup.clear_perf_trace()
	var first_submitted := warmup._submit_next_item(false)
	var first_probe: Node = anchor.get_child(0) if anchor.get_child_count() > 0 else null
	var immediate_rejected := not warmup._submit_next_item(false)
	var same_frame_count := anchor.get_child_count()
	_check("runner_warmup_one_new_resource_per_frame",
		first_submitted and immediate_rejected and same_frame_count == 1,
		"children=%d" % same_frame_count)
	_check("runner_warmup_trace_waits_for_following_frame",
		ShaderWarmup.drain_perf_trace_events().is_empty())
	ShaderWarmup.perf_trace_enabled = false
	# Engine frames cannot advance inside this synchronous contract test, so
	# both seams that a real rendered frame moves have to be moved by hand:
	# the renderer confirming the previous probe drew (_on_frame_post_draw,
	# which is what clears _awaiting_draw) and the per-frame submit throttle.
	# Resetting only the throttle left _awaiting_draw set, so the next submit
	# was refused and this pair of checks could never pass.
	warmup._on_frame_post_draw()
	warmup._last_submit_frame = -1
	var second_submitted := warmup._submit_next_item(false)
	_check("runner_warmup_prior_probe_retained_through_next_draw",
		second_submitted and anchor.get_child_count() == 2
		and anchor.get_child(0) == first_probe,
		"children=%d" % anchor.get_child_count())
	var exact_draw_pairs := true
	for child: Node in anchor.get_children():
		var probe := child as MeshInstance3D
		exact_draw_pairs = exact_draw_pairs and probe != null \
				and probe.mesh != null and probe.material_override != null
	_check("runner_warmup_queued_probes_submit_draw_instances",
		anchor.get_child_count() == 2 and exact_draw_pairs,
		"draw_instances=%d" % anchor.get_child_count())
	ShaderWarmup.clear_perf_trace()
	warmup._anchor = null
	anchor.free()
	warmup.free()

	# SceneRouter owns the opaque loader and must keep it up while this node is
	# present. Test the real predicate without starting a renderer.
	var pending := ShaderWarmup.new()
	pending.name = "ShaderWarmupContractProbe"
	add_child(pending)
	_check("runner_warmup_loader_holds_until_probe_drawn",
		SceneRouter._scene_is_building())
	remove_child(pending)
	pending.free()
	track.free()


func _test_runner_visible_countdown() -> void:
	# Drive the real orchestrator across a deliberately slow construction seam.
	# Before _ready finishes, dependencies can still be null; time cannot run.
	var game := RunnerGame.new()
	game._process(10.0)
	_check("runner_no_countdown_during_construction",
		is_equal_approx(game._countdown, RunnerGame.COUNTDOWN_TIME)
		and not game.running and is_zero_approx(game.elapsed))
	_check("loader_recognizes_unbuilt_runner_root",
		SceneRouter._subtree_is_building(game))
	add_child(game)
	game.set_process(false)
	# ArtCatalog's asynchronous preload yields even under the headless renderer.
	# Observe actual completion instead of assuming _ready is synchronous.
	for frame: int in 180:
		if game.build_finished:
			break
		await get_tree().process_frame
	_check("runner_headless_build_ready", game.build_finished)
	if not game.build_finished:
		game.free()
		return
	_check("loader_recognizes_finished_runner_root",
		not SceneRouter._subtree_is_building(game))
	var pending := ShaderWarmup.new()
	# Keep this synthetic pending pass out of tree so no renderer is required.
	game._startup_warmup = pending
	game._process(10.0)
	game._toggle_pause()
	_check("runner_cannot_pause_under_loading_overlay", not get_tree().paused)
	_check("runner_hazard_clocks_disabled_while_loading",
		game.track.process_mode == Node.PROCESS_MODE_DISABLED)
	_check("runner_no_countdown_during_warmup",
		is_equal_approx(game._countdown, RunnerGame.COUNTDOWN_TIME)
		and not game.running and not game.player._input_enabled
		and is_zero_approx(game.player.distance))
	pending.free()
	var was_presenting := SceneRouter._presenting
	SceneRouter._presenting = true
	SceneRouter.go_to(Game.SCENE_MAIN_MENU)
	_check("loader_preserves_startup_recovery_redirect",
		SceneRouter._queued_scene_path == Game.SCENE_MAIN_MENU and not SceneRouter._busy)
	SceneRouter._queued_scene_path = ""
	game._process(10.0)
	_check("runner_no_countdown_during_loader_fade",
		is_equal_approx(game._countdown, RunnerGame.COUNTDOWN_TIME)
		and not game._presentation_started and SceneRouter.is_busy())
	SceneRouter._presenting = false
	game._process(10.0)
	_check("runner_discards_last_loading_frame_delta",
		game._presentation_started and not game.running
		and is_equal_approx(game._countdown, RunnerGame.COUNTDOWN_TIME))
	_check("runner_hazard_clocks_resume_for_visible_countdown",
		game.track.process_mode == Node.PROCESS_MODE_INHERIT)
	game._process(0.4)
	_check("runner_visible_countdown_advances",
		is_equal_approx(game._countdown, RunnerGame.COUNTDOWN_TIME - 0.4)
		and not game.running and not game.player._input_enabled)
	game._process(RunnerGame.COUNTDOWN_TIME)
	_check("runner_go_enables_input", game.running and game.player._input_enabled)
	_test_runner_retry_blocked_by_loader(game)
	game.restart()
	_check("runner_idle_retry_resets_previous_result_and_mission_baselines",
		not game._dead and game.running and game.player._input_enabled
		and is_zero_approx(game._score)
		and is_zero_approx(game.elapsed) and game.fish == 0 and game.hits_taken == 0
		and game.ramps_hit == 0 and game.near_misses == 0
		and is_zero_approx(game.missions._last_distance)
		and is_zero_approx(game.missions._clean_base)
		and is_zero_approx(game.missions._persist_distance))
	_check("runner_retry_keeps_warm_presentation",
		game._presentation_started and not is_instance_valid(game._startup_warmup)
		and game._countdown <= 0.0 and game.player._input_enabled
		and is_zero_approx(game.player.distance))
	game._process(0.2)
	_check("runner_retry_moves_on_first_process", game.player.distance > 0.0)
	SceneRouter._presenting = was_presenting
	game.free()

	# Nested probes occur under RunnerGame, not only beneath the scene root.
	var container := Node.new()
	var nested := Node.new()
	container.add_child(nested)
	var nested_probe := ShaderWarmup.new()
	nested.add_child(nested_probe)
	_check("loader_recognizes_nested_warmup", SceneRouter._subtree_is_building(container))
	nested_probe.free()
	_check("loader_releases_finished_nested_warmup",
		not SceneRouter._subtree_is_building(container))
	container.free()


func _test_runner_retry_blocked_by_loader(game: RunnerGame) -> void:
	# Use the initialized runner and real restart entrypoint. No await may run
	# while the actual autoload's flags are borrowed for these callback checks.
	var saved_busy := SceneRouter._busy
	var saved_presenting := SceneRouter._presenting
	for phase: String in ["presenting", "busy"]:
		SceneRouter._busy = phase == "busy"
		SceneRouter._presenting = phase == "presenting"
		game._dead = true
		game.running = false
		game._score = 321.0
		game.elapsed = 17.0
		game.fish = 11
		game.hits_taken = 1
		game.clean_metres = 66.0
		game.ramps_hit = 2
		game.near_misses = 3
		game._countdown = 0.23
		game.player.distance = 148.0
		game.player.state = RunnerPlayer.State.DEAD
		game.player.set_input_enabled(false)
		game.missions._last_distance = 148.0
		game.missions._clean_base = 33.0
		game.missions._persist_distance = 130.0
		var old_player := game.player
		var mission_progress := game.missions._progress.duplicate()
		game.restart()
		_check("runner_%s_retry_preserves_dead_result" % phase,
			game._dead and not game.running and is_equal_approx(game._score, 321.0)
			and is_equal_approx(game.elapsed, 17.0) and game.fish == 11
			and game.hits_taken == 1 and is_equal_approx(game.clean_metres, 66.0)
			and game.ramps_hit == 2 and game.near_misses == 3
			and is_equal_approx(game._countdown, 0.23))
		_check("runner_%s_retry_preserves_exact_dead_player" % phase,
			game.player == old_player and not old_player.is_queued_for_deletion()
			and game.player.state == RunnerPlayer.State.DEAD
			and is_equal_approx(game.player.distance, 148.0) and not game.player._input_enabled)
		_check("runner_%s_retry_preserves_mission_run_state" % phase,
			is_equal_approx(game.missions._last_distance, 148.0)
			and is_equal_approx(game.missions._clean_base, 33.0)
			and is_equal_approx(game.missions._persist_distance, 130.0)
			and game.missions._progress == mission_progress)
	SceneRouter._busy = saved_busy
	SceneRouter._presenting = saved_presenting


func _test_runner_touch_pause() -> void:
	# An actual viewport dispatches shipped HUD input before RunnerTouch's
	# unhandled phase. No renderer, provider or full runner construction needed.
	var saved_insets := LayoutProfile.forced_insets
	var saved_hud_scale: Variant = SettingsManager.settings["accessibility"]["hud_scale"]
	var viewport := SubViewport.new()
	viewport.size = Vector2i(540, 960)
	viewport.handle_input_locally = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var game := PauseFixture.new()
	viewport.add_child(game)
	game.player = RunnerPlayer.new()
	game.add_child(game.player)
	game.hud = RunnerHUD.new()
	game.add_child(game.hud)
	game.hud.setup()
	game.hud.pause_pressed.connect(game._on_hud_pause_pressed)
	game._touch = RunnerTouch.new()
	game.add_child(game._touch)
	game._touch.setup(game.player)
	await get_tree().process_frame
	var button := game.hud._pause_button
	_check("runner_touch_pause_hidden_before_play", not button.visible and button.disabled)
	button.pressed.emit()
	_check("runner_touch_pause_loading_signal_rejected", not get_tree().paused)
	game.build_finished = true
	game._presentation_started = true
	button.pressed.emit()
	_check("runner_touch_pause_countdown_signal_rejected", not get_tree().paused)
	game.running = true
	game.hud.set_pause_available(true)
	button.pressed.emit()
	_check("runner_pause_real_button_opens_existing_overlay",
		get_tree().paused and is_instance_valid(game._pause_layer))
	_check("runner_pause_existing_resume_button_gui_works",
		await _resume_runner_pause(viewport, game))

	for scale: float in [0.8, 1.6]:
		# Rebuild at the real accessibility setting so fonts/style minima scale
		# too, then rotate the same live HUD through both viewport orientations.
		SettingsManager.settings["accessibility"]["hud_scale"] = scale
		game.hud.free()
		game.hud = RunnerHUD.new()
		game.add_child(game.hud)
		game.hud.setup()
		game.hud.pause_pressed.connect(game._on_hud_pause_pressed)
		game.hud.set_pause_available(true)
		button = game.hud._pause_button
		for row: Dictionary in [
			{"name": "portrait", "size": Vector2i(540, 960)},
			{"name": "landscape", "size": Vector2i(960, 540)},
		]:
			viewport.size = row["size"]
			for insets: Vector4 in [Vector4(24, 24, 24, 24), Vector4(13, 29, 47, 31)]:
				LayoutProfile.forced_insets = insets
				game.hud._relayout()
				await get_tree().process_frame
				var profile := LayoutProfile.for_view_size(Vector2(viewport.size), insets)
				var actual := button.get_global_rect()
				var tag := "%s_%s_x%.1f" % [row["name"], str(insets), scale]
				_check("runner_pause_safe_live_%s" % tag,
					profile.contains_safe_rect(actual) and actual.size.x >= 56.0 \
					and actual.size.y >= 56.0, "safe=%s button=%s" % [profile.safe_rect, actual])
				_check("runner_pause_live_matches_budget_%s" % tag,
					actual.is_equal_approx(RunnerHUD.pause_rect_for_profile(profile, scale)))
				_check("runner_pause_no_headline_overlap_%s" % tag,
					not actual.intersects(game.hud._headline_column.get_global_rect()),
					"pause=%s headline=%s" % [actual, game.hud._headline_column.get_global_rect()])
				_check("runner_pause_powerups_below_control_%s" % tag,
					game.hud._powerup_box.get_global_rect().position.y >= actual.end.y)
				await _test_runner_gui_resume_cycle(viewport, game, tag)

	# Both finger 0 and a second finger own their entire pause gesture, even if
	# Resume is activated before the first finger lifts and it moves off-button.
	for index: int in [0, 1]:
		game.player.state = RunnerPlayer.State.RUN
		game.player.lane = 1
		game._touch._begin(Vector2(240, 460))
		var at := button.get_global_rect().get_center()
		_push_runner_touch(viewport, index, at, true)
		_check("runner_pause_touch_%d_dispatch_and_cancel" % index,
			get_tree().paused and viewport.is_input_handled() \
			and not game._touch._tracking and not game._touch._fired)
		if index == 0:
			_push_runner_emulated_mouse(viewport, at, true)
			_check("runner_pause_touch_emulated_mouse_no_double_toggle",
				get_tree().paused and viewport.is_input_handled())
		# Finger 0 is still held, so a real mouse activates Resume in that case.
		# Finger 1 may stay held while synthetic finger-0 mouse emulation resumes.
		_check("runner_pause_touch_%d_gui_resume" % index,
			await _resume_runner_pause(viewport, game, index != 0))
		var drag := InputEventScreenDrag.new()
		drag.index = index
		drag.position = at + Vector2(-180, 130)
		viewport.push_input(drag, true)
		_check("runner_pause_touch_%d_drag_consumed" % index, viewport.is_input_handled())
		_push_runner_touch(viewport, index, drag.position, false)
		_check("runner_pause_touch_%d_release_consumed_no_movement" % index,
			viewport.is_input_handled() and game.player.state == RunnerPlayer.State.RUN \
			and game.player.lane == 1 and not get_tree().paused)
		if index == 0:
			_push_runner_emulated_mouse(viewport, drag.position, false)
			_check("runner_pause_touch_emulated_release_cannot_repause",
				viewport.is_input_handled() and not get_tree().paused)
		# Existing overlay disposal is deferred; do not let its departing scrim
		# invalidate the next unrelated-gesture positive control.
		await get_tree().process_frame

	# Positive controls: unrelated gestures still reach the real recognizer.
	game._touch.setup(game.player)
	var gameplay_at := Vector2(240, 460)
	_push_runner_touch(viewport, 2, gameplay_at, true)
	_push_runner_touch(viewport, 2, gameplay_at, false)
	_check("runner_pause_unowned_tap_still_jumps", game.player.state == RunnerPlayer.State.JUMP)
	game.player.state = RunnerPlayer.State.RUN
	_push_runner_touch(viewport, 2, gameplay_at, true)
	var gameplay_drag := InputEventScreenDrag.new()
	gameplay_drag.index = 2
	gameplay_drag.position = gameplay_at + Vector2(80, 0)
	viewport.push_input(gameplay_drag, true)
	_push_runner_touch(viewport, 2, gameplay_drag.position, false)
	_check("runner_pause_unowned_swipe_still_changes_lane", game.player.lane == 2)

	var saved_busy := SceneRouter._busy
	SceneRouter._busy = true
	button.pressed.emit()
	_check("runner_touch_pause_busy_rejected", not get_tree().paused)
	SceneRouter._busy = saved_busy
	game._dead = true
	game.running = false
	game.hud.show_game_over({})
	button.pressed.emit()
	game._toggle_pause()
	_check("runner_touch_pause_results_hidden_and_rejected",
		not button.visible and button.disabled and not get_tree().paused)
	game.hud.hide_game_over()
	game._dead = false
	button.pressed.emit()
	_check("runner_touch_pause_no_active_run_rejected", not get_tree().paused)
	LayoutProfile.forced_insets = saved_insets
	SettingsManager.settings["accessibility"]["hud_scale"] = saved_hud_scale
	viewport.free()


func _test_runner_pause_feedback() -> void:
	# Feedback is inside the pause footer. Put the covered HUD pause hit target
	# underneath it deliberately: lower-layer raw input must not steal gestures.
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.handle_input_locally = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var game := PauseFixture.new()
	viewport.add_child(game)
	game.hud = RunnerHUD.new()
	game.add_child(game.hud)
	game.hud.setup()
	game.hud.set_pause_available(true)
	game.hud.pause_pressed.connect(game._on_hud_pause_pressed)
	game.build_finished = true
	game._presentation_started = true
	game.running = true
	game._toggle_pause()
	await get_tree().process_frame
	await get_tree().process_frame
	var feedback := game._pause_layer.find_child("PauseFeedback", true, false) as Button
	var card := game._pause_layer.find_child("PauseCard", true, false) as Control
	_check("pause_feedback_inside_reference_card", card.get_global_rect().encloses(feedback.get_global_rect()))
	game.hud._pause_button.global_position = feedback.global_position
	var overlap := feedback.get_global_rect().intersection(game.hud._pause_button.get_global_rect())
	_check("pause_feedback_reproduces_covered_hud_overlap", overlap.has_area())
	var at := overlap.get_center()
	var count := {"value":0}
	feedback.pressed.connect(func() -> void: count["value"] += 1)
	var motion := InputEventMouseMotion.new()
	motion.device = InputEvent.DEVICE_ID_EMULATION
	motion.position = at
	motion.global_position = at
	viewport.push_input(motion, true)
	_push_runner_touch(viewport, 0, at, true)
	_push_runner_emulated_mouse(viewport, at, true)
	_push_runner_touch(viewport, 0, at, false)
	_push_runner_emulated_mouse(viewport, at, false)
	var form := game._pause_layer.get_node_or_null("FeedbackForm")
	_check("pause_feedback_new_touch_reaches_overlay_once", count["value"] == 1 and form != null)
	_check("pause_feedback_never_resumes_or_owns_new_touch", get_tree().paused
		and game.hud._pause_button._touches.is_empty() and not game.hud._pause_button._emulated_press)
	if form != null:
		form.call("_close")
	await get_tree().process_frame
	_check("pause_feedback_close_preserves_pause", get_tree().paused and is_instance_valid(game._pause_layer))
	_check("pause_feedback_resume_still_works", await _resume_runner_pause(viewport, game))
	viewport.free()


func _test_runner_gui_resume_cycle(viewport: SubViewport, game: RunnerGame, tag: String) -> void:
	game.player.state = RunnerPlayer.State.RUN
	game.player.lane = 1
	game._touch.cancel_gesture()
	var at := game.hud._pause_button.get_global_rect().get_center()
	# Keep the pause-origin second finger held while GUI Resume uses finger 0.
	_push_runner_touch(viewport, 1, at, true)
	_check("runner_resume_gui_pause_entry_%s" % tag,
		get_tree().paused and viewport.is_input_handled())
	_check("runner_resume_gui_emulated_touch_%s" % tag,
		await _resume_runner_pause(viewport, game))
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = at + Vector2(-180, 130)
	viewport.push_input(drag, true)
	_check("runner_resume_gui_origin_drag_consumed_%s" % tag, viewport.is_input_handled())
	_push_runner_touch(viewport, 1, drag.position, false)
	_check("runner_resume_gui_origin_release_no_movement_%s" % tag,
		viewport.is_input_handled() and not get_tree().paused \
		and game.player.state == RunnerPlayer.State.RUN and game.player.lane == 1)
	await get_tree().process_frame
	# A new finger-0 pause must still work. Release its entire emulated stream
	# while paused before using that finger for a separate GUI Resume tap.
	_push_runner_touch(viewport, 0, at, true)
	_push_runner_emulated_mouse(viewport, at, true)
	_check("runner_resume_gui_second_pause_no_double_toggle_%s" % tag,
		get_tree().paused and viewport.is_input_handled())
	_push_runner_touch(viewport, 0, at, false)
	_push_runner_emulated_mouse(viewport, at, false)
	_check("runner_resume_gui_pause_release_stays_paused_%s" % tag,
		get_tree().paused and viewport.is_input_handled() \
		and game.player.state == RunnerPlayer.State.RUN and game.player.lane == 1)
	_check("runner_resume_gui_second_resume_%s" % tag,
		await _resume_runner_pause(viewport, game))
	_check("runner_resume_gui_cycle_no_movement_%s" % tag,
		not get_tree().paused and game._pause_layer == null \
		and game.player.state == RunnerPlayer.State.RUN and game.player.lane == 1 \
		and not game._touch._tracking and game.hud._pause_button._touches.is_empty())
	await get_tree().process_frame


func _resume_runner_pause(viewport: SubViewport, game: RunnerGame, emulate_touch: bool = true) -> bool:
	if not is_instance_valid(game._pause_layer):
		return false
	# Containers need real process frames to sort the newly created overlay.
	# These are engine-dispatched GUI events, not physical OS/device input.
	await get_tree().process_frame
	await get_tree().process_frame
	for child: Node in game._pause_layer.find_children("*", "Button", true, false):
		var button := child as Button
		if button.text.to_lower().contains("resume"):
			var rect := button.get_global_rect()
			if not button.is_visible_in_tree() or not rect.has_area() \
					or not Rect2(Vector2.ZERO, Vector2(viewport.size)).encloses(rect):
				game._close_pause()
				return false
			var activations := {"count": 0}
			button.pressed.connect(func() -> void: activations["count"] += 1)
			var at := rect.get_center()
			var device := InputEvent.DEVICE_ID_EMULATION if emulate_touch else 0
			var motion := InputEventMouseMotion.new()
			motion.device = device
			motion.position = at
			motion.global_position = at
			viewport.push_input(motion, true)
			if emulate_touch:
				_push_runner_touch(viewport, 0, at, true)
			_push_runner_gui_mouse(viewport, at, true, device)
			if emulate_touch:
				_push_runner_touch(viewport, 0, at, false)
			_push_runner_gui_mouse(viewport, at, false, device)
			var resumed := not get_tree().paused and game._pause_layer == null \
				and int(activations["count"]) == 1 and viewport.is_input_handled()
			# A failed GUI assertion remains RED; cleanup only prevents that
			# failure from leaving later, unrelated positive controls paused.
			if not resumed and is_instance_valid(game._pause_layer):
				game._close_pause()
			return resumed
	game._close_pause()
	return false


func _push_runner_touch(viewport: SubViewport, index: int, at: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = down
	viewport.push_input(event, true)


func _push_runner_emulated_mouse(viewport: SubViewport, at: Vector2, down: bool) -> void:
	_push_runner_gui_mouse(viewport, at, down, InputEvent.DEVICE_ID_EMULATION)


func _push_runner_gui_mouse(viewport: SubViewport, at: Vector2, down: bool, device: int) -> void:
	var event := InputEventMouseButton.new()
	event.device = device
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.position = at
	event.global_position = at
	event.pressed = down
	viewport.push_input(event, true)


func _test_runner_tunnel_static_light_contract() -> void:
	var track := RunnerTrack.new()
	track.setup_golden_slice(20260818, 1)
	var first := _tunnel_static_cue_status(track)
	_check("runner_tunnel_static_two_cues",
		int(first.get("tunnel_chunks", -1)) == 1
		and int(first.get("cue_instances", -1)) == 2,
		str(first))
	_check("runner_tunnel_static_no_dynamic_lights",
		int(first.get("dynamic_lights", -1)) == 0, str(first))
	_check("runner_tunnel_static_existing_signature",
		bool(first.get("material_ok", false))
		and bool(first.get("mesh_ok", false)), str(first))

	# Instant retry replaces chunks, never accumulating lights or cue nodes.
	track.setup_golden_slice(20260818, 1)
	var retry := _tunnel_static_cue_status(track)
	_check("runner_tunnel_static_retry_no_growth",
		int(retry.get("tunnel_chunks", -1)) == 1
		and int(retry.get("cue_nodes", -1)) == 1
		and int(retry.get("cue_instances", -1)) == 2
		and int(retry.get("dynamic_lights", -1)) == 0, str(retry))

	# Stream churn preserves two static cues per resident tunnel and never mints
	# a dynamic OmniLight3D.
	track.setup(20260818, 1.0, 1)
	var churn_ok := true
	for current: int in range(1, 42):
		track.update_stream(-float(current) * RunnerConfig.CHUNK_LENGTH,
				minf(1.0, float(current) / 40.0))
		var status := _tunnel_static_cue_status(track)
		churn_ok = churn_ok \
				and int(status.get("dynamic_lights", -1)) == 0 \
				and int(status.get("cue_instances", -1)) \
						== int(status.get("tunnel_chunks", -1)) \
								* RunnerTrack.TUNNEL_LIGHT_CUES_PER_CHUNK \
				and int(status.get("cue_nodes", -1)) \
						== int(status.get("tunnel_chunks", -1))
	_check("runner_tunnel_static_churn_parity_no_lights", churn_ok)
	track.free()


func _tunnel_static_cue_status(track: RunnerTrack) -> Dictionary:
	var status := {
		"tunnel_chunks": 0,
		"cue_nodes": 0,
		"cue_instances": 0,
		"dynamic_lights": 0,
		"material_ok": true,
		"mesh_ok": true,
	}
	_collect_tunnel_static_cues(track, status, false)
	return status


func _collect_tunnel_static_cues(node: Node, status: Dictionary,
		inside_tunnel: bool) -> void:
	var in_tunnel := inside_tunnel
	var chunk := node as RunnerTrack.RunnerChunk
	if chunk != null and chunk.pattern == RunnerTrack.Pattern.TUNNEL:
		in_tunnel = true
		status["tunnel_chunks"] = int(status["tunnel_chunks"]) + 1
	if in_tunnel and (node is OmniLight3D or node is SpotLight3D):
		status["dynamic_lights"] = int(status["dynamic_lights"]) + 1
	var cues := node as MultiMeshInstance3D
	if in_tunnel and cues != null and cues.name == "TunnelLightCues":
		status["cue_nodes"] = int(status["cue_nodes"]) + 1
		var count := cues.multimesh.instance_count if cues.multimesh != null else 0
		status["cue_instances"] = int(status["cue_instances"]) + count
		status["material_ok"] = bool(status["material_ok"]) \
				and cues.material_override == RunnerTrack._mark_material()
		status["mesh_ok"] = bool(status["mesh_ok"]) \
				and cues.multimesh != null \
				and cues.multimesh.mesh == RunnerTrack._tunnel_light_cue_mesh()
	for child: Node in node.get_children():
		_collect_tunnel_static_cues(child, status, in_tunnel)


func _test_runner_stream_trace_contract() -> void:
	_check("runner_stream_trace_disabled_by_default",
		not RunnerTrack.perf_trace_enabled)
	RunnerTrack.perf_trace_enabled = true
	var track := RunnerTrack.new()
	track.setup(20260818, 0.0, 0)
	var opening := track.drain_perf_trace_events()
	var spawn_count := 0
	var stages_complete := true
	for event: Dictionary in opening:
		if event.get("kind") != "spawn":
			continue
		spawn_count += 1
		for key: String in [
				"frame", "chunk", "biome", "pattern", "select_us", "deck_us",
				"dressing_us", "tunnel_us", "pattern_us", "powerup_us",
				"finish_us", "range_us", "total_us",
		]:
			stages_complete = stages_complete and event.has(key)
	_check("runner_stream_trace_opening_chunks",
		spawn_count == RunnerConfig.CHUNKS_AHEAD,
		"spawns=%d" % spawn_count)
	_check("runner_stream_trace_stage_cpu_fields", stages_complete)

	track.update_stream(-RunnerConfig.CHUNK_LENGTH * 4.0, 0.2)
	var churn := track.drain_perf_trace_events()
	var stream_event: Dictionary = {}
	for event: Dictionary in churn:
		if event.get("kind") == "stream":
			stream_event = event
	_check("runner_stream_trace_spawn_retire_counts",
		int(stream_event.get("spawned", 0)) == 1
		and int(stream_event.get("retired", 0)) == 2,
		str(stream_event))
	var snapshot := track.perf_trace_snapshot(-RunnerConfig.CHUNK_LENGTH * 4.0)
	_check("runner_stream_trace_snapshot",
		int(snapshot.get("current_chunk", -1)) == 4
		and snapshot.has("tunnel_chunks") and snapshot.has("tunnel_lights"),
		str(snapshot))
	RunnerTrack.perf_trace_enabled = false
	track.free()


func _test_quality_governor_registration() -> void:
	var course := Node.new()
	course.add_to_group(&"course")
	add_child(course)
	_check("race_registered_with_governor",
		SettingsManager._quality_governor_gameplay_active())
	remove_child(course)
	course.free()

	var packed := load(Game.SCENE_RUNNER) as PackedScene
	if packed == null:
		_check("runner_scene_loads_for_governor", false)
		return
	var runner := packed.instantiate()
	_check("runner_registered_with_governor",
		SettingsManager._is_quality_governed_scene(runner),
		"scene=%s" % runner.scene_file_path)
	runner.free()
