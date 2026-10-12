extends Node
## Copied to an isolated export only. Never added to the production project.
## Named routing/still staging plus bounded, on-demand scalar diagnostics.

const MENU_SCENES := {
	"main_menu": "res://scenes/menus/main_menu.tscn",
	"base_camp": "res://scenes/menus/main_menu.tscn",
	"missions": "res://scenes/menus/main_menu.tscn",
	"account": "res://scenes/menus/main_menu.tscn",
	"account_name": "res://scenes/menus/main_menu.tscn",
	"feedback": "res://scenes/menus/main_menu.tscn",
	"signin": "res://scenes/menus/main_menu.tscn",
	"customize": "res://scenes/menus/customize.tscn",
	"customize_trails": "res://scenes/menus/customize.tscn",
	"customize_insufficient": "res://scenes/menus/customize.tscn",
	"cosmetic_shop": "res://scenes/menus/cosmetic_shop.tscn",
	"cosmetic_shop_funded": "res://scenes/menus/cosmetic_shop.tscn",
	"achievements": "res://scenes/menus/achievements.tscn",
	"leaderboard": "res://scenes/menus/leaderboard.tscn",
	"credits": "res://scenes/menus/credits.tscn",
	"controls": "res://scenes/menus/controls.tscn",
	"mode_select": "res://scenes/menus/mode_select.tscn",
}
const SETTINGS := ["accessibility", "gameplay", "audio", "display", "online"]
const RUNNER_STAGES := ["runner_character_waddle", "runner_character_jump", "runner_character_slide", "runner_hud", "pause", "avalanche_catch", "results", "results_completed", "runner_jump", "runner_jump_apex", "runner_slide", "runner_ice", "avalanche_pressure_one", "avalanche_pressure_two", "avalanche_pressure_expired", "avalanche_pressure_comfort"]
const RUNNER_OUTFITS := {
	"runner_outfit_cozy": {"body":"body_classic", "hat":"hat_beanie", "goggles":"goggles_ski", "scarf":"scarf_red", "trail":"trail_snowflake"},
	"runner_outfit_explorer": {"body":"body_classic", "hat":"hat_earwarmers", "goggles":"goggles_aviator", "scarf":"scarf_rainbow", "trail":"trail_fish"},
	"runner_outfit_research": {"body":"body_classic", "hat":"hat_headset", "goggles":"goggles_ski", "scarf":"scarf_bowtie", "trail":"trail_aurora"},
	"runner_outfit_royal": {"body":"body_classic", "hat":"hat_crown", "goggles":"goggles_aviator", "scarf":"scarf_rainbow", "trail":"trail_rainbow"},
}
const TIMEOUT_MSEC := 45000
var _enabled := false
var _status := "disabled"
var _route := ""
var _error := ""
var _synthetic := ""
var _ticket := 0
var _draws := 0
var _ready_draw := 0
var _read_callback: JavaScriptObject
var _command_callback: JavaScriptObject
var _feedback: Node
var _loader: Node
var _observed_player: RunnerPlayer
var _accepted := {"jump": 0, "slide": 0}
var _last_accepted: Dictionary = {}
var _pressure_settings: Dictionary = {}
var _equipment_evidence: Dictionary = {}
var _outfit_original: Dictionary = {}
var _outfit_route := ""
var _simulated_device := ""
var _shape_power_fixture: Dictionary = {}

class LoaderStage:
	extends "res://scripts/utilities/scene_router.gd"
	func _request_threaded_load(_path: String) -> void:
		# Real production presentation at its resource-request boundary. Holding
		# only this fixture's backend is explicitly synthetic loader artwork QA.
		_loading_deadline_msec = -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	_gate("autoload_ready", {"web_feature": OS.has_feature("web")})
	if not OS.has_feature("web"):
		_gate("disabled_non_web")
		return
	var token := String(ProjectSettings.get_setting("qa/route_token", ""))
	var allowed: Variant = JavaScriptBridge.eval(
		"['127.0.0.1','localhost','[::1]'].includes(location.hostname) && "
		+ "new URLSearchParams(location.search).get('qa_token') === " + JSON.stringify(token), true)
	_gate("query_checked", {"token_length": token.length(), "allowed": allowed,
		"allowed_variant_type": typeof(allowed), "js_exists": FileAccess.file_exists("res://_qa_local/chrome_reference_bridge.js")})
	if token.is_empty() or not _query_gate_allowed(allowed):
		_gate("disabled_origin_or_token", {"token_length": token.length(), "allowed": allowed})
		return
	_enabled = true
	_status = "idle"
	var device: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('qa_device') || ''", true)
	if device is String and _set_simulated_device(device):
		get_viewport().size_changed.connect(_apply_simulated_safe_area)
	_read_callback = JavaScriptBridge.create_callback(_on_read)
	_command_callback = JavaScriptBridge.create_callback(_on_command)
	var js := FileAccess.get_file_as_string("res://_qa_local/chrome_reference_bridge.js")
	_gate("installing", {"js_bytes": js.length()})
	JavaScriptBridge.eval(js, true)
	var bridge := JavaScriptBridge.get_interface("__wwQA")
	if bridge == null:
		_gate("error_missing_js_interface")
		_fail("QA JS install produced no interface")
		return
	bridge.bind_callbacks(_read_callback, _command_callback)
	RenderingServer.frame_post_draw.connect(_on_draw)
	set_process(true)
	_gate("active")
	var initial: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('qa_route') || ''", true)
	if initial is String and not initial.is_empty():
		request_route(initial)

