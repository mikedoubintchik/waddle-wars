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

class MotionCapableBackdrop:
	extends FrontEndBackdrop

	func _motion_capable() -> bool:
		return true

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	_check_source_contract()
	_check_asset_contract()
	_check_crop_contract()
	await _check_runtime_trees()
	await _check_entrance_reflow()
	await _check_entrance_unmanaged_and_guards()
	await _check_settings_categories()
	# Let the dummy/headless mixer retire real UI hover/click playback before
	# teardown. Two uncapped visual frames do not advance that audio clock.
	for player: AudioStreamPlayer in AudioManager._sfx_pool:
		player.stop()
		player.stream = null
	for player: AudioStreamPlayer in [AudioManager._music_a, AudioManager._music_b]:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.25).timeout
	print("[frontend] DONE: %d/%d checks passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)


func _check_settings_categories() -> void:
	var scene := load("res://scenes/menus/settings.tscn") as PackedScene
	_check(scene != null, "settings category scene exists")
	if scene == null:
		return
	var menu := scene.instantiate() as Control
	add_child(menu)
	await get_tree().process_frame
	var representative := {
		"gameplay": "Settings_gameplay_steer_sensitivity",
		"accessibility": "Settings_accessibility_camera_shake",
		"audio": "Settings_audio_master_volume",
		"online": "SettingsSection_online",
		"display": "Settings_display_quality_preset",
	}
	for id: String in representative.keys():
		_check(menu.find_child("SettingsCategory_%s" % id, true, false) != null,
			id + " destination reachable")
		menu.set("_active", id)
		menu.call("_rebuild")
		_check(String(menu.get("_active")) == id, id + " category selected")
		_check(menu.find_child(String(representative[id]), true, false) != null,
			id + " displays live controls")
	menu.queue_free()
	await get_tree().process_frame


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
	var backdrop := MotionCapableBackdrop.new()
	backdrop.size = Vector2(960.0, 540.0)
	add_child(backdrop)
	await get_tree().process_frame
	_check(not backdrop.is_using_portrait_art(), "landscape selects landscape art")
	backdrop.size = Vector2(540.0, 960.0)
	await get_tree().process_frame
	_check(backdrop.is_using_portrait_art(), "portrait selects portrait art")
	backdrop.set_reduced_motion(false)
	await get_tree().process_frame
	_check(backdrop._motion_requested(), "visible backdrop requests drift")
	_check(backdrop.is_motion_active(), "visible capable backdrop processes drift")
	var elapsed_before_local_hide: float = backdrop._elapsed
	backdrop.hide()
	await get_tree().process_frame
	_check(not backdrop._motion_requested(), "locally hidden backdrop stops drift")
	_check(not backdrop.is_motion_active(), "locally hidden backdrop stops processing")
	_check(is_equal_approx(backdrop._elapsed, elapsed_before_local_hide),
		"locally hidden backdrop does not advance drift clock")
	backdrop.show()
	_check(backdrop.is_motion_active(), "shown backdrop restores drift processing")
	_check(is_equal_approx(backdrop._elapsed, elapsed_before_local_hide),
		"showing backdrop preserves drift phase")
	await get_tree().process_frame
	_check(backdrop._elapsed > elapsed_before_local_hide,
		"restored backdrop resumes drift clock")
	var backdrop_host := Control.new()
	add_child(backdrop_host)
	remove_child(backdrop)
	backdrop_host.add_child(backdrop)
	await get_tree().process_frame
	_check(backdrop._motion_requested(), "shown backdrop restores drift")
	var elapsed_before_hide: float = backdrop._elapsed
	backdrop_host.hide()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not backdrop._motion_requested(), "hidden ancestor stops backdrop drift")
	_check(not backdrop.is_motion_active(), "hidden ancestor stops backdrop processing")
	_check(is_equal_approx(backdrop._elapsed, elapsed_before_hide),
		"hidden ancestor does not advance backdrop drift clock")
	backdrop_host.show()
	_check(backdrop._motion_requested(), "shown ancestor restores backdrop drift")
	_check(backdrop.is_motion_active(), "shown ancestor restores backdrop processing")
	_check(is_equal_approx(backdrop._elapsed, elapsed_before_hide),
		"showing ancestor preserves backdrop drift phase")
	backdrop.set_reduced_motion(true)
	_check(not backdrop.is_motion_active(), "backdrop reduced motion is static")
	_check(not backdrop._motion_requested(), "reduced-motion backdrop never requests drift")
	_check_no_forbidden_nodes(backdrop, "backdrop")
	backdrop_host.queue_free()
	await get_tree().process_frame

	var loader := PenguinLoader.new(260.0)
	add_child(loader)
	await get_tree().process_frame
	_check(loader.custom_minimum_size == Vector2(260.0, 260.0),
		"loader preserves public size constructor")
	loader.set_progress(0.63)
	_check(is_equal_approx(loader.get_progress(), 0.63),
		"loader determinate progress seam")
	loader.set_progress(0.21)
	loader.set_progress(-1.0)
	_check(is_equal_approx(loader.get_progress(), 0.63),
		"loader never reverses through earlier or unknown phase")
	loader.reset_progress()
	_check(is_zero_approx(loader.get_progress()) \
		and is_zero_approx(loader.get_node("LoadingBar/LoadingActivity").anchor_right),
		"next load resets single forward fill")
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


