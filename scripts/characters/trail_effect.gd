class_name TrailEffect
extends GPUParticles3D
## Cosmetic trail behind a racer. Purely visual.
## Emission tracks the parent racer's speed — faint at a waddle, dense at a
## full slide, silent when stopped — so the trail doubles as speed feedback.
## The particle budget respects the display/particle_quality setting.

var _racer: Racer = null
const PARTICLE_PATHS := {
	"trail_snowflake": "res://assets/art/characters/trails/trail_snowflake_particle_v1.webp",
	"trail_fish": "res://assets/art/characters/trails/trail_fish_particle_v1.webp",
	"trail_aurora": "res://assets/art/characters/trails/trail_aurora_particle_v1.webp",
	"trail_rainbow": "res://assets/art/characters/trails/trail_rainbow_particle_v1.webp",
}
static var _particle_textures: Dictionary = {}
static var _fade_gradient: Gradient = null
static var _fade_texture: GradientTexture1D = null
const MAX_PARTICLES := 30
const PARTICLE_LIFETIME := 1.05
const PARTICLE_SIZES := {
	"trail_snowflake": 0.29,
	"trail_fish": 0.35,
	"trail_aurora": 0.46,
	"trail_rainbow": 0.46,
}


func _ready() -> void:
	if String(SettingsManager.get_setting("display", "particle_quality")) == "low":
		amount = maxi(12, amount * 2 / 3)
	_racer = get_parent() as Racer


func _process(_delta: float) -> void:
	if _racer == null:
		return
	set_motion(_racer.current_speed, Racer.SLIDE_MAX_SPEED)


func set_motion(current_speed: float, maximum_speed: float, active: bool = true) -> void:
	# Fixed lifetime and speed-proportional emission keep spacing nearly equal
	# along the ground at both runner speeds. No per-frame material allocation.
	emitting = active and current_speed > 3.0
	amount_ratio = clampf(current_speed / maxf(maximum_speed, 0.001), 0.45, 1.0)
	speed_scale = 1.0


static func fade_gradient() -> Gradient:
	if _fade_gradient == null:
		_fade_gradient = Gradient.new()
		_fade_gradient.offsets = PackedFloat32Array([0.0, 0.12, 0.55, 1.0])
		_fade_gradient.colors = PackedColorArray([Color(1, 1, 1, 0.0),
			Color.WHITE, Color(1, 1, 1, 0.85), Color(1, 1, 1, 0.0)])
	return _fade_gradient


static func create(trail_id: String) -> TrailEffect:
	var texture := _particle_texture(trail_id)
	if texture == null:
		return null
	var trail := TrailEffect.new()
	trail.name = "CosmeticTrail"
	trail.set_meta("cosmetic_id", trail_id)
	# Countdown/idle must not emit before the owner reports actual movement.
	trail.emitting = false
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0.3, 1)
	mat.spread = 20.0
	mat.initial_velocity_min = 0.9
	mat.initial_velocity_max = 2.1
	mat.gravity = Vector3(0, -0.6, 0)
	mat.scale_min = 0.65
	mat.scale_max = 1.0
	var mesh: PrimitiveMesh
	# Artwork already contains the authored colors. Neutral modulation avoids
	# tinting it twice (process material and draw material) or rotating its hue.
	var color := Color(1, 1, 1, 0.9)
	match trail_id:
		"trail_snowflake":
			var flake := QuadMesh.new()
			flake.size = Vector2.ONE * float(PARTICLE_SIZES[trail_id])
			mesh = flake
			mat.angular_velocity_min = -180.0
			mat.angular_velocity_max = 180.0
		"trail_fish":
			var fish := QuadMesh.new()
			fish.size = Vector2.ONE * float(PARTICLE_SIZES[trail_id])
			mesh = fish
			mat.angular_velocity_min = -90.0
			mat.angular_velocity_max = 90.0
		"trail_aurora", "trail_rainbow":
			color.a = 0.75
			var ribbon := QuadMesh.new()
			ribbon.size = Vector2.ONE * float(PARTICLE_SIZES[trail_id])
			mesh = ribbon
		_:
			return null
	mat.color = color
	if _fade_texture == null:
		_fade_texture = GradientTexture1D.new()
		_fade_texture.gradient = fade_gradient()
	mat.color_ramp = _fade_texture
	trail.process_material = mat
	var draw_mat := StandardMaterial3D.new()
	draw_mat.albedo_color = Color.WHITE
	draw_mat.albedo_texture = texture
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh.material = draw_mat
	trail.draw_pass_1 = mesh
	trail.amount = MAX_PARTICLES
	trail.lifetime = PARTICLE_LIFETIME
	trail.local_coords = false
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# World-space particles can trail over30m at max speed and span two lane
	# changes. Keep that finite swept region visible after the emitter moves.
	trail.visibility_aabb = AABB(Vector3(-8, -3, -2), Vector3(16, 8, 36))
	trail.position = Vector3(0, 0.5, 0.6)
	return trail


static func _particle_texture(trail_id: String) -> Texture2D:
	if not PARTICLE_PATHS.has(trail_id):
		return null
	if _particle_textures.has(trail_id):
		return _particle_textures[trail_id] as Texture2D
	var texture := load(String(PARTICLE_PATHS[trail_id])) as Texture2D
	if texture == null:
		return null
	# Catalog-constrained keys bound this cache to four small textures.
	_particle_textures[trail_id] = texture
	return texture


static func _rainbow_ramp() -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.25, 0.32))
	gradient.set_color(1, Color(0.45, 0.35, 1.0))
	gradient.add_point(0.17, Color(1.0, 0.64, 0.18))
	gradient.add_point(0.34, Color(1.0, 0.92, 0.32))
	gradient.add_point(0.51, Color(0.25, 0.88, 0.52))
	gradient.add_point(0.68, Color(0.25, 0.78, 1.0))
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture
