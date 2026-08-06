class_name SnowballPickup
extends Area3D
## Collectible throwable-snowball pickup: a hand-packed pyramid of three
## snowballs (two below, one on top) resting on the track, so the "this is
## ammo, up to 3" read is carried by SHAPE. Grants +1 snowball ammo (up to
## Racer.MAX_SNOWBALL_AMMO) and is left in place when the racer is already
## full. All instances share one mesh and material set; "pooling" is hide +
## respawn like ItemBox, so a row keeps rewarding trailing racers without
## allocating new nodes. The pickup collision sphere is unchanged.
##
## Rendering: the stack is one shared ArrayMesh (three uniformly-scaled,
## individually rotated sphere lobes) under an inline packed-snow shader —
## clumpy grain, cool crevice occlusion, sparse per-cell glitter facets that
## flash as the view sweeps, and a frosty rim — plus a second surface of
## tiny vertex-colored pebble/coal flecks half-sunk into the lobes (the grit
## a hand-packed ball picks up off the track). The snow material is reused
## by the thrown Snowball projectile via get_snow_material() so ammo and
## projectile read as one substance.
##
## Game feel: a larger sense Area3D (the pickup sphere is untouched) makes
## the stack wobble in anticipation as a racer closes in; collecting bursts
## the same snow-clod chunk fan the projectile splats with (shared mesh and
## base material from Snowball) under a soft central flash, and the respawn
## scales back in with ItemBox's back-eased overshoot instead of popping.
##
## Accessibility: reads through SHAPE (pyramid stack) + PATTERN (glitter,
## twin sparkle billboards) + BRIGHTNESS (deep cool undersides against sunlit
## crowns, warm ground disc), never hue alone.
## "accessibility/high_contrast_pickups" swaps the stack and marker to the
## same bright-gold emissive language as FishPickup / ItemBox.

const RESPAWN_TIME: float = 6.0
const GROUP_NAME: StringName = &"snowball_pickups"
const VISUAL_BASE_Y: float = 0.36

## White snow on white snow is the worst readability case in the game, so the
## stack is drawn larger than the ammo it represents and leans hard on FORM
## shading (deep cool undersides against sunlit crowns) plus a warm ground
## disc, rather than on being brighter than its surroundings — which is not
## possible on a snowfield.
const VISUAL_SCALE: float = 1.3

## Packed-snow shader: white clumped surface with faint cool shadow in the
## grain dips, sparse per-cell glitter facets (random normal perturbation
## makes each cell fire at its own view angle, like snow-crystal sparkle in
## low sun), and a soft frost rim. Pure math, no textures — WebGL2/mobile
## safe, and cheap enough for every pickup row on screen at once.
const SNOW_SHADER_CODE := """shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform float sparkle_strength = 0.6;

varying vec3 v_obj;
varying vec3 v_nrm;

float hash31(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void vertex() {
	v_obj = VERTEX;
	v_nrm = NORMAL;
}

void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 3.0);
	// Clumpy packed-snow grain: two interfering sine fields stand in for
	// pressed lumps; the dips read as tiny shadowed pores.
	float clump = sin(v_obj.x * 43.0 + sin(v_obj.y * 31.0) * 2.0)
			* sin(v_obj.y * 37.0 + v_obj.z * 29.0);
	// Cool occlusion toward the underside, sunlit white toward the sky. The
	// underside is pushed much deeper than physically plausible on purpose:
	// on a snowfield the only thing that separates a snowball from the ground
	// behind it is its own form shading, so the terminator has to be strong.
	float up = clamp(v_nrm.y * 0.5 + 0.5, 0.0, 1.0);
	up = smoothstep(0.12, 0.88, up);
	vec3 col = mix(vec3(0.30, 0.44, 0.66), vec3(0.99, 0.995, 1.0), up);
	col -= vec3(0.06, 0.04, 0.005) * clump;
	// Glitter: sparse cells, each with a randomly tilted micro-facet that
	// fires when it aligns with the view — sparkles crawl as camera or ball
	// moves, never strobing in place (reduced-flashing safe).
	vec3 cell = floor(v_obj * 30.0);
	vec3 jitter = vec3(hash31(cell), hash31(cell + 1.3), hash31(cell + 2.6)) - 0.5;
	vec3 gn = normalize(NORMAL + jitter * 1.1);
	float glint = pow(clamp(dot(gn, VIEW), 0.0, 1.0), 36.0) * step(0.55, hash31(cell + 4.1));
	ALBEDO = col;
	ROUGHNESS = clamp(0.58 - clump * 0.08, 0.0, 1.0);
	SPECULAR = 0.35;
	EMISSION = vec3(1.0) * glint * sparkle_strength + vec3(0.55, 0.75, 1.0) * fres * 0.16;
}
"""

