class_name Snowball
extends Area3D
## Thrown snowball with forgiving homing toward a target racer ahead.
## Can miss, hit course geometry, or be blocked by a shield.
##
## Visuals only (the collision sphere is untouched): the ball reuses the
## shared packed-snow glitter material from SnowballPickup so ammo and
## projectile read as one substance, gets motion-stretched along its
## velocity every frame (volume-preserving squash, like a fast-packed ball
## shedding loose powder), and leaves a trailing spray of soft billboard
## puffs driven by a single MultiMesh ring buffer — zero per-frame node or
## array allocation, and the whole trail is skipped when headless.

const SPEED: float = 30.0
const HOMING_STRENGTH: float = 3.2
const LIFETIME: float = 4.0

## Spray trail tuning: ring-buffer size, per-puff lifetime, emission cadence.
const TRAIL_COUNT: int = 14
const PUFF_LIFE: float = 0.5
const EMIT_INTERVAL: float = 0.03

static var _puff_mat: StandardMaterial3D = null

var thrower: Racer = null
var target: Racer = null
var _velocity: Vector3 = Vector3.ZERO
var _age: float = 0.0
var _visual: MeshInstance3D = null
var _trail: MultiMeshInstance3D = null
var _trail_mm: MultiMesh = null
var _puff_pos: PackedVector3Array = PackedVector3Array()
var _puff_vel: PackedVector3Array = PackedVector3Array()
var _puff_age: PackedFloat32Array = PackedFloat32Array()
var _puff_idx: int = 0
var _emit_accum: float = 0.0


func launch(p_thrower: Racer, p_target: Racer) -> void:
	thrower = p_thrower
	target = p_target
	var forward := -p_thrower.global_transform.basis.z
	global_position = p_thrower.global_position + Vector3.UP * 1.2 + forward * 1.0
	_velocity = forward * SPEED + Vector3.UP * 2.0


func _ready() -> void:
	collision_layer = GameConfig.LAYER_HAZARDS
	collision_mask = GameConfig.LAYER_RACERS | GameConfig.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.4
	shape.shape = sphere
	add_child(shape)
	_visual = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.35
	mesh.height = 0.7
	_visual.mesh = mesh
	_visual.material_override = SnowballPickup.get_snow_material()
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_visual)
	if not GameConfig.is_headless():
		_build_trail()
	body_entered.connect(_on_body_entered)


## Pre-builds the spray ring buffer: one MultiMesh of soft billboard puffs,
## top_level so emitted puffs stay put in world space as the ball flies on.
func _build_trail() -> void:
	_puff_pos.resize(TRAIL_COUNT)
	_puff_vel.resize(TRAIL_COUNT)
	_puff_age.resize(TRAIL_COUNT)
	for i: int in TRAIL_COUNT:
		_puff_age[i] = PUFF_LIFE
	_trail_mm = MultiMesh.new()
	_trail_mm.transform_format = MultiMesh.TRANSFORM_3D
	_trail_mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = _get_puff_material()
	_trail_mm.mesh = quad
	_trail_mm.instance_count = TRAIL_COUNT
	for i: int in TRAIL_COUNT:
		_trail_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3.ZERO))
		_trail_mm.set_instance_color(i, Color(1.0, 1.0, 1.0, 0.0))
	_trail = MultiMeshInstance3D.new()
	_trail.multimesh = _trail_mm
	_trail.top_level = true
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trail)


static func _get_puff_material() -> StandardMaterial3D:
	if _puff_mat == null:
		_puff_mat = StandardMaterial3D.new()
		_puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_puff_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_puff_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_puff_mat.billboard_keep_scale = true
		_puff_mat.vertex_color_use_as_albedo = true
		_puff_mat.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.7)
	return _puff_mat


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > LIFETIME:
		_pop()
		return
	if target != null and is_instance_valid(target) and target.state != Racer.State.FINISHED:
		var to_target := (target.global_position + Vector3.UP * 0.7) - global_position
		var desired := to_target.normalized() * SPEED
		_velocity = _velocity.lerp(desired, minf(delta * HOMING_STRENGTH, 1.0))
	else:
		_velocity.y -= 9.0 * delta
	global_position += _velocity * delta
	_update_visual()
	_update_trail(delta)


## Motion stretch: orient the visual along the velocity and stretch it with
## speed (squash on the other axes preserves apparent volume). Visual child
## only — the Area3D and its collision sphere never rotate or scale.
func _update_visual() -> void:
	var speed := _velocity.length()
	if speed < 0.1:
		return
	var dir := _velocity / speed
	var up_ref := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
	var stretch := clampf(1.0 + speed * 0.011, 1.0, 1.45)
	var squash := 1.0 / sqrt(stretch)
	_visual.transform = Transform3D(
		Basis.looking_at(dir, up_ref) * Basis.from_scale(Vector3(squash, squash, stretch)),
		Vector3.ZERO)


## Spray trail: emit fixed-cadence puffs behind the ball into the ring
## buffer, then age every live puff — drifting backward/outward, sinking,
## expanding while fading (per-instance color alpha). All writes go into
## pre-sized packed arrays and the MultiMesh; nothing allocates per frame.
func _update_trail(delta: float) -> void:
	if _trail_mm == null:
		return
	var speed := _velocity.length()
	_emit_accum += delta
	while _emit_accum >= EMIT_INTERVAL:
		_emit_accum -= EMIT_INTERVAL
		if speed > 4.0:
			_emit_puff(_velocity / speed)
	for i: int in TRAIL_COUNT:
		var age := _puff_age[i]
		if age >= PUFF_LIFE:
			continue
		age += delta
		_puff_age[i] = age
		var t := clampf(age / PUFF_LIFE, 0.0, 1.0)
		if t >= 1.0:
			_trail_mm.set_instance_color(i, Color(1.0, 1.0, 1.0, 0.0))
			continue
		var vel := _puff_vel[i]
		vel.y -= 3.0 * delta
		vel *= maxf(1.0 - 2.2 * delta, 0.0)
		_puff_vel[i] = vel
		var pos := _puff_pos[i] + vel * delta
		_puff_pos[i] = pos
		var s := lerpf(0.10, 0.42, t)
		_trail_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * s), pos))
		var a := (1.0 - t) * (1.0 - t) * 0.75
		_trail_mm.set_instance_color(i, Color(0.92, 0.96, 1.0, a))


func _emit_puff(dir: Vector3) -> void:
	var i := _puff_idx
	_puff_idx = (_puff_idx + 1) % TRAIL_COUNT
	_puff_age[i] = 0.0
	_puff_pos[i] = global_position - dir * 0.4 \
		+ Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.22
	_puff_vel[i] = -dir * (1.0 + randf() * 2.0) \
		+ Vector3((randf() - 0.5) * 1.6, randf() * 1.4, (randf() - 0.5) * 1.6)


func _on_body_entered(body: Node3D) -> void:
	if body == thrower:
		return
	if body is Racer:
		var racer := body as Racer
		racer.apply_stun("snowball")
		if racer.is_player or (thrower != null and thrower.is_player):
			AudioManager.play_sfx_3d("sfx_snowball_hit", global_position)
	_pop()


func _pop() -> void:
	var course := get_tree().get_first_node_in_group(&"course") as CourseBase
	if course != null:
		course.spawn_land_puff(global_position)
	queue_free()
