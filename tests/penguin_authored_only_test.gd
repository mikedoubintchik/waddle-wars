extends Node
## Allocation/lifetime contracts only. Actual render/motion gates remain with
## existing authored captures and browser/native quality checks.

var _checks: int = 0
var _failures: int = 0


class MissingAssetVisual:
	extends PenguinVisual

	func _instantiate_authored_backend() -> Node3D:
		return null


class IncompleteAsset:
	extends Node3D

	func missing_contract_items() -> PackedStringArray:
		return PackedStringArray(["test missing clip/socket"])


class IncompleteAssetVisual:
	extends PenguinVisual

	func _instantiate_authored_backend() -> Node3D:
		return IncompleteAsset.new()


func _ready() -> void:
	var previous_qa_backend := PenguinVisual.use_authored_backend_for_qa
	_check(not previous_qa_backend, "production keeps unapproved authored backend disabled")
	# This fixture verifies the retained authored candidate deliberately; enabling
	# it here must never promote that model in gameplay or menu previews.
	PenguinVisual.use_authored_backend_for_qa = true
	_test_authored_roles_skip_fallback()
	_test_species_sockets_and_cosmetics()
	_test_explicit_role_change_builds_lod()
	_test_asset_failure_and_legacy()
	await _test_reused_facade_lifetime()
	print("[penguin_authored_only] %d checks, %d failures" % [_checks, _failures])
	PenguinVisual.use_authored_backend_for_qa = previous_qa_backend
	get_tree().quit(1 if _failures > 0 else 0)


