class_name ItemBox
extends Area3D
## Authored expedition supply cache. A rounded three-lobed pressure pod with
## repeated raised compass apertures replaces the legacy question-mark cube.
## Violet is the fixed power-up semantic; three carry cages plus four-point
## aperture geometry keep the pickup readable without hue. LOD0/LOD1 share one
## opaque 1024px painted albedo/normal/ORM atlas and Compatibility-safe material.
## Gameplay collision, signals, item RNG, respawn timing and pooling are unchanged.

const RESPAWN_TIME: float = 3.5
## Paths, not preloads: on a clean checkout the wrapper is scanned before its
## imported GLB dependencies exist. A class-scope preload therefore made the
## unrelated race scripts fail to parse during the first import pass.
const CACHE_SCENE_PATH := \
	"res://assets/art/interactives/item_cache/item_cache_v1.tscn"
const CACHE_MATERIAL_PATH := \
	"res://assets/art/interactives/item_cache/materials/item_cache_v1.tres"
const LOD_SWITCH_DISTANCE: float = 38.0
const LOD_FAR_DISTANCE: float = 140.0

static var _cache_scene: PackedScene = null
static var _cache_material: StandardMaterial3D = null
static var _cache_warmup_registered: bool = false
static var _cache_missing_reported: bool = false
static var _box_mat_contrast: StandardMaterial3D = null
static var _burst_base_mat: StandardMaterial3D = null
static var _shard_mesh: ArrayMesh = null
static var _shard_base_mat: StandardMaterial3D = null
static var _flash_mesh: QuadMesh = null
static var _flash_base_mat: StandardMaterial3D = null
static var _halo_mesh: QuadMesh = null
static var _halo_mat: StandardMaterial3D = null
static var _halo_mat_contrast: StandardMaterial3D = null
static var _burst_ring_mesh: TorusMesh = null
static var _ring_burst_base_mat: StandardMaterial3D = null
static var _mote_base_mat: StandardMaterial3D = null

