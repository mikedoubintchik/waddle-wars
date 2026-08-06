class_name FishPickup
extends Area3D
## Collectible fish: score pickup, cosmetic currency, magnet-attractable.
## Visual: stylized fish (fusiform body, forked tail, dorsal + pectoral fins,
## eye dots) built once as a shared ArrayMesh with per-surface materials so
## every instance reuses the same mesh and material resources.

static var _fish_mesh: ArrayMesh = null
static var _fish_mat_contrast: StandardMaterial3D = null
static var _ring_mesh: TorusMesh = null
static var _ring_mat: StandardMaterial3D = null
static var _ring_mat_contrast: StandardMaterial3D = null

var value: int = 1
var collected: bool = false
var _bob_time: float = 0.0
var _spin: float = 0.0
var _magnet_target: Racer = null
var _visual: MeshInstance3D = null


func _ready() -> void:
	collision_layer = GameConfig.LAYER_PICKUPS
	collision_mask = GameConfig.LAYER_RACERS
	monitoring = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.0
	shape.shape = sphere
	add_child(shape)
	_visual = MeshInstance3D.new()
	_visual.mesh = _get_fish_mesh()
	_visual.material_override = _get_material()
	add_child(_visual)
	# Soft halo UNDER the fish so pickups read clearly at race speed.
	# Underlay only -- the body itself stays fish-shaped, never a glowing orb.
	var ring := MeshInstance3D.new()
	ring.mesh = _get_ring_mesh()
	ring.material_override = _get_ring_material()
	ring.position.y = -0.16
	_visual.add_child(ring)
	_bob_time = randf() * TAU
	body_entered.connect(_on_body_entered)


static func _get_fish_mesh() -> ArrayMesh:
	if _fish_mesh != null:
		return _fish_mesh
	var mesh := ArrayMesh.new()
	# Surface 0: fusiform body -- sphere lathe squashed into a torpedo
	# (nose at -X, tail root at +X). Normals regenerated after the
	# non-uniform scale so the ellipsoid shades correctly.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := SphereMesh.new()
	body.radius = 0.5
	body.height = 1.0
	body.radial_segments = 16
	body.rings = 8
	st.append_from(body, 0, Transform3D(Basis.from_scale(Vector3(0.44, 0.24, 0.15)), Vector3.ZERO))
	st.deindex()
	st.generate_normals()
	st.commit(mesh)
	# Surface 1: fins -- forked caudal tail (two lobes), dorsal fin, and a
	# pectoral pair. Flat blades, double-sided via the fin material.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_fin(st, Vector3(0.18, 0.0, 0.0), Vector3(0.40, 0.16, 0.0), Vector3(0.28, 0.03, 0.0))
	_add_fin(st, Vector3(0.18, 0.0, 0.0), Vector3(0.28, -0.03, 0.0), Vector3(0.40, -0.16, 0.0))
	_add_fin(st, Vector3(-0.06, 0.09, 0.0), Vector3(0.04, 0.26, 0.0), Vector3(0.12, 0.08, 0.0))
	_add_fin(st, Vector3(-0.06, -0.02, 0.06), Vector3(0.05, -0.09, 0.15), Vector3(0.02, -0.01, 0.07))
	_add_fin(st, Vector3(-0.06, -0.02, -0.06), Vector3(0.02, -0.01, -0.07), Vector3(0.05, -0.09, -0.15))
	st.generate_normals()
	st.commit(mesh)
	# Surface 2: eye dots, one per side near the nose.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var eye := SphereMesh.new()
	eye.radius = 0.035
	eye.height = 0.07
	eye.radial_segments = 8
	eye.rings = 4
	st.append_from(eye, 0, Transform3D(Basis(), Vector3(-0.13, 0.03, 0.052)))
	st.append_from(eye, 0, Transform3D(Basis(), Vector3(-0.13, 0.03, -0.052)))
	st.commit(mesh)
	# Shared per-surface materials (stored on the shared mesh, so all
	# instances reuse them; high-contrast mode overrides via material_override).
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.45, 0.62, 0.78)
	body_mat.metallic = 0.55
	body_mat.roughness = 0.28
	body_mat.emission_enabled = true
	body_mat.emission = Color(0.1, 0.18, 0.28)
	body_mat.emission_energy_multiplier = 0.5
	mesh.surface_set_material(0, body_mat)
	var fin_mat := StandardMaterial3D.new()
	fin_mat.albedo_color = Color(1.0, 0.45, 0.12)
	fin_mat.metallic = 0.1
	fin_mat.roughness = 0.4
	fin_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fin_mat.emission_enabled = true
	fin_mat.emission = Color(0.9, 0.3, 0.05)
	fin_mat.emission_energy_multiplier = 0.45
	mesh.surface_set_material(1, fin_mat)
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.05, 0.06, 0.08)
	eye_mat.metallic = 0.0
	eye_mat.roughness = 0.2
	mesh.surface_set_material(2, eye_mat)
	_fish_mesh = mesh
	return _fish_mesh


