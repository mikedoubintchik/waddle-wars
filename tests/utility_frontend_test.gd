extends Node
## Structural and runtime contract for premium utility screens.

const SCREEN_SCENES: Dictionary = {
	"achievements": "res://scenes/menus/achievements.tscn",
	"settings": "res://scenes/menus/settings.tscn",
	"leaderboard": "res://scenes/menus/leaderboard.tscn",
	"controls": "res://scenes/menus/controls.tscn",
	"credits": "res://scenes/menus/credits.tscn",
}
const OWNED_SCRIPTS: PackedStringArray = [
	"res://scripts/ui/achievements_menu.gd",
	"res://scripts/ui/settings_menu.gd",
	"res://scripts/ui/leaderboard_menu.gd",
	"res://scripts/ui/controls_menu.gd",
	"res://scripts/ui/credits_menu.gd",
	"res://scripts/ui/pause_menu.gd",
	"res://scripts/ui/utility_screen_layout.gd",
]
const FORBIDDEN_RENDER_NODES: PackedStringArray = [
	"SubViewport", "Node3D", "GPUParticles", "CPUParticles",
]

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	_check_geometry_contract()
	_check_source_contract()
	await _check_live_rotation_contract()
	await _check_runtime_screens()
	await _check_pause_overlay()
	print("[utility-frontend] DONE: %d/%d checks passed" % [
		_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)


func _check_geometry_contract() -> void:
	var matrix: Array[Dictionary] = [
		{"size": Vector2(540, 960), "insets": Vector4(24, 36, 24, 34), "portrait": true},
		{"size": Vector2(1080, 1920), "insets": Vector4(28, 52, 28, 42), "portrait": true},
		{"size": Vector2(960, 540), "insets": Vector4(20, 18, 20, 18), "portrait": false},
		{"size": Vector2(1920, 1080), "insets": Vector4.ZERO, "portrait": false},
		{"size": Vector2(2400, 1080), "insets": Vector4(44, 18, 44, 18), "portrait": false},
		{"size": Vector2(1600, 1200), "insets": Vector4.ZERO, "portrait": false},
	]
	for item: Dictionary in matrix:
		var size: Vector2 = item["size"]
		var profile := LayoutProfile.for_view_size(size, item["insets"])
		var width := UtilityScreenLayout.page_width(profile, 1180.0, 300.0)
		_check(width <= profile.safe_rect.size.x + 0.001,
			"page stays inside safe width at %dx%d" % [size.x, size.y])
		_check(width >= minf(300.0, profile.safe_rect.size.x) - 0.001,
			"page keeps usable minimum at %dx%d" % [size.x, size.y])
		_check(UtilityScreenLayout.uses_stacked_rows(profile) == bool(item["portrait"]),
			"row composition matches orientation at %dx%d" % [size.x, size.y])
	var target := Button.new()
	UtilityScreenLayout.enforce_target(target)
	_check(target.custom_minimum_size.y >= UtilityScreenLayout.MIN_TOUCH_TARGET,
		"shared target floor is at least 44px")
	target.free()
	var wide := LayoutProfile.for_view_size(Vector2(1700, 900))
	var inset_compact := LayoutProfile.for_view_size(
		Vector2(1700, 900), Vector4(160, 70, 160, 70))
	_check(wide.view_class == LayoutProfile.ViewClass.LANDSCAPE_WIDE \
		and inset_compact.view_class == LayoutProfile.ViewClass.LANDSCAPE_COMPACT,
		"extreme safe insets downgrade wide landscape composition")
	var tablet := LayoutProfile.for_view_size(Vector2(1000, 1400))
	var inset_phone := LayoutProfile.for_view_size(
		Vector2(1000, 1400), Vector4(70, 20, 70, 20))
	_check(tablet.view_class == LayoutProfile.ViewClass.PORTRAIT_TABLET \
		and inset_phone.view_class == LayoutProfile.ViewClass.PORTRAIT_NARROW,
		"extreme safe insets downgrade portrait tablet composition")


func _check_live_rotation_contract() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 540)
	add_child(viewport)
	var host := Control.new()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(host)
	var compositions: Array[bool] = []
	var initial := UtilityScreenLayout.bind_view_class(host,
		func(profile: LayoutProfile) -> void:
			compositions.append(UtilityScreenLayout.uses_stacked_rows(profile)))
	_check(not UtilityScreenLayout.uses_stacked_rows(initial),
		"live reflow starts in landscape composition")
	viewport.size = Vector2i(540, 960)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(compositions.size() == 1 and compositions[0],
		"landscape-to-portrait rotation rebuilds stacked composition once")
	viewport.size = Vector2i(960, 540)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(compositions.size() == 2 and not compositions[1],
		"portrait-to-landscape rotation rebuilds split composition once")
	viewport.queue_free()
	await get_tree().process_frame