var _visual: Node3D = null
var _halo: MeshInstance3D = null
var _burst: MeshInstance3D = null
var _burst_mat: StandardMaterial3D = null
var _shards: MeshInstance3D = null
var _shard_mat: StandardMaterial3D = null
var _flash: MeshInstance3D = null
var _flash_mat: StandardMaterial3D = null
var _ring: MeshInstance3D = null
var _ring_mat: StandardMaterial3D = null
var _motes: MeshInstance3D = null
var _mote_mat: StandardMaterial3D = null
var _burst_tween: Tween = null
var _respawn_tween: Tween = null
var _active: bool = true
var _spin_time: float = 0.0
var _glow_phase: float = 0.0
var _fx_rich: bool = true
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Time Trial promises "No items, pure skill": boxes never spawn there.
	# Physics process is disabled first since it can run once before the
	# deferred free and would touch the never-built _visual.
	if Game.mode == Game.Mode.TIME_TRIAL:
		set_physics_process(false)
		queue_free()
		return
	collision_layer = GameConfig.LAYER_PICKUPS
	collision_mask = GameConfig.LAYER_RACERS
	_rng.randomize()
	_glow_phase = _rng.randf_range(0.0, TAU)
	_fx_rich = String(SettingsManager.get_setting("display", "particle_quality")) != "low"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 1.4, 1.4)
	shape.shape = box
	add_child(shape)

	# Resolve the wrapper only when a real ItemBox is assembled, after Godot's
	# clean-import dependency pass. Courses assemble boxes behind SceneRouter's
	# loading overlay and before ShaderWarmup, so this lazy load remains outside
	# playable time. The public preload seam lets any future scene loader prime
	# the exact same cache without reinstating a parse-time dependency.
	if preload_authored_visual():
		_visual = _cache_scene.instantiate() as Node3D
	else:
		# Visual failure must not alter collider, item RNG or respawn mechanics.
		# Keep a stable transform target so physics remains safe while the import
		# error is visible in logs instead of cascading into null dereferences.
		_visual = Node3D.new()
	_visual.name = "AuthoredSupplyCache"
	_configure_cache_visual(_visual)
	add_child(_visual)

	# Fixed violet lane pool is presentation-only and remains two triangles.
	_halo = MeshInstance3D.new()
	_halo.name = "PowerupGroundCue"
	_halo.mesh = _get_halo_mesh()
	_halo.material_override = _get_halo_material()
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.position.y = -1.06
	add_child(_halo)

	# Pickup burst trio: expanding shell flash + radial ice shards + central
	# billboard flash. Materials are duplicated per box (alpha animates
	# independently); every node is created once here and reused on each
	# pickup — no per-pickup allocation beyond the one-shot tween.
	_burst_mat = _get_burst_base_material().duplicate() as StandardMaterial3D
	_burst = MeshInstance3D.new()
	_burst.name = "PickupBurst"
	_burst.mesh = _cache_lod_mesh(_visual, "LOD1")
	_burst.material_override = _burst_mat
	_burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_burst.visible = false
	add_child(_burst)

	_shard_mat = _get_shard_base_material().duplicate() as StandardMaterial3D
	_shards = MeshInstance3D.new()
	_shards.name = "PickupShards"
	_shards.mesh = _get_shard_mesh()
	_shards.material_override = _shard_mat
	_shards.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shards.visible = false
	add_child(_shards)

	_flash_mat = _get_flash_base_material().duplicate() as StandardMaterial3D
	_flash = MeshInstance3D.new()
	_flash.name = "PickupFlash"
	_flash.mesh = _get_flash_mesh()
	_flash.material_override = _flash_mat
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	add_child(_flash)

	# Two more pre-built burst layers: a violet horizontal shockwave ring
	# (reuses the halo torus) and a cream mote fan counter-rotating
	# against the ice shards — brightness + pattern variety so the burst
	# reads without relying on hue. Skipped on low particle quality (the
	# shell flash + shards + center flash still carry the read).
	if _fx_rich:
		_ring_mat = _get_ring_burst_base_material().duplicate() as StandardMaterial3D
		_ring = MeshInstance3D.new()
		_ring.name = "PickupRing"
		_ring.mesh = _get_burst_ring_mesh()
		_ring.material_override = _ring_mat
		_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ring.visible = false
		add_child(_ring)

		_mote_mat = _get_mote_base_material().duplicate() as StandardMaterial3D
		_motes = MeshInstance3D.new()
		_motes.name = "PickupMotes"
		_motes.mesh = _get_shard_mesh()
		_motes.material_override = _mote_mat
		_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_motes.visible = false
		add_child(_motes)

	body_entered.connect(_on_body_entered)


func _configure_cache_visual(root: Node3D) -> void:
	var shared_material := _get_box_material()
	for lod_name: String in ["LOD0", "LOD1"]:
		var lod_root := root.get_node_or_null(lod_name)
		var meshes: Array[MeshInstance3D] = []
		_collect_cache_meshes(lod_root, meshes)
		for mesh: MeshInstance3D in meshes:
			mesh.material_override = shared_material
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh.visibility_range_fade_mode = \
				GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			if lod_name == "LOD0":
				mesh.visibility_range_begin = 0.0
				mesh.visibility_range_end = LOD_SWITCH_DISTANCE
			else:
				mesh.visibility_range_begin = LOD_SWITCH_DISTANCE
				mesh.visibility_range_end = LOD_FAR_DISTANCE


func _collect_cache_meshes(node: Node, output: Array[MeshInstance3D]) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		output.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect_cache_meshes(child, output)


func _cache_lod_mesh(root: Node3D, lod_name: String) -> Mesh:
	var meshes: Array[MeshInstance3D] = []
	_collect_cache_meshes(root.get_node_or_null(lod_name), meshes)
	return meshes[0].mesh if not meshes.is_empty() else null


func _physics_process(delta: float) -> void:
	_spin_time += delta
	# Upright beacon rotation preserves compass/aperture recognition; restrained
	# counter-sway adds life without rolling the visual outside its collider.
	_visual.rotation.y += delta * 0.82
	_visual.rotation.x = sin(_spin_time * 1.35 + _glow_phase) * 0.075
	_visual.rotation.z = sin(_spin_time * 1.07 + _glow_phase * 0.7) * 0.055
	var bob := sin(_spin_time * 2.0) * 0.09
	_visual.position.y = bob


