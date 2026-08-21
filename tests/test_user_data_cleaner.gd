extends SceneTree
## Removes only the temporary custom user:// created by run_tests.sh.
## Run as a main-loop script so project autoloads cannot recreate save data
## after the cleanup has finished.

var _failed: bool = false


func _init() -> void:
	var root_path := ProjectSettings.globalize_path("user://")
	_remove_contents(root_path)
	# `use_custom_user_dir` creates this directory outside the temporary project
	# tree. Removing only its contents leaves one empty Application Support entry
	# after every case/suite. This script runs without project autoloads and its
	# working directory is the project snapshot, so the isolated root is safe to
	# remove after its children are gone.
	var root_error := DirAccess.remove_absolute(root_path)
	if root_error != OK and DirAccess.dir_exists_absolute(root_path):
		_failed = true
	if _failed:
		push_error("test_user_data_cleaner: could not fully clean %s" % root_path)
	quit(1 if _failed else 0)


func _remove_contents(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var names := PackedStringArray()
	var name := dir.get_next()
	while name != "":
		if name != "." and name != "..":
			names.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	for entry: String in names:
		var child := path.path_join(entry)
		if DirAccess.dir_exists_absolute(child):
			_remove_contents(child)
		var err := DirAccess.remove_absolute(child)
		if err != OK and (DirAccess.dir_exists_absolute(child) \
				or FileAccess.file_exists(child)):
			_failed = true
