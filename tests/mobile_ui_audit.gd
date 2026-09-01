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
	# must_fit: in PORTRAIT the hub is the first screen a player sees and its
	# rows are the whole navigation of the game, so a scrollable ancestor does
	# not excuse the last row being sliced off the bottom. A phone held
	# sideways genuinely has too little height for the same composition, and
	# there scrolling is the honest answer.
	{"name": "main_menu", "path": "res://scenes/menus/main_menu.tscn", "must_fit": true},
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
	# The first screen anyone sees. It was not audited, which is exactly the
	# kind of gap the main-menu overflow came out of.
	{"name": "title", "path": "res://scenes/ui/title.tscn", "must_fit": true},
]

## Screens built in code rather than authored as scenes. The pause menu is the
## only way off a race on a phone -- there is no Esc key -- so a Quit button
## under the home indicator strands the player in a race they cannot leave.
const CODE_SCREENS: Array[Dictionary] = [
	{"name": "pause_menu", "class": "PauseMenu", "must_fit": true},
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

var _widest_name: String = ""
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
	# Build the web-only sign-in chip too. It is the widest thing on the main
	# menu and the reason the whole panel overflowed a real phone; without this
	# the audit measures a menu the web build never shows.
	LeaderboardClient.force_available = true
	SettingsManager.apply_all()
	_sizes = _devices.duplicate()
	# Pass one is the no-inset case, and it has to be FORCED to zero: a desktop
	# window reports its title bar as a top safe-area inset (139 units), which
	# is a constraint no phone has and made the pass fail for a reason that
	# does not exist on the target.
	LayoutProfile.forced_insets = Vector4.ZERO
	# Two passes. A desktop window reports no safe-area insets, so the first
	# pass measures a screen no notched phone has; the second forces the insets
	# a real handset gives up to the notch and the home indicator. The main
	# menu's status chip passed the first pass and overflowed the second by 80
	# units, which is precisely what shipped to a real iPhone.
	await _run()
	print("")
	print("[mobile-ui] --- second pass: 24-unit safe-area insets ---")
	LayoutProfile.forced_insets = Vector4(24.0, 24.0, 24.0, 24.0)
	await _run(true)


func _run(final: bool = false) -> void:
	for size: Vector2i in _sizes:
		for entry: Dictionary in SCENES:
			await _audit(String(entry["name"]), String(entry["path"]), size,
				bool(entry.get("must_fit", false)))
		for entry: Dictionary in CODE_SCREENS:
			await _audit_code_screen(String(entry["name"]), size,
				bool(entry.get("must_fit", false)))
	if not final:
		return
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


## Same measurement as _audit, for a screen that has no .tscn to load. The
## pause menu is built entirely in code and opened by a key or a button, so it
## has to be constructed and opened by hand here.
func _audit_code_screen(screen_name: String, size: Vector2i,
		must_fit: bool = false) -> void:
	DisplayServer.window_set_size(size)
	await get_tree().process_frame
	await get_tree().process_frame
	var instance: Node = null
	match screen_name:
		"pause_menu":
			var menu := PauseMenu.new()
			get_tree().root.add_child(menu)
			await get_tree().process_frame
			# quiet: no click sound for a measurement.
			menu.call("_open", null, 0.0, false, true)
			instance = menu
		_:
			_failures.append("%s: no builder for a code screen by that name" % screen_name)
			return
	for _i: int in 3:
		await get_tree().process_frame
	_measure(screen_name, instance, size, must_fit)
	# The pause menu pauses the tree; leaving it paused would freeze the rest
	# of the audit, which advances on process frames.
	if instance.has_method("_close"):
		instance.call("_close")
	get_tree().paused = false
	instance.queue_free()
	await get_tree().process_frame


func _audit(scene_name: String, path: String, size: Vector2i,
		must_fit: bool = false) -> void:
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
	_measure(scene_name, instance, size, must_fit)
	instance.queue_free()
	await get_tree().process_frame


## Everything the audit actually asserts, for one built screen at one size.
func _measure(scene_name: String, instance: Node, size: Vector2i,
		must_fit: bool) -> void:
	var rect := get_tree().root.get_visible_rect()
	var offenders: Array[Dictionary] = []
	_walk(instance, rect, offenders)

	# Overflow check, separate from reachability. The main-menu bug that shipped
	# to a real iPhone put no single button outside the viewport — the status
	# chip's minimum widths made it 856 units wide inside a 752-unit safe area
	# and pushed the row of controls under the screen edge. So the thing to
	# measure is the bounding box of everything interactive: on a phone that
	# must fit between the notch and the home indicator, not merely inside the
	# canvas.
	var profile := LayoutProfile.for_viewport(get_tree().root)
	_widest_name = ""
	var touchable := _interactive_bounds(instance, Rect2())
	var safe := profile.safe_rect
	if touchable.size.x > 0.0 and (touchable.position.x < safe.position.x - EDGE_TOLERANCE
			or touchable.end.x > safe.end.x + EDGE_TOLERANCE):
		_failures.append("%s @ %dx%d: controls span x %.0f..%.0f, outside the safe area %.0f..%.0f (widest: %s)"
			% [scene_name, size.x, size.y, touchable.position.x, touchable.end.x,
				safe.position.x, safe.end.x, _widest_name])
	# The same question on the other axis, which the first version of this test
	# did not ask — and a phone caught it immediately: the main menu fitted
	# across but ran off the BOTTOM, slicing the last row of buttons against the
	# browser toolbar. Vertical overflow is only acceptable when something can
	# actually scroll to it.
	if touchable.size.y > 0.0 and (touchable.position.y < safe.position.y - EDGE_TOLERANCE
			or touchable.end.y > safe.end.y + EDGE_TOLERANCE) \
			and ((must_fit and size.y > size.x) or not _has_vertical_scroll(instance)):
		_failures.append("%s @ %dx%d: controls span y %.0f..%.0f, outside the safe area %.0f..%.0f and nothing scrolls"
			% [scene_name, size.x, size.y, touchable.position.y, touchable.end.y,
				safe.position.y, safe.end.y])

	if scene_name == "main_menu":
		print("[mobile-ui] main_menu bounds y %.0f..%.0f  safe y %.0f..%.0f  canvas %s"
			% [touchable.position.y, touchable.end.y, safe.position.y, safe.end.y,
				rect.size])
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
	# Content sliced off inside a clipping control. This is the defect class
	# the mode-select cards had: a card whose contents are anchored to its
	# full rect never raise its minimum size, so an authored height that is
	# too small silently cuts the last line of text off, and nothing looks
	# broken enough to notice in a screenshot. A ScrollContainer clips by
	# design and is excluded along with everything under it.
	var clipped: Array[Dictionary] = []
	_find_clipped(instance, clipped)
	for entry: Dictionary in clipped:
		var offender: Control = entry["control"]
		# An auto-named Button says nothing; the text inside it says which
		# card is losing its last line.
		var caption := _first_text(offender)
		_failures.append("%s: %s%s clips its contents (%.0f tall, needs %.0f)"
			% [label, _describe(offender),
				" (\"%s\")" % caption if caption != "" else "",
				float(entry["have"]), float(entry["want"])])

	if offenders.is_empty():
		print("[mobile-ui] ok    %s" % label)


## Controls that clip content taller than they are.
##
## A ScrollContainer clips by design -- that is what scrolling is -- so it is
## skipped, but only it. Everything inside one is fair game: a card that cuts
## off its own last line of text is just as broken whether or not the page it
## sits on scrolls, and an earlier version of this check that carried the
## exemption down the tree found nothing at all, because every menu here lives
## inside a scroll.
func _find_clipped(node: Node, found: Array[Dictionary], _unused: bool = false) -> void:
	var control := node as Control
	if control != null and control.clip_contents and control.is_visible_in_tree() \
			and not (node is ScrollContainer) and control.size.y > 0.0:
		var want := 0.0
		for child: Node in control.get_children():
			var inner := child as Control
			if inner != null and inner.is_visible_in_tree():
				want = maxf(want, inner.get_combined_minimum_size().y)
		if want > control.size.y + EDGE_TOLERANCE:
			found.append({"control": control, "have": control.size.y, "want": want})
	for child: Node in node.get_children():
		_find_clipped(child, found)


## First non-empty label text under a node, for naming a control that Godot
## only knows as "@Button@103".
func _first_text(node: Node) -> String:
	var label := node as Label
	if label != null and label.text.strip_edges() != "":
		return label.text.substr(0, 28)
	var button := node as Button
	if button != null and button.text.strip_edges() != "":
		return button.text.substr(0, 28)
	for child: Node in node.get_children():
		var found := _first_text(child)
		if found != "":
			return found
	return ""


## True when the screen has a ScrollContainer that can actually scroll
## vertically — content taller than its own view, on an enabled axis.
func _has_vertical_scroll(node: Node) -> bool:
	var scroll := node as ScrollContainer
	if scroll != null and scroll.is_visible_in_tree() \
			and scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		for child: Node in scroll.get_children():
			var control := child as Control
			if control != null and control.is_visible_in_tree() \
					and control.get_combined_minimum_size().y > scroll.size.y + EDGE_TOLERANCE:
				return true
	for child: Node in node.get_children():
		if _has_vertical_scroll(child):
			return true
	return false


## Bounding box of every visible interactive control under `node`.
func _interactive_bounds(node: Node, best: Rect2) -> Rect2:
	var control := node as Control
	if control != null and control.is_visible_in_tree() and _is_interactive(control):
		var r := control.get_global_rect()
		if r.size.x > 0.0 and r.size.y > 0.0 and not _is_full_canvas_catcher(r):
			if best.size.x == 0.0 or r.end.x > best.end.x or r.position.x < best.position.x:
				_widest_name = _describe(control)
			best = r if best.size.x == 0.0 else best.merge(r)
	for child: Node in node.get_children():
		best = _interactive_bounds(child, best)
	return best


## A control deliberately covering the whole canvas to catch a tap anywhere --
## the title screen's "Tap anywhere" button is one. It cannot be off-screen or
## out of reach by construction, and including it in the interactive bounds
## makes every screen that has one look like it overflows on both axes.
func _is_full_canvas_catcher(rect: Rect2) -> bool:
	var canvas := get_tree().root.get_visible_rect()
	return rect.size.x >= canvas.size.x - EDGE_TOLERANCE \
		and rect.size.y >= canvas.size.y - EDGE_TOLERANCE


## The widest visible container that overflows `budget` AND contains something
## a player interacts with.
func _widest_interactive_host(node: Node, budget: float, best: Rect2) -> Rect2:
	var control := node as Control
	if control != null and control.is_visible_in_tree():
		var r := control.get_global_rect()
		if r.size.x > budget + EDGE_TOLERANCE and r.size.x > best.size.x \
				and _holds_interactive(control):
			best = r
	for child: Node in node.get_children():
		best = _widest_interactive_host(child, budget, best)
	return best


func _holds_interactive(node: Node) -> bool:
	if _is_interactive(node as Control) and (node as Control).is_visible_in_tree():
		return true
	for child: Node in node.get_children():
		if _holds_interactive(child):
			return true
	return false


## Widest visible Control under `node`.
func _widest(node: Node, best: Rect2) -> Rect2:
	var control := node as Control
	if control != null and control.is_visible_in_tree():
		var r := control.get_global_rect()
		if r.size.x > best.size.x:
			best = r
	for child: Node in node.get_children():
		best = _widest(child, best)
	return best


func _describe_rect(rect: Rect2) -> String:
	return "x %.0f..%.0f" % [rect.position.x, rect.end.x]


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
	if control == null:
		return false
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
