extends Node
## Gate 1: static, unrigged shape in the actual frozen runner. No gameplay,
## controller, normal chase-camera, course or lighting replacement.

const MODEL := "res://qa_shape/candidate.glb"
var _bridge: Node
var _binding: Dictionary = {}
var _game: RunnerGame
var _original: PenguinVisual
var _holder: Node3D
var _model: Node3D
var _camera: Camera3D
var _chase_transform := Transform3D.IDENTITY
var _chase_fov := 0.0
var _camera_before: Dictionary = {}
var _camera_after: Dictionary = {}
var _baseline_bounds: Dictionary = {}
var _repairs: Array[Dictionary] = []
var _color_transfers: Array[Dictionary] = []
var _draws := 0
var _installed_draw := 0
var _view := "rear"
var _error := ""
var _initial_signature := ""
var _material_ids: Dictionary = {}
var _texture_ids: Dictionary = {}
var _texture_cache: Dictionary = {}
var _pickup_overlay_saved: Array[Dictionary] = []
var _pickup_overlay_detail := false
var _grounding: Dictionary = {}
var _read_callback: JavaScriptObject
var _status_callback: JavaScriptObject
var _view_callback: JavaScriptObject


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_feature("web") or ProjectSettings.get_setting("qa/hero_shape_enabled", false) != true:
		set_process(false)
		return
	_bridge = get_node_or_null("/root/ChromeReferenceQA")
	if _bridge == null or _bridge.get("_enabled") != true or _bridge.call("_offline_fixture_ready") != true:
		set_process(false)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://qa_shape/candidate_binding.json"))
	if not parsed is Dictionary or [parsed.get("gate"), parsed.get("material_contract")] not in [["rear-shape-v1", "plain-literal-COLOR_0"], ["rear-surface-v1", "rear-surface-pbr-v1"], ["rear-surface-v2", "rear-surface-pbr-v1"]] \
			or parsed.get("unrigged") != true or parsed.get("animation_ready") != false \
			or parsed.get("production_ready") != false \
			or String(parsed.get("glb_sha256", "")).length() != 64:
		_error = "Invalid unrigged shape package binding"
	else:
		_binding = parsed
	_read_callback = JavaScriptBridge.create_callback(_on_read)
	_status_callback = JavaScriptBridge.create_callback(_on_status)
	_view_callback = JavaScriptBridge.create_callback(_on_view)
	JavaScriptBridge.eval("""(() => {
	  let readCallback, statusCallback, viewCallback;
	  window.__wwShapeCandidate = {
	    _reply: null,
	    bind_callbacks(read, status, view) { readCallback=read; statusCallback=status; viewCallback=view; },
	    read() { readCallback(); return this._reply; },
	    status() { statusCallback(); return this._reply; },
	    view(name) { viewCallback(name); return this.status(); }
	  };
	})();""", true)
	JavaScriptBridge.get_interface("__wwShapeCandidate").bind_callbacks(_read_callback, _status_callback, _view_callback)
	RenderingServer.frame_post_draw.connect(_on_draw)


func _on_draw() -> void:
	_draws += 1


func _exit_tree() -> void:
	_restore_pickup_overlay()
	if is_instance_valid(_original):
		_original.visible = true


func _process(_delta: float) -> void:
	if _binding.is_empty() or not _error.is_empty():
		return
	var current := get_tree().current_scene as RunnerGame
	if is_instance_valid(_model) and current == _game:
		return
	if current == null or current.player == null or current.camera == null or not get_tree().paused:
		return
	var stage: Dictionary = _bridge.call("snapshot")
	if stage.get("status") != "ready" or stage.get("route") != "runner_hud":
		return
	_install(current)


func _camera_state() -> Dictionary:
	return {"transform": var_to_str(_camera.global_transform), "fov": _camera.fov}


func _visible_bounds(root: Node3D) -> Dictionary:
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	for raw: Node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := raw as MeshInstance3D
		if instance.mesh == null or not instance.is_visible_in_tree():
			continue
		var bounds := instance.mesh.get_aabb()
		for index: int in 8:
			var point := bounds.position + Vector3(bounds.size.x if index & 1 else 0.0,
				bounds.size.y if index & 2 else 0.0, bounds.size.z if index & 4 else 0.0)
			point = instance.global_transform * point
			minimum = minimum.min(point)
			maximum = maximum.max(point)
	return {"minimum": var_to_str(minimum), "maximum": var_to_str(maximum),
		"height_m": maximum.y - minimum.y, "scope": "World-space visible mesh union AABB at frozen original pose"}


