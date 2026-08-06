class_name FishPickup
extends Area3D
## Collectible fish: score pickup, cosmetic currency, magnet-attractable.
## Visual: stylized forage fish built once as a shared ArrayMesh — a lathed
## fusiform body (blunt head, deep mid-body, narrow caudal peduncle,
## laterally compressed), oversized forked tail + dorsal/pectoral/anal fins,
## glossy eye dots. The body and fin surfaces use inline spatial shaders:
## countershaded iridescence with gill/operculum detail, plus a
## world-position-phased vertex swim stroke so every fish waves its tail on
## its own beat (no instance uniforms — gl_compatibility safe). Fins add a
## faster membrane flutter on top of the shared sway, masked to zero at the
## fin roots so they stay seamlessly attached to the flank. Collecting pops
## the fish inside a warm flash and a fan of water droplets that arcs out and
## rains down (shared mesh/base material; skipped on low particle quality).
##
## Readability: a silver fish on sunlit snow is the hardest pickup in the game
## to see, so three things carry it — a much darker dorsal (which is the
## surface the chase camera actually looks at), low METALLIC so the body stops
## mirroring a white sky, and hot-orange fins plus a warm ground disc for
## chroma contrast where value contrast runs out. The whole visual is drawn at
## VISUAL_SCALE, and the mesh was retuned to about a third of its old triangle
## count to pay for it.

## Body shader: countershading (deep slate-teal dorsal -> warm mirror-silver
## belly), scale shimmer bands + sparse view-angle scale glitter, wavy lateral
## line, dorsal speckle rows, gill arc + bright operculum plate, pearlescent
## belly sheen, thin-film iridescence in the fresnel band, and a tail-weighted
## lateral swim sway in the vertex stage phased by world position. Pure math,
## no textures.
##
## Readability: the chase camera looks DOWN on a fish lying on white snow, so
## the dorsal surface is nearly all the player sees — it is therefore pushed
## much darker than a real forage fish, and METALLIC is kept low. The old 0.75
## metallic was the real reason fish vanished on the bright courses: with no
## reflection probes in gl_compatibility a metallic surface just mirrors the
## sky, so a silver fish over snow under a white sky rendered as white-on-white.
const BODY_SHADER_CODE := """shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

varying vec3 v_obj;

float hash31(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void vertex() {
	v_obj = VERTEX;
	// Swim stroke: lateral sway grows toward the tail; phase comes from the
	// instance's world origin so a school never wiggles in lockstep.
	float phase = MODEL_MATRIX[3].x * 1.7 + MODEL_MATRIX[3].z * 2.3;
	VERTEX.z += sin(TIME * 5.0 + phase + VERTEX.x * 6.0) * 0.045 * smoothstep(-0.16, 0.34, VERTEX.x);
}

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 2.5);
	// Countershading: deep slate-teal dorsal -> warm mirror-silver belly. The
	// hard value step between them is the silhouette cue at race distance.
	float topness = smoothstep(-0.11, 0.09, v_obj.y);
	vec3 dorsal = vec3(0.09, 0.155, 0.245);
	vec3 silver = vec3(0.96, 0.95, 0.91);
	vec3 col = mix(silver, dorsal, topness);
	// Scale shimmer: fine cross-bands modulate tone and roughness so the
	// specular response breaks up like overlapping scales.
	float scales = sin(v_obj.x * 72.0) * sin(v_obj.y * 55.0 + v_obj.z * 38.0);
	col += vec3(scales * 0.025);
	// Warm amber flank blush along the mid-line: a chroma cue that separates
	// the fish from blue-white snow even where the values happen to match.
	float flank = (1.0 - smoothstep(0.0, 0.085, abs(v_obj.y + 0.01)))
			* smoothstep(-0.24, -0.12, v_obj.x);
	col = mix(col, vec3(1.0, 0.56, 0.20), flank * 0.62);
	// Gill arc + bright operculum plate on the cheek (head region only).
	float head = 1.0 - smoothstep(-0.07, -0.02, v_obj.x);
	float gill = (1.0 - smoothstep(0.007, 0.020, abs(length(vec2(v_obj.x + 0.17, v_obj.y * 0.8)) - 0.10))) * head;
	col *= 1.0 - gill * 0.45;
	float cheek = (1.0 - smoothstep(0.045, 0.105, length(vec2(v_obj.x + 0.20, v_obj.y * 0.9)))) * head;
	col = mix(col, silver, cheek * 0.45);
	// Lateral line: the wavy sensory seam along the mid-flank, operculum to
	// caudal peduncle — the single strongest "real fish" silhouette cue.
	float mid = smoothstep(-0.20, -0.12, v_obj.x) * (1.0 - smoothstep(0.14, 0.20, v_obj.x));
	float lat = (1.0 - smoothstep(0.004, 0.014, abs(v_obj.y - 0.008 - sin(v_obj.x * 14.0) * 0.006))) * mid;
	col *= 1.0 - lat * 0.30;
	// Dorsal speckle rows (sardine-style), upper flank only.
	float spots = step(0.87, hash31(floor(vec3(v_obj.x * 46.0, v_obj.y * 30.0, sign(v_obj.z))))) * smoothstep(0.02, 0.06, v_obj.y);
	col = mix(col, dorsal * 0.55, spots * 0.6);
	// Pearlescent belly sheen: warm mother-of-pearl in the grazing band on
	// the silver underside.
	col = mix(col, vec3(0.99, 0.93, 0.90), (1.0 - topness) * fres * 0.25);
	// Scale glitter: sparse per-cell micro-facets flash as the view sweeps
	// (crawls with motion, never strobes in place).
	vec3 cell = floor(v_obj * vec3(90.0, 70.0, 70.0));
	vec3 jitter = vec3(hash31(cell), hash31(cell + 1.3), hash31(cell + 2.6)) - 0.5;
	vec3 gn = normalize(NORMAL + jitter * 0.9);
	float glitter = pow(clamp(dot(gn, VIEW), 0.0, 1.0), 48.0) * step(0.5, hash31(cell + 4.1));
	// Thin-film iridescence riding the fresnel band (herring-flank rainbow).
	vec3 irid = 0.5 + 0.5 * cos(6.28318 * (fres * 1.1 + v_obj.x * 2.0 + vec3(0.0, 0.33, 0.66)));
	ALBEDO = col;
	METALLIC = 0.18;
	ROUGHNESS = clamp(0.26 + scales * 0.06, 0.05, 1.0);
	SPECULAR = 0.85;
	// Warm rim light: a bright edge that holds the silhouette against a dark
	// night sky, where the dark dorsal alone would disappear.
	EMISSION = irid * fres * 0.22 + col * 0.22
			+ vec3(1.0, 0.86, 0.62) * fres * 0.5
			+ vec3(1.0) * glitter * 0.4;
}
"""

