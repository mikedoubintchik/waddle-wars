class_name SnowballPickup
extends Area3D
## Collectible throwable-snowball pickup: a small sparkling snowball resting
## on the track. Grants +1 snowball ammo (up to Racer.MAX_SNOWBALL_AMMO) and
## is left in place when the racer is already full. All instances share one
## mesh and material set; "pooling" is hide + respawn like ItemBox, so a row
## keeps rewarding trailing racers without allocating new nodes.

const RESPAWN_TIME: float = 6.0
const GROUP_NAME: StringName = &"snowball_pickups"

static var _ball_mesh: SphereMesh = null
static var _ball_mat: StandardMaterial3D = null
static var _ball_mat_contrast: StandardMaterial3D = null
static var _sparkle_mesh: QuadMesh = null
static var _sparkle_mat: StandardMaterial3D = null

var _visual: MeshInstance3D = null
var _sparkle: MeshInstance3D = null
var _active: bool = true
var _bob_time: float = 0.0
var _base_y: float = 0.0


func _ready() -> void:
	collision_layer = GameConfig.LAYER_PICKUPS
	collision_mask = GameConfig.LAYER_RACERS
	monitoring = true
	add_to_group(GROUP_NAME)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.0
	shape.shape = sphere
	add_child(shape)
	_visual = MeshInstance3D.new()
	_visual.mesh = _get_mesh()
	_visual.material_override = _get_material()
	_visual.position.y = 0.32
	add_child(_visual)
	# Slight sparkle: one soft billboard glint riding the ball's shoulder.
	# Purely decorative, so skipped headless.
	if not GameConfig.is_headless():
		_sparkle = MeshInstance3D.new()
		_sparkle.mesh = _get_sparkle_mesh()
		_sparkle.material_override = _get_sparkle_material()
		_sparkle.position = Vector3(0.14, 0.24, 0.0)
		_visual.add_child(_sparkle)
	_base_y = position.y
	_bob_time = randf() * TAU
	body_entered.connect(_on_body_entered)


static func _get_mesh() -> SphereMesh:
	if _ball_mesh == null:
		_ball_mesh = SphereMesh.new()
		_ball_mesh.radius = 0.3
		_ball_mesh.height = 0.6
		_ball_mesh.radial_segments = 12
		_ball_mesh.rings = 6
	return _ball_mesh


static func _get_material() -> StandardMaterial3D:
	# High-contrast accessibility mode reuses the same bright-gold emissive
	# language as FishPickup so all pickups read consistently.
	var high_contrast := bool(SettingsManager.get_setting("accessibility", "high_contrast_pickups"))
	if high_contrast:
		if _ball_mat_contrast == null:
			_ball_mat_contrast = StandardMaterial3D.new()
			_ball_mat_contrast.albedo_color = Color(1.0, 0.85, 0.1)
			_ball_mat_contrast.emission_enabled = true
			_ball_mat_contrast.emission = Color(1.0, 0.7, 0.05)
			_ball_mat_contrast.emission_energy_multiplier = 1.6
		return _ball_mat_contrast
	if _ball_mat == null:
		_ball_mat = StandardMaterial3D.new()
		_ball_mat.albedo_color = Color(0.96, 0.98, 1.0)
		_ball_mat.roughness = 0.35
		_ball_mat.emission_enabled = true
		_ball_mat.emission = Color(0.62, 0.78, 0.95)
		_ball_mat.emission_energy_multiplier = 0.35
		_ball_mat.rim_enabled = true
		_ball_mat.rim = 0.6
	return _ball_mat


static func _get_sparkle_mesh() -> QuadMesh:
	if _sparkle_mesh == null:
		_sparkle_mesh = QuadMesh.new()
		_sparkle_mesh.size = Vector2(0.34, 0.34)
	return _sparkle_mesh


static func _get_sparkle_material() -> StandardMaterial3D:
	if _sparkle_mat == null:
		_sparkle_mat = StandardMaterial3D.new()
		_sparkle_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.85)
		_sparkle_mat.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.6)
		_sparkle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_sparkle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_sparkle_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return _sparkle_mat


func _physics_process(delta: float) -> void:
	if not _active:
		return
	_bob_time += delta
	position.y = _base_y + sin(_bob_time * 2.2) * 0.1
	_visual.rotation.y += delta * 1.3
	if _sparkle != null:
		# Gentle glint breathing; slow enough to stay reduced-flashing safe.
		var pulse := 0.75 + 0.25 * sin(_bob_time * 4.6)
		_sparkle.scale = Vector3(pulse, pulse, pulse)


## AI queries this before steering toward the pickup.
func is_available() -> bool:
	return _active


func _on_body_entered(body: Node3D) -> void:
	if not _active or not body is Racer:
		return
	var racer := body as Racer
	if not racer.add_snowball_ammo(1):
		return  # already carrying the max: leave it for a rival
	_active = false
	if racer.is_player:
		# Same pickup sfx as item boxes, pitched up so ammo reads distinct.
		AudioManager.play_sfx("sfx_powerup", 1.45, -4.0)
	_visual.visible = false
	set_deferred("monitoring", false)
	var timer := get_tree().create_timer(RESPAWN_TIME)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(self):
			_active = true
			_visual.visible = true
			set_deferred("monitoring", true))
