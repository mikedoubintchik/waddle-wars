class_name HazardSeal
extends Node3D
## Friendly seal that slides back and forth across the track. Bumping into
## it causes a comedic stumble (never a hard stun); the seal is unharmed
## and unbothered.
##
## Visual: a realistic procedural Weddell/harbor seal. The body is a single
## Catmull-Rom lathe (nose -> tail spindle, flattened belly contact, raised
## "banana" head) with swept-back front flippers and splayed, scalloped rear
## flipper fans baked into the SAME ArrayMesh/object space. Coat colors are
## per-vertex: counter-shaded silver belly -> dark dorsal with FastNoiseLite
## blotches and pale flecks (Weddell mottle). A wet-skin spatial shader adds
## low roughness, a cool fresnel rim, and a gentle traveling body undulation
## plus rear-flipper flutter (vertex bend fades to zero at the head so the
## separately-noded eyes / whiskers / nostrils never detach). All meshes and
## materials are built once and cached statically; per-frame work is node
## transforms only.
##
## Hazard readability (colorblind-safe: shape + pattern + brightness, never
## hue alone): dark spindle silhouette on snow, constant sweep motion, and a
## slowly spinning amber/black chevron ground ring. The ring is subtle by
## default and bright/unshaded when "accessibility/high_contrast_pickups" is
## on (same pattern as fish_pickup.gd), which also boosts the skin rim.

const COAT_DORSAL := Color(0.23, 0.24, 0.27)
const COAT_VENTRAL := Color(0.74, 0.74, 0.76)
const SPOT_DARK := Color(0.10, 0.10, 0.13)
const FLECK_PALE := Color(0.70, 0.71, 0.73)
const MUZZLE_PALE := Color(0.60, 0.59, 0.58)
const BODY_SEGS: int = 28
const EYE_L := Vector3(-0.19, 0.71, -1.16)
const EYE_R := Vector3(0.19, 0.71, -1.16)

## Wet-skin + undulation shader. gl_compatibility-safe: TIME, COLOR varying
## and fresnel only (no screen/depth reads, no instance uniforms). The bend
## phase derives from the world origin (MODEL_MATRIX) so multiple seals
## desync for free while sharing one material.
const SKIN_SHADER_CODE := """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform float rim_strength : hint_range(0.0, 2.0) = 0.3;

void vertex() {
	float ph = MODEL_MATRIX[3].x * 0.37 + MODEL_MATRIX[3].z * 0.31;
	// Galumph: a traveling spine hump + lazy lateral sway, zero at the head
	// (z < -0.35) so rigid face parts parented as separate nodes stay glued.
	float m = smoothstep(-0.35, 1.1, VERTEX.z);
	float hump = sin(TIME * 5.0 - VERTEX.z * 2.0 + ph);
	VERTEX.y += (hump * 0.5 + 0.5) * 0.034 * m;
	VERTEX.x += sin(TIME * 2.4 + VERTEX.z * 1.5 + ph) * 0.026 * m;
	// Rear flipper flutter (fans live at z > 1.05 in the shared mesh).
	float f = smoothstep(1.05, 1.5, VERTEX.z);
	VERTEX.x += sin(TIME * 5.0 + ph) * 0.05 * f;
	VERTEX.y += cos(TIME * 2.5 + ph) * 0.022 * f;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.24;
	SPECULAR = 0.55;
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	EMISSION = vec3(0.28, 0.36, 0.46) * fres * rim_strength;
}
"""

static var _seal_mesh: ArrayMesh = null
static var _whisker_mesh: ArrayMesh = null
static var _skin_shader: Shader = null
static var _skin_mat: ShaderMaterial = null
static var _skin_mat_contrast: ShaderMaterial = null
static var _whisker_mat: StandardMaterial3D = null
static var _stripe_tex: ImageTexture = null
static var _ring_mat: StandardMaterial3D = null
static var _ring_mat_contrast: StandardMaterial3D = null

var guide: PathGuide = null
var track_offset: float = 0.0
var sweep: float = 8.0  # lateral half-range
var speed: float = 4.0

var _phase: float = 0.0
var _area: Area3D
var _body_visual: Node3D
var _ring: MeshInstance3D
var _hit_cooldown: Dictionary = {}