static func _add_fin(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


static func _get_material() -> StandardMaterial3D:
	# Returns a whole-fish override for high-contrast accessibility mode
	# (bright gold emissive silhouette), or null so the mesh's per-surface
	# fish materials show normally.
	var high_contrast := bool(SettingsManager.get_setting("accessibility", "high_contrast_pickups"))
	if not high_contrast:
		return null
	if _fish_mat_contrast == null:
		_fish_mat_contrast = StandardMaterial3D.new()
		_fish_mat_contrast.albedo_color = Color(1.0, 0.85, 0.1)
		_fish_mat_contrast.emission_enabled = true
		_fish_mat_contrast.emission = Color(1.0, 0.7, 0.05)
		_fish_mat_contrast.emission_energy_multiplier = 1.6
		_fish_mat_contrast.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _fish_mat_contrast


static func _get_ring_mesh() -> TorusMesh:
	if _ring_mesh == null:
		_ring_mesh = TorusMesh.new()
		_ring_mesh.inner_radius = 0.3
		_ring_mesh.outer_radius = 0.38
		_ring_mesh.rings = 24
		_ring_mesh.ring_segments = 8
	return _ring_mesh


static func _get_ring_material() -> StandardMaterial3D:
	var high_contrast := bool(SettingsManager.get_setting("accessibility", "high_contrast_pickups"))
	if high_contrast:
		if _ring_mat_contrast == null:
			_ring_mat_contrast = StandardMaterial3D.new()
			_ring_mat_contrast.albedo_color = Color(1.0, 0.85, 0.2, 0.55)
			_ring_mat_contrast.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_ring_mat_contrast.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		return _ring_mat_contrast
	if _ring_mat == null:
		_ring_mat = StandardMaterial3D.new()
		_ring_mat.albedo_color = Color(0.55, 0.9, 1.0, 0.3)
		_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _ring_mat


func _physics_process(delta: float) -> void:
	if collected:
		return
	_bob_time += delta
	if _magnet_target != null and is_instance_valid(_magnet_target):
		var to_target := _magnet_target.global_position + Vector3.UP * 0.6 - global_position
		if to_target.length() < 1.2:
			_on_body_entered(_magnet_target)
			return
		global_position += to_target.normalized() * 22.0 * delta
	else:
		# Bob/spin only the visual child so the Area3D transform stays static
		# (no broadphase re-sync every tick; same pattern as item_box.gd).
		_spin += delta * 0.9
		_visual.position.y = sin(_bob_time * 2.4) * 0.15
		# Gentle swim wiggle: yaw sine on the visual so the fish looks alive.
		_visual.rotation.y = _spin + sin(_bob_time * 5.2) * 0.3


func attract_to(racer: Racer) -> void:
	if not collected:
		_magnet_target = racer


func _on_body_entered(body: Node3D) -> void:
	if collected or not body is Racer:
		return
	var racer := body as Racer
	collected = true
	racer.collect_fish(value)
	if racer.is_player:
		AudioManager.play_sfx_varied("sfx_fish", -2.0)
	set_deferred("monitoring", false)
	# Pop animation then free.
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector3.ONE * 1.6, 0.08)
	tween.tween_property(_visual, "scale", Vector3.ONE * 0.01, 0.12)
	tween.tween_callback(queue_free)
