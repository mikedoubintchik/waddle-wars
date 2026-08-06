class_name ItemBox
extends Area3D
## Floating power-up box: a chamfered translucent ice cube that slowly
## tumbles and bobs, with a glowing '?' glyph floating inside. Grants a
## position-weighted random item, then respawns after a short delay
## (simple pooling: hide + reactivate).
##
## Rendering notes: the shell is a beveled ArrayMesh driven by an inline
## spatial shader — fresnel-depth tinting, two parallax-offset internal
## caustic layers (fake refraction, no screen reads: gl_compatibility safe),
## suspended bubble sparkles, an orbiting internal glint star, per-facet
## twinkle, and prismatic dispersion in the rim band + chamfer bevels.
## Mesh, shell material, glyph material/texture, halo, shard, flash, ring
## and mote resources are built once and shared by every box; only burst
## materials are per-instance (their alpha animates).
##
## Accessibility: the box reads through SHAPE (cube + '?' glyph) +
## PATTERN (glyph, facets) + BRIGHTNESS (rim, ground halo) — never hue
## alone. "accessibility/high_contrast_pickups" swaps the shell and halo
## to the same bright-gold emissive language as FishPickup.

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

## Ice shell shader: fresnel depth tint + two internal caustic layers sampled
## at different parallax depths along the object-space view ray (glints swim
## through the interior as the camera or cube moves), suspended bubble
## sparkles at the deeper parallax layer, an orbiting internal glint star,
## per-facet twinkle keyed off the flat-shaded chamfer normals, and a slow
## prismatic hue sweep in the fresnel rim plus a stronger dispersion band
## confined to the chamfer bevels (cut-prism edges). All math, no textures —
## WebGL2/mobile safe.
const BOX_SHADER_CODE := """shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(0.5, 0.78, 1.0, 0.42);
uniform vec4 deep_color : source_color = vec4(0.10, 0.28, 0.55, 1.0);
uniform float rim_power = 2.4;
uniform float prism_strength = 0.55;
uniform float glint_strength = 0.5;

varying vec3 v_obj;
varying vec3 v_view_obj;
varying vec3 v_nrm_obj;

float hash31(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void vertex() {
	v_obj = VERTEX;
	v_nrm_obj = NORMAL;
	vec3 cam_obj = (inverse(MODEL_MATRIX) * vec4(INV_VIEW_MATRIX[3].xyz, 1.0)).xyz;
	v_view_obj = cam_obj - VERTEX;
}

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, rim_power);
	vec3 vdir = normalize(v_view_obj);
	// Two internal caustic layers at different parallax depths: offsetting
	// the sample point along the view ray makes the bands drift through the
	// interior with camera motion — reads as refraction without screen reads.
	vec3 p1 = v_obj - vdir * 0.16;
	vec3 p2 = v_obj - vdir * 0.34;
	float band1 = smoothstep(0.90, 0.995, sin(dot(p1, vec3(9.0, 7.0, 5.0)) + TIME * 1.6));
	float band2 = smoothstep(0.92, 0.997, sin(dot(p2, vec3(6.0, 11.0, 8.0)) - TIME * 1.2));
	float inner = band1 + band2 * 0.7;
	// Facet twinkle: each flat chamfer facet fires briefly on its own phase
	// (slow — well under flashing-safety thresholds).
	float fh = hash31(floor(v_nrm_obj * 3.0 + 5.0));
	float twinkle = smoothstep(0.965, 1.0, sin(TIME * 2.3 + fh * 6.28318)) * ndv;
	// Orbiting internal glint star: a bright refracted highlight that drifts
	// through the volume on its own slow path — a light source caught in the
	// ice, revealed as the camera or cube lines up with it.
	vec3 gdir = normalize(vec3(sin(TIME * 0.7), sin(TIME * 0.53 + 2.1), cos(TIME * 0.61)));
	float star = pow(clamp(dot(vdir, gdir), 0.0, 1.0), 42.0);
	// Suspended bubble sparkles: sparse cells sampled at the deep parallax
	// layer so the specks sit visibly INSIDE the ice, each brightening on
	// its own slow phase (well under flashing-safety thresholds).
	vec3 bc = floor(p2 * 7.0 + 3.0);
	float bh = hash31(bc);
	float bubbles = step(0.80, bh) * smoothstep(0.86, 1.0, sin(TIME * 1.1 + bh * 37.7));
	// Bevel mask: chamfer facets have off-axis normals; the strongest
	// dispersion is confined there so edges read as cut prisms.
	float bevel = smoothstep(0.1, 0.35,
			1.0 - max(max(abs(v_nrm_obj.x), abs(v_nrm_obj.y)), abs(v_nrm_obj.z)));
	// Prismatic dispersion along the fresnel band: hue sweeps with grazing
	// angle and time, like light splitting through a cut edge. Decorative
	// only — shape/brightness carry the pickup read.
	vec3 prism = 0.5 + 0.5 * cos(6.28318 * (fres * 1.35 + vec3(0.0, 0.33, 0.66)) + TIME * 0.4);
	ALBEDO = mix(deep_color.rgb, base_color.rgb, ndv);
	ROUGHNESS = 0.05;
	METALLIC = 0.08;
	SPECULAR = 0.75;
	ALPHA = clamp(base_color.a + fres * 0.5 + inner * 0.22 + twinkle * 0.3
			+ star * 0.2 + bubbles * 0.1, 0.0, 0.96);
	EMISSION = prism * (fres * prism_strength + bevel * 0.5)
			+ vec3(0.85, 0.95, 1.0) * inner * glint_strength
			+ vec3(1.0) * twinkle * 0.6
			+ vec3(0.9, 0.97, 1.0) * star * 0.8
			+ vec3(0.8, 0.92, 1.0) * bubbles * 0.35;
}
"""

