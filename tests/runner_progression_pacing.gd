extends Node
## Deterministic rate study: real course generation + explicitly assumed humans.
## Not a bot solve, retention forecast, or substitute for a 10-hour playtest.
func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		get_tree().quit(2)
		return
	AudioManager._library = {}
	AudioManager._one_shot_cache = {}
	var report := {"course_samples":[],"mission_scenarios":[],"pacing_version":RunnerMissions.PACING_VERSION,"limits":"Real spawned opportunities; collection/action/survival assumptions are synthetic, not measured player behavior. Active play only; excludes menus/retry downtime."}
	for seconds: int in [60,150,300,450]:
		var d := _distance(seconds)
		var totals := {"fish":0,"crates":0,"ramps":0,"hazard_rows":0}
		for seed_value: int in [419,1701,90210]:
			var track := RunnerTrack.new()
			add_child(track)
			track._clear()
			track.set_process(false)
			track._headless = true
			track._seed = seed_value
			track._next_powerup_z = -RunnerTrack.POWERUP_FIRST
			for index: int in ceili(d / RunnerConfig.CHUNK_LENGTH):
				track._spawn_chunk(index,clampf(float(index)*RunnerConfig.CHUNK_LENGTH/7000.0,0.0,1.0))
				var chunk: RunnerTrack.RunnerChunk = track._chunks.back()
				for node: Node in chunk.get_children():
					if node is Node3D and -(node as Node3D).global_position.z > d: continue
					if node.is_in_group(RunnerConfig.GROUP_PICKUP): totals["fish"] += 1
					if node.is_in_group(RunnerConfig.GROUP_POWERUP): totals["crates"] += 1
					if node.get_meta("kind", "") == "ramp": totals["ramps"] += 1
				totals["hazard_rows"] += chunk.rows.size()
				track._chunks.erase(chunk)
				chunk.free()
			track.free()
		var sample := {"run_seconds":seconds,"metres":d,"seeds":3,"ten_hour_metres":d/seconds*36000.0,
			"fish_per_km":float(totals["fish"])/3.0/d*1000.0,"crates_per_km":float(totals["crates"])/3.0/d*1000.0,
			"ramps_per_km":float(totals["ramps"])/3.0/d*1000.0,"hazard_rows_per_km":float(totals["hazard_rows"])/3.0/d*1000.0}
		report["course_samples"].append(sample)
		var capture := 0.12 if seconds==60 else (0.24 if seconds==150 else 0.4)
		var scenario := _simulate_missions(seconds,capture,sample)
		report["mission_scenarios"].append(scenario)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			var file := FileAccess.open(arg.trim_prefix("out="),FileAccess.WRITE)
			file.store_string(JSON.stringify(report,"\t"))
	print("[runner_pacing] "+JSON.stringify(report))
	get_tree().quit()

func _distance(seconds: int) -> float:
	var metres := 0.0
	for tick: int in seconds*60:
		metres += RunnerConfig.speed_at(float(tick+1)/60.0)/60.0
	return metres

func _simulate_missions(run_seconds: int, capture: float, sample: Dictionary) -> Dictionary:
	SaveManager.data = SaveManager.default_save()
	var m := RunnerMissions.new()
	m._rng.seed = 1337
	m.load_state()
	m._flush_suppression_depth = 1
	var fish_left := 0.0
	var power_left := 0.0
	var ramp_left := 0.0
	var distance := 0.0
	var first_star := -1
	var checkpoints: Array = []
	var clean_base := 0.0
	var first_run_badges := -1
	var first_run_missions := -1
	var first_all_badges := -1
	var power_index := 0
	for second: int in 43200:
		var run_t := second % run_seconds
		if run_t==0:
			m.begin_run()
			distance = 0.0
			clean_base = 0.0
		var speed := 0.0
		for quarter: int in 4:
			var rate := RunnerConfig.speed_at(float(run_t) + float(quarter+1)*0.25)
			if clean_base>0.0:
				rate -= RunnerConfig.HIT_SPEED_LOSS * maxf(0.0,1.0-(distance-clean_base)/180.0)
			var step := maxf(rate,RunnerConfig.START_SPEED*0.6)*0.25
			speed += step
			distance += step
			Progression.record_runner_activity(0.25,step,distance,distance-clean_base)
		m.note_distance(distance)
		fish_left += speed*float(sample["fish_per_km"])/1000.0*capture
		if fish_left >= 1.0:
			m.note_fish(int(fish_left))
			Progression.record_runner_event("runner_fish_collected",int(fish_left))
			fish_left -= floorf(fish_left)
		if distance>432.0:
			if run_t%9==0: m.note_jump()
			if run_t%12==0: m.note_slide()
			if run_t%3==0: m.note_lane_change()
			if run_t%45==0:
				m.note_near_miss()
				Progression.record_runner_event("runner_near_misses")
			power_left += speed*float(sample["crates_per_km"])/1000.0*0.4
			if power_left>=1.0:
				m.note_powerup(RunnerConfig.POWERUP_IDS[power_index%3]); power_left-=1.0
				power_index+=1
				Progression.record_runner_event("runner_powerups_collected")
			ramp_left += speed*float(sample["ramps_per_km"])/1000.0*0.4
			if ramp_left>=1.0: m.note_ramp();ramp_left-=1.0
		if run_seconds<300 and run_t==run_seconds/2:
			m.note_hit()
			clean_base=distance
		if run_t==run_seconds-1:
			m.note_run_ended(distance,0,0,false)
			if first_run_badges<0:
				first_run_badges=Progression.runner_achievements_unlocked_count()
				first_run_missions=Progression.get_stat("runner_missions_done")
		if first_all_badges<0 and Progression.runner_achievements_unlocked_count()==32: first_all_badges=second+1
		if first_star<0 and m.stars()>0: first_star=second+1
		if (second+1) in [600,3600,14400,36000,43200]:
			checkpoints.append({"seconds":second+1,"stars":m.stars(),"missions":Progression.get_stat("runner_missions_done"),"badges":Progression.runner_achievements_unlocked_count()})
	return {"run_seconds":run_seconds,"fish_capture_fraction":capture,"crate_and_ramp_capture":0.4,
		"assumed_jump_interval":9,"assumed_slide_interval":12,"assumed_lane_interval":3,"assumed_near_interval":45,
		"first_run_badges":first_run_badges,"first_run_missions":first_run_missions,"all32_seconds":first_all_badges,
		"achievement_stats":SaveManager.get_value("stats",{}).duplicate(true),
		"hit_per_run":0 if run_seconds>=300 else 1,"first_star_seconds":first_star,"checkpoints":checkpoints,
		"remaining_goals":m.rows().duplicate(true)}
