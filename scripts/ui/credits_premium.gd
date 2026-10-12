extends Control

const UtilityArt := preload("res://scripts/ui/utility_reference_art.gd")
## Original credits, rebuilt as a readable expedition journal.

const NINJA_URL := "https://ninjaconsulting.ai"

var _page: Control = null


func _ready() -> void:
	UITheme.apply_ui_scale(self)
	UtilityArt.bind_background(self, "res://assets/art/ui/menu/credits_background_portrait_v1.webp", "res://assets/art/ui/menu/credits_background_landscape_v3.webp")
	_build()
	get_viewport().size_changed.connect(_rebuild)
	UITheme.attach_swipe_back(self, _back)


func _rebuild() -> void:
	if _page != null:
		_page.free()
	_build()


func _build() -> void:
	var profile := LayoutProfile.for_viewport(get_viewport())
	var safe := profile.safe_rect
	var portrait := profile.is_portrait()
	var width := safe.size.x * (0.86 if portrait else 0.43)
	var unit := width / 740.0
	_page = Control.new()
	_page.name = "CreditsReferenceLayout"
	_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_page)
	var back := ExpeditionMenuStyle.back_button(safe.size.y * 0.072 if portrait else safe.size.y * 0.11)
	back.position = safe.position + Vector2(safe.size.x * 0.03, safe.size.y * 0.025)
	back.pressed.connect(_back)
	_page.add_child(back)
	var journal := PanelContainer.new()
	journal.name = "CreditsJournal"
	journal.position = safe.position + Vector2((safe.size.x - width) * 0.5 if portrait else safe.size.x * 0.505, safe.size.y * (0.237 if portrait else 0.04))
	journal.size = Vector2(width, safe.size.y * (0.595 if portrait else 0.80))
	var parchment := StyleBoxTexture.new()
	parchment.texture = ExpeditionMenuStyle._material_texture("res://assets/art/ui/menu/credits_journal_v2.webp")
	parchment.texture_margin_left = 35.0
	parchment.texture_margin_right = 35.0
	parchment.texture_margin_top = 42.0
	parchment.texture_margin_bottom = 42.0
	parchment.content_margin_left = 36.0 * unit
	parchment.content_margin_right = 36.0 * unit
	parchment.content_margin_top = 26.0 * unit
	parchment.content_margin_bottom = 26.0 * unit
	journal.add_theme_stylebox_override("panel", parchment)
	_page.add_child(journal)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", roundi(10 * unit))
	journal.add_child(layout)
	var title := TextureRect.new()
	var title_crop := AtlasTexture.new()
	title_crop.atlas = ExpeditionMenuStyle._material_texture("res://assets/art/ui/menu/credits_title_v4.webp")
	title_crop.region = Rect2(96,138,1976,473)
	title_crop.filter_clip = true
	title.texture = title_crop
	title.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title.custom_minimum_size = Vector2(width * (0.70 if portrait else 0.79), (88 if portrait else 96) * unit)
	title.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	title.accessibility_name = "CREDITS"
	title.name = "CreditsJournalTitle"
	layout.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.name = "ExpeditionContentScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	TouchScroll.attach(scroll)
	layout.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	var main := VBoxContainer.new()
	main.name = "CreditsMainSections"
	main.add_theme_constant_override("separation", roundi(4 * unit))
	content.add_child(main)
	_credit_section(main, "MADE WITH CARE", "Waddle Wars: Penguin Panic\nSlide. Shove. Snack. Repeat.", unit)
	_credit_section(main, "TEAM", "Game design · Programming · Course design\n%s" % GameConfig.STUDIO_NAME, unit)
	_credit_section(main, "ART & MUSIC", "OpenAI ImageGen · Original game audio\nGodot Engine · Blender", unit)
	_credit_section(main, "SPECIAL THANKS", "Ninja Consulting\nOur players and testers", unit)
	var fit := func() -> void: main.custom_minimum_size.y = scroll.size.y
	scroll.resized.connect(fit)
	fit.call_deferred()
	_credit_section(content, "TYPEFACES", "Lilita One · Juan Montoreano\nAtkinson Hyperlegible Next · Braille Institute\nSIL Open Font License 1.1", unit)
	var links := HBoxContainer.new()
	links.name = "CreditsJournalLinks"
	links.add_theme_constant_override("separation", roundi(20 * unit))
	layout.add_child(links)
	for entry: Array in [["LICENSES", _show_licenses, "book"], ["PRIVACY", func() -> void: OS.shell_open(GameConfig.NATIVE_PRIVACY_URL), "shield"]]:
		var button := ExpeditionMenuStyle.button(entry[0], false, roundi(27 * unit), 88 * unit)
		button.name = "Credits" + String(entry[0]).capitalize()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(entry[1])
		UtilityArt.centered_button(button, entry[0], UtilityArt.icon(entry[2]), roundi(27 * unit), 76 * unit)
		links.add_child(button)
	var action_height := safe.size.y * (0.095 if portrait else 0.13)
	var done := ExpeditionMenuStyle.button("BACK", true, roundi(72 * unit), action_height)
	done.name = "CreditsIllustratedBack"
	done.custom_minimum_size.y = action_height
	done.position = Vector2(journal.position.x - width * (0.01 if portrait else -0.02), safe.position.y + safe.size.y * (0.866 if portrait else 0.85))
	done.size = Vector2(width * (1.02 if portrait else 0.96), action_height)
	UtilityArt.centered_button(done, "BACK", ExpeditionMenuStyle._material_texture(
		"res://assets/art/ui/menu/run_action_icon_v5.webp"), roundi(72 * unit), action_height, true, true)
	done.pressed.connect(_back)
	_page.add_child(done)
	# Native font metrics can raise a Button above its requested minimum. Anchor
	# the settled action's bottom, including that actual size, inside the safe area.
	var fit_action := func() -> void:
		done.position.y = minf(safe.position.y + safe.size.y * (0.866 if portrait else 0.85),
			safe.end.y - safe.size.y * 0.025 - done.size.y)
	done.resized.connect(fit_action)
	fit_action.call_deferred()


