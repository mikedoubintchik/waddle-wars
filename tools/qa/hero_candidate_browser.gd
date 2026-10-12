extends Node
## Isolated-export observer. Camera-only front/side views of the actual runner.
## Bound source hashes describe the host package; active signatures describe
## imported renderer resources, never a pretend GLB file hash from the PCK.

const MODEL := "res://qa_hero/candidate.glb"
const SHADER := "res://scripts/shaders/hero_penguin_v1.gdshader"
const TEXTURES := {
	"feather_albedo": "res://assets/art/characters/textures/hero_penguin_v1_albedo.png",
	"feather_normal": "res://assets/art/characters/textures/hero_penguin_v1_normal.png",
	"feather_orm": "res://assets/art/characters/textures/hero_penguin_v1_orm.png",
}
const PALETTE := ["dorsal_color", "ventral_color", "mantle_color", "patch_color", "identity_color"]
const SCALARS := {"surface_roughness": 0.75, "rim_strength": 0.055}
var _bridge: Node
var _binding: Dictionary = {}
var _previous_backend_enabled := false
var _owns_backend_flag := false
var _error := ""
var _view := "chase"
var _ticket := -1
var _draws := 0
var _view_draw := -2
var _chase_transform := Transform3D.IDENTITY
var _chase_fov := 0.0
var _camera: Camera3D
var _read_callback: JavaScriptObject
var _view_callback: JavaScriptObject

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_feature("web") or ProjectSettings.get_setting("qa/hero_candidate_enabled", false) != true:
		return
	_bridge = get_node_or_null("/root/ChromeReferenceQA")
	# That bridge has already checked localhost AND the exact project token.
	if _bridge == null or _bridge.get("_enabled") != true:
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://qa_hero/candidate_binding.json"))
	if not parsed is Dictionary or parsed.get("material_mode") != "runtime":
		_error = "Candidate binding requires explicit runtime material mode"
	else:
		_binding = parsed
		var resources: Variant = _binding.get("runtime_resources")
		if not resources is Dictionary or String(resources.get(SHADER.trim_prefix("res://"), "")).length() != 64:
			_error = "Runtime binding must include the source shader SHA256"
		elif _bridge.call("_offline_fixture_ready") != true:
			_error = "Candidate backend requires the isolated offline QA profile"
		else:
			_previous_backend_enabled = PenguinVisual.use_authored_backend_for_qa
			PenguinVisual.use_authored_backend_for_qa = true
			_owns_backend_flag = true
	_read_callback = JavaScriptBridge.create_callback(_on_read)
	_view_callback = JavaScriptBridge.create_callback(_on_view)
	JavaScriptBridge.eval("""(() => {
	  let readCallback, viewCallback;
	  window.__wwHeroCandidate = {
	    _reply: null,
	    bind_callbacks(read, view) { readCallback = read; viewCallback = view; },
	    read() { readCallback(); return this._reply; },
	    view(name) { viewCallback(name); return this.read(); }
	  };
	})();""", true)
	JavaScriptBridge.get_interface("__wwHeroCandidate").bind_callbacks(_read_callback, _view_callback)
	RenderingServer.frame_post_draw.connect(_on_draw)

func _exit_tree() -> void:
	if _owns_backend_flag:
		PenguinVisual.use_authored_backend_for_qa = _previous_backend_enabled
		_owns_backend_flag = false

func _on_draw() -> void:
	_draws += 1

func _on_read(_args: Array) -> void:
	JavaScriptBridge.eval("window.__wwHeroCandidate._reply = " + JSON.stringify(snapshot()), true)

func _stage() -> Dictionary:
	return _bridge.call("snapshot") if is_instance_valid(_bridge) else {}

func _sync_camera(game: RunnerGame, ticket: int) -> void:
	if _camera == game.camera and _ticket == ticket:
		return
	_camera = game.camera
	_ticket = ticket
	_view = "chase"
	_chase_transform = _camera.global_transform
	_chase_fov = _camera.fov
	_view_draw = _draws - 2

func _on_view(args: Array) -> void:
	if args.size() != 1 or not args[0] is String or args[0] not in ["front", "side", "chase"]:
		_error = "Candidate view must be front, side or chase"
		return
	if _binding.is_empty() or not _owns_backend_flag:
		return
	_error = ""
	var before := snapshot()
	if before.status != "ready":
		_error = "Candidate camera requires a ready, frozen runner with verified resources"
		return
	var game := get_tree().current_scene as RunnerGame
	var target_view := String(args[0])
	if target_view == "chase":
		_camera.global_transform = _chase_transform
		_camera.fov = _chase_fov
	else:
		var height := maxf(RunnerCameraComposition.authored_height(game.player._visual), 0.5)
		# Leave the existing game HUD above and QA controls below the silhouette.
		# Retain world lighting/effects and the exact same player/materials.
		var target := game.player._visual.global_position + Vector3.UP * height * 0.65
		var axis := Vector3.FORWARD if target_view == "front" else Vector3.RIGHT
		_camera.fov = 30.0
		_camera.look_at_from_position(target + axis * height * 3.8 + Vector3.UP * height * 0.15, target)
	_view = target_view
	_view_draw = _draws
	var after := _active_resources(game)
	if after.signature != before.active_renderer.signature:
		_error = "Active geometry/material signature changed while switching only camera"

func _hash(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value))
	return context.finish().hex_encode()