func _install(game: RunnerGame) -> void:
	_restore_pickup_overlay()
	_pickup_overlay_saved.clear()
	_game = game
	_original = game.player._visual
	_camera = game.camera
	if _original == null or not _original.is_visible_in_tree():
		_error = "Original game visual unavailable before shape replacement"
		return
	if not _remember_pickup_overlay():
		return
	_camera_before = _camera_state()
	_chase_transform = _camera.global_transform
	_chase_fov = _camera.fov
	_baseline_bounds = _visible_bounds(_original)
	var packed := load(MODEL) as PackedScene
	_model = packed.instantiate() as Node3D if packed != null else null
	if _model == null or not _model.transform.is_equal_approx(Transform3D.IDENTITY) \
			or not _model.find_children("*", "Skeleton3D", true, false).is_empty() \
			or not _model.find_children("*", "AnimationPlayer", true, false).is_empty():
		_error = "Shape package must be identity-root unrigged geometry with no animation"
		if _model != null:
			_model.free()
		return
	_holder = Node3D.new()
	_holder.name = "UnriggedShapeReview"
	game.player.add_child(_holder)
	_holder.transform = _original.transform
	_holder.scale *= float(_binding.get("gameplay_scale", 0.0))
	_model.name = "Model"
	_holder.add_child(_model)
	_grounding = seat_model_on_visual_floor(game.track, game.player, _holder, _model, _camera)
	if not String(_grounding.error).is_empty():
		_error = _grounding.error
		_holder.queue_free()
		return
	_repairs.clear()
	_color_transfers.clear()
	_material_ids.clear()
	_texture_ids.clear()
	_texture_cache.clear()
	for raw: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var instance := raw as MeshInstance3D
		if instance.mesh == null:
			continue
		var transfer := material_contract_mesh(instance.mesh as ArrayMesh,
			RenderingServer.get_current_rendering_method(), String(_binding.material_contract))
		if not String(transfer.error).is_empty():
			_error = transfer.error
			continue
		instance.mesh = transfer.mesh
		for receipt: Dictionary in transfer.surfaces:
			receipt["mesh"] = String(instance.name)
			_color_transfers.append(receipt)
		for index: int in instance.mesh.get_surface_count():
			var material := instance.mesh.surface_get_material(index) as BaseMaterial3D
			var colors: Variant = instance.mesh.surface_get_arrays(index)[Mesh.ARRAY_COLOR]
			if material == null or (not _is_surface_review() and (not colors is PackedColorArray or colors.is_empty())):
				_error = "Shape surface lacks imported literal-color PBR"
				continue
			if not _is_surface_review() and not material.vertex_color_use_as_albedo:
				material.vertex_color_use_as_albedo = true
				_repairs.append({"mesh": String(instance.name), "surface": index,
					"explicit_import_flag_repair": "vertex_color_use_as_albedo=true"})
			_material_ids[str(instance.get_instance_id()) + ":" + str(index)] = material.get_instance_id()
	_original.visible = false
	_view = "rear"
	_installed_draw = _draws
	_camera_after = _camera_state()
	if _camera_after != _camera_before:
		_error = "Shape replacement changed the actual runner camera"
	var active := _active_resources()
	if not active.errors.is_empty():
		_error = "; ".join(active.errors)
	_initial_signature = active.signature
	if not _error.is_empty():
		_original.visible = true
		_holder.queue_free()


static func _world_transform(node: Node3D) -> Transform3D:
	# Equivalent to global_transform; also usable by off-tree resource tests.
	var result := node.transform
	var ancestor := node.get_parent()
	while ancestor != null:
		if ancestor is Node3D:
			result = (ancestor as Node3D).transform * result
		ancestor = ancestor.get_parent()
	return result


