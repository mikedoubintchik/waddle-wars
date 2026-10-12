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
const WINDOW_USEC: int = 2_000_000

# Opt-in, bounded counters only. Visibility/focus changes remain observable
# between engine frames; no history, player identifiers or event contents.
const BROWSER_CONTEXT_JS := """
(() => {
  if (window.__wwPerfContext) return;
  let last = performance.now(), hidden = document.hidden, focused = document.hasFocus();
  let hiddenMs = 0, transitions = 0, focusChanges = 0, inputs = 0, delayMax = 0;
  let accounted = last;
  function account(now) {
    if (hidden) hiddenMs += Math.max(0, now - accounted);
    accounted = now;
  }
  document.addEventListener('visibilitychange', () => {
    account(performance.now()); hidden = document.hidden; transitions++;
  });
  window.addEventListener('focus', () => { focused = true; focusChanges++; });
  window.addEventListener('blur', () => { focused = false; focusChanges++; });
  function input(event) {
    if (!event.isTrusted) return;
    const delay = performance.now() - event.timeStamp;
    inputs++;
    if (delay >= 0 && delay < 3600000) delayMax = Math.max(delayMax, delay);
  }
  document.addEventListener('pointerdown', input, {capture:true, passive:true});
  document.addEventListener('keydown', input, {capture:true, passive:true});
  window.__wwPerfContext = () => {
    const now = performance.now(); account(now);
    const result = {browser_ms:now, window_ms:now-last, visible:!hidden,
      focused, hidden_ms:hiddenMs, visibility_changes:transitions,
      focus_changes:focusChanges, inputs, event_delay_max_ms:delayMax};
    last = now; hiddenMs = transitions = focusChanges = inputs = delayMax = 0;
    return JSON.stringify(result);
  };
})();
"""

var _elapsed_usec: int = 0
var _frames: int = 0
var _worst_usec: int = 0
var _scene: String = "?"
var _last_tick_usec: int = 0
var _clock_initialized: bool = false


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
	_last_tick_usec = _clock_now_usec()
	_clock_initialized = true
	if OS.has_feature("web") and BootProfiler.enabled():
		JavaScriptBridge.eval(BROWSER_CONTEXT_JS, true)
		_browser_context_data() # Begin a fresh window for this scene's ticker.


## Labels subsequent lines, so a race and a menu can be told apart in the log.
func set_scene_label(label: String) -> void:
	_scene = label


func _process(_delta: float) -> void:
	# Engine delta can be clamped after a long blocked frame. Monotonic process
	# time preserves the stall the ticker exists to expose.
	var now_usec := _clock_now_usec()
	if not _clock_initialized:
		_last_tick_usec = now_usec
		_clock_initialized = true
		return
	var frame_usec := maxi(now_usec - _last_tick_usec, 0)
	_last_tick_usec = now_usec
	_elapsed_usec += frame_usec
	_frames += 1
	_worst_usec = maxi(_worst_usec, frame_usec)
	if _elapsed_usec < WINDOW_USEC:
		return
	_publish_sample(_sample_data())
	_elapsed_usec = 0
	_frames = 0
	_worst_usec = 0


func _clock_now_usec() -> int:
	return Time.get_ticks_usec()


func _sample_data() -> Dictionary:
	var elapsed_seconds := float(_elapsed_usec) / 1_000_000.0
	var sample := {
		"scene": _scene,
		"elapsed_seconds": elapsed_seconds,
		"frames": _frames,
		"fps": float(_frames) / elapsed_seconds,
		"average_ms": float(_elapsed_usec) / float(_frames) / 1000.0,
		"worst_ms": float(_worst_usec) / 1000.0,
	}
	# This is the state at the END of the measured window, not a claim that all
	# frames in that window used it. No settings/viewport reads when profiling is
	# off, and normal builds never attach this node in the first place.
	if BootProfiler.enabled():
		sample["render_state"] = _render_state_data()
		if OS.has_feature("web"):
			sample["browser_context"] = _browser_context_data()
	return sample


func _browser_context_data() -> Dictionary:
	var value: Variant = JavaScriptBridge.eval(
		"window.__wwPerfContext ? window.__wwPerfContext() : '{}'", true)
	var parsed: Variant = JSON.parse_string(String(value)) if value is String else null
	return parsed if parsed is Dictionary else {}


## Fixed allowlist only: no settings dumps, player identities or credentials.
func _render_state_data() -> Dictionary:
	var viewport := get_viewport()
	return {
		"scale_3d": viewport.scaling_3d_scale if viewport != null else null,
		"msaa_3d": int(viewport.msaa_3d) if viewport != null else null,
		"quality": String(SettingsManager.get_setting("display", "quality_preset")),
		"render_step": SettingsManager._render_scale_step,
		"quality_steps": SettingsManager._governor_steps,
		"governor_ready": SettingsManager._governor_target_ready,
		"governor_monitoring": SettingsManager._governor_monitoring,
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphan_nodes": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"texture_bytes": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),
	}


func _publish_sample(sample: Dictionary) -> void:
	var line := "[perf] %-10s %5.1f fps  avg %5.1f ms  worst %6.1f ms  window %.3f s" % [
		sample["scene"], sample["fps"], sample["average_ms"], sample["worst_ms"],
		sample["elapsed_seconds"]]
	if sample.has("render_state"):
		line += "  render_end=%s" % JSON.stringify(sample["render_state"])
	if sample.has("browser_context"):
		line += "  browser_context=%s" % JSON.stringify(sample["browser_context"])
	print(line)
