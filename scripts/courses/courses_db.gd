class_name CoursesDB
extends RefCounted
## Static course registry.

const ITEMS: Dictionary = {
	"glacier": {
		"name": "Glacier Gauntlet",
		"desc": "A bright beginner-friendly glacier run with ice caves, a cracking-ice shortcut, and one big final slide.",
		"script": "res://scripts/courses/course_glacier.gd",
		"theme_color": Color(0.45, 0.75, 0.95),
		"music": "music_race",
		"par_time": 150.0,
	},
	"aurora": {
		"name": "Aurora Ascent",
		"desc": "A twilight mountain climb under the southern lights, with wind, icicles, and a wild corkscrew descent.",
		"script": "res://scripts/courses/course_aurora.gd",
		"theme_color": Color(0.45, 0.9, 0.65),
		"music": "music_aurora",
		"par_time": 165.0,
	},
	"iceberg": {
		"name": "Iceberg Bay",
		"desc": "Sunset ocean racing across drifting bergs, swim channels, wave ramps, and very relaxed seals.",
		"script": "res://scripts/courses/course_iceberg.gd",
		"theme_color": Color(0.98, 0.62, 0.4),
		"music": "music_iceberg",
		"par_time": 160.0,
	},
}

const ORDER: PackedStringArray = ["glacier", "aurora", "iceberg"]
const GRAND_PRIX_ORDER: PackedStringArray = ["glacier", "aurora", "iceberg"]


static func get_item(id: String) -> Dictionary:
	return ITEMS.get(id, {})


static func display_name(id: String) -> String:
	return String(ITEMS.get(id, {}).get("name", id))
