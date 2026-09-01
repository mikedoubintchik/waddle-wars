extends Node
## Reports how much of each mode_select card is actually filled, at a phone
## size: the authored tile height against the height its own content asks for.
## Diagnostic, not a pass/fail check -- run it when a card looks empty.
##
##   godot --path . --resolution 390x844 res://tests/card_probe.tscn

func _ready() -> void:
	GameConfig.force_touch = true
	DisplayServer.window_set_size(Vector2i(390, 844))
	DisplayServer.window_set_position(Vector2i(40, 60))
	DisplayServer.window_move_to_foreground()
	await get_tree().process_frame
	await get_tree().process_frame
	var scene: PackedScene = load("res://scenes/menus/mode_select.tscn")
	var menu: Node = scene.instantiate()
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame

	for step: String in ["mode", "course", "difficulty"]:
		if step == "course":
			menu.set("_chosen_mode", Game.Mode.QUICK_RACE)
			menu.call("_show_course_step")
		elif step == "difficulty":
			menu.set("_chosen_mode", Game.Mode.QUICK_RACE)
			menu.set("_chosen_course", "glacier")
			menu.call("_show_difficulty_step")
		for _i: int in 4:
			await get_tree().process_frame
		print("--- step %s (canvas %s) ---" % [step, get_viewport().get_visible_rect().size])
		_report(menu)
	get_tree().quit(0)


func _report(node: Node) -> void:
	for button: Variant in node.get("_buttons"):
		var control := button as Control
		if control == null:
			continue
		var content := 0.0
		for child: Node in control.get_children():
			var inner := child as Control
			if inner != null:
				content = maxf(content, inner.get_combined_minimum_size().y)
		print("  min=%4.0f actual=%4.0f content=%4.0f slack=%4.0f  %s"
			% [control.custom_minimum_size.y, control.size.y, content,
				control.size.y - content, _label_of(control)])


func _label_of(control: Control) -> String:
	for child: Node in control.get_children():
		var found := _first_label(child)
		if found != "":
			return found
	return "?"


func _first_label(node: Node) -> String:
	var label := node as Label
	if label != null and label.text != "":
		return label.text.substr(0, 24)
	for child: Node in node.get_children():
		var found := _first_label(child)
		if found != "":
			return found
	return ""
