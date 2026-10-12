extends Control
## Live trophy collection on the new expedition screen system.

const DetailStyle := preload("res://scripts/ui/menu_detail_style.gd")

const ICON_ATLAS := "res://assets/art/ui/menu/achievement_icons_v3.webp"
const ICON_REGIONS := {
	"fish": Rect2(50,38,320,397), "sprint": Rect2(418,43,410,395),
	"mountain": Rect2(827,39,410,402), "compass": Rect2(29,443,389,387),
	"aurora": Rect2(424,436,401,396), "dodge": Rect2(827,438,407,394),
	"power": Rect2(13,827,413,378), "gift": Rect2(455,850,350,360),
	"lock": Rect2(861,865,357,348),
}
var _page: Control = null
var _selected_id: String = "runner_fish_bronze"
var _achievement_buttons: Dictionary = {}
var _detail: VBoxContainer = null
var _tile_width: float = 290.0
var _portrait_page := false
var _collection_scroll: ScrollContainer = null

class CollectionRing:
	extends Control
	var fraction: float = 0.0
	func _draw() -> void:
		var center := size * 0.5
		var radius := minf(size.x, size.y) * 0.42
		draw_circle(center, radius + 8.0, Color("fff9ed"))
		draw_arc(center, radius - 5.0, -PI * 0.5, PI * 1.5, 64, Color("d4e4ed"), 12.0, true)
		if fraction > 0.0:
			draw_arc(center, radius - 5.0, -PI * 0.5, -PI * 0.5 + fraction * TAU,
				64, Color("269eeb"), 12.0, true)



func _ready() -> void:
	UITheme.apply_ui_scale(self)
	preload("res://scripts/ui/menu_composition_background.gd").bind(
		ExpeditionMenuStyle.add_backdrop(self, "achievements"),
		ExpeditionMenuStyle.BACKGROUNDS["achievements_portrait"],
		"res://assets/art/ui/menu/achievement_background_desktop_v3.webp")
	_build()
	get_viewport().size_changed.connect(_rebuild)
	UITheme.attach_swipe_back(self, _back)


func _rebuild() -> void:
	if _page != null:
		_page.free()
	_build()


