extends Node
## Focused contract for second authored course-poster migration wave.

const FRAGMENT_PATH: String = "res://data/art/fragments/course_posters_wave2.json"
const POSTERS: Dictionary = {
	"cinder": {
		"path": "res://assets/art/ui/course_posters/cinder_coast_wave2.png",
		"source": "res://art_src/ui/course_posters/cinder_coast_wave2.png",
		"prompt": "res://art_src/ui/course_posters/cinder_coast_wave2.prompt.md",
		"sha256": "41d5a0d4e66abf72d214a69b853950c6b2adbcec581b86b2d5cb31cae6ac71e9",
	},
	"hollow": {
		"path": "res://assets/art/ui/course_posters/sapphire_hollow_wave2.png",
		"source": "res://art_src/ui/course_posters/sapphire_hollow_wave2.png",
		"prompt": "res://art_src/ui/course_posters/sapphire_hollow_wave2.prompt.md",
		"sha256": "80fd58d7037ae518b1461f3512c6763d66e7982f72a78954897c1ff572fbd630",
	},
	"iceberg": {
		"path": "res://assets/art/ui/course_posters/iceberg_bay_wave2.png",
		"source": "res://art_src/ui/course_posters/iceberg_bay_wave2.png",
		"prompt": "res://art_src/ui/course_posters/iceberg_bay_wave2.prompt.md",
		"sha256": "a2d5b3181292c92f9dff661cc882ec8aac4d8d6049546d12a99965b28603a6d0",
	},
}

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	_check_source_contract()
	await _check_mode_select_builder()
	# Asset loads run last. Earlier cache checks prove mode_select preloads own
	# decode/upload rather than card construction doing synchronous first use.
	_check_asset_contract()
	_check_provenance_contract()
	print("[course-posters-wave2] DONE: %d/%d checks passed" % [
		_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)


func _check_source_contract() -> void:
	var file := FileAccess.open("res://scripts/ui/mode_select.gd", FileAccess.READ)
	_check(file != null, "mode_select source readable")
	if file == null:
		return
	var source := file.get_as_text()
	for course_id: String in POSTERS:
		var path := String((POSTERS[course_id] as Dictionary).path)
		_check(path in source, "%s authored path registered" % course_id)
		_check("\"%s\": preload(\"%s\")" % [course_id, path] in source,
			"%s texture is a script preload" % course_id)
	_check(not "ResourceLoader.load(authored_path)" in source,
		"card build performs no synchronous texture load")
	_check(not "const ART_ICEBERG" in source,
		"Iceberg Bay procedural source removed")
	_check(not "const ART_CINDER" in source,
		"Cinder Coast procedural source removed")
	_check(not "const ART_HOLLOW" in source,
		"Sapphire Hollow procedural source removed")
	_check(not "COURSE_ART" in source and not "COURSE_SKY" in source,
		"production poster fallback mapping removed")


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
		var poster := frame.get_node_or_null(
			"CoursePoster_%s" % course_id.capitalize()) as TextureRect
		_check(poster != null, "%s builds authored TextureRect" % course_id)
		if poster != null:
			_check(poster.texture.resource_path == String(
				(POSTERS[course_id] as Dictionary).path),
				"%s binds correct authored texture" % course_id)
			_check(poster.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_COVERED,
				"%s uses crop-safe center cover" % course_id)
			_check(poster.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS,
				"%s requests mip-filtered sampling" % course_id)
		host.queue_free()
		await get_tree().process_frame
	builder.free()


func _check_asset_contract() -> void:
	var unique_hashes: Dictionary = {}
	for course_id: String in POSTERS:
		var contract: Dictionary = POSTERS[course_id]
		var path := String(contract.path)
		_check(FileAccess.file_exists(path), "%s runtime PNG exists" % course_id)
		_check(ResourceLoader.exists(path), "%s runtime texture imported" % course_id)
		var actual_hash := FileAccess.get_sha256(path)
		_check(actual_hash == String(contract.sha256),
			"%s SHA-256 matches provenance" % course_id)
		unique_hashes[actual_hash] = true
		var import_file := FileAccess.open(path + ".import", FileAccess.READ)
		_check(import_file != null, "%s import metadata exists" % course_id)
		if import_file != null:
			var import_text := import_file.get_as_text()
			# Posters are 1672x941 — not powers of two — and a block-compressed
			# non-power-of-two texture decodes to magenta garbage on iOS
			# Safari's WebGL while looking perfect in desktop Chrome. They are
			# imported lossless for that reason; tests/texture_format_test.gd
			# enforces the rule across every texture in the project.
			_check("compress/mode=0" in import_text,
				"%s is lossless (non-power-of-two art must not be VRAM compressed)"
				% course_id)
			_check("mipmaps/generate=true" in import_text,
				"%s generates mipmaps" % course_id)
		var texture := ResourceLoader.load(path) as Texture2D
		_check(texture != null, "%s texture loads" % course_id)
		if texture == null:
			continue
		var dimensions := texture.get_size()
		_check(dimensions == Vector2(1672.0, 941.0),
			"%s source dimensions retained" % course_id)
		_check(absf(dimensions.x / dimensions.y - 16.0 / 9.0) < 0.002,
			"%s plate is 16:9" % course_id)
		for target_aspect: float in [16.0 / 9.0, 4.0 / 3.0, 0.93]:
			var horizontal_fraction := minf(1.0,
				target_aspect / (dimensions.x / dimensions.y))
			_check(horizontal_fraction >= 0.50,
				"%s center crop retains >=50%% at %.2f aspect" % [
					course_id, target_aspect])
	_check(unique_hashes.size() == POSTERS.size(),
		"all three hero plates are pixel-unique")


func _check_provenance_contract() -> void:
	var fragment_file := FileAccess.open(FRAGMENT_PATH, FileAccess.READ)
	_check(fragment_file != null, "wave2 art fragment exists")
	if fragment_file != null:
		var parsed = JSON.parse_string(fragment_file.get_as_text())
		_check(parsed is Dictionary, "wave2 art fragment parses")
		if parsed is Dictionary:
			var fragment := parsed as Dictionary
			_check(fragment.size() == 4
				and fragment.has("runtime_assets")
				and fragment.has("source_exports")
				and fragment.has("generated_assets")
				and fragment.has("concepts"),
				"fragment uses four-list merge schema")
			_check((fragment.get("runtime_assets", []) as Array).size() == 3,
				"fragment registers three runtime textures")
			_check((fragment.get("generated_assets", []) as Array).size() == 3,
				"fragment registers three generated sources")
	for course_id: String in POSTERS:
		var contract: Dictionary = POSTERS[course_id]
		_check(FileAccess.get_sha256(String(contract.source)) == String(contract.sha256),
			"%s editable source matches runtime bytes" % course_id)
		var prompt_file := FileAccess.open(String(contract.prompt), FileAccess.READ)
		_check(prompt_file != null, "%s exact prompt provenance exists" % course_id)
		if prompt_file != null:
			var prompt_text := prompt_file.get_as_text()
			_check("ImageGen calls for this plate: 1" in prompt_text,
				"%s records one distinct ImageGen call" % course_id)
			_check(String(contract.sha256) in prompt_text,
				"%s prompt provenance records SHA-256" % course_id)
			_check("Exact generation prompt:" in prompt_text,
				"%s exact generation prompt retained" % course_id)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("[course-posters-wave2] PASS %s" % message)
	else:
		_failures += 1
		print("[course-posters-wave2] FAIL %s" % message)
