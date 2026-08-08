extends Node
## Headless unit test suite for Waddle Wars. Launch with:
##   godot --headless res://tests/unit_tests.tscn
## Prints "[unit] PASS/FAIL/SKIP <name>" per check, exits 0 only when every
## non-skipped check passes. Skips are reserved for scenes owned by parallel
## workstreams that have not been written yet.

const MENU_SCENES: PackedStringArray = [
	"res://scenes/ui/title.tscn",
	"res://scenes/menus/main_menu.tscn",
	"res://scenes/menus/mode_select.tscn",
	"res://scenes/menus/results.tscn",
	"res://scenes/menus/settings.tscn",
	"res://scenes/menus/controls.tscn",
	"res://scenes/menus/customize.tscn",
	"res://scenes/menus/achievements.tscn",
	"res://scenes/menus/credits.tscn",
	"res://scenes/menus/leaderboard.tscn",
]

var _passes: int = 0
var _failures: int = 0
var _skips: int = 0


func _ready() -> void:
	print("[unit] Waddle Wars unit test suite starting")
	await get_tree().process_frame
	_test_save_round_trip()
	_test_save_corruption_recovery()
	_test_default_settings()
	_test_settings_round_trip()
	_test_cosmetics_db()
	_test_achievements_db()
	_test_powerups_roll()
	_test_progression()
	await _test_racer_instantiation()
	_test_path_guide()
	await _test_powerup_activation()
	await _test_backward_snowball()
	await _test_shield_lifetime()
	await _test_shove_animation()
	_test_daily_challenge()
	_test_tilt_steering()
	await _test_menu_scenes()
	await _test_touch_controls()
	print("[unit] DONE: %d passed, %d failed, %d skipped" % [_passes, _failures, _skips])
	get_tree().quit(1 if _failures > 0 else 0)


## --- Reporting helpers -----------------------------------------------------