func _active_resources(game: RunnerGame) -> Dictionary:
	var result := {"backend": "missing", "model": "", "surfaces": [], "errors": [], "signature": ""}
	var visual := game.player._visual
	if visual == null or not visual.is_authored_backend_active():
		result.errors.append("Actual player selected procedural fallback or has no visual")
		return result
	var rig := visual.get_node_or_null("AuthoredHeroPenguin") as Node3D
	if rig == null:
		result.errors.append("Authored player backend missing")
		return result
	result.backend = "AuthoredHeroPenguin"
	var model := rig.get_node_or_null("Model") as Node3D
	result.model = model.scene_file_path if model != null else ""
	if result.model != MODEL:
		result.errors.append("Active Model scene differs from bound candidate")
	if not rig.is_visible_in_tree():
		result.errors.append("Authored player backend is not visible")
	for raw: Node in rig.find_children("*", "MeshInstance3D", true, false):
		var instance := raw as MeshInstance3D
		if instance.mesh == null: continue
		if instance.material_override != null or instance.material_overlay != null:
			result.errors.append("Unexpected whole-mesh material override or overlay")
		var skin_binds: Array = []
		if instance.skin != null:
			for index: int in instance.skin.get_bind_count():
				skin_binds.append([instance.skin.get_bind_name(index), instance.skin.get_bind_bone(index), instance.skin.get_bind_pose(index)])
		var blends: Array = []
		if instance.mesh is ArrayMesh:
			for index: int in instance.mesh.get_blend_shape_count():
				blends.append([instance.mesh.get_blend_shape_name(index), instance.get_blend_shape_value(index)])
		for index: int in instance.mesh.get_surface_count():
			var material := instance.get_active_material(index) as ShaderMaterial
			var arrays := instance.mesh.surface_get_arrays(index)
			var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			var row := {"mesh": String(rig.get_path_to(instance)), "surface": index,
				"geometry_sha256": _hash(arrays), "vertices": vertices.size() if vertices is PackedVector3Array else 0,
				"indices": indices.size() if indices is PackedInt32Array else 0,
				"primitive": instance.mesh.surface_get_primitive_type(index),
				"skin_sha256": _hash(skin_binds), "blend_shapes": blends,
				"shader": "", "shader_code_sha256": "", "textures": {}, "uniforms": {}, "palette": {}}
			if material == null or material.shader == null:
				result.errors.append("Active surface is not the runtime ShaderMaterial")
			else:
				row.shader = material.shader.resource_path
				row.shader_code_sha256 = material.shader.code.sha256_text()
				if row.shader != SHADER or material.next_pass != null:
					result.errors.append("Unexpected active shader or additional material pass")
				if row.shader_code_sha256 != _binding.get("runtime_resources", {}).get(SHADER.trim_prefix("res://"), ""):
					result.errors.append("Active shader code differs from the bound runtime source")
				for uniform: String in TEXTURES:
					var texture := material.get_shader_parameter(uniform) as Texture2D
					row.textures[uniform] = {"path": texture.resource_path if texture != null else "",
						"size": [texture.get_width(), texture.get_height()] if texture != null else []}
					if texture == null or texture.resource_path != TEXTURES[uniform]:
						result.errors.append("Unexpected runtime texture: " + uniform)
				for uniform: String in SCALARS:
					row.uniforms[uniform] = material.get_shader_parameter(uniform)
					if not row.uniforms[uniform] is float or row.uniforms[uniform] != SCALARS[uniform]:
						result.errors.append("Runtime material scalar differs from canonical template: " + uniform)
				for uniform: String in PALETTE:
					row.palette[uniform] = var_to_str(instance.get_instance_shader_parameter(uniform))
			result.surfaces.append(row)
	if result.surfaces.is_empty(): result.errors.append("Candidate has no rendered surfaces")
	result.signature = _hash([result.backend, result.model, result.surfaces])
	return result

func snapshot() -> Dictionary:
	var stage := _stage()
	var result := {"schema_version": 1, "status": "pending", "error": _error,
		"route": stage.get("route", ""), "view": _view, "bound_source": _binding.duplicate(true),
		"source_hash_scope": "Host-verified original package; active renderer is separately identified below",
		"identity_scope": "Imported mesh arrays, skin binds, blend weights and effective material descriptors; no instance IDs",
		"camera_only_diagnostic": true, "performance_measured": false,
		"qa_backend_enabled": _owns_backend_flag and PenguinVisual.use_authored_backend_for_qa,
		"renderer": RenderingServer.get_current_rendering_method(),
		"tree_paused": get_tree().paused, "active_renderer": {}, "camera": {},
		"logical_viewport": [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		"settled_frames": maxi(0, _draws - _view_draw)}
	if not _error.is_empty():
		result.status = "error"
		return result
	var game := get_tree().current_scene as RunnerGame
	if stage.get("status") != "ready" or game == null or game.player == null or game.camera == null or not get_tree().paused:
		result.error = "Waiting for __wwQA ready and frozen actual runner"
		return result
	_sync_camera(game, int(stage.get("ticket", -1)))
	result.view = _view
	result.settled_frames = maxi(0, _draws - _view_draw)
	result.active_renderer = _active_resources(game)
	result.camera = {"transform": var_to_str(game.camera.global_transform), "fov": game.camera.fov,
		"player_transform": var_to_str(game.player.global_transform), "quality": stage.get("quality"),
		"player_state": int(game.player.state), "elapsed": game.elapsed}
	if not result.active_renderer.errors.is_empty():
		result.status = "error"
		result.error = "; ".join(result.active_renderer.errors)
	elif result.settled_frames >= 2:
		result.status = "ready"
	return result
