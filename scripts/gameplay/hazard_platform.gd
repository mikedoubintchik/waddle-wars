class_name HazardPlatform
extends AnimatableBody3D
## Moving / tilting ice platform. Base modes: "slide" (oscillates along an
## axis) and "tilt" (rocks around its travel axis). Courses layer optional
## compound motion on top via the configure() motion dictionary: a slow yaw
## sweep, a phase-offset fore-aft pitch wobble, a vertical heave bob, a
## "lurch" shaping that makes the platform dwell at its extremes then surge
## through the middle, a bank ("lean") into the travel direction, and seeded
## per-platform period variance so no two slabs in a row breathe in sync.
## Used for iceberg water hops.
##
## Fairness: platforms telegraph reversals — emissive edge strips along the
## moving edges burn dim cyan while cruising and flip to hot amber shortly
## before the wave reverses (the game's hazard warning hue), so players can
## read the lurch coming. Under reduced motion the strips stay steady dim.
## AnimatableBody3D + sync_to_physics=false is load-bearing: racer
## platform-carry logic tracks the frame delta of global_position manually.
##
## Visuals: the slab uses the shared glossy ice shader (voronoi crack plates,
## internal veins, glint facets) with the shader's frosted WHITE border
## enabled on the top face via baked UV2 — a ragged bright edge ring so the
## landing area and its edges read by BRIGHTNESS + PATTERN at any palette.
## The berg skirt below uses a deeper, cloudier ice. When
## "accessibility/high_contrast_pickups" is on, amber edge strips outline the
## walkable top. Collision shape matches platform_size exactly.

## Seconds of amber warning before the dominant wave reverses direction.
const TELEGRAPH_LEAD: float = 0.55

static var _slab_meshes: Dictionary = {}
static var _edge_mat: StandardMaterial3D = null

var platform_size: Vector3 = Vector3(9.0, 0.8, 9.0)
var move_axis: Vector3 = Vector3.RIGHT
var move_range: float = 4.0
var period: float = 5.0
var tilt_degrees: float = 0.0
var phase_offset: float = 0.0
## Compound motion (all optional; see configure()).
var tilt_freq: float = 1.2
var yaw_degrees: float = 0.0
var yaw_freq: float = 0.45
var pitch_degrees: float = 0.0
var pitch_freq: float = 0.8
var heave: float = 0.0
var heave_freq: float = 0.7
var lurch: float = 0.0
var lean_degrees: float = 0.0
var telegraph_enabled: bool = false

var _origin: Vector3
var _time: float = 0.0
var _yaw_phase: float = 0.0
var _pitch_phase: float = 0.0
var _heave_phase: float = 0.0
var _tele_strips: Array[MeshInstance3D] = []
var _tele_flash: bool = false
var _tele_hot: bool = false


## p_motion keys (all optional):
##   "yaw_deg"/"yaw_freq"     slow yaw sweep amplitude (deg) / rate vs period
##   "pitch_deg"/"pitch_freq" fore-aft wobble amplitude (deg) / rate vs period
##   "tilt_freq"              rocking rate vs period (default 1.2, the
##                            original tilt cadence)
##   "heave"/"heave_freq"     vertical bob amplitude (m) / rate vs period
##   "lurch"                  0..2: dwell at extremes, surge through middle
##   "lean_deg"               bank into the travel direction (slide mode)
##   "variance"/"seed"        seeded per-platform period jitter (fraction)
##                            plus randomized yaw/pitch/heave phases
##   "telegraph"              force the warning strips on/off (default: on
##                            whenever the platform slides or tilts)
func configure(p_size: Vector3, p_axis: Vector3, p_range: float, p_period: float, p_tilt: float = 0.0, p_phase: float = 0.0, p_motion: Dictionary = {}) -> void:
	platform_size = p_size
	move_axis = p_axis.normalized() if p_axis.length_squared() > 0.001 else Vector3.ZERO
	move_range = p_range
	period = maxf(p_period, 0.5)
	tilt_degrees = p_tilt
	phase_offset = p_phase
	tilt_freq = float(p_motion.get("tilt_freq", 1.2))
	yaw_degrees = float(p_motion.get("yaw_deg", 0.0))
	yaw_freq = float(p_motion.get("yaw_freq", 0.45))
	pitch_degrees = float(p_motion.get("pitch_deg", 0.0))
	pitch_freq = float(p_motion.get("pitch_freq", 0.8))
	heave = float(p_motion.get("heave", 0.0))
	heave_freq = float(p_motion.get("heave_freq", 0.7))
	lurch = clampf(float(p_motion.get("lurch", 0.0)), 0.0, 2.0)
	lean_degrees = float(p_motion.get("lean_deg", 0.0))
	telegraph_enabled = bool(p_motion.get("telegraph",
		(move_range > 0.0 and move_axis != Vector3.ZERO) or tilt_degrees > 0.0))
	# Seeded per-platform variance: deterministic (sim-reproducible) desync of
	# period and secondary phases, so a row of slabs never metronomes.
	var variance := float(p_motion.get("variance", 0.0))
	if variance > 0.0:
		var vrng := RandomNumberGenerator.new()
		vrng.seed = int(p_motion.get("seed", 0))
		period = maxf(period * (1.0 + vrng.randf_range(-variance, variance)), 0.5)
		_yaw_phase = vrng.randf() * TAU
		_pitch_phase = vrng.randf() * TAU
		_heave_phase = vrng.randf() * TAU


