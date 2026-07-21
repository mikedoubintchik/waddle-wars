class_name FishPickup
extends Area3D
## Collectible fish: score pickup, cosmetic currency, magnet-attractable.

static var _fish_mesh: ArrayMesh = null
static var _fish_mat: StandardMaterial3D = null
static var _fish_mat_contrast: StandardMaterial3D = null

var value: int = 1
var collected: bool = false
var _bob_time: float = 0.0
var _base_y: float = 0.0
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
	_base_y = position.y
	_bob_time = randf() * TAU
	body_entered.connect(_on_body_entered)


static func _get_fish_mesh() -> ArrayMesh:
	if _fish_mesh != null:
		return _fish_mesh
	# Simple stylized fish: squashed body sphere + prism tail merged into
	# one ArrayMesh via append_from with transforms.
	var body := SphereMesh.new()
	body.radius = 0.28
	body.height = 0.4
	body.radial_segments = 10
	body.rings = 6
	var tail := PrismMesh.new()
	tail.size = Vector3(0.3, 0.3, 0.12)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(body, 0, Transform3D(Basis.from_scale(Vector3(1.3, 1.0, 0.7)), Vector3.ZERO))
	st.append_from(tail, 0, Transform3D(
		Basis().rotated(Vector3.FORWARD, deg_to_rad(90)), Vector3(0.4, 0.0, 0.0)))
	_fish_mesh = st.commit()
	return _fish_mesh


static func _get_material() -> StandardMaterial3D:
	var high_contrast := bool(SettingsManager.get_setting("accessibility", "high_contrast_pickups"))
	if high_contrast:
		if _fish_mat_contrast == null:
			_fish_mat_contrast = StandardMaterial3D.new()
			_fish_mat_contrast.albedo_color = Color(1.0, 0.85, 0.1)
			_fish_mat_contrast.emission_enabled = true
			_fish_mat_contrast.emission = Color(1.0, 0.7, 0.05)
			_fish_mat_contrast.emission_energy_multiplier = 1.6
		return _fish_mat_contrast
	if _fish_mat == null:
		_fish_mat = StandardMaterial3D.new()
		_fish_mat.albedo_color = Color(0.55, 0.85, 0.95)
		_fish_mat.metallic = 0.4
		_fish_mat.roughness = 0.3
		_fish_mat.emission_enabled = true
		_fish_mat.emission = Color(0.3, 0.6, 0.8)
		_fish_mat.emission_energy_multiplier = 0.5
	return _fish_mat


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
		position.y = _base_y + sin(_bob_time * 2.4) * 0.15
		rotation.y += delta * 2.0


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
