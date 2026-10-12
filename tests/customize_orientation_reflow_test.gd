extends Node
## Focused live-rotation check. Uses the suite's isolated user:// snapshot.

var _checks: int = 0
var _failed: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var window := get_tree().root
	var original_size := window.size
	var equipped_before := Progression.get_equipped("body")
	window.size = Vector2i(540, 960)
	await _frames(4)
	var menu := load("res://scenes/menus/customize.tscn").instantiate() as Control
	window.add_child(menu)
	await _frames(4)
	# Reproduce a card retired before its initial deferred mask layout runs.
	# This used to dereference freed lambda captures during rapid navigation.
	var retired_card := menu.call("_make_item_tile", "body_classic") as Button
	var retired_icon := retired_card.find_child("ItemPortrait", true, false) as TextureRect
	var retired_mask := retired_icon.material as ShaderMaterial
	retired_mask.set_shader_parameter("card_size", Vector2(13.0, 17.0))
	retired_card.free()
	await _frames(2)
	_check(retired_mask.get_shader_parameter("card_size") == Vector2(13.0, 17.0),
		"retired portrait card cancels pending mask updates")
	_check(_fixed_stage(menu) != null,
		"portrait keeps selected penguin outside wardrobe scroll")
	var name_plate := menu.find_child("OutfitNamePlate", true, false) as Control
	var equip_action := menu.find_child("OutfitEquipAction", true, false) as Button
	_check(name_plate != null and equip_action != null and not name_plate.is_ancestor_of(equip_action),
		"reference name pill and coral action are separate sibling surfaces")
	_check(equip_action.get_global_rect().position.y < name_plate.get_global_rect().end.y
		and equip_action.get_global_rect().end.y > name_plate.get_global_rect().end.y,
		"portrait action overlaps lower edge of name pill and extends below it")
	_check(equip_action.get_theme_color("font_disabled_color") == Color.WHITE,
		"equipped state retains white-on-coral reference treatment")
	_check(menu.find_children("CategoryDivider", "ColorRect", true, false).size() == 4,
		"five category controls have four reference dividers")
	_check(_wardrobe_scroll(menu) != null and _wardrobe_scroll(menu).is_ancestor_of(
		menu.get("_item_grid") as GridContainer),
		"portrait categories and purchasable choices live in wardrobe scroll")
	var body_tab := (menu.get("_tab_buttons") as Dictionary).get("body") as Button
	var active := body_tab.get_theme_stylebox("pressed")
	_check(active != null and not active is StyleBoxEmpty,
		"selected category has visible reference material")
	_check(body_tab.get_global_rect().size.y >= 50.0,
		"portrait category has full touch height")
	var category_scroll := menu.find_child("WardrobeCategoryScroll", true, false) as Control
	var trail_tab := (menu.get("_tab_buttons") as Dictionary)["trail"] as Button
	_check(category_scroll.get_global_rect().grow(1).encloses(trail_tab.get_global_rect()),
		"all five category tabs fit the shelf at normal text scale")
	_check(category_scroll.size.y <= trail_tab.size.y + 4.0,
		"category shelf hugs its controls without blank space pushing cards below fold")
	_check_selection_bounds(menu)
	_check_reference_insets(menu)
	menu.call("_select_category", "trail")
	await _frames(3)
	var snow := menu.call("_tile_for_id", "trail_snowflake") as Button
	var snow_icon := snow.find_child("ItemPortrait", true, false) as TextureRect
	_check(snow_icon.material == null and snow_icon.texture == TrailEffect._particle_texture("trail_snowflake"),
		"snowflake card uses the same complete illustrated particle as preview/gameplay")
	var trail_surface := trail_tab.get_theme_stylebox("pressed")
	_check(trail_surface.get("category") == "trail" and not body_tab.button_pressed,
		"last category uses mirrored end cap and retires first-category selection")
	_check_selection_bounds(menu)
	_check_reference_insets(menu)
	menu.call("_select_category", "body")
	await _frames(3)
	var pages := menu.find_child("WardrobePages", true, false) as Control
	_check(pages != null and get_viewport().get_visible_rect().grow(1).encloses(pages.get_global_rect()),
		"normal portrait fits complete gallery and page dots before scrolling")
	for tab: Button in (menu.get("_tab_buttons") as Dictionary).values():
		for child_name: String in ["CategoryIcon", "CategoryLabel"]:
			var content := tab.find_child(child_name, true, false) as Control
			_check(content != null and tab.get_global_rect().grow(1).encloses(content.get_global_rect()),
				"portrait %s %s stays inside its button" % [tab.name, child_name])
	var fish := menu.find_child("FishBalance", true, false) as PanelContainer
	_check(fish != null and fish.find_child("FishAmount", true, false) != null,
		"penguins uses the shared icon-plus-number fish pill")
	var amount := fish.find_child("FishAmount", true, false) as Label
	var title := menu.find_child("PenguinsReferenceTitle", true, false) as Control
	for total: int in [161, 850, 38290, 9999999]:
		menu.call("_update_fish_label", total)
		await _frames(3)
		_check(amount.is_visible_in_tree() and not amount.text.is_empty(), "phone balance remains visible for %d fish" % total)
		_check(fish.get_global_rect().grow(1).encloses(amount.get_global_rect()), "compact balance stays in currency cap")
		_check(not fish.get_global_rect().intersects(title.get_global_rect()), "currency cap remains separate from title")
		_check(fish.accessibility_name == "%s fish" % ExpeditionMenuStyle.grouped_amount(total), "compact balance exposes exact amount accessibly")
	menu.call("_update_fish_label", Progression.get_fish())
	_check(menu.get("_penguin") == null and menu.get("_outfit_stage") != null,
		"wardrobe owns finished image stage, no3D penguin")
	_check(menu.find_child("LiveOutfitToggle", true, false) == null,
		"live preview does not require a second try-on page")
	menu.call("_select_category", "scarf")
	var scarf_tile := menu.call("_tile_for_id", "scarf_red") as Button
	scarf_tile.pressed.emit()
	await _frames(3)
	_check(String((menu.get("_try_on_loadout") as Dictionary).get("scarf")) == "scarf_red",
		"selected scarf enters temporary complete outfit before purchase")
	_check(Progression.get_equipped("scarf") != "scarf_red",
		"tile try-on does not silently equip locked clothing")
	menu.call("_select_category", "body")
	var hero := menu.find_child("FinishedWardrobePreview", true, false) as Control
	var choices := CosmeticsDB.items_in_category("body")
	var selected := String(choices[1])
	menu.call("_select_item", selected)
	_check((menu.get("_previewed_equipped") as Dictionary).get("body") == selected,
		"species selection changes the finished outfit key")
	var draft_before := (menu.get("_try_on_loadout") as Dictionary).duplicate(true)
	var library_before: Node = menu.get("_outfit_library")
	window.size = Vector2i(960, 540)
	await _frames(6)
	_check(_fixed_stage(menu) == null,
		"short landscape keeps complete wardrobe scrollable")
	_check(not _wardrobe_scroll(menu).is_ancestor_of(
		menu.find_child("FinishedWardrobePreview", true, false)),
		"landscape hero uses the open left stage beside scrollable controls")
	_check(menu.find_child("PreviousPenguins", true, false) != null and menu.find_child("NextPenguins", true, false) != null,
		"landscape keeps both gallery navigation controls")
	_check(String(menu.get("_selected_id")) == selected, "try-on survives portrait to landscape")
	_check_selection_bounds(menu)
	_check_reference_insets(menu)
	_check(menu.get("_try_on_loadout") == draft_before and menu.get("_outfit_library") == library_before,
		"rotation preserves every draft slot and one bounded library")
	for tile: Button in (menu.get("_item_grid") as GridContainer).get_children():
		var badge := tile.find_child("ItemStatusBadge", true, false) as Control
		_check(badge != null and tile.get_global_rect().grow(1).encloses(
			badge.get_global_rect()), "landscape ownership/price badge fits inside its item card")
	window.size = Vector2i(540, 960)
	await _frames(6)
	_check(_fixed_stage(menu) != null,
		"live portrait restores fixed penguin stage")
	_check(_fixed_stage(menu).is_ancestor_of(
		menu.find_child("FinishedWardrobePreview", true, false)),
		"portrait hero does not scroll with options")
	_check(menu.find_children("FinishedWardrobePreview", "Control", true, false).size() == 1,
		"portrait round trip keeps exactly one finished outfit preview")
	_check(String(menu.get("_selected_id")) == selected, "try-on survives round trip")
	_check(menu.get("_try_on_loadout") == draft_before, "all temporary outfit slots survive round trip")
	_check(menu.find_children("Back", "Button", true, false).size() == 1,
		"orientation rebuild owns and retires old Back controls")
	for tile: Button in (menu.get("_item_grid") as GridContainer).get_children():
		var badge := tile.find_child("ItemStatusBadge", true, false) as Control
		_check(badge != null and tile.get_global_rect().grow(1).encloses(
			badge.get_global_rect()), "ownership/price badge fits inside its item card")
	# Match actual Chrome logical layouts, including the touch UI scale.
	var force_touch_before := GameConfig.force_touch
	var insets_before := LayoutProfile.forced_insets
	for shape: Vector2i in [Vector2i(800, 1422), Vector2i(1920, 1080)]:
		GameConfig.force_touch = shape.y > shape.x
		LayoutProfile.forced_insets = Vector4(24, 24, 24, 24) if GameConfig.force_touch else Vector4.ZERO
		window.size = shape
		await _frames(6)
		menu.call("_select_category", "trail")
		await _frames(4)
		_check_reference_insets(menu)
		_check_selection_bounds(menu)
	GameConfig.force_touch = force_touch_before
	LayoutProfile.forced_insets = insets_before
	_check(Progression.get_equipped("body") == equipped_before,
		"rotation and try-on do not change equipped save")
	menu.queue_free()
	active = null
	hero = null
	await _frames(3)
	window.size = original_size
	# The menu focuses its selected category on each rebuild. Stop those brief
	# focus sounds before the isolated headless process exits; otherwise Godot's
	# audio backend reports live playback resources after every assertion passes.
	for player: AudioStreamPlayer in AudioManager._sfx_pool:
		player.stop()
		player.stream = null
	# Dummy/headless audio releases pending playback on its mixer clock, not
	# after two uncapped visual frames. Retain the real hover-sound path.
	await get_tree().create_timer(0.25).timeout
	await _frames(3)
	print("[customize-orientation] %d/%d passed" % [_checks - _failed, _checks])
	get_tree().quit(0 if _failed == 0 else 1)


