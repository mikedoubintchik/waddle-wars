extends Control
## Windowed all-plate crop QA.
## godot res://tests/course_poster_wave1_shot.tscn -- out=qa.png w=540 h=960

const ORDER: PackedStringArray = ["glacier", "tutorial", "aurora"]
const NAMES: Dictionary = {
	"aurora": "Aurora Ascent",
	"glacier": "Glacier Gauntlet",
	"tutorial": "Waddle School",
}

var _out_path: String = "qa_shots/course_posters/wave1.png"
var _wait: float = 1.0
var _elapsed: float = 0.0
var _captured: bool = false


func _ready() -> void:
	var width := 1920
	var height := 1080
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.split("=", true, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"out": _out_path = parts[1]
			"wait": _wait = float(parts[1])
			"w": width = int(parts[1])
			"h": height = int(parts[1])
	DisplayServer.window_set_size(Vector2i(width, height))
	DisplayServer.window_set_position(Vector2i(40, 60))
	DisplayServer.window_move_to_foreground()
	await get_tree().process_frame
	_build_gallery(height > width)


func _build_gallery(portrait: bool) -> void:
	UITheme.make_background(self)
	var safe := MarginContainer.new()
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.add_theme_constant_override("margin_left", 30 if portrait else 54)
	safe.add_theme_constant_override("margin_right", 30 if portrait else 54)
	safe.add_theme_constant_override("margin_top", 26 if portrait else 38)
	safe.add_theme_constant_override("margin_bottom", 26 if portrait else 38)
	add_child(safe)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 18)
	safe.add_child(page)
	var eyebrow := UITheme.make_eyebrow("COURSE POSTERS · AUTHORED WAVE 1", 14)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	page.add_child(eyebrow)
	var heading := UITheme.make_headline("Choose an Expedition", 38 if portrait else 44)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	page.add_child(heading)

	var gallery := GridContainer.new()
	gallery.columns = 1 if portrait else 3
	gallery.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gallery.add_theme_constant_override("h_separation", 24)
	gallery.add_theme_constant_override("v_separation", 16)
	page.add_child(gallery)

	var builder := (load("res://scripts/ui/mode_select.gd") as GDScript).new() as Control
	for course_id: String in ORDER:
		var card := UITheme.make_card(gallery)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if portrait:
			_build_portrait_card(builder, card, course_id)
		else:
			_build_landscape_card(builder, card, course_id)
	builder.free()


func _build_portrait_card(builder: Control, card: PanelContainer, course_id: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	card.add_child(row)
	var art := builder.call("_course_art", row, course_id, Vector2(230.0, 0.0)) as Control
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.add_theme_constant_override("separation", 8)
	row.add_child(copy)
	copy.add_child(UITheme.make_caption("EXPEDITION PLATE", 12))
	var title := UITheme.make_title(String(NAMES[course_id]), 25)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(title)
	var crop := UITheme.make_body("Central 52% crop", 16, UITheme.COLOR_TEXT_DIM)
	copy.add_child(crop)


func _build_landscape_card(builder: Control, card: PanelContainer, course_id: String) -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	card.add_child(column)
	var art := builder.call("_course_art", column, course_id, Vector2(0.0, 250.0)) as Control
	art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(UITheme.make_caption("EXPEDITION PLATE", 12))
	column.add_child(UITheme.make_title(String(NAMES[course_id]), 25))


func _process(delta: float) -> void:
	_elapsed += delta
	if _captured or _elapsed < _wait:
		return
	_captured = true
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_out_path.get_base_dir())
	var error := image.save_png(_out_path)
	print("[course-poster-shot] %s %dx%d err=%d" % [
		_out_path, image.get_width(), image.get_height(), error])
	get_tree().quit(0 if error == OK else 1)