static func visual_floor_at(track: Node3D, point: Vector3) -> Dictionary:
	var result := {"error": "", "paths": [], "height": 0.0, "kind": ""}
	# Only the named playable planes are eligible. Prefer the visible ice skin
	# over the collision-height deck it covers; never choose a nearby prop.
	for kind: String in ["GlacialIceSkin", "Deck"]:
		var heights: Array[float] = []
		for raw: Node in track.find_children(kind, "MeshInstance3D", true, false):
			var instance := raw as MeshInstance3D
			if not instance.visible or (instance.is_inside_tree() and not instance.is_visible_in_tree()) \
					or instance.mesh == null:
				continue
			var world := _world_transform(instance)
			var box := instance.mesh.get_aabb()
			var low := Vector3(INF, INF, INF)
			var high := Vector3(-INF, -INF, -INF)
			for corner: int in 8:
				var local := box.position + Vector3(box.size.x if corner & 1 else 0.0,
					box.size.y if corner & 2 else 0.0, box.size.z if corner & 4 else 0.0)
				var transformed := world * local
				low = low.min(transformed)
				high = high.max(transformed)
			if point.x < low.x or point.x > high.x or point.z < low.z or point.z > high.z:
				continue
			if not instance.mesh is PlaneMesh or high.y - low.y > 0.00001 \
					or (kind == "Deck" and not is_zero_approx(low.y)):
				result.error = "Unsupported playable visual-floor geometry at the player"
				return result
			heights.append(low.y)
			result.paths.append(String(track.get_path_to(instance)))
		if not heights.is_empty():
			for height: float in heights:
				if not is_equal_approx(height, heights[0]):
					result.error = "Ambiguous visual-floor heights at the player"
					return result
			result.height = heights[0]
			result.kind = kind
			return result
	result.error = "No supported visible gameplay floor below the shape candidate"
	return result


static func _lowest_vertex_y(model: Node3D) -> float:
	var lowest := INF
	for raw: Node in model.find_children("*", "MeshInstance3D", true, false):
		var instance := raw as MeshInstance3D
		if instance.mesh == null:
			continue
		var world := _world_transform(instance)
		for surface: int in instance.mesh.get_surface_count():
			var vertices: PackedVector3Array = instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				lowest = minf(lowest, (world * vertex).y)
	return lowest


static func seat_model_on_visual_floor(track: Node3D, player: Node3D, holder: Node3D,
		model: Node3D, camera: Camera3D) -> Dictionary:
	var result := visual_floor_at(track, _world_transform(player).origin)
	if not String(result.error).is_empty():
		return result
	var player_before := _world_transform(player)
	var camera_before := _world_transform(camera)
	var minimum := _lowest_vertex_y(model)
	if not is_finite(minimum):
		result.error = "Cannot locate shape candidate soles"
		return result
	var offset: float = float(result.height) - minimum
	var parent := holder.get_parent() as Node3D
	if parent == null:
		result.error = "Shape holder requires a gameplay parent"
		return result
	holder.position += _world_transform(parent).basis.inverse() * Vector3.UP * offset
	result.merge({"sole_min_before": minimum, "sole_min_after": _lowest_vertex_y(model),
		"world_y_offset": offset, "player_transform_unchanged": _world_transform(player) == player_before,
		"camera_transform_unchanged": _world_transform(camera) == camera_before,
		"policy": "Seat candidate geometry on the actual visible gameplay plane; collision and camera unchanged"})
	if not is_equal_approx(result.sole_min_after, result.height) \
			or not result.player_transform_unchanged or not result.camera_transform_unchanged:
		result.error = "Shape seating changed gameplay or failed to reach the visible floor"
	return result


func _remember_pickup_overlay() -> bool:
	# These are the small HUD reward sprites flying into the fish counter,
	# not the course's Fish MultiMeshes or the permanent HUD currency icon.
	if _game.hud == null or _game.hud._float_fish_icons.is_empty() \
			or _game.hud._float_fish_icons.size() != _game.hud._float_labels.size():
		_error = "Shape review cannot identify the HUD pickup overlay pool"
		return false
	for index: int in _game.hud._float_fish_icons.size():
		var icon: TextureRect = _game.hud._float_fish_icons[index]
		if not is_instance_valid(icon) or icon.get_parent() != _game.hud._float_labels[index] \
				or not _game.hud.is_ancestor_of(icon):
			_error = "Shape review HUD pickup overlay ownership changed"
			return false
		_pickup_overlay_saved.append({"node": icon, "path": String(icon.get_path()),
			"visible": icon.visible, "visible_in_tree": icon.is_visible_in_tree()})
	return true


