class_name AchievementsDB
extends RefCounted
## Static achievement catalog. Progress state lives in SaveManager.

## id -> {name, desc, icon (emoji-like hint used by procedural icon painter)}
const LEGACY_ITEMS: Dictionary = {
	"first_waddle": {"name": "Waddle Graduate", "desc": "Complete Waddle School."},
	"first_win": {"name": "First Flipper", "desc": "Win a Quick Race."},
	"glacier_champ": {"name": "Glacier Guardian", "desc": "Win a race on Glacier Gauntlet."},
	"aurora_champ": {"name": "Light Chaser", "desc": "Win a race on Aurora Ascent."},
	"iceberg_champ": {"name": "Bay Boss", "desc": "Win a race on Iceberg Bay."},
	"gp_finish": {"name": "Circuit Waddler", "desc": "Complete a full Grand Prix."},
	"gp_gold": {"name": "Emperor of the Ice", "desc": "Win a Grand Prix cup."},
	"fish_hoarder": {"name": "Fish Tycoon", "desc": "Collect 500 fish in total."},
	"shove_master": {"name": "Flipper Fury", "desc": "Land 25 flipper shoves."},
	"item_collector": {"name": "Gadget Penguin", "desc": "Use every power-up type at least once."},
	"time_lord": {"name": "Tick Tock Waddle", "desc": "Set a Time Trial best time on any course."},
	"long_waddle": {"name": "Expedition Leader", "desc": "Travel 2000m in one Endless Expedition run."},
	"purist": {"name": "No Gadgets Needed", "desc": "Win a race without using any items."},
	"comeback": {"name": "Cold-Blooded Comeback", "desc": "Win a race after dropping to last place."},
}

const LEGACY_ORDER: PackedStringArray = [
	"first_waddle", "first_win", "glacier_champ", "aurora_champ", "iceberg_champ",
	"gp_finish", "gp_gold", "fish_hoarder", "shove_master", "item_collector",
	"time_lord", "long_waddle", "purist", "comeback",
]


## The active runner collection has four progressively harder tiers. Legacy IDs
## keep their exact meanings and rewards, but do not gate this collection.
const TIERS: PackedStringArray = ["bronze", "silver", "gold", "diamond"]
const TIER_XP: PackedInt32Array = [50, 100, 175, 300]
## Player-facing rules mirror the recorded metrics, not the wallet or score.
## They are shared by every tier so the explanation cannot drift by badge.
const RUNNER_EXPLANATIONS: Dictionary = {
	"distance": {"scope": "ACROSS ALL RUNS", "counts": "Every metre travelled in Waddle Run adds to this total. Starting a new run does not reset it."},
	"fish": {"scope": "ACROSS ALL RUNS", "counts": "Fish picked up on the course count, including magnet pickups. Mission rewards and other fish grants do not count; spending fish does not reduce progress."},
	"missions": {"scope": "ACROSS ALL RUNS", "counts": "Each completed mission counts once. A three-mission set can add three, rather than one. Starting a new run keeps completed missions."},
	"time": {"scope": "ACROSS ALL RUNS", "counts": "Only active running time counts. Menus, countdowns, pauses and time after a run ends do not count. Starting a new run keeps this total."},
	"run": {"scope": "IN ONE RUN", "counts": "Reach the distance in one Waddle Run. Distances from separate runs are not added together; your longest run is kept."},
	"clean": {"scope": "ONE HIT-FREE STREAK", "counts": "Travel this far without losing a heart. A hit or a new run starts a new streak; a shield save does not break it. Your longest streak is kept."},
	"near": {"scope": "ACROSS ALL RUNS", "counts": "A close hazard pass counts when CLOSE! appears. Ordinary passes, hits and passes during hit invulnerability do not count. Starting a new run keeps the total."},
	"power": {"scope": "ACROSS ALL RUNS", "counts": "Each magnet, shield or double-points pickup counts once. Repeated types count; using an effect or saving a hit does not add another pickup."},
}
const FAMILIES: Array[Dictionary] = [
	{"id": "distance", "name": "Trailblazer", "metric": "runner_distance_total",
		"targets": [12000, 80000, 300000, 800000], "unit": " m", "verb": "Run %s m in total."},
	{"id": "fish", "name": "Fish Finder", "metric": "runner_fish_collected",
		"targets": [750, 4000, 16000, 45000], "unit": " fish", "verb": "Pick up %s fish during runs."},
	{"id": "missions", "name": "Goal Getter", "metric": "runner_missions_done",
		"targets": [6, 24, 60, 120], "unit": " missions", "verb": "Complete %s missions."},
	{"id": "time", "name": "Ice Veteran", "metric": "runner_active_seconds",
		"targets": [900, 5400, 18000, 36000], "unit": " seconds", "verb": "Run actively for %s in total."},
	{"id": "run", "name": "Long Haul", "metric": "runner_best_distance",
		"targets": [3000, 4500, 6500, 9000], "unit": " m", "verb": "Reach %s m in one run."},
	{"id": "clean", "name": "Untouchable", "metric": "runner_best_clean_distance",
		"targets": [2000, 3000, 4500, 6500], "unit": " m", "verb": "Run %s m without taking a hit."},
	{"id": "near", "name": "Close Shave", "metric": "runner_near_misses",
		"targets": [12, 60, 250, 600], "unit": " close dodges", "verb": "Make %s close hazard dodges in total."},
	{"id": "power", "name": "Power Player", "metric": "runner_powerups_collected",
		"targets": [12, 60, 250, 600], "unit": " power-ups", "verb": "Collect %s power-ups during runs."},
]
static var RUNNER_ORDER: PackedStringArray = _runner_order()
static var ITEMS: Dictionary = _build_items()
## Complete catalog order remains compatible with legacy consumers/validators.
static var ORDER: PackedStringArray = _all_order()

