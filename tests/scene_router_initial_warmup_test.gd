extends Node3D
## Windowed loader regression: real InitialVisualWarmup, current Camera3D,
## 360 original geometry nodes, and actual frame_post_draw callbacks only.
## This proves draw/state ordering within the existing wall deadline, not GPU
## compilation, a physical frame rate, or the Android cold-load root cause.
## Run from an isolated-user-data project; headless execution is an error.

const VISUAL_COUNT: int = 360


class PendingWorld:
	extends CourseBase

	func _ready() -> void:
		pass


class RouterProbe:
	extends "res://scripts/utilities/scene_router.gd"

	func _ready() -> void:
		# Keep the real watchdog, subtree/build checks, recovery, fade and final
		# drawn boundary. Only expensive frontend decoration is absent.
		process_mode = Node.PROCESS_MODE_ALWAYS
		_overlay_layer = CanvasLayer.new()
		_overlay_layer.layer = 100
		add_child(_overlay_layer)
		_fade_rect = ColorRect.new()
		_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_fade_rect.color = Color(0.03, 0.06, 0.12, 1.0)
		_fade_rect.modulate.a = 1.0
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
		_overlay_layer.add_child(_fade_rect)
		_loading_card = PanelContainer.new()
		_loading_card.set_anchors_preset(Control.PRESET_CENTER)
		_fade_rect.add_child(_loading_card)
		_loading_box = VBoxContainer.new()
		_loading_card.add_child(_loading_box)
		_loading_label = Label.new()
		_loading_box.add_child(_loading_label)
		_loading_progress = ProgressBar.new()
		_loading_progress.max_value = 1.0
		_loading_box.add_child(_loading_progress)
		_loading_recovery = VBoxContainer.new()
		_loading_recovery.visible = false
		_loading_box.add_child(_loading_recovery)
		_retry_button = Button.new()
		_back_button = Button.new()
		_loading_recovery.add_child(_retry_button)
		_loading_recovery.add_child(_back_button)


var _world: PendingWorld
var _camera: Camera3D
var _probe: RouterProbe
var _warmup: InitialVisualWarmup
var _visuals: Array[MeshInstance3D] = []
var _trace: Array[Dictionary] = []
var _started_msec: int = 0
var _completed_msec: int = -1
var _draws: int = 0
var _clear_draws: int = 0
var _initial_queue_size: int = 0
var _first_recovery: Dictionary = {}
var _warmup_complete: bool = false
var _premature_uncover: bool = false
var _finished: bool = false
var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if GameConfig.is_headless():
		push_error("scene_router_initial_warmup requires a rendering window")
		get_tree().quit(1)
		return
	get_tree().paused = false
	# Other actual-window fixtures request foreground too. This is a window
	# setup prerequisite, not proof that focus/occlusion caused a prior timeout.
	DisplayServer.window_move_to_foreground()
	_world = PendingWorld.new()
	_world.name = "PendingWarmupWorld"
	add_child(_world)
	_camera = Camera3D.new()
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = 60.0
	_camera.far = 20.0
	_world.add_child(_camera)
	_camera.make_current()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 0.12
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.24, 0.78, 0.88)
	for index: int in VISUAL_COUNT:
		var visual := MeshInstance3D.new()
		visual.name = "ActualVisual%03d" % index
		visual.mesh = mesh
		visual.material_override = material
		visual.position = Vector3((index % 24 - 11.5) * 0.16,
				(floori(float(index) / 24.0) - 7.0) * 0.16, -6.0)
		_world.add_child(visual)
		_visuals.append(visual)
	_probe = RouterProbe.new()
	add_child(_probe)
	_probe._busy = false
	_probe._presenting = true
	_probe._active_scene_path = Game.SCENE_RUNNER
	InitialVisualWarmup.perf_trace_enabled = true
	InitialVisualWarmup.clear_perf_trace()
	_started_msec = Time.get_ticks_msec()
	_warmup = InitialVisualWarmup.warm(_world)
	if _warmup == null:
		push_error("scene_router_initial_warmup did not create real warmup")
		get_tree().quit(1)
		return
	_initial_queue_size = _warmup._visible_queue.size()
	_warmup.completed.connect(_on_warmup_completed)
	RenderingServer.frame_post_draw.connect(_on_actual_draw)
	_probe._fade_out_when_scene_drawn()


func _on_warmup_completed() -> void:
	_warmup_complete = true
	_completed_msec = Time.get_ticks_msec()
	_trace = InitialVisualWarmup.drain_perf_trace_events()
	# Lift the real subtree latch only after the real full-scene settle draw.
	_world.build_finished = true