func _set_pickup_overlay_detail(detail: bool) -> bool:
	# Validate every saved node before changing any visibility. Zero active
	# floaters is valid; a missing/replaced pool during a frozen review is not.
	for saved: Dictionary in _pickup_overlay_saved:
		if not is_instance_valid(saved.node) or not _game.hud.is_ancestor_of(saved.node):
			_error = "Shape review lost a saved HUD pickup overlay node"
			return false
	for saved: Dictionary in _pickup_overlay_saved:
		var icon := saved.node as TextureRect
		icon.visible = false if detail else bool(saved.visible)
	_pickup_overlay_detail = detail
	return true


func _restore_pickup_overlay() -> void:
	for saved: Dictionary in _pickup_overlay_saved:
		if is_instance_valid(saved.node):
			var icon := saved.node as TextureRect
			icon.visible = bool(saved.visible)
	_pickup_overlay_detail = false


func _pickup_overlay_receipt() -> Dictionary:
	var result := {"policy": "Hide only transient HUD fish pickup icons in rear_detail; restore every original visibility in rear",
		"pool_source": "RunnerHUD._float_fish_icons", "detail_active": _pickup_overlay_detail,
		"matched_nodes": _pickup_overlay_saved.size(), "original_visible_nodes": 0,
		"original_visible_in_tree_nodes": 0, "hidden_nodes": 0, "visibility_mismatches": 0,
		"missing_nodes": 0, "world_collectibles_modified": false, "hud_counters_modified": false,
		"simulation_modified": false, "nodes": []}
	for saved: Dictionary in _pickup_overlay_saved:
		var row := {"path": saved.path, "original_visible": saved.visible,
			"original_visible_in_tree": saved.visible_in_tree, "current_visible": false,
			"current_visible_in_tree": false}
		if saved.visible:
			result.original_visible_nodes += 1
		if saved.visible_in_tree:
			result.original_visible_in_tree_nodes += 1
		if not is_instance_valid(saved.node):
			result.missing_nodes += 1
		else:
			var icon := saved.node as TextureRect
			row.current_visible = icon.visible
			row.current_visible_in_tree = icon.is_visible_in_tree()
			if icon.visible != (false if _pickup_overlay_detail else bool(saved.visible)):
				result.visibility_mismatches += 1
			if saved.visible and not icon.visible:
				result.hidden_nodes += 1
		result.nodes.append(row)
	return result


static func _hash(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value))
	return context.finish().hex_encode()


static func compatibility_color_mesh(imported: ArrayMesh, renderer: String) -> Dictionary:
	var result := {"mesh": imported, "surfaces": [], "error": ""}
	if renderer != "gl_compatibility":
		return result
	if imported == null or imported.get_blend_shape_count() != 0:
		result.error = "Shape color transfer requires an unrigged ArrayMesh"
		return result
	# glTF COLOR_0 is linear. Godot 4.7 Compatibility decodes final ALBEDO
	# from sRGB; FLAG_SRGB_VERTEX_COLOR only acts when !OUTPUT_IS_SRGB.
	# Encode a private mesh copy once, preserving source paint and imported PBR.
	# https://github.com/godotengine/godot/blob/4.7-stable/drivers/gles3/shaders/scene.glsl#L2203
	# https://github.com/godotengine/godot/blob/4.7-stable/scene/resources/material.cpp#L1113
	var converted := ArrayMesh.new()
	converted.resource_name = imported.resource_name
	for surface: int in imported.get_surface_count():
		var arrays := imported.surface_get_arrays(surface).duplicate(true)
		var original: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		if original.is_empty():
			result.error = "Shape surface lacks linear vertex colors"
			return result
		var colors := original.duplicate()
		for index: int in colors.size():
			colors[index] = colors[index].linear_to_srgb()
		arrays[Mesh.ARRAY_COLOR] = colors
		converted.add_surface_from_arrays(imported.surface_get_primitive_type(surface), arrays)
		converted.surface_set_material(surface, imported.surface_get_material(surface))
		converted.surface_set_name(surface, imported.surface_get_name(surface))
		var active: PackedColorArray = converted.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
		var maximum_error := 0.0
		for index: int in active.size():
			var decoded := active[index].srgb_to_linear()
			var expected := original[index]
			maximum_error = maxf(maximum_error, maxf(absf(decoded.r - expected.r),
				maxf(absf(decoded.g - expected.g), absf(decoded.b - expected.b))))
		# ArrayMesh stores color in RGBA8; allow at most one encoded byte step.
		if maximum_error > 0.009:
			result.error = "Shape vertex color transfer exceeds RGBA8 roundtrip tolerance"
			return result
		result.surfaces.append({"surface": surface, "renderer": renderer,
			"transfer": "linear_to_srgb on private mesh; Compatibility decodes to original linear paint",
			"imported_color_sha256": _hash(original), "active_color_sha256": _hash(active),
			"linear_roundtrip_max_error": maximum_error, "linear_roundtrip_tolerance": 0.009,
			"source_mesh_unchanged": _hash(imported.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]) == _hash(original),
			"material_retained": converted.surface_get_material(surface) == imported.surface_get_material(surface)})
	result.mesh = converted
	return result


