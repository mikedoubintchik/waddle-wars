extends Node
## One-shot diagnostic: enters a race, waits, then dumps each racer's
## SnowTrail state. The watcher hangs off the tree ROOT, because
## SceneRouter.go_to frees the current scene -- and this probe is it.

func _ready() -> void:
	Game.mode = Game.Mode.QUICK_RACE
	Game.course_id = "glacier"
	Game.difficulty_id = "competitive"
	RaceManager.autopilot_player = true
	SceneRouter.go_to.call_deferred(Game.SCENE_RACE)
	var watcher := Watcher.new()
	get_tree().root.add_child.call_deferred(watcher)


class Watcher:
	extends Node
	var _elapsed := 0.0
	var _done := false

	func _process(delta: float) -> void:
		if _done:
			return
		_elapsed += delta
		if _elapsed < 12.0:
			return
		_done = true
		var racers := get_tree().get_nodes_in_group(&"racers")
		print("[probe] racers=", racers.size())
		for node: Node in racers:
			var trail: Node = null
			for child: Node in node.get_children():
				if child is SnowTrail:
					trail = child
					break
			if trail == null:
				print("[probe] ", node.get("racer_key"), ": NO TRAIL NODE")
				continue
			var st := trail as SnowTrail
			var mm := st.multimesh
			var info := "live=%d head=%d visible=%s" % [st._live, st._head, st.visible]
			if st._live > 0:
				var idx: int = (st._head - 1 + SnowTrail.SEGMENTS) % SnowTrail.SEGMENTS
				info += " last_origin=%s color=%s gxform_origin=%s" % [
					mm.get_instance_transform(idx).origin, mm.get_instance_color(idx),
					st.global_transform.origin]
			print("[probe] ", node.get("racer_key"), ": ", info)
		get_tree().quit()
