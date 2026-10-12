extends Node
## Real ResourceLoader jobs with a semaphore-controlled format loader. The
## worker cannot finish until this scene yields frames and releases it, so a
## blocking main-thread get during abandonment deadlocks and fails the external
## watchdog. No rendering, save writes or simulated ResourceLoader statuses.

const DRAIN = preload("res://scripts/utilities/threaded_resource_drain.gd")
const LIBRARY = preload("res://scripts/ui/wardrobe_outfit_library.gd")
var _loader := ControlledLoader.new()
var _passed := 0
var _failed := 0
var _shutdown_case := false
var _exit_catalog: ArtCatalog = null
var _shutdown_paths: Array[String] = []


class ControlledLoader extends ResourceFormatLoader:
	var lock := Mutex.new()
	var gate := Semaphore.new()
	var started := 0

	func _get_recognized_extensions() -> PackedStringArray:
		return PackedStringArray(["wwlifetest"])

	func _handles_type(type: StringName) -> bool:
		return type == &"Resource"

	func _get_resource_type(_path: String) -> String:
		return "Resource"

	func _exists(_path: String) -> bool:
		return true

	func _load(path: String, _original_path: String, _use_sub_threads: bool, _cache_mode: int) -> Variant:
		lock.lock()
		started += 1
		lock.unlock()
		gate.wait()
		if "shutdown" in path:
			# Keeps jobs genuinely in progress after all child exit callbacks.
			OS.delay_msec(100)
		return ERR_CANT_OPEN if "failure" in path else Resource.new()

	func count() -> int:
		lock.lock()
		var value := started
		lock.unlock()
		return value


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _run() -> void:
	ResourceLoader.add_resource_format_loader(_loader, true)
	if "shutdown=1" in OS.get_cmdline_user_args():
		await _test_engine_shutdown()
		return
	for action: String in ["clear", "reload", "destroy", "wardrobe_close"]:
		await _test_abandon(action)
	await _test_shared_path()
	await _test_failure(false)
	await _test_failure(true)
	await _test_failed_abandon()
	_test_mountain_cache()
	_check("final drain empty and disconnected", DRAIN.pending_request_count() == 0 and DRAIN._tree == null)
	ResourceLoader.remove_resource_format_loader(_loader)
	_loader = null
	print("[threaded_resource_lifetime] DONE: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed else 0)


func _test_engine_shutdown() -> void:
	get_tree().root.tree_exiting.connect(_observe_shutdown_before_join)
	DRAIN.watch_shutdown()
	_shutdown_paths = ["res://tests/fixtures/shutdown_wardrobe.wwlifetest",
		"res://tests/fixtures/shutdown_catalog.wwlifetest"]
	for path: String in _shutdown_paths:
		await _request(path)
	var library := LIBRARY.new()
	add_child(library)
	library._pending_path = _shutdown_paths[0]
	_exit_catalog = ArtCatalog.new()
	_exit_catalog._pending["fixture"] = _shutdown_paths[1]
	_check("runtime shutdown flag remains false", not DRAIN._shutting_down)
	_shutdown_case = true
	# Both workers remain blocked. The root-exit handler must collect the
	# wardrobe handoff; the later catalog destructor must use shutdown mode.
	get_tree().quit(0)


func _observe_shutdown_before_join() -> void:
	for path: String in _shutdown_paths:
		_check("worker remains unfinished at actual root exit: " + path,
			ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS)


func _exit_tree() -> void:
	if _shutdown_case:
		for path: String in _shutdown_paths:
			_loader.gate.post()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _shutdown_case:
		_exit_catalog = null
		var clean := DRAIN._shutting_down and DRAIN.pending_request_count() == 0
		for path: String in _shutdown_paths:
			clean = clean and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
		print("[threaded_resource_shutdown] %s both tokens consumed during actual root teardown" % ("PASS" if clean and _failed == 0 else "FAIL"))
		ResourceLoader.remove_resource_format_loader(_loader)
		_loader = null


func _request(path: String) -> void:
	var before := _loader.count()
	_check("request accepted: " + path, ResourceLoader.load_threaded_request(path, "Resource", false, ResourceLoader.CACHE_MODE_IGNORE) == OK)
	var deadline := Time.get_ticks_msec() + 5000
	while _loader.count() == before and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check("real worker blocked before completion", _loader.count() == before + 1 and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS)


func _wait_terminal(path: String) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check("worker reaches terminal state", ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_IN_PROGRESS)


func _wait_drained(path: String) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while DRAIN.pending_request_count() > 0 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check("all abandoned ownership collected: " + path, DRAIN.pending_request_count() == 0 and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE)


func _test_abandon(action: String) -> void:
	var path := "res://tests/fixtures/" + action + ".wwlifetest"
	await _request(path)
	var catalog: ArtCatalog = ArtCatalog.new()
	catalog._pending["fixture"] = path
	match action:
		"clear": catalog.clear_runtime_cache()
		"reload":
			catalog.manifest_path = "res://tests/fixtures/art/catalog.json"
			catalog.strict_paths = false
			_check("reload still validates manifest", catalog.reload_manifest() == OK)
		"destroy":
			var weak: WeakRef = weakref(catalog)
			catalog = null
			_check("outgoing catalog itself released", weak.get_ref() == null)
		"wardrobe_close":
			# Transfer the actual request to a normal wardrobe owner before exit.
			catalog._pending.clear()
			var library := LIBRARY.new()
			add_child(library)
			library._pending_path = path
			library.free()
	_check("abandon transfers one request: " + action, DRAIN.pending_request_count() == 1)
	get_tree().paused = true
	for frame: int in 3:
		await get_tree().process_frame
	_check("main loop advances while worker held: " + action, ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS)
	_loader.gate.post()
	await _wait_drained(path)
	get_tree().paused = false
	_check("ordinary owner exit never enables shutdown joins: " + action, not DRAIN._shutting_down)
	catalog = null


func _test_shared_path() -> void:
	var path := "res://tests/fixtures/shared.wwlifetest"
	await _request(path)
	var started := _loader.count()
	for index: int in 12:
		if index > 0:
			_check("same-path request accepted", ResourceLoader.load_threaded_request(path, "Resource", false, ResourceLoader.CACHE_MODE_IGNORE) == OK)
		var catalog := ArtCatalog.new()
		catalog._pending["fixture"] = path
		catalog.clear_runtime_cache()
	_check("repeated abandons counted, one underlying job", DRAIN.pending_request_count() == 12 and _loader.count() == started)
	_check("new active owner adopts same pending path", ResourceLoader.load_threaded_request(path, "Resource", false, ResourceLoader.CACHE_MODE_IGNORE) == OK)
	_loader.gate.post()
	await _wait_terminal(path)
	var live := ResourceLoader.load_threaded_get(path)
	_check("cleanup preserves active owner's result", live != null)
	live = null
	await _wait_drained(path)


func _test_failure(wardrobe: bool) -> void:
	var path := "res://tests/fixtures/failure_%s.wwlifetest" % ("wardrobe" if wardrobe else "catalog")
	await _request(path)
	print("[threaded_resource_lifetime] EXPECTED loader failure: " + path)
	_loader.gate.post()
	await _wait_terminal(path)
	_check("actual loader failure retained before consumer", ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_FAILED)
	if wardrobe:
		var library := LIBRARY.new()
		add_child(library)
		library._pending_path = path
		library._pending_key = "failed"
		library.requested_key = "failed"
		library._process(0.0)
		_check("wardrobe failure remains unavailable", library.state == "unavailable" and library._pending_path.is_empty())
		library.free()
	else:
		var catalog := ArtCatalog.new()
		catalog._pending["fixture"] = path
		var status := catalog.poll_preload()
		_check("catalog failure remains reported", status["failed"] == 1 and status["complete"])
	_check("failed token collected exactly once", ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE)


func _test_failed_abandon() -> void:
	var path := "res://tests/fixtures/failure_abandoned.wwlifetest"
	await _request(path)
	DRAIN.abandon(path)
	print("[threaded_resource_lifetime] EXPECTED loader failure: " + path)
	_loader.gate.post()
	await _wait_drained(path)


func _test_mountain_cache() -> void:
	var before := VisualLibrary.cache_sizes().y
	for seed_value: int in 1024:
		CourseEndless._mountain_mesh(seed_value)
	var after := VisualLibrary.cache_sizes().y
	_check("1024 different run seeds retain at most16 meshes", after - before <= CourseEndless.MOUNTAIN_MESH_VARIANTS)
	for seed_value: int in range(1024, 2048):
		CourseEndless._mountain_mesh(seed_value)
	_check("later runs do not grow mountain mesh cache", VisualLibrary.cache_sizes().y == after)
	_check("same seed retains same mesh identity", CourseEndless._mountain_mesh(19) == CourseEndless._mountain_mesh(19))


func _check(label: String, ok: bool) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
	print("[threaded_resource_lifetime] %s %s" % ["PASS" if ok else "FAIL", label])
