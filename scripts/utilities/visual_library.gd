class_name VisualLibrary
extends RefCounted
## Shared visual asset factory: cached shader materials and cheap low-poly
## helper meshes used by courses, props, and environment dressing.
## All materials/meshes are cached by variant key — call freely, no per-call
## allocation after first use. Everything is procedural (no texture files)
## and mobile-cheap (Forward Mobile / Metal friendly).

const SNOW_SHADER: Shader = preload("res://assets/shaders/snow.gdshader")
const ICE_SHADER: Shader = preload("res://assets/shaders/ice.gdshader")
const WATER_SHADER: Shader = preload("res://assets/shaders/water.gdshader")
const AURORA_SHADER: Shader = preload("res://assets/shaders/aurora.gdshader")
const SPARKLE_SHADER: Shader = preload("res://assets/shaders/sparkle_pickup.gdshader")
const TERRAIN_SHADER: Shader = preload("res://assets/shaders/terrain.gdshader")

static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}
static var _textures: Dictionary = {}
static var _shapes: Dictionary = {}
static var _detail_level_cache: float = -1.0


## Shader micro-detail level derived from the display quality preset, read
## once per session: low = 0.0, medium = 0.5, high = 1.0. Headless runs get
## 0.0 (nothing renders; keeps compiled variants cheapest). Shaders skip all
## detail additions entirely when this is 0.
static func shader_detail_level() -> float:
	if _detail_level_cache >= 0.0:
		return _detail_level_cache
	if GameConfig.is_headless():
		_detail_level_cache = 0.0
		return _detail_level_cache
	match String(SettingsManager.get_setting("display", "quality_preset")):
		"low":
			_detail_level_cache = 0.0
		"medium":
			_detail_level_cache = 0.5
		_:
			_detail_level_cache = 1.0
	return _detail_level_cache


static func _resolve_detail(detail: float) -> float:
	return detail if detail >= 0.0 else shader_detail_level()


## Drops the cached quality-derived values so the next query re-reads the
## (possibly changed) preset. Called by SettingsManager whenever
## display/quality_preset changes — user edit or the web auto-governor.
static func reset_quality_cache() -> void:
	_detail_level_cache = -1.0


## Decorative-dressing cull distance multiplier per quality preset.
## 0.0 = never cull (the "high" contract: zero visual regression on desktop).
static func dressing_range_scale() -> float:
	if GameConfig.is_headless():
		return 0.0
	match String(SettingsManager.get_setting("display", "quality_preset")):
		"low":
			return 0.7
		"medium":
			return 1.0
		_:
			# Chrome reaches WebGL2 through ANGLE, where per-draw-call driver
			# overhead — not shading — is the wall the frame budget hits. The
			# high preset keeps its look but drops the far field there: 1.3 is
			# a gentler cut than the medium preset already ships (1.0), and the
			# skyline dressing opts in at 900-1200 m base, past the camera's
			# 900 m far plane, so only track-side clutter is ever affected.
			return 1.3 if GameConfig.is_web_chrome() else 0.0


## Applies VisibilityRange distance culling with a self-fade to decorative
## geometry. No-op on the high preset (and headless), so desktop visuals are
## untouched; on medium/low, dressing beyond base_distance (scaled per preset)
## dither-fades out and stops costing vertex/raster work on phones.
static func apply_dressing_range(gi: GeometryInstance3D, base_distance: float = 200.0) -> void:
	var scale := dressing_range_scale()
	if scale <= 0.0:
		return
	gi.visibility_range_end = base_distance * scale
	gi.visibility_range_end_margin = base_distance * scale * 0.15
	gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


## --- Shader materials --------------------------------------------------------

