extends Node
## Audits every menu at phone window sizes and fails on content a thumb cannot
## reach.
##
## "The menus are cut off or not scrollable" is a layout claim, and layout
## claims are checkable: open each menu at a real phone size, walk its Control
## tree, and find anything that sits outside the visible rect. An element
## outside the rect is only acceptable if some ancestor ScrollContainer can
## actually bring it into view — otherwise it is unreachable, which is the bug.
##
## MUST RUN WITH A WINDOW, and the window is really resized for each device.
## An earlier version of this harness measured menus inside a SubViewport and
## reported failures that did not exist: these screens size themselves from the
## window (content scale, UI scale boost, safe area), so a SubViewport at
## 800x1422 inside a 1600x900 window lays out against neither one. It flagged
## the leaderboard's tab grid and the settings Back button as unreachable while
## real portrait captures showed both comfortably on screen. Measuring the real
## thing is the only version of this test worth having.
##
##   godot --path . --resolution 390x844 res://tests/mobile_ui_audit.tscn
##   godot --path . res://tests/mobile_ui_audit.tscn -- size=360x640
##
## Exits 1 if any menu has unreachable content.

## Apple's HIG and Material both land at 44-48 px; 44 is the forgiving floor.
const MIN_TOUCH_PX: float = 44.0
## Sub-pixel overhang is rounding, not a defect.
const EDGE_TOLERANCE: float = 1.5

const SCENES: Array[Dictionary] = [
	{"name": "main_menu", "path": "res://scenes/menus/main_menu.tscn"},
	{"name": "mode_select", "path": "res://scenes/menus/mode_select.tscn"},
	{"name": "settings", "path": "res://scenes/menus/settings.tscn"},
	{"name": "customize", "path": "res://scenes/menus/customize.tscn"},
	{"name": "achievements", "path": "res://scenes/menus/achievements.tscn"},
	{"name": "leaderboard", "path": "res://scenes/menus/leaderboard.tscn"},
	{"name": "credits", "path": "res://scenes/menus/credits.tscn"},
	# Reachable from Settings > Key Bindings, and it had the same off-screen
	# Back defect as the rest, so it belongs in the audit.
	{"name": "controls", "path": "res://scenes/menus/controls.tscn"},
	{"name": "results", "path": "res://scenes/menus/results.tscn"},
]

## PHYSICAL device sizes in CSS pixels. These are converted to the logical
## viewport the menus actually lay out in before anything is measured — see
## _logical_size(). Auditing raw device pixels would be meaningless: with
## canvas_items stretch the game never sees them.
var _devices: Array[Vector2i] = [
	Vector2i(360, 640),   # small Android portrait
	Vector2i(390, 844),   # iPhone 14 portrait
	Vector2i(844, 390),   # the same phone rotated
]
var _sizes: Array[Vector2i] = []

var _failures: PackedStringArray = PackedStringArray()
var _warnings: PackedStringArray = PackedStringArray()


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("size="):
			var parts := arg.trim_prefix("size=").split("x")
			if parts.size() == 2:
				_devices = [Vector2i(int(parts[0]), int(parts[1]))]
	if GameConfig.is_headless():
		print("[mobile-ui] SKIP — needs a window; menus size themselves from it")
		get_tree().quit(0)
		return
	# Force touch before anything lays out. SettingsManager applies a 1.35 UI
	# boost on touch devices by shrinking content_scale_size, so a phone lays
	# out on an ~800-wide canvas while the same window without touch reports
	# 1080. Auditing the 1080 canvas measures a screen no phone ever sees.
	GameConfig.force_touch = true
	SettingsManager.apply_all()
	_sizes = _devices.duplicate()
	await _run()


func _run() -> void:
	for size: Vector2i in _sizes:
		for entry: Dictionary in SCENES:
			await _audit(String(entry["name"]), String(entry["path"]), size)
	print("")
	for warning: String in _warnings:
		print("[mobile-ui] WARN  %s" % warning)
	if _failures.is_empty():
		print("[mobile-ui] PASS — every menu's content is reachable at %d sizes" % _sizes.size())
		get_tree().quit(0)
		return
	for failure: String in _failures:
		print("[mobile-ui] FAIL  %s" % failure)
	print("[mobile-ui] %d unreachable-content failures" % _failures.size())
	get_tree().quit(1)


