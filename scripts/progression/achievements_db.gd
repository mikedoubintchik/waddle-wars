class_name AchievementsDB
extends RefCounted
## Static achievement catalog. Progress state lives in SaveManager.

## id -> {name, desc, icon (emoji-like hint used by procedural icon painter)}
const ITEMS: Dictionary = {
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

const ORDER: PackedStringArray = [
	"first_waddle", "first_win", "glacier_champ", "aurora_champ", "iceberg_champ",
	"gp_finish", "gp_gold", "fish_hoarder", "shove_master", "item_collector",
	"time_lord", "long_waddle", "purist", "comeback",
]


static func get_item(id: String) -> Dictionary:
	return ITEMS.get(id, {})
