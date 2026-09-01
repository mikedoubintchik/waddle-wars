extends Node
## Runner platform, quality-governor and accessibility contract checks.
## These are deliberately cheap enough for every headless suite run.

var _passes: int = 0
var _failures: int = 0


func _ready() -> void:
	print("[runner_platform] contract checks starting")
	_test_mobile_orientation()
	_test_layout_profiles()
	_test_portrait_gameplay_layout()
	_test_accessibility_contract()
	_test_runner_accessibility_effects()
	_test_quality_ladder()
	_test_shader_warmup_contract()
	_test_runner_tunnel_static_light_contract()
	_test_runner_stream_trace_contract()
	_test_quality_governor_registration()
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
	var first_count := ShaderWarmup.external_probe_count()
	track._prime_art_cache()
	var second_count := ShaderWarmup.external_probe_count()
	_check("runner_warmup_external_probes_registered", first_count > 0,
		"count=%d" % first_count)
	_check("runner_warmup_registration_idempotent", second_count == first_count,
		"first=%d second=%d" % [first_count, second_count])
	_check("runner_warmup_registration_bounded",
		second_count <= ShaderWarmup.MAX_EXTERNAL_PROBES,
		"count=%d max=%d" % [second_count, ShaderWarmup.MAX_EXTERNAL_PROBES])
	_check("runner_warmup_contains_exact_tunnel_pair",
		ShaderWarmup.has_external_probe(tunnel_mesh, tunnel_material))
	_check("runner_warmup_contains_exact_tunnel_cue_pair",
		ShaderWarmup.has_external_probe(tunnel_cue_mesh, RunnerTrack._mark_material()))
	_check("runner_warmup_contains_exact_streamed_ice_pair",
		ShaderWarmup.has_external_probe(streamed_ice_mesh, streamed_ice_material))
	_check("runner_warmup_streamed_ice_shader_exact",
		streamed_ice_material.shader != null
		and streamed_ice_material.shader.resource_path.ends_with("/ice.gdshader"),
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
