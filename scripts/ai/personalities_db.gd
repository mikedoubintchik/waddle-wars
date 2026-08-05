class_name PersonalitiesDB
extends RefCounted
## The seven AI rivals: names, looks, and behavior personalities.

## aggression: shove/target seeking. shortcut_pref: risky branch choice.
## item_focus: detours for item boxes / holds items smartly.
## caution: hazard avoidance margin. risk: speed through danger.
## consistency: inverse of random mistakes. skill: baseline steering quality.
##
## Each rival is a different real penguin species (the player's default body
## is Emperor, so a full grid shows all eight). body_color/belly_color must
## stay exactly equal to PenguinVisual.SPECIES canonical dorsal/ventral —
## race_manager only forwards those two colors, and the species markings are
## resolved from the dorsal color. accent_color is a trim/UI hint (trails,
## HUD, minimap), never a body recolor.
const ITEMS: Dictionary = {
	"gus": {
		"name": "Gus", "style": "Balanced", "species": "gentoo",
		"body_color": Color(0.10, 0.11, 0.13), "belly_color": Color(0.96, 0.96, 0.95),
		"accent_color": Color(0.3, 0.6, 0.9), "hat": "hat_beanie",
		"aggression": 0.5, "shortcut_pref": 0.5, "item_focus": 0.5,
		"caution": 0.5, "risk": 0.5, "consistency": 0.6, "skill": 0.6,
	},
	"pippa": {
		"name": "Pippa", "style": "Aggressive", "species": "chinstrap",
		"body_color": Color(0.12, 0.13, 0.15), "belly_color": Color(0.97, 0.96, 0.94),
		"accent_color": Color(0.9, 0.25, 0.3), "hat": "",
		"aggression": 0.95, "shortcut_pref": 0.4, "item_focus": 0.6,
		"caution": 0.3, "risk": 0.7, "consistency": 0.5, "skill": 0.65,
	},
	"scooter": {
		"name": "Scooter", "style": "Shortcut Seeker", "species": "macaroni",
		"body_color": Color(0.13, 0.11, 0.10), "belly_color": Color(0.97, 0.94, 0.88),
		"accent_color": Color(0.3, 0.85, 0.5), "hat": "goggles_ski",
		"aggression": 0.3, "shortcut_pref": 0.95, "item_focus": 0.4,
		"caution": 0.35, "risk": 0.8, "consistency": 0.55, "skill": 0.6,
	},
	"marina": {
		"name": "Marina", "style": "Item Expert", "species": "king",
		"body_color": Color(0.16, 0.18, 0.21), "belly_color": Color(0.97, 0.95, 0.90),
		"accent_color": Color(0.85, 0.45, 0.85), "hat": "scarf_bowtie",
		"aggression": 0.55, "shortcut_pref": 0.45, "item_focus": 0.95,
		"caution": 0.55, "risk": 0.45, "consistency": 0.65, "skill": 0.62,
	},
	"bruno": {
		"name": "Bruno", "style": "Defensive", "species": "adelie",
		"body_color": Color(0.06, 0.06, 0.07), "belly_color": Color(0.97, 0.97, 0.96),
		"accent_color": Color(0.6, 0.45, 0.25), "hat": "scarf_red",
		"aggression": 0.25, "shortcut_pref": 0.3, "item_focus": 0.6,
		"caution": 0.9, "risk": 0.2, "consistency": 0.8, "skill": 0.58,
	},
	"ziggy": {
		"name": "Ziggy", "style": "Daredevil", "species": "rockhopper",
		"body_color": Color(0.16, 0.14, 0.13), "belly_color": Color(0.98, 0.95, 0.86),
		"accent_color": Color(0.98, 0.75, 0.2), "hat": "hat_crown",
		"aggression": 0.6, "shortcut_pref": 0.8, "item_focus": 0.35,
		"caution": 0.1, "risk": 0.98, "consistency": 0.35, "skill": 0.68,
	},
	"nova": {
		"name": "Nova", "style": "Consistent", "species": "little_blue",
		"body_color": Color(0.45, 0.53, 0.62), "belly_color": Color(0.96, 0.97, 0.97),
		"accent_color": Color(0.4, 0.9, 0.85), "hat": "hat_earwarmers",
		"aggression": 0.35, "shortcut_pref": 0.4, "item_focus": 0.5,
		"caution": 0.65, "risk": 0.35, "consistency": 0.95, "skill": 0.66,
	},
}

const ORDER: PackedStringArray = ["gus", "pippa", "scooter", "marina", "bruno", "ziggy", "nova"]


static func get_item(id: String) -> Dictionary:
	return ITEMS.get(id, ITEMS["gus"])
