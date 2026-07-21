class_name DifficultyDB
extends RefCounted
## AI difficulty tuning tables.

const ITEMS: Dictionary = {
	"chill": {
		"name": "Chill",
		"desc": "Relaxed rivals for a friendly waddle.",
		"reaction_delay": 0.55,
		"steer_precision": 0.6,
		"mistake_rate": 0.35,
		"speed_scale": 0.86,
		"item_aggression": 0.35,
		"shortcut_chance": 0.2,
		"rubberband": 0.10,
	},
	"competitive": {
		"name": "Competitive",
		"desc": "Rivals who actually want the fish.",
		"reaction_delay": 0.3,
		"steer_precision": 0.82,
		"mistake_rate": 0.15,
		"speed_scale": 0.95,
		"item_aggression": 0.65,
		"shortcut_chance": 0.5,
		"rubberband": 0.14,
	},
	"emperor": {
		"name": "Emperor",
		"desc": "Ruthless, precise, majestic. Good luck.",
		"reaction_delay": 0.14,
		"steer_precision": 0.96,
		"mistake_rate": 0.05,
		"speed_scale": 1.0,
		"item_aggression": 0.9,
		"shortcut_chance": 0.8,
		"rubberband": 0.18,
	},
}

const ORDER: PackedStringArray = ["chill", "competitive", "emperor"]


static func get_item(id: String) -> Dictionary:
	return ITEMS.get(id, ITEMS["competitive"])
