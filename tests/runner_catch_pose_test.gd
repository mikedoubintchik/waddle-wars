extends Node
## Real visual facade + perspective projection; no raster/performance claim.
class GameFixture:
	extends RunnerGame
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass

var passed := 0
var failed := 0
func _ready() -> void:
	var access: Dictionary = SettingsManager.settings.get("accessibility", {})
	var original: Variant = access.get("reduced_flashing", false)
	for shape: Vector2i in [Vector2i(1672,941),Vector2i(941,1672)]:
		for reduced: bool in [false,true]:
			access["reduced_flashing"] = reduced
			var viewport := SubViewport.new()
			viewport.size = shape
			viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			add_child(viewport)
			var game := GameFixture.new()
			viewport.add_child(game)
			game.player = RunnerPlayer.new()
			game.add_child(game.player)
			game.player.setup({"hat":"hat_beanie"})
			game.player.position = Vector3(0,0,-245)
			game.player.distance = 245.0
			game.player.hits_left = 0
			game.player.state = RunnerPlayer.State.DEAD
			game.player.set_input_enabled(false)
			game._camera_hero_height = RunnerCameraComposition.authored_height(game.player._visual)
			game.camera = Camera3D.new()
			game.add_child(game.camera)
			game.camera.position = Vector3(0,3,-239)
			game.camera.look_at(Vector3(0,0.65,-256))
			game.camera.fov = 74.0
			game.camera.make_current()
			game.chaser = RunnerChaser.new()
			game.add_child(game.chaser)
			game.chaser._build_intro_wave()
			game.chaser.overrun(reduced)
			var camera_start := game.camera.transform
			var root_start := game.player.transform
			var shape_start := game.player._shape.transform
			var rng_start := game._rng.state
			game._dead = true
			game._pending_results = {"score":1460}
			for frame: int in 36:
				game.player.tick(0.05,15.0)
				game._settle_camera(0.05)
				game._advance_catch(0.05)
			var tag := str(shape) + (" reduced" if reduced else " normal")
			_check(game.player.state == RunnerPlayer.State.DEAD and not game.player._input_enabled
				and game.player.hits_left == 0 and game.player.distance == 245.0, "dead authority " + tag)
			_check(game.player.transform.is_equal_approx(root_start)
				and game.player._shape.transform.is_equal_approx(shape_start), "collision/root unchanged " + tag)
			_check(game._rng.state == rng_start and is_equal_approx(game._catch_elapsed,1.8)
				and not game._pending_results.is_empty(), "timing/RNG/result boundary " + tag)
			_check(game.player._visual.visible and game.player._visual.pose == PenguinVisual.Pose.SLIDE,
				"real prone visual visible " + tag)
			if reduced:
				_check(game.camera.transform.is_equal_approx(camera_start) and game.camera.fov == 74.0,
					"reduced camera fixed " + tag)
				_check(game.player._visual.rotation.is_zero_approx(), "reduced no turn/tip " + tag)
			else:
				var forward := -game.player._visual.global_basis.z
				var portrait := shape.y >= shape.x
				_check(forward.dot(Vector3.FORWARD if portrait else Vector3.BACK) > 0.99,
					"orientation matches approved catch reference " + tag)
				if not portrait:
					var face_forward := -game.player._visual._head_anchor.global_basis.z.normalized()
					var to_camera := (game.camera.global_position - game.player._visual._head_anchor.global_position).normalized()
					_check(face_forward.dot(to_camera) > 0.995
						and game.player._visual._hat_anchor.get_child_count() > 0,
						"equipped desktop catch face aims at actual elevated camera, not horizon " + tag)
				var rect := _projected_bounds(game.player._visual,game.camera)
				var height := rect.size.y / shape.y
				var center := rect.get_center().y / shape.y
				print("[catch-pose] projection ",JSON.stringify({"shape":str(shape),"rect":str(rect),"height_fraction":height,"center_y_fraction":center}))
				_check(height >= (0.10 if portrait else 0.14) and height <= (0.15 if portrait else 0.21)
					and center >= 0.66 and center <= 0.76,
					"face/body readable below title above gauge " + tag)
				_check(Rect2(Vector2.ZERO,Vector2(shape)).encloses(rect), "whole hero in viewport " + tag)
				var coverage := _snow_coverage(game.chaser._catch_snow,rect)
				print("[catch-pose] snow coverage ",JSON.stringify({"shape":str(shape),"mean_alpha":coverage.x,"opaque_fraction":coverage.y}))
				_check(coverage.x < 0.08 and coverage.y < 0.12,
					"authored powder keeps hero readable at1.8s " + tag)
			var surround := game.chaser._catch_surround
			_check(surround.texture == RunnerHUDArt.catch_surround(shape.y > shape.x)
				and surround.modulate.a > 0.95, "orientation-specific curling snow surrounds catch " + tag)
			if not reduced:
				var body_rect := _projected_bounds(game.player._visual,game.camera)
				var wrap_coverage := _snow_coverage(surround,body_rect)
				print("[catch-pose] surround coverage ",str(wrap_coverage)," ",tag)
				if shape.y > shape.x:
					var upper_coverage := _snow_coverage(surround,Rect2(body_rect.position,
						Vector2(body_rect.size.x,body_rect.size.y * 0.5)))
					_check(wrap_coverage.y > 0.15 and wrap_coverage.y < 0.40
						and upper_coverage.x < 0.08 and upper_coverage.y < 0.12,
						"portrait snow reaches feet while head and most body remain readable " + tag)
				else:
					_check(wrap_coverage.x < 0.08 and wrap_coverage.y < 0.12,
						"desktop curling snow aperture leaves face visible " + tag)
			else:
				var fixed_position := surround.position
				game.chaser.present_overrun(0.85)
				_check(surround.position.is_equal_approx(fixed_position),
					"reduced curling snow dissolves in a fixed position " + tag)
			game.chaser.reset()
			_check(is_zero_approx(surround.modulate.a) and not game.chaser._catch_canvas.visible,
				"retry clears curling snow " + tag)
			viewport.queue_free()
			await get_tree().process_frame
	access["reduced_flashing"] = original
	print("[catch-pose] %d/%d passed" % [passed,passed+failed])
	get_tree().quit(1 if failed else 0)