static func _query_gate_allowed(value: Variant) -> bool:
	# Web's JavaScriptBridge may marshal a JS boolean as Variant INT (observed
	# in Chrome), while native fixtures use BOOL. Accept only these exact true
	# representations; strings, null, floats and other integers remain denied.
	match typeof(value):
		TYPE_BOOL: return value
		TYPE_INT: return value == 1
	return false

func _set_simulated_device(name: String) -> bool:
	# Local copied QA export only, behind the origin/token gate. Never alter
	# production safe areas or claim that Chrome emulation is native evidence.
	if not _enabled or name != "iphone15promax": return false
	_simulated_device = name
	_apply_simulated_safe_area()
	return true

static func _simulated_phone_insets(size: Vector2) -> Vector4:
	var portrait := size.y >= size.x
	var raw := Vector4(0, 59, 0, 34) if portrait else Vector4(59, 0, 59, 21)
	var points := Vector2(430, 932) if portrait else Vector2(932, 430)
	var scaled := LayoutProfile.scale_safe_insets(raw, points, size)
	return Vector4(maxf(scaled.x, LayoutProfile.TOUCH_SAFE_FLOOR),
		maxf(scaled.y, LayoutProfile.TOUCH_SAFE_FLOOR),
		maxf(scaled.z, LayoutProfile.TOUCH_SAFE_FLOOR),
		maxf(scaled.w, LayoutProfile.TOUCH_SAFE_FLOOR))

func _apply_simulated_safe_area() -> void:
	if _enabled and _simulated_device == "iphone15promax":
		LayoutProfile.forced_insets = _simulated_phone_insets(get_viewport().get_visible_rect().size)

func _gate(phase: String, details: Dictionary = {}) -> void:
	var row := {"phase": phase, "engine_ms": Time.get_ticks_msec(), "details": details}
	print("[chrome-qa-gate] " + JSON.stringify(row))
	if OS.has_feature("web"):
		# One current scalar only, so failure stays diagnosable without history.
		JavaScriptBridge.eval("window.__wwQAGate = " + JSON.stringify(row), true)

func _on_draw() -> void:
	_draws += 1

func _process(_delta: float) -> void:
	var game := get_tree().current_scene as RunnerGame
	if game == null or game.player == null or game.player == _observed_player:
		return
	_observed_player = game.player
	# Production handlers connected at player creation, before this observer.
	game.player.jumped.connect(_on_accepted.bind("jump"))
	game.player.slid.connect(_on_accepted.bind("slide"))

func _on_accepted(kind: String) -> void:
	_accepted[kind] += 1
	_last_accepted = {"kind": kind, "engine_ms": Time.get_ticks_msec(), "pool": _audio_pool()}

func _on_read(_args: Array) -> void:
	JavaScriptBridge.eval("window.__wwQA._reply = " + JSON.stringify(snapshot()), true)

func _on_command(args: Array) -> void:
	if args.size() != 1 or not args[0] is String or String(args[0]).length() > 128:
		return
	var command: Variant = JSON.parse_string(args[0])
	if not command is Dictionary:
		return
	match String(command.get("op", "")):
		"route": request_route(String(command.get("name", "")))
		"release":
			if _status == "ready" and get_tree().current_scene is RunnerGame:
				var game := get_tree().current_scene as RunnerGame
				if game._pause_layer == null: get_tree().paused = false
				_synthetic = "Released staged still; natural engine progression restored"
		"stop":
			_restore_outfit_fixture()
			_status = "stopped"
			get_tree().quit()

func valid_route(name: String) -> bool:
	return MENU_SCENES.has(name) or name in RUNNER_STAGES or RUNNER_OUTFITS.has(name) or name == "loader" \
		or not _equipment_route(name).is_empty() \
		or (name.begins_with("settings_") and name.trim_prefix("settings_") in SETTINGS)

func _equipment_route(name: String) -> Dictionary:
	if not name.begins_with("equipment_"): return {}
	var key := name.trim_prefix("equipment_")
	if key.begins_with("category_") and key.trim_prefix("category_") in CosmeticsDB.CATEGORIES:
		return {"category":key.trim_prefix("category_"), "category_page":true}
	if key.ends_with("_none") and key.trim_suffix("_none") in ["hat","scarf","goggles","trail"]:
		return {"category":key.trim_suffix("_none"),"item_id":"", "none":true}
	var item := CosmeticsDB.get_item(key)
	if not item.is_empty(): return {"category":item["category"],"item_id":key,"none":false}
	return {}

