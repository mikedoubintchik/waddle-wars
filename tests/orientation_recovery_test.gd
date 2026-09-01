extends Node
## The design canvas must recover from a wrong first reading.
##
## SettingsManager picks a portrait or landscape design canvas from the window
## shape, and used to do that only at startup and on the resize signal. On iOS
## Safari the canvas can read landscape-shaped for the first frames and then
## simply be the right size with no resize event, so the wrong design canvas
## stuck: on a real iPhone the main menu laid out about 40% wider than the
## display, slicing the Sign In button and the right-hand column off the edge.
##
## This drives that exact sequence — apply while landscape, then become
## portrait without emitting anything — and asserts the canvas corrects itself.
##
##   godot --headless --path . res://tests/orientation_recovery_test.tscn

func _ready() -> void:
	# The design canvas only exists where there is a display; headless returns
	# before touching it, so there is nothing to assert there.
	if GameConfig.is_headless():
		print("[orientation] SKIP — needs a window")
		get_tree().quit(0)
		return
	var failures := PackedStringArray()
	var window := get_tree().root
	var original := window.size

	# 1. A landscape window produces a landscape design canvas.
	window.size = Vector2i(1200, 700)
	SettingsManager.apply_all()
	await get_tree().process_frame
	var landscape := window.content_scale_size
	if landscape.x <= landscape.y:
		failures.append("landscape window gave a %s design canvas" % landscape)

	# 2. Now the window becomes portrait. Godot emits size_changed here, which
	#    is exactly what iOS Safari may not do, so the poll is what must catch
	#    it — wait past one poll interval and check.
	window.size = Vector2i(700, 1200)
	var waited := 0.0
	while waited < SettingsManager.ORIENTATION_POLL * 3.0:
		await get_tree().process_frame
		waited += 0.05
	var portrait := window.content_scale_size
	if portrait.y <= portrait.x:
		failures.append("portrait window left a %s design canvas (was %s)"
			% [portrait, landscape])

	window.size = original
	if failures.is_empty():
		print("[orientation] PASS — design canvas follows the window shape")
		get_tree().quit(0)
		return
	for failure: String in failures:
		print("[orientation] FAIL %s" % failure)
	get_tree().quit(1)
