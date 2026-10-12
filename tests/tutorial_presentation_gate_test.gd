extends Node
## Real tutorial setup/start methods, minimal course and non-rendering lesson UI.
## No finish signal or progression write; the main suite supplies isolated user://.

class CourseProbe:
	extends CourseTutorial

	func _ready() -> void:
		pass


class WarmupProbe:
	extends ShaderWarmup

	func _ready() -> void:
		set_process(false)


class TutorialProbe:
	extends TutorialManager

	var shown_lessons: Array[int] = []
	var celebrations: int = 0

	func _build_prompts() -> void:
		pass

	func _build_celebration_fx() -> void:
		pass

	func _apply_step_card(_step: Dictionary) -> void:
		shown_lessons.append(_step_index)

	func _celebrate_station(_accent: Color) -> void:
		celebrations += 1


var _checks: int = 0
var _failed: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var lighting := CourseTutorial.environment_profile()
	_check(float(lighting["ambient_energy"]) <= 0.45,
		"school snow retains shaded contrast without post-processing")
	_check(float(lighting["sun_energy"]) <= 0.95 \
		and float(lighting["shaft_strength"]) <= 0.18,
		"school direct light and shafts leave white-surface headroom")
	var old_busy: bool = SceneRouter._busy
	var old_presenting: bool = SceneRouter._presenting
	var old_autopilot: bool = RaceManager.autopilot_player
	RaceManager.autopilot_player = false
	SceneRouter._busy = true
	SceneRouter._presenting = true
	var fixture := Node3D.new()
	add_child(fixture)
	var course := CourseProbe.new()
	var curve := Curve3D.new()
	curve.add_point(Vector3(0.0, 20.0, 30.0))
	curve.add_point(Vector3(0.0, 13.0, -700.0))
	course.main_guide = PathGuide.new(curve)
	course.build_finished = true
	fixture.add_child(course)
	var powerups := PowerupSystem.new()
	fixture.add_child(powerups)
	var manager := TutorialProbe.new()
	fixture.add_child(manager)
	# Invoke the real manager method explicitly, so each tested boundary has
	# an exact delta. Racers keep normal processing to catch leaked movement.
	manager.set_physics_process(false)
	manager.setup_tutorial(course, powerups)
	_check(not manager.player.is_physics_processing(), "player frozen before deferred setup")
	_check(not manager.buddy.is_physics_processing(), "buddy frozen before deferred setup")
	_check(not _flag(manager, &"_spawn_ready"), "spawn readiness initially false")
	manager._physics_process(120.0)
	_check(manager._step_index == -1 and manager.shown_lessons.is_empty(),
		"first lesson waits for deferred spawn")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(_flag(manager, &"_spawn_ready"), "real after-spawn marks all setup complete")
	_check(manager.player.controller is PlayerController, "human controller installed")
	var controller := manager.player.controller as PlayerController
	_check(not controller.input_enabled, "human input disabled during loader")
	_check(not manager.player.is_physics_processing() and not manager.buddy.is_physics_processing(),
		"deferred setup does not release either racer")
	_check(manager._step_index == -1 and manager.shown_lessons.is_empty(),
		"after-spawn prepares lessons without showing the first one")
	manager.player._boost_timer = 5.0
	# Invulnerability, unlike the state-specific stun timer, decrements on
	# every active Racer physics tick; no synthetic state change is needed.
	manager.buddy._invuln_timer = 3.0
	var player_start := manager.player.global_transform
	var buddy_start := manager.buddy.global_transform
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(manager.player.global_transform == player_start
		and manager.buddy.global_transform == buddy_start, "actual physics frames cannot move racers under loader")
	_check(manager.player._boost_timer == 5.0 and manager.buddy._invuln_timer == 3.0,
		"actual physics frames cannot consume racer timers under loader")
	manager._physics_process(120.0)
	_check_pending(manager, controller, "router busy and presenting")
	SceneRouter._busy = false
	manager._physics_process(120.0)
	_check_pending(manager, controller, "fade remains presenting after scene swap")
	SceneRouter._presenting = false
	SceneRouter._busy = true
	manager._physics_process(120.0)
	_check_pending(manager, controller, "busy without presentation")
	SceneRouter._busy = false
	course.build_finished = false
	manager._physics_process(120.0)
	_check_pending(manager, controller, "local course build on direct entry")
	course.build_finished = true
	var nested := Node.new()
	fixture.add_child(nested)
	var warmup := WarmupProbe.new()
	nested.add_child(warmup)
	manager._physics_process(120.0)
	_check_pending(manager, controller, "nested shader warmup on direct entry")
	warmup.free()
	# The unchanged manager has no latch: report that missing contract as a
	# failure, not a fixture exception or an invalid property assignment.
	if manager.get("_spawn_ready") is bool:
		manager.set("_spawn_ready", false)
		manager._physics_process(120.0)
		_check_pending(manager, controller, "spawn incomplete with router and course ready")
		manager.set("_spawn_ready", true)
	else:
		_check(false, "spawn-incomplete gate requires a boolean spawn-ready latch")
	controller.jump_pressed = true
	controller.shove_pressed = true
	controller.item_pressed = true
	controller.touch_jump()
	controller.touch_shove()
	controller.touch_item()
	controller.touch_item_back()
	controller.touch_steer = 0.75
	controller.touch_slide_changed(true)
	controller._touch_aim_back = true
	# Already beyond the first checkpoint: the release call must show lesson
	# one only, not run the normal progression loop with its stale load delta.
	manager.player.progress = 200.0
	manager._physics_process(120.0)
	_check(_flag(manager, &"_presentation_started"), "ready direct entry starts without a headless exemption")
	_check(manager.player.is_physics_processing() and manager.buddy.is_physics_processing(),
		"ready gate releases player and buddy together")
	_check(controller.input_enabled, "ready gate releases human input")
	_check(manager.shown_lessons == [0] and manager._step_index == 0,
		"release shows exactly the first lesson and discards the eligible delta")
	_check(manager.celebrations == 0, "release does not celebrate a phantom prior lesson")
	_check(not controller.jump_pressed and not controller.shove_pressed and not controller.item_pressed,
		"release clears controller one-shot edges")
	_check(not controller._touch_jump and not controller._touch_shove
		and not controller._touch_item and not controller._touch_item_back,
		"release clears touch one-shot edges")
	_check(controller.touch_steer == 0.75 and controller._touch_slide and controller._touch_aim_back,
		"release preserves deliberate held touch input")
	_check(manager.player.global_transform == player_start and manager.buddy.global_transform == buddy_start
		and manager.player._boost_timer == 5.0 and manager.buddy._invuln_timer == 3.0,
		"release never applies the accumulated load delta to racers")
	manager.player.progress = 0.0
	controller.touch_jump()
	manager._physics_process(0.016)
	_check(manager.shown_lessons == [0] and controller._touch_jump,
		"later tick neither restarts lesson nor clears a fresh input edge")
	manager.player.progress = 200.0
	manager._physics_process(0.016)
	_check(manager.shown_lessons == [0, 1] and manager.celebrations == 1,
		"normal lesson progression resumes on following ticks")
	fixture.free()
	SceneRouter._busy = old_busy
	SceneRouter._presenting = old_presenting
	RaceManager.autopilot_player = old_autopilot
	# Assertions above exercise the real music and lesson chimes. Stop their
	# autoload-owned playback only during teardown, then give the audio mixer
	# a handoff before quitting; otherwise live playbacks outlast engine exit.
	for child: Node in AudioManager.get_children():
		if child is AudioStreamPlayer:
			(child as AudioStreamPlayer).stop()
		elif child is AudioStreamPlayer3D:
			(child as AudioStreamPlayer3D).stop()
	await get_tree().process_frame
	await get_tree().create_timer(0.05, true, false, true).timeout
	await get_tree().process_frame
	print("[tutorial_presentation_gate] %d checks, %d failures" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check_pending(manager: TutorialProbe, controller: PlayerController, context: String) -> void:
	_check(not _flag(manager, &"_presentation_started") and manager._step_index == -1
		and manager.shown_lessons.is_empty(), context + ": lesson remains pending")
	_check(not manager.player.is_physics_processing() and not manager.buddy.is_physics_processing()
		and not controller.input_enabled, context + ": physics and input remain frozen")
	_check(manager.player._boost_timer == 5.0 and manager.buddy._invuln_timer == 3.0,
		context + ": no racer timer consumed")


func _flag(manager: TutorialProbe, property: StringName) -> bool:
	var value: Variant = manager.get(property)
	return value is bool and value == true


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failed += 1
		push_error("[tutorial_presentation_gate] FAIL " + message)