func _build() -> void:
	_achievement_buttons.clear()
	var shell := ExpeditionSubmenuShell.build(self, "achievements", "Achievements", 0.195)
	_page = shell["root"] as Control
	var content := shell["content"] as VBoxContainer
	var profile := shell["profile"] as LayoutProfile
	_portrait_page = bool(shell["portrait"])
	# One authored gutter measured from the full canvas, never safe+gutter.
	var margins := _page as MarginContainer
	var authored := profile.viewport_size.x * (0.035 if _portrait_page else 0.02)
	for side: String in ["left", "right", "top", "bottom"]:
		var inset := profile.safe_insets.x if side == "left" else profile.safe_insets.z if side == "right" else profile.safe_insets.y if side == "top" else profile.safe_insets.w
		margins.add_theme_constant_override("margin_" + side, roundi(maxf(authored, inset) - inset))

	if bool(shell["portrait"]):
		var header := shell["header"] as Control
		header.custom_minimum_size.y = profile.safe_rect.size.x * 0.26
		var title := header.find_child("ApprovedTitleArtwork",true,false) as TextureRect
		title.offset_top = -profile.viewport_size.y * 0.035
		title.offset_bottom = header.custom_minimum_size.y - profile.viewport_size.y * 0.035
	else:
		var art_stage := shell["art_stage"] as Control
		art_stage.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		art_stage.custom_minimum_size.x = profile.viewport_size.x * 0.41
		var header := shell["header"] as Control
		header.custom_minimum_size.y = 0.0
		header.z_index = 1
		var title := header.find_child("ApprovedTitleArtwork",true,false) as TextureRect
		title.set_anchors_preset(Control.PRESET_TOP_LEFT)
		title.offset_left = profile.safe_rect.size.x * 0.05
		title.offset_right = profile.safe_rect.size.x * 0.45
		title.offset_top = -profile.safe_rect.size.y * 0.043
		title.offset_bottom = profile.safe_rect.size.y * 0.207
		var scroll := shell["scroll"] as ScrollContainer
		var page := scroll.get_parent()
		var enclosure := PanelContainer.new()
		enclosure.name = "TrophyIceEnclosure"
		enclosure.size_flags_vertical = Control.SIZE_EXPAND_FILL
		enclosure.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ice := ExpeditionMenuStyle.material_card(20.0,20.0)
		ice.modulate_color = Color("d3edfc")
		enclosure.add_theme_stylebox_override("panel",ice)
		page.add_child(enclosure)
		scroll.reparent(enclosure)
		# Reference reserves a right rail for scrolling and the collection seal.
		# Keep the live grid out from under that seal instead of hiding a badge.
		var grid_margin := MarginContainer.new()
		grid_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid_margin.add_theme_constant_override("margin_right", roundi(profile.viewport_size.x * 0.060))
		scroll.add_child(grid_margin)
		content.reparent(grid_margin)
		(_page.find_child("ExpeditionFrame", true, false) as VBoxContainer).add_theme_constant_override("separation", roundi(profile.viewport_size.y * 0.023))

	_tile_width = minf((profile.viewport_size.x if _portrait_page else profile.safe_rect.size.x) * (0.295 if _portrait_page else 0.13), 340.0)
	_collection_scroll = shell["scroll"] as ScrollContainer
	_style_collection_scroll(_collection_scroll)
	var guide := ExpeditionSubmenuShell.card(content)
	guide.name = "AchievementGuide"
	(guide.get_parent() as PanelContainer).add_theme_stylebox_override("panel", DetailStyle.inset(18, 14, 24))
	var guide_title := ExpeditionMenuStyle.label("YOUR TROPHY COLLECTION", roundi(_tile_width * 0.12))
	guide_title.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	guide_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	DetailStyle.clean_label(guide_title)
	guide.add_child(guide_title)
	var explanation := ExpeditionMenuStyle.label("Select a badge to see its goal, what counts and the next tier.\nSome goals add across runs; others need one run or a hit-free streak.", roundi(_tile_width * 0.092))
	explanation.name = "AchievementExplanation"
	explanation.add_theme_font_override("font", UITheme.ui_font())
	explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	DetailStyle.clean_label(explanation, ExpeditionMenuStyle.INK_MUTED)
	guide.add_child(explanation)
	var earned := 0
	for id: String in AchievementsDB.RUNNER_ORDER:
		if Progression.is_achievement_unlocked(id):
			earned += 1
	var ring := CollectionRing.new()
	ring.name = "CollectionProgress"
	ring.fraction = float(earned) / float(maxi(1, AchievementsDB.RUNNER_ORDER.size()))
	ring.custom_minimum_size = Vector2.ONE * minf(profile.viewport_size.x * 0.19, 180.0 if _portrait_page else 138.0)
	ring.size = ring.custom_minimum_size
	ring.anchor_left = 1.0
	ring.anchor_right = 1.0
	ring.offset_left = -ring.size.x
	ring.offset_right = 0.0
	if not _portrait_page:
		ring.offset_top = -profile.viewport_size.y * 0.024
		ring.offset_bottom = ring.offset_top + ring.size.y
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(shell["header"] as Control).add_child(ring)
	var count := ExpeditionMenuStyle.label("%d / %d" % [earned, AchievementsDB.RUNNER_ORDER.size()],
		maxi(16, roundi(ring.size.x * 0.23)))
	count.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	count.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ring.add_child(count)
	var display_order := _display_order()
	var first_row := _badge_grid(content)
	for index: int in mini(3, display_order.size()):
		_add_achievement(first_row, display_order[index])
	_detail = ExpeditionSubmenuShell.card(content)
	_detail.name = "SelectedAchievementDetail"
	(_detail.get_parent() as PanelContainer).add_theme_stylebox_override("panel", DetailStyle.inset(18, 18, 28))
	var remaining := _badge_grid(content)
	for index: int in range(3, display_order.size()):
		_add_achievement(remaining, display_order[index])
	# Retired mode trophies remain visible when earned, with their old meanings.
	var legacy := PackedStringArray()
	for id: String in AchievementsDB.LEGACY_ORDER:
		if Progression.is_achievement_unlocked(id): legacy.append(id)
	if not legacy.is_empty():
		ExpeditionSubmenuShell.heading(content, "LEGACY TROPHIES", 24)
		ExpeditionSubmenuShell.note(content, "Previously earned. Kept separately from the Waddle Run collection.", 18)
		var archive := _badge_grid(content)
		for id: String in legacy: _add_achievement(archive, id)
	_select_achievement(_selected_id, false)
	var done := ExpeditionMenuStyle.button("BACK", true, 25, 72.0)
	done.pressed.connect(_back)
	content.add_child(done)
	UtilityScreenLayout.defer_header_alignment(self,
		(shell["header"] as Control).find_child("ApprovedTitleArtwork", true, false) as Control,
		shell["back"] as Control, [ring])


