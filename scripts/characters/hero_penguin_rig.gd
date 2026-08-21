class_name HeroPenguinRig
extends Node3D
## Runtime controller for hero_penguin_v1.glb.
##
## Gameplay never delegates transforms to this node. Every source clip keys
## armature bones only and keeps root identity, while PenguinVisual remains
## movement authority. Semantic palettes and species seams are instance-local.

const MATERIAL_TEMPLATE := preload("res://assets/art/characters/hero_penguin_v1_material.tres")
const RACER_LOD_SCENE := preload("res://assets/art/characters/hero_penguin_v1_lod1.glb")
const REQUIRED_CLIPS: PackedStringArray = [
	"countdown_idle", "fidget", "run", "lean_left", "lean_right",
	"jump_takeoff", "jump_air", "jump_land", "slide_enter", "slide_loop",
	"slide_exit", "ramp_launch", "ramp_flip", "ramp_land", "swim", "shove",
	"hit_left", "hit_right", "stumble", "recover", "wipeout", "defeat",
	"celebration",
]
const REQUIRED_SOCKETS: PackedStringArray = [
	"head_socket", "face_socket", "neck_socket", "trail_socket",
]
const LOOP_CLIPS: PackedStringArray = [
	"countdown_idle", "run", "jump_air", "slide_loop", "swim",
]
const RACER_ROLE: int = 1
const RACER_LOD_TRIANGLES_MIN: int = 8_000
const RACER_LOD_TRIANGLES_MAX: int = 12_000

const SPECIES_PALETTES: Dictionary = {
	"emperor": {
		"dorsal": Color("10243b"), "ventral": Color("f2dfba"),
		"mantle": Color("29445e"), "patch": Color("d99b38"),
	},
	"king": {
		"dorsal": Color("171b28"), "ventral": Color("f3eee3"),
		"mantle": Color("30394d"), "patch": Color("f36a18"),
	},
	"adelie": {
		"dorsal": Color("0b101b"), "ventral": Color("f1f3f2"),
		"mantle": Color("27354a"), "patch": Color("dceaf2"),
	},
	"gentoo": {
		"dorsal": Color("101723"), "ventral": Color("f1f2ee"),
		"mantle": Color("24486a"), "patch": Color("ecf3f3"),
	},
	"chinstrap": {
		"dorsal": Color("111722"), "ventral": Color("f0eee8"),
		"mantle": Color("2a4059"), "patch": Color("e8edf0"),
	},
	"rockhopper": {
		"dorsal": Color("211a20"), "ventral": Color("f1eadb"),
		"mantle": Color("493947"), "patch": Color("ffd133"),
	},
	"macaroni": {
		"dorsal": Color("1e1820"), "ventral": Color("f2eadc"),
		"mantle": Color("463347"), "patch": Color("ffad18"),
	},
	"little_blue": {
		"dorsal": Color("334a68"), "ventral": Color("edf2f3"),
		"mantle": Color("52759b"), "patch": Color("a9d8df"),
	},
}

var root_motion_disabled: bool = true
var _animation_player: AnimationPlayer
var _meshes: Array[MeshInstance3D] = []
var _sockets: Dictionary = {}
var _state_clip: StringName = &"countdown_idle"
var _one_shot_remaining: float = 0.0
var _speed_ratio: float = 0.0
var _configured: bool = false
var _configured_species: String = "emperor"
var _configured_identity_color: Color = Color(0.18, 0.78, 0.92)
var _lod0_meshes: Dictionary = {}
var _using_racer_lod: bool = false
var _racer_lod_triangle_count: int = 0
static var _placeholder_surface_material: StandardMaterial3D
static var _racer_lod_mesh_cache: Dictionary = {}


func _ready() -> void:
	_ensure_runtime()
	if not _configured:
		configure("emperor", Color(0.18, 0.78, 0.92))
	play_state(&"countdown_idle", true)


func configure(species_id: String, identity_color: Color) -> void:
	_ensure_runtime()
	var resolved_species := species_id if SPECIES_PALETTES.has(species_id) else "emperor"
	_configured_species = resolved_species
	_configured_identity_color = identity_color
	var palette: Dictionary = SPECIES_PALETTES[resolved_species]
	for mesh_instance: MeshInstance3D in _meshes:
		_apply_species_shape(mesh_instance, resolved_species)
		_apply_materials(mesh_instance, palette, identity_color)
	_configured = true


## HERO keeps complete 18–25k mesh. RACER uses one authored skinned LOD shared
## by every instance (~10k triangles). Far racers still hand off to facade's
## synchronized procedural backend, so no role ever disappears at distance.
func set_render_role(role: int) -> void:
	_ensure_runtime()
	_set_racer_lod(role == RACER_ROLE)


func is_using_racer_lod() -> bool:
	return _using_racer_lod


func racer_lod_triangle_count() -> int:
	return _racer_lod_triangle_count


