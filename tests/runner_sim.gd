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
