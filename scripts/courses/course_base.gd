class_name CourseBase
extends Node3D
## Base for all courses: main racing line + branch shortcuts, checkpoints,
## finish line, guide queries for racers/AI, environment, and pooled VFX.
## Course geometry lives in world space (course node stays at origin).

signal racer_crossed_finish(racer: Racer)

const CHECKPOINT_INTERVAL: float = 130.0

var course_id: String = ""
var main_guide: PathGuide = null
var branches: Array[Dictionary] = []  # {id, guide, entry, exit, risk}
var checkpoint_transforms: Array[Transform3D] = []
var hints: Array[Dictionary] = []  # {offset, end_offset, type, branch_id}
var kill_y: float = -40.0
var finish_offset: float = 0.0
var rng := RandomNumberGenerator.new()

var _puff_pool: Array[GPUParticles3D] = []
var _puff_next: int = 0
var _splash_pool: Array[GPUParticles3D] = []
var _splash_next: int = 0


func _ready() -> void:
	rng.seed = hash(course_id) if course_id != "" else 12345
	build_course()
	_build_vfx_pools()


## Overridden by concrete courses. Must call setup_main(), then optionally
## add_branch(), then finalize().
func build_course() -> void:
	pass


## --- Construction ----------------------------------------------------------

func setup_main(points: Array) -> void:
	var track := TrackBuilder.build_ribbon(points, "MainTrack")
	add_child(track)
	main_guide = track.get_meta("guide") as PathGuide
	finish_offset = main_guide.length - 18.0


func add_branch(points: Array, risk: float = 0.5, id_hint: String = "") -> PathGuide:
	var track := TrackBuilder.build_ribbon(points, "Branch_%s" % id_hint)
	add_child(track)
	var guide := track.get_meta("guide") as PathGuide
	var entry := float(main_guide.nearest(guide.position_at(0.0), -1)["offset"])
	var exit_offset := float(main_guide.nearest(guide.position_at(guide.length), -1)["offset"])
	branches.append({
		"id": branches.size(), "guide": guide,
		"entry": entry, "exit": exit_offset, "risk": risk, "name": id_hint,
	})
	return guide


func finalize() -> void:
	_build_checkpoints()
	_build_finish_line()
	_build_kill_floor()


## Checkpoints are progress-based (not trigger volumes) so no route — main
## line or any shortcut — can ever miss one. Transforms live on the main line
## for respawns; small visual markers show them to the player.
var checkpoint_offsets: Array[float] = []


func _build_checkpoints() -> void:
	var offset := 40.0
	while offset < finish_offset - 60.0:
		var xform := main_guide.transform_at(offset)
		checkpoint_offsets.append(offset)
		checkpoint_transforms.append(Transform3D(xform.basis, xform.origin + Vector3.UP * 0.5))
		# Visual: two slim glowing posts at the track edges.
		if not GameConfig.is_headless() and checkpoint_offsets.size() % 2 == 0:
			for side: float in [-1.0, 1.0]:
				var post := MeshInstance3D.new()
				var mesh := CylinderMesh.new()
				mesh.top_radius = 0.08
				mesh.bottom_radius = 0.12
				mesh.height = 2.4
				post.mesh = mesh
				var mat := StandardMaterial3D.new()
				mat.albedo_color = Color(0.4, 0.9, 1.0)
				mat.emission_enabled = true
				mat.emission = Color(0.3, 0.8, 1.0)
				mat.emission_energy_multiplier = 0.8
				post.material_override = mat
				post.position = xform.origin + xform.basis.x * (9.0 * side) + Vector3.UP * 1.2
				add_child(post)
		offset += CHECKPOINT_INTERVAL


## Called from get_guide: advances the racer through any checkpoints its
## main-line progress has passed.
func _advance_checkpoints(racer: Racer, progress: float) -> void:
	var next := racer.last_checkpoint_index + 1
	while next < checkpoint_offsets.size() and progress >= checkpoint_offsets[next] + 2.0:
		racer.on_checkpoint(next, checkpoint_transforms[next])
		next += 1