static var _stack_mesh: ArrayMesh = null
static var _snow_mat: ShaderMaterial = null
static var _ball_mat_contrast: StandardMaterial3D = null
static var _sparkle_mesh: QuadMesh = null
static var _sparkle_mat: StandardMaterial3D = null
static var _halo_mesh: QuadMesh = null
static var _halo_mat: StandardMaterial3D = null
static var _halo_mat_contrast: StandardMaterial3D = null
static var _collect_flash_mesh: QuadMesh = null
static var _collect_flash_base_mat: StandardMaterial3D = null

var _visual: MeshInstance3D = null
var _sparkle: MeshInstance3D = null
var _sparkle2: MeshInstance3D = null
var _halo: MeshInstance3D = null
var _sense: Area3D = null
var _chunks: MeshInstance3D = null
var _chunk_mat: StandardMaterial3D = null
var _flash: MeshInstance3D = null
var _flash_mat: StandardMaterial3D = null
var _burst_tween: Tween = null
var _respawn_tween: Tween = null
var _active: bool = true
var _bob_time: float = 0.0
var _near_racers: int = 0
var _wobble: float = 0.0


func _ready() -> void:
	collision_layer = GameConfig.LAYER_PICKUPS
	collision_mask = GameConfig.LAYER_RACERS
	monitoring = true
	add_to_group(GROUP_NAME)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.0
	shape.shape = sphere
	add_child(shape)
	_visual = MeshInstance3D.new()
	_visual.mesh = _get_mesh()
	_visual.material_override = _get_material()
	_visual.position.y = VISUAL_BASE_Y
	_visual.scale = Vector3.ONE * VISUAL_SCALE
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_visual)
	# Warm ground disc: the only thing on a white stack that is not white, and
	# therefore what actually finds the pickup for the player at speed (same
	# language as FishPickup's underlay and ItemBox's marker, gold in
	# high-contrast mode). Attached to self so it does not spin with the stack.
	_halo = MeshInstance3D.new()
	_halo.mesh = _get_halo_mesh()
	_halo.material_override = _get_halo_material()
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.position.y = 0.06
	add_child(_halo)
	# Twin sparkle glints riding the stack: one on the top ball's shoulder,
	# a smaller one on a base ball, breathing in counter-phase. Purely
	# decorative, so skipped headless.
	if not GameConfig.is_headless():
		_sparkle = MeshInstance3D.new()
		_sparkle.mesh = _get_sparkle_mesh()
		_sparkle.material_override = _get_sparkle_material()
		_sparkle.position = Vector3(0.06, 0.30, 0.05)
		_sparkle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_visual.add_child(_sparkle)
		_sparkle2 = MeshInstance3D.new()
		_sparkle2.mesh = _get_sparkle_mesh()
		_sparkle2.material_override = _get_sparkle_material()
		_sparkle2.position = Vector3(-0.17, 0.0, 0.11)
		_sparkle2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_visual.add_child(_sparkle2)
		# Anticipation sense: a second, larger Area3D that only watches for
		# approaching racers so the stack can wobble before the grab (the
		# pickup collision sphere above is untouched). Layer 0 + monitorable
		# off — nothing ever collides with or queries it back.
		_sense = Area3D.new()
		_sense.collision_layer = 0
		_sense.collision_mask = GameConfig.LAYER_RACERS
		_sense.monitorable = false
		var sense_shape := CollisionShape3D.new()
		var sense_sphere := SphereShape3D.new()
		sense_sphere.radius = 4.5
		sense_shape.shape = sense_sphere
		_sense.add_child(sense_shape)
		add_child(_sense)
		_sense.body_entered.connect(_on_sense_entered)
		_sense.body_exited.connect(_on_sense_exited)
		# Collect puff: central soft flash + the same snow-clod chunk fan the
		# thrown Snowball splats with (shared mesh/base material; duplicates
		# because the alpha animates — ItemBox burst pattern). Both nodes are
		# built once and reused every respawn cycle. Chunks are skipped on low
		# particle quality; the flash alone still marks the grab.
		_flash_mat = _get_collect_flash_base_material().duplicate() as StandardMaterial3D
		_flash = MeshInstance3D.new()
		_flash.mesh = _get_collect_flash_mesh()
		_flash.material_override = _flash_mat
		_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flash.visible = false
		_flash.position.y = VISUAL_BASE_Y
		add_child(_flash)
		if String(SettingsManager.get_setting("display", "particle_quality")) != "low":
			_chunk_mat = Snowball.get_chunk_base_material().duplicate() as StandardMaterial3D
			_chunks = MeshInstance3D.new()
			_chunks.mesh = Snowball.get_chunk_mesh()
			_chunks.material_override = _chunk_mat
			_chunks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_chunks.visible = false
			add_child(_chunks)
	_bob_time = randf() * TAU
	body_entered.connect(_on_body_entered)