func _style_collection_scroll(scroll: ScrollContainer) -> void:
	var rail := scroll.get_v_scroll_bar()
	rail.name = "AchievementScrollRail"
	var width := maxf(10.0, _tile_width * 0.052)
	rail.custom_minimum_size.x = width
	var track := DetailStyle.progress(Color("85abc3"), roundi(width * 0.5))
	track.border_color = Color("618399")
	track.set_border_width_all(1)
	track.content_margin_left = width * 0.5
	track.content_margin_right = width * 0.5
	rail.add_theme_stylebox_override("scroll", track)
	rail.add_theme_stylebox_override("scroll_focus", track)
	for state: String in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var thumb := DetailStyle.progress(Color("209eff") if state == "grabber" else Color("49baff"), roundi(width * 0.5))
		thumb.border_color = Color("78d9ff")
		thumb.border_width_left = 2
		thumb.border_width_right = 1
		thumb.border_width_bottom = 2
		thumb.content_margin_top = _tile_width * 0.12
		thumb.content_margin_bottom = _tile_width * 0.12
		rail.add_theme_stylebox_override(state, thumb)
	var blank := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	blank.fill(Color.TRANSPARENT)
	var empty_icon := ImageTexture.create_from_image(blank)
	for icon: String in ["increment", "increment_highlight", "increment_pressed", "decrement", "decrement_highlight", "decrement_pressed"]:
		rail.add_theme_icon_override(icon, empty_icon)


func _display_order() -> PackedStringArray:
	# Presentation follows the reference; IDs, targets and unlock order remain
	# the authoritative progression catalog's values.
	var ordered := PackedStringArray()
	for tier: String in AchievementsDB.TIERS:
		for family: String in ["fish", "missions", "distance", "time", "run", "clean", "near", "power"]:
			ordered.append("runner_%s_%s" % [family, tier])
	return ordered


func _badge_grid(parent: Control) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 14)
	parent.add_child(grid)
	return grid


func _add_achievement(parent: GridContainer, id: String) -> void:
	var info := AchievementsDB.get_item(id)
	var unlocked := Progression.is_achievement_unlocked(id)
	var button := Button.new()
	button.name = "Achievement_%s" % id
	button.accessibility_name = "%s. %s. %s %s" % [info.get("name", id), info.get("scope", "Legacy trophy"), info.get("desc", ""), info.get("counts", "")]
	button.custom_minimum_size = Vector2(0.0, _tile_width * 1.17)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for state: String in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(state, DetailStyle.inset(12.0, 14.0, _tile_width * 0.10, Color("edf5fa")))
	UITheme.hook_sounds(button)
	button.pressed.connect(_select_achievement.bind(id))
	parent.add_child(button)
	_achievement_buttons[id] = button
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.offset_left = _tile_width * 0.10
	stack.offset_right = -_tile_width * 0.10
	stack.offset_top = 10.0
	stack.offset_bottom = -10.0
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 5)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(stack)
	var emblem := TextureRect.new()
	emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	emblem.texture = _badge_texture(id)
	emblem.modulate = Color.WHITE if unlocked or info.get("tier", "bronze") == "bronze" else Color(0.78, 0.84, 0.91)
	emblem.custom_minimum_size.y = _tile_width * 0.75
	emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(emblem)
	var name_label := ExpeditionMenuStyle.label(String(info.get("name", id)).split(" · ")[0].to_upper(),
		maxi(22, roundi(_tile_width * (0.11 if _portrait_page else 0.132))))
	name_label.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	DetailStyle.clean_label(name_label)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(name_label)
	var progress := _progress_for(id)
	var bar := ProgressBar.new()
	bar.max_value = maxi(1, int(progress.get("target", 1)))
	bar.value = bar.max_value if unlocked else int(progress.get("current", 0))
	bar.show_percentage = false
	bar.name = "AchievementTileProgress"
	bar.custom_minimum_size.y = maxf(16.0, _tile_width * 0.07)
	bar.add_theme_stylebox_override("background", DetailStyle.progress(Color("d5dee2")))
	bar.add_theme_stylebox_override("fill", DetailStyle.progress(Color("219ae6")))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(bar)
	var tier := String(info.get("tier", ""))
	if not tier.is_empty():
		var tier_label := ExpeditionMenuStyle.label(tier.to_upper(), maxi(13, roundi(_tile_width * 0.06)))
		tier_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		tier_label.offset_left = -_tile_width * 0.45
		tier_label.offset_right = -10.0
		tier_label.offset_top = 8.0
		tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tier_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tier_label.hide()
		button.tooltip_text = String(info.get("name", id))
		button.add_child(tier_label)
	var glow := Panel.new()
	glow.name = "SelectedAchievementGlow"
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rim := StyleBoxFlat.new()
	rim.draw_center = false
	rim.border_color = Color("ffce50")
	rim.set_border_width_all(6)
	rim.set_corner_radius_all(roundi(_tile_width * 0.10))
	rim.shadow_color = Color(1.0, 0.70, 0.10, 0.6)
	rim.shadow_size = 14
	glow.add_theme_stylebox_override("panel", rim)
	glow.visible = id == _selected_id
	button.add_child(glow)


