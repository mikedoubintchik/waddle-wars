extends RefCounted
## Owns abandoned ResourceLoader requests until they become terminal. Each
## accepted request must be collected once, including FAILED requests. Paths
## are counted because another owner may request the same resource meanwhile.
## No nodes/resources/callback owners from the outgoing scene are retained.

const MAX_COMPLETIONS_PER_FRAME := 8
static var _pending: Dictionary = {}
static var _tree: SceneTree = null
static var _shutdown_root: Node = null
static var _shutting_down := false


static func watch_shutdown() -> void:
	if is_instance_valid(_shutdown_root):
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null or not tree.root.is_inside_tree():
		return
	_shutdown_root = tree.root
	# The root outlives scene changes. Its exit signal runs after child exit
	# callbacks, and before resource destructors can hand off any final tokens.
	_shutdown_root.tree_exiting.connect(_on_root_exiting, CONNECT_ONE_SHOT)


static func abandon(path: String) -> void:
	if path.is_empty():
		return
	watch_shutdown()
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		return
	if _shutting_down or status in [ResourceLoader.THREAD_LOAD_LOADED, ResourceLoader.THREAD_LOAD_FAILED]:
		ResourceLoader.load_threaded_get(path)
		return
	_pending[path] = int(_pending.get(path, 0)) + 1
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null or not tree.root.is_inside_tree():
		return
	_tree = tree
	if not _tree.process_frame.is_connected(_poll):
		_tree.process_frame.connect(_poll)


static func pending_request_count() -> int:
	var total := 0
	for count: int in _pending.values():
		total += count
	return total


static func _poll() -> void:
	var completed := 0
	for path: String in _pending.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		if status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_pending.erase(path)
			continue
		# LOADED and FAILED both own tokens. Only terminal gets are nonblocking.
		ResourceLoader.load_threaded_get(path)
		var remaining := int(_pending[path]) - 1
		if remaining == 0:
			_pending.erase(path)
		else:
			_pending[path] = remaining
		completed += 1
		if completed >= MAX_COMPLETIONS_PER_FRAME:
			break
	if _pending.is_empty() and is_instance_valid(_tree):
		_tree.process_frame.disconnect(_poll)
		_tree = null


static func _on_root_exiting() -> void:
	# Only whole-engine teardown may join an unfinished job. Runtime scene
	# removal uses _poll and never waits. Mark this before collecting: catalog
	# Resources can hand off more tokens from their subsequent PREDELETE.
	_shutting_down = true
	if is_instance_valid(_tree) and _tree.process_frame.is_connected(_poll):
		_tree.process_frame.disconnect(_poll)
	_tree = null
	for path: String in _pending.keys():
		var count := int(_pending[path])
		_pending.erase(path)
		for index: int in count:
			if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				break
			ResourceLoader.load_threaded_get(path)