func _on_body_entered(body: Node3D) -> void:
	if not _active or not body is Racer:
		return
	var racer := body as Racer
	if racer.held_item != "" or racer.state == Racer.State.FINISHED:
		return
	_active = false
	var item := PowerupsDB.roll(racer.race_position, GameConfig.RACER_COUNT, _rng)
	racer.receive_item(item)
	if racer.is_player:
		AudioManager.play_sfx("sfx_powerup", 1.0, -2.0)
	_visual.visible = false
	_halo.visible = false
	_play_burst()
	set_deferred("monitoring", false)
	var timer := get_tree().create_timer(RESPAWN_TIME)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(self):
			_active = true
			_visual.visible = true
			_halo.visible = true
			set_deferred("monitoring", true)
			_play_respawn())


## Respawn shimmer-in: the shell scales back up with a back-eased overshoot
## while the central flash blooms softly — the box condenses out of the air
## instead of popping into existence. Reuses the per-box flash node/material.
func _play_respawn() -> void:
	if _respawn_tween != null and _respawn_tween.is_valid():
		_respawn_tween.kill()
	_visual.scale = Vector3.ONE * 0.15
	_respawn_tween = create_tween()
	_respawn_tween.set_parallel(true)
	_respawn_tween.tween_property(_visual, "scale", Vector3.ONE, 0.4) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _flash != null:
		_flash.visible = true
		_flash.scale = Vector3.ONE * 0.4
		_flash_mat.albedo_color = Color(0.72, 0.42, 1.0, 0.55)
		_respawn_tween.tween_property(_flash, "scale", Vector3.ONE * 1.5, 0.35) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_respawn_tween.tween_property(_flash_mat, "albedo_color:a", 0.0, 0.35)
		_respawn_tween.chain().tween_callback(func() -> void:
			_flash.visible = false)


## One-shot pickup burst: additive cache shell + spinning frost shards + quick
## central violet flash + expanding shockwave ring + cream mote fan (rich
## layers skipped on low
## particle quality). All nodes pre-built in _ready; only the one-shot tween
## is allocated per pickup.
func _play_burst() -> void:
	if _burst == null:
		return
	if _burst_tween != null and _burst_tween.is_valid():
		_burst_tween.kill()
	_burst.visible = true
	_burst.scale = Vector3.ONE * 1.02
	# Kept deliberately faint and short: this layer is the cache's own
	# silhouette blown up additively, so anything stronger reads as a giant
	# white box swallowing the racers rather than as a flash.
	_burst_mat.albedo_color = Color(0.62, 0.26, 1.0, 0.45)
	_shards.visible = true
	_shards.scale = Vector3.ONE * 0.9
	_shards.rotation.y = _rng.randf_range(0.0, TAU)
	_shard_mat.albedo_color = Color(0.90, 0.93, 0.88, 0.95)
	_flash.visible = true
	_flash.scale = Vector3.ONE * 0.6
	_flash_mat.albedo_color = Color(0.76, 0.43, 1.0, 0.85)
	if _ring != null:
		_ring.visible = true
		_ring.scale = Vector3.ONE * 0.7
		_ring_mat.albedo_color = Color(0.58, 0.28, 1.0, 0.9)
	if _motes != null:
		_motes.visible = true
		_motes.scale = Vector3.ONE * 0.45
		_motes.rotation.y = -_shards.rotation.y
		_mote_mat.albedo_color = Color(0.94, 0.90, 0.76, 0.95)
	_burst_tween = create_tween()
	_burst_tween.set_parallel(true)
	_burst_tween.tween_property(_burst, "scale", Vector3.ONE * 1.7, 0.20) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_burst_tween.tween_property(_burst_mat, "albedo_color:a", 0.0, 0.20)
	_burst_tween.tween_property(_shards, "scale", Vector3.ONE * 3.0, 0.44) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_burst_tween.tween_property(_shards, "rotation:y", _shards.rotation.y + 1.3, 0.44)
	_burst_tween.tween_property(_shard_mat, "albedo_color:a", 0.0, 0.44)
	_burst_tween.tween_property(_flash, "scale", Vector3.ONE * 3.0, 0.24) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_burst_tween.tween_property(_flash_mat, "albedo_color:a", 0.0, 0.24)
	if _ring != null:
		_burst_tween.tween_property(_ring, "scale", Vector3.ONE * 3.6, 0.48) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_burst_tween.tween_property(_ring_mat, "albedo_color:a", 0.0, 0.48)
	if _motes != null:
		_burst_tween.tween_property(_motes, "scale", Vector3.ONE * 2.1, 0.52) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_burst_tween.tween_property(_motes, "rotation:y", _motes.rotation.y - 1.7, 0.52)
		_burst_tween.tween_property(_mote_mat, "albedo_color:a", 0.0, 0.52)
	_burst_tween.chain().tween_callback(func() -> void:
		_burst.visible = false
		_shards.visible = false
		_flash.visible = false
		if _ring != null:
			_ring.visible = false
		if _motes != null:
			_motes.visible = false)