func _select_achievement(id: String, reveal: bool = true) -> void:
	if not _achievement_buttons.has(id) or _detail == null:
		return
	_selected_id = id
	for key: String in _achievement_buttons:
		var button := _achievement_buttons[key] as Button
		var surface := DetailStyle.inset(12.0, 14.0, _tile_width * 0.10, Color("fff1c0") if key == id else Color("edf5fa"))
		button.add_theme_stylebox_override("normal", surface)
		var glow := button.get_node_or_null("SelectedAchievementGlow") as Control
		if glow != null: glow.visible = key == id
	for child: Node in _detail.get_children():
		child.free()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.custom_minimum_size.y = _tile_width * 0.72
	_detail.add_child(row)
	var badge := TextureRect.new()
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.texture = _badge_texture(id)
	badge.custom_minimum_size = Vector2.ONE * _tile_width * (0.65 if _portrait_page else 0.64)
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(badge)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(copy)
	var info := AchievementsDB.get_item(id)
	var heading := ExpeditionSubmenuShell.heading(copy, String(info.get("name", id)).to_upper(), PortraitSceneFraming.readable_size(25))
	heading.add_theme_font_size_override("font_size", maxi(24,roundi(_tile_width * 0.13)))
	var description := ExpeditionSubmenuShell.note(copy, String(info.get("desc", "")), roundi(_tile_width * (0.13 if _portrait_page else 0.112)))
	description.name = "AchievementDescription"
	description.add_theme_font_size_override("font_size", roundi(_tile_width * (0.13 if _portrait_page else 0.112)))
	DetailStyle.clean_label(description)
	DetailStyle.clean_label(heading)
	var progress := _progress_for(id)
	var status := "EARNED · %d XP" % int(info.get("xp", 150)) if Progression.is_achievement_unlocked(id) else "NOT YET EARNED"
	if bool(progress.get("earned_before_rebalance", false)):
		status = "EARNED · PREVIOUS GOAL"
	if not Progression.is_achievement_unlocked(id) and not progress.is_empty():
		if info.get("family", "") == "time":
			status = "%d / %d MINUTES ACTIVE" % [int(progress["current"]) / 60, int(progress["target"]) / 60]
		else:
			status = "%d / %d%s" % [int(progress["current"]), int(progress["target"]),
				String(progress.get("unit", ""))]
	var progress_text := ExpeditionMenuStyle.label(status, roundi(_tile_width * 0.092))
	progress_text.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	DetailStyle.clean_label(progress_text)
	progress_text.name = "AchievementProgressValue"
	if bool(progress.get("earned_before_rebalance", false)):
		progress_text.tooltip_text = "Earned before the pacing update. Your badge and XP are kept."
	progress_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var progress_bar := ProgressBar.new()
	progress_bar.name = "AchievementDetailProgress"
	progress_bar.max_value = maxi(1, int(progress.get("target", 1)))
	progress_bar.value = progress_bar.max_value if Progression.is_achievement_unlocked(id) else int(progress.get("current", 0))
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size.y = maxf(_tile_width * 0.16, progress_text.get_combined_minimum_size().y + 6.0)
	progress_bar.add_theme_stylebox_override("background", ExpeditionMenuStyle.surface(Color("e4dfcc"), 16, false))
	progress_bar.add_theme_stylebox_override("fill", ExpeditionMenuStyle.surface(Color("35b7ef"), 16, false))
	copy.add_child(progress_bar)
	progress_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	progress_bar.add_child(progress_text)
	var reward := PanelContainer.new()
	reward.name = "AchievementReward"
	reward.custom_minimum_size.x = _tile_width * 0.60
	reward.add_theme_stylebox_override("panel", DetailStyle.inset(10, 8, 20, Color("f7eccb")))
	row.add_child(reward)
	var reward_stack := VBoxContainer.new()
	reward_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	reward.add_child(reward_stack)
	var reward_icon := TextureRect.new()
	reward_icon.texture = _icon_texture("gift")
	if not _portrait_page:
		var star := AtlasTexture.new()
		star.atlas = ExpeditionMenuStyle._material_texture("res://assets/art/ui/menu/controls_icons_v2.webp")
		star.region = Rect2(836, 836, 418, 418)
		star.filter_clip = true
		reward_icon.texture = star
	reward_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	reward_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	reward_icon.custom_minimum_size.y = _tile_width * 0.38
	reward_stack.add_child(reward_icon)
	var xp := ExpeditionMenuStyle.label("%d XP" % int(info.get("xp", 150)), roundi(_tile_width * 0.11))
	xp.name = "AchievementRewardValue"
	xp.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	xp.autowrap_mode = TextServer.AUTOWRAP_OFF
	DetailStyle.clean_label(xp)
	xp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	xp.tooltip_text = "Awarded automatically when this achievement is earned."
	reward_stack.add_child(xp)
	# Explanation spans the whole detail card, not the narrow badge/reward row.
	var scope := _detail_note(String(info.get("scope", "LEGACY TROPHY")), "AchievementScope", 0.094)
	scope.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	var counts := String(info.get("counts", info.get("desc", "")))
	_detail_note(counts, "AchievementWhatCounts", 0.092)
	var next_text := AchievementsDB.next_tier_requirement(id)
	var next_id := AchievementsDB.next_tier_id(id)
	if not next_id.is_empty() and Progression.is_achievement_unlocked(next_id):
		next_text += " Already earned."
	var next_label := _detail_note(next_text, "AchievementNextTier", 0.092)
	next_label.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	if reveal:
		_reveal_detail.call_deferred(id)


