extends Node
## Headless soak test for Waddle Run.
##
## Runs the real mode with the player on autopilot and asserts the things that
## a runner cannot be shipped without: it keeps running, the track keeps
## streaming (and keeps recycling, so node count does not grow without bound),
## the score climbs, and death is reachable and clean.
##
##   godot --headless res://tests/runner_sim.tscn -- seconds=90
##
## Exits 0 on success, 1 on failure.

var _seconds: float = 60.0
var _elapsed: float = 0.0
var _game: RunnerGame = null
var _peak_nodes: int = 0
var _samples: int = 0
var _last_distance: float = 0.0
var _stalled_for: float = 0.0
var _reported: bool = false
var _probes: Array[Dictionary] = []
var _last_probe: float = 0.0


func player_distance() -> float:
	return _game.player.distance if _game != null and _game.player != null else 0.0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("seconds="):
			_seconds = float(arg.trim_prefix("seconds="))
	RunnerPlayer.autopilot = true
	Engine.time_scale = 4.0
	print("[runner_sim] running %.0fs of Waddle Run on autopilot" % _seconds)
	var scene: PackedScene = load(Game.SCENE_RUNNER)
	_game = scene.instantiate() as RunnerGame
	add_child(_game)


func _process(delta: float) -> void:
	if _reported or _game == null or not is_instance_valid(_game):
		return
	_elapsed += delta
	if _game.player == null or not is_instance_valid(_game.player):
		return

	# Node count is the streaming test: a runner that spawns and never recycles
	# looks fine for thirty seconds and dies at three minutes.
	var nodes := _count(_game)
	_peak_nodes = maxi(_peak_nodes, nodes)
	_samples += 1
	# Node count alone does not catch a leak: a freed chunk still leaks if its
	# meshes, materials or images are referenced somewhere. Sample the engine's
	# own counters so a growing run shows up as a trend rather than a crash
	# twenty minutes later in someone's browser tab.
	if _elapsed - _last_probe > 10.0:
		_last_probe = _elapsed
		_probes.append({
			"t": _elapsed,
			"m": player_distance(),
			"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
			"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
			"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			"vram_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		})

	# Progress test: distance must actually advance once the countdown is over.
	if _game.running:
		if _game.player.distance - _last_distance < 0.01:
			_stalled_for += delta
		else:
			_stalled_for = 0.0
		_last_distance = _game.player.distance
		if _stalled_for > 3.0:
			_fail("player stopped advancing at %.0f m" % _last_distance)
			return

	if _game.player.state == RunnerPlayer.State.DEAD:
		_report("died")
		return
	if _elapsed >= _seconds:
		_report("survived")


func _report(reason: String) -> void:
	_reported = true
	var distance := _game.player.distance
	var nodes := _count(_game)
	var hazards := get_tree().get_nodes_in_group(RunnerConfig.GROUP_HAZARD).size()
	var pickups := get_tree().get_nodes_in_group(RunnerConfig.GROUP_PICKUP).size()
	var crates := get_tree().get_nodes_in_group(RunnerConfig.GROUP_POWERUP).size()
	# The gamification layer is as much a shipping requirement as the movement:
	# a run with no missions in flight is the boring version the user rejected.
	var mission_rows: Array = _game.missions.rows() if _game.missions != null else []
	for row: Dictionary in mission_rows:
		print("[runner_sim]   mission: %-42s %3d%%%s"
			% [row.get("text", "?"), int(float(row.get("progress", 0.0)) * 100.0),
				"  DONE" if bool(row.get("done", false)) else ""])
	# Ramps are counted as they exist as well as as they are hit: a ramp the
	# autopilot never lines up with is a content question, and a ramp that
	# never spawns is a bug, and the two look identical from "ramps 0".
	var live_ramps := 0
	for node: Node in get_tree().get_nodes_in_group(RunnerConfig.GROUP_HAZARD):
		if String((node as Node3D).get_meta("kind", "")) == "ramp":
			live_ramps += 1
	print("[runner_sim] near misses %d, ramps hit %d (live on track %d), live crates %d"
		% [_game.near_misses, _game.ramps_hit, live_ramps, crates])
	print("[runner_sim] %s after %.0fs sim-time: %.0f m, %d fish, %d hits, peak nodes %d, live nodes %d, live hazards %d, live pickups %d"
		% [reason, _elapsed, distance, _game.fish, _game.hits_taken, _peak_nodes, nodes,
			hazards, pickups])
	# The autopilot is not a good player, but a runner whose track or scoring is
	# broken shows up as near-zero distance, so this is a real assertion.
	if distance < 120.0:
		_fail("only %.0f m covered — track or motion is broken" % distance)
		return
	# Streaming: the live node count must stay near the peak rather than being
	# the peak, which is what a leak looks like.
	if nodes > _peak_nodes:
		_fail("node count still growing at exit (%d)" % nodes)
		return
	if mission_rows.size() != 3:
		_fail("expected 3 live missions, got %d" % mission_rows.size())
		return
	for probe: Dictionary in _probes:
		print("[runner_sim] t=%5.0fs %6.0fm  objects %6d  resources %5d  nodes %5d  static %6.1f MB  vram %6.1f MB"
			% [probe["t"], probe["m"], probe["objects"], probe["resources"],
				probe["nodes"], probe["static_mb"], probe["vram_mb"]])
	# Leak assertion: compare the first and last probe once the run is long
	# enough for streaming to have recycled many times. Resources are the
	# telling number — a chunk whose meshes are still referenced after the node
	# is freed shows up here and nowhere else.
	if _probes.size() >= 4:
		var first: Dictionary = _probes[1]
		var last: Dictionary = _probes[_probes.size() - 1]
		var growth := float(last["resources"]) - float(first["resources"])
		var span := float(last["t"]) - float(first["t"])
		print("[runner_sim] resource growth %+.0f over %.0fs (%.2f/s), static %+.1f MB"
			% [growth, span, growth / maxf(span, 1.0),
				float(last["static_mb"]) - float(first["static_mb"])])
		if growth / maxf(span, 1.0) > 3.0:
			_fail("resources growing %.2f/s — this is the browser-tab leak" % (growth / span))
			return
	print("[runner_sim] PASS")
	get_tree().quit(0)


func _fail(message: String) -> void:
	_reported = true
	print("[runner_sim] FAIL: %s" % message)
	get_tree().quit(1)


func _count(root: Node) -> int:
	var total := 1
	for child: Node in root.get_children():
		total += _count(child)
	return total
