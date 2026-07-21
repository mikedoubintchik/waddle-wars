extends Node
## Headless Endless Expedition simulation: fixed seed, autopilot player,
## runs until the storm ends the run, validates score flow + determinism.
##   godot --headless res://tests/endless_sim.tscn


func _ready() -> void:
	# Determinism check: same seed -> identical generated layout.
	CourseEndless.run_seed = 424242
	var course_a := CourseEndless.new()
	var course_b := CourseEndless.new()
	add_child(course_a)
	add_child(course_b)
	var len_a := course_a.main_guide.length
	var len_b := course_b.main_guide.length
	var count_a := course_a.main_guide.points.size()
	var count_b := course_b.main_guide.points.size()
	course_a.queue_free()
	course_b.queue_free()
	if absf(len_a - len_b) > 0.01 or count_a != count_b:
		print("[endless_sim] FAIL: non-deterministic generation (%f vs %f, %d vs %d)" % [len_a, len_b, count_a, count_b])
		get_tree().quit(1)
		return
	print("[endless_sim] determinism OK (length %.0fm, %d samples)" % [len_a, count_a])

	Game.mode = Game.Mode.ENDLESS
	Game.course_id = "endless"
	Game.difficulty_id = "competitive"
	RaceManager.autopilot_player = true
	Engine.time_scale = 12.0
	var monitor := EndlessSimMonitor.new()
	get_tree().root.add_child.call_deferred(monitor)
	SceneRouter.go_to.call_deferred(Game.SCENE_RACE)


class EndlessSimMonitor:
	extends Node

	var _elapsed: float = 0.0
	var _report: float = 0.0

	func _process(delta: float) -> void:
		_elapsed += delta
		_report += delta
		var scene := get_tree().current_scene
		if scene != null and scene.name == "Results":
			Engine.time_scale = 1.0
			var result := Game.last_endless_result
			print("[endless_sim] run ended: score=%d distance=%.0f fish=%d" % [
				int(result.get("score", 0)), float(result.get("distance", 0.0)), int(result.get("fish", 0))])
			if int(result.get("score", 0)) > 100 and float(result.get("distance", 0.0)) > 100.0:
				print("[endless_sim] PASS")
				get_tree().quit(0)
			else:
				print("[endless_sim] FAIL: trivial score/distance")
				get_tree().quit(1)
			return
		if _report > 30.0:
			_report = 0.0
			var manager := _find_manager(scene)
			if manager != null and manager.player != null and is_instance_valid(manager.player):
				print("[endless_sim] t=%.0f progress=%.0f storm=%.0f score=%d" % [
					_elapsed, manager.player.progress, manager.storm_offset, manager.current_score()])
		if _elapsed > 500.0:
			print("[endless_sim] TIMEOUT — storm never caught the player?")
			get_tree().quit(1)

	func _find_manager(scene: Node) -> EndlessManager:
		if scene == null:
			return null
		for child: Node in scene.get_children():
			if child is EndlessManager:
				return child
		return null