func _detail_note(text: String, node_name: String, scale: float) -> Label:
	var label := ExpeditionMenuStyle.label(text, maxi(16, roundi(_tile_width * scale)))
	label.name = node_name
	label.add_theme_font_override("font", UITheme.ui_font())
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	DetailStyle.clean_label(label)
	_detail.add_child(label)
	return label


func _reveal_detail(id: String) -> void:
	# Container sorting must finish before measuring the expanded explanation.
	await get_tree().process_frame
	if is_inside_tree() and id == _selected_id and is_instance_valid(_collection_scroll) and is_instance_valid(_detail):
		_collection_scroll.ensure_control_visible(_detail)


func _icon_texture(key: String) -> Texture2D:
	var icon := AtlasTexture.new()
	icon.atlas = ExpeditionMenuStyle._material_texture(ICON_ATLAS)
	icon.region = ICON_REGIONS.get(key, ICON_REGIONS["mountain"])
	icon.filter_clip = true
	return icon


func _badge_texture(id: String) -> Texture2D:
	var family := String(AchievementsDB.get_item(id).get("family", ""))
	if family == "missions":
		return ExpeditionMenuStyle._material_texture("res://assets/art/ui/menu/achievement_goal_trophy_v3.webp")
	var role := {"distance":"mountain","fish":"fish","missions":"sprint",
		"time":"compass","run":"aurora","clean":"sprint","near":"dodge","power":"power"}
	if role.has(family): return _icon_texture(role[family])
	if id in ["fish_hoarder","first_win","item_collector"]: return _icon_texture("fish")
	if id in ["first_waddle","shove_master","gp_finish","comeback"]: return _icon_texture("sprint")
	return _icon_texture("mountain")


func _progress_for(id: String) -> Dictionary:
	return Progression.achievement_progress(id)


func _back() -> void:
	SceneRouter.go_back()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		_back()
