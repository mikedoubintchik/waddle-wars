class_name RunnerPaintedClouds
extends Node3D
## Two permanent sky cards share one texture/material. The group follows only
## forward travel, keeping clouds distant without adding streamed allocations.

const CLOUD_TEXTURE := "res://assets/art/runner/textures/runner_cloud_bank_v1.webp"
var _material: StandardMaterial3D
var _color := Color.WHITE

func setup(environment: Dictionary) -> void:
	if GameConfig.is_headless() or _material != null:
		return
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.no_depth_test = false
	_material.disable_receive_shadows = true
	_material.disable_fog = true
	_material.albedo_texture = load(CLOUD_TEXTURE) as Texture2D
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_material.render_priority = -1
	for index: int in 2:
		var cloud := MeshInstance3D.new()
		cloud.name = "DistantCloudBank%d" % index
		var quad := QuadMesh.new()
		quad.size = Vector2(730.0, 243.0) if index == 0 else Vector2(420.0, 140.0)
		cloud.mesh = quad
		cloud.material_override = _material
		cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cloud.position = Vector3(-260.0, 135.0, -650.0) if index == 0 \
			else Vector3(240.0, 245.0, -670.0)
		add_child(cloud)
	blend_environment(environment, 1.0)

func follow_z(player_z: float) -> void:
	position.z = player_z

func blend_environment(environment: Dictionary, amount: float) -> void:
	if _material == null:
		return
	var sky: Color = environment.get("sky_horizon", Color.WHITE)
	var sunlight: Color = environment.get("sun", Color.WHITE)
	var target := sunlight.lerp(Color.WHITE, 0.45)
	# Keep warm dusk clouds; distant cave/night banks fade without respawning.
	target.a = clampf((sky.get_luminance() - 0.11) * 2.1, 0.0, 0.92)
	var next := _color.lerp(target, clampf(amount, 0.0, 1.0))
	if next != _color:
		_color = next
		_material.albedo_color = next
