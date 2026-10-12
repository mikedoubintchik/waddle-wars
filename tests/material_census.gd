extends Node
## Counts distinct material-resource signatures found in the live scene tree.
## This is not a GPU-program census: skinning, instancing and renderer variants
## are not fully represented. Correlate late resources with measured frame time.
##
## Why this exists: on the web build (gl_compatibility through ANGLE) the first
## frame a material is visible costs a shader program link, and a link is a
## multi-millisecond-to-multi-second stall on the single WASM thread. A stall
## like that is indistinguishable from a freeze — "the tab froze", "the game
## stops randomly mid-way". Native Compatibility can also stall during linking.
##
## So the thing to measure is not memory, it is: how many distinct materials
## does a session reveal, and how far into the run does it keep revealing new
## ones? Late resources identify candidates to inspect, not proof of compilation.
##
##   godot --path . --resolution 960x540 res://tests/material_census.tscn -- seconds=70
##   godot --path . --resolution 960x540 res://tests/material_census.tscn -- loader_only=true
##
## Run WITH a window: headless builds no visuals at all.

var _seconds: float = 70.0
var _elapsed: float = 0.0
var _game: Node = null
var _seen: Dictionary = {}
var _timeline: Array[Dictionary] = []
var _done: bool = false
var _spikes: Array[Dictionary] = []
var _stream_events: Array[Dictionary] = []
var _warmup_events: Array[Dictionary] = []
var _initial_visual_events: Array[Dictionary] = []
var _loader_frame_ms: PackedFloat64Array = PackedFloat64Array()
var _last_wall_usec: int = 0
var _loader_complete: bool = false
var _loader_only: bool = false
var _seed: int = 20260907
var _loading_gameplay_violations: int = 0
var _max_loader_distance: float = 0.0
var _min_loader_countdown: float = RunnerGame.COUNTDOWN_TIME


func _ready() -> void:
	DisplayServer.window_move_to_foreground()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("seconds="):
			_seconds = float(arg.trim_prefix("seconds="))
		elif arg == "loader_only=true":
			_loader_only = true
		elif arg.begins_with("seed="):
			_seed = int(arg.trim_prefix("seed="))
		elif arg == "keep_visible=true":
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	RunnerPlayer.autopilot = true
	RunnerTrack.perf_trace_enabled = true
	ShaderWarmup.perf_trace_enabled = true
	ShaderWarmup.clear_perf_trace()
	InitialVisualWarmup.perf_trace_enabled = true
	InitialVisualWarmup.clear_perf_trace()
	Engine.time_scale = 1.0 if _loader_only else 2.0
	# Start before scene instantiation so the first loader-covered synchronous
	# build cost is included in the first wall-clock frame.
	_last_wall_usec = Time.get_ticks_usec()
	var scene: PackedScene = load(Game.SCENE_RUNNER)
	_game = scene.instantiate()
	(_game as RunnerGame).generation_seed = _seed
	add_child(_game)
	print("[census] %s" % ("loader-only warmup trace"
			if _loader_only else "walking the runner for %.0fs of run time" % _seconds))


func _process(delta: float) -> void:
	if _done or _game == null or not is_instance_valid(_game):
		return
	var now_usec := Time.get_ticks_usec()
	var wall_ms := float(now_usec - _last_wall_usec) / 1000.0 \
			if _last_wall_usec > 0 else 0.0
	_last_wall_usec = now_usec
	_elapsed += delta
	_drain_stream_trace()
	_drain_warmup_trace()
	for event: Dictionary in InitialVisualWarmup.drain_perf_trace_events():
		_initial_visual_events.append(event)
		print("[census-initial-visual] %s" % event)
	if not _loader_complete:
		var runner := _game as RunnerGame
		if runner != null:
			var distance := runner.player.distance if runner.player != null else 0.0
			_max_loader_distance = maxf(_max_loader_distance, distance)
			_min_loader_countdown = minf(_min_loader_countdown, runner._countdown)
			if runner.running or distance > 0.0 \
					or runner._countdown < RunnerGame.COUNTDOWN_TIME:
				_loading_gameplay_violations += 1
		# Include transition frame after final warmup draw. ShaderWarmup removes
		# itself during previous process callback; this interval contains that
		# final item's raster/compile cost and must not disappear from loader max.
		_loader_frame_ms.append(wall_ms)
		if not _runner_loader_active():
			_loader_complete = true
			if _loader_only:
				_report()
				return
	# Sampling every frame would dominate the frame time on a big tree; every
	# few frames is plenty to catch a first appearance.
	if Engine.get_process_frames() % 6 == 0:
		_walk(_game)
	# Frame-time spikes are the thing a player calls a freeze. Record every
	# frame that blew past a normal budget, with what was on screen at the time
	# (light count especially: gl_compatibility compiles a shader variant per
	# light count, so a tunnel coming into view can link a whole new set).
	if wall_ms > 100.0:
		var spike := _runtime_snapshot()
		spike.merge({
			"t": _elapsed,
			"frame": Engine.get_process_frames(),
			"ms": wall_ms,
			"sim_delta_ms": delta * 1000.0,
			"lights": _count_lights(_game),
			"materials": _seen.size(),
		}, true)
		if not _stream_events.is_empty():
			spike["recent_stream"] = _stream_events.back()
		_spikes.append(spike)
	if _elapsed >= _seconds:
		_report()