## Three uniformly-scaled sphere lobes composed into one shared ArrayMesh:
## two nestled base balls plus one resting on top. Uniform scale + rotation
## per lobe keeps append_from normals valid; the slight size differences and
## tilts sell "hand-packed" rather than "three primitives". Surface 1 adds
## tiny vertex-colored pebble/coal flecks half-sunk into each lobe. Both
## surface materials live on the shared mesh (FishPickup pattern), so every
## instance reuses ONE snow material and ONE fleck material.
static func _get_mesh() -> ArrayMesh:
	if _stack_mesh != null:
		return _stack_mesh
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	# Modest tessellation: a snowball row can put a dozen stacks on screen, and
	# the packed-snow shader carries the surface detail, not the silhouette.
	ball.radial_segments = 12
	ball.rings = 6
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lobes: Array[Transform3D] = [
		Transform3D(Basis(Vector3.UP, 0.4).scaled(Vector3.ONE * 0.22), Vector3(-0.13, -0.07, -0.02)),
		Transform3D((Basis(Vector3.UP, 2.3) * Basis(Vector3.RIGHT, 0.25)).scaled(Vector3.ONE * 0.215), Vector3(0.13, -0.07, 0.03)),
		Transform3D((Basis(Vector3.UP, 4.0) * Basis(Vector3.FORWARD, 0.15)).scaled(Vector3.ONE * 0.19), Vector3(0.0, 0.17, 0.0)),
	]
	for t: Transform3D in lobes:
		st.append_from(ball, 0, t)
	var mesh := st.commit()
	# Fleck surface: three grit chips per lobe on a deterministic golden-angle
	# spread, biased toward the upper hemisphere so some stay visible from any
	# spin angle. Centers sit at 97% of the lobe radius — half embedded, half
	# proud. Vertex colors alternate coal dark / pebble brown so ONE cached
	# rock material (multiplies vertex color) covers both.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var coal := Color(0.14, 0.13, 0.15)
	var pebble := Color(0.44, 0.38, 0.33)
	var fleck_i := 0
	for t: Transform3D in lobes:
		for _k: int in 3:
			var ga := float(fleck_i) * 2.39996 + 0.7
			var el := lerpf(0.05, 0.8, fmod(float(fleck_i) * 0.618, 1.0))
			var ring := sqrt(maxf(1.0 - el * el, 0.0))
			var pos := t * (Vector3(cos(ga) * ring, el, sin(ga) * ring) * 0.97)
			var r := 0.015 + 0.009 * fmod(float(fleck_i) * 0.382, 1.0)
			_add_fleck(st, pos, r, pebble if fleck_i % 3 == 1 else coal)
			fleck_i += 1
	st.generate_normals()
	st.commit(mesh)
	mesh.surface_set_material(0, get_snow_material())
	mesh.surface_set_material(1, VisualLibrary.rock_material(Color(1.0, 1.0, 1.0), 0.92))
	_stack_mesh = mesh
	return _stack_mesh