## Snow with procedural detail + view-dependent sparkle. sparkle 0..~1.
## detail < 0 (default) = auto from the quality preset; 0..1 forces a level.
## groom > 0 marks a groomed racing surface (corduroy along the direction of
## travel plus a packed shoulder at each edge). Off-track snow leaves it at 0,
## and the difference between the two is what makes a course readable on a
## white-on-white day course.
static func snow_material(tint: Color, sparkle: float = 0.55, detail: float = -1.0,
		groom: float = 0.0) -> ShaderMaterial:
	var d := _resolve_detail(detail)
	var key := "snow_%s_%.2f_%.2f_%.2f" % [tint.to_html(false), sparkle, d, groom]
	if _materials.has(key):
		return _materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = SNOW_SHADER
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("shadow_tint", Color(tint.r * 0.82, tint.g * 0.88, tint.b * 1.0))
	mat.set_shader_parameter("sparkle_strength", sparkle)
	mat.set_shader_parameter("detail_level", d)
	mat.set_shader_parameter("groom_strength", groom)
	_materials[key] = mat
	return mat


## Ice with fresnel rim + fake interior depth. clarity 0..1 (1 = clear/deep).
## detail < 0 (default) = auto from the quality preset; 0..1 forces a level.
static func ice_material(tint: Color, clarity: float = 0.7, detail: float = -1.0) -> ShaderMaterial:
	var d := _resolve_detail(detail)
	var key := "ice_%s_%.2f_%.2f" % [tint.to_html(false), clarity, d]
	if _materials.has(key):
		return _materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = ICE_SHADER
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("deep_tint", Color(tint.r * 0.25, tint.g * 0.45, tint.b * 0.62))
	mat.set_shader_parameter("clarity", clarity)
	mat.set_shader_parameter("roughness_base", lerpf(0.4, 0.06, clarity))
	# Cloudy (low-clarity) ice hides its interior: fade the parallax depth
	# patches out, or they read as dark blobs on pale frosted runs.
	mat.set_shader_parameter("depth_strength", lerpf(0.08, 0.3, clarity))
	mat.set_shader_parameter("detail_level", d)
	_materials[key] = mat
	return mat


## Animated water. Foam: paint mesh vertex COLOR.r toward 0.0 near shores
## (meshes without vertex colors get crest foam only). Track channels suit the
## defaults; for huge ocean planes pass a lower wave_scale (e.g. 0.06).
## detail < 0 (default) = auto from the quality preset; 0..1 forces a level.
static func water_material(deep: Color, shallow: Color, wave_height: float = 0.18, wave_scale: float = 0.35, detail: float = -1.0) -> ShaderMaterial:
	var d := _resolve_detail(detail)
	var key := "water_%s_%s_%.2f_%.3f_%.2f" % [deep.to_html(false), shallow.to_html(false), wave_height, wave_scale, d]
	if _materials.has(key):
		return _materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = WATER_SHADER
	mat.set_shader_parameter("deep_color", deep)
	mat.set_shader_parameter("shallow_color", shallow)
	mat.set_shader_parameter("wave_height", wave_height)
	mat.set_shader_parameter("wave_scale", wave_scale)
	mat.set_shader_parameter("detail_level", d)
	_materials[key] = mat
	return mat


## Additive scrolling aurora curtain for ribbon/plane meshes.
## detail < 0 (default) = auto from the quality preset; 0..1 forces a level.
static func aurora_material(detail: float = -1.0) -> ShaderMaterial:
	var d := _resolve_detail(detail)
	var key := "aurora_%.2f" % d
	if _materials.has(key):
		return _materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = AURORA_SHADER
	mat.set_shader_parameter("detail_level", d)
	_materials[key] = mat
	return mat


## Pulsing pickup glow (fish, item boxes, collectibles).
static func sparkle_material(base: Color, glow: Color) -> ShaderMaterial:
	var key := "sparkle_%s_%s" % [base.to_html(false), glow.to_html(false)]
	if _materials.has(key):
		return _materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = SPARKLE_SHADER
	mat.set_shader_parameter("base_color", base)
	mat.set_shader_parameter("glow_color", glow)
	_materials[key] = mat
	return mat


