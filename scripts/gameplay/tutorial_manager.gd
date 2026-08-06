class_name TutorialManager
extends Node
## Waddle School: spawns the player (plus one friendly practice buddy),
## walks through gameplay lessons with on-screen prompts, and completes the
## tutorial when the finish line is crossed.
##
## Presentation layer: a themed lesson card (number chip, instruction, live
## key-binding hint chips), a chime + sparkle burst at every completed
## station, and a gold confetti graduation moment. Every decorative piece is
## headless-guarded and quality-gated; the lesson state machine and all
## gate/trigger thresholds are untouched (tutorial_sim depends on them).

## One accent per lesson, shared with CourseTutorial._station_list() so each
## card matches the banner arch the player waddles under. Checkpoints has no
## arch; it borrows the glowing-post ice cyan.
const STEP_ACCENTS: Array[Color] = [
	Color(0.36, 0.8, 0.45),   # steering gates
	Color(0.9, 0.45, 0.32),   # penguin hop
	Color(0.42, 0.72, 0.98),  # belly slide
	Color(0.34, 0.83, 0.78),  # know your snow
	Color(0.95, 0.63, 0.27),  # flipper shove
	Color(0.96, 0.77, 0.26),  # power-ups
	Color(0.5, 0.88, 1.0),    # checkpoints
	Color(0.72, 0.52, 0.95),  # home slide
]

var course: CourseTutorial = null
var powerups: PowerupSystem = null
var player: Racer = null
var buddy: Racer = null
var camera_rig: ChaseCamera = null

var _steps: Array[Dictionary] = []
var _step_index: int = -1
var _prompt_layer: CanvasLayer
var _prompt_panel: PanelContainer
var _prompt_style: StyleBoxFlat
var _chip_style: StyleBoxFlat
var _chip_label: Label
var _prompt_label: Label
var _detail_label: Label
var _hint_row: HBoxContainer
var _prompt_tween: Tween = null
var _station_burst: CPUParticles3D = null
var _finale_burst: CPUParticles3D = null
var _step_satisfied: bool = false
var _shoves_landed: int = 0
var _finished: bool = false


func setup_tutorial(p_course: CourseTutorial, p_powerups: PowerupSystem) -> void:
	course = p_course
	powerups = p_powerups
	powerups.course = course
	course.racer_crossed_finish.connect(_on_finish)

	player = Racer.new()
	var controller: RacerController
	if RaceManager.autopilot_player:
		controller = AIController.new()
	else:
		controller = PlayerController.new()
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
	# Autopilot uses the frozen demo profile, not a race difficulty: the race
	# profiles are tuned for competition and their pace overshoots the lesson
	# obstacles, stalling the unattended run.
	if RaceManager.autopilot_player and player.controller is AIController:
		(player.controller as AIController).configure(
			player, course, PersonalitiesDB.get_item("gus"), DifficultyDB.get_item("tutorial_demo"), 99)
	var shove_offset: float = course.main_guide.nearest(Vector3(0, 13, -450), -1)["offset"]
	var buddy_xform := course.main_guide.transform_at(shove_offset)
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
	_build_celebration_fx()
	_define_steps()
	AudioManager.play_music("music_title")
	_advance_step()