## Fin shader: same swim sway (phase-matched to the body so the tail wags
## with the peduncle) plus a faster, finer membrane flutter that fades to
## zero at the fin roots, warm membrane with fin-ray striations + rim glow.
const FIN_SHADER_CODE := """shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

varying vec3 v_obj;

void vertex() {
	v_obj = VERTEX;
	float phase = MODEL_MATRIX[3].x * 1.7 + MODEL_MATRIX[3].z * 2.3;
	VERTEX.z += sin(TIME * 5.0 + phase + VERTEX.x * 6.0) * 0.045 * smoothstep(-0.16, 0.34, VERTEX.x);
	// Membrane flutter: higher-frequency ripple riding the shared sway.
	// Masked by distance outside an ellipsoid approximating the body, so
	// fin roots (which must track the flank exactly) never move relative
	// to the body surface while the free edges flutter.
	float away = smoothstep(0.14, 0.26, length(vec3(v_obj.x * 0.55, v_obj.y, v_obj.z * 1.6)));
	VERTEX.z += sin(TIME * 9.0 + phase * 1.7 + (v_obj.x - v_obj.y) * 22.0) * 0.016 * away;
}

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 2.0);
	// Fin-ray striations: brighter membrane between darker structural rays.
	// Hot orange is the fish's loudest signal against blue-white snow, so the
	// fins carry more of the read than they would on a real forage fish.
	float rays = 0.5 + 0.5 * sin(v_obj.y * 46.0 + v_obj.z * 46.0 + v_obj.x * 18.0);
	vec3 col = mix(vec3(1.0, 0.30, 0.04), vec3(1.0, 0.58, 0.16), rays);
	ALBEDO = col;
	ROUGHNESS = 0.38;
	SPECULAR = 0.4;
	EMISSION = col * (0.42 + fres * 0.7);
}
"""

