extends Node
## Domain layer over SaveManager: fish, XP, cosmetics, achievements, records.

signal fish_changed(total: int)
signal xp_changed(xp: int, level: int)
signal achievement_unlocked(id: String)
signal cosmetics_changed
signal record_set(kind: String, course_id: String, value: float)

const XP_PER_LEVEL: int = 400


## --- Fish currency --------------------------------------------------------

func get_fish() -> int:
	return int(SaveManager.get_value("fish", 0))


func add_fish(amount: int) -> void:
	if amount <= 0:
		return
	SaveManager.set_value("fish", get_fish() + amount)
	increment_stat("fish_total", amount)
	fish_changed.emit(get_fish())
	if get_stat("fish_total") >= 500:
		unlock_achievement("fish_hoarder")


func spend_fish(amount: int) -> bool:
	if amount > get_fish():
		return false
	SaveManager.set_value("fish", get_fish() - amount)
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
	return id in unlocked_cosmetics() or int(CosmeticsDB.get_item(id).get("cost", 0)) == 0


func try_unlock_cosmetic(id: String) -> bool:
	if is_cosmetic_unlocked(id):
		return true
	var cost := int(CosmeticsDB.get_item(id).get("cost", 0))
	if not spend_fish(cost):
		return false
	var unlocked: Array = unlocked_cosmetics()
	unlocked.append(id)
	SaveManager.set_value("unlocked_cosmetics", unlocked)
	cosmetics_changed.emit()
	AudioManager.play_sfx("sfx_unlock")
	return true


func equipped() -> Dictionary:
	return SaveManager.get_value("equipped", {})


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
	add_xp(150)
	achievement_unlocked.emit(id)
	AudioManager.play_sfx("sfx_unlock")


func achievements_unlocked_count() -> int:
	var achieved: Dictionary = SaveManager.get_value("achievements", {})
	var count := 0
	for id: String in achieved.keys():
		if bool(achieved[id]):
			count += 1
	return count


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
