extends Node
## Domain layer over SaveManager: fish, XP, cosmetics, achievements, records.

signal fish_changed(total: int)
signal xp_changed(xp: int, level: int)
signal achievement_unlocked(id: String)
signal cosmetics_changed
signal record_set(kind: String, course_id: String, value: float)

const XP_PER_LEVEL: int = 400


func _ready() -> void:
	# Commerce is a later autoload; defer until every singleton is in the tree.
	_connect_purchase_ownership.call_deferred()
	evaluate_runner_achievements.call_deferred()


func _connect_purchase_ownership() -> void:
	var commerce := get_node_or_null("/root/CommerceClient")
	if commerce != null and not commerce.entitlements_changed.is_connected(_on_entitlements_changed):
		commerce.entitlements_changed.connect(_on_entitlements_changed)


func _on_entitlements_changed() -> void:
	# Earned cosmetics stay in the existing save. Paid ownership is a separate
	# verified account ledger, so a refund cannot erase an earned unlock.
	cosmetics_changed.emit()


## --- Fish currency --------------------------------------------------------

func get_fish() -> int:
	return int(SaveManager.get_value("fish", 0))


func add_fish(amount: int, reward_id: String = "") -> void:
	if amount <= 0:
		return
	if not reward_id.is_empty():
		amount = SaveManager.grant_fish_reward(reward_id, amount)
		if amount <= 0: return
	elif not SaveManager.set_value("fish", get_fish() + amount):
		return
	increment_stat("fish_total", amount)
	fish_changed.emit(get_fish())
	if get_stat("fish_total") >= 500:
		unlock_achievement("fish_hoarder")


func spend_fish(amount: int) -> bool:
	if amount < 0 or amount > get_fish():
		return false
	if not SaveManager.set_value("fish", get_fish() - amount):
		return false
	fish_changed.emit(get_fish())
	return true


## --- XP / level -----------------------------------------------------------

func get_xp() -> int:
	return int(SaveManager.get_value("xp", 0))


func get_level() -> int:
	return 1 + get_xp() / XP_PER_LEVEL


func level_progress() -> float:
	return float(get_xp() % XP_PER_LEVEL) / float(XP_PER_LEVEL)


func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	SaveManager.set_value("xp", get_xp() + amount)
	xp_changed.emit(get_xp(), get_level())


## --- Stats ----------------------------------------------------------------

func get_stat(key: String) -> int:
	var stats: Dictionary = SaveManager.get_value("stats", {})
	return int(stats.get(key, 0))


func increment_stat(key: String, amount: int = 1) -> void:
	var stats: Dictionary = SaveManager.get_value("stats", {})
	stats[key] = int(stats.get(key, 0)) + amount
	SaveManager.set_value("stats", stats)


func record_item_used(item_id: String) -> void:
	var stats: Dictionary = SaveManager.get_value("stats", {})
	var used: Dictionary = stats.get("items_used", {})
	used[item_id] = int(used.get(item_id, 0)) + 1
	stats["items_used"] = used
	SaveManager.set_value("stats", stats)
	var all_used := true
	for id: String in PowerupsDB.ORDER:
		if not used.has(id):
			all_used = false
			break
	if all_used:
		unlock_achievement("item_collector")


func record_shove_landed() -> void:
	increment_stat("shoves_landed")
	if get_stat("shoves_landed") >= 25:
		unlock_achievement("shove_master")


## --- Cosmetics ------------------------------------------------------------

func unlocked_cosmetics() -> Array:
	return SaveManager.get_value("unlocked_cosmetics", ["body_classic"])


func is_cosmetic_unlocked(id: String) -> bool:
	if not CosmeticsDB.ITEMS.has(id):
		return false
	if id in unlocked_cosmetics() or int(CosmeticsDB.get_item(id).get("cost", 0)) == 0:
		return true
	var commerce := get_node_or_null("/root/CommerceClient")
	return commerce != null and bool(commerce.owns_cosmetic(id))


func try_unlock_cosmetic(id: String) -> bool:
	if not CosmeticsDB.ITEMS.has(id):
		return false
	if is_cosmetic_unlocked(id):
		return true
	var cost := int(CosmeticsDB.get_item(id).get("cost", 0))
	if not SaveManager.spend_cosmetic_fish({id: cost}, cost):
		return false
	var unlocked: Array = unlocked_cosmetics()
	unlocked.append(id)
	SaveManager.set_value("unlocked_cosmetics", unlocked)
	fish_changed.emit(get_fish())
	cosmetics_changed.emit()
	AudioManager.play_sfx("sfx_unlock")
	return true


