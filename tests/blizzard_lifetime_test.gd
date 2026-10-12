extends Node
## Real five-second SceneTreeTimer lifetime and outgoing-race teardown.
## Run headless from an isolated-user-data project. Unexpected engine errors
## are failures even if Godot's process exit status happens to be zero.

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	var saved_pause := get_tree().paused
	var saved_time_scale := Engine.time_scale
	get_tree().paused = false
	Engine.time_scale = 1.0
	await _test_live_and_outgoing_clouds()
	await _test_paused_expiry()
	get_tree().paused = saved_pause
	Engine.time_scale = saved_time_scale
	await get_tree().process_frame
	print("[blizzard_lifetime] DONE: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _fixture() -> Dictionary:
	var arena := Node3D.new()
	arena.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(arena)
	var powerups := PowerupSystem.new()
	arena.add_child(powerups)
	var racer := Racer.new()
	arena.add_child(racer)
	# No course/controller: the real Racer physics callback returns immediately.
	# Calling this production path avoids unrelated scoring/progression writes.
	powerups._drop_blizzard(racer)
	var cloud: Area3D = null
	for child: Node in arena.get_children():
		if child is Area3D:
			cloud = child as Area3D
	return {"arena": arena, "cloud": cloud}


func _bound_lifetime(cloud: Area3D) -> SceneTreeTimer:
	# A target-bound callable registers an incoming connection on the cloud;
	# cloud deletion then disconnects it instead of leaving a lambda capture.
	if not is_instance_valid(cloud):
		return null
	for row: Dictionary in cloud.get_incoming_connections():
		var callback: Callable = row["callable"]
		var source_signal: Signal = row["signal"]
		if callback.get_object() == cloud and callback.get_method() == &"queue_free" \
				and source_signal.get_name() == &"timeout":
			return source_signal.get_object() as SceneTreeTimer
	return null


func _test_live_and_outgoing_clouds() -> void:
	var live := _fixture()
	var cloud := live["cloud"] as Area3D
	_check("actual_blizzard_cloud_created", is_instance_valid(cloud))
	var lifetime := _bound_lifetime(cloud)
	_check("lifetime_callback_owned_by_cloud", lifetime != null)
	_check("actual_lifetime_is_exactly_five_seconds",
		lifetime != null and is_equal_approx(lifetime.time_left, 5.0))
	var outgoing := _fixture()
	var outgoing_cloud: WeakRef = weakref(outgoing["cloud"])
	var outgoing_lifetime := _bound_lifetime(outgoing["cloud"] as Area3D)
	(outgoing["arena"] as Node3D).free()
	_check("outgoing_race_frees_cloud_before_timeout", outgoing_cloud.get_ref() == null)
	_check("freed_cloud_disconnects_lifetime_callback",
		outgoing_lifetime != null and outgoing_lifetime.timeout.get_connections().is_empty())
	await get_tree().create_timer(4.5).timeout
	_check("live_cloud_retained_before_five_second_expiry", is_instance_valid(cloud))
	# Both real production lifetime timers have now had time to fire. The old
	# lambda emits its freed-capture error here even though its guard returns.
	await get_tree().create_timer(0.75).timeout
	_check("live_cloud_freed_after_actual_timeout", not is_instance_valid(cloud))
	(live["arena"] as Node3D).free()


func _test_paused_expiry() -> void:
	var fixture := _fixture()
	var cloud: WeakRef = weakref(fixture["cloud"])
	get_tree().paused = true
	# Preserve create_timer(5.0)'s existing process_always=true semantics: a
	# pause does not extend a blizzard cloud's lifetime.
	await get_tree().create_timer(5.25).timeout
	_check("existing_lifetime_expires_while_gameplay_paused", cloud.get_ref() == null)
	get_tree().paused = false
	(fixture["arena"] as Node3D).free()


func _check(label: String, ok: bool) -> void:
	if ok:
		_passed += 1
		print("[blizzard_lifetime] PASS " + label)
	else:
		_failed += 1
		print("[blizzard_lifetime] FAIL " + label)