## The mesh is authored at "anatomy" scale; the whole visual is then blown up
## so a fish is actually legible from a few car-lengths back. Kept as a
## constant because the collect pop tweens scale relative to it.
const VISUAL_SCALE: float = 1.5

static var _fish_mesh: ArrayMesh = null
static var _fish_mat_contrast: StandardMaterial3D = null
static var _ring_mesh: QuadMesh = null
static var _ring_mat: StandardMaterial3D = null
static var _ring_mat_contrast: StandardMaterial3D = null
static var _droplet_mesh: ArrayMesh = null
static var _droplet_base_mat: StandardMaterial3D = null
static var _flash_mesh: QuadMesh = null
static var _flash_base_mat: StandardMaterial3D = null

var value: int = 1
var collected: bool = false
var _bob_time: float = 0.0
var _spin: float = 0.0
var _magnet_target: Racer = null
var _visual: MeshInstance3D = null


func _ready() -> void:
	collision_layer = GameConfig.LAYER_PICKUPS
	collision_mask = GameConfig.LAYER_RACERS
	monitoring = true
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.0
	shape.shape = sphere
	add_child(shape)
	_visual = MeshInstance3D.new()
	_visual.mesh = _get_fish_mesh()
	_visual.material_override = _get_material()
	_visual.scale = Vector3.ONE * VISUAL_SCALE
	add_child(_visual)
	# Warm ground marker UNDER the fish so a fish line reads as a line at race
	# speed. Alpha-blended amber (not an additive bloom, which washes out over
	# sunlit snow) on a flat 2-triangle disc, parented to self so it stays
	# level and steady while the fish bobs, swims and rolls above it.
	# Underlay only -- the body itself stays fish-shaped, never a glowing orb.
	var ring := MeshInstance3D.new()
	ring.mesh = _get_ring_mesh()
	ring.material_override = _get_ring_material()
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position.y = -0.5
	add_child(ring)
	_bob_time = randf() * TAU
	body_entered.connect(_on_body_entered)