## Confirmed earned-fish bundle quote. Validate the entire request before any
## currency/ownership mutation, then expose both changes together to observers.
func try_unlock_cosmetics(ids: Array[String], expected_cost: int) -> bool:
	if expected_cost < 0:
		return false
	var missing: Array[String] = []
	var seen: Dictionary = {}
	var total := 0
	var costs: Dictionary = {}
	for id: String in ids:
		if not CosmeticsDB.ITEMS.has(id):
			return false
		var cost := int(CosmeticsDB.get_item(id).get("cost", 0))
		if cost < 0:
			return false
		if seen.has(id):
			continue
		seen[id] = true
		if is_cosmetic_unlocked(id):
			continue
		missing.append(id)
		costs[id] = cost
		total += cost
	if missing.is_empty() or total != expected_cost or total > get_fish():
		return false
	var unlocked := unlocked_cosmetics().duplicate()
	for id: String in missing:
		unlocked.append(id)
	if not SaveManager.spend_cosmetic_fish(costs, total):
		return false
	SaveManager.set_value("unlocked_cosmetics", unlocked)
	SaveManager.save_now()
	fish_changed.emit(get_fish())
	cosmetics_changed.emit()
	AudioManager.play_sfx("sfx_unlock")
	return true


func equipped() -> Dictionary:
	var result: Dictionary = SaveManager.get_value("equipped", {}).duplicate(true)
	for category: String in result:
		var id := String(result[category])
		if id != "" and not is_cosmetic_unlocked(id):
			result[category] = "body_classic" if category == "body" else ""
	return result


func equip(category: String, id: String) -> void:
	if id != "" and not is_cosmetic_unlocked(id):
		return
	var eq: Dictionary = equipped()
	eq[category] = id
	SaveManager.set_value("equipped", eq)
	cosmetics_changed.emit()


func get_equipped(category: String) -> String:
	return String(equipped().get(category, "body_classic" if category == "body" else ""))


## --- Achievements ---------------------------------------------------------

func is_achievement_unlocked(id: String) -> bool:
	var achieved: Dictionary = SaveManager.get_value("achievements", {})
	return bool(achieved.get(id, false))


func unlock_achievement(id: String) -> void:
	if not AchievementsDB.ITEMS.has(id) or is_achievement_unlocked(id):
		return
	var achieved: Dictionary = SaveManager.get_value("achievements", {})
	achieved[id] = true
	SaveManager.set_value("achievements", achieved)
	add_xp(int(AchievementsDB.get_item(id).get("xp", 150)))
	achievement_unlocked.emit(id)
	AudioManager.play_sfx("sfx_unlock")


func achievements_unlocked_count() -> int:
	var achieved: Dictionary = SaveManager.get_value("achievements", {})
	var count := 0
	for id: String in achieved.keys():
		if bool(achieved[id]):
			count += 1
	return count


## Runner metrics count actual simulation events, separate from wallet grants.
## No historic play time is invented when loading an older save.
func record_runner_activity(seconds: float, metres: float, run_distance: float,
		clean_distance: float) -> void:
	if not is_finite(seconds) or not is_finite(metres) or seconds <= 0.0 or metres <= 0.0:
		return
	var stats: Dictionary = SaveManager.get_value("stats", {})
	var before_seconds := float(stats.get("runner_active_seconds", 0.0))
	stats["runner_active_seconds"] = before_seconds + minf(seconds, 0.25)
	stats["runner_distance_total"] = float(stats.get("runner_distance_total", 0.0)) + metres
	stats["runner_best_distance"] = maxf(float(stats.get("runner_best_distance", 0.0)), run_distance)
	stats["runner_best_clean_distance"] = maxf(float(stats.get("runner_best_clean_distance", 0.0)), clean_distance)
	SaveManager.set_value("stats", stats)
	# Two checks per active second; discrete events and run exit also evaluate.
	if floori(before_seconds * 2.0) < floori(float(stats["runner_active_seconds"]) * 2.0):
		evaluate_runner_achievements()


func record_runner_event(metric: String, amount: int = 1) -> void:
	if metric not in ["runner_fish_collected", "runner_powerups_collected",
			"runner_near_misses", "runner_missions_done"] or amount <= 0:
		return
	increment_stat(metric, amount)
	evaluate_runner_achievements()


func evaluate_runner_achievements() -> void:
	var stats: Dictionary = SaveManager.get_value("stats", {})
	for id: String in AchievementsDB.RUNNER_ORDER:
		var info := AchievementsDB.get_item(id)
		if float(stats.get(String(info["metric"]), 0.0)) >= float(info["target"]):
			unlock_achievement(id)


func runner_achievements_unlocked_count() -> int:
	var count := 0
	for id: String in AchievementsDB.RUNNER_ORDER:
		if is_achievement_unlocked(id):
			count += 1
	return count