func _is_surface_review() -> bool:
	return _binding.get("material_contract") == "rear-surface-pbr-v1"


static func material_contract_mesh(imported: ArrayMesh, renderer: String, contract: String) -> Dictionary:
	if contract == "rear-surface-pbr-v1":
		return {"mesh": imported, "surfaces": [], "error": "" if imported != null else "Surface mesh missing"}
	return compatibility_color_mesh(imported, renderer)


func _texture_changed(texture_id: int) -> void:
	# Imported textures are immutable during this frozen review. Never silently
	# recalculate a changed texture and bless it as the original package.
	_texture_cache.erase(texture_id)
	_error = "Imported surface texture changed during review"


func _surface_map_receipts(material: BaseMaterial3D) -> Dictionary:
	var result := {"maps": {}, "errors": []}
	var slots := {"base_color": BaseMaterial3D.TEXTURE_ALBEDO,
		"normal": BaseMaterial3D.TEXTURE_NORMAL, "metallic_roughness": BaseMaterial3D.TEXTURE_ROUGHNESS}
	for name: String in slots:
		var texture := material.get_texture(slots[name])
		var expected: Dictionary = _binding.get("surface_maps", {}).get(name, {})
		if texture == null or expected.is_empty():
			result.errors.append("Imported surface map missing: " + name)
			continue
		var texture_id := texture.get_instance_id()
		if _texture_ids.has(name) and _texture_ids[name] != texture_id:
			result.errors.append("Imported surface texture replaced: " + name)
			continue
		_texture_ids[name] = texture_id
		if not _texture_cache.has(texture_id):
			var pixels := texture.get_image()
			if pixels == null or pixels.is_empty():
				result.errors.append("Imported surface map has no readable pixels: " + name)
				continue
			# get_image returns image data; duplicate before format normalization.
			var has_mipmaps := pixels.has_mipmaps()
			var mipmap_count := pixels.get_mipmap_count()
			pixels = pixels.duplicate()
			if pixels.is_compressed() and pixels.decompress() != OK:
				result.errors.append("Imported surface map cannot be decoded: " + name)
				continue
			pixels.clear_mipmaps()
			pixels.convert(Image.FORMAT_RGBA8)
			var hash_context := HashingContext.new()
			hash_context.start(HashingContext.HASH_SHA256)
			hash_context.update(pixels.get_data())
			_texture_cache[texture_id] = {"width": pixels.get_width(), "height": pixels.get_height(),
				"rgba8_sha256": hash_context.finish().hex_encode(), "texture_class": texture.get_class(),
				"has_mipmaps": has_mipmaps, "mipmap_count": mipmap_count,
				"resource_path": texture.resource_path, "pixel_policy": "Exact imported base-level RGBA8; no material/map substitution"}
			texture.changed.connect(_texture_changed.bind(texture_id))
		var receipt: Dictionary = _texture_cache[texture_id].duplicate()
		for field: String in ["width", "height", "rgba8_sha256"]:
			if receipt[field] != expected.get(field):
				result.errors.append("Imported surface map differs from embedded source: " + name + "/" + field)
		if not receipt.has_mipmaps:
			result.errors.append("Imported surface map lacks mipmaps: " + name)
		receipt["source_png_sha256"] = expected.get("sha256")
		receipt["color_space"] = expected.get("color_space")
		result.maps[name] = receipt
	if material.get_texture(BaseMaterial3D.TEXTURE_METALLIC) != material.get_texture(BaseMaterial3D.TEXTURE_ROUGHNESS):
		result.errors.append("Imported roughness/metallic do not share their bound G/B map")
	return result