func _count_lights(node: Node) -> int:
	var total := 0
	if node is OmniLight3D or node is SpotLight3D:
		total += 1
	for child: Node in node.get_children():
		total += _count_lights(child)
	return total


func _runner_track() -> RunnerTrack:
	if _game == null:
		return null
	return _game.get("track") as RunnerTrack


func _drain_stream_trace() -> void:
	var track := _runner_track()
	if track == null:
		return
	for event: Dictionary in track.drain_perf_trace_events():
		event["t"] = _elapsed
		_stream_events.append(event)
		print("[census-stream] t=%.2fs %s" % [_elapsed, event])


func _drain_warmup_trace() -> void:
	for event: Dictionary in ShaderWarmup.drain_perf_trace_events():
		event["t"] = _elapsed
		_warmup_events.append(event)
		print(("[census-warmup] item=%d/%d type=%s key=%s name=%s "
				+ "submit=%d following=%d wall=%.2fms") % [
			event.get("item_index", 0), event.get("queue_size", 0),
			event.get("type", ""), event.get("key", ""), event.get("name", ""),
			event.get("submit_frame", 0), event.get("following_frame", 0),
			event.get("ms", 0.0),
		])


func _runner_loader_active() -> bool:
	if _game == null or not is_instance_valid(_game):
		return false
	if not bool(_game.get("build_finished")):
		return true
	return _contains_shader_warmup(_game)


func _contains_shader_warmup(node: Node) -> bool:
	if node is ShaderWarmup:
		return true
	for child: Node in node.get_children():
		if _contains_shader_warmup(child):
			return true
	return false