func achievement_progress(id: String) -> Dictionary:
	var info := AchievementsDB.get_item(id)
	var stats: Dictionary = SaveManager.get_value("stats", {})
	if info.has("metric"):
		var actual := float(stats.get(String(info["metric"]), 0.0))
		# Existing earned badges never become partial or locked after targets rise.
		if is_achievement_unlocked(id) and actual < float(info["target"]):
			return {"current":float(info["target"]), "target":info["target"],
				"unit":info["unit"], "earned_before_rebalance":true}
		return {"current": minf(float(stats.get(String(info["metric"]), 0.0)), float(info["target"])),
			"target": info["target"], "unit": info["unit"]}
	match id:
		"fish_hoarder": return {"current": int(stats.get("fish_total", 0)), "target": 500}
		"shove_master": return {"current": int(stats.get("shoves_landed", 0)), "target": 25}
		"long_waddle": return {"current": int(maxf(float(stats.get("endless_best_distance", 0.0)),
			float(stats.get("runner_best_distance", 0.0)))), "target": 2000, "unit": " m"}
		"item_collector":
			var used: Dictionary = stats.get("items_used", {})
			var count := 0
			for power_id: String in PowerupsDB.ORDER:
				if used.has(power_id): count += 1
			return {"current": count, "target": PowerupsDB.ORDER.size()}
	return {}


## --- Records --------------------------------------------------------------

func best_time(course_id: String) -> float:
	var times: Dictionary = SaveManager.get_value("best_times", {})
	return float(times.get(course_id, 0.0))


## Returns true if this is a new record.
func submit_time(course_id: String, time_seconds: float) -> bool:
	var times: Dictionary = SaveManager.get_value("best_times", {})
	var previous := float(times.get(course_id, 0.0))
	if previous > 0.0 and time_seconds >= previous:
		return false
	times[course_id] = time_seconds
	SaveManager.set_value("best_times", times)
	record_set.emit("time", course_id, time_seconds)
	unlock_achievement("time_lord")
	return true


func endless_high_score() -> int:
	return int(SaveManager.get_value("endless_high_score", 0))


func submit_endless_score(score: int, distance: float) -> bool:
	var stats: Dictionary = SaveManager.get_value("stats", {})
	if distance > float(stats.get("endless_best_distance", 0.0)):
		stats["endless_best_distance"] = distance
		SaveManager.set_value("stats", stats)
	if distance >= 2000.0:
		unlock_achievement("long_waddle")
	if score <= endless_high_score():
		return false
	SaveManager.set_value("endless_high_score", score)
	record_set.emit("endless", "", float(score))
	return true


## Waddle Run's best. Kept apart from the Endless Expedition score on purpose:
## the two modes score at completely different rates, so one shared number
## would just show whichever mode inflates faster.
func runner_high_score() -> int:
	return int(SaveManager.get_value("runner_high_score", 0))


func runner_best_distance() -> float:
	var stats: Dictionary = SaveManager.get_value("stats", {})
	return float(stats.get("runner_best_distance", 0.0))


## Returns true when this run set a new best score.
func submit_runner_score(score: int, distance: float) -> bool:
	var stats: Dictionary = SaveManager.get_value("stats", {})
	if distance > float(stats.get("runner_best_distance", 0.0)):
		stats["runner_best_distance"] = distance
		SaveManager.set_value("stats", stats)
	# Waddle Run has its own Long Haul tiers. Retain earned legacy badges, but
	# don't also award the older Endless Expedition badge for this mode.
	if score <= runner_high_score():
		return false
	SaveManager.set_value("runner_high_score", score)
	record_set.emit("runner", "", float(score))
	return true


func gp_record(difficulty: String) -> Dictionary:
	var records: Dictionary = SaveManager.get_value("gp_records", {})
	return records.get(difficulty, {})


func submit_gp_result(difficulty: String, placement: int, points: int) -> void:
	var records: Dictionary = SaveManager.get_value("gp_records", {})
	var previous: Dictionary = records.get(difficulty, {})
	var best_place := int(previous.get("placement", 99))
	if placement < best_place or (placement == best_place and points > int(previous.get("points", 0))):
		records[difficulty] = {"placement": placement, "points": points}
		SaveManager.set_value("gp_records", records)
	unlock_achievement("gp_finish")
	if placement == 1:
		unlock_achievement("gp_gold")


func is_tutorial_complete() -> bool:
	return bool(SaveManager.get_value("tutorial_complete", false))


func complete_tutorial() -> void:
	SaveManager.set_value("tutorial_complete", true)
	unlock_achievement("first_waddle")
