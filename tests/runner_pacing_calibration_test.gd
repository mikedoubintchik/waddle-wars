extends Node
## Real mission model: pacing, board ownership and grandfathered progression.
var checks := 0
var failures := 0

func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir",false):
		get_tree().quit(2)
		return
	AudioManager._library = {}
	AudioManager._one_shot_cache = {}
	_test_starter_and_boundary()
	_test_stages()
	_test_migration()
	_check(AchievementsDB.get_item("runner_time_silver")["desc"] == "Run actively for 90 minutes in total.","90-minute badge does not truncate to one hour")
	_check(RunnerConfig.BIOME_LENGTH == 1800.0 and RunnerTrack.BIOME_LENGTH == RunnerConfig.BIOME_LENGTH,"course and map share 1800m boundary")
	print("[pacing-calibration] %d/%d passed" % [checks-failures,checks])
	get_tree().quit(0 if failures==0 else 1)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[pacing-calibration] FAIL " + label)

func _reset() -> void:
	SaveManager.data = SaveManager.default_save()
	SaveManager._dirty = false

func _test_starter_and_boundary() -> void:
	_reset()
	var m := RunnerMissions.new()
	m.load_state()
	m._flush_suppression_depth = 1
	m.begin_run()
	var ids := ["dist_total","fish_total","jump_total"]
	var targets := [8000.0,300.0,40.0]
	for index: int in 3:
		_check(m.rows()[index]["id"]==ids[index] and m.rows()[index]["target"]==targets[index],"predictable plain starter goal%d" % index)
		_check(not m.rows()[index]["per_run"] and m.rows()[index]["scope"]=="Across runs","starter scope explicit")
	m.note_distance(3000.0)
	m.note_fish(180)
	for n: int in 20: m.note_jump()
	m.note_run_ended(3000.0,180,0,false)
	_check(m.stars()==0 and Progression.get_stat("runner_missions_done")==0,"representative first run cannot clear starter board")
	m.begin_run()
	_check(m.rows()[0]["current"]==3000.0 and m.rows()[1]["current"]==180.0 and m.rows()[2]["current"]==20.0,"cumulative starter carries all actual work")
	m.note_distance(100000.0)
	m.note_fish(100000)
	for n: int in 1000: m.note_jump()
	var summary := m.completed_this_run()
	_check(m.stars()==1 and Progression.get_stat("runner_missions_done")==3,"arbitrarily long run cannot chain boards")
	_check(m.next_set_pending() and summary.size()==3,"Results retains exact three completed goals")
	for line: String in summary:
		_check(not line.contains("SET") and not line.contains("★"),"summary contains real goals only")
	summary.clear()
	_check(m.completed_this_run().size()==3,"caller cannot mutate authoritative Results summary")
	var xp := Progression.get_xp()
	var fish := Progression.get_fish()
	var copy := RunnerMissions.new()
	copy.load_state(false)
	_check(copy.next_set_pending() and copy.rows().all(func(row: Dictionary) -> bool: return row["done"]),"reload preserves complete board and deferred replacement")
	copy.begin_run()
	_check(not copy.next_set_pending() and copy.completed_this_run().is_empty(),"next run starts exactly one new board")
	_check(copy.rows().all(func(row: Dictionary) -> bool: return not row["done"] and row["current"]==0),"new board starts with zero progress")
	_check(Progression.get_xp()==xp and Progression.get_fish()==fish and copy.stars()==1,"reload replacement cannot replay rewards")

func _test_stages() -> void:
	for stars: int in [0,1,2,3,4,7,8,11,12,24,500]:
		for seed_value: int in 24:
			_reset()
			SaveManager.set_value(RunnerMissions.SAVE_KEY_STARS,stars)
			SaveManager.set_value(RunnerMissions.SAVE_KEY_CHANNELS,["slide","lane","near_miss","powerup","ramp"])
			var m := RunnerMissions.new()
			m._rng.seed=seed_value
			m.load_state(false)
			var single_run := 0
			for row: Dictionary in m.rows():
				if row["per_run"]: single_run+=1
				var id := String(row["id"])
				_check(stars>=12 or id not in ["multi_run","power_specific"],"multiplier and named power complexity waits for12 boards")
				_check(stars>=8 or id not in ["near_total","near_run","power_run","ramp_run"],"precision and scarce single-run goals introduced later")
				_check(stars>=4 or id not in ["power_total","ramp_total"],"pickup/ramp goals wait for established runs")
			_check(single_run<=1 and (stars>=3 or single_run==0),"one challenge maximum, first three boards all cumulative")
	# Old saves with only the guaranteed feeds still get three feasible slots.
	for stars: int in [1,2,3,24]:
		_reset()
		SaveManager.set_value(RunnerMissions.SAVE_KEY_STARS,stars)
		var m := RunnerMissions.new()
		m.load_state(false)
		_check(m.rows().size()==3 and m.rows().all(func(row: Dictionary) -> bool: return row["target"]>0),"thin proven pool fills complete board")

func _test_migration() -> void:
	_reset()
	SaveManager.set_value("stats",{"runner_best_distance":1200.0,"runner_fish_collected":100})
	SaveManager.set_value("xp",875)
	SaveManager.set_value("achievements",{"runner_fish_bronze":true,"long_waddle":true})
	SaveManager.set_value(RunnerMissions.SAVE_KEY_STARS,2)
	SaveManager.set_value(RunnerMissions.SAVE_KEY_SET,[
		{"id":"multi_run","target":150.0,"progress":40.0,"done":false,"mult":2},
		{"id":"dist_run","target":1200.0,"progress":1200.0,"done":true},
		{"id":"fish_total","target":100.0,"progress":80.0,"done":false}])
	var before := SaveManager.data.duplicate(true)
	var m := RunnerMissions.new()
	m.load_state(false)
	_check(m.rows()[0]["target"]==150 and m.rows()[0]["current"]==40 and m.rows()[1]["done"] and m.rows()[2]["current"]==80,"saved active board targets and work unchanged")
	_check(Progression.get_xp()==875 and m.stars()==2 and SaveManager.get_value("achievements")==before["achievements"],"earned XP, stars and trophies preserved")
	var legacy := RunnerMissions.map_progress()
	_check(legacy["current_region"]==2 and legacy["distance"]==1200.0 and legacy["legacy_discovery_retained"],"old600m discoveries retained without invented distance")
	_check(Progression.achievement_progress("runner_fish_bronze").get("earned_before_rebalance",false),"prior pacing trophy explicitly marked complete")
	var after := SaveManager.data.duplicate(true)
	RunnerMissions.map_progress()
	_check(SaveManager.data==after,"migration idempotent")
	_reset()
	RunnerMissions.map_progress()
	for metres: float in [600,1799,1800,3600,5400]:
		SaveManager.set_value("stats",{"runner_best_distance":metres})
		_check(RunnerMissions.map_progress()["current_region"]==clampi(floori(metres/1800),0,3),"new save uses only new biome boundaries")