func _projected_bounds(visual: Node3D,camera: Camera3D) -> Rect2:
	var points := PackedVector2Array()
	for node: Node in visual.find_children("*","MeshInstance3D",true,false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
		var bounds := mesh.mesh.get_aabb()
		for corner: int in 8:
			points.append(camera.unproject_position(mesh.global_transform * bounds.get_endpoint(corner)))
	if points.is_empty(): return Rect2()
	var rect := Rect2(points[0],Vector2.ZERO)
	for point: Vector2 in points: rect = rect.expand(point)
	return rect
## Sample the real authored alpha at the real projected body, rather than a
## nominal crest constant: irregular painted plumes can extend above that line.
func _snow_coverage(snow: TextureRect, body: Rect2) -> Vector2:
	var pixels := snow.texture.get_image()
	var alpha_sum := 0.0
	var opaque := 0
	var samples := 0
	for x: int in range(int(body.position.x),int(body.end.x),4):
		for y: int in range(int(body.position.y),int(body.end.y),4):
			var uv := (Vector2(x,y) - snow.position) / snow.size
			var alpha := 0.0
			if Rect2(Vector2.ZERO,Vector2.ONE).has_point(uv):
				alpha = pixels.get_pixel(int(uv.x*pixels.get_width()),int(uv.y*pixels.get_height())).a * snow.modulate.a
			alpha_sum += alpha
			if alpha > 0.3: opaque += 1
			samples += 1
	return Vector2(alpha_sum / maxf(samples,1.0),float(opaque) / maxf(samples,1.0))

func _check(ok: bool,label: String) -> void:
	if ok: passed += 1
	else: failed += 1
	print("[catch-pose] %s %s" % ["PASS" if ok else "FAIL",label])