func _audit(scene_name: String, path: String, size: Vector2i) -> void:
	if not ResourceLoader.exists(path):
		_failures.append("%s: scene missing at %s" % [scene_name, path])
		return
	# Resize the real window, then let the engine settle: content_scale_size is
	# recomputed on resize by SettingsManager, and the menus rebuild from it.
	DisplayServer.window_set_size(size)
	await get_tree().process_frame
	await get_tree().process_frame
	var scene: PackedScene = load(path)
	var instance := scene.instantiate()
	get_tree().root.add_child(instance)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var rect := get_tree().root.get_visible_rect()
	var offenders: Array[Dictionary] = []
	_walk(instance, rect, offenders)
	var label := "%s @ device %dx%d (canvas %dx%d)" % [
		scene_name, size.x, size.y, rect.size.x, rect.size.y]
	for offender: Dictionary in offenders:
		var control: Control = offender["control"]
		if String(offender["reason"]) == "touch":
			_warnings.append("%s: %s is %.0f units tall (min %.0f)"
				% [label, _describe(control), control.get_global_rect().size.y, MIN_TOUCH_PX])
			continue
		_failures.append("%s: %s at %s is outside the canvas and no ancestor can scroll to it"
			% [label, _describe(control), control.get_global_rect()])
	if offenders.is_empty():
		print("[mobile-ui] ok    %s" % label)
	instance.queue_free()
	await get_tree().process_frame


func _walk(node: Node, rect: Rect2, offenders: Array[Dictionary]) -> void:
	var control := node as Control
	if control != null and control.is_visible_in_tree():
		var global := control.get_global_rect()
		if _is_interactive(control) and global.size.x > 0.0 and global.size.y > 0.0:
			# Only leaf-ish interactive controls are judged: a container that
			# spills is fine as long as its children are reachable.
			if not _within(global, rect) and not _scrollable_ancestor(control):
				offenders.append({"control": control, "reason": "clipped"})
			elif global.size.y < MIN_TOUCH_PX and _within(global, rect):
				offenders.append({"control": control, "reason": "touch"})
	for child: Node in node.get_children():
		_walk(child, rect, offenders)


func _within(global: Rect2, rect: Rect2) -> bool:
	return global.position.x >= rect.position.x - EDGE_TOLERANCE \
		and global.position.y >= rect.position.y - EDGE_TOLERANCE \
		and global.end.x <= rect.end.x + EDGE_TOLERANCE \
		and global.end.y <= rect.end.y + EDGE_TOLERANCE


## True when some ancestor is a ScrollContainer that can actually move this
## control into view. A ScrollContainer with scrolling disabled on the axis
## that overflows does not count — that is precisely the "not scrollable"
## complaint.
func _scrollable_ancestor(control: Control) -> bool:
	var parent := control.get_parent()
	while parent != null:
		var scroll := parent as ScrollContainer
		if scroll != null:
			var content_size := Vector2.ZERO
			for child: Node in scroll.get_children():
				var child_control := child as Control
				if child_control != null and child_control.is_visible_in_tree():
					content_size = content_size.max(child_control.get_combined_minimum_size())
			var view := scroll.size
			if content_size.y > view.y and scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
				return true
			if content_size.x > view.x and scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
				return true
			# A ScrollContainer that is itself fully on screen and whose content
			# fits needs no scrolling; anything outside it is a real overflow.
		parent = parent.get_parent()
	return false


## Things a player has to be able to reach. Labels and panels are decoration:
## a title that runs off the edge is ugly, an unreachable button is broken.
func _is_interactive(control: Control) -> bool:
	return control is BaseButton or control is Slider or control is LineEdit \
		or control is TextEdit or control is ItemList


func _describe(control: Control) -> String:
	var text := ""
	var button := control as Button
	if button != null:
		text = button.text
	if text == "":
		text = control.name
	return "%s '%s'" % [control.get_class(), text.strip_edges().substr(0, 28)]
