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
## flash as the view sweeps, and a frosty rim. The same material is reused
## by the thrown Snowball projectile via get_snow_material() so ammo and
## projectile read as one substance.
##
## Accessibility: reads through SHAPE (pyramid stack) + PATTERN (glitter,
## twin sparkle billboards) + BRIGHTNESS (ground halo ring), never hue
## alone. "accessibility/high_contrast_pickups" swaps the stack and halo to
## the same bright-gold emissive language as FishPickup / ItemBox.

const RESPAWN_TIME: float = 6.0
const GROUP_NAME: StringName = &"snowball_pickups"
const VISUAL_BASE_Y: float = 0.32

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
	// Cool occlusion toward the underside, sunlit white toward the sky.
	float up = clamp(v_nrm.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = mix(vec3(0.72, 0.80, 0.92), vec3(0.965, 0.985, 1.0), up);
	col -= vec3(0.045, 0.03, 0.005) * clump;
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
static var _halo_mesh: TorusMesh = null
static var _halo_mat: StandardMaterial3D = null
static var _halo_mat_contrast: StandardMaterial3D = null

var _visual: MeshInstance3D = null
var _sparkle: MeshInstance3D = null
var _sparkle2: MeshInstance3D = null
var _halo: MeshInstance3D = null
var _active: bool = true
var _bob_time: float = 0.0


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
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_visual)
	# Ground halo ring: brightness anchor in the pickup lane (same language
	# as FishPickup's underlay and ItemBox's halo, gold in high-contrast
	# mode). Attached to self so it does not spin with the stack.
	_halo = MeshInstance3D.new()
	_halo.mesh = _get_halo_mesh()
	_halo.material_override = _get_halo_material()
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_halo.position.y = 0.05
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
	_bob_time = randf() * TAU
	body_entered.connect(_on_body_entered)


## Three uniformly-scaled sphere lobes composed into one shared ArrayMesh:
## two nestled base balls plus one resting on top. Uniform scale + rotation
## per lobe keeps append_from normals valid; the slight size differences and
## tilts sell "hand-packed" rather than "three primitives".
static func _get_mesh() -> ArrayMesh:
	if _stack_mesh != null:
		return _stack_mesh
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 14
	ball.rings = 8
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lobes: Array[Transform3D] = [
		Transform3D(Basis(Vector3.UP, 0.4).scaled(Vector3.ONE * 0.22), Vector3(-0.13, -0.07, -0.02)),
		Transform3D((Basis(Vector3.UP, 2.3) * Basis(Vector3.RIGHT, 0.25)).scaled(Vector3.ONE * 0.215), Vector3(0.13, -0.07, 0.03)),
		Transform3D((Basis(Vector3.UP, 4.0) * Basis(Vector3.FORWARD, 0.15)).scaled(Vector3.ONE * 0.19), Vector3(0.0, 0.17, 0.0)),
	]
	for t: Transform3D in lobes:
		st.append_from(ball, 0, t)
	_stack_mesh = st.commit()
	return _stack_mesh


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
	# language as FishPickup so all pickups read consistently.
	var high_contrast := bool(SettingsManager.get_setting("accessibility", "high_contrast_pickups"))
	if high_contrast:
		if _ball_mat_contrast == null:
			_ball_mat_contrast = StandardMaterial3D.new()
			_ball_mat_contrast.albedo_color = Color(1.0, 0.85, 0.1)
			_ball_mat_contrast.emission_enabled = true
			_ball_mat_contrast.emission = Color(1.0, 0.7, 0.05)
			_ball_mat_contrast.emission_energy_multiplier = 1.6
		return _ball_mat_contrast
	return get_snow_material()


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


static func _get_halo_mesh() -> TorusMesh:
	if _halo_mesh == null:
		_halo_mesh = TorusMesh.new()
		_halo_mesh.inner_radius = 0.34
		_halo_mesh.outer_radius = 0.46
		_halo_mesh.rings = 24
		_halo_mesh.ring_segments = 6
	return _halo_mesh


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


func _physics_process(delta: float) -> void:
	if not _active:
		return
	_bob_time += delta
	# Bob only the visual child so the Area3D transform stays static
	# (no broadphase re-sync every tick; same pattern as item_box.gd).
	_visual.position.y = VISUAL_BASE_Y + sin(_bob_time * 2.2) * 0.1
	_visual.rotation.y += delta * 1.3
	if _sparkle != null:
		# Gentle glint breathing; slow enough to stay reduced-flashing safe.
		var pulse := 0.75 + 0.25 * sin(_bob_time * 4.6)
		_sparkle.scale = Vector3(pulse, pulse, pulse)
	if _sparkle2 != null:
		var pulse2 := (0.75 + 0.25 * sin(_bob_time * 4.6 + PI)) * 0.6
		_sparkle2.scale = Vector3(pulse2, pulse2, pulse2)


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
	set_deferred("monitoring", false)
	var timer := get_tree().create_timer(RESPAWN_TIME)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(self):
			_active = true
			_visual.visible = true
			_halo.visible = true
			set_deferred("monitoring", true))
