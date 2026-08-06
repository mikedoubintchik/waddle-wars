extends Control
## Post-race results: standings, rewards, Grand Prix standings between
## rounds, cup ceremony after the final round, records for TT / Endless.

const MEDAL_COLORS: Array[String] = ["#f5c542", "#c9d2dc", "#cd8f5a"]
const MEDAL_RIMS: Array[String] = ["#c98f1b", "#8d99a6", "#96683f"]

## Row text tints for podium places: gold / silver / bronze.
const PODIUM_TINTS: Array[Color] = [
	Color(0.961, 0.773, 0.259),
	Color(0.788, 0.824, 0.863),
	Color(0.804, 0.561, 0.353),
]

var _buttons: Array[Button] = []


func _ready() -> void:
	UITheme.make_background(self)
	_add_celebration_glow()

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UITheme.spacing(UITheme.SPACE_S))
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
	var entrance_items: Array[Control] = []
	for child in vbox.get_children():
		if child is Control:
			entrance_items.append(child as Control)
	UITheme.play_entrance(self, entrance_items)
	AudioManager.play_music("music_title")
	if not _buttons.is_empty():
		_buttons[0].grab_focus()


## Warm radial glow behind the headline area; brighter gold when the player
## podiumed so the screen reads celebratory at a glance.
func _add_celebration_glow() -> void:
	var podium := false
	for row: Dictionary in Game.last_race_results:
		if bool(row.get("is_player", false)) and int(row.get("position", 8)) <= 3:
			podium = true
	var grad := Gradient.new()
	var core := Color(0.96, 0.78, 0.28, 0.22) if podium else Color(0.5, 0.75, 0.95, 0.13)
	grad.colors = PackedColorArray([core, Color(core.r, core.g, core.b, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.18)
	tex.fill_to = Vector2(0.5, 0.75)
	var glow := TextureRect.new()
	glow.texture = tex
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)


## Circular medal glyph with ribbon for podium positions (0-indexed place).
## Place is shown as pip dots (SVG <text> is unsupported by the rasterizer).
static func _medal_svg(place: int) -> String:
	var fill := MEDAL_COLORS[place]
	var rim := MEDAL_RIMS[place]
	var pips := ""
	var count := place + 1
	for i: int in count:
		var x := 18.0 + (float(i) - float(count - 1) * 0.5) * 7.0
		pips += "<circle cx=\"%.1f\" cy=\"30\" r=\"2.6\" fill=\"%s\"/>" % [x, rim]
	return """<svg xmlns="http://www.w3.org/2000/svg" width="36" height="48" viewBox="0 0 36 48">
<path d="M10 2 L18 16 L26 2 L20 2 L18 6 L16 2 Z" fill="#5a7ba6"/>
<path d="M10 2 L14 2 L20 13 L16 16 Z" fill="#48648a"/>
<circle cx="18" cy="30" r="14" fill="%s" stroke="%s" stroke-width="2.5"/>
<circle cx="18" cy="30" r="9.5" fill="none" stroke="%s" stroke-width="1.5" opacity="0.55"/>
%s
</svg>""" % [fill, rim, rim, pips]


## Position cell: medal icon for top three, plain number otherwise. `big`
## enlarges podium medals for the main standings table so top finishes pop.
static func _position_cell(place_number: int, big: bool = false) -> Control:
	if place_number >= 1 and place_number <= 3:
		var medal_scale := 1.3 if big else 1.0
		var texture := UITheme.make_icon(_medal_svg(place_number - 1), medal_scale)
		if texture != null:
			var icon := TextureRect.new()
			icon.texture = texture
			icon.custom_minimum_size = Vector2(36.0 * medal_scale, 48.0 * medal_scale)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			return icon
	var label := Label.new()
	label.text = "%d." % place_number
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0))
	return label


## Row text color: player row reads highlighted gold, podium rows carry their
## medal tint, everyone else stays neutral ice-white.
static func _row_color(is_player: bool, place_number: int) -> Color:
	if is_player:
		return Color(1.0, 0.9, 0.4)
	if place_number >= 1 and place_number <= PODIUM_TINTS.size():
		return PODIUM_TINTS[place_number - 1]
	return Color(0.9, 0.94, 1.0)


func _title(parent: Control, text: String, size: int = 56, color: Color = Color(0.95, 0.97, 1.0)) -> void:
	var label: Label
	if size >= 40:
		label = UITheme.heading(text, size)
	else:
		label = Label.new()
		label.text = text
		label.add_theme_font_size_override("font_size", size)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
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
		var place := int(row.get("position", 0))
		var podium := place >= 1 and place <= 3
		var color := _row_color(is_player, place)
		grid.add_child(_position_cell(place, true))
		var cells := [
			String(row.get("name", "?")),
			"DNF" if bool(row.get("dnf", false)) else RaceHUD.format_time(float(row.get("time", 0.0))),
			str(int(row.get("fish", 0))),
		]
		for cell: String in cells:
			var cell_label := Label.new()
			cell_label.text = cell
			cell_label.add_theme_font_size_override("font_size", 26 if podium else 24)
			if podium or is_player:
				cell_label.add_theme_font_override("font", UITheme.bold_font())
			cell_label.add_theme_color_override("font_color", color)
			cell_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
		var color := _row_color(is_player, i + 1)
		grid.add_child(_position_cell(i + 1))
		for cell: String in [String(row["name"]), "%d pts" % int(row["points"])]:
			var label := Label.new()
			label.text = cell
			label.add_theme_font_size_override("font_size", 24)
			if is_player or i < 3:
				label.add_theme_font_override("font", UITheme.bold_font())
			label.add_theme_color_override("font_color", color)
			label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
	UITheme.crisp_subviewport(viewport, self)
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
	_build_online_section(parent, "endless", "endless", int(result.get("score", 0)))


