extends Node
## Counts the DISTINCT materials a mode puts on screen, and when each one first
## appears.
##
## Why this exists: on the web build (gl_compatibility through ANGLE) the first
## frame a material is visible costs a shader program link, and a link is a
## multi-millisecond-to-multi-second stall on the single WASM thread. A stall
## like that is indistinguishable from a freeze — "the tab froze", "the game
## stops randomly mid-way". Desktop never shows it because Metal links fast.
##
## So the thing to measure is not memory, it is: how many distinct materials
## does a session reveal, and how far into the run does it keep revealing new
## ones? Every entry printed with a late timestamp is a stall a player will hit
## mid-run, and belongs in ShaderWarmup's probe list instead.
##
##   godot --path . --resolution 960x540 res://tests/material_census.tscn -- seconds=70
##
## Run WITH a window: headless builds no visuals at all.

var _seconds: float = 70.0
var _elapsed: float = 0.0
var _game: Node = null
var _seen: Dictionary = {}
var _timeline: Array[Dictionary] = []
var _done: bool = false
var _spikes: Array[Dictionary] = []


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("seconds="):
			_seconds = float(arg.trim_prefix("seconds="))
	RunnerPlayer.autopilot = true
	Engine.time_scale = 2.0
	var scene: PackedScene = load(Game.SCENE_RUNNER)
	_game = scene.instantiate()
	add_child(_game)
	print("[census] walking the runner for %.0fs of run time" % _seconds)


func _process(delta: float) -> void:
	if _done or _game == null or not is_instance_valid(_game):
		return
	_elapsed += delta
	# Sampling every frame would dominate the frame time on a big tree; every
	# few frames is plenty to catch a first appearance.
	if Engine.get_process_frames() % 6 == 0:
		_walk(_game)
	# Frame-time spikes are the thing a player calls a freeze. Record every
	# frame that blew past a normal budget, with what was on screen at the time
	# (light count especially: gl_compatibility compiles a shader variant per
	# light count, so a tunnel coming into view can link a whole new set).
	if delta > 0.1:
		_spikes.append({
			"t": _elapsed,
			"ms": delta * 1000.0,
			"lights": _count_lights(_game),
			"materials": _seen.size(),
		})
	if _elapsed >= _seconds:
		_report()


func _count_lights(node: Node) -> int:
	var total := 0
	if node is OmniLight3D or node is SpotLight3D:
		total += 1
	for child: Node in node.get_children():
		total += _count_lights(child)
	return total


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


## Keyed by the material's shader signature rather than its instance: two
## StandardMaterial3Ds with the same feature flags share one program, and it is
## programs that cost.
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
	print("[census] %d distinct material programs over %.0fs" % [_seen.size(), _elapsed])
	var late := 0
	for row: Dictionary in _timeline:
		var marker := "  <-- MID-RUN STALL" if float(row["t"]) > 6.0 else ""
		if float(row["t"]) > 6.0:
			late += 1
		print("[census] %6.1fs  %s%s" % [row["t"], row["key"], marker])
	if _spikes.is_empty():
		print("[census] no frame took longer than 100 ms")
	else:
		var worst := 0.0
		for spike: Dictionary in _spikes:
			worst = maxf(worst, float(spike["ms"]))
			print("[census] SPIKE %6.1fs  %7.1f ms  lights=%d  materials=%d"
				% [spike["t"], spike["ms"], spike["lights"], spike["materials"]])
		print("[census] %d spikes over 100 ms, worst %.0f ms" % [_spikes.size(), worst])
	print("[census] %d of %d first appeared after the opening 6s — each of those is a stall a player hits mid-run on web"
		% [late, _seen.size()])
	get_tree().quit(0)