func _check(check_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("[unit] PASS %s" % check_name)
	else:
		_failures += 1
		var suffix := ": %s" % detail if detail != "" else ""
		print("[unit] FAIL %s%s" % [check_name, suffix])


func _skip(check_name: String, reason: String) -> void:
	_skips += 1
	print("[unit] SKIP %s: %s" % [check_name, reason])
	push_warning("unit test skipped: %s (%s)" % [check_name, reason])


func _count_nodes(node: Node) -> int:
	var count := 1
	for child: Node in node.get_children():
		count += _count_nodes(child)
	return count


func _types_compatible(a: Variant, b: Variant) -> bool:
	if typeof(a) == typeof(b):
		return true
	# JSON round trips turn ints into floats; treat numerics as one family.
	var numeric: Array[int] = [TYPE_INT, TYPE_FLOAT]
	return typeof(a) in numeric and typeof(b) in numeric


## --- 1. Save round trip ----------------------------------------------------

func _test_save_round_trip() -> void:
	var backup: Dictionary = SaveManager.data.duplicate(true)
	SaveManager.data["fish"] = 123
	var achievements: Dictionary = SaveManager.data.get("achievements", {})
	achievements["first_win"] = true
	SaveManager.data["achievements"] = achievements
	var times: Dictionary = SaveManager.data.get("best_times", {})
	times["glacier"] = 88.5
	SaveManager.data["best_times"] = times
	SaveManager.save_now()
	SaveManager.data = {}
	SaveManager.load_save()
	_check("save_round_trip_fish", int(SaveManager.data.get("fish", -1)) == 123,
		"fish=%s" % str(SaveManager.data.get("fish")))
	_check("save_round_trip_achievement",
		bool(SaveManager.data.get("achievements", {}).get("first_win", false)))
	var reloaded_time := float(SaveManager.data.get("best_times", {}).get("glacier", 0.0))
	_check("save_round_trip_best_time", absf(reloaded_time - 88.5) < 0.01,
		"glacier=%f" % reloaded_time)
	SaveManager.data = backup
	SaveManager.save_now()


## --- 2. Save corruption recovery -------------------------------------------

func _test_save_corruption_recovery() -> void:
	var backup: Dictionary = SaveManager.data.duplicate(true)
	for path: String in [SaveManager.SAVE_PATH, SaveManager.SAVE_BACKUP_PATH]:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string("{ not valid json !!! %$#@ ")
			file.close()
	SaveManager.load_save()
	var defaults: Dictionary = SaveManager.default_save()
	_check("save_corruption_defaults",
		int(SaveManager.data.get("fish", -1)) == int(defaults["fish"])
		and SaveManager.data.has("equipped")
		and SaveManager.data.has("stats")
		and SaveManager.data.has("unlocked_cosmetics"))
	_check("save_corruption_version",
		int(SaveManager.data.get("version", -1)) == GameConfig.SAVE_VERSION)
	SaveManager.data = backup
	SaveManager.save_now()
	# Second write refreshes save.json.bak with valid data again.
	SaveManager.save_now()


## --- 3. Default settings ---------------------------------------------------

func _test_default_settings() -> void:
	var defaults: Dictionary = SettingsManager.default_settings()
	var all_ok := true
	var bad := ""
	for section: String in defaults.keys():
		var sect: Dictionary = defaults[section]
		for key: Variant in sect.keys():
			var value: Variant = SettingsManager.get_setting(section, String(key))
			if value == null or not _types_compatible(value, sect[key]):
				all_ok = false
				bad = "%s/%s=%s" % [section, key, str(value)]
	_check("settings_defaults_all_keys", all_ok, bad)
	var music := float(SettingsManager.get_setting("audio", "music_volume"))
	_check("settings_defaults_music_range", music >= 0.0 and music <= 1.0, "music=%f" % music)
	_check("settings_defaults_touch_mode",
		String(defaults["gameplay"]["touch_controls"]) in ["auto", "on", "off"])


## --- 4. Settings round trip ------------------------------------------------

func _test_settings_round_trip() -> void:
	var original: Variant = SettingsManager.get_setting("audio", "music_volume")
	SettingsManager.set_setting("audio", "music_volume", 0.33)
	SettingsManager.settings = {}
	SettingsManager._load_settings()
	var reloaded := float(SettingsManager.get_setting("audio", "music_volume"))
	_check("settings_round_trip", absf(reloaded - 0.33) < 0.001, "reloaded=%f" % reloaded)
	SettingsManager.set_setting("audio", "music_volume", original)


## --- 5. CosmeticsDB --------------------------------------------------------

func _test_cosmetics_db() -> void:
	var total := CosmeticsDB.ITEMS.size()
	var non_body := 0
	for id: String in CosmeticsDB.ITEMS.keys():
		if String(CosmeticsDB.ITEMS[id]["category"]) != "body":
			non_body += 1
	_check("cosmetics_count", non_body >= 12 or total >= 16,
		"total=%d non_body=%d" % [total, non_body])
	var fields_ok := true
	var bad_id := ""
	for id: String in CosmeticsDB.ITEMS.keys():
		var item: Dictionary = CosmeticsDB.ITEMS[id]
		if not (item.has("name") and item.has("category") and item.has("cost")):
			fields_ok = false
			bad_id = id
			break
		if String(item["category"]) not in CosmeticsDB.CATEGORIES:
			fields_ok = false
			bad_id = id
			break
	_check("cosmetics_fields", fields_ok, bad_id)
	var sorted_ok := true
	var covered := 0
	for category: String in CosmeticsDB.CATEGORIES:
		var ids := CosmeticsDB.items_in_category(category)
		covered += ids.size()
		var prev := -1
		for id: String in ids:
			var cost := int(CosmeticsDB.get_item(id)["cost"])
			if cost < prev:
				sorted_ok = false
			prev = cost
	_check("cosmetics_category_sort", sorted_ok and covered == total,
		"covered=%d total=%d" % [covered, total])


## --- 6. AchievementsDB -----------------------------------------------------

func _test_achievements_db() -> void:
	_check("achievements_count", AchievementsDB.ITEMS.size() >= 12,
		"size=%d" % AchievementsDB.ITEMS.size())
	var order_ok := AchievementsDB.ORDER.size() == AchievementsDB.ITEMS.size()
	for id: String in AchievementsDB.ORDER:
		if not AchievementsDB.ITEMS.has(id):
			order_ok = false
	for id: String in AchievementsDB.ITEMS.keys():
		if id not in AchievementsDB.ORDER:
			order_ok = false
	_check("achievements_order_matches_items", order_ok)
	var fields_ok := true
	for id: String in AchievementsDB.ITEMS.keys():
		var item: Dictionary = AchievementsDB.ITEMS[id]
		if not (item.has("name") and item.has("desc")):
			fields_ok = false
	_check("achievements_fields", fields_ok)


## --- 7. PowerupsDB.roll ----------------------------------------------------

func _test_powerups_roll() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var all_valid := true
	var bad := ""
	var seen: Dictionary = {}
	for i: int in 200:
		var position := (i % 8) + 1
		var id := PowerupsDB.roll(position, 8, rng)
		if not PowerupsDB.ITEMS.has(id):
			all_valid = false
			bad = "pos=%d id=%s" % [position, id]
			break
		seen[id] = true
	_check("powerups_roll_valid_ids", all_valid, bad)
	_check("powerups_roll_variety", seen.size() >= 3,
		"only %d distinct ids in 200 rolls" % seen.size())


## --- 8. Progression --------------------------------------------------------

func _test_progression() -> void:
	var backup: Dictionary = SaveManager.data.duplicate(true)
	SaveManager.data = SaveManager.default_save()

	_check("progression_fish_baseline", Progression.get_fish() == 0)
	Progression.add_fish(100)
	_check("progression_add_fish", Progression.get_fish() == 100,
		"fish=%d" % Progression.get_fish())
	_check("progression_spend_fish_ok", Progression.spend_fish(40) and Progression.get_fish() == 60)
	_check("progression_spend_fish_insufficient",
		not Progression.spend_fish(1000) and Progression.get_fish() == 60)

	# hat_crown costs 400, balance is 60: unlock must fail without charging.
	_check("progression_unlock_insufficient",
		not Progression.try_unlock_cosmetic("hat_crown") and Progression.get_fish() == 60)
	# hat_beanie costs 50: unlock must succeed and charge exactly 50.
	var unlocked := Progression.try_unlock_cosmetic("hat_beanie")
	_check("progression_unlock_success",
		unlocked and Progression.is_cosmetic_unlocked("hat_beanie") and Progression.get_fish() == 10,
		"fish=%d" % Progression.get_fish())

	Progression.equip("hat", "hat_beanie")
	_check("progression_equip", Progression.get_equipped("hat") == "hat_beanie")
	Progression.equip("hat", "hat_crown")  # still locked: must be rejected
	_check("progression_equip_locked_rejected", Progression.get_equipped("hat") == "hat_beanie")

	SaveManager.data = backup
	SaveManager.save_now()


## --- 9. Racer instantiation ------------------------------------------------

func _test_racer_instantiation() -> void:
	var racer := Racer.new()
	add_child(racer)
	racer.setup("test_racer", "Testy", false, {}, RacerController.new(), null)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("racer_setup_children",
		racer.visual != null and racer.controller != null and racer.get_child_count() >= 3,
		"children=%d" % racer.get_child_count())
	_check("racer_initial_state", racer.state == Racer.State.WADDLING)
	racer.queue_free()
	await get_tree().process_frame


## --- 10. PathGuide ---------------------------------------------------------

func _test_path_guide() -> void:
	var positions: Array = [
		Vector3.ZERO, Vector3(0, 0, -40), Vector3(12, 0, -80), Vector3(12, 0, -130),
	]
	var curve := TrackBuilder.make_curve(positions)
	var guide := PathGuide.new(curve)
	_check("path_guide_length", guide.length > 100.0, "length=%f" % guide.length)

	var probe := guide.position_at(30.0)
	var res := guide.nearest(probe, -1)
	_check("path_guide_nearest_close", float(res["distance"]) < 2.5,
		"distance=%f" % float(res["distance"]))
	_check("path_guide_nearest_offset", absf(float(res["offset"]) - 30.0) <= 4.0,
		"offset=%f" % float(res["offset"]))

	var monotonic := true
	var prev := -1.0
	for offset: float in [5.0, 25.0, 50.0, 75.0, 100.0]:
		var r := guide.nearest(guide.position_at(offset), -1)
		if float(r["offset"]) <= prev:
			monotonic = false
		prev = float(r["offset"])
	_check("path_guide_offsets_monotonic", monotonic)

	var yaw := guide.yaw_at(0.0)
	_check("path_guide_yaw_sane", is_finite(yaw) and absf(yaw) < 0.6, "yaw=%f" % yaw)
	var mid := guide.position_at(guide.length * 0.5)
	_check("path_guide_position_finite",
		is_finite(mid.x) and is_finite(mid.y) and is_finite(mid.z))


## --- 11. Every powerup activates -------------------------------------------

func _test_powerup_activation() -> void:
	var arena := Node3D.new()
	add_child(arena)
	var powerups := PowerupSystem.new()
	arena.add_child(powerups)
	var racer := Racer.new()
	arena.add_child(racer)
	racer.setup("pu_racer", "PU", false, {}, RacerController.new(), null)
	await get_tree().physics_frame

	for item_id: String in PowerupsDB.ORDER:
		powerups.activate(racer, item_id)

	var snowballs := 0
	var clouds := 0
	for child: Node in arena.get_children():
		if child is Snowball:
			snowballs += 1
		elif child is Area3D:
			clouds += 1
	_check("powerup_snowball_spawns", snowballs == 1, "snowballs=%d" % snowballs)
	_check("powerup_shield_applied", racer.has_shield())
	_check("powerup_frenzy_boost", racer.boost_mult > 1.0, "boost=%f" % racer.boost_mult)
	_check("powerup_magnet_registered", powerups._magnets.size() == 1,
		"magnets=%d" % powerups._magnets.size())
	_check("powerup_blizzard_cloud", clouds == 1, "clouds=%d" % clouds)

	# Let one physics tick run the live effects (snowball flight, magnet
	# filter with null course) to prove nothing crashes.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check("powerup_effects_tick", is_instance_valid(racer) and is_instance_valid(powerups))
	arena.queue_free()
	await get_tree().process_frame


## --- 11c. Ice shield lifetime ----------------------------------------------

## The shield used to end only by absorbing a hit, so a clean run carried a
## glowing bubble to the finish line and the power-up read as broken. It must
## now also lapse on its own -- and lapsing has to stay distinguishable from
## being broken, because only one of the two grants the post-hit grace window.
##
## Driven through _update_timers directly rather than through physics frames:
## _physics_process returns early without a course, and the point here is the
## clock, not the movement around it.
func _test_shield_lifetime() -> void:
	var racer := Racer.new()
	add_child(racer)
	racer.setup("shield_racer", "Shieldy", false, {}, RacerController.new(), null)
	await get_tree().physics_frame

	racer.give_shield()
	_check("shield_starts_active", racer.has_shield())
	_check("shield_starts_full",
		absf(racer.shield_remaining() - Racer.SHIELD_DURATION) < 0.001,
		"remaining=%f" % racer.shield_remaining())

	for _i: int in int(Racer.SHIELD_DURATION * 0.5 / 0.05):
		racer._update_timers(0.05)
	_check("shield_survives_midlife", racer.has_shield())
	_check("shield_clock_runs",
		racer.shield_remaining() < Racer.SHIELD_DURATION * 0.6,
		"remaining=%f" % racer.shield_remaining())

	# A second pickup refreshes the window; it does not stack a second shield.
	racer.give_shield()
	_check("shield_refresh_resets_clock",
		absf(racer.shield_remaining() - Racer.SHIELD_DURATION) < 0.001,
		"remaining=%f" % racer.shield_remaining())

	for _i: int in int(Racer.SHIELD_DURATION / 0.05) + 4:
		racer._update_timers(0.05)
	_check("shield_expires", not racer.has_shield())
	_check("shield_expiry_reports_zero", racer.shield_remaining() == 0.0,
		"remaining=%f" % racer.shield_remaining())
	_check("shield_expiry_grants_no_invuln", racer._invuln_timer <= 0.0,
		"invuln=%f" % racer._invuln_timer)

	# Absorbing a hit still works exactly as before, grace window included.
	racer.give_shield()
	_check("shield_blocks_stun", not racer.apply_stun())
	_check("shield_consumed_by_hit", not racer.has_shield())
	_check("shield_break_grants_invuln", racer._invuln_timer > 0.0,
		"invuln=%f" % racer._invuln_timer)

	# A hit that the racer's own i-frames already absorb must not ALSO spend
	# the shield. All three guards used to share one condition, so any blocked
	# hit consumed a shield that was never needed.
	racer.give_shield()
	racer._invuln_timer = 1.0
	_check("shield_survives_stun_during_iframes",
		not racer.apply_stun() and racer.has_shield())
	racer.apply_blizzard_slip(1.0)
	_check("shield_survives_blizzard_during_iframes", racer.has_shield())
	var attacker := Racer.new()
	add_child(attacker)
	attacker.setup("shield_attacker", "Bully", false, {}, RacerController.new(), null)
	await get_tree().physics_frame
	_check("shield_survives_shove_during_iframes",
		not racer.receive_shove(attacker) and racer.has_shield())
	# With the i-frames gone the same shove spends it, as it should.
	racer._invuln_timer = 0.0
	racer._shove_immunity = 0.0
	_check("shield_blocks_live_shove",
		not racer.receive_shove(attacker) and not racer.has_shield())

	attacker.queue_free()
	racer.queue_free()
	await get_tree().process_frame


## --- 11d. Shove animation envelopes ----------------------------------------

## Both shove impulses must deflect the body and then put it back. The return
## is the half worth testing: _root.position.z is written by nothing else in
## tick(), so an offset applied only while the envelope runs would never be
## taken off again and the penguin would stay leaning forever.
func _test_shove_animation() -> void:
	var racer := Racer.new()
	add_child(racer)
	racer.setup("shove_racer", "Shovey", false, {}, RacerController.new(), null)
	await get_tree().physics_frame
	var visual := racer.visual
	if visual == null or visual._root == null:
		_check("shove_animation_visual_built", false, "no visual root")
		racer.queue_free()
		await get_tree().process_frame
		return

	visual.trigger_lunge()
	var peak_z := 0.0
	for _i: int in 6:
		visual.tick(0.03, 1.0)
		peak_z = minf(peak_z, visual._root.position.z)
	_check("lunge_drives_body_forward", peak_z < -0.01, "peak_z=%f" % peak_z)
	for _i: int in int(PenguinVisual.LUNGE_TIME / 0.03) + 6:
		visual.tick(0.03, 1.0)
	_check("lunge_returns_to_rest", absf(visual._root.position.z) < 0.001,
		"z=%f" % visual._root.position.z)

	visual.set_pose(PenguinVisual.Pose.RUN)
	visual.trigger_tumble(1.0)
	visual.tick(0.016, 1.0)
	var hit_yaw := absf(visual._root.rotation.y)
	_check("tumble_swings_silhouette", hit_yaw > deg_to_rad(20.0),
		"yaw=%.1f deg" % rad_to_deg(hit_yaw))
	for _i: int in int(PenguinVisual.TUMBLE_TIME / 0.016) + 8:
		visual.tick(0.016, 1.0)
	# Settles back to the gait's own yaw (~7 deg), not to exactly zero.
	_check("tumble_settles", absf(visual._root.rotation.y) < deg_to_rad(12.0),
		"yaw=%.1f deg" % rad_to_deg(visual._root.rotation.y))

	# Direction has to follow the push, or a shove from the left spins the
	# victim into the attacker.
	visual.trigger_tumble(-1.0)
	visual.tick(0.016, 1.0)
	var left_yaw := visual._root.rotation.y
	visual.trigger_tumble(1.0)
	visual.tick(0.016, 1.0)
	_check("tumble_direction_follows_push", signf(left_yaw) != signf(visual._root.rotation.y),
		"left=%.3f right=%.3f" % [left_yaw, visual._root.rotation.y])

	racer.queue_free()
	await get_tree().process_frame


## --- 11b. Over-the-shoulder snowball ---------------------------------------

## A back-throw must leave in the opposite direction and pick the rival behind,
## never the one in front — the whole point is answering a tail.
func _test_backward_snowball() -> void:
	var arena := Node3D.new()
	add_child(arena)
	var powerups := PowerupSystem.new()
	arena.add_child(powerups)

	var controller := RacerController.new()
	var thrower := Racer.new()
	arena.add_child(thrower)
	thrower.setup("bt_thrower", "BT", false, {}, controller, null)
	# Racers face -Z, so -Z is ahead and +Z is behind.
	var ahead := Racer.new()
	arena.add_child(ahead)
	ahead.setup("bt_ahead", "AH", false, {}, RacerController.new(), null)
	var behind := Racer.new()
	arena.add_child(behind)
	behind.setup("bt_behind", "BH", false, {}, RacerController.new(), null)
	await get_tree().physics_frame
	thrower.global_position = Vector3.ZERO
	ahead.global_position = Vector3(0.0, 0.0, -14.0)
	behind.global_position = Vector3(0.0, 0.0, 14.0)
	await get_tree().physics_frame

	controller.aim_back = false
	powerups.activate(thrower, "snowball")
	var forward_ball := _latest_snowball(arena)
	_check("snowball_forward_targets_ahead",
		forward_ball != null and forward_ball.target == ahead,
		"target=%s" % (forward_ball.target.racer_key if forward_ball != null and forward_ball.target != null else "<none>"))
	_check("snowball_forward_leaves_forward",
		forward_ball != null and forward_ball.global_position.z < 0.0,
		"z=%f" % (forward_ball.global_position.z if forward_ball != null else 0.0))

	controller.aim_back = true
	powerups.activate(thrower, "snowball")
	var back_ball := _latest_snowball(arena)
	_check("snowball_back_targets_behind",
		back_ball != null and back_ball.target == behind,
		"target=%s" % (back_ball.target.racer_key if back_ball != null and back_ball.target != null else "<none>"))
	_check("snowball_back_leaves_backward",
		back_ball != null and back_ball.global_position.z > 0.0,
		"z=%f" % (back_ball.global_position.z if back_ball != null else 0.0))

	arena.queue_free()
	await get_tree().process_frame


func _latest_snowball(arena: Node) -> Snowball:
	var found: Snowball = null
	for child: Node in arena.get_children():
		if child is Snowball:
			found = child as Snowball
	return found


## --- 11c. Daily challenge --------------------------------------------------

## The daily has to be identical for everyone on a given day, has to pay out
## once and only once, and must only continue a streak across consecutive days.
func _test_daily_challenge() -> void:
	var day := DailyChallenge.today_id()
	var a := DailyChallenge.for_day(day)
	var b := DailyChallenge.for_day(day)
	_check("daily_deterministic",
		a["course"] == b["course"] and a["modifier"] == b["modifier"],
		"%s/%s vs %s/%s" % [a["course"], a["modifier"], b["course"], b["modifier"]])
	_check("daily_course_valid", DailyChallenge.COURSES.has(String(a["course"])),
		"course=%s" % a["course"])

	# Neighbouring days must not walk the rotation in lockstep, which would make
	# the whole cycle guessable and repeat every three days.
	var varied := false
	var seen_courses := {}
	for i: int in 8:
		var c := DailyChallenge.for_day(day + i)
		seen_courses[c["course"]] = true
		if String(c["course"]) != String(a["course"]):
			varied = true
	_check("daily_rotates", varied and seen_courses.size() >= 2,
		"distinct courses over 8 days=%d" % seen_courses.size())

	# Reward and streak accounting, driven through the real save.
	var saved_day: Variant = SaveManager.data.get("daily_last_day", -1)
	var saved_time: Variant = SaveManager.data.get("daily_last_time", 0.0)
	var saved_streak: Variant = SaveManager.data.get("daily_streak", 0)
	var saved_fish := Progression.get_fish()

	SaveManager.data["daily_last_day"] = day - 1  # played yesterday
	SaveManager.data["daily_streak"] = 3
	var first := DailyChallenge.record_completion(90.0)
	_check("daily_first_pays", bool(first["first_today"]) and int(first["fish"]) > 0,
		"fish=%d" % int(first["fish"]))
	_check("daily_streak_continues", int(first["streak"]) == 4,
		"streak=%d" % int(first["streak"]))

	var again := DailyChallenge.record_completion(80.0)
	_check("daily_second_run_pays_nothing", not bool(again["first_today"]) and int(again["fish"]) == 0,
		"fish=%d" % int(again["fish"]))
	_check("daily_second_run_records_better_time", bool(again["improved"])
		and is_equal_approx(DailyChallenge.today_best(), 80.0),
		"best=%f" % DailyChallenge.today_best())

	var slower := DailyChallenge.record_completion(95.0)
	_check("daily_slower_run_ignored", not bool(slower["improved"])
		and is_equal_approx(DailyChallenge.today_best(), 80.0),
		"best=%f" % DailyChallenge.today_best())

	# A missed day resets rather than continuing.
	SaveManager.data["daily_last_day"] = day - 3
	SaveManager.data["daily_streak"] = 9
	var broken := DailyChallenge.record_completion(70.0)
	_check("daily_gap_resets_streak", int(broken["streak"]) == 1,
		"streak=%d" % int(broken["streak"]))

	SaveManager.data["daily_last_day"] = saved_day
	SaveManager.data["daily_last_time"] = saved_time
	SaveManager.data["daily_streak"] = saved_streak
	SaveManager.data["fish"] = saved_fish


## --- 12. Menu scenes load --------------------------------------------------

func _test_menu_scenes() -> void:
	Game.mode = Game.Mode.QUICK_RACE
	Game.course_id = "glacier"
	var rows: Array[Dictionary] = []
	for i: int in 8:
		rows.append({
			"key": "player" if i == 0 else "rival_%d" % i,
			"name": "You" if i == 0 else "Rival %d" % i,
			"is_player": i == 0,
			"position": i + 1,
			"time": 95.0 + float(i) * 3.5,
			"fish": 18 - i,
			"dnf": false,
		})
	Game.last_race_results = rows
	Game.last_rewards = {"fish": 63, "xp": 145, "unlocks": []}

	for path: String in MENU_SCENES:
		var short := path.get_file()
		if not ResourceLoader.exists(path):
			_skip("menu_load_%s" % short, "scene not written yet (parallel stream)")
			continue
		var packed: PackedScene = load(path)
		if packed == null:
			_check("menu_load_%s" % short, false, "load() returned null")
			continue
		var instance := packed.instantiate()
		add_child(instance)
		await get_tree().process_frame
		await get_tree().process_frame
		var node_count := _count_nodes(instance)
		var has_script := instance.get_script() != null
		_check("menu_load_%s" % short, has_script and node_count > 3,
			"script=%s nodes=%d" % [str(has_script), node_count])
		instance.queue_free()
		await get_tree().process_frame


## --- 13. Touch controls instantiate ----------------------------------------

func _test_touch_controls() -> void:
	var player_controller := PlayerController.new()
	add_child(player_controller)
	var touch := TouchControls.new()
	add_child(touch)
	touch.setup(player_controller)
	await get_tree().process_frame
	_check("touch_controls_setup",
		touch.controller == player_controller and touch.get_child_count() >= 1
		and _count_nodes(touch) > 5,
		"nodes=%d" % _count_nodes(touch))
	touch.queue_free()
	player_controller.queue_free()
	await get_tree().process_frame


## Tilt steering axis maths. Worth testing precisely because it is the one part
## of that feature that cannot be checked by running the game on a desktop --
## there is no sensor here, so without this the whole feel of it would be
## shipped unverified.
func _test_tilt_steering() -> void:
	_check("tilt_neutral_is_zero",
		is_zero_approx(TiltSteering.axis_for_lean(0.0, 1.0, false)),
		"%f" % TiltSteering.axis_for_lean(0.0, 1.0, false))
	# Inside the deadzone a resting hand must produce nothing at all.
	_check("tilt_deadzone_silent",
		is_zero_approx(TiltSteering.axis_for_lean(TiltSteering.DEADZONE_DEG - 0.1, 1.0, false)),
		"%f" % TiltSteering.axis_for_lean(TiltSteering.DEADZONE_DEG - 0.1, 1.0, false))
	# Right lean is positive, matching Input.get_axis("steer_left","steer_right").
	var right := TiltSteering.axis_for_lean(12.0, 1.0, false)
	var left := TiltSteering.axis_for_lean(-12.0, 1.0, false)
	_check("tilt_sign_right_positive", right > 0.0, "%f" % right)
	_check("tilt_symmetric", is_equal_approx(right, -left), "%f vs %f" % [right, left])
	# A full lean must reach full lock, and nothing may exceed it.
	var full := TiltSteering.axis_for_lean(TiltSteering.FULL_LOCK_DEG * 4.0, 1.0, false)
	_check("tilt_clamped_to_one", is_equal_approx(full, 1.0), "%f" % full)
	# Higher sensitivity must reach a given axis with LESS lean, not more.
	var lo := TiltSteering.axis_for_lean(10.0, 0.6, false)
	var hi := TiltSteering.axis_for_lean(10.0, 1.8, false)
	_check("tilt_sensitivity_orders", hi > lo, "%f vs %f" % [hi, lo])
	# Sensitivity is clamped, so absurd settings cannot invert or explode it.
	var wild := TiltSteering.axis_for_lean(10.0, 99.0, false)
	_check("tilt_sensitivity_clamped", wild > 0.0 and wild <= 1.0, "%f" % wild)
	_check("tilt_invert_flips",
		is_equal_approx(TiltSteering.axis_for_lean(12.0, 1.0, true), -right),
		"%f" % TiltSteering.axis_for_lean(12.0, 1.0, true))
