extends Node
## Focused contract for the first authored course-poster migration wave.

const POSTERS: Dictionary = {
	"aurora": {
		"path": "res://assets/art/ui/course_posters/aurora_ascent_wave1.png",
		"sha256": "d381caec5087d9c408afc0cedad3ee0de7a9bed43564e2fe10a7a21e2554d8d5",
	},
	"glacier": {
		"path": "res://assets/art/ui/course_posters/glacier_gauntlet_wave1.png",
		"sha256": "f2397eb2b72c75a5a3415568a68ffe61f19265b3fdd0af723f3d67fa680391a7",
	},
	"tutorial": {
		"path": "res://assets/art/ui/course_posters/waddle_school_wave1.png",
		"sha256": "0e71ffa5d1f678278e66f0bc6245edb4e3e1d5fdab7d5f41bf0c12bf391a98eb",
	},
}

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	_check_source_contract()
	await _check_mode_select_builder()
	# Asset load checks run last so the cache assertions above prove the mode
	# script's preloads populated ResourceLoader before any card or test load.
	_check_asset_contract()
	print("[course-posters] DONE: %d/%d checks passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)


func _check_asset_contract() -> void:
	var unique_hashes: Dictionary = {}
	for course_id: String in POSTERS:
		var contract: Dictionary = POSTERS[course_id]
		var path := String(contract.path)
		_check(FileAccess.file_exists(path), "%s runtime PNG exists" % course_id)
		_check(ResourceLoader.exists(path), "%s runtime texture imported" % course_id)
		var actual_hash := FileAccess.get_sha256(path)
		_check(actual_hash == String(contract.sha256), "%s SHA-256 matches provenance" % course_id)
		unique_hashes[actual_hash] = true
		var texture := ResourceLoader.load(path) as Texture2D
		_check(texture != null, "%s texture loads" % course_id)
		if texture == null:
			continue
		var dimensions := texture.get_size()
		_check(dimensions == Vector2(1672.0, 941.0), "%s source dimensions retained" % course_id)
		_check(absf(dimensions.x / dimensions.y - 16.0 / 9.0) < 0.002,
			"%s plate is 16:9" % course_id)
		# Portrait course rows expose about 52% of a centered 16:9 plate. The
		# art contract keeps the landmark inside the central 55%, so no layout
		# needs a per-course crop exception.
		for target_aspect: float in [16.0 / 9.0, 4.0 / 3.0, 0.93]:
			var horizontal_fraction := minf(1.0, target_aspect / (dimensions.x / dimensions.y))
			_check(horizontal_fraction >= 0.50,
				"%s center crop retains >=50%% at %.2f aspect" % [course_id, target_aspect])
	_check(unique_hashes.size() == POSTERS.size(), "all three hero plates are pixel-unique")


func _check_source_contract() -> void:
	var file := FileAccess.open("res://scripts/ui/mode_select.gd", FileAccess.READ)
	_check(file != null, "mode_select source readable")
	if file == null:
		return
	var source := file.get_as_text()
	for course_id: String in POSTERS:
		var path := String((POSTERS[course_id] as Dictionary).path)
		_check(path in source, "%s authored path registered in mode select" % course_id)
	_check(not "ResourceLoader.load(authored_path)" in source,
		"card build performs no synchronous texture load")
	_check("preload(\"res://assets/art/ui/course_posters/" in source,
		"poster textures are threaded scene dependencies")
	_check(not '"glacier": ART_GLACIER' in source,
		"Glacier Gauntlet no longer selects procedural poster")
	_check(not '"aurora": ART_AURORA' in source,
		"Aurora Ascent no longer selects procedural poster")


func _check_mode_select_builder() -> void:
	var script := load("res://scripts/ui/mode_select.gd") as GDScript
	_check(script != null, "mode_select script loads")
	if script == null:
		return
	for course_id: String in POSTERS:
		var path := String((POSTERS[course_id] as Dictionary).path)
		_check(ResourceLoader.has_cached(path),
			"%s texture cached with mode_select dependency load" % course_id)
	var builder := script.new() as Control
	for course_id: String in POSTERS:
		var host := Control.new()
		add_child(host)
		builder.call("_course_art", host, course_id, Vector2(240.0, 220.0))
		await get_tree().process_frame
		var frame := host.get_child(0) as Control
		var poster := frame.get_node_or_null("CoursePoster_%s" % course_id.capitalize()) as TextureRect
		_check(poster != null, "%s builds authored TextureRect" % course_id)
		if poster != null:
			_check(poster.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED,
				"%s uses crop-safe center cover" % course_id)
			_check(poster.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,
				"%s requests mip-filtered sampling" % course_id)
		host.queue_free()
		await get_tree().process_frame
	builder.free()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("[course-posters] PASS %s" % message)
	else:
		_failures += 1
		print("[course-posters] FAIL %s" % message)