## Matte rock; multiplies baked per-face vertex colors (snow caps, shading)
## into the base tint. Meshes without vertex colors render plain base.
## Optional roughness/metallic replace the ".duplicate() then tweak" pattern:
## every (base, roughness, metallic) combination is cached and shared, so
## identical-looking surfaces never spawn extra material instances.
static func rock_material(base: Color, roughness: float = 0.95, metallic: float = 0.0) -> StandardMaterial3D:
	var key := "rock_%s_%.2f_%.2f" % [base.to_html(false), roughness, metallic]
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = base
	mat.roughness = roughness
	mat.metallic = metallic
	mat.vertex_color_use_as_albedo = true
	_materials[key] = mat
	return mat


## Rock / cliff / massif surface with real internal value structure and its own
## aerial-perspective ramp. Use this instead of rock_material() for anything
## that is TERRAIN — anything the player reads as landform rather than as a prop.
##
## Why it exists: rock_material() is a StandardMaterial3D, so every face of a
## form wears one albedo and one roughness. On a white course under a white key
## light that is indistinguishable from an untextured polygon, and at distance
## the engine fog carries it to the sky colour, which is how the horizon turned
## into a single pale mass. terrain.gdshader adds world-Y strata, a wall/ledge
## value split, a slope-gated snow catch, and a distance ramp toward a haze tone
## that stays DARKER than the sky (fog alone cannot do that without also
## flattening the near track).
##
## structure 0..1 scales the whole internal-detail block (0 skips it entirely).
## haze 0..1 scales the aerial-perspective ramp (0 skips it). Vertex colors
## still multiply into the tint, exactly like rock_material, so every mesh that
## bakes per-face colour keeps working.
static func terrain_material(tint: Color, structure: float = 1.0, haze: float = 0.0,
		roughness: float = 0.92) -> ShaderMaterial:
	var key := "terrain_%s_%.2f_%.2f_%.2f" % [tint.to_html(false), structure, haze, roughness]
	if _materials.has(key):
		return _materials[key]
	var mat := ShaderMaterial.new()
	mat.shader = TERRAIN_SHADER
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("structure", structure)
	mat.set_shader_parameter("haze_strength", haze)
	mat.set_shader_parameter("roughness_value", roughness)
	_materials[key] = mat
	return mat


## Soft contact shadow laid flat on the ground under a prop. gl_compatibility
## has no SSAO, so the ambient occlusion that makes an object look like it is ON
## the ground has to be geometry: without it, correctly seated rocks, crystals
## and dressing all read as hovering. One shared unshaded alpha quad material
## plus contact_patch_mesh() means a whole course's contact shadows cost one
## MultiMesh draw call.
##
## Deliberately blue-grey rather than black: the shadow of a rock on sunlit snow
## is filled by blue sky bounce, and a neutral grey blob is the giveaway.
static func contact_shadow_material(strength: float = 0.42) -> StandardMaterial3D:
	var key := "contact_%.2f" % strength
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.40, 0.58, strength)
	mat.albedo_texture = soft_radial_texture(48, 0.95)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Depth writes off: these lie a few centimetres above the surface and must
	# never punch a hole in anything drawn after them.
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[key] = mat
	return mat


## Unit ground-facing quad (1 m across, +Y normal, origin at its centre) for
## contact_shadow_material. Scale it per instance at the MultiMesh transform.
static func contact_patch_mesh() -> PlaneMesh:
	var key := "contact_patch"
	if _meshes.has(key):
		return _meshes[key]
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(1.0, 1.0)
	mesh.subdivide_width = 0
	mesh.subdivide_depth = 0
	_meshes[key] = mesh
	return mesh


## Cached parameter-tweaked copy of a cached library shader material. Replaces
## the "library_material().duplicate() then set params" pattern that minted a
## unique material (and a first-sight WebGL program state) per call site — the
## same base + same overrides now always return ONE shared instance.
## base must itself be a cached library material (stable instance id).
static func shader_variant(base: ShaderMaterial, overrides: Dictionary) -> ShaderMaterial:
	var param_keys: Array = overrides.keys()
	param_keys.sort()
	var key := "variant_%d" % base.get_instance_id()
	for param: Variant in param_keys:
		key += "_%s=%s" % [param, overrides[param]]
	if _materials.has(key):
		return _materials[key]
	var mat := base.duplicate() as ShaderMaterial
	for param: Variant in param_keys:
		mat.set_shader_parameter(param, overrides[param])
	_materials[key] = mat
	return mat


