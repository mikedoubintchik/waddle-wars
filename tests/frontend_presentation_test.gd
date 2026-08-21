extends Node
## Headless structural contract for premium 2D boot/title/loading presentation.

const OWNED_SCRIPTS: PackedStringArray = [
	"res://scripts/ui/boot.gd",
	"res://scripts/ui/front_end_backdrop.gd",
	"res://scripts/ui/penguin_loader.gd",
	"res://scripts/ui/title.gd",
	"res://scripts/utilities/boot_warmup.gd",
]
const FORBIDDEN_SOURCE: PackedStringArray = [
	"SubViewport", "Node3D", "GPUParticles", "CPUParticles", "ShaderMaterial",
]

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	_check_source_contract()
	_check_asset_contract()
	_check_crop_contract()
	await _check_runtime_trees()
	print("[frontend] DONE: %d/%d checks passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)


func _check_source_contract() -> void:
	for path: String in OWNED_SCRIPTS:
		_check(FileAccess.file_exists(path), "%s exists" % path.get_file())
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var source := file.get_as_text()
		for token: String in FORBIDDEN_SOURCE:
			# Comments describe removed systems. Only executable identifiers count.
			var executable := false
			for line: String in source.split("\n"):
				var trimmed := line.strip_edges()
				if not trimmed.begins_with("#") and token in trimmed:
					executable = true
					break
			_check(not executable, "%s has no executable %s" % [path.get_file(), token])


func _check_asset_contract() -> void:
	for path: String in [
		FrontEndBackdrop.LANDSCAPE_PATH,
		FrontEndBackdrop.PORTRAIT_PATH,
		PenguinLoader.TEXTURE_PATH,
	]:
		_check(ResourceLoader.exists(path), "%s imported" % path.get_file())
		var texture := ResourceLoader.load(path) as Texture2D
		_check(texture != null, "%s loads" % path.get_file())
		if texture != null:
			var dimensions := texture.get_size()
			_check(maxf(dimensions.x, dimensions.y) <= 2048.0,
				"%s max dimension <= 2048" % path.get_file())
	_check(FrontEndBackdrop.preload_assets().size() == 2,
		"backdrop cache exposes two orientations")
	_check(PenguinLoader.loader_texture() != null, "loader cache populated")
	_check(TitleScreen.logo_texture() != null, "title logo raster populated")


func _check_crop_contract() -> void:
	var texture_sizes := [Vector2(1672.0, 941.0), Vector2(941.0, 1672.0)]
	var targets := [
		Vector2(540.0, 960.0), Vector2(1080.0, 1920.0),
		Vector2(960.0, 540.0), Vector2(1920.0, 1080.0),
		Vector2(2400.0, 1080.0), Vector2(1600.0, 1200.0),
	]
	for target: Vector2 in targets:
		var portrait := target.y >= target.x
		var texture_size: Vector2 = texture_sizes[1] if portrait else texture_sizes[0]
		var rect := FrontEndBackdrop.cover_source_rect(
			texture_size, target, Vector2(0.5, 0.52), 1.009)
		_check(rect.position.x >= -0.001 and rect.position.y >= -0.001
			and rect.end.x <= texture_size.x + 0.001
			and rect.end.y <= texture_size.y + 0.001,
			"cover crop remains inside texture at %dx%d" % [target.x, target.y])
		_check(absf(rect.size.x / rect.size.y - target.x / target.y) < 0.002,
			"cover crop preserves aspect at %dx%d" % [target.x, target.y])


func _check_runtime_trees() -> void:
	var backdrop := FrontEndBackdrop.new()
	backdrop.size = Vector2(960.0, 540.0)
	add_child(backdrop)
	await get_tree().process_frame
	_check(not backdrop.is_using_portrait_art(), "landscape selects landscape art")
	backdrop.size = Vector2(540.0, 960.0)
	await get_tree().process_frame
	_check(backdrop.is_using_portrait_art(), "portrait selects portrait art")
	backdrop.set_reduced_motion(true)
	_check(not backdrop.is_motion_active(), "backdrop reduced motion is static")
	_check_no_forbidden_nodes(backdrop, "backdrop")
	backdrop.queue_free()
	await get_tree().process_frame

	var loader := PenguinLoader.new(260.0)
	add_child(loader)
	await get_tree().process_frame
	_check(loader.custom_minimum_size == Vector2(260.0, 260.0),
		"loader preserves public size constructor")
	loader.set_progress(0.63)
	_check(is_equal_approx(loader.get_progress(), 0.63),
		"loader determinate progress seam")
	loader.set_reduced_motion(true)
	_check(not loader.is_motion_active(), "loader reduced motion is static")
	_check_no_forbidden_nodes(loader, "loader")
	loader.queue_free()
	await get_tree().process_frame

	var packed := load("res://scenes/ui/title.tscn") as PackedScene
	var title := packed.instantiate()
	add_child(title)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(title.get_node_or_null("ExpeditionBackdrop") != null,
		"title owns authored backdrop")
	_check(_find_named(title, &"BeginExpedition") != null,
		"title owns semantic Begin CTA")
	_check_no_forbidden_nodes(title, "title")
	title.queue_free()
	await get_tree().process_frame


func _check_no_forbidden_nodes(root: Node, label: String) -> void:
	var forbidden := _first_forbidden_node(root)
	_check(forbidden == null, "%s tree is Canvas-only%s" % [
		label, "" if forbidden == null else " (found %s)" % forbidden.get_class()])


func _first_forbidden_node(node: Node) -> Node:
	if node is Node3D or node is SubViewport or node is GPUParticles2D \
			or node is GPUParticles3D or node is CPUParticles2D \
			or node is CPUParticles3D:
		return node
	for child: Node in node.get_children():
		var found := _first_forbidden_node(child)
		if found != null:
			return found
	return null


func _find_named(node: Node, target: StringName) -> Node:
	if node.name == target:
		return node
	for child: Node in node.get_children():
		var found := _find_named(child, target)
		if found != null:
			return found
	return null


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		print("[frontend] PASS %s" % message)
	else:
		_failures += 1
		print("[frontend] FAIL %s" % message)