## One grit chip: a squashed octahedron with a per-size equator twist —
## small enough to read as embedded grit, not decoration.
static func _add_fleck(st: SurfaceTool, center: Vector3, r: float, color: Color) -> void:
	var top := center + Vector3(0.0, r * 0.8, 0.0)
	var bottom := center - Vector3(0.0, r * 0.8, 0.0)
	var eq: Array[Vector3] = []
	for i: int in 4:
		var a := TAU * float(i) / 4.0 + r * 200.0
		eq.append(center + Vector3(cos(a) * r, 0.0, sin(a) * r))
	for i: int in 4:
		var j := (i + 1) % 4
		_add_fleck_tri(st, top, eq[i], eq[j], center, color)
		_add_fleck_tri(st, bottom, eq[j], eq[i], center, color)


## Adds one fleck triangle, auto-orienting to Godot's clockwise front-face
## winding relative to the fleck's own center (same rule as ItemBox faces).
static func _add_fleck_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, center: Vector3, color: Color) -> void:
	var outward := (a + b + c) / 3.0 - center
	var normal := (b - a).cross(c - a)
	var ordered: Array[Vector3] = [a, b, c]
	if normal.dot(outward) > 0.0:
		ordered = [a, c, b]
	for p: Vector3 in ordered:
		st.set_color(color)
		st.add_vertex(p)


## Shared packed-snow glitter material — also used by the thrown Snowball
## projectile so ammo and projectile read as the same substance. Always the
## normal snow look: high-contrast pickup gilding is applied separately in
## _get_material() (the projectile is a hazard, not a pickup).
static func get_snow_material() -> ShaderMaterial:
	if _snow_mat == null:
		var shader := Shader.new()
		shader.code = SNOW_SHADER_CODE
		_snow_mat = ShaderMaterial.new()
		_snow_mat.shader = shader
	return _snow_mat


static func _get_material() -> Material:
	# High-contrast accessibility mode reuses the same bright-gold emissive
	# language as FishPickup so all pickups read consistently (the override
	# also gilds the grit flecks: one solid readable silhouette).
	var high_contrast := bool(SettingsManager.get_setting("accessibility", "high_contrast_pickups"))
	if high_contrast:
		if _ball_mat_contrast == null:
			_ball_mat_contrast = StandardMaterial3D.new()
			_ball_mat_contrast.albedo_color = Color(1.0, 0.85, 0.1)
			_ball_mat_contrast.emission_enabled = true
			_ball_mat_contrast.emission = Color(1.0, 0.7, 0.05)
			_ball_mat_contrast.emission_energy_multiplier = 1.6
		return _ball_mat_contrast
	# Normal mode: null override, so the shared mesh's per-surface materials
	# (packed snow + grit flecks) show through.
	return null


