class_name PowerupSystem
extends Node
## Activates power-ups for any racer and runs their ongoing effects
## (magnet attraction, blizzard clouds).

var course: CourseBase = null
var _magnets: Array[Dictionary] = []  # {racer, until}
var _magnet_scan_timer: float = 0.0


func activate(racer: Racer, item_id: String) -> void:
	if racer.is_player:
		Game.used_item_this_race = true
		Progression.record_item_used(item_id)
	AudioManager.play_sfx_3d("sfx_powerup_use", racer.global_position)
	match item_id:
		"snowball":
			_fire_snowball(racer)
		"shield":
			racer.give_shield()
		"fish_frenzy":
			racer.apply_boost(2.8, 1.5)
			AudioManager.play_sfx_3d("sfx_boost", racer.global_position)
			if racer.is_player:
				var camera := get_viewport().get_camera_3d()
				if camera != null and camera.get_parent() is ChaseCamera:
					(camera.get_parent() as ChaseCamera).boost_fov_kick(9.0)
		"magnet":
			_magnets.append({"racer": racer, "until": Time.get_ticks_msec() + 6000})
		"blizzard":
			_drop_blizzard(racer)


func _fire_snowball(racer: Racer) -> void:
	var target: Racer = null
	var best_score := INF
	var forward := -racer.global_transform.basis.z
	for node: Node in get_tree().get_nodes_in_group(GameConfig.GROUP_RACERS):
		var other := node as Racer
		if other == null or other == racer or other.state == Racer.State.FINISHED:
			continue
		var to_other := other.global_position - racer.global_position
		var dist := to_other.length()
		if dist > 55.0:
			continue
		# Prefer racers ahead in a generous cone.
		var dot := forward.dot(to_other.normalized())
		if dot < 0.2:
			continue
		var score := dist * (2.0 - dot)
		if score < best_score:
			best_score = score
			target = other
	var ball := Snowball.new()
	get_parent().add_child(ball)
	ball.launch(racer, target)
	AudioManager.play_sfx_3d("sfx_throw", racer.global_position)


func _drop_blizzard(racer: Racer) -> void:
	var cloud := Area3D.new()
	cloud.collision_layer = GameConfig.LAYER_HAZARDS
	cloud.collision_mask = GameConfig.LAYER_RACERS
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 7.0
	shape.shape = sphere
	cloud.add_child(shape)
	var reduced_flash := bool(SettingsManager.get_setting("accessibility", "reduced_flashing"))
	if not GameConfig.is_headless():
		var particles := GPUParticles3D.new()
		var mat := ParticleProcessMaterial.new()
		mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		mat.emission_sphere_radius = 6.0
		mat.gravity = Vector3(0, -0.5, 0)
		mat.initial_velocity_min = 0.5
		mat.initial_velocity_max = 2.0
		mat.scale_min = 0.3
		mat.scale_max = 0.9
		mat.color = Color(0.85, 0.9, 0.98, 0.28 if reduced_flash else 0.5)
		particles.process_material = mat
		var puff := SphereMesh.new()
		puff.radius = 0.5
		puff.height = 1.0
		puff.radial_segments = 6
		puff.rings = 4
		var draw_mat := StandardMaterial3D.new()
		draw_mat.albedo_color = mat.color
		draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		puff.material = draw_mat
		particles.draw_pass_1 = puff
		particles.amount = 40
		particles.lifetime = 1.6
		cloud.add_child(particles)
	var owner_racer := racer
	cloud.body_entered.connect(func(body: Node3D) -> void:
		if body is Racer and body != owner_racer:
			(body as Racer).apply_blizzard_slip(1.2))
	var refresh := Timer.new()
	refresh.wait_time = 0.4
	refresh.autostart = true
	refresh.timeout.connect(func() -> void:
		for body: Node3D in cloud.get_overlapping_bodies():
			if body is Racer and body != owner_racer:
				(body as Racer).apply_blizzard_slip(1.2))
	cloud.add_child(refresh)
	get_parent().add_child(cloud)
	cloud.global_position = racer.global_position - (-racer.global_transform.basis.z) * 3.0
	var lifetime := get_tree().create_timer(5.0)
	lifetime.timeout.connect(func() -> void:
		if is_instance_valid(cloud):
			cloud.queue_free())


func _physics_process(delta: float) -> void:
	_magnet_scan_timer -= delta
	if _magnet_scan_timer > 0.0 or _magnets.is_empty() or course == null:
		return
	_magnet_scan_timer = 0.2
	var now := Time.get_ticks_msec()
	_magnets = _magnets.filter(func(m: Dictionary) -> bool:
		return int(m["until"]) > now and is_instance_valid(m["racer"]))
	for magnet: Dictionary in _magnets:
		var racer: Racer = magnet["racer"]
		for child: Node in course.get_children():
			if child is FishPickup:
				var fish := child as FishPickup
				if fish.global_position.distance_squared_to(racer.global_position) < 15.0 * 15.0:
					fish.attract_to(racer)
