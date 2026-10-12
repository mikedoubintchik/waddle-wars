extends Node
## Live state regression for illustrated menus. Raster fidelity checked separately.

class OfflineShop:
	extends PremiumCosmeticShop
	func _ready() -> void:
		UITheme.apply_ui_scale(self)
		_client = null
		_build()
		_update()

var _passes := 0
var _failures := 0

func _ready() -> void:
	SettingsManager.set_setting("accessibility", "reduced_flashing", true)
	for viewport_size: Vector2i in [Vector2i(800, 1422), Vector2i(1920, 1080)]:
		var viewport := SubViewport.new()
		viewport.size = viewport_size
		add_child(viewport)
		var shop := OfflineShop.new()
		viewport.add_child(shop)
		await get_tree().process_frame
		_check(shop._selector_buttons.size() == CommerceCatalog.products().size(), "every real product keeps a selector")
		for product: Dictionary in CommerceCatalog.products():
			var id := String(product["id"])
			shop._select_product(id)
			var shown := 0
			for card: Control in shop._detail_cards.values():
				shown += int(card.visible)
			_check(shown == 1 and (shop._detail_cards[id] as Control).visible, "selected product owns exactly one detail")
			_check(shop._selected_banner.text == String(product["name"]).to_upper(), "banner shows actual catalogue name")
			_check((shop._buttons[id] as Button).disabled and (shop._price_labels[id] as Label).text == "Price unavailable", "unavailable provider never invents price or enables purchase")
		shop.free()
		var achievements := load("res://scenes/menus/achievements.tscn").instantiate() as Control
		viewport.add_child(achievements)
		await get_tree().process_frame
		_check(achievements._achievement_buttons.size() == AchievementsDB.RUNNER_ORDER.size() + _earned_legacy(), "every real achievement retained")
		for id: String in AchievementsDB.RUNNER_ORDER:
			achievements._select_achievement(id)
			_check(achievements._selected_id == id and _has_text(achievements._detail, String(AchievementsDB.get_item(id)["desc"])), "selected achievement shows authoritative description: " + id)
		_check(_three_columns(achievements) == (3 if _earned_legacy() > 0 else 2), "both badge groups keep three columns")
		achievements.free()
		var credits := load("res://scenes/menus/credits.tscn").instantiate() as Control
		viewport.add_child(credits)
		await get_tree().process_frame
		var back := credits.find_child("CreditsIllustratedBack", true, false) as Button
		var licenses := _button(credits, "LICENSES")
		_check(back != null and licenses != null and not _under_scroll(back) and not _under_scroll(licenses), "credits footer reachable independently of journal scroll")
		_check(_has_text(credits, "Lilita One · Juan Montoreano\nAtkinson Hyperlegible Next · Braille Institute\nSIL Open Font License 1.1"), "font attribution preserved")
		credits.free()
		var controls := load("res://scenes/menus/controls.tscn").instantiate() as Control
		viewport.add_child(controls)
		await get_tree().process_frame
		_check(controls._binding_buttons.size() == SettingsManager.REMAPPABLE_ACTIONS.size() * 2, "every real action remains remappable for keyboard and pad")
		for action: String in SettingsManager.REMAPPABLE_ACTIONS:
			_check(controls.find_child("ActionIcon_" + action, true, false) != null, "action art exists: " + action)
			for family: String in ["key", "joy"]:
				var key := "%s/%s" % [action, family]
				var cap: Button = controls._binding_buttons[key]
				_check(cap.tooltip_text == SettingsManager.describe_action_binding(action, family) and cap.accessibility_name.ends_with(SettingsManager.describe_action_binding(action, family)), "keycap shows actual binding: " + key)
		controls._begin_capture("jump", "key")
		_check(controls._capture_overlay.visible and controls._capturing_action == "jump", "styled keycap still enters capture")
		controls._end_capture()
		_check(not controls._capture_overlay.visible and controls._capturing_action.is_empty(), "capture cancel remains safe")
		controls.free()
		viewport.free()
	# Let the audio thread retire headless focus-hover playback before exit.
	for player: AudioStreamPlayer in AudioManager._sfx_pool:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.08).timeout
	print("[menu_fidelity] DONE: %d passed, %d failed" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)

func _check(passed: bool, label: String) -> void:
	if passed: _passes += 1
	else: _failures += 1
	print("[menu_fidelity] %s %s" % ["PASS" if passed else "FAIL", label])

func _has_text(node: Node, text: String) -> bool:
	if node is Label and node.text == text: return true
	for child: Node in node.get_children():
		if _has_text(child, text): return true
	return false

func _button(node: Node, text: String) -> Button:
	if node is Button and node.text == text: return node
	for child: Node in node.get_children():
		var found := _button(child, text)
		if found != null: return found
	return null

func _under_scroll(node: Node) -> bool:
	var parent := node.get_parent()
	while parent != null:
		if parent is ScrollContainer: return true
		parent = parent.get_parent()
	return false

func _three_columns(node: Node) -> int:
	var count := 1 if node is GridContainer and node.columns == 3 else 0
	for child: Node in node.get_children(): count += _three_columns(child)
	return count

func _earned_legacy() -> int:
	var count := 0
	for id: String in AchievementsDB.LEGACY_ORDER:
		if Progression.is_achievement_unlocked(id): count += 1
	return count