## Cube half-size and corner bevel width for the chamfered shell mesh.
const CUBE_HALF: float = 0.5
const CUBE_BEVEL: float = 0.16

static var _cube_mesh: ArrayMesh = null
static var _box_mat: ShaderMaterial = null
static var _box_mat_contrast: StandardMaterial3D = null
static var _glyph_mesh: QuadMesh = null
static var _glyph_mat: StandardMaterial3D = null
static var _burst_base_mat: StandardMaterial3D = null
static var _shard_mesh: ArrayMesh = null
static var _shard_base_mat: StandardMaterial3D = null
static var _flash_mesh: QuadMesh = null
static var _flash_base_mat: StandardMaterial3D = null
static var _halo_mesh: TorusMesh = null
static var _halo_mat: StandardMaterial3D = null
static var _halo_mat_contrast: StandardMaterial3D = null
static var _ring_burst_base_mat: StandardMaterial3D = null
static var _mote_base_mat: StandardMaterial3D = null

var _visual: MeshInstance3D = null
var _glyph: MeshInstance3D = null
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
var _active: bool = true
var _spin_time: float = 0.0
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

	# Ground halo: soft unshaded ring under the box (attached to self so it
	# does not tumble). Brightness anchor for the pickup lane — same visual
	# language as FishPickup's underlay ring, gold in high-contrast mode.
	_halo = MeshInstance3D.new()
	_halo.mesh = _get_halo_mesh()
	_halo.material_override = _get_halo_material()
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.position.y = -0.6
	add_child(_halo)

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

	# Pickup burst trio: expanding shell flash + radial ice shards + central
	# billboard flash. Materials are duplicated per box (alpha animates
	# independently); every node is created once here and reused on each
	# pickup — no per-pickup allocation beyond the one-shot tween.
	_burst_mat = _get_burst_base_material().duplicate() as StandardMaterial3D
	_burst = MeshInstance3D.new()
	_burst.mesh = _get_cube_mesh()
	_burst.material_override = _burst_mat
	_burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_burst.visible = false
	add_child(_burst)

	_shard_mat = _get_shard_base_material().duplicate() as StandardMaterial3D
	_shards = MeshInstance3D.new()
	_shards.mesh = _get_shard_mesh()
	_shards.material_override = _shard_mat
	_shards.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shards.visible = false
	add_child(_shards)

	_flash_mat = _get_flash_base_material().duplicate() as StandardMaterial3D
	_flash = MeshInstance3D.new()
	_flash.mesh = _get_flash_mesh()
	_flash.material_override = _flash_mat
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	add_child(_flash)

	# Two more pre-built burst layers: a cool horizontal shockwave ring
	# (reuses the halo torus) and a warm gold mote fan counter-rotating
	# against the ice shards — brightness + pattern variety so the burst
	# reads without relying on hue.
	_ring_mat = _get_ring_burst_base_material().duplicate() as StandardMaterial3D
	_ring = MeshInstance3D.new()
	_ring.mesh = _get_halo_mesh()
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)

	_mote_mat = _get_mote_base_material().duplicate() as StandardMaterial3D
	_motes = MeshInstance3D.new()
	_motes.mesh = _get_shard_mesh()
	_motes.material_override = _mote_mat
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_motes.visible = false
	add_child(_motes)

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
	_halo.visible = false
	_play_burst()
	set_deferred("monitoring", false)
	var timer := get_tree().create_timer(RESPAWN_TIME)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(self):
			_active = true
			_visual.visible = true
			_halo.visible = true
			set_deferred("monitoring", true))


