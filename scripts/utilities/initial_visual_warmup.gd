class_name InitialVisualWarmup
extends Node
## Experimental runner-only first-draw staging, before ShaderWarmup probes.
##
## An opaque Canvas overlay does not stop the world below it from rendering.
## Hide the already-built world before its first camera draw, then reveal one
## ORIGINAL geometry node per drawn frame. Real skinning, MultiMesh resources,
## material overrides, transforms and light intersections remain untouched.
## This spreads initial submissions; it does not prove a shader was compiled:
## offscreen geometry can still be culled, and one driver link can still stall.
## Call before the first world draw; calling after a staged race build is late.

signal completed

## Native Compatibility can submit several original nodes behind the opaque
## loader without web's single-threaded shader-link risk. This keeps every
## original geometry in the pass while bounding the number of draw frames.
const NATIVE_SUBMISSIONS_PER_DRAW: int = 4
const QA_TRACE_ENV: String = "WADDLE_QA_VISUAL_TRACE"

static var perf_trace_enabled: bool = false
static var _perf_trace_events: Array[Dictionary] = []

var finished: bool = false
var _world: Node = null
var _originals: Array[Dictionary] = []
var _visible_queue: Array[Dictionary] = []
var _cursor: int = 0
var _revealed_count: int = 0
var _drawn_count: int = 0
var _awaiting_draw: bool = false
var _settling: bool = false
var _restored: bool = false
var _last_submit_frame: int = -1
var _started_usec: int = 0
var _submitted_usec: int = 0
var _pending_name: String = ""
var _pending_class: String = ""
var _maximum_draw_ms: float = 0.0
var _recovery_suspended: bool = false
var _qa_trace: bool = false
var _reveal_started: bool = true


## Returns null in headless mode. Otherwise await the returned node's completed
## signal before starting resource probes or exposing the scene. No frame can
## draw between this call's capture/hide and its return.
static func warm(world: Node, defer_reveal: bool = false) -> InitialVisualWarmup:
	if world == null or GameConfig.is_headless():
		return null
	var pass_node := InitialVisualWarmup.new()
	pass_node.name = "InitialVisualWarmup"
	pass_node._world = world
	pass_node._reveal_started = not defer_reveal
	world.add_child(pass_node)
	return pass_node


## Only effective-visible originals belong in the prewarm queue. The caller
## may hide them before ShaderWarmup collects the scene; this immutable ID set
## preserves the original inventory without re-enabling a single real draw.
func originally_visible_ids() -> Dictionary:
	var ids: Dictionary = {}
	for row: Dictionary in _visible_queue:
		var geometry := row["node"] as GeometryInstance3D
		if is_instance_valid(geometry):
			ids[geometry.get_instance_id()] = true
	return ids


func begin_reveal() -> void:
	if finished or _recovery_suspended or _reveal_started:
		return
	_reveal_started = true
	_submit_next_visual()


static func clear_perf_trace() -> void:
	_perf_trace_events.clear()


static func drain_perf_trace_events() -> Array[Dictionary]:
	var events := _perf_trace_events.duplicate(true)
	_perf_trace_events.clear()
	return events


func _ready() -> void:
	process_priority = -100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_qa_trace = OS.get_environment(QA_TRACE_ENV) == "1" or (OS.has_feature("android") \
			and (OS.is_debug_build() or bool(ProjectSettings.get_setting(
				"application/qa/native_load_trace", false))))
	_started_usec = Time.get_ticks_usec()
	_capture_and_hide()
	if _qa_trace:
		print("[initial_visual_qa] captured=%d visible=%d" % [
			_originals.size(), _visible_queue.size()])
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)
	SceneRouter.loading_recovery_started.connect(suspend_for_recovery)
	if SceneRouter.is_loading_recovery_active():
		suspend_for_recovery()
	elif _reveal_started:
		_submit_next_visual()


func _process(_delta: float) -> void:
	if _reveal_started and not _recovery_suspended and not finished and not _awaiting_draw:
		_submit_next_visual()


func suspend_for_recovery() -> void:
	if finished or _recovery_suspended:
		return
	_recovery_suspended = true
	set_process(false)
	_disconnect_draw_signal()
	# Do not free/restore here: revealing every remaining cold object would
	# defeat recovery containment. Ordinary world exit restores saved flags.
	_record_summary("recovery_suspended")


func _capture_and_hide() -> void:
	# Capture ALL effective visibility before changing ANY local visibility.
	# Otherwise hiding a geometry parent would erase its children's eligibility.
	_capture_geometry(_world)
	for row: Dictionary in _originals:
		var geometry := row["node"] as GeometryInstance3D
		if is_instance_valid(geometry):
			geometry.visible = false


