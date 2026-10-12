extends Node
## Headless lifecycle/census regression, not shader compilation or visual QA.
## Real deferred/staged actor setup; only warmup rendering and tutorial widgets
## are substituted. Run via the main suite's copied project and isolated user://.

class CensusProbe:
	extends ShaderWarmup

	func _ready() -> void:
		set_process(false)
		_build_queue()

	func _process(_delta: float) -> void:
		pass


class CourseProbe:
	extends CourseBase

	func _ready() -> void:
		pass


class TutorialCourseProbe:
	extends CourseTutorial

	func _ready() -> void:
		pass


class RaceProbe:
	extends RaceManager

	var staged: bool = false
	var after_setup: Callable
	var census: Callable

	func _queue_spawn(work: Callable) -> void:
		_spawn_staged = staged
		if work.get_object() is Racer and work.get_method() == &"setup":
			var actor := work.get_object() as Racer
			super._queue_spawn(func() -> void:
				work.call()
				after_setup.call(actor))
		else:
			super._queue_spawn(work)

	# On the regression baseline this override simply never gets called.
	func _start_visual_warmup() -> void:
		census.call(self)


class EndlessProbe:
	extends EndlessManager

	var staged: bool = false
	var after_setup: Callable
	var census: Callable

	func _queue_spawn(work: Callable) -> void:
		_spawn_staged = staged
		if work.get_object() is Racer and work.get_method() == &"setup":
			var actor := work.get_object() as Racer
			super._queue_spawn(func() -> void:
				work.call()
				after_setup.call(actor))
		else:
			super._queue_spawn(work)

	func _start_visual_warmup() -> void:
		census.call(self)


class QuietTutorial:
	extends TutorialManager

	var prompts_ready: bool = false
	var fx_ready: bool = false
	var lessons: Array[int] = []

	func _build_prompts() -> void:
		prompts_ready = true

	func _build_celebration_fx() -> void:
		fx_ready = true

	func _apply_step_card(_step: Dictionary) -> void:
		lessons.append(_step_index)

	func _celebrate_station(_accent: Color) -> void:
		pass


class TutorialProbe:
	extends QuietTutorial

	var after_prompts: Callable
	var census: Callable

	func _build_prompts() -> void:
		super._build_prompts()
		after_prompts.call(self)

	func _start_visual_warmup() -> void:
		census.call(self)


