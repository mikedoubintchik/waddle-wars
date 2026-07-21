extends Control
## Post-race results: standings, rewards, Grand Prix standings between
## rounds, cup ceremony after the final round, records for TT / Endless.

var _buttons: Array[Button] = []


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.13, 0.24)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	center.add_child(vbox)

	match Game.mode:
		Game.Mode.ENDLESS:
			_build_endless(vbox)
		Game.Mode.TIME_TRIAL:
			_build_time_trial(vbox)
		Game.Mode.TUTORIAL:
			_build_tutorial(vbox)
		Game.Mode.GRAND_PRIX:
			_build_race_results(vbox)
			_build_gp_standings(vbox)
		_:
			_build_race_results(vbox)

	_build_rewards(vbox)
	_build_buttons(vbox)
	AudioManager.play_music("music_title")
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


func _title(parent: Control, text: String, size: int = 56, color: Color = Color(0.95, 0.97, 1.0)) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)


func _build_race_results(parent: Control) -> void:
	var player_row: Dictionary = {}
	for row: Dictionary in Game.last_race_results:
		if bool(row.get("is_player", false)):
			player_row = row
	var pos := int(player_row.get("position", 8))
	var headline := "Race Complete!"
	if pos == 1:
		headline = "VICTORY!"
	elif pos <= 3:
		headline = "Podium Finish!"
	_title(parent, headline, 64, Color(1.0, 0.85, 0.25) if pos <= 3 else Color(0.95, 0.97, 1.0))
	_title(parent, CoursesDB.display_name(Game.course_id), 28, Color(0.7, 0.82, 0.95))

	var panel := _make_panel(parent)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 6)
	panel.add_child(grid)
	for header: String in ["", "Racer", "Time", "Fish"]:
		var head_label := Label.new()
		head_label.text = header
		head_label.add_theme_font_size_override("font_size", 20)
		head_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))
		grid.add_child(head_label)
	for row: Dictionary in Game.last_race_results:
		var is_player := bool(row.get("is_player", false))
		var color := Color(1.0, 0.9, 0.4) if is_player else Color(0.9, 0.94, 1.0)
		var cells := [
			"%d." % int(row.get("position", 0)),
			String(row.get("name", "?")),
			"DNF" if bool(row.get("dnf", false)) else RaceHUD.format_time(float(row.get("time", 0.0))),
			str(int(row.get("fish", 0))),
		]
		for cell: String in cells:
			var cell_label := Label.new()
			cell_label.text = cell
			cell_label.add_theme_font_size_override("font_size", 24)
			cell_label.add_theme_color_override("font_color", color)
			grid.add_child(cell_label)


func _build_gp_standings(parent: Control) -> void:
	_title(parent, "Grand Prix Standings — Round %d of %d" % [Game.gp_round + 1, CoursesDB.GRAND_PRIX_ORDER.size()], 30, Color(0.7, 0.85, 1.0))
	var panel := _make_panel(parent)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 40)
	panel.add_child(grid)
	var standings := Game.gp_standings()
	for i: int in standings.size():
		var row: Dictionary = standings[i]
		var is_player := String(row.get("key", "")) == "player"
		var color := Color(1.0, 0.9, 0.4) if is_player else Color(0.9, 0.94, 1.0)
		for cell: String in ["%d." % (i + 1), String(row["name"]), "%d pts" % int(row["points"])]:
			var label := Label.new()
			label.text = cell
			label.add_theme_font_size_override("font_size", 24)
			label.add_theme_color_override("font_color", color)
			grid.add_child(label)
	if Game.is_final_gp_round():
		var standings_sorted := standings
		if not standings_sorted.is_empty():
			var winner := String(standings_sorted[0]["name"])
			_title(parent, "Cup Winner: %s!" % winner, 40, Color(1.0, 0.85, 0.25))
			_build_podium(parent, standings_sorted)
			var player_place := 1
			for i: int in standings_sorted.size():
				if String(standings_sorted[i].get("key", "")) == "player":
					player_place = i + 1
			Game.gp_round = CoursesDB.GRAND_PRIX_ORDER.size()  # mark complete
			Progression.submit_gp_result(Game.difficulty_id, player_place, int(standings_sorted[player_place - 1]["points"]) if player_place <= standings_sorted.size() else 0)
			AudioManager.play_sfx("sfx_victory")