func _capture_geometry(node: Node) -> void:
	if node == null or node == self:
		return
	var geometry := node as GeometryInstance3D
	if geometry != null:
		var row: Dictionary = {
			"node": geometry,
			"local_visible": geometry.visible,
			"effective_visible": geometry.is_visible_in_tree(),
			"name": String(_world.get_path_to(geometry)),
			"class": geometry.get_class(),
		}
		_originals.append(row)
		if bool(row["effective_visible"]):
			_visible_queue.append(row)
	for child: Node in node.get_children():
		_capture_geometry(child)


func _has_current_camera() -> bool:
	var viewport := get_viewport()
	return viewport != null and is_instance_valid(viewport.get_camera_3d())


func _submit_next_visual() -> bool:
	if not _reveal_started or _recovery_suspended or finished or _awaiting_draw \
			or not _has_current_camera():
		return false
	var frame := Engine.get_process_frames()
	if frame == _last_submit_frame:
		return false
	var batch_limit := NATIVE_SUBMISSIONS_PER_DRAW if OS.has_feature("mobile") \
			and not OS.has_feature("web") and not perf_trace_enabled else 1
	var submitted := 0
	var batch_names: Array[String] = []
	while _cursor < _visible_queue.size() and submitted < batch_limit:
		var row := _visible_queue[_cursor]
		_cursor += 1
		var geometry := row["node"] as GeometryInstance3D
		if not is_instance_valid(geometry) or not geometry.is_inside_tree():
			continue
		geometry.visible = bool(row["local_visible"])
		_revealed_count += 1
		submitted += 1
		_pending_name = String(row["name"])
		_pending_class = String(row["class"])
		if _qa_trace:
			batch_names.append(_pending_name)
	if submitted > 0:
		if _qa_trace:
			print("[initial_visual_qa] submit frame=%d index=%d/%d names=%s" % [
				frame, _revealed_count, _visible_queue.size(), str(batch_names)])
		_begin_draw_wait(frame)
		return true
	# Restore even originally hidden descendants' LOCAL flags. Their hidden
	# ancestors remain untouched, so this cannot deliberately enable a far LOD.
	# No instance cap may silently strand captured geometry in the hidden state.
	_restore_original_flags()
	_settling = true
	_pending_name = "full_scene_settle"
	_pending_class = ""
	_begin_draw_wait(frame)
	return true


func _begin_draw_wait(frame: int) -> void:
	_last_submit_frame = frame
	_submitted_usec = Time.get_ticks_usec()
	_awaiting_draw = true


func _on_frame_post_draw() -> void:
	# Canvas-only draws must not advance a pass waiting for a gameplay camera.
	if _recovery_suspended or finished or not _awaiting_draw or not _has_current_camera():
		return
	var wall_ms := float(Time.get_ticks_usec() - _submitted_usec) / 1000.0
	if _qa_trace:
		print("[initial_visual_qa] draw frame=%d index=%d/%d ms=%.1f" % [
			_last_submit_frame, _revealed_count, _visible_queue.size(), wall_ms])
	_maximum_draw_ms = maxf(_maximum_draw_ms, wall_ms)
	if perf_trace_enabled:
		_perf_trace_events.append({
			"phase": "settle" if _settling else "visual",
			"name": _pending_name,
			"class": _pending_class,
			"index": _revealed_count,
			"visible_total": _visible_queue.size(),
			"captured_total": _originals.size(),
			"submit_frame": _last_submit_frame,
			"following_frame": Engine.get_process_frames(),
			"ms": wall_ms,
		})
	_awaiting_draw = false
	_drawn_count = _revealed_count
	if not _settling:
		return
	finished = true
	_record_summary("complete")
	_disconnect_draw_signal()
	completed.emit()
	queue_free()


func _restore_original_flags() -> void:
	if _restored:
		return
	for row: Dictionary in _originals:
		var geometry := row["node"] as GeometryInstance3D
		if is_instance_valid(geometry):
			geometry.visible = bool(row["local_visible"])
	_restored = true


func _record_summary(phase: String) -> void:
	if perf_trace_enabled:
		_perf_trace_events.append({
			"phase": phase,
			"visible_total": _visible_queue.size(),
			"captured_total": _originals.size(),
			"revealed_total": _revealed_count,
			"max_draw_ms": _maximum_draw_ms,
			"total_ms": float(Time.get_ticks_usec() - _started_usec) / 1000.0,
		})


func _disconnect_draw_signal() -> void:
	if RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)


func _exit_tree() -> void:
	_disconnect_draw_signal()
	if is_instance_valid(SceneRouter) \
			and SceneRouter.loading_recovery_started.is_connected(suspend_for_recovery):
		SceneRouter.loading_recovery_started.disconnect(suspend_for_recovery)
	_restore_original_flags()
	if not finished:
		_record_summary("cancelled")
	# This helper owns no renderer resources and no cloned scene nodes. Releasing
	# its references also covers an interrupted transition or early world exit.
	_originals.clear()
	_visible_queue.clear()
	_world = null