func request_route(name: String) -> bool:
	if not _enabled or not valid_route(name) or _status == "routing":
		return false
	_restore_outfit_fixture()
	_ticket += 1
	_route = name
	_status = "routing"
	_error = ""
	_synthetic = ""
	_equipment_evidence.clear()
	_shape_power_fixture.clear()
	_route_to.call_deferred(name, _ticket)
	return true

func _offline_fixture_ready() -> bool:
	if not OS.has_feature("web"): return false
	return _query_gate_allowed(JavaScriptBridge.eval(
		"!!window.__wwQAOffline && window.__wwQAOffline.mode === 'offline_visual_qa' && "
		+ "window.__wwQAOffline.remote_connections_allowed === false && "
		+ "!!window.__ww_auth && window.__ww_auth.signedIn === false", true))

func _begin_outfit_fixture(name: String) -> bool:
	# Additional protection for owned/equipped fixture mutation. The general
	# route gate already verified localhost and the exact query token.
	if not _enabled or not RUNNER_OUTFITS.has(name) or not _offline_fixture_ready() \
			or not bool(ProjectSettings.get_setting("application/config/use_custom_user_dir", false)) \
			or not String(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("waddle-chrome-reference-"):
		return false
	if not SaveManager.data.get("equipped", {}) is Dictionary \
			or not SaveManager.data.get("unlocked_cosmetics", []) is Array:
		return false
	_restore_outfit_fixture()
	for key: String in ["equipped", "unlocked_cosmetics"]:
		_outfit_original[key] = {"present":SaveManager.data.has(key),
			"value":SaveManager.data.get(key, null)}
	_outfit_original = _outfit_original.duplicate(true)
	var owned: Array = SaveManager.data.get("unlocked_cosmetics", []).duplicate()
	var look: Dictionary = RUNNER_OUTFITS[name].duplicate(true)
	for id: String in look.values():
		if not id in owned: owned.append(id)
	# Do not invoke purchase/equip APIs or generate wallet events. Only this
	# copied offline QA profile is seeded, before the real player is created.
	SaveManager.data["unlocked_cosmetics"] = owned
	SaveManager.data["equipped"] = look
	_outfit_route = name
	return true

func _restore_outfit_fixture() -> void:
	if _outfit_original.is_empty(): return
	for key: String in _outfit_original:
		var original: Dictionary = _outfit_original[key]
		if original.present: SaveManager.data[key] = original.value
		else: SaveManager.data.erase(key)
	_outfit_original.clear()
	_outfit_route = ""
	# A real runner tick may have autosaved while the fixture was active.
	# Persist the restored keys before stop/exit, in this verified QA identity.
	SaveManager.save_now()

func _exit_tree() -> void:
	if is_instance_valid(SaveManager): _restore_outfit_fixture()

func _route_to(name: String, ticket: int) -> void:
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	for key: String in _pressure_settings:
		SettingsManager.set_setting("accessibility", key, _pressure_settings[key])
	_pressure_settings.clear()
	# Let normal boot/title finish before entering a real production route.
	while SceneRouter.is_busy() or SceneRouter.is_presenting() or get_tree().current_scene == null \
			or get_tree().current_scene.scene_file_path == "res://scenes/ui/main.tscn":
		if not _before_deadline(deadline, ticket): return
		await get_tree().process_frame
	if not await _await_startup_reveal(deadline, ticket): return
	if is_instance_valid(_feedback):
		_feedback.call("_close")
		_feedback = null
	if is_instance_valid(_loader):
		_loader.queue_free()
		_loader = null
	var old_game := get_tree().current_scene as RunnerGame
	if old_game != null and old_game._pause_layer != null: old_game._close_pause()
	get_tree().paused = false
	var runner := name in RUNNER_STAGES or RUNNER_OUTFITS.has(name)
	if RUNNER_OUTFITS.has(name) and not _begin_outfit_fixture(name):
		_fail("Outfit fixture requires an isolated offline QA profile")
		return
	var path := Game.SCENE_RUNNER if runner else String(MENU_SCENES.get(name, Game.SCENE_SETTINGS))
	if not _equipment_route(name).is_empty(): path = "res://scenes/menus/customize.tscn"
	if name == "loader": path = Game.SCENE_MAIN_MENU
	if get_tree().current_scene.scene_file_path != path:
		SceneRouter.go_to(path)
		while get_tree().current_scene == null or get_tree().current_scene.scene_file_path != path \
				or SceneRouter.is_busy() or SceneRouter.is_presenting():
			if not _before_deadline(deadline, ticket): return
			await get_tree().process_frame
	var scene := get_tree().current_scene
	if scene.has_method("_dismiss_save_prompt"): scene.call("_dismiss_save_prompt")
	if runner:
		await _stage_runner(scene as RunnerGame, name, deadline, ticket)
	elif name == "loader":
		_loader = LoaderStage.new()
		add_child(_loader)
		_loader.call("go_to", Game.SCENE_RUNNER)
		_synthetic = "Real SceneRouter loader held at resource-request boundary; no resource load/performance claim"
	elif name.begins_with("settings_"):
		scene.call("restore_navigation_state", {"category": name.trim_prefix("settings_")})
	elif name == "cosmetic_shop_funded":
		# Explicit isolated-save fixture; the origin/token gate and export's
		# offline transport fence remain mandatory. No real profile is copied.
		SaveManager.data = SaveManager.default_save()
		SaveManager.set_value("fish", 10000)
		Progression.fish_changed.emit(Progression.get_fish())
		Progression.cosmetics_changed.emit()
		_synthetic = "Isolated QA save reset with 10,000 synthetic fish; real shop UI and local unlock path, all remote transport blocked"
	elif name in ["main_menu", "base_camp", "missions", "account", "account_name", "feedback", "signin"]:
		var panel := "home" if name in ["main_menu", "feedback", "signin"] else ("account" if name == "account_name" else name)
		if scene.has_method("_dismiss_name_prompt"): scene.call("_dismiss_name_prompt")
		scene.call("restore_navigation_state", {"panel": panel})
		if name == "account_name":
			scene.call("_show_name_prompt")
			_synthetic = "Real name editor opened; no name submitted or account mutation"
		if name == "signin":
			scene.call("_show_save_prompt")
			_synthetic = "Real save reminder opened for design capture; no sign-in request sent"
		if name == "feedback":
			_feedback = preload("res://scripts/ui/feedback_form.gd").new()
			_feedback.call("open", scene)
	elif not _equipment_route(name).is_empty():
		var requested := _equipment_route(name)
		var saved_before: Dictionary = Progression.equipped().duplicate(true)
		scene.call("_reset_try_on")
		scene.call("_select_category",requested["category"])
		if requested.has("item_id"): scene.call("_select_item",requested["item_id"])
		_equipment_evidence = requested.duplicate(true)
		_equipment_evidence["item_id"] = String(scene.get("_selected_id"))
		_equipment_evidence["temporary_preview"] = true
		_equipment_evidence["saved_equipment_unchanged"] = saved_before == Progression.equipped()
		var library: Node = scene.get("_outfit_library")
		while library.get("state") == "loading":
			if not _before_deadline(deadline,ticket): return
			await get_tree().process_frame
		if library.get("state") != "ready":
			_fail("Requested equipment outfit artwork unavailable")
			return
		_equipment_evidence["outfit_state"] = library.get("state")
		_equipment_evidence["outfit_key"] = library.get("requested_key")
		_synthetic = "Real equipment category and temporary item preview; no purchase, equip or currency mutation"
	elif name in ["customize", "customize_trails", "customize_insufficient"]:
		scene.call("_select_category", "trail" if name == "customize_trails" else "body")
		if name == "customize_insufficient":
			scene.call("_select_item", "body_chinstrap")
			_synthetic = "Unowned Chinstrap preview selected; no purchase, equip, or currency mutation"
	if _status == "error": return
	# Real submitted draws plus wall time; no readback or force_draw.
	var start_draw := _draws
	var settle_until := Time.get_ticks_msec() + 900
	while _draws - start_draw < 8 or Time.get_ticks_msec() < settle_until:
		if not _before_deadline(deadline, ticket): return
		await get_tree().process_frame
	_ready_draw = _draws
	_status = "ready"

func _stage_runner(game: RunnerGame, name: String, deadline: int, ticket: int) -> void:
	# Normal production renderer and real action timing. These extra reference
	# views omit synthetic power grants; they never replace or pose the model.
	var character_review := name.begins_with("runner_character_")
	if character_review:
		name = {"runner_character_waddle": "runner_hud", "runner_character_jump": "runner_jump_apex",
			"runner_character_slide": "runner_slide"}[name]
	if RUNNER_OUTFITS.has(name) or game._dead or game.elapsed > 0.5:
		game.restart()
	while not game.running or not game._presentation_started:
		if not _before_deadline(deadline, ticket): return
		await get_tree().process_frame
	if RUNNER_OUTFITS.has(name):
		await _stage_outfit(game, name, deadline, ticket)
		return
	if name.begins_with("avalanche_pressure_"):
		await _stage_pressure(game, name, deadline, ticket)
		return
	if name == "runner_ice":
		await _stage_ice(game, deadline, ticket)
		return
	if name in ["runner_hud", "runner_jump", "runner_jump_apex", "runner_slide", "pause"]:
		var shape_only: bool = character_review or name == "runner_hud" and (ProjectSettings.get_setting("qa/hero_shape_enabled", false) == true or ProjectSettings.get_setting("qa/hero_motion_enabled", false) == true)
		# Gate 1 needs an unobscured shape. Keep normal movement/camera/lighting,
		# but do not create the synthetic magnet/shield/double-fish celebration.
		# Other gallery routes retain their original power-up presentation fixture.
		if not shape_only:
			for id: StringName in RunnerConfig.POWERUP_IDS: game.player.grant_powerup(id)
		elif not game.player.powerups.is_empty():
			_fail("Shape review requires a fresh runner without active power-ups")
			return
		var start := game.elapsed
		while game.elapsed - start < 2.25 and not game._dead:
			if not _before_deadline(deadline, ticket): return
			await get_tree().process_frame
			if shape_only and not game.player.powerups.is_empty():
				_fail("Natural power-up pickup obscured the shape fixture; no capture accepted")
				return
		if game._dead:
			_fail("Natural collision ended run before HUD stage")
			return
		if name == "pause":
			game._toggle_pause()
		elif name in ["runner_jump", "runner_jump_apex", "runner_slide"]:
			if name.begins_with("runner_jump"): game.player.jump()
			else: game.player.slide()
			var action_elapsed := game.elapsed
			var sample_time := RunnerConfig.JUMP_SPEED / RunnerConfig.GRAVITY if name == "runner_jump_apex" else 0.16
			while game.elapsed - action_elapsed < sample_time:
				if not _before_deadline(deadline, ticket): return
				await get_tree().process_frame
			get_tree().paused = true
		else:
			get_tree().paused = true
		if shape_only:
			var ribbon_accumulator := game.vfx._ribbon_acc if game.vfx != null else 0.0
			if not is_zero_approx(ribbon_accumulator):
				_fail("Shape review retained power-up ribbon effects")
				return
			_shape_power_fixture = {"synthetic_grants_skipped": true, "active_powerups_at_freeze": game.player.powerups.duplicate(),
				"power_ribbon_accumulator": ribbon_accumulator, "natural_powerup_seen": false,
				"effects_cleared": false, "ordinary_movement_camera_lighting_preserved": true}
			_synthetic = "Shape gate: synthetic power grants skipped; no magnet or power-up ribbons; real movement/camera/lighting preserved, then tree paused"
		else:
			_synthetic = "Three synthetic power grants; real movement/timers, then tree paused for Chrome still"
		if name in ["runner_jump", "runner_jump_apex", "runner_slide"]:
			_synthetic += "; one real player action method invoked, accepted signal observed"
	else:
		game.player.powerups.clear()
		var start := game.elapsed
		while game.elapsed - start < 2.25 and not game._dead:
			if not _before_deadline(deadline, ticket): return
			await get_tree().process_frame
		if game._dead:
			_fail("Natural collision ended run before catch stage")
			return
		for hit: int in 3:
			game.player.invulnerable_for = 0.0
			game.player.take_hit()
		var target := 1.8 if name == "avalanche_catch" else 0.0
		while (game._catch_elapsed < target if target > 0.0 else not game._world_covered):
			if not _before_deadline(deadline, ticket): return
			await get_tree().process_frame
		if name == "results_completed":
			game.hud.show_game_over({"score":int(game._score),"distance":game.player.distance,
				"fish":game.fish,"best":Progression.runner_high_score(),"is_new_best":true,
				"missions":["Collect 15 fish in one run","Run 150 m at x2 or better in one run"]})
		if name in ["results", "results_completed"]:
			var finish_at := Time.get_ticks_msec() + 1300
			while Time.get_ticks_msec() < finish_at:
				if not _before_deadline(deadline, ticket): return
				await get_tree().process_frame
		get_tree().paused = true
		_synthetic = "Three actual take_hit calls with iframes cleared; natural catch/fade timing, paused still"
		if name == "results_completed": _synthetic += "; two synthetic completed-goal descriptions in real Results UI, no progression mutation"

func _stage_outfit(game: RunnerGame, name: String, deadline: int, ticket: int) -> void:
	var start := game.elapsed
	while game.elapsed - start < 2.25 and not game._dead:
		if not _before_deadline(deadline, ticket): return
		await get_tree().process_frame
	if game._dead or game.player == null:
		_fail("Natural collision ended run before outfit stage")
		return
	if not game.player.powerups.is_empty():
		_fail("Outfit stage encountered a power-up; clean movement still required")
		return
	if not _outfit_live_matches(game, name):
		_fail("Live player does not carry the requested outfit and emitting trail")
		return
	get_tree().paused = true
	_synthetic = "Temporary owned/equipped outfit in isolated offline QA profile; real RunnerGame restart and2.25s movement, no synthetic powers/hits/immunity; live scene paused for still. Original equipment/ownership restored before next route, error, stop or exit"

func _outfit_live_matches(game: RunnerGame, name: String) -> bool:
	if not RUNNER_OUTFITS.has(name) or game.player == null: return false
	var trail := game.player._cosmetic_trail
	return Progression.equipped() == RUNNER_OUTFITS[name] and trail != null \
		and String(trail.get_meta("cosmetic_id", "")) == String(RUNNER_OUTFITS[name].trail) \
		and trail.emitting and trail.is_visible_in_tree() and game.player._visual != null \
		and game.player._visual.visible and not game._world_covered

func _stage_pressure(game: RunnerGame, name: String, deadline: int, ticket: int) -> void:
	if name == "avalanche_pressure_comfort":
		_pressure_settings["camera_shake"] = SettingsManager.get_setting("accessibility", "camera_shake")
		SettingsManager.set_setting("accessibility", "camera_shake", "off")
	game.player.powerups.clear()
	var start := game.elapsed
	while game.elapsed - start < 2.25 and not game._dead:
		if not _before_deadline(deadline, ticket): return
		await get_tree().process_frame
	var hit_count := 1 if name == "avalanche_pressure_one" else 2
	for index: int in hit_count:
		game.player.invulnerable_for = 0.0
		game.player.take_hit()
	# Protect this bounded visual fixture from unrelated later collisions;
	# accepted hits and aftereffect use the real production paths and clock.
	game.player.invulnerable_for = 30.0
	var wait_seconds := 15.2 if name == "avalanche_pressure_expired" else 1.0
	var hit_time := game.elapsed
	while game.elapsed - hit_time < wait_seconds:
		if not _before_deadline(deadline, ticket): return
		await get_tree().process_frame
	# Synthetic immunity also drives the real hit-blink animation. Do not freeze
	# an arbitrary invisible blink phase into the reference comparison: let the
	# unchanged player presentation reach its next visible phase naturally.
	# Keep immunity for this isolated timing probe, never force model visibility.
	var visibility_start := game.elapsed
	while game.elapsed <= visibility_start or game.player._visual == null or not game.player._visual.visible:
		if not _before_deadline(deadline, ticket): return
		if game._dead:
			_fail("Natural collision ended run before pressure visibility settled")
			return
		await get_tree().process_frame
	get_tree().paused = true
	_synthetic = "%d real take_hit calls; %.3f seconds real active play; temporary collision immunity for isolated aftereffect observation; real blink advanced to visible phase without overriding visibility; paused still" % [hit_count, game.elapsed - hit_time]

func _stage_ice(game: RunnerGame, deadline: int, ticket: int) -> void:
	# Production generator and actual world movement, with a repeatable route.
	# No prop insertion, collision changes, camera shift, or artwork override.
	game.track.reset(20261008)
	var original_invulnerability := game.player.invulnerable_for
	var found := false
	while not found:
		if not _before_deadline(deadline, ticket):
			game.player.invulnerable_for = original_invulnerability
			return
		game.player.invulnerable_for = 1.0
		for chunk: RunnerTrack.RunnerChunk in game.track._chunks:
			for node: Node in chunk.get_children():
				if not node is Area3D: continue
				var ahead := game.player.global_position.z - (node as Node3D).global_position.z
				if ahead < 8.0 or ahead > 12.0: continue
				for child: Node in node.get_children():
					if child is MeshInstance3D and bool(child.get_meta("reference_ice_block", false)):
						found = true
		if not found:
			await get_tree().process_frame
	game.player.invulnerable_for = original_invulnerability
	# The real player tick owns blink visibility. Restoring the timer alone
	# does not undo a hidden blink phase; let normal presentation advance before
	# pausing, without writing visibility or changing the production model.
	var settle_start := game.elapsed
	while not _ice_visual_ready(game.player, game.elapsed, settle_start):
		if not _before_deadline(deadline, ticket): return
		if game._dead:
			_fail("Natural collision ended run before ice visibility settled")
			return
		await get_tree().process_frame
	get_tree().paused = true
	_synthetic = "Fixed production track seed20261008; actual movement past warmup with temporary invulnerability; original immunity restored and normal player tick settles blink; first generated ice BLOCK8–12m ahead; paused for artwork review"

static func _ice_visual_ready(player: RunnerPlayer, elapsed: float, settle_start: float) -> bool:
	return elapsed > settle_start and player.invulnerable_for <= 0.0 \
		and player._visual != null and player._visual.visible

func _ice_snapshot(game: RunnerGame) -> Dictionary:
	var hazards: Array = []
	var sea_instances := 0
	var sea_triangles := 0
	if game.track == null or game.player == null:
		return {"nearby_hazards": hazards, "sea_instances": 0, "sea_triangles_per_instance": 0}
	for chunk: RunnerTrack.RunnerChunk in game.track._chunks:
		for node: Node in chunk.get_children():
			if node is MultiMeshInstance3D and bool(node.get_meta("reference_ice_derivative", false)):
				sea_instances += node.multimesh.instance_count
				sea_triangles = node.multimesh.mesh.get_faces().size() / 3
			if not node is Area3D or not node.is_in_group(RunnerConfig.GROUP_HAZARD): continue
			var ahead := game.player.global_position.z - (node as Node3D).global_position.z
			if ahead < 0.0 or ahead > 60.0 or hazards.size() >= 12: continue
			var mesh_node: MeshInstance3D
			var collider: CollisionShape3D
			for child: Node in node.get_children():
				if child is MeshInstance3D: mesh_node = child
				if child is CollisionShape3D: collider = child
			if mesh_node == null or collider == null or not collider.shape is BoxShape3D: continue
			var bounds := mesh_node.transform * mesh_node.mesh.get_aabb()
			var size := (collider.shape as BoxShape3D).size
			var position := (node as Node3D).global_position
			hazards.append({"kind": String(node.get_meta("kind", "")),
				"ice_block": bool(mesh_node.get_meta("reference_ice_block", false)),
				"lane": int(node.get_meta("lane", -1)), "ahead_m": ahead,
				"position": [position.x, position.y, position.z],
				"collider_size": [size.x, size.y, size.z],
				"visual_bounds": [bounds.position.x, bounds.position.y, bounds.position.z,
					bounds.size.x, bounds.size.y, bounds.size.z],
				"triangles": mesh_node.mesh.get_faces().size() / 3})
	return {"nearby_hazards": hazards, "sea_instances": sea_instances,
		"sea_triangles_per_instance": sea_triangles}

func _before_deadline(deadline: int, ticket: int) -> bool:
	if ticket != _ticket: return false
	if Time.get_ticks_msec() <= deadline: return true
	_fail("Route/stage exceeded 45-second bound")
	return false

func _startup_cover_pending() -> bool:
	if not OS.has_feature("web"): return false
	return _query_gate_allowed(JavaScriptBridge.eval(
		"!!document.getElementById('ww-boot-layer') || typeof window.__wwBootReady === 'function'", true))

func _await_startup_reveal(deadline: int, ticket: int) -> bool:
	# Router idle precedes Main Menu's post-draw reveal. Do not free that scene
	# while its production coroutine still owns removal of the browser cover.
	# QA observes the real DOM state; it never hides or completes the cover.
	while true:
		if ticket != _ticket: return false
		if Time.get_ticks_msec() > deadline:
			_fail("Startup cover did not finish its production reveal before route deadline")
			return false
		if not _startup_cover_pending(): return true
		await get_tree().process_frame
	return false

func _fail(message: String) -> void:
	_restore_outfit_fixture()
	_status = "error"
	_error = message

func _audio_pool() -> Array:
	var pool: Array = []
	for player: AudioStreamPlayer in AudioManager._sfx_pool:
		if player.playing and pool.size() < 12:
			pool.append({"path": player.stream.resource_path if player.stream != null else "",
				"pitch": player.pitch_scale, "volume_db": player.volume_db})
	return pool

func _trail_snapshot(player: RunnerPlayer) -> Dictionary:
	if player == null or player._cosmetic_trail == null: return {"present":false}
	var trail := player._cosmetic_trail
	var material := trail.process_material as ParticleProcessMaterial
	var quad := trail.draw_pass_1 as QuadMesh
	var draw := quad.material as StandardMaterial3D if quad != null else null
	var bounds := trail.visibility_aabb
	return {"present":true,"id":String(trail.get_meta("cosmetic_id", "")),
		"emitting":trail.emitting,"visible":trail.is_visible_in_tree(),
		"amount":trail.amount,"amount_ratio":trail.amount_ratio,"lifetime":trail.lifetime,
		"local_coords":trail.local_coords,
		"position":[trail.global_position.x,trail.global_position.y,trail.global_position.z],
		"visibility_aabb":[bounds.position.x,bounds.position.y,bounds.position.z,bounds.size.x,bounds.size.y,bounds.size.z],
		"quad_size":[quad.size.x,quad.size.y] if quad != null else [],
		"texture":draw.albedo_texture.resource_path if draw != null and draw.albedo_texture != null else "",
		"fade_points":(material.color_ramp as GradientTexture1D).gradient.get_point_count()
			if material != null and material.color_ramp is GradientTexture1D else 0,
		"texture_cache_entries":TrailEffect._particle_textures.size()}

func snapshot() -> Dictionary:
	var viewport := get_viewport()
	var scene := get_tree().current_scene
	var master := AudioServer.get_bus_index("Master")
	var row := {"schema_version": 1, "ticket": _ticket, "route": _route,
		"status": _status, "error": _error, "synthetic_state": _synthetic,
		"engine_ms": Time.get_ticks_msec(), "submitted_frames": _draws,
		"ready_draw": _ready_draw, "settled_frames": maxi(0, _draws - _ready_draw),
		"scene": scene.scene_file_path if scene != null else "", "tree_paused": get_tree().paused,
		"viewport_disable_3d": viewport.disable_3d,
		"logical_viewport": [viewport.get_visible_rect().size.x, viewport.get_visible_rect().size.y],
		"simulated_device_safe_area": _simulated_device,
		"safe_insets": var_to_str(LayoutProfile.safe_insets_for_viewport(viewport)),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"process_frame_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphan_nodes": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"texture_bytes": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),
		"fps": Engine.get_frames_per_second(), "scale_3d": viewport.scaling_3d_scale,
		"quality": SettingsManager.get_setting("display", "quality_preset"),
		"governor_ready": SettingsManager._governor_target_ready,
		"audio": {"master_bus_muted": AudioServer.is_bus_mute(master),
			"master_bus_db": AudioServer.get_bus_volume_db(master),
			"explicit_mute": AudioManager._muted, "master_silent": AudioManager._master_silent,
			"window_focused": AudioManager._window_focused,
			"mute_all_setting": SettingsManager.get_setting("audio", "muted"),
			"mute_unfocused_setting": SettingsManager.get_setting("audio", "mute_unfocused"),
			"accepted_actions": _accepted.duplicate(), "last_accepted": _last_accepted.duplicate(true),
			"playing_sfx": _audio_pool()}}
	if not _equipment_evidence.is_empty(): row["equipment"] = _equipment_evidence.duplicate(true)
	if scene != null and scene.scene_file_path == "res://scenes/menus/cosmetic_shop.tscn":
		for child: Node in scene.get_children():
			if not child is PremiumCosmeticShop: continue
			var shop := child as PremiumCosmeticShop
			var id := shop._selected_product_id
			var confirm: Button = null
			if shop._purchase_info != null:
				confirm = shop._purchase_info.find_child("ConfirmFishPurchase", true, false) as Button
			row["shop"] = {"selected_product":id, "fish":Progression.get_fish(),
				"quote":shop._fish_quote(id), "confirmation_open":shop._purchase_info != null,
				"confirmation_enabled":confirm != null and not confirm.disabled,
				"action_label":(shop._fish_buttons[id] as Button).text,
				"status_label":shop._status_label.text}
	if scene is RunnerGame:
		var game := scene as RunnerGame
		if not _shape_power_fixture.is_empty():
			row["shape_power_fixture"] = _shape_power_fixture.duplicate(true)
		row["runner"] = {"running": game.running, "dead": game._dead, "covered": game._world_covered,
			"root_visible": game.visible, "elapsed": game.elapsed, "catch_elapsed": game._catch_elapsed,
			"distance": game.player.distance if game.player != null else 0.0,
			"hits_left": game.player.hits_left if game.player != null else 0,
			"invulnerable_for": game.player.invulnerable_for if game.player != null else 0.0,
			"visual_visible": game.player._visual.visible if game.player != null and game.player._visual != null else false,
			"powerups": game.player.powerups.duplicate() if game.player != null else {},
			"state": int(game.player.state) if game.player != null else -1}
		row["runner"]["equipped"] = Progression.equipped()
		if game.player != null and game.player._visual != null:
			row["reviewed_penguin"] = game.player._visual.reviewed_runner_snapshot()
		if game._painted_sea != null and game._painted_sea._water_material != null:
			var water := game._painted_sea._water_material
			row["reviewed_water"] = {"detail_weight":water.get_shader_parameter("day_detail_weight"),
				"shader":water.shader.resource_path, "water_tint":str(water.get_shader_parameter("water_tint")),
				"day_tile_metres":str(water.get_shader_parameter("day_tile_metres")),
				"day_lateral_reference_metres":water.get_shader_parameter("day_lateral_reference_metres")}

		row["cosmetic_trail"] = _trail_snapshot(game.player)
		if not _outfit_original.is_empty():
			row["runner_outfit"] = {"route":_outfit_route,
				"requested":RUNNER_OUTFITS.get(_outfit_route, {}).duplicate(true),
				"temporary_fixture":true, "restore_pending":true}
		if game.camera != null and game.player != null:
			row["camera"] = {"position": [game.camera.global_position.x, game.camera.global_position.y, game.camera.global_position.z],
				"player_position": [game.player.global_position.x, game.player.global_position.y, game.player.global_position.z],
				"fov": game.camera.fov, "pitch_degrees": game.camera.rotation_degrees.x,
				"follow_z": game._camera_follow_z}
		if game._hit_distortion != null:
			row["avalanche_pressure"] = {"seconds_left":game._hit_distortion.seconds_left,
				"lost_lives":game._hit_distortion.lost_lives, "active_seconds":game._hit_distortion.active_seconds,
				"strength":game._hit_distortion.strength, "motion_scale":game._hit_distortion.motion_scale,
				"haze_opacity":game._hit_distortion.haze_opacity,
				"rear_snow_alpha":game._hit_distortion.rear_snow_alpha,
				"rear_crest":game._hit_distortion.rear_crest,
				"visible":game._hit_distortion.visible}
		row["reference_ice"] = _ice_snapshot(game)
	return row
