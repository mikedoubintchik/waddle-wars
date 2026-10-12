extends Node
## Project the production camera fit with the engine, not a duplicate formula.
var _failures := 0
var _checks := 0

func _ready() -> void:
	_test_imported_heights()
	_test_reviewed_reference_fit()
	for size: Vector2i in [Vector2i(540, 960), Vector2i(1080, 1920),
		Vector2i(1080, 2400), Vector2i(1200, 1600), Vector2i(960, 540),
		Vector2i(1920, 1080), Vector2i(2400, 1080), Vector2i(1600, 1200)]:
		var viewport := SubViewport.new()
		viewport.size = size
		add_child(viewport)
		var camera := Camera3D.new()
		viewport.add_child(camera)
		var portrait := size.y >= size.x
		for height: float in [0.971, 1.048]:
			for speed: float in [0.0, 0.5, 1.0]:
				var fov := (68.0 if portrait else 66.0) + speed * 8.0
				var fraction := lerpf(0.155, 0.145, speed)
				var pitch := 18.0 if portrait else 16.0
				var fit := RunnerCameraComposition.solve(height, fov, fraction, 0.84, pitch)
				camera.fov = fov
				camera.rotation.x = deg_to_rad(-pitch)
				camera.position = Vector3(0.0, fit.y, fit.x)
				var sole := camera.unproject_position(Vector3.ZERO) / Vector2(size)
				var crown := camera.unproject_position(Vector3.UP * height) / Vector2(size)
				_check(absf(sole.y - 0.84) < 0.00001, "sole anchor")
				_check(absf(sole.y - crown.y - fraction) < 0.00001, "actual vertical projection")
				_check(fit.y >= 2.95, "tunnel camera clearance %s h=%.3f" % [size, fit.y])
				for lane: int in 3:
					camera.position.x = RunnerConfig.lane_x(lane) * 0.75
					for horizon: float in [20.0, 55.0, 62.0, 70.0]:
						for edge: float in [-4.65, 4.65]:
							var world := Vector3(edge, 0.0, -horizon)
							var point := camera.unproject_position(world) / Vector2(size)
							_check(not camera.is_position_behind(world)
								and point.x >= 0.0 and point.x <= 1.0
								and point.y >= 0.0 and point.y <= 1.0,
								"all lanes visible %s lane%d %.0fm" % [size, lane, horizon])
		viewport.free()
	print("[runner_camera] %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures else 0)

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("[runner_camera] FAIL ", label)


func _test_imported_heights() -> void:
	# Production deliberately uses distinct procedural species until shared-rig
	# sockets and silhouettes pass art review. Exercise the imported-fit contract
	# under its explicit QA opt-in instead of treating that release gate as on.
	var previous := PenguinVisual.use_authored_backend_for_qa
	PenguinVisual.use_authored_backend_for_qa = true
	for species: String in HeroPenguinRig.SPECIES_PALETTES:
		var visual := PenguinVisual.new()
		add_child(visual)
		var look := CharacterLook.new()
		look.species_id = species
		look.render_role = CharacterLook.RenderRole.HERO
		visual.setup_look(look)
		var height := RunnerCameraComposition.authored_height(visual)
		print("[runner_camera] imported %s reference_height=%.6f" % [species, height])
		_check(height > 0.0, "configured imported height " + species)
		for speed: float in [0.0, 1.0]:
			var fit := RunnerCameraComposition.with_clearance(height, 68.0 + speed * 8.0,
				lerpf(0.155, 0.145, speed), 0.84, 18.0)
			_check(fit.y >= 2.95, "small species retain tunnel clearance " + species)
		visual.free()
	PenguinVisual.use_authored_backend_for_qa = previous


func _test_reviewed_reference_fit() -> void:
	# Exercise the production selection, imported rest height and actual camera
	# projection together. Legacy QA opt-in above remains a separate contract.
	for size: Vector2i in [Vector2i(960, 540), Vector2i(540, 960)]:
		var viewport := SubViewport.new()
		viewport.size = size
		add_child(viewport)
		var player := RunnerPlayer.new()
		viewport.add_child(player)
		player.setup({})
		var camera := Camera3D.new()
		viewport.add_child(camera)
		var height := RunnerCameraComposition.authored_height(player._visual)
		_check(is_equal_approx(height, 1.05), "production reviewed height " + str(size))
		var portrait := size.y >= size.x
		for speed: float in [0.0, 1.0]:
			var fov := RunnerCameraComposition.reference_fov(speed)
			var fit := RunnerCameraComposition.reference_fit(height, fov, portrait)
			camera.fov = fov
			camera.rotation.x = deg_to_rad(-fit.z)
			camera.position = Vector3(0.0, fit.y, fit.x)
			var sole := camera.unproject_position(Vector3.ZERO) / Vector2(size)
			var crown := camera.unproject_position(Vector3.UP * height) / Vector2(size)
			_check(absf(sole.y - (0.71 if portrait else 0.73)) < 0.00001,
				"reviewed reference sole placement " + str(size))
			_check(crown.y > 0.0 and crown.y < sole.y and fit.y >= 2.95,
				"reviewed silhouette remains framed above tunnel-safe camera " + str(size))
		viewport.free()