## One-shot pickup burst: additive shell flash + spinning radial ice shards
## + a quick central billboard flash + expanding shockwave ring + warm gold
## mote fan counter-rotating against the shards. All nodes pre-built in
## _ready; only the one-shot tween is allocated per pickup.
func _play_burst() -> void:
	if _burst == null:
		return
	if _burst_tween != null and _burst_tween.is_valid():
		_burst_tween.kill()
	_burst.visible = true
	_burst.scale = Vector3.ONE * 1.05
	_burst_mat.albedo_color = Color(0.75, 0.92, 1.0, 0.85)
	_shards.visible = true
	_shards.scale = Vector3.ONE * 0.9
	_shards.rotation.y = _rng.randf_range(0.0, TAU)
	_shard_mat.albedo_color = Color(0.85, 0.95, 1.0, 0.9)
	_flash.visible = true
	_flash.scale = Vector3.ONE * 0.6
	_flash_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
	_ring.visible = true
	_ring.scale = Vector3.ONE * 0.7
	_ring_mat.albedo_color = Color(0.7, 0.9, 1.0, 0.8)
	_motes.visible = true
	_motes.scale = Vector3.ONE * 0.45
	_motes.rotation.y = -_shards.rotation.y
	_mote_mat.albedo_color = Color(1.0, 0.85, 0.4, 0.85)
	_burst_tween = create_tween()
	_burst_tween.set_parallel(true)
	_burst_tween.tween_property(_burst, "scale", Vector3.ONE * 2.1, 0.32) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_burst_tween.tween_property(_burst_mat, "albedo_color:a", 0.0, 0.32)
	_burst_tween.tween_property(_shards, "scale", Vector3.ONE * 2.6, 0.42) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_burst_tween.tween_property(_shards, "rotation:y", _shards.rotation.y + 1.3, 0.42)
	_burst_tween.tween_property(_shard_mat, "albedo_color:a", 0.0, 0.42)
	_burst_tween.tween_property(_flash, "scale", Vector3.ONE * 2.3, 0.22) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_burst_tween.tween_property(_flash_mat, "albedo_color:a", 0.0, 0.22)
	_burst_tween.tween_property(_ring, "scale", Vector3.ONE * 3.1, 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_burst_tween.tween_property(_ring_mat, "albedo_color:a", 0.0, 0.45)
	_burst_tween.tween_property(_motes, "scale", Vector3.ONE * 1.8, 0.5) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_burst_tween.tween_property(_motes, "rotation:y", _motes.rotation.y - 1.7, 0.5)
	_burst_tween.tween_property(_mote_mat, "albedo_color:a", 0.0, 0.5)
	_burst_tween.chain().tween_callback(func() -> void:
		_burst.visible = false
		_shards.visible = false
		_flash.visible = false
		_ring.visible = false
		_motes.visible = false)


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


## Shell material: inline ice shader normally; bright-gold translucent
## emissive in high-contrast mode (same language as FishPickup) so the '?'
## glyph still reads through the shell.
static func _get_box_material() -> Material:
	var high_contrast := bool(SettingsManager.get_setting("accessibility", "high_contrast_pickups"))
	if high_contrast:
		if _box_mat_contrast == null:
			_box_mat_contrast = StandardMaterial3D.new()
			_box_mat_contrast.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_box_mat_contrast.albedo_color = Color(1.0, 0.85, 0.1, 0.62)
			_box_mat_contrast.emission_enabled = true
			_box_mat_contrast.emission = Color(1.0, 0.7, 0.05)
			_box_mat_contrast.emission_energy_multiplier = 1.4
		return _box_mat_contrast
	if _box_mat != null:
		return _box_mat
	var shader := Shader.new()
	shader.code = BOX_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_box_mat = mat
	return _box_mat


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


static func _get_halo_mesh() -> TorusMesh:
	if _halo_mesh == null:
		_halo_mesh = TorusMesh.new()
		_halo_mesh.inner_radius = 0.5
		_halo_mesh.outer_radius = 0.62
		_halo_mesh.rings = 24
		_halo_mesh.ring_segments = 6
	return _halo_mesh


static func _get_ring_burst_base_material() -> StandardMaterial3D:
	if _ring_burst_base_mat != null:
		return _ring_burst_base_mat
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.7, 0.9, 1.0, 0.0)
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
	mat.albedo_color = Color(1.0, 0.85, 0.4, 0.0)
	mat.render_priority = 1
	_mote_base_mat = mat
	return _mote_base_mat


static func _get_halo_material() -> StandardMaterial3D:
	var high_contrast := bool(SettingsManager.get_setting("accessibility", "high_contrast_pickups"))
	if high_contrast:
		if _halo_mat_contrast == null:
			_halo_mat_contrast = StandardMaterial3D.new()
			_halo_mat_contrast.albedo_color = Color(1.0, 0.85, 0.2, 0.55)
			_halo_mat_contrast.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_halo_mat_contrast.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		return _halo_mat_contrast
	if _halo_mat == null:
		_halo_mat = StandardMaterial3D.new()
		_halo_mat.albedo_color = Color(0.55, 0.9, 1.0, 0.3)
		_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _halo_mat