func _set_racer_lod(enabled: bool) -> void:
	if _using_racer_lod == enabled and (not enabled or _racer_lod_triangle_count > 0):
		return
	var applied_triangles := 0
	for mesh_instance: MeshInstance3D in _meshes:
		var key := mesh_instance.get_instance_id()
		if not _lod0_meshes.has(key):
			_lod0_meshes[key] = mesh_instance.mesh
		var lod0 := _lod0_meshes[key] as Mesh
		if lod0 == null:
			continue
		if enabled:
			var lod_result := _racer_lod_mesh(lod0)
			var lod_mesh := lod_result.get("mesh") as ArrayMesh
			var triangle_count := int(lod_result.get("triangles", 0))
			if lod_mesh == null or triangle_count < RACER_LOD_TRIANGLES_MIN \
					or triangle_count > RACER_LOD_TRIANGLES_MAX:
				push_warning("Authored racer LOD1 unavailable for %s; preserving LOD0" % lod0)
				mesh_instance.mesh = lod0
				continue
			mesh_instance.mesh = lod_mesh
			applied_triangles += triangle_count
		else:
			mesh_instance.mesh = lod0
		_apply_species_shape(mesh_instance, _configured_species)
		_apply_materials(mesh_instance, SPECIES_PALETTES[_configured_species],
				_configured_identity_color)
	_using_racer_lod = enabled and applied_triangles >= RACER_LOD_TRIANGLES_MIN
	_racer_lod_triangle_count = applied_triangles if _using_racer_lod else 0


static func _racer_lod_mesh(source: Mesh) -> Dictionary:
	var cache_key := source.get_instance_id()
	if _racer_lod_mesh_cache.has(cache_key):
		return _racer_lod_mesh_cache[cache_key] as Dictionary
	var holder := RACER_LOD_SCENE.instantiate()
	if holder == null:
		var empty := {"mesh": null, "triangles": 0}
		_racer_lod_mesh_cache[cache_key] = empty
		return empty
	var lod_instance := holder.find_child("HeroPenguinLOD1", true, false) as MeshInstance3D
	var lod_mesh := lod_instance.mesh as ArrayMesh if lod_instance != null else null
	var selected_triangles := 0
	if lod_mesh != null:
		for surface_index: int in lod_mesh.get_surface_count():
			var arrays := lod_mesh.surface_get_arrays(surface_index)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			selected_triangles += indices.size() / 3
	holder.free()
	if lod_mesh == null or selected_triangles < RACER_LOD_TRIANGLES_MIN \
			or selected_triangles > RACER_LOD_TRIANGLES_MAX:
		var missing := {"mesh": null, "triangles": 0}
		_racer_lod_mesh_cache[cache_key] = missing
		return missing
	var value := {"mesh": lod_mesh, "triangles": selected_triangles}
	_racer_lod_mesh_cache[cache_key] = value
	return value


func set_pose(pose_id: int) -> void:
	var clip: StringName
	match pose_id:
		0:
			clip = &"run"
		1:
			clip = &"slide_loop"
		2:
			clip = &"jump_air"
		3:
			clip = &"swim"
		4:
			clip = &"stumble"
		5:
			clip = &"countdown_idle"
		6:
			clip = &"celebration"
		7:
			clip = &"defeat"
		_:
			clip = &"countdown_idle"
	_state_clip = clip
	if _one_shot_remaining <= 0.0:
		play_state(clip, clip in LOOP_CLIPS)


func drive_motion(speed_ratio: float, turn: float, _slope: float,
		_vertical_speed: float, _grounded: bool) -> void:
	_speed_ratio = clampf(speed_ratio, 0.0, 1.5)
	if absf(turn) > 0.64 and _state_clip == &"run" and _one_shot_remaining <= 0.0:
		play_state(&"lean_left" if turn < 0.0 else &"lean_right", false)
		_one_shot_remaining = _clip_length(&"lean_left") * 0.65


func trigger_event(event_id: StringName, context: Dictionary = {}) -> void:
	var side := float(context.get("side", 1.0))
	var clip := StringName()
	match event_id:
		&"jumped", &"jump_takeoff":
			clip = &"jump_takeoff"
		&"landed", &"jump_land":
			clip = &"jump_land"
		&"slid", &"slide_enter":
			clip = &"slide_enter"
		&"slide_exit":
			clip = &"slide_exit"
		&"ramp_launched", &"ramp_launch":
			clip = &"ramp_launch"
		&"ramp_flip":
			clip = &"ramp_flip"
		&"ramp_land":
			clip = &"ramp_land"
		&"shove", &"shove_started":
			clip = &"shove"
		&"hit_taken", &"hit":
			clip = &"hit_left" if side < 0.0 else &"hit_right"
		&"stumble":
			clip = &"stumble"
		&"recover":
			clip = &"recover"
		&"wipeout":
			clip = &"wipeout"
		&"died", &"defeat":
			clip = &"defeat"
		&"celebrate", &"celebration":
			clip = &"celebration"
	if clip != StringName():
		play_one_shot(clip)