static func _get_fish_mesh() -> ArrayMesh:
	if _fish_mesh != null:
		return _fish_mesh
	var mesh := ArrayMesh.new()
	# Surface 0: fusiform body lathe -- nose at -X, caudal peduncle at +X.
	# Radius profile peaks ~38% along the body (blunt head, tapering tail),
	# depth > width (laterally compressed), slight belly drop at mid-body.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Tessellation is deliberately modest: the fish is drawn 1.5x larger than
	# before but at roughly a third of its old triangle count, because a fish
	# line can put dozens of them on screen on a mobile web frame.
	var rings := 11
	var segs := 10
	var ring_pts: Array[PackedVector3Array] = []
	for i: int in rings + 1:
		var t := float(i) / float(rings)
		var x := lerpf(-0.24, 0.20, t)
		var r := maxf(0.135 * pow(maxf(sin(PI * pow(t, 0.72)), 0.0), 0.85), 0.004)
		var yc := -0.012 * sin(PI * t)
		var pts := PackedVector3Array()
		for j: int in segs:
			var a := TAU * float(j) / float(segs)
			pts.append(Vector3(x, yc + cos(a) * r, sin(a) * r * 0.58))
		ring_pts.append(pts)
	for i: int in rings:
		for j: int in segs:
			var jn := (j + 1) % segs
			var a := ring_pts[i][j]
			var b := ring_pts[i][jn]
			var c := ring_pts[i + 1][jn]
			var d := ring_pts[i + 1][j]
			_add_body_tri(st, a, b, c)
			_add_body_tri(st, a, c, d)
	st.generate_normals()
	st.commit(mesh)
	# Surface 1: fins -- forked caudal tail (two lobes), dorsal fin, pectoral
	# pair, and a small anal fin. Flat blades, double-sided via the fin
	# shader's cull_disabled; the shader's vertex sway wags the tail lobes.
	# The tail and dorsal are oversized versus a real forage fish: they are
	# the hot-orange flags that make the pickup findable on white snow.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_fin(st, Vector3(0.17, 0.0, 0.0), Vector3(0.46, 0.23, 0.0), Vector3(0.30, 0.03, 0.0))
	_add_fin(st, Vector3(0.17, 0.0, 0.0), Vector3(0.30, -0.03, 0.0), Vector3(0.46, -0.23, 0.0))
	_add_fin(st, Vector3(-0.07, 0.08, 0.0), Vector3(0.04, 0.32, 0.0), Vector3(0.13, 0.08, 0.0))
	# Pectorals and the anal fin stay small: blown up to match the tail they
	# turn the fish into a radial orange starburst when seen head- or tail-on.
	_add_fin(st, Vector3(-0.06, -0.02, 0.06), Vector3(0.06, -0.09, 0.13), Vector3(0.02, -0.01, 0.07))
	_add_fin(st, Vector3(-0.06, -0.02, -0.06), Vector3(0.02, -0.01, -0.07), Vector3(0.06, -0.09, -0.13))
	_add_fin(st, Vector3(0.04, -0.11, 0.0), Vector3(0.12, -0.18, 0.0), Vector3(0.15, -0.08, 0.0))
	st.generate_normals()
	st.commit(mesh)
	# Surface 2: eye dots, one per side near the nose. Glossy black spheres --
	# the separate corneal-glint spheres they used to carry were a whole extra
	# surface (a draw call per fish) for two specks that never survived past
	# a couple of metres; a low roughness / high specular eye gets the same
	# highlight out of the real sun for free.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var eye := SphereMesh.new()
	eye.radius = 0.042
	eye.height = 0.084
	eye.radial_segments = 6
	eye.rings = 3
	st.append_from(eye, 0, Transform3D(Basis(), Vector3(-0.13, 0.032, 0.05)))
	st.append_from(eye, 0, Transform3D(Basis(), Vector3(-0.13, 0.032, -0.05)))
	st.commit(mesh)
	# Shared per-surface materials (stored on the shared mesh, so all
	# instances reuse them; high-contrast mode overrides via material_override).
	var body_shader := Shader.new()
	body_shader.code = BODY_SHADER_CODE
	var body_mat := ShaderMaterial.new()
	body_mat.shader = body_shader
	mesh.surface_set_material(0, body_mat)
	var fin_shader := Shader.new()
	fin_shader.code = FIN_SHADER_CODE
	var fin_mat := ShaderMaterial.new()
	fin_mat.shader = fin_shader
	mesh.surface_set_material(1, fin_mat)
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.04, 0.05, 0.07)
	eye_mat.metallic = 0.0
	eye_mat.roughness = 0.08
	eye_mat.metallic_specular = 1.0
	mesh.surface_set_material(2, eye_mat)
	_fish_mesh = mesh
	return _fish_mesh


## Adds one lathe triangle, auto-orienting to Godot's clockwise front-face
## winding using the radial outward direction (same rule as ItemBox faces).
static func _add_body_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var centroid := (a + b + c) / 3.0
	var outward := Vector3(0.0, centroid.y, centroid.z)
	if outward.length_squared() < 0.000001:
		outward = Vector3.UP
	var normal := (b - a).cross(c - a)
	if normal.dot(outward) > 0.0:
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(b)
	else:
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)


