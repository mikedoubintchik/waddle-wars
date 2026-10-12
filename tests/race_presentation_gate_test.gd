extends Node
## Deterministic startup gate checks plus real-tree racer lifecycle checks.
## Minimal guide only: no course art, scene swaps or progression/save writes.
## The typed warmup fixture does not claim to compile shaders in headless mode.

class PendingWarmup:
	extends ShaderWarmup

	func _ready() -> void:
		set_process(false)

	func _process(_delta: float) -> void:
		pass


class CourseProbe:
	extends CourseBase

	func _ready() -> void:
		pass


class MovingHazardProbe:
	extends Node3D

	var ticks: int = 0

	func _physics_process(_delta: float) -> void:
		ticks += 1
		position.x += 0.1


class SpawnPathProbe:
	extends RaceManager

	var use_staged_spawn: bool = false

	func _queue_spawn(work: Callable) -> void:
		# Exercise both production spawn paths under headless. Only the platform
		# choice changes; setup, racer creation, deferred add and queue pump stay real.
		_spawn_staged = use_staged_spawn
		super._queue_spawn(work)


class EndlessSpawnPathProbe:
	extends EndlessManager

	var use_staged_spawn: bool = false

	func _queue_spawn(work: Callable) -> void:
		_spawn_staged = use_staged_spawn
		super._queue_spawn(work)