## Cached emissive prop material (checkpoint posts, glow markers).
static func emissive_material(albedo: Color, emission: Color, energy: float = 1.0, roughness: float = 1.0) -> StandardMaterial3D:
	var key := "emissive_%s_%s_%.2f_%.2f" % [albedo.to_html(false), emission.to_html(false), energy, roughness]
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	mat.roughness = roughness
	mat.emission_enabled = true
	mat.emission = emission
	mat.emission_energy_multiplier = energy
	_materials[key] = mat
	return mat


## Cached unshaded soft-radial billboard material (cloud puffs, snow flakes,
## glows). keep_scale = true lets one shared unit mesh be sized per instance
## via node scale instead of a unique mesh per puff.
static func billboard_puff_material(color: Color, tex_size: int = 32, inner_alpha: float = 0.9, keep_scale: bool = false) -> StandardMaterial3D:
	var key := "puff_%s_%d_%.2f_%d" % [color.to_html(), tex_size, inner_alpha, int(keep_scale)]
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.albedo_texture = soft_radial_texture(tex_size, inner_alpha)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = keep_scale
	_materials[key] = mat
	return mat


## Upgraded track floor material per surface type. Snow/ice surfaces get the
## shader treatments; everything else falls back to the classic flat material.
static func track_surface_material(surface: SurfacesDB.Surface) -> Material:
	match surface:
		SurfacesDB.Surface.PACKED_SNOW:
			return snow_material(Color(0.93, 0.96, 1.0), 0.55, -1.0, 1.0)
		SurfacesDB.Surface.DEEP_SNOW:
			# Deep snow is the punishing surface, so it is groomed only faintly:
			# it should still read as part of the course, but visibly softer and
			# less travelled than the packed racing line.
			return snow_material(Color(0.99, 0.99, 1.0), 0.25, -1.0, 0.45)
		SurfacesDB.Surface.ICE_SMOOTH:
			return ice_material(Color(0.48, 0.74, 0.97), 0.85)
		SurfacesDB.Surface.ICE_ROUGH:
			return ice_material(Color(0.58, 0.76, 0.92), 0.3)
		_:
			return TrackBuilder.surface_material(surface)


## Soft radial white blob texture (snowflakes, cloud puffs, glows).
static func soft_radial_texture(size: int = 32, inner_alpha: float = 0.9) -> GradientTexture2D:
	var key := "radial_%d_%.2f" % [size, inner_alpha]
	if _textures.has(key):
		return _textures[key]
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, inner_alpha))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = size
	tex.height = size
	_textures[key] = tex
	return tex


## --- Low-poly helper meshes --------------------------------------------------
## All meshes are unit-scale (about 1m tall) with baked per-face vertex colors;
## scale/tint at the MeshInstance3D. Pair with rock_material()/ice-tinted
## rock_material() so vertex colors show.

