class_name TutorialManager
extends Node
## Waddle School: spawns the player (plus one friendly practice buddy),
## walks through gameplay lessons with on-screen prompts, and completes the
## tutorial when the finish line is crossed.

var course: CourseTutorial = null
var powerups: PowerupSystem = null
var player: Racer = null
var buddy: Racer = null
var camera_rig: ChaseCamera = null

var _steps: Array[Dictionary] = []
var _step_index: int = -1
var _prompt_layer: CanvasLayer
var _prompt_label: Label
var _detail_label: Label
var _step_satisfied: bool = false
var _shoves_landed: int = 0
var _finished: bool = false


func setup_tutorial(p_course: CourseTutorial, p_powerups: PowerupSystem) -> void:
	course = p_course
	powerups = p_powerups
	powerups.course = course
	course.racer_crossed_finish.connect(_on_finish)

	player = Racer.new()
	var controller := PlayerController.new()
	get_parent().add_child.call_deferred(player)
	var equipped := Progression.equipped()
	var body_info := CosmeticsDB.get_item(String(equipped.get("body", "body_classic")))
	player.setup.call_deferred("player", "You", true, {
		"body_color": body_info.get("body_color", Color(0.13, 0.16, 0.22)),
		"belly_color": body_info.get("belly_color", Color(0.95, 0.94, 0.9)),
		"hat": equipped.get("hat", ""),
	}, controller, course)
	player.item_used.connect(func(racer: Racer, item_id: String) -> void:
		powerups.activate(racer, item_id)
		_satisfy("item"))
	player.shove_landed.connect(func(_attacker: Racer, _victim: Racer) -> void:
		_shoves_landed += 1
		_satisfy("shove"))
	player.checkpoint_reached.connect(func(_racer: Racer, _index: int) -> void:
		_satisfy("checkpoint"))
	player.state_changed.connect(_on_player_state)

	# Practice buddy: a patient AI penguin that waddles slowly near the shove
	# zone so the player has someone to (gently) practice on.
	buddy = Racer.new()
	var buddy_controller := RacerController.new()
	get_parent().add_child.call_deferred(buddy)
	buddy.setup.call_deferred("buddy", "Coach Wobbles", false, {
		"body_color": Color(0.35, 0.3, 0.2),
		"belly_color": Color(0.97, 0.94, 0.85),
	}, buddy_controller, course)

	call_deferred("_after_spawn")


func _after_spawn() -> void:
	var xform := course.start_grid_transform(0)
	player.global_transform = xform
	player.last_checkpoint_transform = xform
	var shove_offset := course.main_guide.nearest(Vector3(0, 13, -450), -1)["offset"]
	var buddy_xform := course.main_guide.transform_at(float(shove_offset))
	buddy.global_transform = Transform3D(buddy_xform.basis, buddy_xform.origin + Vector3.UP * 0.5)
	buddy.last_checkpoint_transform = buddy.global_transform
	buddy.speed_scale = 0.0  # stands still until bumped; recovers in place

	camera_rig = ChaseCamera.new()
	get_parent().add_child(camera_rig)
	camera_rig.attach_to(player)
	if not GameConfig.is_headless():
		camera_rig.camera.make_current()

	get_parent().add_child(PauseMenu.new())
	if SettingsManager.touch_controls_enabled():
		var touch := TouchControls.new()
		get_parent().add_child(touch)
		touch.setup(player.controller as PlayerController)

	_build_prompts()
	_define_steps()
	AudioManager.play_music("music_title")
	_advance_step()


func _build_prompts() -> void:
	_prompt_layer = CanvasLayer.new()
	add_child(_prompt_layer)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.offset_left = -420
	panel.offset_right = 420
	panel.offset_top = 30
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.12, 0.22, 0.85)
	style.set_corner_radius_all(14)
	style.set_border_width_all(2)
	style.border_color = Color(0.45, 0.75, 1.0)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	var vbox := VBoxContainer.new()
	panel.add_child(vbox)
	_prompt_label = Label.new()
	_prompt_label.add_theme_font_size_override("font_size", 32)
	_prompt_label.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_prompt_label)
	_detail_label = Label.new()
	_detail_label.add_theme_font_size_override("font_size", 21)
	_detail_label.add_theme_color_override("font_color", Color(0.65, 0.8, 0.95))
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_detail_label)
	_prompt_layer.add_child(panel)