## --- Shared visual resources (built once, shared by all boxes) -----------


## Scene-loader seam for the authored cache. Safe during fresh import because
## the script itself contains only paths; resource resolution starts solely
## when this method is called after the import pass. CACHE_MODE_REUSE makes all
## ItemBox instances and retries share the imported scenes, meshes and atlas.
## Registering both LOD meshes here also places their shader signatures in the
## existing behind-overlay ShaderWarmup pass before countdown.
static func preload_authored_visual() -> bool:
	if _cache_scene == null:
		if ResourceLoader.exists(CACHE_SCENE_PATH, "PackedScene"):
			_cache_scene = ResourceLoader.load(
				CACHE_SCENE_PATH, "PackedScene", ResourceLoader.CACHE_MODE_REUSE
			) as PackedScene
	if _cache_material == null:
		if ResourceLoader.exists(CACHE_MATERIAL_PATH, "StandardMaterial3D"):
			_cache_material = ResourceLoader.load(
				CACHE_MATERIAL_PATH, "StandardMaterial3D",
				ResourceLoader.CACHE_MODE_REUSE
			) as StandardMaterial3D
	var ready := _cache_scene != null and _cache_material != null
	if not ready:
		if not _cache_missing_reported:
			push_error("ItemBox: authored cache unavailable after import (%s, %s)" % [
				CACHE_SCENE_PATH, CACHE_MATERIAL_PATH])
			_cache_missing_reported = true
		return false
	_cache_missing_reported = false
	_register_authored_warmup()
	return true


static func _register_authored_warmup() -> void:
	if _cache_warmup_registered or _cache_scene == null or _cache_material == null:
		return
	var probe_root := _cache_scene.instantiate()
	var meshes: Array[MeshInstance3D] = []
	_collect_cache_meshes_static(probe_root, meshes)
	for instance: MeshInstance3D in meshes:
		if instance.mesh != null:
			ShaderWarmup.register_external_probe(instance.mesh, _cache_material)
	probe_root.free()
	_cache_warmup_registered = true


static func _collect_cache_meshes_static(
		node: Node, output: Array[MeshInstance3D]) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		output.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect_cache_meshes_static(child, output)


## One atlas material in normal mode; bright emissive whole-silhouette override
## in high-contrast mode. Both paths remain one surface and one draw per LOD.
static func _get_box_material() -> Material:
	var high_contrast := bool(SettingsManager.get_setting("accessibility", "high_contrast_pickups"))
	if not high_contrast:
		return _cache_material
	if _box_mat_contrast == null:
		_box_mat_contrast = StandardMaterial3D.new()
		_box_mat_contrast.albedo_color = Color(1.0, 0.85, 0.1)
		_box_mat_contrast.emission_enabled = true
		_box_mat_contrast.emission = Color(1.0, 0.7, 0.05)
		_box_mat_contrast.emission_energy_multiplier = 1.8
		# Grow-pass rim: pushing the shell slightly outward along its
		# normals hardens the silhouette edge against any backdrop.
		_box_mat_contrast.grow = true
		_box_mat_contrast.grow_amount = 0.015
	return _box_mat_contrast