func tick(delta: float) -> void:
	_ensure_runtime()
	if _animation_player == null:
		return
	if _one_shot_remaining > 0.0:
		_one_shot_remaining = maxf(0.0, _one_shot_remaining - delta)
		if is_zero_approx(_one_shot_remaining):
			play_state(_state_clip, _state_clip in LOOP_CLIPS)
	if _one_shot_remaining <= 0.0 and _state_clip == &"run":
		_animation_player.speed_scale = lerpf(0.82, 1.42, clampf(_speed_ratio, 0.0, 1.0))


func get_socket(socket_id: StringName) -> Node3D:
	_ensure_runtime()
	return _sockets.get(String(socket_id)) as Node3D


func animation_names() -> PackedStringArray:
	_ensure_runtime()
	return _animation_player.get_animation_list() if _animation_player != null else PackedStringArray()


func missing_contract_items() -> PackedStringArray:
	_ensure_runtime()
	var missing := PackedStringArray()
	var names := animation_names()
	for clip: String in REQUIRED_CLIPS:
		if clip not in names:
			missing.append("animation:%s" % clip)
	for socket_name: String in REQUIRED_SOCKETS:
		if not _sockets.has(socket_name):
			missing.append("socket:%s" % socket_name)
	return missing


func play_state(clip: StringName, loop: bool) -> void:
	_ensure_runtime()
	if _animation_player == null or not _animation_player.has_animation(clip):
		return
	var animation := _animation_player.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	_animation_player.speed_scale = 1.0
	_animation_player.play(clip, 0.10)


func play_one_shot(clip: StringName) -> void:
	_ensure_runtime()
	if _animation_player == null or not _animation_player.has_animation(clip):
		return
	var animation := _animation_player.get_animation(clip)
	if animation != null:
		animation.loop_mode = Animation.LOOP_NONE
	_animation_player.speed_scale = 1.0
	_animation_player.play(clip, 0.07)
	_one_shot_remaining = maxf(0.05, _clip_length(clip))


func _clip_length(clip: StringName) -> float:
	if _animation_player == null or not _animation_player.has_animation(clip):
		return 0.1
	var animation := _animation_player.get_animation(clip)
	return animation.length if animation != null else 0.1


func _ensure_runtime() -> void:
	if _animation_player == null:
		var players := find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			_animation_player = players[0] as AnimationPlayer
	if _meshes.is_empty():
		for child: Node in find_children("*", "MeshInstance3D", true, false):
			_meshes.append(child as MeshInstance3D)
	if _sockets.is_empty():
		for socket_name: String in REQUIRED_SOCKETS:
			var socket := find_child(socket_name, true, false) as Node3D
			if socket != null:
				_sockets[socket_name] = socket


func _apply_species_shape(mesh_instance: MeshInstance3D, species_id: String) -> void:
	if mesh_instance.mesh == null:
		return
	for candidate: String in SPECIES_PALETTES.keys():
		var wanted := "species_%s" % candidate
		var index := -1
		for shape_index: int in mesh_instance.mesh.get_blend_shape_count():
			if String(mesh_instance.mesh.get_blend_shape_name(shape_index)) == wanted:
				index = shape_index
				break
		if index >= 0:
			mesh_instance.set_blend_shape_value(index, 1.0 if candidate == species_id else 0.0)


func _apply_materials(mesh_instance: MeshInstance3D, palette: Dictionary,
		identity_color: Color) -> void:
	if mesh_instance.mesh == null:
		return
	for surface_index: int in mesh_instance.mesh.get_surface_count():
		if _placeholder_surface_material == null:
			_placeholder_surface_material = StandardMaterial3D.new()
			_placeholder_surface_material.vertex_color_use_as_albedo = true
			_placeholder_surface_material.roughness = 0.67
		# Placeholder GLB export intentionally carries no PBR materials. Install
		# one shared neutral base RID once; shader instance uniforms own species
		# palette. Avoids per-racer ArrayMesh/material duplication and fixes dummy
		# renderer/transparency queries against null base materials.
		if mesh_instance.mesh.surface_get_material(surface_index) == null:
			mesh_instance.mesh.surface_set_material(surface_index, _placeholder_surface_material)
		if DisplayServer.get_name() == "headless":
			# Dummy renderer cannot compile spatial shader instance parameters and
			# reports a false runtime ERROR on teardown. Headless tests need mesh,
			# skin, clips, and transforms; visual shader is exercised by captures.
			mesh_instance.set_surface_override_material(surface_index,
					_placeholder_surface_material)
			continue
		mesh_instance.set_instance_shader_parameter(&"dorsal_color", palette["dorsal"])
		mesh_instance.set_instance_shader_parameter(&"ventral_color", palette["ventral"])
		mesh_instance.set_instance_shader_parameter(&"mantle_color", palette["mantle"])
		mesh_instance.set_instance_shader_parameter(&"patch_color", palette["patch"])
		mesh_instance.set_instance_shader_parameter(&"identity_color", identity_color)
		mesh_instance.set_surface_override_material(surface_index, MATERIAL_TEMPLATE)
