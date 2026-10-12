extends Node
var passed := 0
var failed := 0

func _ready() -> void:
	SettingsManager.settings["accessibility"]["reduced_flashing"] = true
	for dimensions: Vector2i in [Vector2i(1280,720), Vector2i(1920,1080), Vector2i(800,1422)]:
		GameConfig.force_touch = dimensions.y > dimensions.x
		var viewport := SubViewport.new()
		viewport.size = dimensions
		add_child(viewport)
		var credits := load("res://scenes/menus/credits.tscn").instantiate() as Control
		viewport.add_child(credits)
		for frame in 4: await get_tree().process_frame
		var back := credits.find_child("CreditsIllustratedBack", true, false) as Button
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		print("[utility-bounds] view=%s back=%s" % [dimensions, back.get_global_rect()])
		_check(bounds.encloses(back.get_global_rect()), "whole Credits action inside exact viewport")
		var journal := credits.find_child("CreditsJournal", true, false) as Control
		_check(not back.get_global_rect().intersects(journal.get_global_rect()), "Credits action stays below journal and internal links")
		var group := back.get_node("IllustratedAction") as Control
		for child: Control in group.get_children():
			_check(back.get_global_rect().grow(1).encloses(child.get_global_rect()), "Credits icon/text/arrow remain inside action")
		credits.free()
		var controls := load("res://scenes/menus/controls.tscn").instantiate() as Control
		viewport.add_child(controls)
		for frame in 4: await get_tree().process_frame
		for button: Button in [controls._back_button, controls._reset_button]:
			var face := button.get_theme_stylebox("normal")
			_check(face.get("texture") != null, "icy control face retains painted source texture")
			_check(bounds.encloses(button.get_global_rect()), "whole Controls footer/reset inside exact viewport")
		controls.free()
		viewport.free()
	for voice in AudioManager._sfx_pool:
		voice.stop()
		voice.stream = null
	for player in [AudioManager._music_a, AudioManager._music_b]:
		player.stop()
		player.stream = null
	await get_tree().process_frame
	print("[utility-bounds] DONE: %d passed, %d failed" % [passed,failed])
	get_tree().quit(0 if failed == 0 else 1)

func _check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		push_error(label)
