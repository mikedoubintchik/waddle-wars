class_name ItemBox
extends Area3D
## Floating power-up box. Grants a position-weighted random item, then
## respawns after a short delay (simple pooling: hide + reactivate).

static var _box_mat: StandardMaterial3D = null

const RESPAWN_TIME: float = 3.5

var _visual: MeshInstance3D = null
var _active: bool = true
var _spin_time: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	collision_layer = GameConfig.LAYER_PICKUPS
	collision_mask = GameConfig.LAYER_RACERS
	_rng.randomize()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 1.4, 1.4)
	shape.shape = box
	add_child(shape)
	_visual = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 1.0, 1.0)
	_visual.mesh = mesh
	if _box_mat == null:
		_box_mat = StandardMaterial3D.new()
		_box_mat.albedo_color = Color(0.4, 0.75, 1.0, 0.75)
		_box_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_box_mat.emission_enabled = true
		_box_mat.emission = Color(0.3, 0.6, 1.0)
		_box_mat.emission_energy_multiplier = 0.9
		_box_mat.rim_enabled = true
		_box_mat.rim = 0.7
		_box_mat.roughness = 0.1
	_visual.material_override = _box_mat
	add_child(_visual)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_spin_time += delta
	_visual.rotation.y += delta * 1.6
	_visual.rotation.x = sin(_spin_time * 1.3) * 0.3
	_visual.position.y = sin(_spin_time * 2.0) * 0.12


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
	set_deferred("monitoring", false)
	var timer := get_tree().create_timer(RESPAWN_TIME)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(self):
			_active = true
			_visual.visible = true
			set_deferred("monitoring", true))
