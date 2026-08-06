class_name HazardSnowball
extends Node3D
## Big rolling snowball that travels down a stretch of track and resets.
## Telegraphed by size, rumble sound, and a consistent lane. Stuns on hit.

var guide: PathGuide = null
var start_offset: float = 0.0
var end_offset: float = 0.0
var lateral: float = 0.0
var speed: float = 14.0
var radius: float = 1.7

const ROLL_SFX_INTERVAL: float = 1.1

var _offset: float = 0.0
var _visual: MeshInstance3D
var _area: Area3D
var _respawn_wait: float = 0.0
var _hit_cooldown: Dictionary = {}
var _roll_sfx_timer: float = 0.0


func configure(p_guide: PathGuide, p_start: float, p_end: float, p_lateral: float, p_speed: float = 14.0) -> void:
	guide = p_guide
	start_offset = p_start
	end_offset = p_end
	lateral = p_lateral
	speed = p_speed
	_offset = p_start


func _ready() -> void:
	add_to_group(&"hazards")
	_visual = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 14
	mesh.rings = 10
	_visual.mesh = mesh
	_visual.material_override = PenguinVisual.get_material(Color(0.96, 0.98, 1.0), 0.0, 0.85)
	add_child(_visual)
	_area = Area3D.new()
	_area.collision_layer = GameConfig.LAYER_HAZARDS
	_area.collision_mask = GameConfig.LAYER_RACERS
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius * 0.9
	shape.shape = sphere
	_area.add_child(shape)
	add_child(_area)
	_area.body_entered.connect(_on_hit)
	if guide != null:
		global_position = guide.point_at(_offset, lateral, radius)


func _physics_process(delta: float) -> void:
	if guide == null:
		return
	if _respawn_wait > 0.0:
		_respawn_wait -= delta
		if _respawn_wait <= 0.0:
			_offset = start_offset
			_visual.visible = true
			_area.monitoring = true
		return
	_offset += speed * delta
	if _offset >= end_offset:
		_visual.visible = false
		_area.set_deferred("monitoring", false)
		_respawn_wait = 2.0
		return
	global_position = guide.point_at(_offset, lateral, radius * 0.95)
	_visual.rotate_x(-speed * delta / radius)
	# Throttled low rumble while rolling: the audible telegraph promised in
	# the class doc, matching the seal/geyser positional-audio pattern.
	_roll_sfx_timer -= delta
	if _roll_sfx_timer <= 0.0:
		_roll_sfx_timer = ROLL_SFX_INTERVAL
		AudioManager.play_sfx_3d("sfx_slide", global_position, 0.5, -4.0)


func _on_hit(body: Node3D) -> void:
	if not body is Racer:
		return
	var racer := body as Racer
	var now := Time.get_ticks_msec()
	if int(_hit_cooldown.get(racer.racer_key, 0)) > now:
		return
	_hit_cooldown[racer.racer_key] = now + 3000
	# Heavy thud layered under apply_stun's sfx_impact; pitched well below
	# the thrown-snowball version so the big hazard reads bigger. The 3s
	# per-racer cooldown above throttles it.
	AudioManager.play_sfx_3d("sfx_snowball_hit", global_position, 0.7, -2.0)
	if racer.apply_stun("snowball_hazard") and racer.is_player:
		var camera := get_viewport().get_camera_3d()
		if camera != null and camera.get_parent() is ChaseCamera:
			(camera.get_parent() as ChaseCamera).add_shake(0.55)