func _check_source_contract() -> void:
	for path: String in OWNED_SCRIPTS:
		_check(FileAccess.file_exists(path), "%s exists" % path.get_file())
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var source := file.get_as_text()
		_check("UtilityScreenLayout" in source,
			"%s consumes shared utility contract" % path.get_file())
		if not path.ends_with("utility_screen_layout.gd"):
			_check("bind_view_class" in source,
				"%s rebuilds on live orientation class change" % path.get_file())
		for token: String in FORBIDDEN_RENDER_NODES:
			var executable := false
			for line: String in source.split("\n"):
				var trimmed := line.strip_edges()
				if not trimmed.begins_with("#") and token in trimmed:
					executable = true
					break
			_check(not executable, "%s has no executable %s" % [path.get_file(), token])
	var settings := FileAccess.get_file_as_string(
		"res://scripts/ui/settings_menu.gd")
	_check("canvas %d" not in settings and "3D %d%%" not in settings,
		"settings omits renderer diagnostics from player UI")
	var credits := FileAccess.get_file_as_string(
		"res://scripts/ui/credits_menu.gd")
	_check("OpenAI ImageGen" in credits and "Blender" in credits \
		and "ATTRIBUTION.md" in credits \
		and "All art, audio and code are original" not in credits,
		"credits carries accurate authored/generated-art disclosure")


func _check_runtime_screens() -> void:
	var old_reduced := bool(SettingsManager.get_setting(
		"accessibility", "reduced_flashing"))
	SettingsManager.set_setting("accessibility", "reduced_flashing", true)
	for label: String in SCREEN_SCENES:
		var packed := load(String(SCREEN_SCENES[label])) as PackedScene
		_check(packed != null, "%s scene loads" % label)
		if packed == null:
			continue
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1920, 1080)
		add_child(viewport)
		var screen := packed.instantiate()
		viewport.add_child(screen)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(_count_type(screen, "FrontEndBackdrop") == 1,
			"%s owns one authored backdrop" % label)
		_check(_find_first_kind(screen, &"scroll") != null,
			"%s owns scroll-safe content" % label)
		_check(_find_first_kind(screen, &"panel") != null,
			"%s owns expedition card hierarchy" % label)
		_check(_visible_fullscreen_passes(screen) <= 3,
			"%s uses <=3 visible full-screen passes" % label)
		_check(_first_short_button(screen) == null,
			"%s visible buttons meet 44px floor%s" % [label,
			"" if _first_short_button(screen) == null else \
				" (%s)" % _first_short_button(screen).name])
		_check(_screen_composition(screen, label) == "split",
			"%s starts with landscape-specific split composition" % label)
		viewport.size = Vector2i(540, 960)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(_screen_composition(screen, label) == "stacked",
			"%s reflows live to portrait stacked composition" % label)
		_check(_count_type(screen, "FrontEndBackdrop") == 1,
			"%s rotation does not duplicate backdrop" % label)
		_check(_first_short_button(screen) == null,
			"%s portrait reflow keeps 44px buttons" % label)
		viewport.size = Vector2i(1920, 1080)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(_screen_composition(screen, label) == "split",
			"%s reflows live back to landscape split composition" % label)
		viewport.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	SettingsManager.set_setting("accessibility", "reduced_flashing", old_reduced)