## Lesson card (top center): accent-tinted themed panel holding the lesson
## number chip, the title, the instruction, and a row of input hint chips.
func _build_prompts() -> void:
	_prompt_layer = CanvasLayer.new()
	add_child(_prompt_layer)
	_prompt_panel = PanelContainer.new()
	_prompt_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_prompt_panel.anchor_left = 0.5
	_prompt_panel.anchor_right = 0.5
	_prompt_panel.offset_left = -420
	_prompt_panel.offset_right = 420
	_prompt_panel.offset_top = 26
	_prompt_style = UITheme.make_panel_style(Color(0.055, 0.106, 0.196, 0.88))
	_prompt_style.set_corner_radius_all(16)
	_prompt_style.set_border_width_all(2)
	_prompt_style.border_color = Color(UITheme.COLOR_ACCENT, 0.55)
	_prompt_style.content_margin_left = 26.0
	_prompt_style.content_margin_right = 26.0
	_prompt_style.content_margin_top = 12.0
	_prompt_style.content_margin_bottom = 14.0
	_prompt_panel.add_theme_stylebox_override("panel", _prompt_style)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_prompt_panel.add_child(vbox)

	# Lesson number chip: small accent pill above the title.
	var chip_row := HBoxContainer.new()
	chip_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(chip_row)
	var chip_panel := PanelContainer.new()
	_chip_style = StyleBoxFlat.new()
	_chip_style.bg_color = Color(UITheme.COLOR_ACCENT, 0.16)
	_chip_style.set_corner_radius_all(9)
	_chip_style.set_border_width_all(1)
	_chip_style.border_color = Color(UITheme.COLOR_ACCENT, 0.7)
	_chip_style.content_margin_left = 12.0
	_chip_style.content_margin_right = 12.0
	_chip_style.content_margin_top = 2.0
	_chip_style.content_margin_bottom = 2.0
	chip_panel.add_theme_stylebox_override("panel", _chip_style)
	_chip_label = Label.new()
	_chip_label.add_theme_font_override("font", UITheme.bold_font())
	_chip_label.add_theme_font_size_override("font_size", 15)
	_chip_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	chip_panel.add_child(_chip_label)
	chip_row.add_child(chip_panel)

	_prompt_label = Label.new()
	_prompt_label.add_theme_font_override("font", UITheme.bold_font())
	_prompt_label.add_theme_font_size_override("font_size", 32)
	_prompt_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	_prompt_label.add_theme_constant_override("outline_size", 6)
	_prompt_label.add_theme_color_override("font_outline_color", UITheme.COLOR_BG_DEEP)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_prompt_label)

	_detail_label = Label.new()
	_detail_label.add_theme_font_size_override("font_size", 20)
	_detail_label.add_theme_color_override("font_color", Color(0.68, 0.82, 0.95))
	_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_detail_label)

	_hint_row = HBoxContainer.new()
	_hint_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_hint_row.add_theme_constant_override("separation", 6)
	vbox.add_child(_hint_row)
	_prompt_layer.add_child(_prompt_panel)


## Small keyboard-keycap chip matching RaceHUD's onboarding-strip style
## (light face, heavier bottom border). Touch devices reuse it for gestures.
func _make_keycap(text: String) -> PanelContainer:
	var cap := PanelContainer.new()
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.9, 0.95, 1.0)
	style.set_corner_radius_all(5)
	style.set_border_width_all(1)
	style.border_width_bottom = 3
	style.border_color = Color(0.45, 0.6, 0.78)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 1.0
	style.content_margin_bottom = 2.0
	cap.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(0.07, 0.14, 0.27))
	cap.add_child(label)
	return cap


