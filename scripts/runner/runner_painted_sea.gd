class_name RunnerPaintedSea
extends MeshInstance3D
## One persistent, collision-free water surface beneath the runner's snow shelf.
## World-space paint stays fixed while the plane follows the infinite course.
## The owner creates this before InitialVisualWarmup and drives both updates.

const SURFACE_SHADER: Shader = preload("res://assets/art/runner/materials/runner_painted_sea_v1.gdshader")
const WATER_TEXTURE: String = "res://assets/art/runner/textures/runner_painted_water_v1.webp"
const SEA_HEIGHT: float = -4.7
const SEA_SIZE: float = 2200.0

var _water_material: ShaderMaterial
var _water_tint: Color
var _horizon_tint: Color
var _bottom_tint: Color
var _haze_distances := Vector2(110.0, 600.0)
var _crest_tint := Vector3(0.70, 0.91, 1.0)
var _detail_weight := 0.0


func setup(environment: Dictionary) -> void:
	# Headless tests retain no texture or render resources for this decoration.
	if GameConfig.is_headless() or _water_material != null:
		return
	var plane := PlaneMesh.new()
	plane.size = Vector2(SEA_SIZE, SEA_SIZE)
	mesh = plane
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	position.y = SEA_HEIGHT
	_water_material = ShaderMaterial.new()
	_water_material.shader = SURFACE_SHADER
	if ResourceLoader.exists(WATER_TEXTURE):
		var texture := load(WATER_TEXTURE) as Texture2D
		if texture != null:
			_water_material.set_shader_parameter("painted_albedo", texture)
			_water_material.set_shader_parameter("painted_enabled", true)
	material_override = _water_material
	_water_material.set_shader_parameter("day_tile_metres", Vector2(10.0, 128.0))
	_water_material.set_shader_parameter("day_lateral_reference_metres", 80.0)
	_water_material.set_shader_parameter("day_trough_tint", Color(0.1733874951, 0.3539693131, 0.6587933568, 1.0))
	_water_material.set_shader_parameter("day_body_tint", Color(0.1617658861, 0.4084237627, 0.7555587524, 1.0))
	_water_material.set_shader_parameter("day_face_tint", Color(0.1070936283, 0.4641352836, 0.8910564644, 1.0))
	_water_material.set_shader_parameter("day_crest_tint", Color(0.68, 0.94, 1.0, 1.0))
	blend_environment(environment, 1.0)


func follow_z(player_z: float) -> void:
	position.z = player_z


func blend_environment(environment: Dictionary, weight: float) -> void:
	if _water_material == null:
		return
	var horizon: Color = environment.get("ground_horizon", Color(0.31, 0.51, 0.63))
	var bottom: Color = environment.get("ground_bottom", Color(0.10, 0.27, 0.43))
	var water: Color = environment.get("water_tint", reference_water_tint(horizon, bottom))
	# DAY gains turquoise water; the same mapping preserves darker CAVE/NIGHT
	# values and DUSK's muted violet. No light or sky resource is modified.
	var haze: Vector2 = environment.get("water_haze", Vector2(110.0, 600.0))
	var crest: Vector3 = environment.get("water_crest_tint", Vector3(0.70, 0.91, 1.0))
	var detail: float = environment.get("water_detail_weight", 0.0)
	var amount := clampf(weight, 0.0, 1.0)
	var next_water := _water_tint.lerp(water, amount)
	var next_horizon := _horizon_tint.lerp(horizon, amount)
	var next_bottom := _bottom_tint.lerp(bottom, amount)
	var next_haze := _haze_distances.lerp(haze, amount)
	var next_crest := _crest_tint.lerp(crest, amount)
	var next_detail := lerpf(_detail_weight, detail, amount)
	if next_water != _water_tint:
		_water_tint = next_water
		_water_material.set_shader_parameter("water_tint", _water_tint)
	if next_horizon != _horizon_tint:
		_horizon_tint = next_horizon
		_water_material.set_shader_parameter("horizon_tint", _horizon_tint)
	if next_bottom != _bottom_tint:
		_bottom_tint = next_bottom
		_water_material.set_shader_parameter("bottom_tint", _bottom_tint)
	if next_haze != _haze_distances:
		_haze_distances = next_haze
		_water_material.set_shader_parameter("haze_distances", _haze_distances)
	if next_crest != _crest_tint:
		_crest_tint = next_crest
		_water_material.set_shader_parameter("crest_tint", _crest_tint)
	if next_detail != _detail_weight:
		_detail_weight = next_detail
		_water_material.set_shader_parameter("day_detail_weight", _detail_weight)


static func reference_water_tint(horizon: Color, bottom: Color) -> Color:
	# Reference water is clear cyan-blue, not the old near-navy slab. Retain
	# biome-derived darkness; only ocean paint changes, never sky/fog shaders.
	var reflected := bottom.lerp(horizon, 0.72)
	return Color(reflected.r * 0.26, reflected.g * 1.08, reflected.b * 1.02)