func _surface_material_error(material: BaseMaterial3D) -> String:
	var expected: Dictionary = _binding.get("materials", [{}])[0]
	if not material is StandardMaterial3D or material.vertex_color_use_as_albedo \
			or material.albedo_color != Color.WHITE or not is_equal_approx(material.roughness, 1.0) \
			or not is_equal_approx(material.metallic, 1.0) or not material.normal_enabled \
			or not is_equal_approx(material.normal_scale, float(expected.get("normal_scale", -1.0))) \
			or material.roughness_texture_channel != BaseMaterial3D.TEXTURE_CHANNEL_GREEN \
			or material.metallic_texture_channel != BaseMaterial3D.TEXTURE_CHANNEL_BLUE \
			or material.texture_filter not in [BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS, BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC] \
			or material.uv1_scale != Vector3.ONE or material.uv1_offset != Vector3.ZERO \
			or material.next_pass != null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
			or material.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL \
			or material.cull_mode != (BaseMaterial3D.CULL_DISABLED if expected.get("double_sided", false) else BaseMaterial3D.CULL_BACK):
		return "Surface material differs from imported standard PBR contract"
	for slot: int in BaseMaterial3D.TEXTURE_MAX:
		if material.get_texture(slot) != null and slot not in [BaseMaterial3D.TEXTURE_ALBEDO,
				BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_METALLIC]:
			return "Surface material has an undeclared texture slot"
	return ""


func _active_resources() -> Dictionary:
	var result := {"model": "", "surfaces": [], "errors": [], "signature": "", "original_hidden": false}
	if not is_instance_valid(_model) or not is_instance_valid(_original):
		result.errors.append("Shape or original visual missing")
		return result
	result.model = _model.scene_file_path
	result.original_hidden = not _original.visible and not _original.is_visible_in_tree()
	if result.model != MODEL or not result.original_hidden or not _model.is_visible_in_tree():
		result.errors.append("Bound shape is not the sole visible player model")
	for raw: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var instance := raw as MeshInstance3D
		if instance.mesh == null:
			continue
		if instance.skin != null or instance.material_override != null or instance.material_overlay != null:
			result.errors.append("Shape surface has skinning or material substitution")
		for index: int in instance.mesh.get_surface_count():
			var arrays := instance.mesh.surface_get_arrays(index)
			var material := instance.get_active_material(index) as BaseMaterial3D
			var row := {"mesh": String(_model.get_path_to(instance)), "surface": index,
				"geometry_sha256": _hash(arrays), "material": {}}
			if material == null or instance.get_surface_override_material(index) != null \
					or material.get_instance_id() != _material_ids.get(str(instance.get_instance_id()) + ":" + str(index)):
				result.errors.append("Shape material differs from the imported package")
			else:
				row.material = {"class": material.get_class(), "name": material.resource_name,
					"albedo": var_to_str(material.albedo_color), "roughness": material.roughness,
					"metallic": material.metallic, "vertex_color": material.vertex_color_use_as_albedo,
					"vertex_color_is_srgb": material.vertex_color_is_srgb, "cull_mode": material.cull_mode,
					"shading_mode": material.shading_mode, "normal_enabled": material.normal_enabled,
					"normal_scale": material.normal_scale, "roughness_channel": material.roughness_texture_channel,
					"metallic_channel": material.metallic_texture_channel, "texture_filter": material.texture_filter,
					"uv1_scale": var_to_str(material.uv1_scale), "uv1_offset": var_to_str(material.uv1_offset)}
				if _is_surface_review():
					var material_error := _surface_material_error(material)
					if not material_error.is_empty():
						result.errors.append(material_error)
					var maps := _surface_map_receipts(material)
					row.material["maps"] = maps.maps
					result.errors.append_array(maps.errors)
				else:
					if not material.vertex_color_use_as_albedo or material.albedo_color != Color.WHITE \
							or material.roughness < 0.8 or material.metallic != 0.0 or material.next_pass != null \
							or material.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL:
						result.errors.append("Shape material no longer matches plain matte PBR")
					for slot: int in BaseMaterial3D.TEXTURE_MAX:
						if material.get_texture(slot) != null:
							result.errors.append("Shape material unexpectedly uses texture maps")
			result.surfaces.append(row)
	if result.surfaces.size() != int(_binding.get("surface_count", -1)):
		result.errors.append("Shape surface count differs from bound source")
	result.signature = _hash([result.model, result.surfaces, _holder.transform])
	return result


