class_name ExpeditionSubmenuShell
extends RefCounted
## Fresh submenu composition. Art is a scene layer, never a bitmap UI; every
## label, action and stateful row below is a real accessible Godot control.

const TITLE_ART := {
	"settings": "res://assets/art/ui/menu/settings_title_v1.webp",
	"leaderboard": "res://assets/art/ui/menu/leaderboard_title_v1.webp",
	"achievements": "res://assets/art/ui/menu/achievements_title_v1.webp",
	"shop": "res://assets/art/ui/menu/shop_title_v1.webp",
	"penguins": "res://assets/art/ui/menu/penguins_title_v1.webp",
}


static func build(owner: Control, _art_key: String, title: String,
		hero_fraction: float, header_first: bool = true) -> Dictionary:
	var profile := LayoutProfile.for_viewport(owner.get_viewport())
	var portrait := profile.is_portrait()
	var root := MarginContainer.new()
	root.name = "ExpeditionPageLayout"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	UtilityScreenLayout.bind_safe_rect(owner, root)
	var gutter := maxi(12, roundi(profile.safe_rect.size.x * (0.035 if portrait else 0.02)))
	for side: String in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_%s" % side, gutter)
	owner.add_child(root)

	var frame := VBoxContainer.new()
	frame.name = "ExpeditionFrame"
	frame.add_theme_constant_override("separation", gutter)
	root.add_child(frame)
	var body: BoxContainer = VBoxContainer.new() if portrait else HBoxContainer.new()
	body.add_theme_constant_override("separation", gutter)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(body)
	var art_stage: Control = null
	if not portrait:
		art_stage = Control.new()
		art_stage.name = "ExpeditionArtStage"
		art_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		art_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(art_stage)

	var page := VBoxContainer.new()
	page.name = "ExpeditionPage"
	page.add_theme_constant_override("separation", gutter)
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if not portrait:
		page.custom_minimum_size.x = minf(profile.safe_rect.size.x * 0.43, 750.0)
	body.add_child(page)
	var hero_space: Control = null
	if portrait and hero_fraction > 0.0:
		hero_space = Control.new()
		hero_space.custom_minimum_size.y = profile.safe_rect.size.y * hero_fraction
		hero_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page.add_child(hero_space)

	var header := Control.new()
	header.name = "ExpeditionHeader"
	var art_width := minf(profile.safe_rect.size.x * (0.62 if portrait else 0.44),
		760.0)
	var header_height := profile.safe_rect.size.x * 0.18 if portrait \
		else clampf(profile.safe_rect.size.y * 0.115, 74.0, 150.0)
	if portrait and _art_key == "leaderboard":
		header_height = profile.safe_rect.size.x * 0.32
	elif _art_key == "leaderboard":
		header_height = clampf(profile.safe_rect.size.y * 0.22, 120.0, 280.0)
	header.custom_minimum_size.y = header_height
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_child(header)
	frame.move_child(header, 0)
	var header_surface := Panel.new()
	header_surface.name = "SharedSnowHeader"
	header_surface.visible = _art_key == "penguins"
	header_surface.set_anchors_preset(Control.PRESET_FULL_RECT)
	header_surface.add_theme_stylebox_override("panel",
		ExpeditionMenuStyle.material_card(0.0, 0.0))
	header_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(header_surface)
	var back_size := header_height * (0.46 if _art_key == "leaderboard" else 0.86)
	var back := ExpeditionMenuStyle.back_button(back_size)
	back.accessibility_name = "Back to previous page"
	back.set_anchors_preset(Control.PRESET_TOP_LEFT)
	back.offset_right = back_size
	back.offset_bottom = back_size
	back.pressed.connect(func() -> void:
		SceneRouter.go_back())
	header.add_child(back)
	if TITLE_ART.has(_art_key):
		var title_art := TextureRect.new()
		title_art.name = "ApprovedTitleArtwork"
		title_art.texture = ExpeditionMenuStyle.title_texture(_art_key)
		title_art.accessibility_name = title
		title_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		title_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		title_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_art.set_anchors_preset(Control.PRESET_CENTER_TOP)
		title_art.offset_left = -art_width * 0.5
		title_art.offset_right = art_width * 0.5
		title_art.offset_top = header_height * 0.42 if portrait and _art_key == "leaderboard" else 0.0
		title_art.offset_bottom = header_height
		header.add_child(title_art)
	elif not title.is_empty():
		var heading_plate := PanelContainer.new()
		heading_plate.name = "ExpeditionTitlePlate"
		heading_plate.add_theme_stylebox_override("panel",
			ExpeditionMenuStyle.material_box(false, 12.0, 6.0))
		heading_plate.set_anchors_preset(Control.PRESET_CENTER_TOP)
		heading_plate.offset_left = -art_width * 0.5
		heading_plate.offset_right = art_width * 0.5
		heading_plate.offset_top = 0.0
		heading_plate.offset_bottom = header_height * 0.76
		header.add_child(heading_plate)
		var heading := ExpeditionMenuStyle.label(title.to_upper(), _font(40),
			ExpeditionMenuStyle.INK)
		heading.add_theme_font_override("font", UITheme.display_font())
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		heading_plate.add_child(heading)
	if header_first and hero_space != null:
		page.move_child(hero_space, 0)
	var scroll := ScrollContainer.new()
	scroll.name = "ExpeditionContentScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	TouchScroll.attach(scroll)
	page.add_child(scroll)
	var content := VBoxContainer.new()
	content.name = "ExpeditionContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	UtilityScreenLayout.defer_header_alignment(owner,
		header.find_child("ApprovedTitleArtwork", true, false) as Control, back)
	return {"root": root, "content": content, "scroll": scroll,
		"back": back, "portrait": portrait, "profile": profile,
		"header": header, "art_stage": art_stage}


static func heading(parent: Control, text: String, size: int = 25) -> Label:
	var label := ExpeditionMenuStyle.label(text, _font(size), ExpeditionMenuStyle.INK)
	label.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	parent.add_child(label)
	return label


static func note(parent: Control, text: String, size: int = 18) -> Label:
	var label := ExpeditionMenuStyle.label(text, _font(size),
		ExpeditionMenuStyle.INK_MUTED)
	label.add_theme_font_override("font", UITheme.ui_font())
	parent.add_child(label)
	return label


static func card(parent: Control) -> VBoxContainer:
	var panel := ExpeditionMenuStyle.panel(parent, Color(ExpeditionMenuStyle.IVORY, 0.96))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	panel.add_child(stack)
	return stack


static func _font(size: int) -> int:
	return maxi(1, roundi(float(UITheme.scaled_font(size)) *
		(1.25 if UITheme.is_touch() else 1.0)))
