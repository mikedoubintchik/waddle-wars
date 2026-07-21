extends Node
## Headless Grand Prix flow test: three autopilot races on the full cup,
## points accumulate, standings valid, records saved.
##   godot --headless res://tests/gp_sim.tscn


func _ready() -> void:
	RaceManager.autopilot_player = true
	Engine.time_scale = 12.0
	Game.start_grand_prix.call_deferred("competitive")
	var monitor := GPSimMonitor.new()
	get_tree().root.add_child.call_deferred(monitor)


class GPSimMonitor:
	extends Node

	var _elapsed: float = 0.0
	var _races_done: int = 0
	var _advance_cooldown: float = 0.0

	func _process(delta: float) -> void:
		_elapsed += delta
		_advance_cooldown -= delta
		var scene := get_tree().current_scene
		if scene != null and scene.name == "Results" and _advance_cooldown <= 0.0:
			_advance_cooldown = 2.0
			_races_done += 1
			print("[gp_sim] round %d results reached; standings rows=%d" % [
				_races_done, Game.gp_standings().size()])
			if Game.gp_round < CoursesDB.GRAND_PRIX_ORDER.size() - 1:
				Game.advance_grand_prix()
			else:
				_finish()
		if _elapsed > 900.0:
			print("[gp_sim] TIMEOUT (round %d, elapsed %.0f)" % [_races_done, _elapsed])
			get_tree().quit(1)

	func _finish() -> void:
		Engine.time_scale = 1.0
		var standings := Game.gp_standings()
		var failures: Array[String] = []
		if _races_done != 3:
			failures.append("expected 3 rounds, got %d" % _races_done)
		if standings.size() != 8:
			failures.append("expected 8 standings rows, got %d" % standings.size())
		var total := 0
		for row: Dictionary in standings:
			total += int(row["points"])
		# 3 races x sum(GP_POINTS)=39 -> 117 total points.
		if total != 117:
			failures.append("points total %d != 117" % total)
		for i: int in standings.size() - 1:
			if int(standings[i]["points"]) < int(standings[i + 1]["points"]):
				failures.append("standings not sorted")
				break
		print("[gp_sim] final standings:")
		for i: int in standings.size():
			print("  %d. %-8s %d pts" % [i + 1, String(standings[i]["name"]), int(standings[i]["points"])])
		if failures.is_empty():
			print("[gp_sim] PASS")
			get_tree().quit(0)
		else:
			print("[gp_sim] FAIL: %s" % ", ".join(failures))
			get_tree().quit(1)