func _build_finish_line() -> void:
	var xform := main_guide.transform_at(finish_offset)
	var area := Area3D.new()
	area.name = "FinishLine"
	area.collision_layer = GameConfig.LAYER_TRIGGERS
	area.collision_mask = GameConfig.LAYER_RACERS
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30.0, 14.0, 3.0)
	shape.shape = box
	area.add_child(shape)
	area.transform = Transform3D(xform.basis, xform.origin + Vector3.UP * 5.0)
	area.body_entered.connect(func(body: Node3D) -> void:
		if body is Racer:
			racer_crossed_finish.emit(body))
	add_child(area)

	# Banner: two posts + crossbar + checkered panels.
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.18
	post_mesh.bottom_radius = 0.22
	post_mesh.height = 7.0
	var post_mat := TrackBuilder.prop_material(Color(0.85, 0.3, 0.3))
	for side: float in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		post.mesh = post_mesh
		post.material_override = post_mat
		post.position = xform.origin + xform.basis.x * (11.0 * side) + Vector3.UP * 3.5
		add_child(post)
	var bar := MeshInstance3D.new()
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(22.6, 1.4, 0.4)
	bar.mesh = bar_mesh
	bar.material_override = TrackBuilder.prop_material(Color(0.95, 0.96, 1.0))
	bar.transform = Transform3D(xform.basis, xform.origin + Vector3.UP * 6.6)
	add_child(bar)
	var checker_mat := StandardMaterial3D.new()
	checker_mat.albedo_color = Color(0.1, 0.1, 0.12)
	for i: int in 10:
		if i % 2 == 0:
			var square := MeshInstance3D.new()
			var square_mesh := BoxMesh.new()
			square_mesh.size = Vector3(2.26, 0.7, 0.42)
			square.mesh = square_mesh
			square.material_override = checker_mat
			square.transform = Transform3D(xform.basis,
				xform.origin + xform.basis.x * (-10.2 + float(i) * 2.26) + Vector3.UP * 6.6)
			add_child(square)


func _build_kill_floor() -> void:
	var lowest := INF
	for point: Vector3 in main_guide.points:
		lowest = minf(lowest, point.y)
	kill_y = lowest - 22.0


## --- Racer guide queries ----------------------------------------------------

## Returns {yaw, progress} where progress is main-line-equivalent distance.
## Uses per-racer cache with path hysteresis so branches work automatically
## for both the player and AI.
func get_guide(racer: Racer) -> Dictionary:
	if main_guide == null:
		return {"yaw": 0.0, "progress": 0.0}
	var cache: Dictionary = racer.guide_cache
	var current_path := int(cache.get("path", -1))
	var pos := racer.global_position

	var main_hint := int(cache.get("main_idx", -1))
	var main_res := main_guide.nearest(pos, main_hint)
	var best_path := -1
	var best_res := main_res
	var best_dist := float(main_res["distance"])
	if current_path == -1:
		best_dist -= 2.0  # hysteresis: stick with current path

	var main_progress_estimate := float(main_res["offset"])
	for branch: Dictionary in branches:
		var entry := float(branch["entry"])
		var exit_offset := float(branch["exit"])
		if main_progress_estimate < entry - 40.0 or main_progress_estimate > exit_offset + 40.0:
			continue
		var branch_id := int(branch["id"])
		var guide: PathGuide = branch["guide"]
		var hint := int(cache.get("branch_idx_%d" % branch_id, -1))
		var res := guide.nearest(pos, hint)
		cache["branch_idx_%d" % branch_id] = int(res["index"])
		var dist := float(res["distance"])
		if current_path == branch_id:
			dist -= 2.0
		if dist < best_dist:
			best_dist = dist
			best_path = branch_id
			best_res = res

	cache["main_idx"] = int(main_res["index"])
	cache["path"] = best_path
	racer.guide_cache = cache

	var result: Dictionary
	if best_path == -1:
		result = {"yaw": main_guide.yaw_at(float(main_res["offset"])), "progress": float(main_res["offset"])}
	else:
		var branch: Dictionary = branches[best_path]
		var guide: PathGuide = branch["guide"]
		var frac := float(best_res["offset"]) / maxf(guide.length, 0.001)
		var mapped := lerpf(float(branch["entry"]), float(branch["exit"]), frac)
		result = {"yaw": guide.yaw_at(float(best_res["offset"])), "progress": mapped}
	_advance_checkpoints(racer, float(result["progress"]))
	return result


## Target point ahead of the racer on its current path, for AI steering.
func ai_target(racer: Racer, lookahead: float, lateral: float = 0.0) -> Vector3:
	var cache: Dictionary = racer.guide_cache
	var path := int(cache.get("path", -1))
	if path >= 0 and path < branches.size():
		var branch: Dictionary = branches[path]
		var guide: PathGuide = branch["guide"]
		var idx := int(cache.get("branch_idx_%d" % path, 0))
		var offset := float(idx) * PathGuide.SAMPLE_SPACING + lookahead
		if offset < guide.length - 2.0:
			return guide.point_at(offset, lateral)
		# Near branch end: aim back onto the main line.
		return main_guide.point_at(float(branch["exit"]) + 12.0, lateral)
	var main_idx := int(cache.get("main_idx", 0))
	return main_guide.point_at(float(main_idx) * PathGuide.SAMPLE_SPACING + lookahead, lateral)


