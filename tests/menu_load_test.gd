extends Node
## Headless menu smoke test. Launch with:
##   godot --headless res://tests/menu_load_test.tscn
## Instantiates every menu scene, verifies each builds a real UI tree, then
## drives SceneRouter to the main menu to prove headless navigation works.
## Prints "[menu] PASS/FAIL/SKIP <name>", exits 0 only when nothing failed.

const MENU_SCENES: PackedStringArray = [
	"res://scenes/ui/title.tscn",
	"res://scenes/menus/main_menu.tscn",
	"res://scenes/menus/mode_select.tscn",
	"res://scenes/menus/results.tscn",
	"res://scenes/menus/settings.tscn",
	"res://scenes/menus/controls.tscn",
	"res://scenes/menus/customize.tscn",
	"res://scenes/menus/achievements.tscn",
	"res://scenes/menus/credits.tscn",
]

var _failures: int = 0


func _ready() -> void:
	print("[menu] menu load test starting")
	await get_tree().process_frame
	_prefill_game_state()

	for path: String in MENU_SCENES:
		var short := path.get_file()
		if not ResourceLoader.exists(path):
			print("[menu] SKIP %s: scene not written yet (parallel stream)" % short)
			push_warning("menu load test skipped %s" % short)
			continue
		var packed: PackedScene = load(path)
		if packed == null:
			_fail(short, "load() returned null")
			continue
		var instance := packed.instantiate()
		add_child(instance)
		await get_tree().process_frame
		await get_tree().process_frame
		var node_count := _count_nodes(instance)
		if instance.get_script() == null:
			_fail(short, "root node has no script")
		elif node_count <= 3:
			_fail(short, "only %d nodes built" % node_count)
		else:
			print("[menu] PASS %s (%d nodes)" % [short, node_count])
		instance.queue_free()
		await get_tree().process_frame

	# Navigation check: SceneRouter must reach the main menu headlessly.
	# The monitor lives under the tree root so it survives the scene swap
	# (this scene is freed by change_scene_to_file).
	var monitor := NavMonitor.new()
	monitor.prior_failures = _failures
	get_tree().root.add_child(monitor)
	SceneRouter.go_to(Game.SCENE_MAIN_MENU)


func _prefill_game_state() -> void:
	Game.mode = Game.Mode.QUICK_RACE
	Game.course_id = "glacier"
	var rows: Array[Dictionary] = []
	for i: int in 8:
		rows.append({
			"key": "player" if i == 0 else "rival_%d" % i,
			"name": "You" if i == 0 else "Rival %d" % i,
			"is_player": i == 0,
			"position": i + 1,
			"time": 95.0 + float(i) * 3.5,
			"fish": 18 - i,
			"dnf": false,
		})
	Game.last_race_results = rows
	Game.last_rewards = {"fish": 63, "xp": 145, "unlocks": []}


func _fail(short: String, reason: String) -> void:
	_failures += 1
	print("[menu] FAIL %s: %s" % [short, reason])


func _count_nodes(node: Node) -> int:
	var count := 1
	for child: Node in node.get_children():
		count += _count_nodes(child)
	return count


class NavMonitor:
	extends Node
	## Waits for SceneRouter to land on the main menu, then reports and quits.

	var prior_failures: int = 0
	var _frames: int = 0

	func _process(_delta: float) -> void:
		_frames += 1
		var scene := get_tree().current_scene
		if scene != null and scene.name == "MainMenu":
			print("[menu] PASS scene_router_navigation")
			print("[menu] DONE: %d failures" % prior_failures)
			get_tree().quit(1 if prior_failures > 0 else 0)
			return
		if _frames > 300:
			var current := scene.name if scene != null else &"null"
			print("[menu] FAIL scene_router_navigation: current_scene=%s" % current)
			print("[menu] DONE: %d failures" % (prior_failures + 1))
			get_tree().quit(1)
