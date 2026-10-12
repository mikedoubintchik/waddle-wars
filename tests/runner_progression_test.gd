extends Node
## Isolated domain, live-feed, migration and UI-binding regression.

class GameProbe:
	extends RunnerGame
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _emit_lifecycle(_event: String, _fields: Dictionary = {}) -> void: pass

var passed := 0
var failed := 0
var writes := 0
var fish_signals := 0
var cosmetic_signals := 0
var atomic_observation := true
var expected_owned: Array[String] = []

func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		push_error("runner_progression requires isolated save")
		get_tree().quit(2)
		return
	AudioManager._library = {}
	AudioManager._one_shot_cache = {}
	SaveManager.save_written.connect(func() -> void: writes += 1)
	_test_catalog_and_migration()
	_test_mission_feeds()
	_test_mission_lifecycle()
	_test_player_action_wiring()
	_test_clock_and_real_events()
	_test_bundle()
	await _test_collection_ui()
	print("[runner_progression] DONE: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _reset() -> void:
	SaveManager.data = SaveManager.default_save()
	SaveManager._dirty = false
	writes = 0

func _check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else: failed += 1
	print("[runner_progression] %s %s" % ["PASS" if ok else "FAIL", label])

func _assign(ids: Array[String], target: float = 100000.0) -> RunnerMissions:
	var slots: Array = []
	for id: String in ids:
		slots.append({"id":id,"target":target,"progress":0.0,"done":false,
			"param":"magnet","mult":2})
	SaveManager.set_value(RunnerMissions.SAVE_KEY_SET, slots)
	var missions := RunnerMissions.new()
	missions.load_state()
	missions.begin_run()
	return missions

func _test_catalog_and_migration() -> void:
	_reset()
	_check(AchievementsDB.RUNNER_ORDER.size() == 32, "32 runner trophies")
	_check(AchievementsDB.LEGACY_ORDER.size() == 14, "14 legacy meanings retained")
	for family: Dictionary in AchievementsDB.FAMILIES:
		var last := 0
		for target: int in family["targets"]:
			_check(target > last, "%s tiers strictly increase" % family["id"])
			last = target
	SaveManager.set_value("achievements", {"first_win":true,"long_waddle":true})
	SaveManager.set_value("xp", 450)
	SaveManager.set_value("stats", {"runner_best_distance":4500.0,"runner_missions_done":6,
		"fish_total":20000,"endless_best_distance":3200.0})
	Progression.evaluate_runner_achievements()
	_check(Progression.is_achievement_unlocked("first_win") and Progression.is_achievement_unlocked("long_waddle"), "earned legacy IDs preserved")
	_check(Progression.is_achievement_unlocked("runner_run_silver") and Progression.is_achievement_unlocked("runner_missions_bronze"), "known historic runner records migrate honestly")
	_check(not Progression.is_achievement_unlocked("runner_fish_bronze") and not Progression.is_achievement_unlocked("runner_time_bronze"), "wallet grants cannot invent pickup or playtime history")
	_check(Progression.runner_achievements_unlocked_count() == 3, "legacy trophies excluded from active collection count")
	var xp := Progression.get_xp()
	Progression.evaluate_runner_achievements()
	_check(Progression.get_xp() == xp and xp == 650, "new tier rewards exactly once; old XP preserved")
	SaveManager.save_now()
	SaveManager.load_save()
	_check(Progression.get_xp() == xp and Progression.is_achievement_unlocked("first_win"), "legacy and new unlocks survive disk reload")
	_check(Progression.achievement_progress("long_waddle")["current"] == 4500, "legacy distance UI accepts both historic modes")

func _test_mission_feeds() -> void:
	for tpl: Dictionary in RunnerMissions.TEMPLATES:
		_reset()
		var id := String(tpl["id"])
		var m := _assign([id,"dist_total","fish_total"])
		m._target[0] = 1.0
		match int(tpl["kind"]):
			RunnerMissions.Kind.DISTANCE_RUN, RunnerMissions.Kind.DISTANCE_TOTAL, RunnerMissions.Kind.CLEAN_RUN: m.note_distance(1.0)
			RunnerMissions.Kind.MULTIPLIER_RUN: m.note_distance(261.0)
			RunnerMissions.Kind.FISH_TOTAL, RunnerMissions.Kind.FISH_RUN: m.note_fish(1)
			RunnerMissions.Kind.JUMP_TOTAL, RunnerMissions.Kind.JUMP_RUN: m.note_jump()
			RunnerMissions.Kind.SLIDE_TOTAL, RunnerMissions.Kind.SLIDE_RUN: m.note_slide()
			RunnerMissions.Kind.LANE_TOTAL, RunnerMissions.Kind.LANE_RUN: m.note_lane_change()
			RunnerMissions.Kind.NEAR_MISS_TOTAL, RunnerMissions.Kind.NEAR_MISS_RUN: m.note_near_miss()
			RunnerMissions.Kind.POWERUP_TOTAL, RunnerMissions.Kind.POWERUP_RUN, RunnerMissions.Kind.POWERUP_SPECIFIC: m.note_powerup(&"magnet")
			RunnerMissions.Kind.RAMP_TOTAL, RunnerMissions.Kind.RAMP_RUN: m.note_ramp()
		_check(m.rows()[0]["done"] and Progression.get_stat("runner_missions_done") == 1, "real note feed completes " + id)
		_check(writes == 1, "individual completion durably flushed " + id)
		SaveManager.load_save()
		_check(Progression.get_stat("runner_missions_done") == 1, "completion counter persisted " + id)

func _test_mission_lifecycle() -> void:
	_reset()
	var m := _assign(["dist_run","fish_total","clean_run"])
	m.note_distance(40.0)
	m.note_fish(4)
	m.note_hit()
	var copy := RunnerMissions.new()
	copy.load_state(false)
	_check(copy.rows()[2]["current"] == 0.0, "hit reset immediately visible to mission menu")
	copy.begin_run()
	_check(copy.rows()[0]["current"] == 0.0 and copy.rows()[1]["current"] == 4.0, "retry resets run goals and keeps cumulative fish")
	_check(copy.rows()[0]["target"] == 100000.0, "saved targets retained through calibration")
	m = _assign(["multi_run","dist_total","fish_total"])
	m.note_distance(259.0)
	m.note_distance(261.0)
	_check(is_equal_approx(m.rows()[0]["current"], 1.0), "multiplier threshold counts crossing portion only")
	m = _assign(["dist_run","fish_run","clean_run"])
	m._last_distance = 1000.0
	m._clean_base = 0.0
	m.note_distance(1010.0)
	m.note_fish(2)
	m.note_run_ended(1010.0, 90, 500, false)
	_check(m.rows()[0]["current"] == 10.0 and m.rows()[2]["current"] == 10.0, "mid-run assignment does not inherit earlier distance/streak")
	_check(m.rows()[1]["current"] == 2.0, "end reconciliation does not retro-credit prior fish")
	_reset()
	m = _assign(["dist_run","dist_total","clean_run"], 1.0)
	m.note_distance(1.0)
	_check(m.stars() == 1 and Progression.get_fish() == 25, "three completed goals grant one star and exact fish")
	_check(Progression.get_stat("runner_missions_done") == 3 and not Progression.is_achievement_unlocked("runner_missions_bronze"), "first board records three goals; six-goal trophy waits")
	_check(writes == 1 and not SaveManager._dirty, "set, trophy, XP and currency share single complete save")
	var xp := Progression.get_xp()
	SaveManager.load_save()
	copy = RunnerMissions.new()
	copy.load_state(false)
	copy.begin_run()
	copy.note_distance(0.0)
	_check(copy.stars() == 1 and Progression.get_fish() == 25 and Progression.get_xp() == xp, "reload/retry cannot replay star rewards")

func _test_player_action_wiring() -> void:
	_reset()
	var game := GameProbe.new()
	add_child(game)
	game.player = RunnerPlayer.new()
	game.add_child(game.player)
	game.missions = _assign(["jump_run","slide_run","lane_run"],1.0)
	game.running = true
	game._presentation_started = true
	game._connect_player()
	game.player.set_input_enabled(true)
	game.player.slide()
	_check(game.missions.rows()[1]["done"], "real player slide action progresses mission through game wiring")
	game.player.jump()
	_check(game.missions.rows()[0]["done"], "real player jump action progresses mission through game wiring")
	game.player.move_lane(1)
	_check(game.missions.stars()==1 and Progression.get_stat("runner_missions_done")==3, "real lane action clears set through game wiring")
	game.running = false
	game.free()


func _test_clock_and_real_events() -> void:
	_reset()
	var game := GameProbe.new()
	add_child(game)
	game.player = RunnerPlayer.new()
	game.add_child(game.player)
	game.missions = _assign(["dist_run","fish_total","clean_run"])
	game._presentation_started = true
	game._begin_activity_tick(1.0)
	game.player.distance += 15.0
	game._commit_activity_tick()
	_check(Progression.get_stat("runner_active_seconds") == 0, "countdown excluded from active clock")
	game.running = true
	get_tree().paused = true
	game._begin_activity_tick(1.0)
	game.player.distance += 15.0
	game._commit_activity_tick()
	get_tree().paused = false
	_check(Progression.get_stat("runner_active_seconds") == 0, "paused tree excluded even if manually ticked")
	game._begin_activity_tick(0.1)
	game._commit_activity_tick()
	_check(Progression.get_stat("runner_active_seconds") == 0, "stationary simulation earns no play time")
	game._begin_activity_tick(0.1)
	game.player.distance += 1.5
	game._commit_activity_tick()
	game._commit_activity_tick()
	_check(is_equal_approx(_active_time(),0.1), "moving live frame counted once")
	game._begin_activity_tick(60.0)
	game.player.distance += 15.0
	game._commit_activity_tick()
	_check(is_equal_approx(_active_time(),0.35), "background/stalled frame cannot credit a minute")
	game._on_fish_collected(7)
	game._on_powerup_gained(&"magnet")
	game._on_near_miss()
	_check(Progression.get_stat("runner_fish_collected") == 7 and Progression.get_stat("runner_powerups_collected") == 1 and Progression.get_stat("runner_near_misses") == 1, "actual RunnerGame signals reach progression")
	Progression.add_fish(500)
	_check(Progression.get_stat("runner_fish_collected") == 7, "currency grants excluded from pickup achievements")
	game._begin_activity_tick(0.1)
	game.player.distance += 1.5
	game._on_hit_taken(0)
	game._on_death()
	game._commit_activity_tick()
	_check(is_equal_approx(_active_time(),0.45) and not SaveManager._dirty, "fatal frame credited before complete save exactly once")
	game._begin_activity_tick(2.4)
	game.player.distance += 30.0
	game._commit_activity_tick()
	_check(is_equal_approx(_active_time(),0.45), "catch/results excluded from play time")
	game.free()
	_reset()
	var leaving := GameProbe.new()
	add_child(leaving)
	leaving.player = RunnerPlayer.new()
	leaving.add_child(leaving.player)
	leaving.missions = _assign(["fish_total","dist_run","clean_run"])
	leaving.running = true
	leaving._presentation_started = true
	leaving._on_fish_collected(2)
	leaving._begin_activity_tick(0.1)
	leaving.player.distance = 2.0
	leaving._commit_activity_tick()
	leaving.free()
	_check(writes==1 and not SaveManager._dirty, "leaving live run checkpoints metrics and mission progress")
	SaveManager.load_save()
	var resumed := RunnerMissions.new()
	resumed.load_state(false)
	_check(resumed.rows()[0]["current"]==2.0 and is_equal_approx(_active_time(),0.1), "abandoned live run progress survives reload")
	_check(Progression.get_fish()==0 and Progression.runner_high_score()==0, "abandon checkpoint does not bank unfinished run wallet or score")
	_reset()
	SaveManager.set_value("stats", {"runner_active_seconds":35999.75})
	Progression.evaluate_runner_achievements()
	_check(not Progression.is_achievement_unlocked("runner_time_diamond"), "10-hour capstone never early")
	Progression.record_runner_activity(0.25, 3.0, 3.0, 3.0)
	_check(Progression.is_achievement_unlocked("runner_time_diamond") and is_equal_approx(_active_time(),36000.0), "10-hour capstone uses real seconds threshold")
	var xp := Progression.get_xp()
	Progression.record_runner_activity(0.25, 3.0, 6.0, 6.0)
	_check(Progression.get_xp() == xp, "active-time trophy reward once")

func _active_time() -> float:
	return float((SaveManager.get_value("stats", {}) as Dictionary).get("runner_active_seconds",0.0))

func _test_bundle() -> void:
	_reset()
	var ids: Array[String] = ["hat_beanie","scarf_red"]
	var price := int(CosmeticsDB.get_item(ids[0])["cost"]) + int(CosmeticsDB.get_item(ids[1])["cost"])
	SaveManager.set_value("fish", price + 100)
	var before := SaveManager.data.duplicate(true)
	_check(not Progression.try_unlock_cosmetics(["hat_beanie","missing"],price) and SaveManager.data == before, "invalid bundle atomic rejection")
	_check(not Progression.try_unlock_cosmetics(ids,-1) and SaveManager.data == before, "negative quote rejected")
	_check(not Progression.try_unlock_cosmetics(ids,price-1) and SaveManager.data == before, "stale quote cannot partially spend")
	SaveManager.set_value("fish",price-1)
	before = SaveManager.data.duplicate(true)
	_check(not Progression.try_unlock_cosmetics(ids,price) and SaveManager.data == before, "insufficient bundle balance atomic rejection")
	SaveManager.set_value("fish",price+100)
	expected_owned = ids
	fish_signals = 0
	cosmetic_signals = 0
	atomic_observation = true
	Progression.fish_changed.connect(_on_bundle_fish)
	Progression.cosmetics_changed.connect(_on_bundle_cosmetics)
	_check(Progression.try_unlock_cosmetics(["hat_beanie","hat_beanie","scarf_red"],price), "duplicate IDs charged once")
	_check(Progression.get_fish() == 100 and fish_signals == 1 and cosmetic_signals == 1 and atomic_observation and writes == 1, "bundle observers see complete durable transaction once")
	var equipped := Progression.equipped()
	_check(String(equipped.get("hat","")) == "" and String(equipped.get("scarf","")) == "", "bundle does not equip purchase")
	before = SaveManager.data.duplicate(true)
	_check(not Progression.try_unlock_cosmetics(ids,0) and SaveManager.data == before, "all-owned bundle is safe no-op")
	Progression.fish_changed.disconnect(_on_bundle_fish)
	Progression.cosmetics_changed.disconnect(_on_bundle_cosmetics)
	_reset()
	SaveManager.set_value("unlocked_cosmetics",["body_classic","hat_beanie"])
	var missing_cost := int(CosmeticsDB.get_item("scarf_red")["cost"])
	SaveManager.set_value("fish",missing_cost)
	_check(Progression.try_unlock_cosmetics(ids,missing_cost) and Progression.get_fish()==0, "partly owned bundle charges missing items only")
	_check(not Progression.spend_fish(-100) and Progression.get_fish()==0, "negative spend cannot mint fish")
	SaveManager.load_save()
	_check(Progression.is_cosmetic_unlocked("scarf_red") and Progression.get_fish()==0, "bundle ownership and balance survive disk reload")
	_reset()
	var cache_before: Dictionary = CommerceClient._cache.duplicate(true)
	var owner_before: String = CommerceClient._owner_id
	CommerceClient._owner_id = "isolated-progression-fixture"
	_check(CommerceClient._accept_entitlements({"product_ids":["cozy_expedition"],"verified_at":"synthetic-test"}), "synthetic verified-response fixture accepted")
	var ledger: Dictionary = SaveManager.get_value("commerce",{}).duplicate(true)
	var crown_cost := int(CosmeticsDB.get_item("hat_crown")["cost"])
	SaveManager.set_value("fish",crown_cost)
	_check(Progression.try_unlock_cosmetics(["hat_beanie","scarf_red","hat_crown"],crown_cost), "verified paid ownership excluded from earned bundle quote")
	_check(Progression.get_fish()==0 and not Progression.unlocked_cosmetics().has("hat_beanie") and Progression.unlocked_cosmetics().has("hat_crown"), "paid grants are not copied into earned ownership")
	_check(SaveManager.get_value("commerce",{})==ledger, "earned bundle leaves verified account ledger untouched")
	CommerceClient._cache = cache_before
	CommerceClient._owner_id = owner_before

func _on_bundle_fish(_amount: int) -> void:
	fish_signals += 1
	for id: String in expected_owned: atomic_observation = atomic_observation and Progression.is_cosmetic_unlocked(id)

func _on_bundle_cosmetics() -> void:
	cosmetic_signals += 1
	atomic_observation = atomic_observation and Progression.get_fish()==100

func _test_collection_ui() -> void:
	_reset()
	SaveManager.set_value("achievements",{"first_win":true})
	SaveManager.set_value("stats",{"runner_fish_collected":37})
	var view := load("res://scenes/menus/achievements.tscn").instantiate() as Control
	add_child(view)
	await get_tree().process_frame
	_check(view._achievement_buttons.size()==33 and view._achievement_buttons.has("first_win") and not view._achievement_buttons.has("gp_gold"), "32 live goals plus earned legacy; inactive locked goals excluded")
	_check(view._progress_for("runner_fish_bronze")=={"current":37.0,"target":750,"unit":" fish"}, "visible trophy progress bound to actual metric")
	_check((view.find_child("CollectionProgress",true,false) as Control).fraction == 0.0, "collection ring excludes legacy earnings")
	view.free()
