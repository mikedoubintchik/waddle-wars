extends "res://tests/runner_life_pressure_test.gd"
## Real accepted player hits through RunnerGame, at phone portrait/landscape
## sizes and both quality extremes. This proves wiring and composition bounds;
## final rendered Chrome/native acceptance remains a separate release gate.

func _ready() -> void:
	var before_settings := SettingsManager.settings.duplicate(true)
	var before_override := SettingsManager._governor_override
	SettingsManager._governor_override = ""
	for shape: Vector2i in [Vector2i(440, 956), Vector2i(956, 440)]:
		for quality: String in ["low", "high"]:
			for reduced: bool in [false, true]:
				await _test_phone_hits(shape, quality, reduced)
	SettingsManager.settings = before_settings
	SettingsManager._governor_override = before_override
	for audio_player: AudioStreamPlayer in AudioManager._sfx_pool:
		audio_player.stop()
		audio_player.stream = null
	await get_tree().create_timer(0.1).timeout
	print("[runner_mobile_whiteout] %d/%d passed" % [passed, passed + failed])
	get_tree().quit(1 if failed else 0)

func _test_phone_hits(shape: Vector2i, quality: String, reduced: bool) -> void:
	SettingsManager.settings["display"] = {"quality_preset": quality, "particle_quality": quality}
	SettingsManager.settings["accessibility"] = {"reduced_flashing": reduced,
		"camera_shake": "off" if reduced else "full"}
	var context := "%s %s reduced=%s" % [shape, quality, reduced]
	var viewport := SubViewport.new()
	viewport.size = shape
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var game := QuietGame.new()
	viewport.add_child(game)
	game.player = RunnerPlayer.new()
	game.add_child(game.player)
	game.player.setup({})
	game.player.set_input_enabled(false)
	game.missions = RunnerMissions.new()
	var effect := Effect.new()
	game._hit_distortion = effect
	game.add_child(effect)
	effect.setup()
	effect.finish_warmup()
	game.player.hit_taken.connect(game._on_hit_taken)
	game.running = true
	game._presentation_started = true
	await get_tree().process_frame
	_check(effect._surface.get_rect().is_equal_approx(Rect2(Vector2.ZERO, Vector2(shape))),
		"whiteout covers actual phone viewport " + context)
	var hud := RunnerHUD.new()
	game.add_child(hud)
	_check(effect.layer < hud.layer, "whole-world whiteout stays below native HUD " + context)
	_check(not effect.visible, "no whiteout before damage " + context)
	var nodes := effect.get_children()
	var material := effect._effect_material
	game.player.powerups[RunnerConfig.POWERUP_SHIELD] = 3.0
	game.player.take_hit()
	game._advance_hit_distortion(1.0)
	_check(game.player.hits_left == 3 and not effect.visible,
		"absorbed damage never applies whiteout " + context)
	game.player.invulnerable_for = 0.0
	game.player.take_hit()
	game._advance_hit_distortion(1.0)
	var first := effect.haze_opacity
	_check(game.player.hits_left == 2 and effect.visible and first >= 0.30 and first <= 0.34,
		"accepted first loss visibly obscures field of view " + context)
	_check(is_equal_approx(float(material.get_shader_parameter("haze_opacity")), first),
		"actual rendered material receives whole-world whiteout " + context)
	_check((effect.motion_scale == 0.0) == reduced,
		"comfort setting removes motion without hiding fog " + context)
	game.player.take_hit()
	_check(game.player.hits_left == 2 and effect.seconds_left == 14.0,
		"rejected collision cannot extend whiteout " + context)
	game.player.invulnerable_for = 0.0
	game.player.take_hit()
	_check(is_equal_approx(effect.haze_opacity, first) and effect.seconds_left == 15.0,
		"second loss builds from existing fog without clear-frame flash " + context)
	game._advance_hit_distortion(1.0)
	_check(game.player.hits_left == 1 and effect.haze_opacity > first * 1.4
		and effect.haze_opacity < 0.50 and effect.rear_crest < 0.83,
		"second loss strengthens fog and pushes snow closer " + context)
	game._world_covered = true
	game._advance_hit_distortion(100.0)
	_check(effect.seconds_left == 14.0, "covered pause cannot consume warning " + context)
	game._world_covered = false
	game._advance_hit_distortion(10.0)
	_check(effect.haze_opacity > 0.46 and effect.seconds_left == 4.0,
		"strong whiteout still present after eleven active seconds " + context)
	game._advance_hit_distortion(3.0)
	_check(effect.haze_opacity > 0.0 and effect.haze_opacity < first,
		"warning visibly fades during final three seconds " + context)
	game._advance_hit_distortion(1.0)
	_check(not effect.visible and effect.haze_opacity == 0.0 and effect.rear_snow_alpha == 0.0,
		"all fog and snow disappear after fifteen active seconds " + context)
	_check(effect.get_children() == nodes and effect._effect_material == material,
		"repeated damage uses fixed quads and one material " + context)
	game.player.invulnerable_for = 0.0
	game.player.take_hit()
	_check(game.player.state == RunnerPlayer.State.DEAD and not effect.visible,
		"fatal loss hands off to separate catch presentation " + context)
	viewport.queue_free()
	await get_tree().process_frame