## Two persistent one-shot sparkle bursts (small per-station, large finale)
## sharing ONE unshaded billboard material and ONE quad mesh — no per-event
## node or material churn (WebGL2 jank guard). Amounts scale with the
## particle_quality setting and shrink further under reduced motion.
func _build_celebration_fx() -> void:
	if GameConfig.is_headless():
		return
	var quality := String(SettingsManager.get_setting("display", "particle_quality"))
	var density := 1.0
	if quality == "medium":
		density = 0.75
	elif quality == "low":
		density = 0.5
	if UITheme.reduced_motion():
		density *= 0.6
	var material := StandardMaterial3D.new()
	material.albedo_texture = VisualLibrary.soft_radial_texture(32, 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	var quad := QuadMesh.new()
	quad.size = Vector2(0.24, 0.24)
	_station_burst = _make_burst(int(22.0 * density), 0.9, 4.5, 8.5, quad, material)
	_finale_burst = _make_burst(int(64.0 * density), 1.5, 6.0, 11.0, quad, material)


func _make_burst(amount: int, lifetime: float, vel_min: float, vel_max: float,
		mesh: Mesh, material: Material) -> CPUParticles3D:
	var burst := CPUParticles3D.new()
	burst.emitting = false
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = maxi(amount, 8)
	burst.lifetime = lifetime
	burst.mesh = mesh
	burst.material_override = material
	burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	burst.emission_sphere_radius = 0.4
	burst.direction = Vector3.UP
	burst.spread = 75.0
	burst.gravity = Vector3(0.0, -7.0, 0.0)
	burst.initial_velocity_min = vel_min
	burst.initial_velocity_max = vel_max
	burst.scale_amount_min = 0.6
	burst.scale_amount_max = 1.4
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	burst.color_ramp = ramp
	get_parent().add_child(burst)
	return burst


## Each step: title, detail, satisfied-by tag or progress threshold, plus
## presentation-only hint chips (hint_actions -> live desktop key bindings,
## hint_touch -> gesture text, hint_verb -> what the input does). Thresholds
## and tags are gameplay-critical — tutorial_sim depends on them exactly.
func _define_steps() -> void:
	_steps = [
		{"title": "Welcome to Waddle School!", "detail": "You waddle forward automatically — weave through the green gates! (Gamepad: steer with the left stick.)", "until_progress": 170.0,
			"hint_actions": ["steer_left", "steer_right"], "hint_touch": ["Drag ↔"], "hint_verb": "Steer"},
		{"title": "Penguin Hop", "detail": "Hop over the red bars ahead. You can buffer a jump slightly early — the penguin forgives you.", "until_progress": 250.0,
			"hint_actions": ["jump"], "hint_touch": ["Swipe ↑"], "hint_verb": "Jump"},
		{"title": "Belly Slide", "detail": "Slide under the low ice bars ahead — and remember: sliding downhill is FAST.", "until_progress": 330.0,
			"hint_actions": ["slide"], "hint_touch": ["Hold ↓"], "hint_verb": "Hold to Slide"},
		{"title": "Know Your Snow", "detail": "Smooth ice is slick and fast — deep snow is a slog. Slide the ice, waddle the powder.", "until_progress": 470.0},
		{"title": "Flipper Shove", "detail": "Coach Wobbles volunteered for this. Get close and give a friendly shove!", "tag": "shove",
			"hint_actions": ["shove"], "hint_touch": ["SHOVE"], "hint_verb": "Shove"},
		{"title": "Power-Ups", "detail": "Grab a glowing box, then use the item. Every item helps differently!", "tag": "item",
			"hint_actions": ["use_item"], "hint_touch": ["ITEM"], "hint_verb": "Use Item"},
		{"title": "Checkpoints", "detail": "Glowing posts mark checkpoints. Fall off or wipe out and you'll return to the last one — no big deal.", "tag": "checkpoint_auto"},
		{"title": "The Home Slide", "detail": "One last downhill. Hold that slide and cross the finish line, champ!", "tag": "finish",
			"hint_actions": ["slide"], "hint_touch": ["Hold ↓"], "hint_verb": "Hold to Slide"},
	]


func _advance_step() -> void:
	if _step_index >= 0 and _step_index < _steps.size():
		_celebrate_station(STEP_ACCENTS[_step_index])
	_step_index += 1
	_step_satisfied = false
	if _step_index >= _steps.size():
		return
	_apply_step_card(_steps[_step_index])
	AudioManager.play_sfx("sfx_checkpoint", 1.2, -10.0)


## Fills the lesson card (chip, title, instruction, hint chips), tints it
## toward the station's accent color, and pops it in.
func _apply_step_card(step: Dictionary) -> void:
	var accent := STEP_ACCENTS[mini(_step_index, STEP_ACCENTS.size() - 1)]
	_chip_label.text = "LESSON %d OF %d" % [_step_index + 1, _steps.size()]
	_chip_style.bg_color = Color(accent, 0.18)
	_chip_style.border_color = Color(accent, 0.8)
	_prompt_style.border_color = Color(accent, 0.6)
	_prompt_label.text = String(step["title"])
	_detail_label.text = String(step["detail"])
	_set_hint(step)
	_animate_prompt_in()


## Rebuilds the input hint row: keycap chips with the player's live key
## bindings (or touch gestures), the verb, and — when a matching gamepad
## button is bound — a dim "Pad:" suffix. Hidden for observation lessons.
func _set_hint(step: Dictionary) -> void:
	for child: Node in _hint_row.get_children():
		# Hide before queue_free: freed nodes linger until end of frame and
		# would briefly double up beside the incoming chips.
		(child as CanvasItem).visible = false
		child.queue_free()
	var actions: Array = step.get("hint_actions", [])
	if actions.is_empty():
		_hint_row.visible = false
		return
	_hint_row.visible = true
	if UITheme.is_touch():
		for gesture: String in step.get("hint_touch", []):
			_hint_row.add_child(_make_keycap(gesture))
	else:
		for action: String in actions:
			var key := SettingsManager.describe_action_binding(action, "key")
			_hint_row.add_child(_make_keycap(key if key != "—" else "?"))
	var verb_label := Label.new()
	verb_label.text = String(step.get("hint_verb", ""))
	verb_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	verb_label.add_theme_font_size_override("font_size", 16)
	verb_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_hint_row.add_child(verb_label)
	if not UITheme.is_touch():
		var joy := SettingsManager.describe_action_binding(String(actions[0]), "joy")
		if joy != "—" and not joy.begins_with("Axis"):
			var joy_label := Label.new()
			joy_label.text = "·  Pad: %s" % joy
			joy_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			joy_label.add_theme_font_size_override("font_size", 15)
			joy_label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
			_hint_row.add_child(joy_label)


## Quick fade + settle-scale entrance for the lesson card. Event-driven
## tween only; skipped headless and under reduced motion.
func _animate_prompt_in() -> void:
	if GameConfig.is_headless() or UITheme.reduced_motion():
		return
	if _prompt_tween != null and _prompt_tween.is_valid():
		_prompt_tween.kill()
	_prompt_panel.pivot_offset = Vector2(_prompt_panel.size.x * 0.5, 0.0)
	_prompt_panel.modulate.a = 0.0
	_prompt_panel.scale = Vector2(0.94, 0.94)
	_prompt_tween = create_tween().set_parallel(true)
	_prompt_tween.tween_property(_prompt_panel, "modulate:a", 1.0, 0.18)
	_prompt_tween.tween_property(_prompt_panel, "scale", Vector2.ONE, 0.26) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Success feedback when a lesson completes: bright chime plus a short
## sparkle burst in the station's accent color at the player's position.
func _celebrate_station(accent: Color) -> void:
	AudioManager.play_sfx("sfx_unlock", 1.1, -5.0)
	if _station_burst == null or player == null or not is_instance_valid(player):
		return
	_station_burst.global_position = player.global_position + Vector3.UP * 1.6
	_station_burst.color = accent
	_station_burst.restart()


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
	_show_completion()
	var timer := get_tree().create_timer(2.6)
	timer.timeout.connect(func() -> void:
		Game.finish_tutorial())


## Graduation moment: the card restyles gold, the hint row clears, and a big
## gold confetti burst (echoed by a smaller ice one) fires over the finish
## line. The completion achievement fires downstream in Game.finish_tutorial()
## — nothing here re-fires it.
func _show_completion() -> void:
	_chip_label.text = "COMPLETE"
	_chip_style.bg_color = Color(UITheme.COLOR_GOLD, 0.2)
	_chip_style.border_color = Color(UITheme.COLOR_GOLD, 0.9)
	_prompt_style.border_color = Color(UITheme.COLOR_GOLD, 0.85)
	_prompt_label.text = "Waddle School Complete!"
	_prompt_label.add_theme_color_override("font_color", UITheme.COLOR_GOLD)
	_detail_label.text = "You're ready for the big leagues."
	_hint_row.visible = false
	_animate_prompt_in()
	if _finale_burst == null or player == null or not is_instance_valid(player):
		return
	_finale_burst.global_position = player.global_position + Vector3.UP * 2.0
	_finale_burst.color = UITheme.COLOR_GOLD
	_finale_burst.restart()
	var echo := get_tree().create_timer(0.35)
	echo.timeout.connect(func() -> void:
		if _station_burst == null or not is_instance_valid(_station_burst) \
				or player == null or not is_instance_valid(player):
			return
		_station_burst.global_position = player.global_position + Vector3.UP * 1.8
		_station_burst.color = Color(0.5, 0.88, 1.0)
		_station_burst.restart())