static func _add_fin(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


static func _get_material() -> StandardMaterial3D:
	# Returns a whole-fish override for high-contrast accessibility mode
	# (bright gold emissive silhouette; also freezes the shader swim sway for
	# a steadier read), or null so the mesh's per-surface materials show.
	var high_contrast := bool(SettingsManager.get_setting("accessibility", "high_contrast_pickups"))
	if not high_contrast:
		return null
	if _fish_mat_contrast == null:
		_fish_mat_contrast = StandardMaterial3D.new()
		_fish_mat_contrast.albedo_color = Color(1.0, 0.85, 0.1)
		_fish_mat_contrast.emission_enabled = true
		_fish_mat_contrast.emission = Color(1.0, 0.7, 0.05)
		_fish_mat_contrast.emission_energy_multiplier = 1.6
		_fish_mat_contrast.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _fish_mat_contrast


## Flat ground disc (2 triangles) in place of the old 384-triangle torus --
## a fish line used to cost more geometry in its halos than in its fish.
static func _get_ring_mesh() -> QuadMesh:
	if _ring_mesh == null:
		_ring_mesh = QuadMesh.new()
		_ring_mesh.size = Vector2(1.15, 1.15)
		_ring_mesh.orientation = PlaneMesh.FACE_Y
	return _ring_mesh


static func _get_ring_material() -> StandardMaterial3D:
	var high_contrast := bool(SettingsManager.get_setting("accessibility", "high_contrast_pickups"))
	if high_contrast:
		if _ring_mat_contrast == null:
			_ring_mat_contrast = _make_disc_material(Color(1.0, 0.82, 0.15, 0.7))
		return _ring_mat_contrast
	if _ring_mat == null:
		_ring_mat = _make_disc_material(Color(1.0, 0.56, 0.14, 0.5))
	return _ring_mat


## Warm alpha-blended ground wash. Alpha, not additive, on purpose: an
## additive disc vanishes over sunlit snow, while this tints bright snow
## toward amber and lifts dark night snow -- it reads on both.
static func _make_disc_material(tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.95)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = -3
	return mat


## Radial fan of teardrop water droplets for the collect splash: golden-angle
## directions biased upward (a splash, not an explosion), each an elongated
## kite with deterministic size variance. Same construction family as
## Snowball's chunk fan so all pickup bursts share one aesthetic. Winding is
## irrelevant — the base material is cull_disabled.
static func _get_droplet_mesh() -> ArrayMesh:
	if _droplet_mesh != null:
		return _droplet_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 14
	for i: int in count:
		var g := float(i) * 2.39996
		var y := lerpf(-0.1, 0.85, (float(i) + 0.5) / float(count))
		var r := sqrt(maxf(1.0 - y * y, 0.0))
		var dir := Vector3(cos(g) * r, y, sin(g) * r)
		var ref_axis := Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT
		var tangent := dir.cross(ref_axis).normalized()
		var drop_len := 0.13 + 0.10 * fmod(float(i) * 0.618, 1.0)
		var half_w := 0.020 + 0.010 * fmod(float(i) * 0.382, 1.0)
		var inner := dir * 0.10
		var outer := dir * (0.10 + drop_len)
		var mid := dir * (0.10 + drop_len * 0.45)
		st.add_vertex(mid + tangent * half_w)
		st.add_vertex(mid - tangent * half_w)
		st.add_vertex(outer)
		st.add_vertex(mid - tangent * half_w)
		st.add_vertex(mid + tangent * half_w)
		st.add_vertex(inner)
	_droplet_mesh = st.commit()
	return _droplet_mesh


## Base material for the droplet fan. Alpha animates during the splash, so
## each burst duplicates it — same pattern as Snowball's chunk material.
static func _get_droplet_base_material() -> StandardMaterial3D:
	if _droplet_base_mat == null:
		_droplet_base_mat = StandardMaterial3D.new()
		_droplet_base_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_droplet_base_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_droplet_base_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_droplet_base_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_droplet_base_mat.albedo_color = Color(0.85, 0.94, 1.0, 0.0)
		_droplet_base_mat.render_priority = 1
	return _droplet_base_mat


static func _get_flash_mesh() -> QuadMesh:
	if _flash_mesh == null:
		_flash_mesh = QuadMesh.new()
		_flash_mesh.size = Vector2(0.9, 0.9)
	return _flash_mesh


## Base material for the collect flash. Alpha animates during the burst, so
## each grab duplicates it -- same pattern as the droplet fan.
static func _get_flash_base_material() -> StandardMaterial3D:
	if _flash_base_mat == null:
		_flash_base_mat = StandardMaterial3D.new()
		_flash_base_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_base_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_base_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flash_base_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_flash_base_mat.billboard_keep_scale = true
		_flash_base_mat.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.9)
		_flash_base_mat.albedo_color = Color(1.0, 0.87, 0.5, 0.0)
		_flash_base_mat.render_priority = 2
	return _flash_base_mat


