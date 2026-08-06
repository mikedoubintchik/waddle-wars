class_name Snowball
extends Area3D
## Thrown snowball with forgiving homing toward a target racer ahead.
## Can miss, hit course geometry, or be blocked by a shield.
##
## Visuals only (the collision sphere is untouched): the ball reuses the
## shared packed-snow glitter material from SnowballPickup so ammo and
## projectile read as one substance, spins about its travel axis, wears a
## soft additive powder-fuzz corona, gets motion-stretched along its
## velocity every frame (volume-preserving squash, like a fast-packed ball
## shedding loose powder), and leaves a trailing spray of soft billboard
## puffs driven by a single MultiMesh ring buffer — zero per-frame node or
## array allocation, and the whole trail is skipped when headless.
##
## Impact: instead of vanishing, the ball splats — a radial fan of snow
## chunks bursts outward while a flattened irregular splat disc fades on the
## ground (cheap mesh, no decals: gl_compatibility safe), the pooled course
## land-puff fires, and the spray trail is left to finish fading before the
## node frees itself. Trail puff count and the chunk fan respect
## display/particle_quality (low drops the chunks and shortens the trail).

const SPEED: float = 30.0
const HOMING_STRENGTH: float = 3.2
const LIFETIME: float = 4.0

## Spray trail tuning: default ring-buffer size, per-puff lifetime, cadence.
const TRAIL_COUNT: int = 14
const PUFF_LIFE: float = 0.5
const EMIT_INTERVAL: float = 0.03

static var _puff_mat: StandardMaterial3D = null
static var _fuzz_mat: StandardMaterial3D = null
static var _fuzz_mesh: QuadMesh = null
static var _chunk_mesh: ArrayMesh = null
static var _chunk_base_mat: StandardMaterial3D = null
static var _splat_mesh: ArrayMesh = null
static var _splat_base_mat: StandardMaterial3D = null

var thrower: Racer = null
var target: Racer = null
var _velocity: Vector3 = Vector3.ZERO
var _age: float = 0.0
var _roll: float = 0.0
var _popped: bool = false
var _visual: MeshInstance3D = null
var _fuzz: MeshInstance3D = null
var _chunks: MeshInstance3D = null
var _chunk_mat: StandardMaterial3D = null
var _splat: MeshInstance3D = null
var _splat_mat: StandardMaterial3D = null
var _trail: MultiMeshInstance3D = null
var _trail_mm: MultiMesh = null
var _trail_count: int = TRAIL_COUNT
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
		var quality := String(SettingsManager.get_setting("display", "particle_quality"))
		_trail_count = 20 if quality == "high" else (14 if quality == "medium" else 8)
		_build_trail()
		_build_fuzz()
		_build_impact_fx(quality != "low")
	body_entered.connect(_on_body_entered)


## Pre-builds the spray ring buffer: one MultiMesh of soft billboard puffs,
## top_level so emitted puffs stay put in world space as the ball flies on.
func _build_trail() -> void:
	_puff_pos.resize(_trail_count)
	_puff_vel.resize(_trail_count)
	_puff_age.resize(_trail_count)
	for i: int in _trail_count:
		_puff_age[i] = PUFF_LIFE
	_trail_mm = MultiMesh.new()
	_trail_mm.transform_format = MultiMesh.TRANSFORM_3D
	_trail_mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.material = _get_puff_material()
	_trail_mm.mesh = quad
	_trail_mm.instance_count = _trail_count
	for i: int in _trail_count:
		_trail_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3.ZERO))
		_trail_mm.set_instance_color(i, Color(1.0, 1.0, 1.0, 0.0))
	_trail = MultiMeshInstance3D.new()
	_trail.multimesh = _trail_mm
	_trail.top_level = true
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trail)


## Powder-fuzz corona: one soft additive billboard riding the collision
## center (NOT the stretched visual, so it never distorts) — reads as loose
## snow being shed in flight. Shared material/mesh across all snowballs.
func _build_fuzz() -> void:
	_fuzz = MeshInstance3D.new()
	_fuzz.mesh = _get_fuzz_mesh()
	_fuzz.material_override = _get_fuzz_material()
	_fuzz.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fuzz)