var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var saved_busy: bool = SceneRouter._busy
	var saved_presenting: bool = SceneRouter._presenting
	var saved_autopilot: bool = RaceManager.autopilot_player
	SceneRouter._busy = false
	SceneRouter._presenting = false
	RaceManager.autopilot_player = false
	_check("headless_fixture_has_no_rendering_claim", GameConfig.is_headless())
	var orchestrator := FileAccess.get_file_as_string("res://scripts/gameplay/race.gd")
	_check("orchestrator_no_longer_censuses_before_deferred_actors",
		not orchestrator.is_empty() and not orchestrator.contains("ShaderWarmup.warm(self)"))
	for mode: String in ["race", "endless", "time_trial"]:
		for staged: bool in [false, true]:
			await _test_race_boundary(mode, staged)
	await _test_tutorial_boundary()
	await _test_direct_headless()
	await _test_canceled_staged_scene()
	SceneRouter._busy = saved_busy
	SceneRouter._presenting = saved_presenting
	RaceManager.autopilot_player = saved_autopilot
	# Tutorial uses production music/chimes. Stop only test-owned playback at
	# teardown and allow mixer handoff before engine exit, matching gate tests.
	for child: Node in AudioManager.get_children():
		if child is AudioStreamPlayer:
			(child as AudioStreamPlayer).stop()
		elif child is AudioStreamPlayer3D:
			(child as AudioStreamPlayer3D).stop()
	await get_tree().process_frame
	await get_tree().create_timer(0.05, true, false, true).timeout
	await get_tree().process_frame
	print("[race_warmup_boundary] DONE: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _fixture(tutorial: bool = false) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	# Sentinels occupy an early subtree so this tiny fixture tests collection
	# timing, not the independent 128-probe budget. They are created only after
	# real actor setup; they are not substitutes for actual production assets.
	var late := Node3D.new()
	late.name = "LateResourceSentinels"
	root.add_child(late)
	var course: CourseBase = TutorialCourseProbe.new() if tutorial else CourseProbe.new()
	var curve := Curve3D.new()
	curve.add_point(Vector3(0.0, 20.0, 30.0))
	curve.add_point(Vector3(0.0, 20.0, -700.0))
	course.main_guide = PathGuide.new(curve)
	course.finish_offset = 650.0
	course.build_finished = true
	root.add_child(course)
	var powerups := PowerupSystem.new()
	root.add_child(powerups)
	return {"root": root, "late": late, "course": course, "powerups": powerups,
		"census_count": 0, "warmup": null, "keys": [], "actor_setups": 0,
		"all_actor_setup_ready": true, "latch_held_at_census": false,
		"router_held_at_census": false, "all_ready_at_census": false,
		"shell_ready_at_census": false, "collected_all_late_resources": false}


func _add_scene_shell(fixture: Dictionary) -> void:
	var root := fixture["root"] as Node3D
	var camera := Camera3D.new()
	camera.name = "CameraSetupSentinel"
	root.add_child(camera)
	var ui := Control.new()
	ui.name = "UISetupSentinel"
	root.add_child(ui)
	fixture["camera"] = camera
	fixture["ui"] = ui


func _add_late_resource(fixture: Dictionary) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = BoxMesh.new()
	instance.material_override = StandardMaterial3D.new()
	(fixture["late"] as Node).add_child(instance)
	(fixture["keys"] as Array).append("mesh:%d" % instance.mesh.get_instance_id())
	(fixture["keys"] as Array).append("material:%d" % instance.material_override.get_instance_id())


func _after_actor_setup(actor: Racer, fixture: Dictionary) -> void:
	fixture["actor_setups"] = int(fixture["actor_setups"]) + 1
	fixture["all_actor_setup_ready"] = bool(fixture["all_actor_setup_ready"]) \
		and actor.is_inside_tree() and actor.is_node_ready() \
		and actor.controller != null and actor.visual != null
	_add_late_resource(fixture)


func _new_race_probe(mode: String, staged: bool, fixture: Dictionary) -> RaceManager:
	var manager: RaceManager
	if mode == "endless":
		var probe := EndlessProbe.new()
		probe.staged = staged
		probe.after_setup = _after_actor_setup.bind(fixture)
		probe.census = _race_census.bind(fixture)
		manager = probe
	else:
		var probe := RaceProbe.new()
		probe.staged = staged
		probe.after_setup = _after_actor_setup.bind(fixture)
		probe.census = _race_census.bind(fixture)
		manager = probe
	(fixture["root"] as Node).add_child(manager)
	if manager is EndlessManager:
		manager.race_started.disconnect((manager as EndlessManager)._show_storm_hint)
	manager.set_process(false)
	manager.setup(fixture["course"] as CourseBase, fixture["powerups"] as PowerupSystem,
		mode == "time_trial")
	manager.set_physics_process(false)
	fixture["manager"] = manager
	return manager


func _race_census(manager: RaceManager, fixture: Dictionary) -> void:
	fixture["latch_held_at_census"] = not manager._grid_placed
	fixture["router_held_at_census"] = not SceneRouter.is_gameplay_ready(fixture["root"] as Node)
	var actors_ready := int(fixture["actor_setups"]) == manager.racers.size() \
		and bool(fixture["all_actor_setup_ready"]) and manager._spawn_queue.is_empty()
	for index: int in manager.racers.size():
		var actor := manager.racers[index]
		var expected := manager.course.start_grid_transform(index if not manager.single_racer_mode else 0)
		actors_ready = actors_ready and actor.controller != null and actor.visual != null \
			and actor.global_position.is_equal_approx(expected.origin)
	fixture["all_ready_at_census"] = actors_ready
	fixture["shell_ready_at_census"] = is_instance_valid(fixture.get("camera")) \
		and is_instance_valid(fixture.get("ui"))
	_install_census(fixture)


func _install_census(fixture: Dictionary) -> void:
	fixture["census_count"] = int(fixture["census_count"]) + 1
	var probe := CensusProbe.new()
	probe._world = fixture["root"] as Node
	(fixture["root"] as Node).add_child(probe)
	fixture["warmup"] = probe
	var complete := not (fixture["keys"] as Array).is_empty()
	for key: String in fixture["keys"]:
		complete = complete and probe._queue_keys.has(key)
	fixture["collected_all_late_resources"] = complete


func _test_race_boundary(mode: String, staged: bool) -> void:
	var label := mode + ("_staged" if staged else "_deferred")
	var fixture := _fixture()
	var manager := _new_race_probe(mode, staged, fixture)
	var root := fixture["root"] as Node
	_check(label + "_pending_manager_holds_router_without_overlay",
		not SceneRouter.is_gameplay_ready(root) and not manager._grid_placed)
	_check(label + "_no_census_before_actor_setup", int(fixture["census_count"]) == 0)
	# Match production ordering: shell is built after manager.setup returns,
	# while actor setup remains deferred/staged.
	_add_scene_shell(fixture)
	manager._physics_process(120.0)
	_check(label + "_pending_setup_keeps_full_countdown", _race_held(manager))
	await get_tree().process_frame
	await get_tree().process_frame
	if staged:
		_check(label + "_real_actors_entered_but_setup_still_pending",
			manager.racers.all(func(actor: Racer) -> bool: return actor.is_inside_tree()) \
			and int(fixture["actor_setups"]) == 0 and int(fixture["census_count"]) == 0)
		while not manager._spawn_queue.is_empty():
			manager._process(0.0)
			if not manager._grid_placed:
				_check(label + "_partial_batch_cannot_release_or_census",
					int(fixture["census_count"]) == 0 and not SceneRouter.is_gameplay_ready(root))
			await get_tree().physics_frame
			await get_tree().physics_frame
	_check(label + "_real_grid_and_setup_finished", manager._grid_placed \
		and int(fixture["actor_setups"]) == (1 if mode == "time_trial" else 8))
	_check_census(fixture, label)
	_check(label + "_warmup_keeps_router_held_after_grid", not SceneRouter.is_gameplay_ready(root))
	manager._physics_process(120.0)
	_check(label + "_warmup_keeps_countdown_input_physics_frozen", _race_held(manager))
	_release_probe(fixture)
	_check(label + "_direct_ready_only_after_census_node_exits", SceneRouter.is_gameplay_ready(root))
	manager._physics_process(120.0)
	_check(label + "_first_release_discards_delta", manager._presentation_started and _race_held(manager))
	manager._physics_process(0.25)
	_check(label + "_following_tick_consumes_only_its_delta",
		manager._countdown_value == 4 and is_equal_approx(manager._countdown_timer, 0.75))
	manager._process(0.0)
	_check(label + "_no_duplicate_census_on_later_ticks", int(fixture["census_count"]) == 1)
	root.free()


func _race_held(manager: RaceManager) -> bool:
	var human := manager.player.controller as PlayerController
	return not manager.started and manager._countdown_value == 4 \
		and is_equal_approx(manager._countdown_timer, 1.0) \
		and (human == null or not human.input_enabled) \
		and manager.racers.all(func(actor: Racer) -> bool: return not actor.is_physics_processing())


func _check_census(fixture: Dictionary, label: String) -> void:
	_check(label + "_exactly_one_post_setup_census", int(fixture["census_count"]) == 1)
	_check(label + "_readiness_latch_still_held_while_census_starts",
		bool(fixture["latch_held_at_census"]) and bool(fixture["router_held_at_census"]))
	_check(label + "_all_actors_and_grid_ready_at_census", bool(fixture["all_ready_at_census"]))
	_check(label + "_camera_and_ui_precede_census", bool(fixture["shell_ready_at_census"]))
	_check(label + "_real_census_collected_every_late_sentinel_mesh_and_material",
		bool(fixture["collected_all_late_resources"]))


func _release_probe(fixture: Dictionary) -> void:
	var probe := fixture.get("warmup") as CensusProbe
	if is_instance_valid(probe):
		probe.free()
	fixture["warmup"] = null


func _tutorial_prompts(manager: TutorialProbe, fixture: Dictionary) -> void:
	_after_actor_setup(manager.player, fixture)
	_after_actor_setup(manager.buddy, fixture)
	var ui := Control.new()
	ui.name = "TutorialUISetupSentinel"
	(fixture["root"] as Node).add_child(ui)
	fixture["ui"] = ui


func _tutorial_census(manager: TutorialProbe, fixture: Dictionary) -> void:
	fixture["latch_held_at_census"] = not manager._spawn_ready
	fixture["router_held_at_census"] = not SceneRouter.is_gameplay_ready(fixture["root"] as Node)
	fixture["all_ready_at_census"] = int(fixture["actor_setups"]) == 2 \
		and bool(fixture["all_actor_setup_ready"]) and not manager._steps.is_empty() \
		and manager._step_index == -1
	fixture["shell_ready_at_census"] = manager.prompts_ready and manager.fx_ready \
		and manager.camera_rig != null and manager.camera_rig.camera != null \
		and is_instance_valid(fixture.get("ui"))
	_install_census(fixture)


func _test_tutorial_boundary() -> void:
	var fixture := _fixture(true)
	var root := fixture["root"] as Node
	var manager := TutorialProbe.new()
	manager.after_prompts = _tutorial_prompts.bind(fixture)
	manager.census = _tutorial_census.bind(fixture)
	root.add_child(manager)
	manager.set_physics_process(false)
	manager.setup_tutorial(fixture["course"] as CourseTutorial, fixture["powerups"] as PowerupSystem)
	_check("tutorial_pending_spawn_holds_router_without_overlay", not SceneRouter.is_gameplay_ready(root))
	_check("tutorial_no_early_census", int(fixture["census_count"]) == 0)
	manager._physics_process(120.0)
	_check("tutorial_pending_spawn_shows_no_lesson", manager._step_index == -1 and manager.lessons.is_empty())
	await get_tree().process_frame
	await get_tree().process_frame
	_check("tutorial_real_after_spawn_finishes", manager._spawn_ready)
	_check_census(fixture, "tutorial")
	_check("tutorial_live_warmup_keeps_router_held", not SceneRouter.is_gameplay_ready(root))
	manager._physics_process(120.0)
	_check("tutorial_live_warmup_keeps_lesson_input_and_physics_held",
		manager._step_index == -1 and manager.lessons.is_empty() \
		and not (manager.player.controller as PlayerController).input_enabled \
		and not manager.player.is_physics_processing() and not manager.buddy.is_physics_processing())
	_release_probe(fixture)
	_check("tutorial_direct_ready_after_warmup_exits", SceneRouter.is_gameplay_ready(root))
	manager.player.progress = 200.0
	manager._physics_process(120.0)
	_check("tutorial_first_release_shows_only_first_lesson",
		manager._presentation_started and manager.lessons == [0] and manager._step_index == 0)
	manager.player.progress = 0.0
	manager._physics_process(0.016)
	_check("tutorial_no_duplicate_census_or_lesson", int(fixture["census_count"]) == 1 and manager.lessons == [0])
	root.free()


func _test_direct_headless() -> void:
	# No warmup override: exercise the real helper's headless null return.
	var fixture := _fixture()
	var root := fixture["root"] as Node
	var manager := RaceManager.new()
	root.add_child(manager)
	manager.setup(fixture["course"] as CourseBase, fixture["powerups"] as PowerupSystem, true)
	manager.set_physics_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("headless_real_race_helper_creates_no_render_probe", _count_warmups(root) == 0)
	_check("headless_real_race_setup_releases_without_overlay", manager._grid_placed and SceneRouter.is_gameplay_ready(root))
	manager._physics_process(120.0)
	_check("headless_real_race_preserves_first_countdown_delta", manager._presentation_started and _race_held(manager))
	root.free()
	fixture = _fixture(true)
	root = fixture["root"] as Node
	var tutorial := QuietTutorial.new()
	root.add_child(tutorial)
	tutorial.set_physics_process(false)
	tutorial.setup_tutorial(fixture["course"] as CourseTutorial, fixture["powerups"] as PowerupSystem)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("headless_real_tutorial_helper_creates_no_render_probe", _count_warmups(root) == 0)
	_check("headless_real_tutorial_setup_releases_without_overlay", tutorial._spawn_ready and SceneRouter.is_gameplay_ready(root))
	tutorial._physics_process(120.0)
	_check("headless_real_tutorial_shows_initial_lesson", tutorial.lessons == [0])
	root.free()


func _test_canceled_staged_scene() -> void:
	var fixture := _fixture()
	var root := fixture["root"] as Node
	var manager := _new_race_probe("race", true, fixture)
	_add_scene_shell(fixture)
	await get_tree().process_frame
	await get_tree().process_frame
	manager._process(0.0)
	_check("canceled_scene_has_real_partial_actor_setup",
		int(fixture["actor_setups"]) == 2 and int(fixture["census_count"]) == 0 and not manager._grid_placed)
	root.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("canceled_scene_has_no_late_census", not is_instance_valid(root) \
		and int(fixture["census_count"]) == 0 and int(fixture["actor_setups"]) == 2)


func _count_warmups(node: Node) -> int:
	var total := 1 if node is ShaderWarmup else 0
	for child: Node in node.get_children():
		total += _count_warmups(child)
	return total


func _check(label: String, condition: bool) -> void:
	if condition:
		_passed += 1
		print("[race_warmup_boundary] PASS ", label)
	else:
		_failed += 1
		print("[race_warmup_boundary] FAIL ", label)