## Cup ceremony: 3D podium with the top three penguins, winner celebrating.
func _build_podium(parent: Control, standings: Array[Dictionary]) -> void:
	if GameConfig.is_headless():
		return
	var viewport_container := SubViewportContainer.new()
	viewport_container.custom_minimum_size = Vector2(560, 260)
	viewport_container.stretch = true
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport_container.add_child(viewport)
	parent.add_child(viewport_container)

	var world := Node3D.new()
	viewport.add_child(world)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.6, 4.6)
	camera.rotation_degrees = Vector3(-8, 0, 0)
	camera.fov = 45.0
	world.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 1.4
	world.add_child(light)

	var heights := [1.0, 0.65, 0.4]
	var slots := [Vector3(0, 0, 0), Vector3(-1.5, 0, 0.3), Vector3(1.5, 0, 0.3)]
	var podium_colors := [Color(1.0, 0.85, 0.25), Color(0.8, 0.85, 0.9), Color(0.8, 0.6, 0.4)]
	var penguins: Array[PenguinVisual] = []
	for i: int in mini(3, standings.size()):
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.2, float(heights[i]), 1.2)
		box.mesh = mesh
		box.material_override = PenguinVisual.get_material(podium_colors[i], 0.3, 0.4)
		box.position = slots[i] + Vector3(0, float(heights[i]) * 0.5, 0)
		world.add_child(box)
		var key := String(standings[i].get("key", ""))
		var penguin := PenguinVisual.new()
		if key == "player":
			var body := CosmeticsDB.get_item(Progression.get_equipped("body"))
			penguin.setup({
				"body_color": body.get("body_color", Color(0.13, 0.16, 0.22)),
				"belly_color": body.get("belly_color", Color(0.95, 0.94, 0.9)),
				"hat": Progression.get_equipped("hat"),
			})
		else:
			var info := PersonalitiesDB.get_item(key)
			penguin.setup({
				"body_color": info.get("body_color", Color(0.13, 0.16, 0.22)),
				"belly_color": info.get("belly_color", Color(0.95, 0.94, 0.9)),
			})
		penguin.position = slots[i] + Vector3(0, float(heights[i]), 0)
		penguin.rotation.y = PI  # penguin forward is -Z; camera sits at +Z
		penguin.set_pose(PenguinVisual.Pose.CELEBRATE if i == 0 else PenguinVisual.Pose.IDLE)
		world.add_child(penguin)
		penguins.append(penguin)
	var ticker := Timer.new()
	ticker.wait_time = 1.0 / 30.0
	ticker.autostart = true
	ticker.timeout.connect(func() -> void:
		for penguin: PenguinVisual in penguins:
			penguin.tick(1.0 / 30.0, 0.5))
	viewport_container.add_child(ticker)


func _build_endless(parent: Control) -> void:
	var result := Game.last_endless_result
	_title(parent, "Expedition Over!", 64)
	if bool(result.get("is_record", false)):
		_title(parent, "★ NEW HIGH SCORE ★", 36, Color(1.0, 0.85, 0.25))
	var panel := _make_panel(parent)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	panel.add_child(grid)
	var rows := [
		["Score", str(int(result.get("score", 0)))],
		["Distance", "%dm" % int(result.get("distance", 0.0))],
		["Fish", str(int(result.get("fish", 0)))],
		["Best Score", str(Progression.endless_high_score())],
	]
	for row: Array in rows:
		for cell: String in row:
			var label := Label.new()
			label.text = cell
			label.add_theme_font_size_override("font_size", 26)
			grid.add_child(label)


func _build_time_trial(parent: Control) -> void:
	var row: Dictionary = Game.last_race_results[0] if not Game.last_race_results.is_empty() else {}
	_title(parent, "Time Trial Complete!", 60)
	_title(parent, RaceHUD.format_time(float(row.get("time", 0.0))), 72, Color(0.6, 0.95, 1.0))
	if bool(row.get("is_record", false)):
		_title(parent, "★ NEW RECORD ★", 36, Color(1.0, 0.85, 0.25))
	var best := Progression.best_time(Game.course_id)
	if best > 0.0:
		_title(parent, "Best: %s" % RaceHUD.format_time(best), 26, Color(0.7, 0.82, 0.95))


func _build_tutorial(parent: Control) -> void:
	_title(parent, "Waddle School Complete!", 60)
	_title(parent, "You're ready to race, champ.", 28, Color(0.7, 0.85, 1.0))


func _build_rewards(parent: Control) -> void:
	var rewards := Game.last_rewards
	if rewards.is_empty():
		return
	var panel := _make_panel(parent)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 40)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(hbox)
	var fish_label := Label.new()
	fish_label.text = "+%d fish" % int(rewards.get("fish", 0))
	fish_label.add_theme_font_size_override("font_size", 30)
	fish_label.add_theme_color_override("font_color", Color(0.55, 0.85, 0.95))
	hbox.add_child(fish_label)
	var xp_label := Label.new()
	xp_label.text = "+%d XP  (Level %d)" % [int(rewards.get("xp", 0)), Progression.get_level()]
	xp_label.add_theme_font_size_override("font_size", 30)
	xp_label.add_theme_color_override("font_color", Color(0.7, 0.95, 0.6))
	hbox.add_child(xp_label)
	var total_label := Label.new()
	total_label.text = "Total: %d fish" % Progression.get_fish()
	total_label.add_theme_font_size_override("font_size", 30)
	hbox.add_child(total_label)


func _build_buttons(parent: Control) -> void:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(hbox)
	if Game.mode == Game.Mode.GRAND_PRIX and Game.gp_round < CoursesDB.GRAND_PRIX_ORDER.size() - 1:
		_add_button(hbox, "Next Race", func() -> void:
			Game.advance_grand_prix())
	elif Game.mode == Game.Mode.GRAND_PRIX:
		_add_button(hbox, "Finish Cup", func() -> void:
			SceneRouter.go_to(Game.SCENE_MAIN_MENU))
	else:
		_add_button(hbox, "Race Again", func() -> void:
			SceneRouter.go_to(Game.SCENE_RACE))
	_add_button(hbox, "Main Menu", func() -> void:
		SceneRouter.go_to(Game.SCENE_MAIN_MENU))


func _make_panel(parent: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.17, 0.3, 0.85)
	style.set_corner_radius_all(14)
	style.content_margin_left = 30
	style.content_margin_right = 30
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel


func _add_button(parent: Control, text: String, action: Callable) -> void:
	var button := UITheme.make_button(text, Vector2(240, 56), 26)
	UITheme.hook_sounds(button)
	button.pressed.connect(action)
	parent.add_child(button)
	_buttons.append(button)