func status() -> Dictionary:
	var state := {"status": "pending", "error": _error, "view": _view,
		"settled_frames": maxi(0, _draws - _installed_draw), "tree_paused": get_tree().paused}
	if not _error.is_empty():
		state.status = "error"
	elif is_instance_valid(_model) and get_tree().paused and state.settled_frames >= 2:
		state.status = "ready"
	return state


func snapshot() -> Dictionary:
	var result := status()
	result.merge({"schema_version": 1, "gate": _binding.get("gate"), "bound_source": _binding,
		"label": "Surface review • animation/front review pending" if _is_surface_review() else "Shape review • animation/material detail pending", "unrigged": true,
		"animation_ready": false, "production_ready": false, "performance_measured": false,
		"camera_before_swap": _camera_before, "camera_after_swap": _camera_after,
		"original_visible_bounds": _baseline_bounds, "import_flag_repairs": _repairs,
		"vertex_color_transfers": _color_transfers,
		"pickup_overlay": _pickup_overlay_receipt(),
		"grounding": _grounding,
		"renderer": RenderingServer.get_current_rendering_method(), "active_renderer": {},
		"logical_viewport": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]})
	if result.status != "ready":
		return result
	result.active_renderer = _active_resources()
	result.camera = _camera_state()
	result.camera.merge({"projection": _camera.projection, "keep_aspect": _camera.keep_aspect,
		"near": _camera.near, "far": _camera.far, "h_offset": _camera.h_offset, "v_offset": _camera.v_offset,
		"frustum_offset": var_to_str(_camera.frustum_offset)})
	result.transforms = {"player_global": var_to_str(_game.player.global_transform),
		"holder_global": var_to_str(_holder.global_transform), "model_global": var_to_str(_model.global_transform)}
	result.gameplay_scale = _binding.get("gameplay_scale")
	if result.pickup_overlay.missing_nodes > 0 or result.pickup_overlay.visibility_mismatches > 0:
		result.active_renderer.errors.append("HUD pickup overlay visibility differs from declared view policy")
	if result.active_renderer.signature != _initial_signature:
		result.active_renderer.errors.append("Shape geometry or material changed after installation")
	if not result.active_renderer.errors.is_empty():
		result.status = "error"
		result.error = "; ".join(result.active_renderer.errors)
	return result


func _on_status(_args: Array) -> void:
	JavaScriptBridge.eval("window.__wwShapeCandidate._reply = " + JSON.stringify(status()), true)


func _on_read(_args: Array) -> void:
	JavaScriptBridge.eval("window.__wwShapeCandidate._reply = " + JSON.stringify(snapshot()), true)


func _on_view(args: Array) -> void:
	if args.size() != 1 or not args[0] is String or args[0] not in ["rear", "rear_detail"]:
		_error = "Shape review permits only rear gameplay and rear detail"
		return
	if status().status != "ready":
		return
	if not _set_pickup_overlay_detail(args[0] == "rear_detail"):
		return
	if args[0] == "rear":
		_camera.global_transform = _chase_transform
		_camera.fov = _chase_fov
	else:
		var height := float(_binding.gameplay_height_m)
		# Seating repairs must not silently reframe the diagnostic camera.
		var target := _original.global_position + Vector3.UP * height * 0.65
		_camera.fov = 30.0
		_camera.look_at_from_position(target + Vector3.BACK * height * 3.8 + Vector3.UP * height * 0.15, target)
	_view = String(args[0])
	var caption := "Rear detail • pickup overlay hidden; animation/material detail pending" \
		if _pickup_overlay_detail else "Shape review • animation/material detail pending"
	if _is_surface_review():
		caption = "Rear surface detail • pickup overlay hidden; animation/front review pending" if _pickup_overlay_detail else "Surface review • animation/front review pending"
	JavaScriptBridge.eval("(() => { const caption = document.querySelector('#ww-shape-review small'); if (caption) caption.textContent = " \
		+ JSON.stringify(caption) + "; })();", true)
	_installed_draw = _draws