var _passes: int = 0
var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var was_presenting: bool = SceneRouter._presenting
	var was_busy: bool = SceneRouter._busy
	var was_autopilot: bool = RaceManager.autopilot_player
	RaceManager.autopilot_player = false
	SceneRouter._presenting = false
	SceneRouter._busy = false
	for endless: bool in [false, true]:
		_test_loader_hold(endless)
		_test_pending_warmup(endless)
		_test_visible_countdown(endless)
	_test_deferred_grid_hold()
	_test_staged_spawn_pump()
	for endless: bool in [false, true]:
		for staged: bool in [false, true]:
			await _test_real_tree_spawn_freeze(endless, staged)
	SceneRouter._presenting = was_presenting
	SceneRouter._busy = was_busy
	RaceManager.autopilot_player = was_autopilot
	# Real countdown SFX can still own playback on the audio mixer thread when
	# this short test exits. Drain test-only playback after every assertion;
	# gameplay logic and its production audio calls remain unchanged.
	for child: Node in AudioManager.get_children():
		if child is AudioStreamPlayer:
			(child as AudioStreamPlayer).stop()
		elif child is AudioStreamPlayer3D:
			(child as AudioStreamPlayer3D).stop()
	await get_tree().process_frame
	await get_tree().create_timer(0.05).timeout
	await get_tree().process_frame
	print("[race_presentation_gate] DONE: %d passed, %d failed" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(label: String, success: bool, detail: String = "") -> void:
	if success:
		_passes += 1
		print("[race_presentation_gate] PASS %s" % label)
	else:
		_failures += 1
		print("[race_presentation_gate] FAIL %s %s" % [label, detail])


func _fixture(endless: bool, grid_ready: bool = true) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var manager: RaceManager = EndlessManager.new() if endless else RaceManager.new()
	root.add_child(manager)
	if manager is EndlessManager:
		# The unrelated onboarding hint owns a one-second SceneTreeTimer. These
		# fixtures finish synchronously, so do not leave that UI callback alive
		# after freeing its manager. Countdown and storm logic remain real.
		manager.race_started.disconnect((manager as EndlessManager)._show_storm_hint)
	manager.set_process(false)
	manager.set_physics_process(false)
	manager._countdown_timer = 1.0
	if grid_ready:
		# Empty grid exercises the real completion seam without making a course.
		manager._place_on_grid()
	var human := PlayerController.new()
	human.input_enabled = false
	var racer := Racer.new()
	racer.is_player = true
	racer.controller = human
	racer.add_child(human)
	racer.set_physics_process(false)
	manager.racers.append(racer)
	# Racer deliberately stays outside the tree: manager enables its real
	# physics flag at GO, but no movement/collision simulation runs in this test.
	# Leaving manager.player null also avoids Endless's unrelated storm visual.
	var ticks: Array[int] = []
	manager.countdown_tick.connect(func(value: int) -> void: ticks.append(value))
	return {"root": root, "manager": manager, "racer": racer, "human": human,
			"ticks": ticks, "label": "endless" if endless else "race"}


func _free_fixture(fixture: Dictionary) -> void:
	(fixture["root"] as Node).free()
	(fixture["racer"] as Racer).free()


func _test_loader_hold(endless: bool) -> void:
	var fixture := _fixture(endless)
	var manager := fixture["manager"] as RaceManager
	var human := fixture["human"] as PlayerController
	var racer := fixture["racer"] as Racer
	var label := String(fixture["label"])
	SceneRouter._presenting = true
	for _tick: int in 4:
		manager._physics_process(1.0)
	_check(label + "_loader_keeps_full_countdown",
			manager._countdown_value == 4 and is_equal_approx(manager._countdown_timer, 1.0))
	_check(label + "_loader_emits_no_countdown_or_go", (fixture["ticks"] as Array).is_empty())
	_check(label + "_loader_keeps_race_input_and_physics_stopped",
			not manager.started and not human.input_enabled and not racer.is_physics_processing())
	if endless:
		_check("endless_loader_keeps_storm_frozen",
				is_equal_approx((manager as EndlessManager).storm_offset,
						-EndlessManager.STORM_START_GAP))
	SceneRouter._presenting = false
	_free_fixture(fixture)


func _test_pending_warmup(endless: bool) -> void:
	var fixture := _fixture(endless)
	var manager := fixture["manager"] as RaceManager
	var pending := PendingWarmup.new()
	(fixture["root"] as Node).add_child(pending)
	manager._physics_process(10.0)
	_check(String(fixture["label"]) + "_direct_entry_waits_for_exact_scene_warmup",
			manager._countdown_value == 4 and is_equal_approx(manager._countdown_timer, 1.0)
			and (fixture["ticks"] as Array).is_empty() and not manager.started)
	pending.free()
	manager._physics_process(10.0)
	_check(String(fixture["label"]) + "_warmup_release_discards_delta",
			manager._countdown_value == 4 and is_equal_approx(manager._countdown_timer, 1.0)
			and not manager.started)
	_free_fixture(fixture)


func _test_visible_countdown(endless: bool) -> void:
	var fixture := _fixture(endless)
	var manager := fixture["manager"] as RaceManager
	var human := fixture["human"] as PlayerController
	var racer := fixture["racer"] as Racer
	var label := String(fixture["label"])
	manager._physics_process(10.0)
	_check(label + "_first_visible_tick_discards_loading_delta",
			manager._countdown_value == 4 and is_equal_approx(manager._countdown_timer, 1.0)
			and (fixture["ticks"] as Array).is_empty())
	for _tick: int in 3:
		manager._physics_process(1.0)
	_check(label + "_visible_countdown_has_full_three_numbers",
			fixture["ticks"] == [3, 2, 1] and not manager.started
			and not human.input_enabled and not racer.is_physics_processing())
	# These actions can arrive from touch callbacks while countdown disables
	# physics; they must not burst into gameplay when input is finally enabled.
	human.jump_pressed = true
	human.shove_pressed = true
	human.item_pressed = true
	human.touch_jump()
	human.touch_shove()
	human.touch_item()
	human.touch_item_back()
	human.touch_steer = 0.4
	human.touch_slide_changed(true)
	manager._physics_process(1.0)
	_check(label + "_go_enables_input_and_physics_after_full_countdown",
			fixture["ticks"] == [3, 2, 1, 0] and manager.started
			and human.input_enabled and racer.is_physics_processing())
	_check(label + "_go_discards_queued_action_edges",
			not human.jump_pressed and not human.shove_pressed and not human.item_pressed
			and not human._touch_jump and not human._touch_shove
			and not human._touch_item and not human._touch_item_back)
	_check(label + "_go_preserves_held_touch_controls",
			is_equal_approx(human.touch_steer, 0.4) and human._touch_slide)
	_free_fixture(fixture)


func _test_deferred_grid_hold() -> void:
	var fixture := _fixture(false, false)
	var manager := fixture["manager"] as RaceManager
	_check("deferred_grid_fixture_has_empty_spawn_queue", manager._spawn_queue.is_empty())
	manager._physics_process(10.0)
	_check("empty_queue_does_not_release_pending_deferred_grid",
			manager._countdown_value == 4 and is_equal_approx(manager._countdown_timer, 1.0)
			and (fixture["ticks"] as Array).is_empty())
	_free_fixture(fixture)


func _test_staged_spawn_pump() -> void:
	var fixture := _fixture(false, false)
	var manager := fixture["manager"] as RaceManager
	manager._spawn_staged = true
	var work: Array[String] = []
	manager._queue_spawn(func() -> void: work.append("first"))
	manager._queue_spawn(func() -> void: work.append("second"))
	manager._queue_spawn(func() -> void: work.append("third"))
	SceneRouter._presenting = true
	manager._process(0.0)
	_check("staged_spawn_pump_keeps_its_bounded_work_during_loader",
			work == ["first", "second"] and manager._spawn_queue.size() == 1)
	manager._process(0.0)
	_check("staged_spawn_pump_finishes_while_gameplay_is_held",
			work == ["first", "second", "third"] and manager._spawn_queue.is_empty())
	manager._physics_process(10.0)
	_check("spawn_work_does_not_bypass_grid_or_presentation_gate",
			manager._countdown_value == 4 and is_equal_approx(manager._countdown_timer, 1.0))
	SceneRouter._presenting = false
	_free_fixture(fixture)


func _test_real_tree_spawn_freeze(endless: bool, staged: bool) -> void:
	var label := ("endless" if endless else "race") + ("_staged" if staged else "_deferred")
	SceneRouter._busy = false
	SceneRouter._presenting = true
	var fixture := Node3D.new()
	add_child(fixture)
	var course := CourseProbe.new()
	var curve := Curve3D.new()
	curve.add_point(Vector3(0.0, 20.0, 30.0))
	curve.add_point(Vector3(0.0, 20.0, -700.0))
	course.main_guide = PathGuide.new(curve)
	course.build_finished = true
	course.finish_offset = 650.0
	fixture.add_child(course)
	var hazard := MovingHazardProbe.new()
	course.add_child(hazard)
	var powerups := PowerupSystem.new()
	fixture.add_child(powerups)
	var manager: RaceManager
	if endless:
		var endless_probe := EndlessSpawnPathProbe.new()
		endless_probe.use_staged_spawn = staged
		manager = endless_probe
	else:
		var race_probe := SpawnPathProbe.new()
		race_probe.use_staged_spawn = staged
		manager = race_probe
	fixture.add_child(manager)
	if endless:
		manager.race_started.disconnect((manager as EndlessManager)._show_storm_hint)
	manager.set_process(false)
	manager.setup(course, powerups, false)
	# Drive manager countdown/pump explicitly; real Racer callbacks remain
	# untouched so entering the tree and actual physics ticks can expose leaks.
	manager.set_physics_process(false)
	_check(label + "_all_racers_disabled_before_deferred_add",
			manager.racers.size() == 8 and _all_racers_frozen(manager))
	await get_tree().process_frame
	await get_tree().process_frame
	_check(label + "_all_racers_enter_real_tree",
			manager.racers.all(func(racer: Racer) -> bool: return racer.is_inside_tree()))
	_check(label + "_ready_does_not_reenable_racer_physics", _all_racers_frozen(manager))
	var setup_physics_frozen := true
	if staged:
		_check(label + "_real_setup_queue_waits_for_pump", manager._spawn_queue.size() == 9)
		for _stage_index: int in 5:
			manager._process(0.0)
			var stage_before := _capture_racer_clocks(manager)
			await get_tree().physics_frame
			await get_tree().physics_frame
			setup_physics_frozen = setup_physics_frozen and _racers_unchanged(manager, stage_before)
		_check(label + "_actual_physics_cannot_advance_between_spawn_batches", setup_physics_frozen)
	_check(label + "_real_grid_and_controllers_finish",
			manager._grid_placed and manager._spawn_queue.is_empty()
			and manager.racers.all(func(racer: Racer) -> bool: return racer.controller != null))
	var before := _capture_racer_clocks(manager)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(label + "_actual_physics_cannot_move_or_tick_under_loader",
			_racers_unchanged(manager, before) and _all_racers_frozen(manager))
	_check(label + "_course_hazard_does_not_advance_under_loader",
			hazard.ticks == 0 and hazard.position == Vector3.ZERO)
	_check(label + "_human_input_stays_disabled",
			not (manager.player.controller as PlayerController).input_enabled)
	SceneRouter._presenting = false
	manager._physics_process(120.0)
	_check(label + "_real_tree_release_keeps_full_countdown",
			manager._countdown_value == 4 and is_equal_approx(manager._countdown_timer, 1.0)
			and not manager.started and _all_racers_frozen(manager))
	for _count: int in 3:
		manager._physics_process(1.0)
		await get_tree().physics_frame
		await get_tree().physics_frame
	_check(label + "_actual_physics_stays_frozen_through_visible_countdown",
			_racers_unchanged(manager, before) and _all_racers_frozen(manager) and not manager.started)
	_check(label + "_course_hazard_stays_frozen_through_countdown", hazard.ticks == 0)
	manager._physics_process(1.0)
	_check(label + "_go_reenables_all_real_racers",
			manager.started and (manager.player.controller as PlayerController).input_enabled
			and manager.racers.all(func(racer: Racer) -> bool: return racer.is_physics_processing()))
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(label + "_actual_physics_resumes_only_after_go", not _racers_unchanged(manager, before))
	_check(label + "_course_hazard_resumes_only_after_go", hazard.ticks > 0)
	fixture.free()


func _all_racers_frozen(manager: RaceManager) -> bool:
	return manager.racers.all(func(racer: Racer) -> bool: return not racer.is_physics_processing())


func _capture_racer_clocks(manager: RaceManager) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	for racer: Racer in manager.racers:
		racer._boost_timer = 5.0
		racer._invuln_timer = 3.0
		transforms.append(racer.global_transform)
	return transforms


func _racers_unchanged(manager: RaceManager, transforms: Array[Transform3D]) -> bool:
	for index: int in manager.racers.size():
		var racer := manager.racers[index]
		if racer.global_transform != transforms[index] or racer._boost_timer != 5.0 \
				or racer._invuln_timer != 3.0:
			return false
	return true
