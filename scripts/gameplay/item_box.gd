class_name ItemBox
extends Area3D
## Floating power-up box: a chamfered translucent ice cube that slowly
## tumbles and bobs, with a glowing '?' glyph floating inside. Grants a
## position-weighted random item, then respawns after a short delay
## (simple pooling: hide + reactivate).
##
## Rendering notes: the shell needs real alpha so the inner glyph reads
## through it, and the shared ice ShaderMaterial is opaque — so the shell
## uses a beveled ArrayMesh with a tuned translucent StandardMaterial3D
## (rim + soft emission gives the icy read). Mesh, shell material, and
## glyph material/texture are built once and shared by every box; only the
## pickup-burst material is per-instance (its alpha animates).

const RESPAWN_TIME: float = 3.5

## Warm '?' glyph with a baked soft halo + dark backing outline, so it glows
## gently without relying on bloom (same Image.load_svg_from_string
## technique as the HUD fish icon).
const GLYPH_SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<circle cx="32" cy="32" r="30" fill="#8fd8ff" opacity="0.14"/>
<circle cx="32" cy="32" r="21" fill="#aee4ff" opacity="0.18"/>
<path d="M21 24 C21 13 43 13 43 24 C43 31 32 31 32 37 L32 41" fill="none" stroke="#0e2036" stroke-width="13" stroke-linecap="round" opacity="0.4"/>
<circle cx="32" cy="52" r="7.4" fill="#0e2036" opacity="0.4"/>
<path d="M21 24 C21 13 43 13 43 24 C43 31 32 31 32 37 L32 41" fill="none" stroke="#ffe9a0" stroke-width="9" stroke-linecap="round"/>
<circle cx="32" cy="52" r="5.4" fill="#ffe9a0"/>
</svg>"""

## Cube half-size and corner bevel width for the chamfered shell mesh.
const CUBE_HALF: float = 0.5
const CUBE_BEVEL: float = 0.16

static var _cube_mesh: ArrayMesh = null
static var _box_mat: StandardMaterial3D = null
static var _glyph_mesh: QuadMesh = null
static var _glyph_mat: StandardMaterial3D = null
static var _burst_base_mat: StandardMaterial3D = null

var _visual: MeshInstance3D = null
var _glyph: MeshInstance3D = null
var _burst: MeshInstance3D = null
var _burst_mat: StandardMaterial3D = null
var _burst_tween: Tween = null
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

	# Ice shell.
	_visual = MeshInstance3D.new()
	_visual.mesh = _get_cube_mesh()
	_visual.material_override = _get_box_material()
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_visual)

	# Inner '?' glyph: billboard quad drawn before the shell (render_priority)
	# so the ice front face tints it — reads as floating inside the cube.
	# Skipped when the SVG module is unavailable (headless).
	var glyph_mat := _get_glyph_material()
	if glyph_mat != null:
		_glyph = MeshInstance3D.new()
		_glyph.mesh = _get_glyph_mesh()
		_glyph.material_override = glyph_mat
		_glyph.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_visual.add_child(_glyph)

	# Pickup burst: the same chamfered shell flashes additively and expands.
	# Material is duplicated per box (alpha animates independently); created
	# once here, reused on every pickup — no per-pickup allocation beyond
	# the one-shot tween.
	_burst_mat = _get_burst_base_material().duplicate() as StandardMaterial3D
	_burst = MeshInstance3D.new()
	_burst.mesh = _get_cube_mesh()
	_burst.material_override = _burst_mat
	_burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_burst.visible = false
	add_child(_burst)

	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_spin_time += delta
	# Slow two-axis tumble + gentle bob.
	_visual.rotation.y += delta * 0.9
	_visual.rotation.x += delta * 0.37
	_visual.position.y = sin(_spin_time * 2.0) * 0.12
	if _glyph != null:
		# Small independent float so the glyph drifts inside the ice.
		_glyph.position.y = sin(_spin_time * 2.6) * 0.05


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
	_play_burst()
	set_deferred("monitoring", false)
	var timer := get_tree().create_timer(RESPAWN_TIME)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(self):
			_active = true
			_visual.visible = true
			set_deferred("monitoring", true))


## One-shot expanding additive flash of the cube shell on pickup.
func _play_burst() -> void:
	if _burst == null:
		return
	if _burst_tween != null and _burst_tween.is_valid():
		_burst_tween.kill()
	_burst.visible = true
	_burst.scale = Vector3.ONE * 1.05
	_burst_mat.albedo_color = Color(0.75, 0.92, 1.0, 0.85)
	_burst_tween = create_tween()
	_burst_tween.set_parallel(true)
	_burst_tween.tween_property(_burst, "scale", Vector3.ONE * 2.1, 0.32) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_burst_tween.tween_property(_burst_mat, "albedo_color:a", 0.0, 0.32)
	_burst_tween.chain().tween_callback(func() -> void:
		_burst.visible = false)


## --- Shared visual resources (built once, shared by all boxes) -----------


## Chamfered cube: 6 inset faces + 12 edge bevels + 8 corner facets, flat
## shaded for a cut-gem ice read. Built with SurfaceTool once.
static func _get_cube_mesh() -> ArrayMesh:
	if _cube_mesh != null:
		return _cube_mesh
	var h := CUBE_HALF
	var inner := CUBE_HALF - CUBE_BEVEL
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 6 main faces (inset squares at each axis extreme).
	for axis: int in 3:
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		for s: float in [-1.0, 1.0]:
			var pts: Array[Vector3] = []
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				pts.append(_axes_vec(axis, s * h, u, corner.x * inner, v, corner.y * inner))
			_add_face(st, pts)
	# 12 edge bevel quads (one per pair of adjacent faces).
	for pair: Vector2i in [Vector2i(0, 1), Vector2i(1, 2), Vector2i(0, 2)]:
		var a := pair.x
		var b := pair.y
		var c := 3 - a - b
		for sa: float in [-1.0, 1.0]:
			for sb: float in [-1.0, 1.0]:
				var pts: Array[Vector3] = [
					_axes_vec(a, sa * h, b, sb * inner, c, -inner),
					_axes_vec(a, sa * h, b, sb * inner, c, inner),
					_axes_vec(a, sa * inner, b, sb * h, c, inner),
					_axes_vec(a, sa * inner, b, sb * h, c, -inner),
				]
				_add_face(st, pts)
	# 8 corner triangles.
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var pts: Array[Vector3] = [
					Vector3(sx * h, sy * inner, sz * inner),
					Vector3(sx * inner, sy * h, sz * inner),
					Vector3(sx * inner, sy * inner, sz * h),
				]
				_add_face(st, pts)
	st.generate_normals()
	_cube_mesh = st.commit()
	return _cube_mesh


static func _axes_vec(a: int, av: float, b: int, bv: float, c: int, cv: float) -> Vector3:
	var out := Vector3.ZERO
	out[a] = av
	out[b] = bv
	out[c] = cv
	return out


## Fan-triangulates a convex polygon, auto-orienting to Godot's clockwise
## front-face winding (viewed from outside the origin-centered solid).
static func _add_face(st: SurfaceTool, pts: Array[Vector3]) -> void:
	var centroid := Vector3.ZERO
	for p: Vector3 in pts:
		centroid += p
	centroid /= float(pts.size())
	var normal := (pts[1] - pts[0]).cross(pts[2] - pts[0])
	var ordered := pts
	if normal.dot(centroid) > 0.0:
		ordered = pts.duplicate()
		ordered.reverse()
	for i: int in range(1, ordered.size() - 1):
		st.add_vertex(ordered[0])
		st.add_vertex(ordered[i])
		st.add_vertex(ordered[i + 1])


static func _get_box_material() -> StandardMaterial3D:
	if _box_mat != null:
		return _box_mat
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.5, 0.78, 1.0, 0.5)
	mat.roughness = 0.06
	mat.metallic = 0.1
	mat.metallic_specular = 0.9
	mat.rim_enabled = true
	mat.rim = 0.9
	mat.rim_tint = 0.4
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.45, 0.85)
	mat.emission_energy_multiplier = 0.35
	_box_mat = mat
	return mat


static func _get_glyph_mesh() -> QuadMesh:
	if _glyph_mesh != null:
		return _glyph_mesh
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.55, 0.55)
	_glyph_mesh = mesh
	return _glyph_mesh


## Billboard glyph material; null when the SVG module is unavailable
## (headless), in which case the glyph node is simply skipped.
static func _get_glyph_material() -> StandardMaterial3D:
	if _glyph_mat != null:
		return _glyph_mat
	var tex := UITheme.make_icon(GLYPH_SVG, 2.0)
	if tex == null:
		return null
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = tex
	# Draw before the ice shell in the transparent pass so the shell's front
	# face blends over the glyph (glyph reads as inside the cube).
	mat.render_priority = -1
	_glyph_mat = mat
	return mat


static func _get_burst_base_material() -> StandardMaterial3D:
	if _burst_base_mat != null:
		return _burst_base_mat
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.75, 0.92, 1.0, 0.0)
	mat.render_priority = 1
	_burst_base_mat = mat
	return mat