## Pre-builds the impact splat pair: a radial chunk fan (skipped on low
## particle quality) and a flattened irregular splat disc. Meshes are shared;
## the two materials are duplicated per snowball because their alpha
## animates during the splat.
func _build_impact_fx(with_chunks: bool) -> void:
	if with_chunks:
		_chunk_mat = _get_chunk_base_material().duplicate() as StandardMaterial3D
		_chunks = MeshInstance3D.new()
		_chunks.mesh = _get_chunk_mesh()
		_chunks.material_override = _chunk_mat
		_chunks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_chunks.visible = false
		_chunks.top_level = true
		add_child(_chunks)
	_splat_mat = _get_splat_base_material().duplicate() as StandardMaterial3D
	_splat = MeshInstance3D.new()
	_splat.mesh = _get_splat_mesh()
	_splat.material_override = _splat_mat
	_splat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_splat.visible = false
	_splat.top_level = true
	add_child(_splat)


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


static func _get_fuzz_mesh() -> QuadMesh:
	if _fuzz_mesh == null:
		_fuzz_mesh = QuadMesh.new()
		_fuzz_mesh.size = Vector2(1.15, 1.15)
	return _fuzz_mesh


static func _get_fuzz_material() -> StandardMaterial3D:
	if _fuzz_mat == null:
		_fuzz_mat = StandardMaterial3D.new()
		_fuzz_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_fuzz_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_fuzz_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_fuzz_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_fuzz_mat.billboard_keep_scale = true
		_fuzz_mat.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.55)
		_fuzz_mat.albedo_color = Color(0.95, 0.98, 1.0, 0.3)
	return _fuzz_mat


## Radial fan of chunky snow-clod triangles for the impact burst — shorter
## and wider than ItemBox's ice shards so it reads as soft lumps, not glass.
## Golden-angle sphere distribution, deterministic size variance.
static func _get_chunk_mesh() -> ArrayMesh:
	if _chunk_mesh != null:
		return _chunk_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 12
	for i: int in count:
		var g := float(i) * 2.39996
		var y := lerpf(-0.55, 0.85, (float(i) + 0.5) / float(count))
		var r := sqrt(maxf(1.0 - y * y, 0.0))
		var dir := Vector3(cos(g) * r, y, sin(g) * r)
		var ref_axis := Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT
		var tangent := dir.cross(ref_axis).normalized()
		var tip := 0.28 + 0.18 * fmod(float(i) * 0.618, 1.0)
		st.add_vertex(dir * 0.1 + tangent * 0.09)
		st.add_vertex(dir * 0.1 - tangent * 0.09)
		st.add_vertex(dir * tip)
	_chunk_mesh = st.commit()
	return _chunk_mesh


static func _get_chunk_base_material() -> StandardMaterial3D:
	if _chunk_base_mat == null:
		_chunk_base_mat = StandardMaterial3D.new()
		_chunk_base_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_chunk_base_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_chunk_base_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_chunk_base_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_chunk_base_mat.albedo_color = Color(0.95, 0.98, 1.0, 0.0)
		_chunk_base_mat.render_priority = 1
	return _chunk_base_mat


## Flattened irregular splat disc: a lumpy-edged fan in the XZ plane (radius
## wobbles per spoke) that scales up and fades where the ball hit — the cheap
## gl_compatibility stand-in for a decal.
static func _get_splat_mesh() -> ArrayMesh:
	if _splat_mesh != null:
		return _splat_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var spokes := 12
	for i: int in spokes:
		var a0 := TAU * float(i) / float(spokes)
		var a1 := TAU * float(i + 1) / float(spokes)
		var r0 := 0.55 + 0.22 * sin(a0 * 3.0) * sin(a0 * 5.0 + 1.7)
		var r1 := 0.55 + 0.22 * sin(a1 * 3.0) * sin(a1 * 5.0 + 1.7)
		var p0 := Vector3(cos(a0) * r0, 0.0, sin(a0) * r0)
		var p1 := Vector3(cos(a1) * r1, 0.0, sin(a1) * r1)
		# Upward-facing winding (viewed from +Y, clockwise front face).
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(p1)
		st.add_vertex(p0)
	st.generate_normals()
	_splat_mesh = st.commit()
	return _splat_mesh


static func _get_splat_base_material() -> StandardMaterial3D:
	if _splat_base_mat == null:
		_splat_base_mat = StandardMaterial3D.new()
		_splat_base_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_splat_base_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_splat_base_mat.albedo_color = Color(0.95, 0.97, 1.0, 0.0)
		_splat_base_mat.render_priority = 1
	return _splat_base_mat


func _physics_process(delta: float) -> void:
	if _popped:
		# Ball already splatted: freeze in place and let the spray trail
		# finish fading (no new puffs) until the splat tween frees the node.
		_update_trail(delta, false)
		return
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
	_update_visual(delta)
	_update_trail(delta, true)


