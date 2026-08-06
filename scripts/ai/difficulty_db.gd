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
		"reaction_delay": 0.26,
		"steer_precision": 0.88,
		"mistake_rate": 0.10,
		"speed_scale": 0.97,
		"item_aggression": 0.7,
		"shortcut_chance": 0.55,
		"rubberband": 0.17,
	},
	## Autopilot profile for the Waddle School demo drive. Frozen at the
	## pre-2026-08-06 "competitive" numbers: the buffed race profile carries
	## enough pace and steering precision to overshoot the lesson obstacles,
	## which stalls the unattended run. Not selectable by players.
	"tutorial_demo": {
		"name": "Demo",
		"desc": "Autopilot profile used by Waddle School.",
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
		"reaction_delay": 0.12,
		"steer_precision": 0.98,
		"mistake_rate": 0.03,
		"speed_scale": 1.02,
		"item_aggression": 0.95,
		"shortcut_chance": 0.85,
		"rubberband": 0.2,
	},
}

const ORDER: PackedStringArray = ["chill", "competitive", "emperor"]


static func get_item(id: String) -> Dictionary:
	return ITEMS.get(id, ITEMS["competitive"])