func _journal_label(text: String, font_size: int) -> Label:
	var label := ExpeditionMenuStyle.label(text, font_size, ExpeditionMenuStyle.INK)
	label.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _credit_section(parent: Control, title: String, body: String, unit: float = 1.0) -> void:
	var section := VBoxContainer.new()
	section.name = "CreditsSection_" + title.replace("&", "").to_pascal_case()
	section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	section.add_theme_constant_override("separation", roundi(4 * unit))
	parent.add_child(section)
	var divider := HBoxContainer.new()
	divider.name = "MountainDivider"
	divider.add_theme_constant_override("separation", roundi(12 * unit))
	section.add_child(divider)
	divider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	divider.custom_minimum_size.x = 490 * unit
	for index in 3:
		if index == 1:
			var mark := TextureRect.new()
			var mountain := AtlasTexture.new()
			mountain.atlas = UtilityArt.icon("mountain")
			mountain.region = Rect2(2,26,124,70)
			mark.texture = mountain
			mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			mark.custom_minimum_size = Vector2(82, 20) * unit
			divider.add_child(mark)
		else:
			var line := ColorRect.new()
			line.color = Color("8ba6bd")
			line.custom_minimum_size = Vector2(201 * unit, maxf(1.0, unit))
			line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			divider.add_child(line)
	section.add_child(_journal_label(title, roundi(30 * unit)))
	var text := _journal_label(body, roundi(22 * unit))
	text.add_theme_font_override("font", UITheme.ui_font())
	text.add_theme_color_override("font_color", ExpeditionMenuStyle.INK_MUTED)
	section.add_child(text)


func _show_licenses() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Open-source licenses"
	dialog.ok_button_text = "Close"
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	var text := TextEdit.new()
	text.editable = false
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text.text = "Studio: " + NINJA_URL + "\n\n" + Engine.get_license_text()
	for font_license: String in ["res://assets/fonts/LilitaOne-OFL.txt",
			"res://assets/fonts/AtkinsonHyperlegibleNext-OFL.txt"]:
		text.text += "\n\n" + FileAccess.get_file_as_string(font_license)
	text.custom_minimum_size = get_viewport_rect().size * Vector2(0.78, 0.65)
	dialog.add_child(text)
	add_child(dialog)
	dialog.popup_centered()


func _back() -> void:
	SceneRouter.go_back()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		_back()