func configure(p_guide: PathGuide, p_offset: float, p_sweep: float, p_speed: float = 4.0) -> void:
	guide = p_guide
	track_offset = p_offset
	sweep = p_sweep
	speed = p_speed


func _ready() -> void:
	add_to_group(&"hazards")
	_phase = randf() * TAU
	var high_contrast := bool(SettingsManager.get_setting("accessibility", "high_contrast_pickups"))
	_body_visual = Node3D.new()
	add_child(_body_visual)

	# Body + all four flippers: one mesh, one wet-skin material.
	var body := MeshInstance3D.new()
	body.mesh = _get_seal_mesh()
	body.material_override = _get_skin_material(high_contrast)
	# The undulation shader bends verts ~8 cm past the static AABB; pad the
	# cull bounds so the tail never pops at screen edges.
	body.extra_cull_margin = 0.25
	_body_visual.add_child(body)

	# Big dark glossy eyes with an emissive catchlight (penguin gleam pattern).
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.072
	eye_mesh.height = 0.144
	eye_mesh.radial_segments = 20
	eye_mesh.rings = 12
	var gleam_mesh := SphereMesh.new()
	gleam_mesh.radius = 0.015
	gleam_mesh.height = 0.03
	gleam_mesh.radial_segments = 8
	gleam_mesh.rings = 4
	var eye_mat := PenguinVisual.get_material(Color(0.07, 0.055, 0.05), 0.0, 0.06)
	var gleam_mat := PenguinVisual.get_material(Color(1.0, 1.0, 1.0), 0.0, 0.2, true)
	for side: float in [-1.0, 1.0]:
		var eye_pos := EYE_R if side > 0.0 else EYE_L
		var eye := MeshInstance3D.new()
		eye.mesh = eye_mesh
		eye.material_override = eye_mat
		eye.position = eye_pos
		eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_body_visual.add_child(eye)
		var gleam := MeshInstance3D.new()
		gleam.mesh = gleam_mesh
		gleam.material_override = gleam_mat
		gleam.position = eye_pos + Vector3(side * 0.018, 0.02, -0.058)
		gleam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_body_visual.add_child(gleam)

	# Nostrils: two dark comma slits angled into a "V" on the nose pad.
	var nostril_mesh := SphereMesh.new()
	nostril_mesh.radius = 0.02
	nostril_mesh.height = 0.04
	nostril_mesh.radial_segments = 8
	nostril_mesh.rings = 4
	var nostril_mat := PenguinVisual.get_material(Color(0.07, 0.06, 0.07), 0.0, 0.35)
	for side: float in [-1.0, 1.0]:
		var nostril := MeshInstance3D.new()
		nostril.mesh = nostril_mesh
		nostril.material_override = nostril_mat
		nostril.position = Vector3(side * 0.035, 0.662, -1.408)
		nostril.rotation.z = deg_to_rad(-18.0 * side)
		nostril.scale = Vector3(0.6, 1.3, 0.5)
		nostril.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_body_visual.add_child(nostril)

	# Whisker quills: one shared fan mesh for both mystacial pads.
	var whiskers := MeshInstance3D.new()
	whiskers.mesh = _get_whisker_mesh()
	whiskers.material_override = _get_whisker_material()
	whiskers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body_visual.add_child(whiskers)

	# Hazard ground ring: amber/black chevron stripes, spun slowly for a
	# motion cue. Subtle overlay normally; bright in high-contrast mode.
	_ring = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.82
	ring_mesh.outer_radius = 1.0
	ring_mesh.rings = 32
	ring_mesh.ring_segments = 6
	_ring.mesh = ring_mesh
	_ring.material_override = _get_ring_material(high_contrast)
	_ring.position.y = 0.05
	_ring.scale = Vector3(1.0, 0.25, 1.0)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)

	_area = Area3D.new()
	_area.collision_layer = GameConfig.LAYER_HAZARDS
	_area.collision_mask = GameConfig.LAYER_RACERS
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.3, 1.4, 2.6)
	shape.shape = box
	shape.position.y = 0.7
	_area.add_child(shape)
	add_child(_area)
	_area.body_entered.connect(_on_bump)


## --- Procedural mesh construction -------------------------------------------

