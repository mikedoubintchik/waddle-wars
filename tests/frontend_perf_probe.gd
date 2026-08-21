extends Node
## Windowed steady-state probe for pure-Canvas title/loading presentation.

var _screen: String = "title"
var _warmup: float = 1.0
var _seconds: float = 5.0
var _enforce: bool = false
var _elapsed: float = 0.0
var _frames: Array[float] = []
var _draw_sum: float = 0.0
var _draw_peak: int = 0
var _first_present_usec: int = 0
var _begin_usec: int = 0


func _ready() -> void:
	var width := 1920
	var height := 1080
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.split("=", true, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"screen": _screen = parts[1]
			"warmup": _warmup = float(parts[1])
			"seconds": _seconds = float(parts[1])
			"enforce": _enforce = parts[1] == "1"
			"w": width = int(parts[1])
			"h": height = int(parts[1])
	DisplayServer.window_set_size(Vector2i(width, height))
	DisplayServer.window_move_to_foreground()
	_begin_usec = Time.get_ticks_usec()
	if _screen == "boot":
		var monitor := BootRouteMonitor.new()
		monitor.begin_usec = _begin_usec
		monitor.warmup = _warmup
		monitor.seconds = _seconds
		monitor.enforce = _enforce
		get_tree().root.add_child.call_deferred(monitor)
		var boot: Node = (load("res://scenes/ui/main.tscn") as PackedScene).instantiate()
		add_child(boot)
		set_process(false)
		return
	elif _screen == "loader":
		_build_loader()
	else:
		add_child(load("res://scenes/ui/title.tscn").instantiate())
	_measure_first_present()


func _measure_first_present() -> void:
	await RenderingServer.frame_post_draw
	_first_present_usec = Time.get_ticks_usec() - _begin_usec


func _build_loader() -> void:
	var backdrop := FrontEndBackdrop.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.set_presentation(FrontEndBackdrop.Context.LOADING, 0.90, true)
	add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	center.add_child(PenguinLoader.new(280.0))


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _warmup:
		_frames.append(delta * 1000.0)
		var draws := int(Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		_draw_sum += float(draws)
		_draw_peak = maxi(_draw_peak, draws)
	if _elapsed < _warmup + _seconds:
		return
	_report()


func _report() -> void:
	if _frames.is_empty():
		print("[frontend-perf] FAIL no frames")
		get_tree().quit(1)
		return
	_frames.sort()
	var sum := 0.0
	for frame_ms: float in _frames:
		sum += frame_ms
	var average_ms := sum / float(_frames.size())
	var p95_index := mini(ceili(float(_frames.size()) * 0.95) - 1, _frames.size() - 1)
	var p95_ms := _frames[p95_index]
	var max_ms: float = float(_frames.back())
	var fps := 1000.0 / maxf(average_ms, 0.001)
	var draws_average := _draw_sum / float(_frames.size())
	var passed: bool = fps >= 57.0 and p95_ms <= 20.0 and max_ms <= 50.0 \
		and draws_average <= 20.0 and _draw_peak <= 24
	print("[frontend-perf] screen=%s first_present_ms=%.2f avg_fps=%.2f p95_ms=%.2f max_ms=%.2f draws_avg=%.1f draws_peak=%d frames=%d pass=%s" % [
		_screen, float(_first_present_usec) / 1000.0, fps, p95_ms, max_ms,
		draws_average, _draw_peak, _frames.size(), str(passed)])
	get_tree().quit(1 if _enforce and not passed else 0)


class BootRouteMonitor:
	extends Node

	var begin_usec: int = 0
	var warmup: float = 1.0
	var seconds: float = 5.0
	var enforce: bool = false
	var first_present_usec: int = 0
	var route_usec: int = 0
	var boot_max_ms: float = 0.0
	var title_seen: bool = false
	var title_presented: bool = false
	var sample_elapsed: float = 0.0
	var frames: Array[float] = []
	var draw_sum: float = 0.0
	var draw_peak: int = 0
	var first_present_done: bool = false

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_measure_boot_present()

	func _measure_boot_present() -> void:
		await RenderingServer.frame_post_draw
		first_present_usec = Time.get_ticks_usec() - begin_usec
		first_present_done = true

	func _process(delta: float) -> void:
		if not first_present_done:
			return
		if not title_seen:
			boot_max_ms = maxf(boot_max_ms, delta * 1000.0)
			var scene := get_tree().current_scene
			if scene != null and scene.name == &"Title":
				title_seen = true
				route_usec = Time.get_ticks_usec() - begin_usec
				_measure_title_present()
			return
		if not title_presented:
			return
		sample_elapsed += delta
		if sample_elapsed >= warmup:
			frames.append(delta * 1000.0)
			var draws := int(Performance.get_monitor(
				Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			draw_sum += float(draws)
			draw_peak = maxi(draw_peak, draws)
		if sample_elapsed >= warmup + seconds:
			_report()

	func _measure_title_present() -> void:
		await RenderingServer.frame_post_draw
		title_presented = true

	func _report() -> void:
		if frames.is_empty():
			print("[frontend-perf] FAIL boot route produced no title frames")
			get_tree().quit(1)
			return
		frames.sort()
		var sum := 0.0
		for frame_ms: float in frames:
			sum += frame_ms
		var average_ms := sum / float(frames.size())
		var p95_index := mini(ceili(float(frames.size()) * 0.95) - 1,
			frames.size() - 1)
		var p95_ms := frames[p95_index]
		var max_ms: float = float(frames.back())
		var fps := 1000.0 / maxf(average_ms, 0.001)
		var draws_average := draw_sum / float(frames.size())
		var first_ms := float(first_present_usec) / 1000.0
		var passed: bool = first_ms <= 100.0 and boot_max_ms <= 33.4 \
			and fps >= 57.0 and p95_ms <= 20.0 and max_ms <= 50.0 \
			and draws_average <= 20.0 and draw_peak <= 24
		print("[frontend-perf] screen=boot first_present_ms=%.2f boot_hitch_max_ms=%.2f route_ms=%.2f title_avg_fps=%.2f title_p95_ms=%.2f title_max_ms=%.2f title_draws_avg=%.1f title_draws_peak=%d frames=%d pass=%s" % [
			first_ms, boot_max_ms, float(route_usec) / 1000.0, fps, p95_ms,
			max_ms, draws_average, draw_peak, frames.size(), str(passed)])
		get_tree().quit(1 if enforce and not passed else 0)