func _on_actual_draw() -> void:
	_draws += 1
	if not _warmup_complete:
		_premature_uncover = _premature_uncover or not _probe.is_presenting() \
				or not _probe._fade_rect.visible or _probe._fade_rect.modulate.a < 0.999
	if _probe._recovery_active and _first_recovery.is_empty():
		_first_recovery = {
			"draw": _draws,
			"elapsed_msec": Time.get_ticks_msec() - _started_msec,
			"cursor": _warmup._cursor if is_instance_valid(_warmup) else VISUAL_COUNT,
		}
	if not _probe._fade_rect.visible and _probe.is_presenting():
		_clear_draws += 1


func _process(_delta: float) -> void:
	if _finished or _probe == null:
		return
	# Let a premature recovery's ALWAYS warmup finish, so RED proves that the
	# healthy pass completes before the unchanged wall deadline despite recovery.
	if _warmup_complete and (_probe._recovery_active or not _probe.is_presenting()):
		_finish()
	elif Time.get_ticks_msec() - _started_msec > 32_000:
		_finish()


func _finish() -> void:
	_finished = true
	# Completion normally drains the trace. Preserve partial submissions on a
	# timeout too; an empty local trace must not masquerade as zero progress.
	if not _warmup_complete:
		_trace = InitialVisualWarmup.drain_perf_trace_events()
	_check("real_current_camera_retained", get_viewport().get_camera_3d() == _camera)
	_check("more_than_300_actual_geometry_nodes_queued", _initial_queue_size == VISUAL_COUNT)
	_check("warmup_completed_within_unchanged_30_second_limit",
		_warmup_complete and _completed_msec - _started_msec < 30_000)
	_check("no_uncover_before_actual_warmup_settle", not _premature_uncover)
	var visual_events := 0
	var settle_events := 0
	var summary_events := 0
	var previous_frame := -1
	var distinct_frames := true
	for row: Dictionary in _trace:
		if row.get("phase") == "visual" or row.get("phase") == "settle":
			var frame := int(row["submit_frame"])
			distinct_frames = distinct_frames and frame > previous_frame
			previous_frame = frame
			if row["phase"] == "visual":
				visual_events += 1
			else:
				settle_events += 1
		elif row.get("phase") == "complete":
			summary_events += 1
	_check("all_original_submissions_and_settle_reached_actual_draw",
		visual_events == VISUAL_COUNT and settle_events == 1 and summary_events == 1)
	_check("one_submission_per_distinct_process_frame", distinct_frames and visual_events == VISUAL_COUNT)
	_check("advancing_warmup_does_not_latch_premature_recovery",
		_first_recovery.is_empty() and not _probe._recovery_active)
	_check("actual_final_clear_draw_precedes_gameplay_release",
		_clear_draws > 0 and not _probe.is_presenting() and not _probe.is_busy()
		and _probe._loading_deadline_msec == -1 and not get_tree().paused)
	print("[scene_router_initial_warmup] evidence=" + JSON.stringify({
		"actual_draws": _draws,
		"queue_size": _initial_queue_size,
		"completed_msec": _completed_msec - _started_msec if _warmup_complete else -1,
		"visual_events": visual_events,
		"settle_events": settle_events,
		"clear_draws": _clear_draws,
		"first_recovery": _first_recovery,
		"window_focused": get_window().has_focus(),
		"window_visible": get_window().visible,
		"tree_paused": get_tree().paused,
		"warmup_alive": is_instance_valid(_warmup),
		"warmup_cursor": _warmup._cursor if is_instance_valid(_warmup) else null,
		"warmup_awaiting_draw": _warmup._awaiting_draw if is_instance_valid(_warmup) else null,
		"warmup_can_process": _warmup.can_process() if is_instance_valid(_warmup) else null,
		"engine_max_fps": Engine.max_fps,
		"renderer": RenderingServer.get_current_rendering_method(),
		"gpu_performance_claim": false,
		"android_cold_timeout_root_cause_proven": false,
	}))
	InitialVisualWarmup.perf_trace_enabled = false
	print("[scene_router_initial_warmup] DONE: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(label: String, ok: bool) -> void:
	if ok:
		_passed += 1
		print("[scene_router_initial_warmup] PASS " + label)
	else:
		_failed += 1
		print("[scene_router_initial_warmup] FAIL " + label)


func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_actual_draw):
		RenderingServer.frame_post_draw.disconnect(_on_actual_draw)
	InitialVisualWarmup.perf_trace_enabled = false