func _check(ok: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if ok:
		return
	_failures += 1
	print("[penguin_authored_only] FAIL %s%s" % [label,
			": " + detail if not detail.is_empty() else ""])


func _new_visual(role: int, config: Dictionary = {}) -> PenguinVisual:
	var visual := PenguinVisual.new()
	add_child(visual)
	visual.setup_look(CharacterLook.from_legacy_config(config, role))
	return visual


func _test_authored_roles_skip_fallback() -> void:
	for role: int in [CharacterLook.RenderRole.HERO, CharacterLook.RenderRole.GHOST]:
		var mesh_cache_before := PenguinVisual._mesh_cache.size()
		var material_cache_before := PenguinVisual._material_cache.size()
		var visual := _new_visual(role, {"species": "emperor"})
		var backend := visual.get_node_or_null("AuthoredHeroPenguin") as HeroPenguinRig
		_check(backend != null and visual.is_authored_backend_active(),
				"role %d retains shipped authored rig" % role)
		_check(visual.get_node_or_null("SpeciesScale") == null \
				and visual._root == null and visual._body == null,
				"role %d allocates no hidden procedural branch" % role)
		_check(PenguinVisual._mesh_cache.size() == mesh_cache_before \
				and PenguinVisual._material_cache.size() == material_cache_before,
				"role %d does not mint procedural mesh/material cache entries" % role)
		if backend != null:
			var transform_before := backend.transform
			var position_before := Vector3(4.0, 2.0, -9.0)
			visual.position = position_before
			visual.drive_motion(0.9, 0.4, 0.1, 0.0, true)
			visual.trigger_event(&"jumped")
			visual.tick(1.0 / 60.0, 0.9)
			visual.trigger_event(&"landed")
			visual.trigger_event(&"hit", {"strength": 0.8, "side": -1.0})
			var recovery_frames := ceili((PenguinVisual.TUMBLE_TIME + 0.25) * 60.0)
			for _frame: int in recovery_frames:
				visual.tick(1.0 / 60.0, 0.9)
			_check(backend.transform.is_equal_approx(transform_before) \
					and visual.position.is_equal_approx(position_before),
					"role %d authored animation preserves movement authority" % role)
			_check(visual._tumble_t < 0.0 and absf(visual._squash - 1.0) < 0.001,
					"role %d unused procedural effects expire without geometry" % role,
					"tumble_t=%.6f squash=%.6f elapsed=%.6f" % [visual._tumble_t,
							visual._squash, float(recovery_frames) / 60.0])
		visual.free()


func _test_species_sockets_and_cosmetics() -> void:
	for species: String in PenguinVisual.SPECIES.keys():
		var look := CharacterLook.from_legacy_config({"species": species,
				"hat": "hat_beanie", "scarf": "scarf_red", "goggles": "goggles_ski"},
				CharacterLook.RenderRole.HERO)
		var visual := PenguinVisual.new()
		add_child(visual)
		visual.setup_look(look)
		var sockets_resolve := true
		for socket_id: String in CharacterLook.REQUIRED_SOCKETS:
			sockets_resolve = sockets_resolve and visual.get_socket(StringName(socket_id)) != null
		_check(sockets_resolve and visual._root == null,
				"%s keeps authored socket contract without fallback" % species)
		var head := visual.get_socket(&"head_socket")
		var face := visual.get_socket(&"face_socket")
		var neck := visual.get_socket(&"neck_socket")
		_check(head != null and face != null and neck != null \
				and not head.find_children("*", "GeometryInstance3D", true, false).is_empty() \
				and not face.find_children("*", "GeometryInstance3D", true, false).is_empty() \
				and not neck.find_children("*", "GeometryInstance3D", true, false).is_empty(),
				"%s cosmetics still attach to authored sockets" % species)
		visual.free()


func _test_explicit_role_change_builds_lod() -> void:
	var look := CharacterLook.from_legacy_config({"species": "little_blue",
			"hat": "hat_beanie"}, CharacterLook.RenderRole.HERO)
	look.visual_offset = Vector3(0.2, 0.1, -0.3)
	look.visual_rotation_degrees = Vector3(0.0, 9.0, 0.0)
	look.visual_scale = Vector3.ONE * 1.2
	var visual := PenguinVisual.new()
	add_child(visual)
	visual.setup_look(look)
	var backend := visual.get_node("AuthoredHeroPenguin")
	var head := visual.get_socket(&"head_socket")
	var cosmetic_count := head.get_child_count()
	visual.set_pose(PenguinVisual.Pose.RUN)
	visual.tick(0.4, 0.9)
	visual.set_render_role(PenguinVisual.RenderRole.RACER)
	_check(visual._root != null and visual.get_node_or_null("SpeciesScale") != null,
			"explicit RACER role constructs required far LOD")
	_check(visual.get_node("AuthoredHeroPenguin") == backend \
			and visual.get_socket(&"head_socket") == head \
			and head.get_child_count() == cosmetic_count,
			"lazy far LOD preserves authored rig/socket/cosmetic identity")
	_check(visual._scale_root.position.is_equal_approx(look.visual_offset) \
			and visual._scale_root.rotation_degrees.is_equal_approx(look.visual_rotation_degrees) \
			and visual._scale_root.scale.is_equal_approx(
					PenguinVisual.SPECIES["little_blue"]["scale"] * look.visual_scale),
			"lazy fallback preserves species and look-space transform")
	var fallback := visual._root
	visual.set_render_role(PenguinVisual.RenderRole.RACER)
	_check(visual._root == fallback, "repeated racer role does not rebuild fallback")
	visual.set_render_role(PenguinVisual.RenderRole.HERO)
	_check(visual.is_authored_lod_visible() and not visual._scale_root.visible,
			"return to HERO restores authored backend")
	visual.set_render_role(PenguinVisual.RenderRole.CROWD)
	_check(visual._scale_root.visible and not visual.is_authored_lod_visible(),
			"explicit CROWD role retains procedural presentation")
	visual.free()


func _test_asset_failure_and_legacy() -> void:
	for role: int in [CharacterLook.RenderRole.HERO, CharacterLook.RenderRole.GHOST]:
		var missing := MissingAssetVisual.new()
		add_child(missing)
		missing.setup_look(CharacterLook.from_legacy_config(
				{"species": "adelie", "hat": "hat_beanie"}, role))
		_check(not missing.is_authored_backend_active() and missing._root != null \
				and missing.get_socket(&"head_socket") != null,
				"role %d missing asset keeps complete procedural fallback" % role)
		missing.set_pose(PenguinVisual.Pose.RUN)
		missing.tick(0.2, 1.0)
		_check(not is_zero_approx(missing._root.rotation.length()),
				"role %d failed asset fallback still animates" % role)
		missing.free()
	var incomplete := IncompleteAssetVisual.new()
	add_child(incomplete)
	incomplete.setup_look(CharacterLook.from_legacy_config({}, CharacterLook.RenderRole.HERO))
	_check(not incomplete.is_authored_backend_active() and incomplete._root != null \
			and incomplete.get_node_or_null("AuthoredHeroPenguin") == null,
			"incomplete asset detaches rejected wrapper and builds fallback")
	incomplete.free()
	for role: int in [CharacterLook.RenderRole.RACER, CharacterLook.RenderRole.CROWD]:
		var visual := _new_visual(role, {"species": "emperor"})
		_check(visual._root != null, "role %d retains eager procedural LOD" % role)
		visual.free()
	var legacy := PenguinVisual.new()
	add_child(legacy)
	legacy.setup({"species": "emperor", "hat": "hat_beanie"})
	_check(legacy._root != null and not legacy.is_authored_backend_active(),
			"legacy setup retains procedural behavior")
	legacy.free()


func _test_reused_facade_lifetime() -> void:
	var visual := PenguinVisual.new()
	add_child(visual)
	visual.setup({"species": "emperor"})
	var old_scale_root := visual._scale_root
	visual.setup_look(CharacterLook.from_legacy_config({}, CharacterLook.RenderRole.HERO))
	_check(visual._root == null and visual._scale_root == null \
			and old_scale_root.get_parent() == null,
			"legacy to HERO detaches queued fallback and clears old fields")
	var old_authored := visual.get_node("AuthoredHeroPenguin")
	visual.setup_look(CharacterLook.from_legacy_config(
			{"species": "gentoo"}, CharacterLook.RenderRole.GHOST))
	_check(old_authored.get_parent() == null and visual._root == null \
			and visual.get_child_count() == 1,
			"repeated authored look has one live backend and no queued field latch")
	var replacement := visual.get_node("AuthoredHeroPenguin")
	visual.setup({"species": "adelie"})
	_check(visual._root != null and not visual.is_authored_backend_active() \
			and replacement.get_parent() == null \
			and visual.get_node_or_null("AuthoredHeroPenguin") == null,
			"authored to legacy immediately restores only procedural live branch")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(not is_instance_valid(old_scale_root) and not is_instance_valid(old_authored) \
			and not is_instance_valid(replacement), "re-setup queued branches eventually free")
	visual.tick(0.1, 1.0)
	_check(is_instance_valid(visual._root), "replacement survives queued old branches")
	visual.free()