func _ready() -> void:
	sync_to_physics = false
	collision_layer = GameConfig.LAYER_WORLD
	collision_mask = 0
	set_meta("surface", SurfacesDB.Surface.ICE_ROUGH)
	_origin = global_position
	_time = phase_offset

	var visual := MeshInstance3D.new()
	visual.mesh = _get_slab_mesh(platform_size)
	visual.material_override = VisualLibrary.ice_material(Color(0.56, 0.77, 0.94), 0.6)
	add_child(visual)
	# Icy skirt under the platform so it reads as a floating berg: deeper,
	# cloudier ice than the polished top.
	var skirt := MeshInstance3D.new()
	var skirt_mesh := BoxMesh.new()
	skirt_mesh.size = Vector3(platform_size.x * 0.8, platform_size.y * 3.0, platform_size.z * 0.8)
	skirt.mesh = skirt_mesh
	skirt.material_override = VisualLibrary.ice_material(Color(0.45, 0.62, 0.8), 0.35)
	skirt.position.y = -platform_size.y * 1.6
	add_child(skirt)
	if not GameConfig.is_headless():
		if bool(SettingsManager.get_setting("accessibility", "high_contrast_pickups")):
			_add_edge_strips()
		if telegraph_enabled:
			_add_telegraph_strips()
			# Reduced motion: strips stay steady dim — no flashing, but the
			# moving edges keep their always-on marker band.
			_tele_flash = not UITheme.reduced_motion()

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = platform_size
	shape.shape = box
	add_child(shape)


## Amber edge strips outlining the walkable top (high-contrast mode): the
## drop-off edge reads by a hue-independent bright band, matching the game's
## hazard warning language.
func _add_edge_strips() -> void:
	var hy := platform_size.y * 0.5
	for side: int in 2:
		var s := -1.0 if side == 0 else 1.0
		var strip_x := MeshInstance3D.new()
		var mesh_x := BoxMesh.new()
		mesh_x.size = Vector3(platform_size.x * 0.96, 0.06, 0.18)
		strip_x.mesh = mesh_x
		strip_x.material_override = _get_edge_material()
		strip_x.position = Vector3(0.0, hy + 0.04, s * (platform_size.z * 0.5 - 0.15))
		strip_x.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(strip_x)
		var strip_z := MeshInstance3D.new()
		var mesh_z := BoxMesh.new()
		mesh_z.size = Vector3(0.18, 0.06, platform_size.z * 0.96)
		strip_z.mesh = mesh_z
		strip_z.material_override = _get_edge_material()
		strip_z.position = Vector3(s * (platform_size.x * 0.5 - 0.15), hy + 0.04, 0.0)
		strip_z.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(strip_z)


## Telegraph strips along the two MOVING edges (the ±X edges lead both the
## slide travel and the tilt rise/fall): dim cyan while cruising, hot amber
## shortly before the wave reverses. Set inboard of the high-contrast amber
## outline so the two bands never overlap.
func _add_telegraph_strips() -> void:
	var hy := platform_size.y * 0.5
	for side: int in 2:
		var s := -1.0 if side == 0 else 1.0
		var strip := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.24, 0.07, platform_size.z * 0.88)
		strip.mesh = mesh
		strip.material_override = _telegraph_dim_material()
		strip.position = Vector3(s * (platform_size.x * 0.5 - 0.55), hy + 0.045, 0.0)
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(strip)
		_tele_strips.append(strip)


func _physics_process(delta: float) -> void:
	_time += delta
	var ph := _time * TAU / period
	var sliding := move_axis != Vector3.ZERO and move_range > 0.0
	if sliding or heave > 0.0:
		var pos := _origin
		if sliding:
			pos += move_axis * _shaped_wave(ph, lurch) * move_range
		if heave > 0.0:
			pos.y += sin(ph * heave_freq + _heave_phase) * heave
		global_position = pos
	if tilt_degrees > 0.0 or lean_degrees > 0.0 or pitch_degrees > 0.0 or yaw_degrees > 0.0:
		var roll := 0.0
		if tilt_degrees > 0.0:
			roll = deg_to_rad(tilt_degrees) * _shaped_wave(ph * tilt_freq, lurch)
		if lean_degrees > 0.0 and sliding:
			# Bank INTO the travel: the leading edge dips while the slab surges
			# (cos(ph) tracks the travel speed), a readable "wave riding" cue.
			roll -= deg_to_rad(lean_degrees) * cos(ph)
		var pitch := 0.0
		if pitch_degrees > 0.0:
			pitch = deg_to_rad(pitch_degrees) * sin(ph * pitch_freq + _pitch_phase)
		var yaw := 0.0
		if yaw_degrees > 0.0:
			yaw = deg_to_rad(yaw_degrees) * sin(ph * yaw_freq + _yaw_phase)
		rotation = Vector3(pitch, yaw, roll)
	if _tele_flash:
		_update_telegraph(ph)


