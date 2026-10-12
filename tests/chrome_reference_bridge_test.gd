extends Node
## Local fixture only; bridge is copied to _qa_local in isolated test/export.
const Bridge = preload("res://_qa_local/chrome_reference_bridge.gd")

class StartupCoverFixture:
	extends "res://_qa_local/chrome_reference_bridge.gd"
	var cover_pending := true
	var navigation_count := 0
	var finished := false
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_process(false)
	func _startup_cover_pending() -> bool:
		return cover_pending
	func navigate_after_reveal(deadline: int, ticket: int) -> void:
		if await _await_startup_reveal(deadline, ticket):
			navigation_count += 1
		finished = true

class OfflineOutfitFixture:
	extends "res://_qa_local/chrome_reference_bridge.gd"
	var offline := true
	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_process(false)
	func _offline_fixture_ready() -> bool:
		return offline
	func _route_to(_name: String, _ticket_value: int) -> void:
		# Isolate route-entry restoration from real scene navigation.
		pass

class OutfitTrack:
	extends RunnerTrack
	func reset(_seed: int, _density: float = -1.0) -> void: pass

class OutfitMissions:
	extends RunnerMissions
	func begin_run() -> void: pass

class OutfitGame:
	extends RunnerGame
	func _ready() -> void: pass
	func _process(delta: float) -> void:
		if running:
			elapsed += delta
			player.tick(delta, RunnerConfig.START_SPEED)
	func restart() -> void:
		super.restart()
		# Headless production setup omits GPU nodes. Install the real emitter
		# only to verify staging/ownership; no pixel acceptance is implied.
		player._cosmetic_trail = TrailEffect.create(String(_player_visual_config().trail))
		player.add_child(player._cosmetic_trail)