func _check_entrance_reflow() -> void:
	var host := Control.new()
	host.size = Vector2(960.0, 540.0)
	add_child(host)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size = Vector2(460.0, 200.0)
	grid.add_theme_constant_override("v_separation", 12)
	host.add_child(grid)
	var race := Button.new()
	race.text = "Race"
	race.custom_minimum_size = Vector2(180.0, 80.0)
	grid.add_child(race)
	var runner := Button.new()
	runner.text = "Waddle Run"
	runner.custom_minimum_size = race.custom_minimum_size
	grid.add_child(runner)
	await get_tree().process_frame
	await get_tree().process_frame
	var race_landscape := race.position
	var runner_landscape := runner.position
	_check(is_equal_approx(race_landscape.y, runner_landscape.y)
		and runner_landscape.x >= race_landscape.x + race.size.x,
		"entrance fixture starts with distinct landscape columns")
	race.modulate.a = 0.0
	runner.modulate.a = 0.0
	# Public play_entrance deliberately skips headless runs. Exercise the real
	# helper and hold its real tweens while the container changes orientation.
	var tweens := _paused_entrance_tweens(host, [race, runner], 20.0)
	_check(tweens.size() == 2, "entrance creates one fade per grid item")
	_check(race.position.is_equal_approx(race_landscape)
		and runner.position.is_equal_approx(runner_landscape),
		"entrance leaves container-owned positions untouched")
	grid.columns = 1
	grid.size.x = 220.0
	await get_tree().process_frame
	await get_tree().process_frame
	var race_portrait := race.position
	var runner_portrait := runner.position
	_check(runner_portrait.y >= race_portrait.y + race.size.y + 12.0,
		"portrait reflow separates cards during entrance")
	for tween: Tween in tweens:
		tween.custom_step(1.0)
	_check(race.position.is_equal_approx(race_portrait)
		and runner.position.is_equal_approx(runner_portrait),
		"completed entrance preserves reflowed portrait positions")
	_check(not race.get_rect().intersects(runner.get_rect()),
		"completed entrance cannot overlap portrait cards")
	_check(is_equal_approx(race.modulate.a, 1.0)
		and is_equal_approx(runner.modulate.a, 1.0),
		"container-owned cards still finish entrance fade")
	host.queue_free()
	await get_tree().process_frame


func _check_entrance_unmanaged_and_guards() -> void:
	var host := Control.new()
	add_child(host)
	var item := Control.new()
	item.position = Vector2(30.0, 100.0)
	item.modulate = Color(0.7, 0.8, 0.9, 0.0)
	host.add_child(item)
	var target := item.position
	var tweens := _paused_entrance_tweens(host, [item], 20.0)
	_check(tweens.size() == 1 and item.position.is_equal_approx(target + Vector2(0.0, 20.0))
		and is_zero_approx(item.modulate.a), "unmanaged entrance retains initial rise and fade")
	for tween: Tween in tweens:
		tween.custom_step(1.0)
	_check(item.position.is_equal_approx(target)
		and item.modulate.is_equal_approx(Color(0.7, 0.8, 0.9, 1.0)),
		"unmanaged entrance lands and preserves color while fading")
	var freed := Control.new()
	host.add_child(freed)
	var detached := Control.new()
	detached.modulate.a = 0.0
	var guarded_items: Array[Control] = [freed, detached, item]
	freed.free()
	item.modulate.a = 0.0
	tweens = _paused_entrance_tweens(host, guarded_items, 20.0)
	_check(tweens.size() == 1 and is_zero_approx(detached.modulate.a)
		and detached.position == Vector2.ZERO, "entrance skips freed and detached items")
	for tween: Tween in tweens:
		tween.custom_step(1.0)
	_check(item.position.is_equal_approx(target) and is_equal_approx(item.modulate.a, 1.0),
		"entrance continues past freed items to live item")
	item.modulate.a = 0.0
	_check(_paused_entrance_tweens(detached, [item], 20.0).is_empty()
		and _paused_entrance_tweens(null, [item], 20.0).is_empty()
		and item.position.is_equal_approx(target) and is_zero_approx(item.modulate.a),
		"entrance rejects detached or invalid root without changing live item")
	detached.free()
	host.queue_free()
	await get_tree().process_frame


func _paused_entrance_tweens(root: Control, items: Array[Control], rise: float) -> Array[Tween]:
	var before := get_tree().get_processed_tweens()
	UITheme._start_entrance(root, items, rise)
	var created: Array[Tween] = []
	for tween: Tween in get_tree().get_processed_tweens():
		if tween not in before:
			tween.pause()
			created.append(tween)
	return created


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
