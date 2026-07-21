extends Node
## Headless race simulation: runs a full 8-racer AI race on a course at high
## time scale and verifies every racer finishes. Launch with:
##   godot --headless res://tests/race_sim.tscn -- course=glacier
## Exits 0 on success, 1 on failure.

var _monitor_added: bool = false


func _ready() -> void:
	var course_id := "glacier"
	var difficulty := "competitive"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("course="):
			course_id = arg.trim_prefix("course=")
		elif arg.begins_with("difficulty="):
			difficulty = arg.trim_prefix("difficulty=")
	print("[race_sim] course=%s difficulty=%s" % [course_id, difficulty])

	Game.mode = Game.Mode.QUICK_RACE
	Game.course_id = course_id
	Game.difficulty_id = difficulty
	RaceManager.autopilot_player = true
	Engine.time_scale = 12.0

	var monitor := RaceSimMonitor.new()
	monitor.course_id = course_id
	get_tree().root.add_child.call_deferred(monitor)
	_monitor_added = true
	# Hand off to the real race scene; the monitor survives the swap.
	SceneRouter.go_to.call_deferred(Game.SCENE_RACE)


class RaceSimMonitor:
	extends Node

	var course_id: String = ""
	var _elapsed: float = 0.0
	var _report_timer: float = 0.0

	func _process(delta: float) -> void:
		_elapsed += delta
		_report_timer += delta
		var scene := get_tree().current_scene
		if scene != null and scene.name == "Results":
			_finish()
			return
		if _report_timer > 20.0:
			_report_timer = 0.0
			_print_progress(scene)
		if _elapsed > 420.0 * Engine.time_scale / 12.0 and Engine.time_scale > 1.0:
			pass
		if _elapsed > 600.0:
			print("[race_sim] TIMEOUT after %.0fs sim-time" % _elapsed)
			_print_progress(scene)
			get_tree().quit(1)

	func _print_progress(scene: Node) -> void:
		if scene == null:
			return
		var manager := _find_manager(scene)
		if manager == null:
			print("[race_sim] no RaceManager yet (scene=%s)" % scene.name)
			return
		print("[race_sim] t=%.1f race_time=%.1f" % [_elapsed, manager.race_time])
		for racer: Racer in manager.racers:
			print("  %-8s pos=%d progress=%.0f state=%d cp=%d p=(%.0f,%.1f,%.0f) spd=%.1f steer=%.2f" % [
				racer.display_name, racer.race_position, racer.progress,
				racer.state, racer.last_checkpoint_index,
				racer.global_position.x, racer.global_position.y, racer.global_position.z,
				racer.current_speed, racer.controller.steer])

	func _find_manager(scene: Node) -> RaceManager:
		for child: Node in scene.get_children():
			if child is RaceManager:
				return child
		return null

	func _finish() -> void:
		Engine.time_scale = 1.0
		var results := Game.last_race_results
		print("[race_sim] RESULTS (%d rows):" % results.size())
		var failures: Array[String] = []
		for row: Dictionary in results:
			print("  %d. %-8s time=%.1f fish=%d dnf=%s" % [
				int(row["position"]), String(row["name"]),
				float(row["time"]), int(row["fish"]), str(bool(row["dnf"]))])
			if bool(row["dnf"]):
				failures.append("%s DNF" % String(row["name"]))
		if results.size() != 8:
			failures.append("expected 8 results, got %d" % results.size())
		if failures.is_empty():
			print("[race_sim] PASS course=%s" % course_id)
			get_tree().quit(0)
		else:
			print("[race_sim] FAIL: %s" % ", ".join(failures))
			get_tree().quit(1)