## Optional global leaderboard hook. Signed in: auto-post and show rank.
## Signed out on web: offer Clerk sign-in, then post. Desktop: stay quiet —
## boards are still viewable from the main menu.
func _build_online_section(parent: Control, mode: String, course: String, value: int) -> void:
	if GameConfig.is_headless() or value <= 0:
		return
	var label := UITheme.sub_label("", 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var submit := func() -> void:
		label.text = "Posting to global leaderboard…"
		LeaderboardClient.submit_score(mode, course, value,
			func(ok: bool, data: Dictionary) -> void:
				if not is_instance_valid(label):
					return
				if not ok:
					label.text = "Couldn't reach the leaderboard."
					return
				var rank := int(data.get("rank", 0))
				if bool(data.get("improved", false)):
					label.text = "★ Global rank #%d — new personal best posted!" % rank
				else:
					label.text = "Global rank #%d (your best: %s)" % [
						rank, LeaderboardClient.format_value(mode, int(data.get("best", value)))])
	if LeaderboardClient.signed_in:
		parent.add_child(label)
		submit.call()
	elif LeaderboardClient.can_sign_in():
		label.text = "Sign in to post your score to the global leaderboard"
		parent.add_child(label)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		parent.add_child(row)
		var button := UITheme.make_button("Sign In", Vector2(240, 52), 22)
		UITheme.hook_sounds(button)
		button.pressed.connect(func() -> void:
			button.text = "Opening…"
			LeaderboardClient.sign_in())
		row.add_child(button)
		LeaderboardClient.auth_changed.connect(func() -> void:
			if LeaderboardClient.signed_in and is_instance_valid(label):
				if is_instance_valid(button):
					button.visible = false
				submit.call(),
			CONNECT_ONE_SHOT)


func _build_time_trial(parent: Control) -> void:
	var row: Dictionary = Game.last_race_results[0] if not Game.last_race_results.is_empty() else {}
	_title(parent, "Time Trial Complete!", 60)
	_title(parent, RaceHUD.format_time(float(row.get("time", 0.0))), 72, Color(0.6, 0.95, 1.0))
	if bool(row.get("is_record", false)):
		_title(parent, "★ NEW RECORD ★", 36, Color(1.0, 0.85, 0.25))
	var best := Progression.best_time(Game.course_id)
	if best > 0.0:
		_title(parent, "Best: %s" % RaceHUD.format_time(best), 26, Color(0.7, 0.82, 0.95))
	_build_online_section(parent, "time", Game.course_id, int(round(float(row.get("time", 0.0)) * 1000.0)))


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
	_add_share_button(hbox)
	_add_button(hbox, "Main Menu", func() -> void:
		SceneRouter.go_to(Game.SCENE_MAIN_MENU))


## Share copy for the finished run, or "" when there is nothing worth
## bragging about (tutorial, missing result handoff).
func _share_text() -> String:
	match Game.mode:
		Game.Mode.TUTORIAL:
			return ""
		Game.Mode.ENDLESS:
			var score := int(Game.last_endless_result.get("score", 0))
			if score <= 0:
				return ""
			return ShareManager.compose_race_text("endless", "", 0, str(score))
		Game.Mode.TIME_TRIAL:
			if Game.last_race_results.is_empty():
				return ""
			var row: Dictionary = Game.last_race_results[0]
			return ShareManager.compose_race_text(
				"time_trial", CoursesDB.display_name(Game.course_id), 0,
				RaceHUD.format_time(float(row.get("time", 0.0))))
		_:
			var player_row: Dictionary = {}
			for row: Dictionary in Game.last_race_results:
				if bool(row.get("is_player", false)):
					player_row = row
			if player_row.is_empty():
				return ""
			var time_text := "" if bool(player_row.get("dnf", false)) \
				else RaceHUD.format_time(float(player_row.get("time", 0.0)))
			var mode_tag := "grand_prix" if Game.mode == Game.Mode.GRAND_PRIX else "race"
			return ShareManager.compose_race_text(
				mode_tag, CoursesDB.display_name(Game.course_id),
				int(player_row.get("position", 0)), time_text)


## Share sits between the primary continue action and Main Menu. The native
## share sheet must open from inside the press (browser user gesture), so the
## handler calls ShareManager directly; the clipboard path toasts "Copied!".
func _add_share_button(parent: Control) -> void:
	var text := _share_text()
	if text.is_empty():
		return
	var button := ShareManager.make_share_button("Share", Vector2(220, 56), 26)
	UITheme.hook_sounds(button)
	button.pressed.connect(func() -> void:
		ShareManager.share_with_toast(self, text))
	parent.add_child(button)
	_buttons.append(button)


func _make_panel(parent: Control) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := UITheme.make_panel_style(Color(0.075, 0.129, 0.220, 0.92))
	style.content_margin_left = 32.0
	style.content_margin_right = 32.0
	style.content_margin_top = 20.0
	style.content_margin_bottom = 20.0
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel


func _add_button(parent: Control, text: String, action: Callable) -> void:
	var button := UITheme.make_button(text, Vector2(240, 56), 26)
	UITheme.hook_sounds(button)
	button.pressed.connect(action)
	parent.add_child(button)
	_buttons.append(button)