func _physics_process(delta: float) -> void:
	if collected:
		return
	_bob_time += delta
	if _magnet_target != null and is_instance_valid(_magnet_target):
		var to_target := _magnet_target.global_position + Vector3.UP * 0.6 - global_position
		if to_target.length() < 1.2:
			_on_body_entered(_magnet_target)
			return
		global_position += to_target.normalized() * 22.0 * delta
	else:
		# Bob/spin only the visual child so the Area3D transform stays static
		# (no broadphase re-sync every tick; same pattern as item_box.gd).
		_spin += delta * 0.9
		_visual.position.y = sin(_bob_time * 2.4) * 0.15
		# Gentle swim wiggle: yaw sine on the visual so the fish looks alive
		# (the fine tail wag rides in the body/fin shaders' vertex sway),
		# plus a small counter-phase roll — real fish bank into each stroke.
		_visual.rotation.y = _spin + sin(_bob_time * 5.2) * 0.3
		_visual.rotation.z = sin(_bob_time * 5.2 + 1.1) * 0.07


func attract_to(racer: Racer) -> void:
	if not collected:
		_magnet_target = racer


func _on_body_entered(body: Node3D) -> void:
	if collected or not body is Racer:
		return
	var racer := body as Racer
	collected = true
	racer.collect_fish(value)
	if racer.is_player:
		AudioManager.play_sfx_varied("sfx_fish", -2.0)
	set_deferred("monitoring", false)
	# Pop the fish, then splash: a warm flash blooms where it was swimming and
	# a droplet fan arcs out and rains down. When the splash is skipped
	# (headless, low particle quality) the pop alone carries the read and frees
	# the node.
	var pop := create_tween()
	pop.tween_property(_visual, "scale", Vector3.ONE * VISUAL_SCALE * 1.75, 0.08)
	pop.tween_property(_visual, "scale", Vector3.ONE * 0.01, 0.12)
	var drops := _spawn_droplet_burst()
	if drops == null:
		pop.tween_callback(queue_free)
		return
	# The splash outlives the pop, so it owns the queue_free.
	var drop_mat := drops.material_override as StandardMaterial3D
	var splash := create_tween()
	splash.set_parallel(true)
	splash.tween_property(drops, "scale", Vector3.ONE * 2.1, 0.42) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	splash.tween_property(drops, "rotation:y", drops.rotation.y + 0.7, 0.42)
	splash.tween_property(drops, "position:y", drops.position.y - 0.35, 0.42) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	splash.tween_property(drop_mat, "albedo_color:a", 0.0, 0.42)
	# Reward flash: a single warm billboard that snaps out and fades, so the
	# grab lands as a beat rather than only as a disappearance.
	var flash := _spawn_collect_flash()
	if flash != null:
		var flash_mat := flash.material_override as StandardMaterial3D
		splash.tween_property(flash, "scale", Vector3.ONE * 2.4, 0.26) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		splash.tween_property(flash_mat, "albedo_color:a", 0.0, 0.26)
	splash.chain().tween_callback(queue_free)


## Builds the one-shot droplet fan at the fish's position, or returns null
## when the splash is skipped (headless, low particle quality). Mesh and
## base material are shared across all fish; only the animated duplicate and
## the burst node are allocated, and both free with the pickup.
func _spawn_droplet_burst() -> MeshInstance3D:
	if GameConfig.is_headless():
		return null
	if String(SettingsManager.get_setting("display", "particle_quality")) == "low":
		return null
	var mat := _get_droplet_base_material().duplicate() as StandardMaterial3D
	mat.albedo_color = Color(0.85, 0.94, 1.0, 0.95)
	var drops := MeshInstance3D.new()
	drops.mesh = _get_droplet_mesh()
	drops.material_override = mat
	drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	drops.position = _visual.position
	drops.rotation.y = randf() * TAU
	drops.scale = Vector3.ONE * 0.6
	add_child(drops)
	return drops


## One-shot warm reward flash at the fish's position, or null when bursts are
## skipped. The base material is shared; only the animated duplicate and the
## node are allocated, and both free with the pickup.
func _spawn_collect_flash() -> MeshInstance3D:
	if GameConfig.is_headless():
		return null
	var mat := _get_flash_base_material().duplicate() as StandardMaterial3D
	mat.albedo_color = Color(1.0, 0.87, 0.5, 0.95)
	var flash := MeshInstance3D.new()
	flash.mesh = _get_flash_mesh()
	flash.material_override = mat
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.position = _visual.position
	flash.scale = Vector3.ONE * 0.5
	add_child(flash)
	return flash