var passed := 0
var failed := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bridge := Bridge.new()
	add_child(bridge)
	_check(not bridge._enabled, "native launch cannot activate localhost Web bridge")
	var original_insets := LayoutProfile.forced_insets
	_check(not bridge._set_simulated_device("iphone15promax"), "disabled bridge cannot force phone safe area")
	_check(LayoutProfile.forced_insets == original_insets, "disabled phone fixture preserves safe area")
	var portrait_insets: Vector4 = Bridge._simulated_phone_insets(Vector2(800, 932.0 * 800.0 / 430.0))
	_check(is_equal_approx(portrait_insets.y, 59.0 * 800.0 / 430.0), "phone portrait notch scales into logical canvas")
	_check(is_equal_approx(portrait_insets.w, 34.0 * 800.0 / 430.0), "phone portrait home indicator scales into logical canvas")
	_check(portrait_insets.x == 24.0 and portrait_insets.z == 24.0, "phone rounded-corner minimum preserved")
	var landscape_insets: Vector4 = Bridge._simulated_phone_insets(Vector2(932, 430))
	_check(landscape_insets == Vector4(59, 24, 59, 24), "phone landscape notch rotates and preserves corner floor")
	bridge._enabled = true
	_check(not bridge._set_simulated_device("unknown"), "unknown phone profile denied")
	_check(LayoutProfile.forced_insets == original_insets, "unknown profile preserves safe area")
	_check(bridge._set_simulated_device("iphone15promax"), "explicit local fixture activates bounded phone profile")
	_check(bridge.snapshot().simulated_device_safe_area == "iphone15promax", "snapshot labels simulation honestly")
	LayoutProfile.forced_insets = original_insets
	bridge._simulated_device = ""
	bridge._enabled = false
	_check(Bridge._query_gate_allowed(true), "boolean true gate accepted")
	_check(Bridge._query_gate_allowed(1), "Chrome integer one gate accepted")
	for rejected: Variant in [false, 0, -1, 2, null, "true", "1", 1.0, {}, []]:
		_check(not Bridge._query_gate_allowed(rejected), "non-true gate representation denied: "+str(rejected))
	for key: String in ["main_menu", "base_camp", "missions", "account", "feedback", "customize",
			"signin", "customize_trails", "customize_insufficient", "cosmetic_shop", "achievements", "leaderboard", "credits", "controls", "mode_select", "loader",
			"settings_accessibility", "settings_gameplay", "settings_audio", "settings_display", "settings_online",
			"runner_hud", "runner_jump", "runner_slide", "runner_ice", "pause", "avalanche_catch", "results"]:
		_check(bridge.valid_route(key), "named route allowed: "+key)
	for key: String in ["res://arbitrary.gd", "settings_delete_account", "https://example.org", ""]:
		_check(not bridge.valid_route(key), "unknown route denied: "+key)
	for item_id: String in CosmeticsDB.ITEMS:
		_check(bridge.valid_route("equipment_"+item_id), "catalogue equipment route allowed")
	for category: String in CosmeticsDB.CATEGORIES:
		_check(bridge.valid_route("equipment_category_"+category), "category route allowed")
		if category != "body": _check(bridge.valid_route("equipment_"+category+"_none"), "valid clear state allowed")
	for key: String in ["equipment_body_none", "equipment_category_unknown", "equipment_unknown", "equipment_../../settings"]:
		_check(not bridge.valid_route(key), "unknown equipment route denied")
	_check(bridge.valid_route("results_completed"), "long completed-goal summary route allowed")
	_check(bridge.valid_route("runner_jump_apex"), "real jump apex capture route allowed")
	for pose: String in ["waddle", "jump", "slide"]:
		_check(bridge.valid_route("runner_character_" + pose), "production character comparison route allowed")
	_check(bridge.valid_route("cosmetic_shop_funded"), "explicit isolated funded shop route allowed")
	_check(not bridge.request_route("cosmetic_shop_funded"), "funded shop fixture cannot reset save while bridge disabled")
	_check(not bridge.request_route("main_menu"), "route cannot mutate while bridge disabled")
	for key: String in Bridge.RUNNER_OUTFITS:
		_check(bridge.valid_route(key), "explicit outfit route allowed: " + key)
		_check(not bridge.request_route(key) and not bridge._begin_outfit_fixture(key),
			"disabled bridge cannot seed outfit: " + key)
	for key: String in ["runner_outfit_unknown", "runner_outfit_../../save", "runner_outfit_cozy_extra"]:
		_check(not bridge.valid_route(key), "unknown outfit denied: " + key)
	var saved := SaveManager.data.duplicate(true)
	var settings := SettingsManager.settings.duplicate(true)
	var cursor := AudioManager._sfx_next
	var one: Dictionary = bridge.snapshot()
	var two: Dictionary = bridge.snapshot()
	_check(one.audio.master_bus_muted == AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "real Master bus mute read")
	_check(one.audio.mute_all_setting == SettingsManager.get_setting("audio", "muted"), "actual explicit mute setting read")
	_check(one.audio.playing_sfx.size() <= 12, "sound snapshot bounded by fixed pool")
	_check(one.audio.accepted_actions == {"jump":0,"slide":0}, "no invented accepted sound actions")
	_check(one.submitted_frames == 0 and one.ready_draw == 0, "headless read cannot claim submitted Chrome frames")
	_check(one.viewport_disable_3d == get_viewport().disable_3d, "actual viewport 3D suppression read")
	_check(SaveManager.data == saved and SettingsManager.settings == settings and AudioManager._sfx_next == cursor,
		"scalar reads preserve save/settings/audio authority")
	_check(one.size() == two.size(), "no growing scalar history")
	await _test_outfit_fixtures()
	var startup := StartupCoverFixture.new()
	add_child(startup)
	startup._ticket = 1
	startup.navigate_after_reveal.call_deferred(Time.get_ticks_msec() + 5000, 1)
	for frame: int in 3: await get_tree().process_frame
	_check(startup.navigation_count == 0 and not startup.finished,
		"idle router cannot navigate while real startup-cover observation remains pending")
	startup.cover_pending = false
	for frame: int in 2: await get_tree().process_frame
	_check(startup.navigation_count == 1 and startup.finished,
		"observed production cover removal permits exactly one navigation")
	startup.cover_pending = true
	startup.finished = false
	startup.navigate_after_reveal.call_deferred(Time.get_ticks_msec() + 5000, 1)
	await get_tree().process_frame
	startup._ticket = 2
	startup.cover_pending = false
	for frame: int in 2: await get_tree().process_frame
	_check(startup.navigation_count == 1 and startup.finished and startup._error.is_empty(),
		"superseded request cannot navigate after startup reveal")
	startup.finished = false
	startup.cover_pending = true
	startup.navigate_after_reveal.call_deferred(Time.get_ticks_msec() - 1, 2)
	for frame: int in 2: await get_tree().process_frame
	_check(startup.navigation_count == 1 and startup.finished and startup._status == "error"
		and startup._error.begins_with("Startup cover"),
		"stuck cover produces bounded explicit error without navigation")
	startup.queue_free()
	var player := RunnerPlayer.new()
	add_child(player)
	player.setup({})
	player.set_input_enabled(false)
	player.invulnerable_for = 0.06
	player.tick(0.016, 0.0)
	_check(not player._visual.visible, "real player tick enters immunity blink hidden phase")
	player.invulnerable_for = 0.0
	_check(not Bridge._ice_visual_ready(player, 1.016, 1.0), "cleared timer alone cannot accept hidden ice-stage hero")
	player.tick(0.016, 0.0)
	_check(not Bridge._ice_visual_ready(player, 1.0, 1.0), "ice stage requires actual elapsed tick before pause")
	_check(Bridge._ice_visual_ready(player, 1.016, 1.0), "normal player tick restores hero after immunity expires")
	player.queue_free()
	bridge.queue_free()
	await get_tree().process_frame
	print("[chrome_reference_bridge] DONE: %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)

func _test_outfit_fixtures() -> void:
	await get_tree().process_frame
	var identity := String(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	_check(identity.begins_with("waddle-chrome-reference-"), "outfit mutation tests use a separate QA user identity")
	if not identity.begins_with("waddle-chrome-reference-"): return
	var original := SaveManager.data.duplicate(true)
	var fixture := OfflineOutfitFixture.new()
	add_child(fixture)
	fixture._enabled = true
	fixture.offline = false
	_check(not fixture._begin_outfit_fixture("runner_outfit_cozy") and SaveManager.data == original,
		"active route gate alone cannot seed without offline transport fence")
	fixture.offline = true
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "not-the-qa-profile")
	_check(not fixture._begin_outfit_fixture("runner_outfit_cozy") and SaveManager.data == original,
		"offline bridge cannot seed a non-QA user identity")
	ProjectSettings.set_setting("application/config/custom_user_dir_name", identity)
	var samples := {"equipped":{"body":"body_adelie","hat":"","goggles":"","scarf":"scarf_red","trail":""},
		"unlocked_cosmetics":["body_classic","body_adelie","scarf_red"],"fish":321,"fixture_preserve":{"value":7}}
	SaveManager.data = samples.duplicate(true)
	for route: String in Bridge.RUNNER_OUTFITS:
		_check(fixture._begin_outfit_fixture(route), route + ": guarded fixture starts")
		var look: Dictionary = Bridge.RUNNER_OUTFITS[route]
		var all_owned := true
		for id: String in look.values(): all_owned = all_owned and Progression.is_cosmetic_unlocked(id)
		_check(Progression.equipped() == look and all_owned, route + ": actual Progression exposes exact owned loadout")
		_check(SaveManager.data.fish == 321 and SaveManager.data.fixture_preserve == samples.fixture_preserve,
			route + ": seeding does not spend fish or replace unrelated state")
		var game := OutfitGame.new()
		get_tree().root.add_child(game)
		game.track = OutfitTrack.new()
		game.add_child(game.track)
		game.missions = OutfitMissions.new()
		game.chaser = RunnerChaser.new()
		game.add_child(game.chaser)
		game.player = RunnerPlayer.new()
		game.add_child(game.player)
		game.player.setup(game._player_visual_config())
		game._presentation_started = true
		game._hit_distortion = preload("res://scripts/runner/runner_hit_distortion.gd").new()
		game.add_child(game._hit_distortion)
		fixture._ticket = 7
		fixture._status = "routing"
		var previous_scene := get_tree().current_scene
		get_tree().current_scene = game
		await fixture._stage_runner(game, route, Time.get_ticks_msec() + 7000, 7)
		_check(get_tree().paused and game.elapsed >= 2.25 and game.player.distance >= 33.75
			and game.player.powerups.is_empty() and not game._dead,
			route + ": real player advances2.25s then pauses without synthetic powers")
		_check(fixture._outfit_live_matches(game, route), route + ": actual emitting trail agrees with equipped fixture")
		var row: Dictionary = fixture.snapshot()
		_check(row.runner.equipped == look and row.cosmetic_trail.id == look.trail
			and row.cosmetic_trail.texture == TrailEffect.PARTICLE_PATHS[look.trail]
			and row.cosmetic_trail.amount <= 30 and row.cosmetic_trail.fade_points == 4
			and row.cosmetic_trail.texture_cache_entries <= 4,
			route + ": snapshot reads bounded actual trail/material/equipment values")
		_check(row.runner_outfit.temporary_fixture and row.runner_outfit.restore_pending
			and row.runner_outfit.requested == look, route + ": synthetic equipment clearly labeled")
		game._hit_distortion.lost_life(1)
		game._hit_distortion.advance(1.0, true, false, "full")
		var pressure: Dictionary = fixture.snapshot().avalanche_pressure
		_check(pressure.haze_opacity == game._hit_distortion.haze_opacity
			and pressure.rear_snow_alpha == game._hit_distortion.rear_snow_alpha
			and pressure.rear_crest == game._hit_distortion.rear_crest,
			route + ": rear-pressure diagnostics read actual presentation values")
		get_tree().paused = false
		get_tree().current_scene = previous_scene
		game.queue_free()
		await get_tree().process_frame
		fixture._status = "ready"
		var progress_before_restore := SaveManager.data.duplicate(true)
		progress_before_restore.erase("equipped")
		progress_before_restore.erase("unlocked_cosmetics")
		_check(fixture.request_route("main_menu") and SaveManager.data.equipped == samples.equipped
			and SaveManager.data.unlocked_cosmetics == samples.unlocked_cosmetics,
			route + ": next accepted route restores exact prior equipment and ownership first")
		var progress_after_restore := SaveManager.data.duplicate(true)
		progress_after_restore.erase("equipped")
		progress_after_restore.erase("unlocked_cosmetics")
		_check(progress_after_restore == progress_before_restore,
			route + ": restoration retains real runner checkpoint data from the isolated run")
		var stored: Variant = JSON.parse_string(FileAccess.get_file_as_string(SaveManager.SAVE_PATH))
		_check(stored is Dictionary and stored.equipped == samples.equipped
			and stored.unlocked_cosmetics == samples.unlocked_cosmetics,
			route + ": restored equipment is persisted only to isolated QA save")
		await get_tree().process_frame
	fixture._status = "ready"
	var before_failure := SaveManager.data.duplicate(true)
	_check(fixture._begin_outfit_fixture("runner_outfit_cozy"), "failure-restoration fixture starts")
	fixture._fail("injected QA staging failure")
	_check(SaveManager.data == before_failure and fixture._outfit_original.is_empty(),
		"stage failure restores exact keys and clears pending ownership snapshot")
	SaveManager.data = {"fish":123}
	_check(fixture._begin_outfit_fixture("runner_outfit_royal"), "missing-original-keys fixture starts")
	fixture._restore_outfit_fixture()
	fixture._restore_outfit_fixture()
	_check(SaveManager.data == {"fish":123}, "restoration preserves originally absent keys and is idempotent")
	SaveManager.data = samples.duplicate(true)
	_check(fixture._begin_outfit_fixture("runner_outfit_research"), "exit-restoration fixture starts")
	fixture.queue_free()
	await get_tree().process_frame
	_check(SaveManager.data == samples, "bridge exit restores original equipment before disposal")
	SaveManager.data = original
	SaveManager.save_now()

func _check(ok: bool, text: String) -> void:
	if ok: passed += 1
	else: failed += 1
	print("[chrome_reference_bridge] %s %s" % ["PASS" if ok else "FAIL", text])