func _fixed_stage(menu: Control) -> VBoxContainer:
	return menu.find_child("FixedPenguinStage", true, false) as VBoxContainer


func _check_selection_bounds(menu: Control) -> void:
	var grid := menu.get("_item_grid") as GridContainer
	var scroll := menu.find_child("WardrobeGalleryScroll", true, false) as ScrollContainer
	var selected_count := 0
	for index: int in grid.get_child_count():
		var tile := grid.get_child(index) as Control
		var rim := tile.get_node("EquippedRim") as Panel
		var style := rim.get_theme_stylebox("panel")
		if style.get("selected"):
			selected_count += 1
			_check(String(tile.get_meta("cosmetic_id")) == String(menu.get("_selected_id")),
				"coral outline belongs to current preview, independent of owned/equipped state")
		if index < 3:
			var halo := float(style.call("glow_padding", tile.size))
			_check(scroll.get_global_rect().grow(1).encloses(tile.get_global_rect().grow(halo)),
				"first three choice halos fit inside their scroll viewport")
		_check(tile.get_child(tile.get_child_count() - 1) == rim,
			"selection outline paints above thumbnail content")
	_check(selected_count == 1, "exactly one preview outline remains selected")


func _wardrobe_scroll(menu: Control) -> ScrollContainer:
	return menu.find_child("ExpeditionContentScroll", true, false) as ScrollContainer


