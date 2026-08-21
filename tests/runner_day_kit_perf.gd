extends "res://tests/runner_perf_probe.gd"
## Fixed dense-view performance probe for staged DAY authored art. Gameplay
## scripts are frozen after the real runner finishes loading; track animation,
## renderer submission, VFX and scene resources remain live.
##
##   godot --path . --rendering-method gl_compatibility \
##     res://tests/runner_day_kit_perf.tscn -- \
##     tier=high w=1920 h=1080 warmup=5 seconds=30 enforce=true

const PERF_DISTANCE: float = 146.0

var _day_kit_injected: bool = false


func _ready() -> void:
	_out_path = "user://qa/runner_day_kit_perf.json"
	super._ready()


func _process(delta: float) -> void:
	if not _day_kit_injected and _game != null and _game.build_finished:
		_day_kit_injected = true
		var art_set := load("res://data/art/runner_art_set_foundation.tres") as RunnerArtSet
		var catalog := ArtCatalog.new()
		catalog.manifest_path = "res://tests/fixtures/art/runner_day_kit_catalog.json"
		var load_error := catalog.reload_manifest()
		if art_set == null or load_error != OK:
			_abort("DAY kit catalog setup failed: %s" % catalog.manifest_errors())
			return
		_game.track.configure_art(art_set, catalog)
		_game.track.setup_golden_slice(20260818, 1)
		var status := _game.track.authored_day_kit_status()
		if not bool(status.get("active", false)):
			_abort("DAY kit incomplete: %s" % status)
			return
		_game.player.distance = PERF_DISTANCE
		_game.player.position = Vector3(0.0, 0.0, -PERF_DISTANCE)
		_game.player.lane = 1
		_game.player.speed = RunnerConfig.MAX_SPEED
		_game.player.set_input_enabled(false)
		_game.player.set_process(false)
		_game.player.set_physics_process(false)
		_game.running = true
		_game.set_process(false)
		_game._place_camera(0.0, true)
		_game._blend_biome(1.0)
		ShaderWarmup.warm(_game)
		print("[runner_day_kit_perf] frozen distance=%.0fm assets=%d" % [
				PERF_DISTANCE, int(status.get("loaded", 0))])
	super._process(delta)
