extends SceneTree
## Run outside the PCK against --main-pack in an empty directory. This catches
## excluded preload dependencies that a project-directory test can still find.
var passed := 0
var failed := 0
var checks: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var packed := load("res://scenes/menus/mode_select.tscn") as PackedScene
	_check(packed != null, "Race setup PackedScene loads")
	if packed == null:
		_finish()
		return
	var menu := packed.instantiate() as Control
	_check(menu != null and menu.get_script() != null and menu.has_method("_show_mode_step"),
		"Actual Race setup instance retains executable script and preload dependencies")
	if menu == null or menu.get_script() == null:
		if menu != null: menu.free()
		_finish()
		return
	root.add_child(menu)
	await process_frame
	await process_frame
	_check(menu.get("_content") != null and menu.get_child_count() > 0, "Race setup constructs live UI")
	_check(menu.get("_step") == "mode" and menu.get("_buttons").size() == 5,
		"Four mode actions and Back constructed")
	menu.call("_show_course_step")
	await process_frame
	_check(menu.get("_step") == "course" and menu.get("_buttons").size() == 6,
		"Five real course selections and Back constructed")
	var constants: Dictionary = menu.get_script().get_script_constant_map()
	var posters: Dictionary = constants.get("COURSE_POSTER_TEXTURES", {})
	_check(posters.size() == 6, "All six required authored poster resources instantiated")
	for key: String in ["aurora", "cinder", "glacier", "hollow", "iceberg", "tutorial"]:
		var texture := posters.get(key) as Texture2D
		var decoded := texture.get_image() if texture != null else null
		_check(decoded != null and not decoded.is_empty() and decoded.get_width() > 0 and decoded.get_height() > 0,
			"Packed course poster decoded: " + key)
	menu.call("_show_difficulty_step")
	await process_frame
	_check(menu.get("_step") == "difficulty" and menu.get("_buttons").size() == 4,
		"Three difficulty actions and Back constructed")
	menu.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	_finish()

func _check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if ok: passed += 1
	else: failed += 1

func _finish() -> void:
	print("CHROME_PACKED_MENU " + JSON.stringify({"passed": passed, "failed": failed, "checks": checks}))
	quit(1 if failed else 0)