func _check_pause_overlay() -> void:
	var restore_mode := process_mode
	process_mode = Node.PROCESS_MODE_ALWAYS
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	add_child(viewport)
	var menu := PauseMenu.new()
	viewport.add_child(menu)
	await get_tree().process_frame
	menu.toggle()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(menu._panel != null and get_tree().paused,
		"pause overlay opens over frozen gameplay")
	_check(_find_named(menu, &"PauseExpeditionCard") != null,
		"pause owns expedition card")
	_check(_find_first_kind(menu, &"scroll") != null,
		"pause is short-screen scroll safe")
	_check(_visible_fullscreen_passes(menu) <= 3,
		"pause uses <=3 visible full-screen passes")
	_check(_first_short_button(menu) == null,
		"pause visible buttons meet 44px floor")
	viewport.size = Vector2i(540, 960)
	await get_tree().process_frame
	await get_tree().process_frame
	var portrait_profile := menu.get("_profile") as LayoutProfile
	_check(portrait_profile != null and portrait_profile.is_portrait(),
		"pause rebuilds live into portrait composition")
	_check(_find_named(menu, &"PauseExpeditionCard") != null,
		"pause rotation preserves expedition card")
	menu.toggle()
	await get_tree().process_frame
	viewport.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	process_mode = restore_mode


func _screen_composition(screen: Node, label: String) -> String:
	var profile := screen.get("_profile") as LayoutProfile
	if profile == null:
		return "unknown"
	match label:
		"achievements", "leaderboard":
			return "stacked" if bool(screen.get("_stacked")) else "split"
		"settings", "controls":
			return "stacked" if bool(screen.get("_compact")) else "split"
		"credits":
			return "stacked" if profile.is_portrait() else "split"
	return "unknown"


func _first_short_button(node: Node) -> BaseButton:
	if node is BaseButton:
		var button := node as BaseButton
		if button.is_visible_in_tree() and button.size.y + 0.5 \
				< UtilityScreenLayout.MIN_TOUCH_TARGET:
			return button
	for child: Node in node.get_children():
		var found := _first_short_button(child)
		if found != null:
			return found
	return null


func _visible_fullscreen_passes(node: Node) -> int:
	var count := 0
	if node is FrontEndBackdrop and (node as CanvasItem).is_visible_in_tree():
		count += 1
	elif node is ColorRect and (node as ColorRect).is_visible_in_tree():
		var rect := node as ColorRect
		var view := rect.get_viewport().get_visible_rect().size
		if rect.size.x >= view.x * 0.95 and rect.size.y >= view.y * 0.95:
			count += 1
	for child: Node in node.get_children():
		count += _visible_fullscreen_passes(child)
	return count


func _count_type(node: Node, class_text: String) -> int:
	var count := 1 if (node.get_class() == class_text \
		or (class_text == "FrontEndBackdrop" and node is FrontEndBackdrop)) else 0
	for child: Node in node.get_children():
		count += _count_type(child, class_text)
	return count


func _find_first_kind(node: Node, kind: StringName) -> Node:
	if (kind == &"scroll" and node is ScrollContainer) \
			or (kind == &"panel" and node is PanelContainer):
		return node
	for child: Node in node.get_children():
		var found := _find_first_kind(child, kind)
		if found != null:
			return found
	return null


func _find_named(node: Node, wanted: StringName) -> Node:
	if node.name == wanted:
		return node
	for child: Node in node.get_children():
		var found := _find_named(child, wanted)
		if found != null:
			return found
	return null


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("[utility-frontend] PASS %s" % message)
	else:
		_failures += 1
		print("[utility-frontend] FAIL %s" % message)