func _key_hint(action: String) -> String:
	return SettingsManager.describe_action_binding(action, "key")


func _define_steps() -> void:
	# Each step: title, detail, satisfied-by tag or progress threshold.
	_steps = [
		{"title": "Welcome to Waddle School!", "detail": "You waddle forward automatically. Steer with %s / %s (or left stick). Weave through the green gates!" % [_key_hint("steer_left"), _key_hint("steer_right")], "until_progress": 170.0},
		{"title": "Penguin Hop", "detail": "Press %s (or the south button) to hop over the red bars ahead. You can buffer a jump slightly early — the penguin forgives you." % _key_hint("jump"), "until_progress": 250.0},
		{"title": "Belly Slide", "detail": "Hold %s to belly slide! Slide under the low ice bars ahead — and remember: sliding downhill is FAST." % _key_hint("slide"), "until_progress": 330.0},
		{"title": "Know Your Snow", "detail": "Smooth ice is slick and fast — deep snow is a slog. Slide the ice, waddle the powder.", "until_progress": 470.0},
		{"title": "Flipper Shove", "detail": "Coach Wobbles volunteered for this. Get close and press %s to give a friendly shove!" % _key_hint("shove"), "tag": "shove"},
		{"title": "Power-Ups", "detail": "Grab a glowing box, then press %s to use the item. Every item helps differently!" % _key_hint("use_item"), "tag": "item"},
		{"title": "Checkpoints", "detail": "Glowing posts mark checkpoints. Fall off or wipe out and you'll return to the last one — no big deal.", "tag": "checkpoint_auto"},
		{"title": "The Home Slide", "detail": "One last downhill. Hold that slide and cross the finish line, champ!", "tag": "finish"},
	]


func _advance_step() -> void:
	_step_index += 1
	_step_satisfied = false
	if _step_index >= _steps.size():
		return
	var step := _steps[_step_index]
	_prompt_label.text = String(step["title"])
	_detail_label.text = String(step["detail"])
	AudioManager.play_sfx("sfx_checkpoint", 1.2, -6.0)


func _satisfy(tag: String) -> void:
	if _step_index < 0 or _step_index >= _steps.size():
		return
	var step := _steps[_step_index]
	var want := String(step.get("tag", ""))
	if want == tag or (want == "checkpoint_auto" and tag == "checkpoint"):
		_advance_step()


func _on_player_state(_new_state: Racer.State) -> void:
	pass


func _physics_process(_delta: float) -> void:
	if _finished or _step_index < 0 or _step_index >= _steps.size() or player == null or not is_instance_valid(player):
		return
	var step := _steps[_step_index]
	if step.has("until_progress") and player.progress >= float(step["until_progress"]):
		_advance_step()
	# The checkpoint lesson auto-advances shortly after display too, in case
	# the player already passed every remaining checkpoint.
	if String(step.get("tag", "")) == "checkpoint_auto" and player.progress > course.main_guide.length * 0.82:
		_advance_step()
	# Keep Coach Wobbles facing the player and cheerful.
	if buddy != null and is_instance_valid(buddy) and buddy.visual != null:
		buddy.visual.set_pose(PenguinVisual.Pose.IDLE)


func _on_finish(racer: Racer) -> void:
	if _finished or not racer.is_player:
		return
	_finished = true
	AudioManager.play_sfx("sfx_victory")
	_prompt_label.text = "Waddle School Complete!"
	_detail_label.text = "You're ready for the big leagues."
	var timer := get_tree().create_timer(2.0)
	timer.timeout.connect(func() -> void:
		Game.finish_tutorial())
