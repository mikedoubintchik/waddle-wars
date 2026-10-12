extends Node
## The race HUD and the touch buttons share the bottom of the screen, and
## nothing checked that they share it without colliding. On a portrait phone
## the course gauge ran from 32% to 68% of the width while SHOVE started at
## about 62%, so the end of the rail -- the end carrying the percentage --
## was drawn underneath a button.
##
## This measures the real controls at real device sizes: the HUD's own rails
## and cards against the rects TouchControls will place, and against the safe
## area. It needs a window, because both sides are laid out from the live
## viewport, so it is skipped headless.
##
##   godot --path . --resolution 390x844 res://tests/race_hud_touch_layout.tscn

## Device viewports to check, in physical pixels. Portrait phones are the
## case the bug lived in; the landscape entry keeps the desktop-shaped path
## honest, and the tablet catches anything that assumed a phone aspect.
const DEVICES: Array[Vector2i] = [
	Vector2i(360, 640),
	Vector2i(390, 844),
	Vector2i(412, 915),
	Vector2i(820, 1180),
	Vector2i(844, 390),
]

## Touch scales a player can pick, so the check covers the extremes of the
## setting rather than only its default.
const TOUCH_SCALES: PackedFloat32Array = [0.5, 1.0, 1.4, 2.0]

## A couple of pixels of overlap is a rounding artefact, not a collision.
const TOLERANCE: float = 2.0

## Wall-clock ceiling. Every capture harness in this repo has hung at least
## once on a window that never got a frame; a run that stops reporting is
## worse than a run that fails.
const WATCHDOG_SECONDS: float = 240.0

var _passes: int = 0
var _failures: int = 0
var _elapsed: float = 0.0
var _done: bool = false


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	if _elapsed > WATCHDOG_SECONDS:
		_done = true
		push_error("race_hud_touch_layout: watchdog fired after %.0f s" % _elapsed)
		get_tree().quit(1)


func _ready() -> void:
	if GameConfig.is_headless():
		print("[hud-touch] SKIP (needs a window)")
		get_tree().quit(0)
		return
	GameConfig.force_touch = true
	LayoutProfile.forced_insets = Vector4.ZERO
	SettingsManager.set_setting("accessibility", "hud_scale", 1.0)
	DisplayServer.window_set_position(Vector2i(40, 60))
	DisplayServer.window_move_to_foreground()

	for size: Vector2i in DEVICES:
		DisplayServer.window_set_size(size)
		for _i: int in 4:
			await get_tree().process_frame
		await _check_device(size)

	_done = true
	LayoutProfile.forced_insets = Vector4(-1.0, -1.0, -1.0, -1.0)
	print("[hud-touch] DONE: %d passed, %d failed" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check_device(size: Vector2i) -> void:
	var viewport := get_viewport()
	var profile := LayoutProfile.for_viewport(viewport)
	var canvas := viewport.get_visible_rect().size
	var manager := _inert_race_state()
	for scale: float in TOUCH_SCALES:
		# Both sides read the same setting: the buttons size themselves from
		# it, and the HUD's rail stops short of where they land. Building the
		# HUD against a scale the player has not chosen would only prove the
		# two disagree.
		SettingsManager.set_setting("gameplay", "touch_scale", scale)
		var hud := RaceHUD.new()
		hud.manager = manager
		hud.player = manager.player
		add_child(hud)
		hud.set_process(false)
		# Chrome seeds the position card and builds the real minimap from race
		# state. Keep these genuine inputs inert; no gameplay simulation runs.
		hud.build_chrome_for_test()
		for _i: int in 3:
			await get_tree().process_frame
		var buttons := TouchControls.button_rects_for_profile(profile, scale)
		var label := "%dx%d s%.1f" % [size.x, size.y, scale]
		if buttons.is_empty():
			_check("%s buttons_placed" % label, false, "no rects")
			hud.queue_free()
			await get_tree().process_frame
			continue
		var cluster := TouchControls.action_cluster_rect(profile, scale)
		_check("%s cluster_measured" % label, cluster.size.x > 0.0,
			"cluster footprint was empty")
		if profile.is_portrait():
			# Endless' score/storm caption changes the clock card's width. The
			# real Android build showed that it grazed the touch pause target.
			hud.set_endless_status(999999, 12345.0, 9999.0)
			for _i: int in 2:
				await get_tree().process_frame
			var time_card := hud.time_card_rect_for_test()
			var pause := buttons["pause"] as Rect2
			var top_overlap := time_card.intersection(pause)
			_check("%s endless_clock_clear_of_pause" % label,
				top_overlap.size.x <= TOLERANCE or top_overlap.size.y <= TOLERANCE,
				"overlap %.0fx%.0f at %s" % [top_overlap.size.x,
					top_overlap.size.y, top_overlap.position])

		for entry: Dictionary in hud.bottom_rail_rects_for_test():
			var rect := entry["rect"] as Rect2
			if rect.size.x <= 0.0 or rect.size.y <= 0.0:
				continue
			for id: Variant in buttons.keys():
				# The pause button lives at the top of the screen; the bottom
				# rail cannot reach it and the HUD reserves its lane already.
				if String(id) == "pause":
					continue
				var button := buttons[id] as Rect2
				var shared := rect.intersection(button)
				var overlaps := shared.size.x > TOLERANCE and shared.size.y > TOLERANCE
				_check("%s %s_clear_of_%s" % [label, entry["name"], id], not overlaps,
					"overlap %.0fx%.0f at %s" % [shared.size.x, shared.size.y, shared.position])

			# Everything on the rail also has to stay inside the safe area,
			# or a rounded corner eats the end of it.
			var inside := rect.position.x >= profile.safe_rect.position.x - TOLERANCE \
				and rect.end.x <= profile.safe_rect.end.x + TOLERANCE \
				and rect.end.y <= profile.safe_rect.end.y + TOLERANCE
			_check("%s %s_inside_safe_area" % [label, entry["name"]], inside,
				"rect %s vs safe %s" % [rect, profile.safe_rect])

			# And it has to stay on the canvas at all.
			var on_canvas := rect.position.x >= -TOLERANCE \
				and rect.end.x <= canvas.x + TOLERANCE
			_check("%s %s_on_canvas" % [label, entry["name"]], on_canvas,
				"rect %s vs canvas %s" % [rect, canvas])

		hud.queue_free()
		await get_tree().process_frame
	manager.free()


func _inert_race_state() -> RaceManager:
	# Keep the whole state outside SceneTree: CourseBase._ready would create
	# VFX pools, and RaceManager.setup would spawn and start actual racers.
	var manager := RaceManager.new()
	var course := CourseBase.new()
	var curve := Curve3D.new()
	curve.add_point(Vector3.ZERO)
	curve.add_point(Vector3(0.0, 0.0, -100.0))
	curve.add_point(Vector3(20.0, 0.0, -200.0))
	course.main_guide = PathGuide.new(curve)
	course.finish_offset = course.main_guide.length
	manager.course = course
	manager.add_child(course)
	for index: int in 8:
		var racer := Racer.new()
		racer.course = course
		racer.is_player = index == 0
		manager.racers.append(racer)
		manager.add_child(racer)
	manager.player = manager.racers[0]
	return manager


func _check(check_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passes += 1
		return
	_failures += 1
	print("[hud-touch] FAIL %s: %s" % [check_name, detail])
