extends SceneTree
## Actual AnimationPlayer clock/blend tests; no runner, rendering or source assets.
var passes := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var review := load("res://_qa_local/motion_candidate_browser.gd")
	var helper: Node = review.new()
	var fixture := Node3D.new()
	root.add_child(fixture)
	var marker := Node3D.new()
	marker.name = "Marker"
	fixture.add_child(marker)
	var holder := Node3D.new()
	fixture.add_child(holder)
	var skeleton := Skeleton3D.new()
	fixture.add_child(skeleton)
	var player := AnimationPlayer.new()
	fixture.add_child(player)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var library := AnimationLibrary.new()
	library.add_animation("waddle", clip(1.2, Vector3.ZERO, Vector3.ZERO, true))
	library.add_animation("slide", clip(1.2, Vector3(20, 0, 0), Vector3(20, 0, 0), true))
	library.add_animation("jump", clip(1.0, Vector3(10, 0, 0), Vector3(10, 1, 0), false))
	player.add_animation_library("", library)
	helper.set("_animation", player)
	helper.set("_skeleton", skeleton)
	helper.set("_holder", holder)
	helper.set("_holder_rest", Vector3(0, 0.022, 0))
	helper.set("_clip_names", {"waddle": "waddle", "jump": "jump", "slide": "slide"})
	var airtime: float = review.JUMP_AIRTIME

	helper.call("_on_sample", ["waddle", 0.5])
	helper.call("_on_action", ["waddle"])
	check(near(player.current_animation_position, 0.0) and near(helper.get("_phase"), 0.0),
		"same-action restart resets clip and review phase together")
	helper.call("_advance_motion", 0.2)
	check(near(player.current_animation_position, 0.2) and near(helper.get("_phase"), 0.2 / 1.2),
		"restarted looping clip retains clock agreement")

	helper.call("_on_sample", ["jump", 0.5])
	helper.call("_on_action", ["jump"])
	check(near(player.current_animation_position, 0.0) and near(helper.get("_jump_height"), 0.0),
		"repeated jump restarts articulation and ballistic height together")
	helper.call("_advance_motion", airtime * 0.25)
	check(near(player.current_animation_position, 0.25) and near(helper.get("_phase"), 0.25),
		"normalized jump clip follows authoritative airtime")
	var clock_before := player.current_animation_position
	var height_before: float = helper.get("_jump_height")
	helper.call("_on_play", [false])
	helper.call("_advance_motion", 0.4)
	check(near(player.current_animation_position, clock_before) and near(helper.get("_jump_height"), height_before),
		"pause freezes both skeleton clock and ballistic height")

	helper.call("_on_sample", ["waddle", 0.0])
	helper.call("_on_action", ["jump"])
	helper.call("_advance_motion", 0.06)
	settle_blend(player, marker, "jump .06")
	check(near(marker.position.x, 5.0), "jump crossfade is halfway after .06 real seconds")
	check(near(player.current_animation_position, 0.06 / airtime), "jump speed changes incoming clip clock only")
	helper.call("_advance_motion", 0.06)
	settle_blend(player, marker, "jump .12")
	check(near(marker.position.x, 10.0), "jump crossfade completes after .12 real seconds")
	helper.call("_on_sample", ["waddle", 0.0])
	helper.call("_on_action", ["slide"])
	helper.call("_advance_motion", 0.06)
	settle_blend(player, marker, "slide .06")
	check(near(marker.position.x, 10.0), "slide uses the same .12 real-second crossfade")

	helper.call("_on_sample", ["jump", 0.9])
	helper.call("_on_play", [true])
	helper.call("_advance_motion", airtime * 0.1 + 0.000000001)
	check(helper.get("_action") == "waddle" and near(marker.position.y, 1.0)
		and near(holder.position.y, 0.022), "landing reaches authored final pose before grounded waddle blend")
	helper.call("_on_sample", ["jump", 0.9])
	helper.call("_on_play", [true])
	helper.call("_advance_motion", airtime * 0.1 + 0.03)
	settle_blend(player, marker, "landing overshoot .03")
	check(helper.get("_action") == "waddle" and near(player.current_animation_position, 0.03)
		and near(helper.get("_phase"), 0.03 / 1.2), "frame overshoot advances new waddle without discarding time")
	check(near(marker.position.y, 0.75) and near(holder.position.y, 0.022),
		"overshoot blends from complete landing pose without a height pop")
	helper.call("_advance_motion", 0.09)
	check(near(marker.position.y, 0.0) and near(player.current_animation_position, 0.12),
		"landing crossfade completes on the real-time clock")

	helper.free()
	fixture.free()
	print("[motion_candidate_playback] %d passed, %d failed" % [passes, failures])
	quit(1 if failures else 0)


func clip(duration: float, start: Vector3, finish: Vector3, looping: bool) -> Animation:
	var animation := Animation.new()
	animation.length = duration
	animation.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	var track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(track, NodePath("Marker"))
	animation.position_track_insert_key(track, 0.0, start)
	animation.position_track_insert_key(track, duration, finish)
	return animation


func near(actual: float, expected: float) -> bool:
	return absf(actual - expected) < 0.0001


func settle_blend(player: AnimationPlayer, marker: Node3D, label: String) -> void:
	# Godot 4.7 calculates incoming weight before decrementing the outgoing blend
	# timer. Evaluate once at zero delta to observe both weights at the same time.
	# This does not advance clip time or relax any timing/pose assertion.
	var before := marker.position
	var time := player.current_animation_position
	player.advance(0.0)
	print("MOTION_BLEND_DIAGNOSTIC " + JSON.stringify({"step": label,
		"before": var_to_str(before), "settled": var_to_str(marker.position),
		"time_before": time, "time_after": player.current_animation_position}))


func check(condition: bool, label: String) -> void:
	if condition:
		passes += 1
		print("PASS " + label)
	else:
		failures += 1
		push_error("FAIL " + label)
