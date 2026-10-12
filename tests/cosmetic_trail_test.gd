extends Node
## Real movement and imported trail resources; headless setup deliberately omits
## GPU effects, so the fixture installs the production emitter under its owner.
## This tests lifecycle/configuration, never claims GPU raster acceptance.

const PREVIEW = preload("res://scripts/ui/wardrobe_outfit_preview.gd")

class RetryGame:
	extends RunnerGame
	var trail_id := ""
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _player_visual_config() -> Dictionary:
		return {"species":"emperor", "trail":trail_id}

class RetryTrack:
	extends RunnerTrack
	func reset(_seed: int, _density: float = -1.0) -> void: pass

class RetryMissions:
	extends RunnerMissions
	func begin_run() -> void: pass

var checks: Array[Dictionary] = []
var observations: Array[Dictionary] = []

func _ready() -> void:
	if not String(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("waddle-wars-trail-"):
		push_error("Trail fixture requires isolated waddle-wars-trail-* user data")
		get_tree().quit(2)
		return
	_run.call_deferred()

func _run() -> void:
	var display: Dictionary = SettingsManager.settings["display"]
	var old_quality: Variant = display.get("particle_quality", "high")
	for quality: String in ["high", "low"]:
		display["particle_quality"] = quality
		for id: String in CosmeticsDB.items_in_category("trail"):
			await _movement_case(id, quality)
	display["particle_quality"] = old_quality
	for stage_size: Vector2 in [Vector2(600, 700), Vector2(300, 400)]:
		await _preview_case(stage_size)
	await _retry_case()
	_check(TrailEffect._particle_textures.size() == 4, "All runs and previews retain only four catalog texture entries")
	_check(TrailEffect._particle_texture("not_a_catalog_item") == null and TrailEffect.create("") == null,
		"Invalid/None create no effect or cache entry")
	await get_tree().process_frame
	var output := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="): output = arg.trim_prefix("out=")
	var passed := checks.filter(func(row: Dictionary) -> bool: return row.passed).size()
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var file := FileAccess.open(output.path_join("cosmetic-trail.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"passed":passed,"total":checks.size(),"checks":checks,
			"observations":observations,"limits":"Headless real player actions and imported image/material data. GPU particle pixels and actual run appearance require the final Chrome review."}, "\t"))
	print("[cosmetic-trail] %d/%d passed" % [passed, checks.size()])
	get_tree().quit(0 if passed == checks.size() else 1)

