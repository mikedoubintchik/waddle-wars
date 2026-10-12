extends Node
## Restart-cycle soak for Waddle Run.
##
## The single-run soak (runner_sim) proved a long run is flat, but that is not
## how the mode is played: a player dies, hits Run Again, dies, hits Run Again.
## Every one of those cycles frees a player, resets a track full of meshes and
## lights, and hands the HUD a new set of missions. A leak in that path is
## invisible to a single long run and shows up as a browser tab that dies after
## ten minutes of actual play, which is exactly what was reported.
##
## Run WITH a window — headless skips every visual, and the visuals are where
## the per-cycle allocations live:
##   godot --path . --resolution 960x540 res://tests/runner_churn.tscn -- runs=16
##
## Exits 1 if objects, resources or memory trend up across cycles.

## Seconds of running before each forced death.
const RUN_SECONDS: float = 3.0

var _runs: int = 16
var _run_index: int = 0
var _elapsed: float = 0.0
var _game: RunnerGame = null
var _probes: Array[Dictionary] = []
var _waiting_for_restart: bool = false
var _done: bool = false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("runs="):
			_runs = int(arg.trim_prefix("runs="))
	RunnerPlayer.autopilot = true
	Engine.time_scale = 3.0
	print("[runner_churn] %d death/restart cycles" % _runs)
	var scene: PackedScene = load(Game.SCENE_RUNNER)
	_game = scene.instantiate() as RunnerGame
	add_child(_game)


func _process(delta: float) -> void:
	if _done or _game == null or not is_instance_valid(_game):
		return
	if _game.player == null or not is_instance_valid(_game.player):
		return
	_elapsed += delta

	if _waiting_for_restart:
		# Give the death frame a beat to settle (the results panel builds here,
		# and building it is part of what a cycle costs).
		if _elapsed < 1.0:
			return
		_sample()
		_run_index += 1
		if _run_index >= _runs:
			_report()
			return
		_elapsed = 0.0
		_waiting_for_restart = false
		_game.restart()
		return

	if _elapsed >= RUN_SECONDS:
		_elapsed = 0.0
		_waiting_for_restart = true
		_game.player.kill()


func _sample() -> void:
	_probes.append({
		"run": _run_index,
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"vram_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
	})


func _report() -> void:
	_done = true
	for probe: Dictionary in _probes:
		print("[runner_churn] run %2d  objects %6d  resources %5d  nodes %5d  orphans %4d  static %6.1f MB  vram %6.1f MB"
			% [probe["run"], probe["objects"], probe["resources"], probe["nodes"],
				probe["orphans"], probe["static_mb"], probe["vram_mb"]])
	if _probes.size() < 4:
		print("[runner_churn] FAIL: too few cycles to judge")
		get_tree().quit(1)
		return
	# Compare late cycles against early ones rather than first against last:
	# the first cycle pays one-off costs (shader programs, cached meshes) that
	# are not a leak.
	var early: Dictionary = _probes[1]
	var late: Dictionary = _probes[_probes.size() - 1]
	var cycles := float(int(late["run"]) - int(early["run"]))
	var per_cycle := {
		"objects": (float(late["objects"]) - float(early["objects"])) / cycles,
		"resources": (float(late["resources"]) - float(early["resources"])) / cycles,
		"nodes": (float(late["nodes"]) - float(early["nodes"])) / cycles,
		"static_mb": (float(late["static_mb"]) - float(early["static_mb"])) / cycles,
		"vram_mb": (float(late["vram_mb"]) - float(early["vram_mb"])) / cycles,
	}
	print("[runner_churn] per cycle: objects %+.1f  resources %+.1f  nodes %+.1f  static %+.2f MB  vram %+.2f MB"
		% [per_cycle["objects"], per_cycle["resources"], per_cycle["nodes"],
			per_cycle["static_mb"], per_cycle["vram_mb"]])
	# Thresholds are deliberately loose: a few objects of jitter is normal, a
	# steady climb is not. At +2 MB a cycle a phone browser dies inside twenty
	# retries, which is the reported symptom.
	var failures := PackedStringArray()
	if float(per_cycle["static_mb"]) > 0.6:
		failures.append("static memory +%.2f MB/cycle" % per_cycle["static_mb"])
	if float(per_cycle["vram_mb"]) > 1.0:
		failures.append("VRAM +%.2f MB/cycle" % per_cycle["vram_mb"])
	if float(per_cycle["resources"]) > 2.0:
		failures.append("resources +%.1f/cycle" % per_cycle["resources"])
	if float(per_cycle["nodes"]) > 12.0:
		failures.append("nodes +%.1f/cycle" % per_cycle["nodes"])
	if int(late["orphans"]) > 40:
		failures.append("%d orphan nodes" % late["orphans"])
	if failures.is_empty():
		print("[runner_churn] PASS")
		get_tree().quit(0)
		return
	print("[runner_churn] FAIL: %s" % ", ".join(failures))
	get_tree().quit(1)
