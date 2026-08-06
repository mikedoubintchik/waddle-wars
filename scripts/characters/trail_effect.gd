class_name TrailEffect
extends GPUParticles3D
## Cosmetic trail behind a racer (snowflake / fish / aurora). Purely visual.


static func create(trail_id: String) -> TrailEffect:
	var trail := TrailEffect.new()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0.3, 1)
	mat.spread = 20.0
	mat.initial_velocity_min = 0.6
	mat.initial_velocity_max = 1.6
	mat.gravity = Vector3(0, -0.6, 0)
	mat.scale_min = 0.5
	mat.scale_max = 1.0
	var mesh: PrimitiveMesh
	var color: Color
	match trail_id:
		"trail_snowflake":
			color = Color(0.92, 0.97, 1.0, 0.9)
			var flake := QuadMesh.new()
			flake.size = Vector2(0.16, 0.16)
			mesh = flake
			mat.angular_velocity_min = -180.0
			mat.angular_velocity_max = 180.0
		"trail_fish":
			color = Color(0.55, 0.88, 0.98, 0.9)
			var fish := PrismMesh.new()
			fish.size = Vector3(0.16, 0.12, 0.2)
			mesh = fish
			mat.angular_velocity_min = -90.0
			mat.angular_velocity_max = 90.0
		"trail_aurora":
			color = Color(0.45, 0.95, 0.7, 0.75)
			var ribbon := QuadMesh.new()
			ribbon.size = Vector2(0.3, 0.1)
			mesh = ribbon
			mat.hue_variation_min = -0.25
			mat.hue_variation_max = 0.25
		_:
			return null
	mat.color = color
	trail.process_material = mat
	var draw_mat := StandardMaterial3D.new()
	draw_mat.albedo_color = color
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh.material = draw_mat
	trail.draw_pass_1 = mesh
	trail.amount = 26
	trail.lifetime = 0.9
	trail.local_coords = false
	trail.position = Vector3(0, 0.5, 0.6)
	return trail
