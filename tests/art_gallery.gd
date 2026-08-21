extends Node3D
## Runtime-catalog visual gallery. Never fabricates placeholder art.
##
##   godot --path . res://tests/art_gallery.tscn -- group=runner_day
##   godot --headless --path . res://tests/art_gallery.tscn -- quit=1
##   godot --path . res://tests/art_gallery.tscn -- group=course_posters out=/tmp/posters.png

const CELL_X: float = 5.0
const CELL_Z: float = 5.0
const COLUMNS: int = 4

var _catalog: ArtCatalog
var _ids := PackedStringArray()
var _group: String = "gallery"
var _quit_when_ready: bool = false
var _started: bool = false
var _output_path: String = ""
var _window_size := Vector2i(1600, 900)
var _camera: Camera3D = null
var _capture_started: bool = false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var parts := arg.split("=", false, 1)
		if parts.size() != 2:
			continue
		match parts[0]:
			"group": _group = parts[1]
			"quit": _quit_when_ready = parts[1] == "1"
			"out": _output_path = parts[1]
			"w": _window_size.x = maxi(320, int(parts[1]))
			"h": _window_size.y = maxi(240, int(parts[1]))
	if not GameConfig.is_headless():
		DisplayServer.window_set_size(_window_size)
		DisplayServer.window_move_to_foreground()
	_build_stage()
	_catalog = load("res://data/art/art_catalog.tres") as ArtCatalog
	if _catalog == null or _catalog.reload_manifest() != OK:
		_show_status("ART CATALOG INVALID")
		_finish(1)
		return
	_ids = _catalog.asset_ids(_group)
	if _ids.is_empty():
		_show_status("No authored '%s' assets registered\nFoundation only — procedural visuals remain authoritative" % _group)
		print("[art-gallery] no authored assets registered for group '%s'" % _group)
		_finish(0)
		return
	var error := _catalog.begin_preload(_ids)
	if error != OK:
		_show_status("ART PRELOAD REQUEST FAILED: %d" % error)
		_finish(1)
		return
	_started = true


func _process(_delta: float) -> void:
	if not _started:
		return
	var status := _catalog.poll_preload()
	if not bool(status.get("complete", false)):
		return
	_started = false
	if int(status.get("failed", 0)) > 0:
		_show_status("ART PRELOAD FAILED\n%s" % str(status.get("failures", {})))
		_finish(1)
		return
	_build_assets()
	_finish(0)


func _build_stage() -> void:
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.07, 0.11, 0.18)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.62, 0.74, 0.92)
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment_node.environment = environment
	add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 5.5, 11.0)
	_camera.rotation_degrees = Vector3(-15.0, 0.0, 0.0)
	_camera.fov = 52.0
	_camera.current = true
	add_child(_camera)


func _build_assets() -> void:
	var textures: Array[Dictionary] = []
	var spatial_count := 0
	var unsupported := PackedStringArray()
	for index: int in _ids.size():
		var asset_id := _ids[index]
		var entry := _catalog.asset_entry(asset_id)
		var kind := String(entry.get("kind", ""))
		if kind == "texture":
			var texture := _catalog.loaded_resource(asset_id) as Texture2D
			if texture != null:
				textures.append({"id": asset_id, "texture": texture})
			else:
				unsupported.append(asset_id)
			continue
		if kind not in ["scene", "mesh"]:
			unsupported.append(asset_id)
			continue
		var instance := _catalog.instantiate_scene(asset_id)
		if instance == null:
			unsupported.append(asset_id)
			continue
		var spatial := instance as Node3D
		if spatial == null:
			instance.queue_free()
			unsupported.append(asset_id)
			continue
		spatial.position = Vector3(
			(float(spatial_count % COLUMNS) - 1.5) * CELL_X,
			0.0,
			-float(spatial_count / COLUMNS) * CELL_Z
		)
		add_child(spatial)
		var label := Label3D.new()
		label.text = asset_id
		label.font_size = 36
		label.position = spatial.position + Vector3(0.0, 3.0, 0.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(label)
		spatial_count += 1
	if spatial_count > COLUMNS and _camera != null:
		var rows := ceili(float(spatial_count) / float(COLUMNS))
		_camera.position = Vector3(0.0, 6.0 + float(rows), 13.0 + float(rows) * 2.5)
		_camera.look_at(Vector3(0.0, 1.5, -float(rows - 1) * CELL_Z * 0.5))
	if not textures.is_empty():
		_build_texture_sheet(textures)
	print("[art-gallery] built group='%s' spatial=%d textures=%d unsupported=%d" % [
		_group, spatial_count, textures.size(), unsupported.size(),
	])
	if not unsupported.is_empty():
		print("[art-gallery] unsupported entries: %s" % ", ".join(unsupported))


func _build_texture_sheet(entries: Array[Dictionary]) -> void:
	var layer := CanvasLayer.new()
	layer.name = "TextureContactSheet"
	layer.layer = 20
	add_child(layer)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.025, 0.05, 0.09, 0.98)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(backdrop)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_bottom", 28)
	layer.add_child(margin)
	var grid := GridContainer.new()
	grid.columns = 2 if _window_size.x < 1200 else 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 20)
	margin.add_child(grid)
	for entry: Dictionary in entries:
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 6)
		grid.add_child(card)
		var texture_rect := TextureRect.new()
		texture_rect.texture = entry["texture"] as Texture2D
		texture_rect.custom_minimum_size = Vector2(360.0, 205.0)
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		card.add_child(texture_rect)
		var label := Label.new()
		label.text = String(entry["id"])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", UITheme.caption_font())
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", Color(0.82, 0.91, 1.0))
		card.add_child(label)


func _show_status(message: String) -> void:
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(label)
	add_child(layer)


func _finish(code: int) -> void:
	if not _output_path.is_empty() and code == 0 and not GameConfig.is_headless():
		if not _capture_started:
			_capture_started = true
			_capture_then_quit.call_deferred()
		return
	if _quit_when_ready or DisplayServer.get_name() == "headless":
		get_tree().quit(code)


func _capture_then_quit() -> void:
	for _frame: int in 3:
		await RenderingServer.frame_post_draw
		if not is_inside_tree():
			return
	var absolute_path := ProjectSettings.globalize_path(_output_path)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if directory_error != OK:
		push_error("art gallery cannot create output directory: %s" % absolute_path)
		get_tree().quit(1)
		return
	var image := get_viewport().get_texture().get_image()
	var save_error := image.save_png(absolute_path)
	if save_error != OK:
		push_error("art gallery cannot save capture: %s" % absolute_path)
		get_tree().quit(1)
		return
	print("[art-gallery] capture=%s" % absolute_path)
	get_tree().quit(0)