func _check_reference_insets(menu: Control) -> void:
	var shelf := menu.find_child("WardrobeCategoryShelf", true, false) as Control
	var enclosure := menu.find_child("WardrobeEnclosure", true, false) as Control
	var outer := shelf.get_global_rect() if enclosure == null else enclosure.get_global_rect()
	for tab: Button in (menu.get("_tab_buttons") as Dictionary).values():
		var bounds := tab.get_global_rect()
		_check(outer.encloses(bounds) and bounds.position.y - outer.position.y >= bounds.size.y * 0.07,
			"%s has a real ivory gutter above its selected surface" % tab.name)
		for child_name: String in ["CategoryIcon", "CategoryLabel"]:
			var child := tab.find_child(child_name, true, false) as Control
			_check(bounds.grow(1).encloses(child.get_global_rect()),
				"%s %s enclosed after responsive tab sizing" % [tab.name, child_name])
	var footer := menu.find_child("TryOnFooter", true, false) as Control
	var footer_rect := footer.get_global_rect()
	_check(get_viewport().get_visible_rect().encloses(footer_rect), "entire try-on plate stays visible")
	var dots := menu.find_child("WardrobePages", true, false) as Control
	_check(get_viewport().get_visible_rect().encloses(dots.get_global_rect()), "complete page-dot container stays onscreen")
	_check(dots.get_global_rect().end.y <= footer_rect.position.y, "page dots leave clearance before footer")
	for dot: Control in dots.get_children():
		if not dot.is_queued_for_deletion():
			_check(dots.get_global_rect().grow(1).encloses(dot.get_global_rect()), "complete circular dot enclosed by pagination row")
	if _fixed_stage(menu) != null:
		_check(not _wardrobe_scroll(menu).is_ancestor_of(footer), "phone footer cannot be clipped by choices scroller")
		_check(not _wardrobe_scroll(menu).is_ancestor_of(dots), "phone page dots cannot be clipped by choices scroller")
		var carousel := menu.find_child("WardrobeCarousel", true, false) as Control
		_check(_wardrobe_scroll(menu).get_global_rect().grow(1).encloses(carousel.get_global_rect()), "entire phone carousel clears outer scroll edge above pagination")
		_check(carousel.get_global_rect().end.y <= dots.get_global_rect().position.y, "phone cards and halo leave clearance before page dots")
	for child: Control in [menu.get("_try_on_note"), menu.get("_reset_try_on_button"),
			menu.find_child("TryOnHanger", true, false)]:
		_check(footer_rect.encloses(child.get_global_rect()), "try-on footer encloses %s" % child.name)
	var grid := menu.get("_item_grid") as GridContainer
	for tile: Control in grid.get_children():
		var image := tile.find_child("ItemPortrait", true, false) as TextureRect
		_check(tile.get_global_rect().grow(1).encloses(image.get_global_rect()),
			"thumbnail remains inside card after selection-ring content inset")


func _frames(count: int) -> void:
	for _i: int in count:
		await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failed += 1
		push_error("[customize-orientation] " + message)
