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
##   godot --path ISOLATED_QA_PROJECT res://tests/mobile_ui_audit.tscn -- menu_insets=true
##   Add out=/fresh/absolute/prefix.png for six second-pass menu captures.
##
## Exits 1 if any menu has unreachable content.

## Layout audit must never contact production boards, accounts or purchases.
## Keep production identity/completion guards; replace only their transport.
class OfflineLeaderboard extends "res://scripts/network/leaderboard_client.gd":
	var blocked_requests: int = 0
	func _dispatch_request(_method: String, _url: String, _body: String, cb: Callable) -> void:
		blocked_requests += 1
		cb.call(false, {"error": "mobile_ui_audit_offline"})

class OfflineCommerce extends "res://scripts/commerce/commerce_client.gd":
	var blocked_requests: int = 0
	func _dispatch_request(_method: String, _path: String, _body: Dictionary,
			_token: String, complete: Callable) -> void:
		blocked_requests += 1
		complete.call(false, {"error": "network_unavailable"})

## Apple's HIG and Material both land at 44-48 px; 44 is the forgiving floor.
const MIN_TOUCH_PX: float = 44.0
## Sub-pixel overhang is rounding, not a defect.
const EDGE_TOLERANCE: float = 1.5

const SCENES: Array[Dictionary] = [
	# must_fit: in PORTRAIT the hub is the first screen a player sees and its
	# rows are the whole navigation of the game, so a scrollable ancestor does
	# not excuse the last row being sliced off the first screen in either
	# orientation.
	{"name": "main_menu", "path": "res://scenes/menus/main_menu.tscn", "must_fit": true},
	{"name": "base_camp", "path": "res://scenes/menus/main_menu.tscn",
		"overlay": "_show_base_camp"},
	{"name": "missions", "path": "res://scenes/menus/main_menu.tscn",
		"overlay": "_show_missions"},
	{"name": "account", "path": "res://scenes/menus/main_menu.tscn",
		"overlay": "_show_account"},
	{"name": "cosmetic_shop", "path": "res://scenes/menus/cosmetic_shop.tscn"},
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
var _menu_inset_only: bool = false
var _capture_prefix: String = ""
var _capture_pass: bool = false
var _captured_frames: int = 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "menu_insets=true":
			_menu_inset_only = true
		if arg.begins_with("out="):
			_capture_prefix = arg.trim_prefix("out=")
		if arg.begins_with("size="):
			var parts := arg.trim_prefix("size=").split("x")
			if parts.size() == 2:
				_devices = [Vector2i(int(parts[0]), int(parts[1]))]
	if GameConfig.is_headless():
		print("[mobile-ui] SKIP — needs a window; menus size themselves from it")
		get_tree().quit(0)
		return
	LeaderboardClient.set_script(OfflineLeaderboard)
	CommerceClient.set_script(OfflineCommerce)
	LeaderboardClient.set_process(false)
	CommerceClient.set_process(false)
	if LeaderboardClient.get_script() != OfflineLeaderboard \
			or CommerceClient.get_script() != OfflineCommerce:
		_failures.append("offline singleton transports were not installed")
		_finish()
		return
	print("[mobile-ui] OFFLINE — board/shop transport errors simulated; live data and purchase flows not audited")
	if not _prepare_captures():
		_finish()
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
	if _menu_inset_only:
		await _audit_menu_insets()
		_finish()
		return
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
	_capture_pass = final
	for size: Vector2i in _sizes:
		for entry: Dictionary in SCENES:
			await _audit(String(entry["name"]), String(entry["path"]), size,
				bool(entry.get("must_fit", false)), String(entry.get("overlay", "")))
		for entry: Dictionary in CODE_SCREENS:
			await _audit_code_screen(String(entry["name"]), size,
				bool(entry.get("must_fit", false)))
	if not final:
		return
	await _audit_menu_insets()
	_finish()


func _finish() -> void:
	print("")
	if LeaderboardClient.get_script() == OfflineLeaderboard \
			and CommerceClient.get_script() == OfflineCommerce:
		print("[mobile-ui] offline transports — %d board/account and %d commerce requests blocked"
			% [int(LeaderboardClient.get("blocked_requests")), int(CommerceClient.get("blocked_requests"))])
	if not _capture_prefix.is_empty():
		print("[mobile-ui] rendered captures — %d saved" % _captured_frames)
		if _captured_frames != (SCENES.size() + CODE_SCREENS.size()) * 2:
			_failures.append("requested portrait and landscape menu captures were not completed")
	for warning: String in _warnings:
		print("[mobile-ui] WARN  %s" % warning)
	if _failures.is_empty():
		if _menu_inset_only:
			print("[mobile-ui] PASS — main-menu dock/cards stay inside the horizontal safe budget")
		else:
			print("[mobile-ui] PASS — every menu's content is reachable at %d sizes" % _sizes.size())
		get_tree().quit(0)
		return
	for failure: String in _failures:
		print("[mobile-ui] FAIL  %s" % failure)
	print("[mobile-ui] %d unreachable-content failures" % _failures.size())
	get_tree().quit(1)


## Regression for the actual Android 540x960 dock crop: interactive leaves
## alone stayed safe because the dock's padding hid its over-wide parent.
## Measure real container/card rectangles, including a retained menu after
## rotation. Vertical scrolling remains valid; this guard is horizontal only.
func _audit_menu_insets() -> void:
	var window := get_tree().root
	var original_size := window.size
	var original_insets := LayoutProfile.forced_insets
	var accessibility: Dictionary = SettingsManager.settings["accessibility"]
	var original_scale := float(accessibility.get("ui_scale", 1.0))
	var cases: Array[Vector4] = [
		Vector4(24.0, 24.0, 24.0, 24.0),
		Vector4(40.0, 24.0, 12.0, 32.0),
	]
	var shapes: Array[Vector2i] = [Vector2i(540, 960), Vector2i(960, 540)]
	var failures_before := _failures.size()
	var measured := 0
	for ui_scale: float in [0.8, 1.6]:
		accessibility["ui_scale"] = ui_scale
		for insets: Vector4 in cases:
			LayoutProfile.forced_insets = insets
			for shape: Vector2i in shapes:
				window.size = shape
				# apply_all also restores saved desktop display resolution;
				# only apply UI scaling so this remains the requested real shape.
				SettingsManager._apply_ui_scale(ui_scale)
				for _frame: int in 3:
					await get_tree().process_frame
				var scene: PackedScene = load("res://scenes/menus/main_menu.tscn")
				var menu := scene.instantiate()
				window.add_child(menu)
				# Entrance captures/tweens positions for ~0.7s. Judge settled
				# layout, not the deliberately transient entrance positions.
				await get_tree().create_timer(0.8).timeout
				_measure_menu_insets(menu, "fresh", shape, ui_scale, insets)
				measured += 1
				for rotated: Vector2i in [Vector2i(shape.y, shape.x), shape]:
					window.size = rotated
					SettingsManager._apply_ui_scale(ui_scale)
					for _frame: int in 4:
						await get_tree().process_frame
					_measure_menu_insets(menu, "live resize", rotated, ui_scale, insets)
					measured += 1
				menu.queue_free()
				await get_tree().process_frame
	accessibility["ui_scale"] = original_scale
	LayoutProfile.forced_insets = original_insets
	window.size = original_size
	SettingsManager._apply_ui_scale(original_scale)
	print("[mobile-ui] menu inset regression %s — %d fresh/live layouts at two UI scales"
		% ["PASS" if _failures.size() == failures_before else "FAIL", measured])


func _measure_menu_insets(menu: Node, phase: String, requested: Vector2i,
		ui_scale: float, insets: Vector4) -> void:
	var actual := get_tree().root.size
	var label := "main_menu %s @ %dx%d (actual %dx%d), UI %.1f, insets %s" % [
		phase, requested.x, requested.y, actual.x, actual.y, ui_scale, insets]
	if actual != requested:
		_failures.append("%s: requested window geometry was not achieved" % label)
	var profile := LayoutProfile.for_viewport(get_tree().root)
	var scroll := menu.get("_safe_scroll") as ScrollContainer
	var buttons: Array = menu.get("_buttons")
	var content := scroll.find_child("HomeComposition", false, false) as Control \
		if scroll != null else null
	if scroll == null or buttons.size() < 4 or content == null:
		_failures.append("%s: current Home composition or its four actions missing (scroll=%s, buttons=%d, composition=%s)" % [
			label, scroll != null, buttons.size(), content != null])
		return
	_assert_menu_horizontal(scroll, profile.safe_rect, label, "safe scroll")
	_assert_menu_horizontal(content, scroll.get_global_rect(), label, "scroll content")
	var dock: PanelContainer = null
	var ancestor: Node = (buttons[0] as Button).get_parent()
	while ancestor != null and ancestor != scroll:
		if ancestor is PanelContainer:
			dock = ancestor as PanelContainer
			break
		ancestor = ancestor.get_parent()
	_assert_menu_horizontal(dock, profile.safe_rect, label, "dock")
	if dock != null and dock.get_combined_minimum_size().x > profile.safe_rect.size.x:
		_trace_menu_minimum(dock, label, "dock")
	for index: int in 4:
		_assert_menu_horizontal(buttons[index] as Control, profile.safe_rect,
			label, "departure/destination %d" % index)
		if dock != null:
			_assert_menu_horizontal(buttons[index] as Control, dock.get_global_rect(),
				label, "departure/destination %d inside dock" % index)
	# Width comes from ScrollContainer, not a full-width child minimum (which
	# would force any vertical scrollbar past the safe edge). The premium home
	# paints its shelf through the bottom inset in portrait; its composition
	# therefore spans the scroll viewport, not only the safe rectangle.
	var composition: BoxContainer = null
	if content is BoxContainer:
		composition = content as BoxContainer
	elif content != null and content.get_child_count() == 1:
		composition = content.get_child(0) as BoxContainer
	var live_profile := menu.get("_profile") as LayoutProfile
	if live_profile == null or live_profile.safe_rect != profile.safe_rect:
		_failures.append("%s: menu retained a stale safe-area profile" % label)
	var expected_height := profile.safe_rect.size.y + (
		profile.safe_insets.w if profile.is_portrait() else 0.0)
	if composition == null or not is_zero_approx(composition.custom_minimum_size.x) \
			or not is_equal_approx(composition.custom_minimum_size.y, expected_height) \
			or composition.vertical != profile.is_portrait():
		_failures.append("%s: composition did not rebudget to live scroll geometry (minimum %s, expected height %.1f, vertical %s, expected %s)" % [
			label, composition.custom_minimum_size if composition != null else Vector2.ZERO,
			expected_height, composition.vertical if composition != null else false,
			profile.is_portrait()])
	if dock != null and not is_equal_approx(
			dock.custom_minimum_size.x, float(menu.call("_hub_width"))):
		_failures.append("%s: dock minimum retained its opening width" % label)
	var destinations := (buttons[1] as Button).get_parent() as HBoxContainer
	if destinations == null or destinations.name != "DestinationDock" \
			or destinations.get_child_count() != 3:
		_failures.append("%s: three-destination dock missing after resize" % label)


## Failure-only minimum chain: no account text or save contents in evidence.
func _trace_menu_minimum(control: Control, label: String, path: String) -> void:
	print("[mobile-ui] MIN %s: %s %s min %.1f / custom %.1f / actual %.1f" % [
		label, path, control.get_class(), control.get_combined_minimum_size().x,
		control.custom_minimum_size.x, control.get_global_rect().size.x])
	for index: int in control.get_child_count():
		var child := control.get_child(index) as Control
		if child != null and child.get_combined_minimum_size().x \
				>= control.get_combined_minimum_size().x - 100.0:
			_trace_menu_minimum(child, label, "%s/%d" % [path, index])


func _assert_menu_horizontal(control: Control, safe: Rect2, label: String,
		part: String) -> void:
	if control == null:
		_failures.append("%s: %s missing" % [label, part])
		return
	var rect := control.get_global_rect()
	if rect.size.x <= 0.0 or rect.position.x < safe.position.x - EDGE_TOLERANCE \
			or rect.end.x > safe.end.x + EDGE_TOLERANCE:
		_failures.append("%s: %s spans x %.1f..%.1f, outside %.1f..%.1f" % [
			label, part, rect.position.x, rect.end.x, safe.position.x, safe.end.x])


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
	await _capture_screen(screen_name, size)
	# The pause menu pauses the tree; leaving it paused would freeze the rest
	# of the audit, which advances on process frames.
	if instance.has_method("_close"):
		instance.call("_close")
	get_tree().paused = false
	instance.queue_free()
	await get_tree().process_frame


func _audit(scene_name: String, path: String, size: Vector2i,
		must_fit: bool = false, overlay: String = "") -> void:
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
	if not overlay.is_empty():
		if not instance.has_method(overlay):
			_failures.append("%s: overlay entry point missing: %s" % [scene_name, overlay])
		else:
			instance.call(overlay)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	_measure(scene_name, instance, size, must_fit)
	await _capture_screen(scene_name, size)
	instance.queue_free()
	await get_tree().process_frame


func _prepare_captures() -> bool:
	if _capture_prefix.is_empty():
		return true
	if _menu_inset_only or not _capture_prefix.is_absolute_path() \
			or not _capture_prefix.ends_with(".png") \
			or not DirAccess.dir_exists_absolute(_capture_prefix.get_base_dir()) \
			or not _devices.has(Vector2i(360, 640)) or not _devices.has(Vector2i(844, 390)) \
			or FileAccess.file_exists(_capture_prefix) \
			or DirAccess.open(_capture_prefix.get_base_dir()).is_link(_capture_prefix.get_file()):
		_failures.append("capture prefix requires full audit and fresh absolute .png path in an existing directory")
		return false
	for size: Vector2i in [Vector2i(360, 640), Vector2i(844, 390)]:
		var screen_names: Array[String] = []
		for entry: Dictionary in SCENES:
			screen_names.append(String(entry["name"]))
		for entry: Dictionary in CODE_SCREENS:
			screen_names.append(String(entry["name"]))
		for screen: String in screen_names:
			var path := _capture_path(screen, size)
			if FileAccess.file_exists(path) or DirAccess.open(path.get_base_dir()).is_link(path.get_file()):
				_failures.append("refusing to overwrite capture %s" % path)
				return false
	return true


func _capture_path(screen: String, size: Vector2i) -> String:
	return "%s-%s-%dx%d.png" % [_capture_prefix.trim_suffix(".png"), screen, size.x, size.y]


func _capture_screen(screen: String, size: Vector2i) -> void:
	if _capture_prefix.is_empty() or not _capture_pass \
			or size not in [Vector2i(360, 640), Vector2i(844, 390)]:
		return
	var path := _capture_path(screen, size)
	# Existing entrance tweens take about 0.7 seconds. Capture settled content,
	# not the transient fade used by the earlier geometry-only audit.
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if FileAccess.file_exists(path) or DirAccess.open(path.get_base_dir()).is_link(path.get_file()) or image == null \
			or image.is_empty() or image.get_size() != size or get_tree().root.size != size:
		_failures.append("capture refused: output exists or physical image dimensions differ for %s" % path)
		return
	if image.save_png(path) != OK:
		_failures.append("capture save failed: %s" % path)
		return
	_captured_frames += 1
	print("[mobile-ui] CAPTURE %s" % path)


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
	if scene_name in ["missions", "base_camp", "account"]:
		var overlay_back := instance.find_child("OverlayBack", true, false) as Button
		if overlay_back == null or not overlay_back.is_visible_in_tree():
			_failures.append("%s: circular overlay Back missing or hidden" % scene_name)
		else:
			print("[mobile-ui] %s Back rect %s safe %s" % [scene_name,
				overlay_back.get_global_rect(), safe])
			if overlay_back.get_global_rect().size.x < MIN_TOUCH_PX \
					or overlay_back.get_global_rect().size.y < MIN_TOUCH_PX:
				_failures.append("%s: circular overlay Back has no usable hit area" % scene_name)
			if not _within(overlay_back.get_global_rect(), safe):
				_failures.append("%s: circular overlay Back outside safe rect" % scene_name)
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
			and ((must_fit and (scene_name == "main_menu" or size.y > size.x))
				or not _has_vertical_scroll(instance)):
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
		# A horizontally scrollable category shelf intentionally keeps additional
		# buttons beyond the visible width. Measure only its clipped hit region;
		# reachability is checked separately against the scroll axis below.
		var ancestor := control.get_parent()
		while ancestor != null:
			if ancestor is ScrollContainer:
				r = r.intersection((ancestor as ScrollContainer).get_global_rect())
			ancestor = ancestor.get_parent()
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