## Motion stretch + travel-axis spin: orient the visual along the velocity,
## stretch it with speed (squash on the other axes preserves apparent
## volume), and roll it around the travel axis so the glitter cells and
## clump grain visibly rotate — a thrown ball, not a sliding sphere. The
## roll sits between the aim rotation and the scale, so the stretch stays
## locked to the flight direction. Visual child only — the Area3D and its
## collision sphere never rotate or scale.
func _update_visual(delta: float) -> void:
	var speed := _velocity.length()
	if speed < 0.1:
		return
	var dir := _velocity / speed
	var up_ref := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
	var stretch := clampf(1.0 + speed * 0.011, 1.0, 1.45)
	var squash := 1.0 / sqrt(stretch)
	_roll += delta * clampf(speed * 0.5, 4.0, 13.0)
	_visual.transform = Transform3D(
		Basis.looking_at(dir, up_ref) * Basis(Vector3(0.0, 0.0, 1.0), _roll)
			* Basis.from_scale(Vector3(squash, squash, stretch)),
		Vector3.ZERO)


## Spray trail: emit fixed-cadence puffs behind the ball into the ring
## buffer (only while emitting), then age every live puff — drifting
## backward/outward, sinking, expanding while fading (per-instance color
## alpha). All writes go into pre-sized packed arrays and the MultiMesh;
## nothing allocates per frame.
func _update_trail(delta: float, emitting: bool) -> void:
	if _trail_mm == null:
		return
	var speed := _velocity.length()
	_emit_accum += delta
	while _emit_accum >= EMIT_INTERVAL:
		_emit_accum -= EMIT_INTERVAL
		if emitting and speed > 4.0:
			_emit_puff(_velocity / speed)
	for i: int in _trail_count:
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
	_puff_idx = (_puff_idx + 1) % _trail_count
	_puff_age[i] = 0.0
	_puff_pos[i] = global_position - dir * 0.4 \
		+ Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 0.22
	_puff_vel[i] = -dir * (1.0 + randf() * 2.0) \
		+ Vector3((randf() - 0.5) * 1.6, randf() * 1.4, (randf() - 0.5) * 1.6)


func _on_body_entered(body: Node3D) -> void:
	if _popped or body == thrower:
		return
	if body is Racer:
		var racer := body as Racer
		racer.apply_stun("snowball")
		if racer.is_player or (thrower != null and thrower.is_player):
			AudioManager.play_sfx_3d("sfx_snowball_hit", global_position)
	_pop()


## Splat: hide the ball, fire the pooled course puff, then burst the snow
## chunk fan while the flattened splat disc fades on the ground below the
## impact. The node stays alive (collision off) just long enough for the
## splat + remaining spray puffs to finish, then frees itself. Headless (or
## when the impact meshes were skipped) falls back to an instant free.
func _pop() -> void:
	if _popped:
		return
	_popped = true
	var course := get_tree().get_first_node_in_group(&"course") as CourseBase
	if course != null:
		course.spawn_land_puff(global_position)
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	_visual.visible = false
	if _fuzz != null:
		_fuzz.visible = false
	if _splat == null:
		queue_free()
		return
	var tween := create_tween()
	tween.set_parallel(true)
	_splat.visible = true
	_splat.global_position = global_position + Vector3.DOWN * 0.25
	_splat.rotation.y = randf() * TAU
	_splat.scale = Vector3.ONE * 0.5
	_splat_mat.albedo_color = Color(0.95, 0.97, 1.0, 0.8)
	tween.tween_property(_splat, "scale", Vector3.ONE * 1.5, 0.55) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_splat_mat, "albedo_color:a", 0.0, 0.55)
	if _chunks != null:
		_chunks.visible = true
		_chunks.global_position = global_position
		_chunks.rotation.y = randf() * TAU
		_chunks.scale = Vector3.ONE * 0.5
		_chunk_mat.albedo_color = Color(0.95, 0.98, 1.0, 0.9)
		tween.tween_property(_chunks, "scale", Vector3.ONE * 2.0, 0.4) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(_chunks, "rotation:y", _chunks.rotation.y + 0.9, 0.4)
		tween.tween_property(_chunks, "position:y", _chunks.position.y - 0.35, 0.4) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(_chunk_mat, "albedo_color:a", 0.0, 0.4)
	tween.chain().tween_callback(queue_free)
