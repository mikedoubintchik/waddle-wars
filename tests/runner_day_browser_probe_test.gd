extends Node
## QA metadata/guard regression, not browser rendering or timing evidence.
const Bridge := preload("res://_qa_local/runner_day_course_bridge.gd")
var passed := 0
var failed := 0
func _ready() -> void:
	var probe := Bridge.new()
	add_child(probe)
	_check("native bridge disabled", not probe._enabled)
	_check("exact bounded checkpoints", probe.DISTANCES == [0.0,60.0,146.0,266.0,600.0,650.0])
	_check("untrusted call cannot start", not probe._start_course("continuous"))
	_check("invalid mode rejected", not probe._start_course("teleport"))
	var packed := load(probe.COURSE_SCENE) as PackedScene
	_check("QA replay scene loads", packed != null)
	var game := packed.instantiate() as RunnerGame
	_check("QA replay retains actual RunnerGame authority", game is RunnerGame)
	# Reproduce the repeat-start race with the old fully prepared course still
	# alive before its deferred SceneRouter teardown. No world/rendering needed.
	game.build_finished = true
	game._presentation_started = true
	probe._day_state = "loading"
	probe._day_session = 4
	probe._day_origin_instance_id = game.get_instance_id()
	_check("old ready course rejected before deferred route", not probe._matches_requested_course(game))
	probe._day_course_requested = true
	_check("old ready course rejected even after route request", not probe._matches_requested_course(game))
	var fresh_game := packed.instantiate() as RunnerGame
	_check("new actual course instance accepted after request", probe._matches_requested_course(fresh_game))
	_check("missing current course rejected during swap", not probe._matches_requested_course(null))
	_check("current loading session may route", probe._loading_session(4))
	_check("stale deferred session cannot route", not probe._loading_session(3))
	probe._day_state = "stopped"
	_check("stopped session cannot route", not probe._loading_session(4))
	probe._day_course_requested = false
	_check("fresh course not accepted before explicit request", not probe._matches_requested_course(fresh_game))
	fresh_game.free()
	game.free()
	for i: int in 20: probe._append_sample(200.0 if i == 19 else 10.0,40+i,400+i, i*1.0,0.75)
	var result := probe._sample_summary()
	_check("all actual draw intervals counted", result.samples == 20 and is_equal_approx(result.seconds,0.39))
	_check("draw intervals drive average fps", is_equal_approx(result.average_fps,20.0/0.39))
	_check("nearest rank p95", result.p95_ms == 10.0)
	_check("slow interval retained", result.max_ms == 200.0 and result.frames_over100ms == 1)
	_check("draw aggregate exact", result.draw_calls_average == 49.5 and result.draw_calls_peak == 59)
	_check("primitive aggregate exact", result.primitives_peak == 419)
	probe._day_mode = "stills";probe._day_state = "complete"
	_check("stills cannot claim performance", not probe.day_report().performance_evidence)
	probe._day_mode = "continuous"
	_check("headless cannot claim browser performance", not probe.day_report().performance_evidence)
	for i: int in probe.MAX_SAMPLES+5: probe._append_sample(10.0,1,1,1.0,1.0)
	_check("sample storage bounded", probe._day_ms.size() == probe.MAX_SAMPLES and probe._day_draws.size() == probe.MAX_SAMPLES and probe._day_primitives.size() == probe.MAX_SAMPLES and probe._day_distances.size() == probe.MAX_SAMPLES and probe._day_scale.size() == probe.MAX_SAMPLES)
	probe.free()
	print("[day-browser-probe] %d/%d passed" % [passed,passed+failed])
	get_tree().quit(1 if failed else 0)
func _check(label: String, ok: bool) -> void:
	if ok: passed += 1
	else: failed += 1
	print("[day-browser-probe] %s %s" % ["PASS" if ok else "FAIL",label])