## Catmull-Rom point on the segment p1..p2 (component-wise Vector3).
static func _cat3(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return (p1 * 2.0 + (p2 - p0) * t
		+ (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * t2
		+ (p1 * 3.0 - p0 - p2 * 3.0 + p3) * t3) * 0.5


## Samples a smooth curve through the control points (subdiv points per span).
static func _sample_profile3(ctrl: Array[Vector3], subdiv: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for i: int in ctrl.size() - 1:
		var p0 := ctrl[maxi(i - 1, 0)]
		var p1 := ctrl[i]
		var p2 := ctrl[i + 1]
		var p3 := ctrl[mini(i + 2, ctrl.size() - 1)]
		for s: int in subdiv:
			out.append(_cat3(p0, p1, p2, p3, float(s) / float(subdiv)))
	out.append(ctrl[ctrl.size() - 1])
	return out


## Stitches equal-length vertex rings into a smooth tube inside a shared
## SurfaceTool (same quad winding as PenguinVisual._grid_mesh; rings must
## advance +Z with each loop starting at the top and sweeping +X first).
static func _stitch(st: SurfaceTool, rings: Array[PackedVector3Array], colors: Array[PackedColorArray]) -> void:
	var n := rings[0].size()
	for j: int in rings.size() - 1:
		var ra := rings[j]
		var rb := rings[j + 1]
		var ca := colors[j]
		var cb := colors[j + 1]
		for i: int in n:
			var i2 := (i + 1) % n
			st.set_color(ca[i]); st.add_vertex(ra[i])
			st.set_color(ca[i2]); st.add_vertex(ra[i2])
			st.set_color(cb[i2]); st.add_vertex(rb[i2])
			st.set_color(ca[i]); st.add_vertex(ra[i])
			st.set_color(cb[i2]); st.add_vertex(rb[i2])
			st.set_color(cb[i]); st.add_vertex(rb[i])


## Coat color at a vertex. up_t: 0 belly -> 1 spine. Counter-shaded base,
## FastNoiseLite blotches (stretched along the body for the Weddell streak
## look) and pale flecks, pale muzzle, darkened eye surrounds, faint grain.
static func _coat(pos: Vector3, up_t: float, na: FastNoiseLite, nb: FastNoiseLite) -> Color:
	var col := COAT_VENTRAL.lerp(COAT_DORSAL, smoothstep(0.10, 0.62, up_t))
	var blotch := smoothstep(0.08, 0.40, na.get_noise_3d(pos.x * 2.3, pos.y * 2.8, pos.z * 1.15))
	col = col.lerp(SPOT_DARK, blotch * (0.18 + 0.52 * up_t))
	var fleck := smoothstep(0.24, 0.55, nb.get_noise_3d(pos.x * 4.0, pos.y * 4.6, pos.z * 2.1))
	col = col.lerp(FLECK_PALE, fleck * 0.30 * up_t)
	if pos.z < -1.02:
		var mz := smoothstep(1.02, 1.30, -pos.z)
		col = col.lerp(MUZZLE_PALE, mz * 0.55 * clampf(0.3 + up_t, 0.0, 1.0))
	var eye := EYE_R if pos.x >= 0.0 else EYE_L
	var d := pos.distance_to(eye)
	if d < 0.13:
		col = col.lerp(SPOT_DARK, (1.0 - d / 0.13) * 0.5)
	var g := 1.0 + sin(pos.x * 91.0 + pos.y * 53.0 + pos.z * 71.0) * 0.012
	return Color(clampf(col.r * g, 0.0, 1.0), clampf(col.g * g, 0.0, 1.0), clampf(col.b * g, 0.0, 1.0), 1.0)


## Full seal: body lathe + front flippers + rear fans in one cached surface.
static func _get_seal_mesh() -> ArrayMesh:
	if _seal_mesh != null:
		return _seal_mesh
	var na := FastNoiseLite.new()
	na.seed = 7
	na.noise_type = FastNoiseLite.TYPE_SIMPLEX
	na.frequency = 1.0
	na.fractal_octaves = 3
	var nb := FastNoiseLite.new()
	nb.seed = 19
	nb.noise_type = FastNoiseLite.TYPE_SIMPLEX
	nb.frequency = 1.0
	nb.fractal_octaves = 2
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)

	# Body spindle. Control points: (z, spine center y, radius). Head raised
	# in the alert "banana" rest pose; torso rings flatten where the belly
	# meets the ice. Cross-sections are wider than tall (1.06 / 0.88).
	var ctrl: Array[Vector3] = [
		Vector3(-1.44, 0.620, 0.020),  # nose tip
		Vector3(-1.36, 0.630, 0.095),  # nose pad
		Vector3(-1.20, 0.640, 0.165),  # muzzle
		Vector3(-1.00, 0.620, 0.300),  # head dome
		Vector3(-0.82, 0.580, 0.320),  # occiput
		Vector3(-0.58, 0.470, 0.335),  # neck
		Vector3(-0.22, 0.435, 0.480),  # chest
		Vector3(0.12, 0.487, 0.540),   # widest, forward of middle
		Vector3(0.55, 0.420, 0.460),   # hind belly
		Vector3(0.95, 0.285, 0.300),   # hip taper
		Vector3(1.22, 0.155, 0.140),   # tail base
		Vector3(1.34, 0.115, 0.045),   # tail stub
	]
	var profile := _sample_profile3(ctrl, 3)
	var rings: Array[PackedVector3Array] = []
	var colors: Array[PackedColorArray] = []
	var nose_ring := PackedVector3Array()
	var nose_col := PackedColorArray()
	for i: int in BODY_SEGS:
		nose_ring.append(Vector3(0.0, 0.615, -1.445))
		nose_col.append(MUZZLE_PALE.darkened(0.15))
	rings.append(nose_ring)
	colors.append(nose_col)
	for p: Vector3 in profile:
		var z := p.x
		var yc := p.y
		var r := maxf(p.z, 0.004)
		var ring := PackedVector3Array()
		var col := PackedColorArray()
		for i: int in BODY_SEGS:
			var ang := TAU * float(i) / float(BODY_SEGS)
			var pos := Vector3(sin(ang) * r * 1.06, yc + cos(ang) * r * 0.88, z)
			if z > -0.75 and z < 1.05:
				pos.y = maxf(pos.y, 0.018)  # belly contact patch on the ice
			ring.append(pos)
			col.append(_coat(pos, cos(ang) * 0.5 + 0.5, na, nb))
		rings.append(ring)
		colors.append(col)
	var tail_ring := PackedVector3Array()
	var tail_col := PackedColorArray()
	for i: int in BODY_SEGS:
		tail_ring.append(Vector3(0.0, 0.115, 1.35))
		tail_col.append(COAT_DORSAL)
	rings.append(tail_ring)
	colors.append(tail_col)
	_stitch(st, rings, colors)

	# Front flippers: short blades laid back along the lower flanks, digit
	# ridges baked as darker web valleys on the top face.
	for side: float in [-1.0, 1.0]:
		_stitch_front_flipper(st, side, na, nb)
	# Rear flippers: two splayed vertical-ish fans trailing behind the tail
	# with a scalloped, digit-rayed trailing edge (classic phocid silhouette).
	for side: float in [-1.0, 1.0]:
		_stitch_rear_fan(st, side, na, nb)

	st.generate_normals()
	st.index()
	_seal_mesh = st.commit()
	return _seal_mesh


static func _stitch_front_flipper(st: SurfaceTool, side: float, na: FastNoiseLite, nb: FastNoiseLite) -> void:
	var rows := 12
	var segs := 10
	var rings: Array[PackedVector3Array] = []
	var colors: Array[PackedColorArray] = []
	for j: int in rows + 1:
		var t := float(j) / float(rows)
		var cx := side * (0.40 + 0.20 * t + 0.03 * sin(t * PI))
		var cy := maxf(0.17 - 0.09 * t, 0.055)
		var cz := -0.18 + 0.88 * t
		var hw: float
		if t < 0.45:
			hw = lerpf(0.075, 0.115, t / 0.45)
		else:
			hw = lerpf(0.115, 0.028, pow((t - 0.45) / 0.55, 1.2))
		var hth := lerpf(0.034, 0.012, t)
		var ring := PackedVector3Array()
		var col := PackedColorArray()
		for i: int in segs:
			var ang := TAU * float(i) / float(segs)
			var pos := Vector3(cx + sin(ang) * hw, cy + cos(ang) * hth, cz)
			ring.append(pos)
			var c := _coat(pos, 0.75, na, nb).darkened(0.08)
			if cos(ang) > 0.0:  # digit ridges on the upper face only
				var ridge := 0.5 + 0.5 * cos(clampf(sin(ang), -1.0, 1.0) * 3.0 * PI)
				c = c.darkened(0.14 * (1.0 - ridge) * smoothstep(0.35, 0.9, t))
			col.append(c)
		rings.append(ring)
		colors.append(col)
	var tip := PackedVector3Array()
	var tip_col := PackedColorArray()
	var tip_pos := Vector3(side * 0.635, 0.06, 0.75)
	for i: int in segs:
		tip.append(tip_pos)
		tip_col.append(SPOT_DARK.lerp(COAT_DORSAL, 0.4))
	rings.append(tip)
	colors.append(tip_col)
	_stitch(st, rings, colors)


static func _stitch_rear_fan(st: SurfaceTool, side: float, na: FastNoiseLite, nb: FastNoiseLite) -> void:
	var rows := 12
	var segs := 10
	# Fan plane: mostly vertical, tilted outward. d_t = Z x d_w keeps the
	# (width, thickness, +Z advance) frame right-handed so winding matches.
	var d_w := Vector3(0.42 * side, 0.91, 0.0).normalized()
	var d_t := Vector3(0.0, 0.0, 1.0).cross(d_w)
	var rings: Array[PackedVector3Array] = []
	var colors: Array[PackedColorArray] = []
	var c_end := Vector3(side * 0.25, 0.17, 1.58)
	var hw_end := 0.035 + 0.155
	for j: int in rows + 1:
		var t := float(j) / float(rows)
		var c := Vector3(side * (0.05 + 0.20 * t), 0.14 + 0.03 * t, 1.18 + 0.40 * t)
		var hw := 0.035 + 0.155 * pow(t, 0.9)
		var hth := lerpf(0.020, 0.010, t)
		var ring := PackedVector3Array()
		var col := PackedColorArray()
		for i: int in segs:
			var ang := TAU * float(i) / float(segs)
			var pos := c + d_w * (sin(ang) * hw) + d_t * (cos(ang) * hth)
			ring.append(pos)
			var ray := 0.5 + 0.5 * cos(clampf(sin(ang), -1.0, 1.0) * 4.0 * PI)
			col.append(_coat(pos, 0.85, na, nb).darkened(0.10 + (1.0 - ray) * 0.18 * t))
		rings.append(ring)
		colors.append(col)
	# Scalloped trailing edge: digits extend past the web between them.
	var edge := PackedVector3Array()
	var edge_col := PackedColorArray()
	for i: int in segs:
		var ang := TAU * float(i) / float(segs)
		var u := clampf(sin(ang), -1.0, 1.0)
		var ray := 0.5 + 0.5 * cos(u * 4.0 * PI)
		var pos := c_end + d_w * (u * hw_end * 0.98) + d_t * (cos(ang) * 0.003) \
			+ Vector3(0.0, 0.0, 0.055 * ray)
		edge.append(pos)
		edge_col.append(SPOT_DARK.lerp(COAT_DORSAL, 0.35))
	rings.append(edge)
	colors.append(edge_col)
	_stitch(st, rings, colors)


## Whisker quills: five tapered three-sided cones per mystacial pad, fanning
## out-down-back from the muzzle sides. One mesh for both sides.
static func _get_whisker_mesh() -> ArrayMesh:
	if _whisker_mesh != null:
		return _whisker_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side: float in [-1.0, 1.0]:
		for k: int in 5:
			var kf := float(k)
			var base := Vector3(
				side * (0.104 + 0.005 * kf),
				0.598 + 0.014 * (kf - 2.0) * 0.5,
				-1.275 - 0.012 * kf)
			var dir := Vector3(
				side * (0.58 + 0.10 * kf),
				0.16 - 0.09 * kf,
				-0.30 + 0.11 * kf).normalized()
			var tip := base + dir * (0.30 - 0.014 * kf)
			var e1 := dir.cross(Vector3.UP).normalized()
			var e2 := dir.cross(e1).normalized()
			for i: int in 3:
				var a0 := TAU * float(i) / 3.0
				var a1 := TAU * float(i + 1) / 3.0
				var b0 := base + (e1 * cos(a0) + e2 * sin(a0)) * 0.0055
				var b1 := base + (e1 * cos(a1) + e2 * sin(a1)) * 0.0055
				st.add_vertex(b0)
				st.add_vertex(b1)
				st.add_vertex(tip)
	st.generate_normals()
	_whisker_mesh = st.commit()
	return _whisker_mesh


static func _get_whisker_material() -> StandardMaterial3D:
	if _whisker_mat == null:
		_whisker_mat = StandardMaterial3D.new()
		_whisker_mat.albedo_color = Color(0.87, 0.86, 0.82)
		_whisker_mat.roughness = 0.5
		_whisker_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _whisker_mat


static func _get_skin_material(high_contrast: bool) -> ShaderMaterial:
	if _skin_shader == null:
		_skin_shader = Shader.new()
		_skin_shader.code = SKIN_SHADER_CODE
	if high_contrast:
		if _skin_mat_contrast == null:
			_skin_mat_contrast = ShaderMaterial.new()
			_skin_mat_contrast.shader = _skin_shader
			_skin_mat_contrast.set_shader_parameter("rim_strength", 0.9)
		return _skin_mat_contrast
	if _skin_mat == null:
		_skin_mat = ShaderMaterial.new()
		_skin_mat.shader = _skin_shader
		_skin_mat.set_shader_parameter("rim_strength", 0.3)
	return _skin_mat


## Amber/black chevron stripe texture for the hazard ring: high luminance
## contrast between stripes so the pattern reads for every color vision.
static func _get_stripe_tex() -> ImageTexture:
	if _stripe_tex != null:
		return _stripe_tex
	var img := Image.create(128, 16, false, Image.FORMAT_RGB8)
	var amber := Color(1.0, 0.58, 0.02)
	var dark := Color(0.08, 0.07, 0.06)
	for y: int in 16:
		for x: int in 128:
			var ph := (float(x) / 128.0 + float(y) / 16.0 * 0.06) * 14.0
			img.set_pixel(x, y, amber if int(floor(ph)) % 2 == 0 else dark)
	_stripe_tex = ImageTexture.create_from_image(img)
	return _stripe_tex


static func _get_ring_material(high_contrast: bool) -> StandardMaterial3D:
	if high_contrast:
		if _ring_mat_contrast == null:
			_ring_mat_contrast = StandardMaterial3D.new()
			_ring_mat_contrast.albedo_color = Color(1.0, 1.0, 1.0, 0.92)
			_ring_mat_contrast.albedo_texture = _get_stripe_tex()
			_ring_mat_contrast.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_ring_mat_contrast.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		return _ring_mat_contrast
	if _ring_mat == null:
		_ring_mat = StandardMaterial3D.new()
		_ring_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.30)
		_ring_mat.albedo_texture = _get_stripe_tex()
		_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _ring_mat


func _physics_process(delta: float) -> void:
	if guide == null:
		return
	_phase += delta * speed / maxf(sweep, 1.0)
	var lateral := sin(_phase) * sweep
	global_position = guide.point_at(track_offset, lateral, 0.0)
	# Face the direction of travel, belly-sliding style, with a happy wobble.
	var moving_right := cos(_phase) > 0.0
	var xform := guide.transform_at(track_offset)
	var face_dir := xform.basis.x * (1.0 if moving_right else -1.0)
	if face_dir.length_squared() > 0.01:
		look_at(global_position + face_dir, Vector3.UP)
	# Node-level life on top of the shader undulation: gentle roll + nose bob.
	_body_visual.rotation.z = sin(_phase * 8.0) * 0.05
	_body_visual.rotation.x = sin(_phase * 3.7) * 0.025
	# Spinning chevron ring: motion cue that marks the hazard footprint.
	_ring.rotate_y(delta * 0.8)


func _on_bump(body: Node3D) -> void:
	if not body is Racer:
		return
	var racer := body as Racer
	var now := Time.get_ticks_msec()
	if int(_hit_cooldown.get(racer.racer_key, 0)) > now:
		return
	_hit_cooldown[racer.racer_key] = now + 2500
	racer.receive_shove_from_position(global_position)
	AudioManager.play_sfx_3d("sfx_stumble", global_position, 0.85)
	# The seal barks happily, unharmed.
	AudioManager.play_sfx_3d("sfx_chirp", global_position, 0.6, -4.0)