static func _get_burst_base_material() -> StandardMaterial3D:
	if _burst_base_mat != null:
		return _burst_base_mat
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.62, 0.26, 1.0, 0.0)
	mat.render_priority = 1
	_burst_base_mat = mat
	return _burst_base_mat


## Radial ice-shard fan for the pickup burst: thin triangles distributed on
## a golden-angle sphere spiral with deterministic length variance.
static func _get_shard_mesh() -> ArrayMesh:
	if _shard_mesh != null:
		return _shard_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 14
	for i: int in count:
		var g := float(i) * 2.39996
		var y := lerpf(-0.75, 0.75, (float(i) + 0.5) / float(count))
		var r := sqrt(maxf(1.0 - y * y, 0.0))
		var dir := Vector3(cos(g) * r, y, sin(g) * r)
		var ref_axis := Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT
		var tangent := dir.cross(ref_axis).normalized()
		var tip := 0.55 + 0.25 * fmod(float(i) * 0.618, 1.0)
		st.add_vertex(dir * 0.3 + tangent * 0.05)
		st.add_vertex(dir * 0.3 - tangent * 0.05)
		st.add_vertex(dir * tip)
	_shard_mesh = st.commit()
	return _shard_mesh


static func _get_shard_base_material() -> StandardMaterial3D:
	if _shard_base_mat != null:
		return _shard_base_mat
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.85, 0.95, 1.0, 0.0)
	mat.render_priority = 1
	_shard_base_mat = mat
	return _shard_base_mat


static func _get_flash_mesh() -> QuadMesh:
	if _flash_mesh != null:
		return _flash_mesh
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.1, 1.1)
	_flash_mesh = mesh
	return _flash_mesh


static func _get_flash_base_material() -> StandardMaterial3D:
	if _flash_base_mat != null:
		return _flash_base_mat
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.85)
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	mat.render_priority = 2
	_flash_base_mat = mat
	return _flash_base_mat


## Ground marker: one horizontal quad with a soft radial falloff. Replaces the
## old 288-triangle torus with 2 triangles for a stronger read.
static func _get_halo_mesh() -> QuadMesh:
	if _halo_mesh == null:
		_halo_mesh = QuadMesh.new()
		_halo_mesh.size = Vector2(1.9, 1.9)
		_halo_mesh.orientation = PlaneMesh.FACE_Y
	return _halo_mesh


## Torus used only by the pickup shockwave ring (the ground marker is a disc).
static func _get_burst_ring_mesh() -> TorusMesh:
	if _burst_ring_mesh == null:
		_burst_ring_mesh = TorusMesh.new()
		_burst_ring_mesh.inner_radius = 0.5
		_burst_ring_mesh.outer_radius = 0.62
		_burst_ring_mesh.rings = 20
		_burst_ring_mesh.ring_segments = 4
	return _burst_ring_mesh


static func _get_ring_burst_base_material() -> StandardMaterial3D:
	if _ring_burst_base_mat != null:
		return _ring_burst_base_mat
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.58, 0.28, 1.0, 0.0)
	mat.render_priority = 1
	_ring_burst_base_mat = mat
	return _ring_burst_base_mat


static func _get_mote_base_material() -> StandardMaterial3D:
	if _mote_base_mat != null:
		return _mote_base_mat
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.94, 0.90, 0.76, 0.0)
	mat.render_priority = 1
	_mote_base_mat = mat
	return _mote_base_mat


## Ground cue repeats violet semantic beneath the pod. The opaque authored
## cache remains the primary read; this pooled two-triangle wash only anchors
## its lane position on both snow and dark ice.
static func _get_halo_material() -> StandardMaterial3D:
	var high_contrast := bool(SettingsManager.get_setting("accessibility", "high_contrast_pickups"))
	if high_contrast:
		if _halo_mat_contrast == null:
			_halo_mat_contrast = _make_disc_material(Color(1.0, 0.86, 0.35, 0.7))
		return _halo_mat_contrast
	if _halo_mat == null:
		_halo_mat = _make_disc_material(Color(0.58, 0.29, 0.92, 0.48))
	return _halo_mat


static func _make_disc_material(tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.95)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = -3
	return mat