## Cluster of three faceted ice shards, pale tips, deeper blue base.
static func ice_crystal_mesh() -> ArrayMesh:
	var key := "ice_crystal"
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shards: Array[Dictionary] = [
		{"pos": Vector3.ZERO, "h": 1.0, "r": 0.16, "lean": Vector3.ZERO},
		{"pos": Vector3(0.16, 0.0, 0.07), "h": 0.55, "r": 0.1, "lean": Vector3(0.14, 0.0, 0.05)},
		{"pos": Vector3(-0.13, 0.0, -0.1), "h": 0.42, "r": 0.08, "lean": Vector3(-0.1, 0.0, -0.07)},
	]
	var base_col := Color(0.62, 0.82, 0.95)
	var tip_col := Color(0.92, 0.98, 1.0)
	# Contact grounding, baked. gl_compatibility gives no SSAO, so the darkening
	# where a shard meets the ground has to live in the vertex colours or the
	# cluster reads as hovering however correctly it is seated.
	var foot_col := Color(0.3, 0.44, 0.62)
	for shard: Dictionary in shards:
		var origin: Vector3 = shard["pos"]
		var height := float(shard["h"])
		var radius := float(shard["r"])
		var apex: Vector3 = origin + Vector3.UP * height + (shard["lean"] as Vector3)
		var sides := 5
		for i: int in sides:
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			var p0 := origin + Vector3(cos(a0) * radius, 0.0, sin(a0) * radius)
			var p1 := origin + Vector3(cos(a1) * radius, 0.0, sin(a1) * radius)
			var face_col := base_col.lerp(tip_col, 0.35 + 0.5 * absf(sin(a0 * 2.0)))
			# Per-vertex ramp instead of one flat colour per facet: a faceted
			# shard that is one tone from foot to tip is the low-poly-placeholder
			# tell, and the gradient costs nothing.
			var root := foot_col.lerp(face_col, 0.18)
			_tri3(st, p0, p1, apex, root, root, face_col)
	st.generate_normals()
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh


## Soft low-poly snow mound (flat-shaded dome), faint blue toward the base.
static func snow_drift_mesh() -> ArrayMesh:
	var key := "snow_drift"
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 8
	var radii: Array[float] = [1.0, 0.82, 0.48]
	var heights: Array[float] = [0.0, 0.32, 0.58]
	# Ring 0 is the contact ring: a drift that keeps its crest value all the way
	# down to the snow it sits on has no shadow under it, and with no SSAO on
	# gl_compatibility that is the whole reason dressing reads as hovering.
	var colors: Array[Color] = [
		Color(0.6, 0.69, 0.88),
		Color(0.92, 0.95, 1.0),
		Color(1.0, 1.0, 1.0),
	]
	var apex := Vector3(0.0, 0.75, 0.0)
	for ring: int in radii.size() - 1:
		for i: int in sides:
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			var b0 := Vector3(cos(a0) * radii[ring], heights[ring], sin(a0) * radii[ring])
			var b1 := Vector3(cos(a1) * radii[ring], heights[ring], sin(a1) * radii[ring])
			var t0 := Vector3(cos(a0) * radii[ring + 1], heights[ring + 1], sin(a0) * radii[ring + 1])
			var t1 := Vector3(cos(a1) * radii[ring + 1], heights[ring + 1], sin(a1) * radii[ring + 1])
			var lo := colors[ring]
			var hi := colors[ring + 1]
			_tri3(st, b0, t1, t0, lo, hi, hi)
			_tri3(st, b0, b1, t1, lo, lo, hi)
	for i: int in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var last := radii.size() - 1
		var p0 := Vector3(cos(a0) * radii[last], heights[last], sin(a0) * radii[last])
		var p1 := Vector3(cos(a1) * radii[last], heights[last], sin(a1) * radii[last])
		_tri(st, p0, p1, apex, colors[last])
	st.generate_normals()
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh


