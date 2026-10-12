extends Node
## Dev export only: preserve menu/page selection, never change saved settings.
## Live-reload verification: comment-only edit, no gameplay or save changes.
var _remaining := 0.0
var _restore: Dictionary = {}
var _restoring := true
var _routed := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_feature("web"):
		set_process(false)
		return
	var raw: Variant = JavaScriptBridge.eval("JSON.stringify(parent.__wwDevRestoreState || {})", true)
	if raw is String:
		var parsed: Variant = JSON.parse_string(raw)
		if parsed is Dictionary:
			_restore = parsed

func _process(delta: float) -> void:
	_remaining -= delta
	if _remaining > 0.0 or SceneRouter.is_busy():
		return
	_remaining = 0.5
	var current := get_tree().current_scene
	if current == null or not current.scene_file_path.begins_with("res://scenes/menus/"):
		return
	if _restoring:
		var target := String(_restore.get("path", ""))
		if not target.is_empty() and target.begins_with("res://scenes/menus/") and ResourceLoader.exists(target):
			if current.scene_file_path != target and not _routed:
				_routed = true
				SceneRouter.go_to(target)
				return
			if current.scene_file_path == target:
				if current.has_method("restore_navigation_state"):
					current.call("restore_navigation_state", _restore.get("state", {}))
				if target.ends_with("/customize.tscn"):
					var category := String(_restore.get("category", "body"))
					if category in CosmeticsDB.CATEGORIES:
						current.call("_select_category", category)
		_restoring = false
	var state := {"path": current.scene_file_path}
	if current.has_method("get_navigation_state"):
		state["state"] = current.call("get_navigation_state")
	if current.scene_file_path.ends_with("/customize.tscn"):
		state["category"] = current.get("_current_category")
	JavaScriptBridge.eval("window.__wwDevPageState = " + JSON.stringify(state), true)
