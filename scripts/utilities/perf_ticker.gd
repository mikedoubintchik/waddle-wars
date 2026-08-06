class_name PerfTicker
extends Node
## Rolling frame-time readout, printed to stdout (the browser console on web).
##
## Chrome's Task Manager reports a single averaged CPU percentage per tab, which
## cannot distinguish "running smoothly at the frame cap" from "struggling at 12
## fps": a single-threaded WASM build that is comfortably ahead of its budget and
## one that is drowning can show the same number. This prints what actually
## matters — average and worst frame time over a window — so a report of "it
## feels choppy" can be checked against a figure.
##
## Only runs when BootProfiler is enabled (`?profile=1` on web, `-- profile` on
## desktop), so shipping builds pay nothing.

const WINDOW: float = 2.0  ## Seconds per printed line.

var _elapsed: float = 0.0
var _frames: int = 0
var _worst: float = 0.0
var _scene: String = "?"


## Attaches a ticker to `host` when profiling is on; returns null otherwise.
static func attach(host: Node) -> PerfTicker:
	if host == null or not BootProfiler.enabled():
		return null
	var node := PerfTicker.new()
	node.name = "PerfTicker"
	host.add_child(node)
	return node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100


## Labels subsequent lines, so a race and a menu can be told apart in the log.
func set_scene_label(label: String) -> void:
	_scene = label


func _process(delta: float) -> void:
	_elapsed += delta
	_frames += 1
	_worst = maxf(_worst, delta)
	if _elapsed < WINDOW:
		return
	var avg_ms := _elapsed / float(_frames) * 1000.0
	print("[perf] %-10s %5.1f fps  avg %5.1f ms  worst %6.1f ms" % [
		_scene, float(_frames) / _elapsed, avg_ms, _worst * 1000.0])
	_elapsed = 0.0
	_frames = 0
	_worst = 0.0