static func _get_sparkle_mesh() -> QuadMesh:
	if _sparkle_mesh == null:
		_sparkle_mesh = QuadMesh.new()
		_sparkle_mesh.size = Vector2(0.34, 0.34)
	return _sparkle_mesh


static func _get_sparkle_material() -> StandardMaterial3D:
	if _sparkle_mat == null:
		_sparkle_mat = StandardMaterial3D.new()
		_sparkle_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.85)
		_sparkle_mat.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.6)
		_sparkle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_sparkle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_sparkle_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return _sparkle_mat


## Flat 2-triangle ground disc, replacing the old 288-triangle torus ring.
static func _get_halo_mesh() -> QuadMesh:
	if _halo_mesh == null:
		_halo_mesh = QuadMesh.new()
		_halo_mesh.size = Vector2(1.5, 1.5)
		_halo_mesh.orientation = PlaneMesh.FACE_Y
	return _halo_mesh


## Alpha-blended warm wash rather than an additive bloom: additive light
## disappears over sunlit snow, whereas this tints bright snow toward amber
## AND lifts dark night snow, so the marker reads on every course.
static func _get_halo_material() -> StandardMaterial3D:
	var high_contrast := bool(SettingsManager.get_setting("accessibility", "high_contrast_pickups"))
	if high_contrast:
		if _halo_mat_contrast == null:
			_halo_mat_contrast = _make_disc_material(Color(1.0, 0.82, 0.15, 0.75))
		return _halo_mat_contrast
	if _halo_mat == null:
		_halo_mat = _make_disc_material(Color(0.98, 0.52, 0.16, 0.6))
	return _halo_mat


static func _make_disc_material(tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.95)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = -3
	return mat


static func _get_collect_flash_mesh() -> QuadMesh:
	if _collect_flash_mesh == null:
		_collect_flash_mesh = QuadMesh.new()
		_collect_flash_mesh.size = Vector2(0.9, 0.9)
	return _collect_flash_mesh


## Base material for the collect flash. Alpha animates during the burst, so
## instances duplicate it — same pattern as ItemBox's burst materials.
static func _get_collect_flash_base_material() -> StandardMaterial3D:
	if _collect_flash_base_mat == null:
		_collect_flash_base_mat = StandardMaterial3D.new()
		_collect_flash_base_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_collect_flash_base_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_collect_flash_base_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_collect_flash_base_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_collect_flash_base_mat.billboard_keep_scale = true
		_collect_flash_base_mat.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.85)
		_collect_flash_base_mat.albedo_color = Color(0.95, 0.98, 1.0, 0.0)
		_collect_flash_base_mat.render_priority = 1
	return _collect_flash_base_mat


func _physics_process(delta: float) -> void:
	if not _active:
		return
	_bob_time += delta
	# Bob only the visual child so the Area3D transform stays static
	# (no broadphase re-sync every tick; same pattern as item_box.gd).
	_visual.position.y = VISUAL_BASE_Y + sin(_bob_time * 2.2) * 0.1
	_visual.rotation.y += delta * 1.3
	# Anticipation wobble: the stack jitters like loose-packed snow about to
	# be grabbed while a racer is inside the sense radius. Eased in and out
	# so it never snaps; amplitude drops under reduced motion. Frequencies
	# stay well under flashing-safety thresholds.
	var wobble_target := 1.0 if _near_racers > 0 else 0.0
	_wobble = move_toward(_wobble, wobble_target, delta * 3.0)
	if _wobble > 0.0:
		var amp := 0.4 if UITheme.reduced_motion() else 1.0
		_visual.rotation.z = sin(_bob_time * 9.2) * 0.13 * _wobble * amp
		_visual.rotation.x = sin(_bob_time * 7.1 + 1.4) * 0.07 * _wobble * amp
	else:
		_visual.rotation.z = 0.0
		_visual.rotation.x = 0.0
	if _sparkle != null:
		# Gentle glint breathing; slow enough to stay reduced-flashing safe.
		var pulse := 0.75 + 0.25 * sin(_bob_time * 4.6)
		_sparkle.scale = Vector3(pulse, pulse, pulse)
	if _sparkle2 != null:
		var pulse2 := (0.75 + 0.25 * sin(_bob_time * 4.6 + PI)) * 0.6
		_sparkle2.scale = Vector3(pulse2, pulse2, pulse2)


