extends SceneTree
## Guards the one texture rule that iOS Safari actually enforces.
##
## A VRAM-compressed texture whose dimensions are not powers of two decodes
## incorrectly on iOS Safari's WebGL: the first mip renders, the smaller levels
## appear tiled below it, and the rest of the surface is magenta garbage. The
## whole front end shipped like that — title, loader and every course poster —
## while desktop Chrome, whose driver handles the same data fine, showed
## nothing wrong. Found only by running the real build in a real iPhone
## simulator.
##
## The rule: if a texture is imported with compress/mode=2 (VRAM compressed),
## both dimensions must be powers of two. Anything non-power-of-two must be
## lossless (mode=0), which costs VRAM but renders everywhere.
##
##   godot --headless --path . --script tests/texture_format_test.gd

const VRAM_COMPRESSED := "compress/mode=2"


func _init() -> void:
	var failures := PackedStringArray()
	var checked := 0
	for path: String in _find_imports("res://assets"):
		var text := FileAccess.get_file_as_string(path)
		if not text.contains(VRAM_COMPRESSED):
			continue
		var source := path.trim_suffix(".import")
		var image := Image.new()
		if image.load(source) != OK:
			continue
		checked += 1
		var w := image.get_width()
		var h := image.get_height()
		if not (_is_power_of_two(w) and _is_power_of_two(h)):
			failures.append("%s is %dx%d and VRAM-compressed — iOS Safari renders this as garbage; import it lossless (compress/mode=0) or resize to powers of two"
				% [source.get_file(), w, h])
	print("[texture-format] checked %d VRAM-compressed textures" % checked)
	if failures.is_empty():
		print("[texture-format] PASS")
		quit(0)
		return
	for failure: String in failures:
		print("[texture-format] FAIL %s" % failure)
	quit(1)


func _is_power_of_two(value: int) -> bool:
	return value > 0 and (value & (value - 1)) == 0


func _find_imports(root: String) -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := root.path_join(name)
		if dir.current_is_dir():
			found.append_array(_find_imports(full))
		elif name.ends_with(".png.import"):
			found.append(full)
		name = dir.get_next()
	dir.list_dir_end()
	return found
