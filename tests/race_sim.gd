extends Node
## Headless race simulation: runs a full 8-racer AI race on a course at high
## time scale and verifies every racer finishes. Launch with:
##   godot --headless res://tests/race_sim.tscn -- course=glacier
## Focused real section-3 traversal (normal physics, no result/respawn pass):
##   godot --headless res://tests/race_sim.tscn -- iceberg_platforms
## Exits 0 on success, 1 on failure.

var _monitor_added: bool = false


func _ready() -> void:
	var course_id := "glacier"
	var difficulty := "competitive"
	var time_trial := false
	var platform_traversal := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("course="):
			course_id = arg.trim_prefix("course=")
		elif arg.begins_with("difficulty="):
			difficulty = arg.trim_prefix("difficulty=")
		elif arg == "tt":
			time_trial = true
		elif arg == "iceberg_platforms":
			platform_traversal = true
	if platform_traversal:
		await _run_iceberg_platform_traversal()
		return
	print("[race_sim] course=%s difficulty=%s tt=%s" % [course_id, difficulty, str(time_trial)])

	Game.mode = Game.Mode.TIME_TRIAL if time_trial else Game.Mode.QUICK_RACE
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


## Uses the production course, Racer, controller, platform collision/motion
## and all three selectable difficulty profiles. One racer at a time isolates
## traversal from rival shove randomness. Watchdogs remain enabled: any
## respawn is failure, never evidence that the crossing was traversed.
func _run_iceberg_platform_traversal() -> void:
	Engine.time_scale = 1.0
	var crossing := CourseIceberg.new()
	add_child(crossing)
	await crossing.build_ready()
	crossing.process_mode = Node.PROCESS_MODE_INHERIT
	var platforms: Array[HazardPlatform] = []
	for child: Node in crossing.get_children():
		if child is HazardPlatform and child.position.z < -635.0 and child.position.z > -675.0:
			platforms.append(child as HazardPlatform)
	if platforms.size() != 3:
		print("[iceberg_platforms] FAIL expected 3 actual section-3 platforms, got %d" % platforms.size())
		get_tree().quit(1)
		return
	var failures: Array[String] = []
	var case_index := 0
	for arrival_phase: float in [0.0, 1.7, 3.4]:
		for difficulty_id: String in DifficultyDB.ORDER:
			case_index += 1
			# Vary only arrival time, not platform size, heave, phase spacing,
			# seeded period/yaw or collision. The normal callbacks keep moving.
			for platform: HazardPlatform in platforms:
				platform._time = platform.phase_offset + arrival_phase
				platform._physics_process(0.0)
			var actor := Racer.new()
			add_child(actor)
			var start := crossing.main_guide.nearest(Vector3(0.0, 8.4, -612.0))
			actor.global_transform = crossing.main_guide.transform_at(float(start["offset"]))
			actor.position += Vector3.UP * 0.15
			var initial_lateral := 0.0 if arrival_phase == 0.0 else (3.5 if arrival_phase == 1.7 else -3.5)
			actor.position += actor.global_transform.basis.x * initial_lateral
			var driver := AIController.new()
			var profile := DifficultyDB.get_item(difficulty_id)
			actor.setup("platform_qa_%d" % case_index, "Platform QA", false,
				PersonalitiesDB.get_item("ziggy"), driver, crossing)
			actor.speed_scale = float(profile["speed_scale"])
			actor.current_speed = Racer.BASE_SPEED * actor.speed_scale
			actor._update_guide()
			driver.configure(actor, crossing, PersonalitiesDB.get_item("ziggy"), profile,
				70_000 + case_index)
			# ±5 is the existing pickup-attraction limit. Stress the supported
			# bad line without disabling normal AI, movement or its watchdogs.
			driver._lateral_offset = 5.0 if initial_lateral >= 0.0 else -5.0
			var evidence := {"respawns": 0, "contacts": {}, "moving_contacts": {}, "center_seen": false}
			actor.respawned.connect(func(_racer: Racer) -> void:
				evidence["respawns"] = int(evidence["respawns"]) + 1)
			var reached_exit := false
			var reason := ""
			var ticks := 0
			for tick: int in 1200:
				await get_tree().physics_frame
				ticks = tick + 1
				if int(evidence["respawns"]) > 0:
					reason = "respawned instead of traversing"
					break
				if actor.global_position.y < 6.0:
					reason = "fell below crossing"
					break
				if driver._center_line_active:
					evidence["center_seen"] = true
					if not is_zero_approx(driver._lateral_offset):
						reason = "center hint allowed a random/pickup detour"
						break
				for index: int in actor.get_slide_collision_count():
					var contact := actor.get_slide_collision(index)
					var body := contact.get_collider() as HazardPlatform
					if body in platforms and contact.get_normal().y > 0.5:
						evidence["contacts"][body.get_instance_id()] = true
						if body.move_range > 0.0:
							evidence["moving_contacts"][body.get_instance_id()] = true
				if actor.global_position.z < -704.0 and actor.is_on_floor():
					reached_exit = true
					break
			if reason.is_empty() and not reached_exit:
				reason = "did not reach grounded far-side exit within 1200 physics ticks"
			if reason.is_empty() and (evidence["contacts"].size() < 2 or evidence["moving_contacts"].is_empty()):
				reason = "missing real support contacts on moving crossing"
			if reason.is_empty() and (not bool(evidence["center_seen"]) or driver._center_line_active):
				reason = "center hint did not enter then release outside window"
			var label := "%s phase=%.1f seed=%d" % [difficulty_id, arrival_phase, 70_000 + case_index]
			print("[iceberg_platforms] %s %s ticks=%d respawns=%d contacts=%d moving=%d exit=(%.2f,%.2f,%.2f)%s" % [
				"PASS" if reason.is_empty() else "FAIL", label, ticks, evidence["respawns"],
				evidence["contacts"].size(), evidence["moving_contacts"].size(),
				actor.global_position.x, actor.global_position.y, actor.global_position.z,
				"" if reason.is_empty() else " reason=" + reason])
			if not reason.is_empty():
				failures.append(label + ": " + reason)
			actor.queue_free()
			await get_tree().process_frame
	print("[iceberg_platforms] DONE %d cases, %d failures; no gameplay/performance approval" % [case_index, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


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
		var expected := 1 if Game.mode == Game.Mode.TIME_TRIAL else 8
		print("[race_sim] RESULTS (%d rows):" % results.size())
		var failures: Array[String] = []
		for row: Dictionary in results:
			print("  %d. %-8s time=%.1f fish=%d dnf=%s" % [
				int(row["position"]), String(row["name"]),
				float(row["time"]), int(row["fish"]), str(bool(row.get("dnf", false)))])
			if bool(row.get("dnf", false)):
				failures.append("%s DNF" % String(row["name"]))
		if Game.mode == Game.Mode.TIME_TRIAL:
			var ghost_file := GhostSystem.ghost_path(Game.course_id)
			if not FileAccess.file_exists(ghost_file):
				failures.append("no ghost file recorded at %s" % ghost_file)
			else:
				print("[race_sim] ghost file present: %s" % ghost_file)
		if results.size() != expected:
			failures.append("expected %d results, got %d" % [expected, results.size()])
		if failures.is_empty():
			print("[race_sim] PASS course=%s" % course_id)
			get_tree().quit(0)
		else:
			print("[race_sim] FAIL: %s" % ", ".join(failures))
			get_tree().quit(1)