func _percentile_ms(values: PackedFloat64Array, percentile: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var index := clampi(int(ceil(percentile * float(sorted.size()))) - 1,
			0, sorted.size() - 1)
	return sorted[index]


func _max_ms(values: PackedFloat64Array) -> float:
	var maximum := 0.0
	for value: float in values:
		maximum = maxf(maximum, value)
	return maximum


## Expensive tree/RID-proxy walk, executed only after a >100 ms frame. This
## keeps census overhead out of normal frames while preserving enough state to
## distinguish shader compilation from chunk construction and light churn.
func _runtime_snapshot() -> Dictionary:
	var state := {
		"geometry": 0,
		"material_ids": {},
		"mesh_ids": {},
	}
	_collect_runtime_stats(_game, state)
	var snapshot := {
		"distance": 0.0,
		"geometry": int(state["geometry"]),
		"material_resources": (state["material_ids"] as Dictionary).size(),
		"mesh_resources": (state["mesh_ids"] as Dictionary).size(),
		# Rendering objects/draws and Resource count are stable public proxies for
		# live renderer RIDs; Godot exposes no portable per-scene RID enumeration.
		"render_objects": int(Performance.get_monitor(
				Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"draw_calls": int(Performance.get_monitor(
				Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"resource_count": int(Performance.get_monitor(
				Performance.OBJECT_RESOURCE_COUNT)),
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphan_count": int(Performance.get_monitor(
				Performance.OBJECT_ORPHAN_NODE_COUNT)),
	}
	var player := _game.get("player") as Node3D
	if player != null:
		snapshot["distance"] = float(player.get("distance"))
	var track := _runner_track()
	if track != null:
		snapshot.merge(track.perf_trace_snapshot(
				player.position.z if player != null else 0.0), true)
	return snapshot


func _collect_runtime_stats(node: Node, state: Dictionary) -> void:
	if node == null:
		return
	var mesh_ids := state["mesh_ids"] as Dictionary
	var geometry := node as GeometryInstance3D
	if geometry != null:
		state["geometry"] = int(state["geometry"]) + 1
		_note_runtime_material(geometry.material_override, state)
		_note_runtime_material(geometry.material_overlay, state)
	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		mesh_ids[mesh_instance.mesh.get_instance_id()] = true
		for surface: int in mesh_instance.mesh.get_surface_count():
			_note_runtime_material(mesh_instance.get_active_material(surface), state)
	var multi := node as MultiMeshInstance3D
	if multi != null and multi.multimesh != null and multi.multimesh.mesh != null:
		var mesh := multi.multimesh.mesh
		mesh_ids[mesh.get_instance_id()] = true
		for surface: int in mesh.get_surface_count():
			_note_runtime_material(mesh.surface_get_material(surface), state)
	var particles := node as GPUParticles3D
	if particles != null and particles.draw_pass_1 != null:
		var draw_mesh := particles.draw_pass_1
		mesh_ids[draw_mesh.get_instance_id()] = true
		for surface: int in draw_mesh.get_surface_count():
			_note_runtime_material(draw_mesh.surface_get_material(surface), state)
	for child: Node in node.get_children():
		_collect_runtime_stats(child, state)


func _note_runtime_material(material: Material, state: Dictionary) -> void:
	if material != null:
		var material_ids := state["material_ids"] as Dictionary
		material_ids[material.get_instance_id()] = true


func _walk(node: Node) -> void:
	var visual := node as GeometryInstance3D
	if visual != null:
		_note(visual.material_override)
		var mesh_node := node as MeshInstance3D
		if mesh_node != null and mesh_node.mesh != null:
			for i: int in mesh_node.mesh.get_surface_count():
				_note(mesh_node.get_active_material(i))
		var multi := node as MultiMeshInstance3D
		if multi != null and multi.multimesh != null and multi.multimesh.mesh != null:
			for i: int in multi.multimesh.mesh.get_surface_count():
				_note(multi.multimesh.mesh.surface_get_material(i))
	var particles := node as GPUParticles3D
	if particles != null and particles.draw_pass_1 != null:
		for i: int in particles.draw_pass_1.get_surface_count():
			_note(particles.draw_pass_1.surface_get_material(i))
	for child: Node in node.get_children():
		_walk(child)


## Partial resource signature, not a renderer program ID. This intentionally
## groups instances but does not encode every shader flag or geometry variant.
func _note(material: Material) -> void:
	if material == null:
		return
	var key := ""
	var standard := material as StandardMaterial3D
	if standard != null:
		key = "std|shade=%d|transp=%d|blend=%d|cull=%d|vc=%d|billboard=%d|tex=%d|depth=%d|no_depth=%d" % [
			standard.shading_mode, standard.transparency, standard.blend_mode,
			standard.cull_mode, int(standard.vertex_color_use_as_albedo),
			standard.billboard_mode, int(standard.albedo_texture != null),
			int(standard.disable_receive_shadows), int(standard.no_depth_test)]
	else:
		var shader_material := material as ShaderMaterial
		if shader_material != null and shader_material.shader != null:
			key = "shader|%s" % shader_material.shader.resource_path
		else:
			key = "other|%s" % material.get_class()
	if _seen.has(key):
		return
	_seen[key] = _elapsed
	_timeline.append({"t": _elapsed, "key": key})


func _report() -> void:
	_done = true
	_drain_warmup_trace()
	var warmup_frame_ms := PackedFloat64Array()
	var worst_warmup: Dictionary = {}
	for event: Dictionary in _warmup_events:
		var item_ms := float(event.get("ms", 0.0))
		warmup_frame_ms.append(item_ms)
		if worst_warmup.is_empty() or item_ms > float(worst_warmup.get("ms", 0.0)):
			worst_warmup = event
	print("[census-loader] frames=%d p95=%.2fms max=%.2fms" % [
		_loader_frame_ms.size(), _percentile_ms(_loader_frame_ms, 0.95),
		_max_ms(_loader_frame_ms),
	])
	print("[census-warmup] frames=%d p95=%.2fms max=%.2fms" % [
		warmup_frame_ms.size(), _percentile_ms(warmup_frame_ms, 0.95),
		_max_ms(warmup_frame_ms),
	])
	if not worst_warmup.is_empty():
		print("[census-warmup-worst] item=%d/%d type=%s key=%s name=%s wall=%.2fms" % [
			worst_warmup.get("item_index", 0), worst_warmup.get("queue_size", 0),
			worst_warmup.get("type", ""), worst_warmup.get("key", ""),
			worst_warmup.get("name", ""), worst_warmup.get("ms", 0.0),
		])
	print("[census] %d resource signatures over %.0fs" % [_seen.size(), _elapsed])
	var late := 0
	for row: Dictionary in _timeline:
		var marker := "  <-- LATE RESOURCE (inspect frame trace)" if float(row["t"]) > 6.0 else ""
		if float(row["t"]) > 6.0:
			late += 1
		print("[census] %6.1fs  %s%s" % [row["t"], row["key"], marker])
	if _spikes.is_empty():
		print("[census] no frame took longer than 100 ms")
	else:
		var worst := 0.0
		for spike: Dictionary in _spikes:
			worst = maxf(worst, float(spike["ms"]))
			print(("[census] SPIKE %6.1fs %7.1fms frame=%d distance=%.1fm "
					+ "chunk=%d biome=%d next=%d live=%d tunnels=%d cues=%d "
					+ "dynamic_tunnel_lights=%d scene_lights=%d "
					+ "signatures=%d geometry=%d material_res=%d mesh_res=%d "
					+ "render_objects=%d draws=%d resources=%d nodes=%d orphans=%d recent=%s"
				) % [
					spike["t"], spike["ms"], spike["frame"], spike.get("distance", 0.0),
					spike.get("current_chunk", -1), spike.get("current_biome", -1),
					spike.get("next_chunk", -1), spike.get("live_chunks", -1),
					spike.get("tunnel_chunks", -1), spike.get("tunnel_light_cues", -1),
					spike.get("tunnel_lights", -1), spike["lights"],
					spike["materials"], spike.get("geometry", -1),
					spike.get("material_resources", -1), spike.get("mesh_resources", -1),
					spike.get("render_objects", -1), spike.get("draw_calls", -1),
					spike.get("resource_count", -1), spike.get("node_count", -1),
					spike.get("orphan_count", -1), spike.get("recent_stream", {}),
				])
		print("[census] %d spikes over 100 ms, worst %.0f ms" % [_spikes.size(), worst])
	print("[census] %d of %d resource signatures first appeared after 6s; GPU program/variant coverage requires separate verification"
		% [late, _seen.size()])
	print("[census-loader-gameplay] violations=%d max_distance=%.3fm min_countdown=%.3fs"
		% [_loading_gameplay_violations, _max_loader_distance, _min_loader_countdown])
	RunnerTrack.perf_trace_enabled = false
	ShaderWarmup.perf_trace_enabled = false
	InitialVisualWarmup.perf_trace_enabled = false
	Engine.time_scale = 1.0
	var exit_code := 1 if _loading_gameplay_violations > 0 or not _loader_complete else 0
	if not _loader_complete:
		var initial := _game.get_node_or_null("InitialVisualWarmup") as InitialVisualWarmup
		print("[census-loader] FAIL incomplete; drawn_frames=%d window_mode=%d camera=%s"
			% [Engine.get_frames_drawn(), DisplayServer.window_get_mode(),
				get_viewport().get_camera_3d()])
		if initial != null:
			print("[census-loader] initial cursor=%d waiting=%s processing=%s inside_tree=%s"
				% [initial._cursor, initial._awaiting_draw, initial.is_processing(),
					initial.is_inside_tree()])
	_game.queue_free()
	_game = null
	# Warmup anchors live beneath cameras and use deferred deletion. Let those
	# frees reach the renderer before exit so probe resources do not look leaked.
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(exit_code)