## Sense handlers: count racers inside the wobble radius. The count is kept
## across collection/respawn, so a stack reappearing next to a waiting racer
## resumes wobbling immediately.
func _on_sense_entered(body: Node3D) -> void:
	if body is Racer:
		_near_racers += 1


func _on_sense_exited(body: Node3D) -> void:
	if body is Racer:
		_near_racers = maxi(_near_racers - 1, 0)


## AI queries this before steering toward the pickup.
func is_available() -> bool:
	return _active


func _on_body_entered(body: Node3D) -> void:
	if not _active or not body is Racer:
		return
	var racer := body as Racer
	if not racer.add_snowball_ammo(1):
		return  # already carrying the max: leave it for a rival
	_active = false
	if racer.is_player:
		# Same pickup sfx as item boxes, pitched up so ammo reads distinct.
		AudioManager.play_sfx("sfx_powerup", 1.45, -4.0)
	_visual.visible = false
	_halo.visible = false
	_play_collect_burst()
	set_deferred("monitoring", false)
	var timer := get_tree().create_timer(RESPAWN_TIME)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(self):
			_active = true
			_visual.visible = true
			_halo.visible = true
			set_deferred("monitoring", true)
			_play_respawn())


## Collect puff: soft central flash + the Snowball splat's chunk fan
## bursting off the stack, so grabbing ammo reads as the same substance the
## projectile splats into. Nodes are pre-built in _ready and reused every
## respawn cycle; only the one-shot tween allocates. No-op headless.
func _play_collect_burst() -> void:
	if _flash == null:
		return
	if _burst_tween != null and _burst_tween.is_valid():
		_burst_tween.kill()
	_burst_tween = create_tween()
	_burst_tween.set_parallel(true)
	_flash.visible = true
	_flash.scale = Vector3.ONE * 0.5
	_flash_mat.albedo_color = Color(1.0, 0.94, 0.78, 0.95)
	_burst_tween.tween_property(_flash, "scale", Vector3.ONE * 2.2, 0.26) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_burst_tween.tween_property(_flash_mat, "albedo_color:a", 0.0, 0.26)
	if _chunks != null:
		_chunks.visible = true
		_chunks.position = Vector3(0.0, VISUAL_BASE_Y, 0.0)
		_chunks.rotation.y = randf() * TAU
		_chunks.scale = Vector3.ONE * 0.4
		_chunk_mat.albedo_color = Color(0.95, 0.98, 1.0, 0.95)
		_burst_tween.tween_property(_chunks, "scale", Vector3.ONE * 1.9, 0.36) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_burst_tween.tween_property(_chunks, "rotation:y", _chunks.rotation.y + 0.8, 0.36)
		_burst_tween.tween_property(_chunks, "position:y", VISUAL_BASE_Y - 0.28, 0.36) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_burst_tween.tween_property(_chunk_mat, "albedo_color:a", 0.0, 0.36)
	_burst_tween.chain().tween_callback(func() -> void:
		_flash.visible = false
		if _chunks != null:
			_chunks.visible = false)


## Respawn scale-in with a back-eased overshoot (ItemBox's respawn language)
## so the stack re-packs itself instead of popping into existence.
func _play_respawn() -> void:
	if _respawn_tween != null and _respawn_tween.is_valid():
		_respawn_tween.kill()
	_visual.scale = Vector3.ONE * 0.2
	_respawn_tween = create_tween()
	_respawn_tween.tween_property(_visual, "scale", Vector3.ONE * VISUAL_SCALE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