static func _runner_order() -> PackedStringArray:
	var ids := PackedStringArray()
	# Early tiers first, so the first screen presents attainable goals.
	for tier: String in TIERS:
		for family: Dictionary in FAMILIES:
			ids.append("runner_%s_%s" % [family["id"], tier])
	return ids

static func _all_order() -> PackedStringArray:
	var ids := RUNNER_ORDER.duplicate()
	ids.append_array(LEGACY_ORDER)
	return ids

static func _build_items() -> Dictionary:
	var items := LEGACY_ITEMS.duplicate(true)
	for family: Dictionary in FAMILIES:
		for index: int in TIERS.size():
			var target := int(family["targets"][index])
			var amount := _group(target)
			if family["id"] == "time":
				amount = "%d minutes" % (target / 60) if target % 3600 != 0 \
					else "%d hour%s" % [target / 3600, "" if target == 3600 else "s"]
			var id := "runner_%s_%s" % [family["id"], TIERS[index]]
			items[id] = {"name": "%s · %s" % [family["name"], TIERS[index].capitalize()],
				"desc": String(family["verb"]) % amount, "metric": family["metric"],
				"target": target, "unit": family["unit"], "family": family["id"],
				"tier": TIERS[index], "xp": TIER_XP[index],
				"scope": RUNNER_EXPLANATIONS[family["id"]]["scope"],
				"counts": RUNNER_EXPLANATIONS[family["id"]]["counts"]}
	return items

static func get_item(id: String) -> Dictionary:
	return ITEMS.get(id, {})


static func next_tier_id(id: String) -> String:
	var info := get_item(id)
	var index := TIERS.find(String(info.get("tier", "")))
	if index < 0 or index + 1 >= TIERS.size():
		return ""
	return "runner_%s_%s" % [info["family"], TIERS[index + 1]]


static func next_tier_requirement(id: String) -> String:
	var next_id := next_tier_id(id)
	if next_id.is_empty():
		return "Diamond is the final tier." if get_item(id).has("family") else "Legacy trophy — no further tiers."
	var next := get_item(next_id)
	return "Next: %s — %s" % [String(next["tier"]).capitalize(), next["desc"]]


static func _group(value: int) -> String:
	var text := str(value)
	var cursor := text.length() - 3
	while cursor > 0:
		text = text.insert(cursor, ",")
		cursor -= 3
	return text