func _movement_case(id: String, quality: String) -> void:
	var label := id + "/" + quality + ": "
	var player := RunnerPlayer.new()
	add_child(player)
	player.setup({})
	player.set_input_enabled(false)
	var trail := TrailEffect.create(id)
	player._cosmetic_trail = trail
	player.add_child(trail)
	_check(not trail.emitting, label + "countdown begins without cosmetic emission")
	_check(trail.amount == (20 if quality == "low" else 30), label + "actual quality setting respects bounded particle budget")
	var texture := TrailEffect._particle_texture(id)
	var pixels := texture.get_image()
	_check(pixels.get_size() == Vector2i(256, 256) and pixels.has_mipmaps()
		and pixels.get_pixel(0, 0).a < 0.01 and pixels.get_pixel(128, 128).a > 0.2,
		label + "actual imported art decodes with alpha and mipmaps")
	var material := trail.process_material as ParticleProcessMaterial
	var mesh := trail.draw_pass_1 as QuadMesh
	var draw_material := mesh.material as StandardMaterial3D
	_check(draw_material.albedo_texture == texture and draw_material.albedo_color == Color.WHITE
		and draw_material.vertex_color_use_as_albedo and material.hue_variation_min == 0.0
		and material.hue_variation_max == 0.0, label + "shared artwork has no second color/hue filter")
	var gradient: Gradient = (material.color_ramp as GradientTexture1D).gradient
	var neutral := true
	for color: Color in gradient.colors:
		neutral = neutral and is_equal_approx(color.r, 1) and is_equal_approx(color.g, 1) and is_equal_approx(color.b, 1)
	_check(neutral and gradient == TrailEffect.fade_gradient() and gradient.sample(0).a == 0
		and gradient.sample(0.2).a > 0.8 and gradient.sample(1).a == 0,
		label + "shared lifetime fade keeps hue and removes hard spawn/death edges")
	var material_id := material.get_instance_id()
	var mesh_id := mesh.get_instance_id()
	var node_count := player.get_child_count()
	var normal_density := 0.0
	for speed: float in [RunnerConfig.START_SPEED, RunnerConfig.MAX_SPEED]:
		for frame: int in 60:
			player.tick(1.0 / 60.0, speed)
		_check(trail.emitting and not trail.local_coords and trail.is_visible_in_tree(),
			label + "actual movement emits a visible world-space trail at %sm/s" % speed)
		# Particles per metre must stay stable as speed increases: otherwise high
		# speed either leaves large gaps or creates an increasingly dense cloud.
		var density := trail.amount * trail.amount_ratio / (trail.lifetime * speed)
		if normal_density == 0:
			normal_density = density
		else:
			_check(absf(density - normal_density) < 0.001, label + "normal/max speed maintain equal particles per metre")
	_check(material_id == trail.process_material.get_instance_id() and mesh_id == trail.draw_pass_1.get_instance_id()
		and node_count == player.get_child_count(), label + "120 movement ticks allocate no replacement particle resources/nodes")
	player.distance = 20000.0
	player.tick(1.0 / 60.0, RunnerConfig.MAX_SPEED)
	_check(trail.global_position.is_equal_approx(player.global_position + trail.position)
		and player.distance > 20000.0 and trail.global_position.z < -19999.0 and trail.emitting,
		label + "emitter follows real player after long-distance world translation")
	var ground_y := trail.global_position.y
	player.jump()
	for frame: int in 18:
		player.tick(1.0 / 60.0, RunnerConfig.MAX_SPEED)
	_check(player.state == RunnerPlayer.State.JUMP and trail.global_position.y > ground_y + 1.0
		and trail.emitting and not trail.local_coords,
		label + "accepted jump lifts source while previous particles remain world-space")
	for frame: int in 60:
		player.tick(1.0 / 60.0, RunnerConfig.MAX_SPEED)
	player.set_input_enabled(true)
	player.slide()
	player.tick(1.0 / 60.0, RunnerConfig.START_SPEED)
	_check(player.state == RunnerPlayer.State.SLIDE and trail.emitting,
		label + "accepted slide keeps emission active")
	player.move_lane(-1)
	for frame: int in 18: player.tick(1.0 / 60.0, RunnerConfig.MAX_SPEED)
	player.move_lane(1)
	for frame: int in 18: player.tick(1.0 / 60.0, RunnerConfig.MAX_SPEED)
	player.move_lane(1)
	for frame: int in 18: player.tick(1.0 / 60.0, RunnerConfig.MAX_SPEED)
	var swept := trail.visibility_aabb
	var travel := (RunnerConfig.MAX_SPEED + material.initial_velocity_max) * trail.lifetime
	_check(swept.has_point(Vector3(-RunnerConfig.LANE_WIDTH * 2, 0, travel))
		and swept.has_point(Vector3(RunnerConfig.LANE_WIDTH * 2, 2.5, travel))
		and swept.size.length() < 45.0, label + "finite culling box contains full lifetime travel, jumping and two lane changes")
	_check(trail.get_child_count() == 0 and trail.draw_passes == 1
		and trail.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		label + "single shadow-free draw pass; no per-particle scene nodes")
	observations.append({"id":id,"quality":quality,"amount":trail.amount,"lifetime":trail.lifetime,
		"glyph_width_m":mesh.size.x,"normal_particles_per_m":normal_density,
		"farthest_test_distance_m":player.distance,"swept_box_size":str(swept.size)})
	player.kill()
	player.tick(0.1, RunnerConfig.MAX_SPEED)
	_check(not trail.emitting and player.state == RunnerPlayer.State.DEAD,
		label + "death/catch does not re-enable cosmetic emission")
	var old_trail: WeakRef = weakref(trail)
	player.queue_free()
	await get_tree().process_frame
	_check(old_trail.get_ref() == null, label + "owner removal frees old emitter before next run")
	var next_trail := TrailEffect.create(id)
	add_child(next_trail)
	_check(not next_trail.emitting and next_trail.get_meta("cosmetic_id") == id,
		label + "fresh run starts clean with same equipped art and no retained emission")
	next_trail.queue_free()
	await get_tree().process_frame