## Seeded low-poly iceberg silhouette (irregular base ring, mid shelf, peak).
## Unit-ish scale: ~1m radius, 1.2-1.9m tall. Deterministic per seed.
static func berg_mesh(seed: int) -> ArrayMesh:
	var key := "berg_%d" % seed
	if _meshes.has(key):
		return _meshes[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 7
	var base_pts: Array[Vector3] = []
	var mid_pts: Array[Vector3] = []
	var mid_y := rng.randf_range(0.45, 0.7)
	for i: int in sides:
		var angle := TAU * float(i) / float(sides)
		var base_r := rng.randf_range(0.7, 1.25)
		var mid_r := base_r * rng.randf_range(0.5, 0.8)
		base_pts.append(Vector3(cos(angle) * base_r, 0.0, sin(angle) * base_r))
		mid_pts.append(Vector3(cos(angle) * mid_r, mid_y + rng.randf_range(-0.08, 0.12), sin(angle) * mid_r))
	var peak := Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(1.2, 1.9), rng.randf_range(-0.2, 0.2))
	var wall_col := Color(0.68, 0.82, 0.94)
	var top_col := Color(0.96, 0.98, 1.0)
	# Waterline / contact foot: bergs and ice blocks are darkest where they meet
	# the surface they sit in, and that band is what plants them.
	var foot_col := Color(0.26, 0.42, 0.6)
	for i: int in sides:
		var j := (i + 1) % sides
		var shade := rng.randf_range(0.85, 1.0)
		var side_col := Color(wall_col.r * shade, wall_col.g * shade, wall_col.b)
		var root_col := foot_col.lerp(side_col, 0.25)
		_tri3(st, base_pts[i], mid_pts[j], mid_pts[i], root_col, side_col, side_col)
		_tri3(st, base_pts[i], base_pts[j], mid_pts[j], root_col, root_col, side_col)
		var cap_shade := rng.randf_range(0.92, 1.0)
		var cap_col := Color(top_col.r * cap_shade, top_col.g * cap_shade, top_col.b)
		_tri3(st, mid_pts[i], mid_pts[j], peak, side_col.lerp(cap_col, 0.5),
			side_col.lerp(cap_col, 0.5), cap_col)
	st.generate_normals()
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	_tri3(st, a, b, c, color, color, color)


## Triangle with a colour per corner. Flat facets shaded with ONE tone are the
## low-poly-placeholder look; a per-vertex ramp (dark at the contact foot,
## bright at the crest) costs the same vertex data and gives every form real
## internal value.
static func _tri3(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ca: Color, cb: Color, cc: Color) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)


## --- Cache registry (shader warm-up) -----------------------------------------
## The dedup pass above collapsed a course build down to a dozen or so shared
## materials, but each of those still costs a linked GPU program the first time
## something wearing it is drawn — milliseconds under Chrome's ANGLE -> Metal
## path. ShaderWarmup walks these registries behind the loading overlay and
## draws one sub-pixel instance per entry so nothing links mid-race.

## One-triangle mesh carrying the full attribute set (normal, tangent, UV,
## vertex color) the shipped meshes use, so a warm-up draw links the same
## program a real surface will ask for.
##
## The model itself is 0.08 mm across, which matters for one case the warm-up
## node's instance scale cannot cover: a billboard material without
## billboard_keep_scale throws the model matrix's scale away and draws at mesh
## size. Under a pixel either way.
static func warmup_mesh() -> ArrayMesh:
	var key := "warmup_probe"
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners: Array[Vector3] = [
		Vector3(-0.00004, -0.00004, 0.0), Vector3(0.00004, -0.00004, 0.0), Vector3(0.0, 0.00004, 0.0),
	]
	var uvs: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.5, 1.0)]
	for i: int in corners.size():
		st.set_color(Color(1.0, 1.0, 1.0, 1.0))
		st.set_normal(Vector3.BACK)
		st.set_tangent(Plane(Vector3.RIGHT, 1.0))
		st.set_uv(uvs[i])
		st.add_vertex(corners[i])
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh


## Every material minted through this library so far, in creation order.
## Read repeatedly by the warm-up: props and racers spawn deferred, so the
## registry keeps growing for a frame or two after a course finishes building.
static func cached_materials() -> Array[Material]:
	var out: Array[Material] = []
	for value: Variant in _materials.values():
		var mat := value as Material
		if mat != null:
			out.append(mat)
	return out


## Every helper mesh minted through this library so far. SurfaceTool meshes
## have no GPU buffers until something draws them, so the warm-up pass touches
## these too — a berg that only comes into frustum halfway down a course would
## otherwise upload its vertex data on the frame it appears.
static func cached_meshes() -> Array[Mesh]:
	var out: Array[Mesh] = []
	for value: Variant in _meshes.values():
		var mesh := value as Mesh
		if mesh != null:
			out.append(mesh)
	return out


## Registry sizes (materials, meshes). Both dictionaries only ever grow, so
## the warm-up compares this between passes and skips re-listing them when
## nothing new has been minted.
static func cache_sizes() -> Vector2i:
	return Vector2i(_materials.size(), _meshes.size())