## Sine shaped to DWELL at its extremes and LURCH through the middle: iterated
## smoothstep flattens the curve near ±1 (a readable pause at each end of the
## sweep) and steepens the zero crossing (the surge). lurch 0 = plain sine,
## 1 = one smoothstep, 2 = two. Extremes stay at the same phases as sin(ph),
## so telegraph timing is shaping-independent.
static func _shaped_wave(ph: float, p_lurch: float) -> float:
	var s := sin(ph)
	if p_lurch <= 0.0:
		return s
	var u := s * 0.5 + 0.5
	var eased := u * u * (3.0 - 2.0 * u)
	u = lerpf(u, eased, minf(p_lurch, 1.0))
	if p_lurch > 1.0:
		eased = u * u * (3.0 - 2.0 * u)
		u = lerpf(u, eased, p_lurch - 1.0)
	return u * 2.0 - 1.0


## Flip the telegraph strips hot when the dominant wave (translation when the
## platform slides, tilt otherwise) is within TELEGRAPH_LEAD seconds of its
## next extreme — the moment the motion reverses. Material writes only on
## state flips (two cached shared materials, ~2 swaps per cycle).
func _update_telegraph(ph: float) -> void:
	var rate := TAU / period
	var dom_ph := ph
	if not (move_axis != Vector3.ZERO and move_range > 0.0):
		dom_ph = ph * tilt_freq
		rate *= tilt_freq
	var to_extreme := (PI - fposmod(dom_ph - PI * 0.5, PI)) / rate
	var hot := to_extreme < TELEGRAPH_LEAD
	if hot == _tele_hot:
		return
	_tele_hot = hot
	var mat := _telegraph_hot_material() if hot else _telegraph_dim_material()
	for strip: MeshInstance3D in _tele_strips:
		strip.material_override = mat


## --- Shared visual resources ----------------------------------------------


## Slab mesh with baked UV2 frost flags: subdivided box whose TOP vertices
## carry UV2 = (edge_proximity, 1.0) so the shared ice shader draws its
## ragged frosted border as a ring around the platform lip (the shader gates
## the frost path on UV2.y > 0.5; sides/bottom stay clear glass). Cached per
## size; exact same outer dimensions as the collider box.
static func _get_slab_mesh(size: Vector3) -> ArrayMesh:
	var key := "%.2f_%.2f_%.2f" % [size.x, size.y, size.z]
	if _slab_meshes.has(key):
		return _slab_meshes[key]
	var box := BoxMesh.new()
	box.size = size
	box.subdivide_width = 6
	box.subdivide_depth = 6
	var arrays: Array = box.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv2 := PackedVector2Array()
	uv2.resize(verts.size())
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	for i: int in verts.size():
		if normals[i].y > 0.9:
			# Remap edge proximity so frost hugs the outer band only.
			var e := maxf(absf(verts[i].x) / hx, absf(verts[i].z) / hz)
			uv2[i] = Vector2(clampf((e - 0.5) * 2.0, 0.0, 1.0), 1.0)
		else:
			uv2[i] = Vector2.ZERO
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_slab_meshes[key] = mesh
	return mesh


static func _get_edge_material() -> StandardMaterial3D:
	if _edge_mat == null:
		_edge_mat = StandardMaterial3D.new()
		_edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_edge_mat.albedo_color = Color(1.0, 0.72, 0.12)
	return _edge_mat


## Cruise state: cool cyan, below the glow threshold — visible marker band,
## no bloom. Cached/shared via VisualLibrary.
static func _telegraph_dim_material() -> StandardMaterial3D:
	return VisualLibrary.emissive_material(
		Color(0.5, 0.8, 1.0), Color(0.35, 0.7, 1.0), 0.6, 0.4)


## Warning state: hot amber (the game's hazard hue) over the 1.1 glow
## threshold, so an imminent reversal blooms from race distance.
static func _telegraph_hot_material() -> StandardMaterial3D:
	return VisualLibrary.emissive_material(
		Color(1.0, 0.72, 0.12), Color(1.0, 0.6, 0.15), 2.0, 0.4)