## Branches whose entry lies in [progress + near, progress + far].
func upcoming_branches(progress: float, near: float = 20.0, far: float = 90.0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for branch: Dictionary in branches:
		var entry := float(branch["entry"])
		if entry >= progress + near and entry <= progress + far:
			result.append(branch)
	return result


func add_hint(offset: float, type: String, end_offset: float = -1.0, branch_id: int = -1) -> void:
	hints.append({
		"offset": offset, "type": type,
		"end_offset": end_offset if end_offset > 0.0 else offset,
		"branch_id": branch_id,
	})


func hints_in_range(from_offset: float, to_offset: float, branch_id: int = -1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for hint: Dictionary in hints:
		if int(hint["branch_id"]) != branch_id:
			continue
		var o := float(hint["offset"])
		if o >= from_offset and o <= to_offset:
			result.append(hint)
	return result


func start_grid_transform(slot: int) -> Transform3D:
	var row := slot / 2
	var col := slot % 2
	var offset := 16.0 - float(row) * 3.2
	var lateral := -2.6 + float(col) * 5.2
	var xform := main_guide.transform_at(maxf(offset, 2.0))
	var origin := xform.origin + xform.basis.x * lateral + Vector3.UP * 0.6
	return Transform3D(xform.basis, origin)


## --- Environment -----------------------------------------------------------

## params: sky_top, sky_horizon, ground_color, sun_angle_deg, sun_energy,
## sun_color, fog_color, fog_density, ambient_energy, snow (bool), stars (bool)
## Optional (all backward compatible, sensible defaults):
##   sun_angle_max (deg, sun disc/halo size, default 15.0), sun_curve (0.08),
##   sky_energy (sky brightness multiplier, 1.0), exposure (tonemap, 1.05),
##   sky_contribution (ambient from sky, 1.0), fog_height + fog_height_density
##   (height fog, off unless fog_height given), glow (bool, default true;
##   auto-off when particle_quality == "low"), glow_threshold (1.1),
##   shadow_distance (140.0), clouds (bool) + cloud_color, distant_bergs
##   (bool) + berg_color/berg_count/berg_distance/berg_y.
func build_environment(params: Dictionary) -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = params.get("sky_top", Color(0.25, 0.55, 0.85))
	sky_mat.sky_horizon_color = params.get("sky_horizon", Color(0.75, 0.88, 0.98))
	sky_mat.ground_bottom_color = params.get("ground_color", Color(0.7, 0.8, 0.9))
	sky_mat.ground_horizon_color = params.get("sky_horizon", Color(0.75, 0.88, 0.98))
	sky_mat.sun_angle_max = float(params.get("sun_angle_max", 15.0))
	sky_mat.sun_curve = float(params.get("sun_curve", 0.08))
	sky_mat.sky_energy_multiplier = float(params.get("sky_energy", 1.0))
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = float(params.get("ambient_energy", 1.0))
	env.ambient_light_sky_contribution = float(params.get("sky_contribution", 1.0))
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = float(params.get("exposure", 1.05))
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_light_color = params.get("fog_color", Color(0.75, 0.86, 0.95))
	env.fog_density = float(params.get("fog_density", 0.004))
	env.fog_sky_affect = 0.2
	if params.has("fog_height"):
		env.fog_height = float(params["fog_height"])
		env.fog_height_density = float(params.get("fog_height_density", 0.08))
	var particle_quality := String(SettingsManager.get_setting("display", "particle_quality"))
	if bool(params.get("glow", true)) and particle_quality != "low" and not GameConfig.is_headless():
		# High HDR threshold: only emissive peaks (boost pads, pickups, aurora)
		# bloom — cheap on Forward Mobile, never a full-screen wash.
		env.glow_enabled = true
		env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		env.glow_hdr_threshold = float(params.get("glow_threshold", 1.1))
		env.glow_intensity = 0.45
		env.glow_bloom = 0.0
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.light_color = params.get("sun_color", Color(1.0, 0.98, 0.92))
	sun.light_energy = float(params.get("sun_energy", 1.2))
	sun.rotation_degrees = Vector3(float(params.get("sun_angle_deg", -48.0)), float(params.get("sun_yaw_deg", -30.0)), 0.0)
	var shadow_quality := String(SettingsManager.get_setting("display", "shadow_quality"))
	sun.shadow_enabled = shadow_quality != "off" and not GameConfig.is_headless()
	sun.directional_shadow_max_distance = float(params.get("shadow_distance", 140.0))
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.6
	sun.directional_shadow_fade_start = 0.85
	match shadow_quality:
		"low":
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		"medium":
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		_:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_blend_splits = true
	add_child(sun)

	if bool(params.get("snow", false)) and not GameConfig.is_headless():
		_add_snowfall()
	if bool(params.get("clouds", false)) and not GameConfig.is_headless():
		_add_clouds(params.get("cloud_color", Color(1.0, 1.0, 1.0, 0.75)))
	if bool(params.get("distant_bergs", false)) and not GameConfig.is_headless():
		_add_distant_bergs(params)


## 3-puff soft billboard cloud clusters spread high along the main line.
func _add_clouds(color: Color) -> void:
	var cloud_mat := StandardMaterial3D.new()
	cloud_mat.albedo_color = color
	cloud_mat.albedo_texture = VisualLibrary.soft_radial_texture(64, 0.85)
	cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloud_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var count := 5
	for i: int in count:
		var anchor := Vector3.ZERO
		if main_guide != null:
			anchor = main_guide.position_at(main_guide.length * (float(i) + 0.5) / float(count))
		var cluster := Node3D.new()
		cluster.name = "Cloud_%d" % i
		cluster.position = anchor + Vector3(
			rng.randf_range(-260.0, 260.0),
			rng.randf_range(110.0, 170.0),
			rng.randf_range(-120.0, 120.0))
		for j: int in 3:
			var puff := MeshInstance3D.new()
			var quad := QuadMesh.new()
			var size := rng.randf_range(55.0, 110.0)
			quad.size = Vector2(size, size * 0.55)
			puff.mesh = quad
			puff.material_override = cloud_mat
			puff.position = Vector3(
				rng.randf_range(-30.0, 30.0),
				rng.randf_range(-8.0, 8.0),
				rng.randf_range(-18.0, 18.0))
			cluster.add_child(puff)
		add_child(cluster)


## Ring of low-poly iceberg silhouettes near the horizon for depth layering.
func _add_distant_bergs(params: Dictionary) -> void:
	var count := int(params.get("berg_count", 10))
	var distance := float(params.get("berg_distance", 650.0))
	var color: Color = params.get("berg_color", Color(0.78, 0.87, 0.96))
	var center := Vector3.ZERO
	var lowest := 0.0
	if main_guide != null and main_guide.points.size() > 0:
		var sum := Vector3.ZERO
		lowest = INF
		for point: Vector3 in main_guide.points:
			sum += point
			lowest = minf(lowest, point.y)
		center = sum / float(main_guide.points.size())
	var base_y := float(params.get("berg_y", lowest - 6.0))
	var mat := VisualLibrary.rock_material(color)
	for i: int in count:
		var angle := TAU * float(i) / float(count) + rng.randf_range(-0.18, 0.18)
		var berg := MeshInstance3D.new()
		berg.mesh = VisualLibrary.berg_mesh(rng.randi())
		berg.material_override = mat
		var s := rng.randf_range(28.0, 70.0)
		berg.scale = Vector3(s * rng.randf_range(0.8, 1.3), s * rng.randf_range(0.55, 0.9), s)
		berg.position = Vector3(center.x + cos(angle) * distance, base_y, center.z + sin(angle) * distance)
		berg.rotation.y = rng.randf() * TAU
		add_child(berg)


func _add_snowfall() -> void:
	var snow := GPUParticles3D.new()
	snow.name = "Snowfall"
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(45.0, 1.0, 45.0)
	mat.direction = Vector3(0, -1, 0)
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 4.0
	mat.gravity = Vector3(0.4, -3.0, 0.2)
	mat.scale_min = 0.04
	mat.scale_max = 0.1
	snow.process_material = mat
	var flake := QuadMesh.new()
	flake.size = Vector2(0.12, 0.12)
	var flake_mat := StandardMaterial3D.new()
	flake_mat.albedo_color = Color(1, 1, 1, 0.85)
	flake_mat.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.9)
	flake_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flake_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flake_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flake.material = flake_mat
	snow.draw_pass_1 = flake
	var quality := String(SettingsManager.get_setting("display", "particle_quality"))
	snow.amount = 220 if quality == "high" else (120 if quality == "medium" else 50)
	snow.lifetime = 7.0
	snow.preprocess = 4.0
	snow.visibility_aabb = AABB(Vector3(-60, -40, -60), Vector3(120, 80, 120))
	add_child(snow)
	# Follow the active camera so snow always surrounds the player.
	var follower := Timer.new()
	follower.wait_time = 0.25
	follower.autostart = true
	follower.timeout.connect(func() -> void:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			snow.global_position = cam.global_position + Vector3.UP * 18.0)
	snow.add_child(follower)


## --- Pooled one-shot VFX ----------------------------------------------------

func _build_vfx_pools() -> void:
	if GameConfig.is_headless():
		return
	for i: int in 8:
		_puff_pool.append(_make_burst(Color(0.98, 0.99, 1.0, 0.9), 14, 0.45))
	for i: int in 6:
		_splash_pool.append(_make_burst(Color(0.55, 0.78, 0.95, 0.9), 20, 0.6))


func _make_burst(color: Color, count: int, life: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.one_shot = true
	particles.emitting = false
	particles.explosiveness = 0.95
	particles.amount = count
	particles.lifetime = life
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3.UP
	mat.spread = 70.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 5.0
	mat.gravity = Vector3(0, -9, 0)
	mat.scale_min = 0.08
	mat.scale_max = 0.22
	mat.color = color
	particles.process_material = mat
	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	mesh.radial_segments = 6
	mesh.rings = 4
	var draw_mat := StandardMaterial3D.new()
	draw_mat.albedo_color = color
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = draw_mat
	particles.draw_pass_1 = mesh
	add_child(particles)
	return particles


func spawn_land_puff(pos: Vector3) -> void:
	if _puff_pool.is_empty():
		return
	var particles := _puff_pool[_puff_next]
	_puff_next = (_puff_next + 1) % _puff_pool.size()
	particles.global_position = pos
	particles.restart()


func spawn_splash(pos: Vector3) -> void:
	if _splash_pool.is_empty():
		return
	var particles := _splash_pool[_splash_next]
	_splash_next = (_splash_next + 1) % _splash_pool.size()
	particles.global_position = pos
	particles.restart()


## --- Pickup helpers ---------------------------------------------------------

func add_fish_line(offset_start: float, count: int, spacing: float = 4.0, lateral: float = 0.0, arc_height: float = 0.0, guide: PathGuide = null) -> void:
	var g := guide if guide != null else main_guide
	for i: int in count:
		var offset := offset_start + float(i) * spacing
		if offset >= g.length:
			break
		var height := 0.8
		if arc_height > 0.0:
			var t := float(i) / maxf(float(count - 1), 1.0)
			height += sin(t * PI) * arc_height
		var fish := FishPickup.new()
		fish.position = g.point_at(offset, lateral, height)
		add_child(fish)


func add_item_row(offset: float, count: int = 4, guide: PathGuide = null) -> void:
	var g := guide if guide != null else main_guide
	var span := 10.0
	for i: int in count:
		var lateral := -span * 0.5 + span * float(i) / maxf(float(count - 1), 1.0)
		var box := ItemBox.new()
		box.position = g.point_at(offset, lateral, 1.1)
		add_child(box)


## Lateral row of collectible throwable snowballs (see SnowballPickup).
func add_snowball_row(offset: float, count: int = 3, guide: PathGuide = null) -> void:
	var g := guide if guide != null else main_guide
	if g == null or offset >= g.length:
		return
	var span := 7.0
	for i: int in count:
		var lateral := 0.0 if count <= 1 else -span * 0.5 + span * float(i) / float(count - 1)
		var ball := SnowballPickup.new()
		ball.position = g.point_at(offset, lateral, 0.55)
		add_child(ball)


## Big ground plane far below for visual grounding (ocean/ice sheet).
## Optional material overrides the flat color — e.g.
## VisualLibrary.water_material(...) for ocean or snow_material(...) for
## an ice sheet (pass subdivided = true with water so waves displace).
func add_ground_plane(y: float, color: Color, size: float = 4000.0, material: Material = null, subdivided: bool = false) -> void:
	var plane := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(size, size)
	if subdivided:
		mesh.subdivide_width = 48
		mesh.subdivide_depth = 48
	plane.mesh = mesh
	if material != null:
		plane.material_override = material
	else:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.6
		plane.material_override = mat
	plane.position = Vector3(0, y, 0)
	add_child(plane)
