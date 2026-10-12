@tool
extends "res://qa_motion/surface_post_import.gd"
## Retain imported resources; persist declared loops and source-authored specular.

func _post_import(scene: Node) -> Object:
	var imported: Object = super._post_import(scene)
	if imported == null:
		return null
	var binding: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://qa_motion/candidate_binding.json"))
	if not binding is Dictionary or binding.get("gate") != "rear-motion-v1":
		push_error("Motion import binding missing")
		return null
	var revision: Dictionary = binding.get("material_revision", {})
	if not revision.is_empty():
		if revision.get("id") != "charcoal-feather-contrast-v1" or revision.get("specular") != 0.15 \
				or binding.materials[0].get("specular") != 0.15:
			push_error("Unknown source-authored motion surface revision")
			return null
		for raw: Node in scene.find_children("*", "MeshInstance3D", true, false):
			var instance := raw as MeshInstance3D
			for surface: int in instance.mesh.get_surface_count():
				var material := instance.mesh.surface_get_material(surface) as StandardMaterial3D
				if material == null or not is_equal_approx(material.metallic_specular, 0.5):
					push_error("Unexpected imported motion specular before source recipe")
					return null
				# Godot 4.7's GLTF importer lacks KHR_materials_specular support.
				# Apply the bound Blender intent once to this same imported material.
				material.metallic_specular = 0.15
				material.set_meta("motion_surface_revision", revision.id)
	var players: Array[Node] = scene.find_children("*", "AnimationPlayer", true, false)
	var skeletons: Array[Node] = scene.find_children("*", "Skeleton3D", true, false)
	if players.size() != 1 or skeletons.size() != 1:
		push_error("Motion import requires one actual skeleton and AnimationPlayer")
		return null
	var skeleton := skeletons[0] as Skeleton3D
	var names: Array = []
	for bone: int in skeleton.get_bone_count():
		names.append(skeleton.get_bone_name(bone))
	var actual_parents: Dictionary = {}
	for bone: int in skeleton.get_bone_count():
		var parent: int = skeleton.get_bone_parent(bone)
		actual_parents[skeleton.get_bone_name(bone)] = skeleton.get_bone_name(parent) if parent >= 0 else null
	var expected_parents: Dictionary = {}
	for index: int in binding.rig.joints.size():
		expected_parents[binding.rig.joints[index]] = binding.rig.parents[index]
	var sorted_names: Array = names.duplicate()
	var expected_names: Array = binding.rig.joints.duplicate()
	sorted_names.sort()
	expected_names.sort()
	if sorted_names != expected_names or names.size() != actual_parents.size() or actual_parents != expected_parents:
		push_error("Imported motion names/parents differ from source; actual=" + str(names) + " parents=" + str(actual_parents))
		return null
	var player := players[0] as AnimationPlayer
	var wanted: Array = binding.clips.keys()
	var actual: Array = Array(player.get_animation_list())
	wanted.sort()
	actual.sort()
	if actual != wanted:
		push_error("Imported motion clips differ from source: " + str(actual))
		return null
	for clip_name: String in wanted:
		var clip := player.get_animation(clip_name)
		var contract: Dictionary = binding.clips[clip_name]
		if absf(clip.length - float(contract.duration)) > 0.0001 or clip.get_track_count() == 0:
			push_error("Imported motion clip length/tracks differ: " + clip_name)
			return null
		for track: int in clip.get_track_count():
			var kind: int = clip.track_get_type(track)
			var path: NodePath = clip.track_get_path(track)
			if kind not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D] \
					or path.get_subname_count() != 1 or not names.has(String(path.get_subname(0))) \
					or clip.track_get_key_count(track) < 1 \
					or (clip.track_get_key_count(track) == 1 and not _source_track_constant(contract, String(path.get_subname(0)), kind)):
				push_error("Imported motion must contain keyed joint-only TRS: " + JSON.stringify({"clip": clip_name, "track": track, "path": String(path), "type": kind, "subnames": path.get_subname_count(), "keys": clip.track_get_key_count(track), "name_known": path.get_subname_count() == 1 and names.has(String(path.get_subname(0))), "bone_names": names}))
				return null
			var expected_keys := _source_nonconstant_track_keys(contract, String(path.get_subname(0)), kind)
			if expected_keys >= 0 and clip.track_get_key_count(track) != expected_keys:
				push_error("Imported motion optimizer/resampling changed source keys: " + JSON.stringify({"clip": clip_name,
					"path": String(path), "type": kind, "actual_keys": clip.track_get_key_count(track), "source_keys": expected_keys}))
				return null
		clip.loop_mode = Animation.LOOP_LINEAR if contract.loop else Animation.LOOP_NONE
	return scene


func _source_track_constant(contract: Dictionary, bone: String, kind: int) -> bool:
	var property: String = {Animation.TYPE_POSITION_3D: "translation",
		Animation.TYPE_ROTATION_3D: "rotation", Animation.TYPE_SCALE_3D: "scale"}.get(kind, "")
	for track: Dictionary in contract.get("tracks", []):
		if track.get("joint") == bone and track.get("path") == property:
			return track.get("constant") == true
	return false


func _source_nonconstant_track_keys(contract: Dictionary, bone: String, kind: int) -> int:
	var property: String = {Animation.TYPE_POSITION_3D: "translation",
		Animation.TYPE_ROTATION_3D: "rotation", Animation.TYPE_SCALE_3D: "scale"}.get(kind, "")
	for track: Dictionary in contract.get("tracks", []):
		if track.get("joint") == bone and track.get("path") == property:
			return -1 if track.get("constant") == true else int(track.get("keys", 0))
	return 0
