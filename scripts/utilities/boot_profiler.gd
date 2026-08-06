class_name BootProfiler
## Phase timer for scene construction, used to find where a heavy scene spends
## its first second.
##
## It exists because "the browser freezes on the splash" turned out to mean
## something quite different: the splash is simply the last frame the engine
## managed to present before change_scene_to_file() blocked the main thread
## building the next scene. Knowing that a build is slow is not enough to fix
## it — the two candidate costs pull in opposite directions:
##
##   * CPU: procedural mesh generation, lathes, noise, texture synthesis.
##     Slow everywhere, so it shows up in Safari too.
##   * GPU: shader program links. On Chrome/macOS WebGL2 runs through ANGLE
##     onto Metal and each first-sight program link costs milliseconds, where
##     Safari's native GL path costs microseconds. Invisible on desktop.
##
## step() measures the first, present() measures the second — build phases are
## timed as they run, then the caller waits for real presented frames, which is
## where deferred program links actually land.
##
## Disabled unless asked for, so shipping builds carry no logging cost:
##   web      https://…/?profile=1
##   desktop  godot … -- profile
##
## Output goes to stdout, which on web is the browser console.

static var _enabled: int = -1  ## -1 unknown, 0 off, 1 on.
static var _label: String = ""
static var _begin_usec: int = 0
static var _last_usec: int = 0
static var _rows: Array[String] = []


## Cached probe: a query string on web, a `profile` user arg on desktop.
static func enabled() -> bool:
	if _enabled >= 0:
		return _enabled == 1
	_enabled = 0
	if GameConfig.is_headless():
		return false
	if OS.has_feature("web"):
		var probe: Variant = JavaScriptBridge.eval("location.search.includes('profile')", true)
		if bool(probe):
			_enabled = 1
	elif OS.get_cmdline_user_args().has("profile"):
		_enabled = 1
	return _enabled == 1


static func begin(label: String) -> void:
	if not enabled():
		return
	_label = label
	_rows.clear()
	_begin_usec = Time.get_ticks_usec()
	_last_usec = _begin_usec


## Closes the phase that started at the previous step() (or begin()).
static func step(phase: String) -> void:
	if not enabled() or _label.is_empty():
		return
	var now := Time.get_ticks_usec()
	_rows.append("  %-22s %8.1f ms" % [phase, float(now - _last_usec) / 1000.0])
	_last_usec = now


## Waits for `frames` presented frames and reports how long they took, then
## dumps the table. Build work is already done by this point, so a large number
## here is GPU-side: program links, texture uploads, pipeline setup.
static func present(frames: int = 3) -> void:
	if not enabled() or _label.is_empty():
		return
	var build_usec := Time.get_ticks_usec() - _begin_usec
	var draw_start := Time.get_ticks_usec()
	for i: int in frames:
		await RenderingServer.frame_post_draw
	var draw_usec := Time.get_ticks_usec() - draw_start
	var out := "[boot-profile] %s\n%s" % [_label, "\n".join(_rows)]
	out += "\n  %-22s %8.1f ms" % ["BUILD (cpu)", float(build_usec) / 1000.0]
	out += "\n  %-22s %8.1f ms  (%d frames)" % ["FIRST DRAWS (gpu)", float(draw_usec) / 1000.0, frames]
	print(out)
	_label = ""
