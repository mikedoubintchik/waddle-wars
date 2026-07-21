class_name PowerupsDB
extends RefCounted
## Static power-up catalog. Behavior implemented in scripts/gameplay/powerups.gd.

const ITEMS: Dictionary = {
	"snowball": {
		"name": "Snowball",
		"desc": "Lob a snowball at the racer ahead.",
		"color": Color(0.92, 0.96, 1.0),
		"icon": "snowball",
	},
	"shield": {
		"name": "Ice Shield",
		"desc": "Blocks one attack or hazard hit.",
		"color": Color(0.45, 0.85, 1.0),
		"icon": "shield",
	},
	"fish_frenzy": {
		"name": "Fish Frenzy",
		"desc": "A burst of pure fish-powered speed.",
		"color": Color(1.0, 0.75, 0.25),
		"icon": "bolt",
	},
	"magnet": {
		"name": "Fish Magnet",
		"desc": "Pulls nearby fish to you for a while.",
		"color": Color(0.9, 0.4, 0.65),
		"icon": "magnet",
	},
	"blizzard": {
		"name": "Blizzard Burst",
		"desc": "Drop a slippery snow squall behind you.",
		"color": Color(0.75, 0.85, 0.98),
		"icon": "cloud",
	},
}

const ORDER: PackedStringArray = ["snowball", "shield", "fish_frenzy", "magnet", "blizzard"]

## Weighted tables by race position band. Lower positions get slightly
## stronger help — bounded, no obvious cheating.
const WEIGHTS_FRONT: Dictionary = {"snowball": 2, "shield": 4, "fish_frenzy": 1, "magnet": 3, "blizzard": 3}
const WEIGHTS_MID: Dictionary = {"snowball": 3, "shield": 3, "fish_frenzy": 3, "magnet": 2, "blizzard": 2}
const WEIGHTS_BACK: Dictionary = {"snowball": 3, "shield": 2, "fish_frenzy": 5, "magnet": 2, "blizzard": 1}


static func roll(position: int, racer_count: int, rng: RandomNumberGenerator) -> String:
	var band: Dictionary
	var third: float = float(racer_count) / 3.0
	if position <= ceili(third):
		band = WEIGHTS_FRONT
	elif position <= ceili(third * 2.0):
		band = WEIGHTS_MID
	else:
		band = WEIGHTS_BACK
	var total: int = 0
	for id: String in band.keys():
		total += int(band[id])
	var pick: int = rng.randi_range(1, total)
	for id: String in band.keys():
		pick -= int(band[id])
		if pick <= 0:
			return id
	return "shield"


static func get_item(id: String) -> Dictionary:
	return ITEMS.get(id, {})