func _retry_case() -> void:
	# Execute production restart(), replacing only streaming/mission work.
	# Headless intentionally skips automatic emitter construction; install the
	# same production emitter before each retry to verify ownership teardown.
	var game := RetryGame.new()
	add_child(game)
	game.track = RetryTrack.new()
	game.add_child(game.track)
	game.missions = RetryMissions.new()
	game.chaser = RunnerChaser.new()
	game.add_child(game.chaser)
	game.player = RunnerPlayer.new()
	game.add_child(game.player)
	game.player.setup({})
	var busy := SceneRouter._busy
	var presenting := SceneRouter._presenting
	SceneRouter._busy = false
	SceneRouter._presenting = false
	for id: String in CosmeticsDB.items_in_category("trail"):
		game.trail_id = id
		var old_player: WeakRef = weakref(game.player)
		var trail := TrailEffect.create(id)
		game.player._cosmetic_trail = trail
		game.player.add_child(trail)
		game.player.tick(0.1, RunnerConfig.START_SPEED)
		var old_trail: WeakRef = weakref(trail)
		game.restart()
		_check(game.player != old_player.get_ref() and game.running
			and game.player.distance == 0.0 and game._player_visual_config().trail == id,
			id + ": real Retry creates fresh player and retains requested equipped trail")
		await get_tree().process_frame
		_check(old_player.get_ref() == null and old_trail.get_ref() == null,
			id + ": real Retry releases previous player and GPU emitter")
	SceneRouter._busy = busy
	SceneRouter._presenting = presenting
	game.queue_free()
	await get_tree().process_frame

func _preview_case(stage_size: Vector2) -> void:
	var stage := PREVIEW.new()
	stage.size = stage_size
	add_child(stage)
	var image := Image.create(128, 160, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var character := ImageTexture.create_from_image(image)
	stage._on_preview_changed("test_complete_outfit", character, "ready")
	var label := "preview %s: " % stage_size
	for id: String in CosmeticsDB.items_in_category("trail"):
		stage.show_equipped({"body":"body_classic","trail":id})
		await get_tree().process_frame
		var trail := stage.trail as CPUParticles2D
		_check(trail.emitting and trail.visible and trail.amount == 12,
			label + id + " animates with unchanged twelve-particle budget")
		_check(trail.texture == TrailEffect._particle_texture(id) and trail.color_ramp == TrailEffect.fade_gradient()
			and stage.sprite.texture == character and stage.displayed_key == "test_complete_outfit",
			label + id + " uses runtime artwork/fade without replacing complete penguin illustration")
		var minimum := trail.texture.get_width() * trail.scale_amount_min
		var maximum := trail.texture.get_width() * trail.scale_amount_max
		_check(minimum >= stage_size.y * 0.0399 and maximum <= stage_size.y * 0.0601
			and maximum > stage_size.y * 0.0599 and maximum < stage.sprite.size.y * 0.10,
			label + id + " glyphs visibly enlarge to4–6%stage and remain under10%hero height")
		var emitter_id := trail.get_instance_id()
		stage.show_equipped({"body":"body_classic","trail":id})
		_check(stage.trail.get_instance_id() == emitter_id,
			label + id + " repeated selection reuses current emitter")
		_check(stage.find_children("*", "CPUParticles2D", false, false).size() == 1,
			label + id + " switching styles leaves only one preview emitter")
	var old_trail := stage.trail
	stage.show_equipped({"body":"body_classic","trail":""})
	_check(stage.trail == null and not old_trail.emitting and not old_trail.visible,
		label + "None stops and hides old particles immediately")
	await get_tree().process_frame
	_check(stage.find_children("*", "CPUParticles2D", false, false).is_empty(),
		label + "None releases preview emitter on next frame")
	stage.queue_free()
	await get_tree().process_frame

func _check(passed: bool, description: String) -> void:
	checks.append({"passed":passed,"description":description})
	if not passed: push_error(description)
