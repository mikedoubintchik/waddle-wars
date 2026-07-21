extends Node
## Headless tutorial simulation: autopilot penguin completes Waddle School
## end to end; validates the tutorial course, prompts, and completion flow.
##   godot --headless res://tests/tutorial_sim.tscn


func _ready() -> void:
	Game.mode = Game.Mode.TUTORIAL
	Game.course_id = "tutorial"
	RaceManager.autopilot_player = true
	Engine.time_scale = 10.0
	var monitor := TutorialSimMonitor.new()
	get_tree().root.add_child.call_deferred(monitor)
	SceneRouter.go_to.call_deferred(Game.SCENE_RACE)


class TutorialSimMonitor:
	extends Node

	var _elapsed: float = 0.0

	func _process(delta: float) -> void:
		_elapsed += delta
		var scene := get_tree().current_scene
		if scene != null and scene.name == "Results":
			Engine.time_scale = 1.0
			if Progression.is_tutorial_complete():
				print("[tutorial_sim] PASS — tutorial completed, achievement=%s" %
					str(Progression.is_achievement_unlocked("first_waddle")))
				get_tree().quit(0)
			else:
				print("[tutorial_sim] FAIL — results reached but tutorial not marked complete")
				get_tree().quit(1)
			return
		if _elapsed > 300.0:
			print("[tutorial_sim] TIMEOUT")
			if scene != null:
				for child: Node in scene.get_children():
					if child is TutorialManager:
						var manager := child as TutorialManager
						if manager.player != null and is_instance_valid(manager.player):
							print("  player progress=%.0f pos=%s state=%d" % [
								manager.player.progress, str(manager.player.global_position), manager.player.state])
			get_tree().quit(1)
