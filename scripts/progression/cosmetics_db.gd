class_name CosmeticsDB
extends RefCounted
## Static cosmetic catalog. Cosmetics never affect gameplay.

const CATEGORIES: PackedStringArray = ["body", "hat", "scarf", "goggles", "trail"]

const CATEGORY_NAMES: Dictionary = {
	"body": "Penguins",
	"hat": "Hats",
	"scarf": "Neckwear",
	"goggles": "Eyewear",
	"trail": "Trails",
}

## id -> {name, category, cost, desc, colors...}
## Body items are real penguin species rendered by PenguinVisual.SPECIES.
## body_color must stay exactly equal to that species' canonical "dorsal"
## color — consumers only forward body_color/belly_color into setup(), and
## the species (markings, scale, bill, feet) is resolved from that color.
## Legacy ids are kept for save compatibility: body_classic -> Emperor,
## body_snowy -> Little Blue, body_midnight -> King (owners keep unlocks).
const ITEMS: Dictionary = {
	"body_classic": {
		"name": "Emperor", "category": "body", "cost": 0, "species": "emperor",
		"desc": "The regal original. Golden ear patches, unbothered pace.",
		"body_color": Color(0.13, 0.16, 0.22), "belly_color": Color(0.95, 0.94, 0.9),
	},
	"body_adelie": {
		"name": "Adelie", "category": "body", "cost": 0, "species": "adelie",
		"desc": "Sharpest tuxedo on the ice. White eye rings, chaos inside.",
		"body_color": Color(0.06, 0.06, 0.07), "belly_color": Color(0.97, 0.97, 0.96),
	},
	"body_gentoo": {
		"name": "Gentoo", "category": "body", "cost": 0, "species": "gentoo",
		"desc": "White headband, orange bill, fastest flippers in the sea.",
		"body_color": Color(0.10, 0.11, 0.13), "belly_color": Color(0.96, 0.96, 0.95),
	},
	"body_chinstrap": {
		"name": "Chinstrap", "category": "body", "cost": 150, "species": "chinstrap",
		"desc": "Wears the helmet strap at all times. Safety first.",
		"body_color": Color(0.12, 0.13, 0.15), "belly_color": Color(0.97, 0.96, 0.94),
	},
	"body_snowy": {
		"name": "Little Blue", "category": "body", "cost": 150, "species": "little_blue",
		"desc": "The smallest penguin in the world. Slate blue and speedy.",
		"body_color": Color(0.45, 0.53, 0.62), "belly_color": Color(0.96, 0.97, 0.97),
	},
	"body_midnight": {
		"name": "King", "category": "body", "cost": 200, "species": "king",
		"desc": "Vivid orange teardrops. Second largest, first in style.",
		"body_color": Color(0.16, 0.18, 0.21), "belly_color": Color(0.97, 0.95, 0.90),
	},
	"body_rockhopper": {
		"name": "Rockhopper", "category": "body", "cost": 300, "species": "rockhopper",
		"desc": "Wild golden brows and zero patience.",
		"body_color": Color(0.16, 0.14, 0.13), "belly_color": Color(0.98, 0.95, 0.86),
		"crest_color": Color(0.98, 0.82, 0.2),
	},
	"body_macaroni": {
		"name": "Macaroni", "category": "body", "cost": 350, "species": "macaroni",
		"desc": "Droopy golden crest. Named for fashion, not pasta.",
		"body_color": Color(0.13, 0.11, 0.10), "belly_color": Color(0.97, 0.94, 0.88),
	},
	"hat_beanie": {
		"name": "Cozy Beanie", "category": "hat", "cost": 50,
		"desc": "Hand-knitted by research station volunteers.",
		"color": Color(0.85, 0.25, 0.25),
	},
	"hat_earwarmers": {
		"name": "Ear Warmers", "category": "hat", "cost": 120,
		"desc": "Penguins do have ears. Probably.",
		"color": Color(0.4, 0.7, 0.95),
	},
	"hat_headset": {
		"name": "Research Headset", "category": "hat", "cost": 200,
		"desc": "For coordinating very serious waddle science.",
		"color": Color(0.9, 0.6, 0.15),
	},
	"hat_crown": {
		"name": "Emperor's Crown", "category": "hat", "cost": 400,
		"desc": "Rule the ice with style.",
		"color": Color(0.98, 0.8, 0.2),
	},
	"scarf_red": {
		"name": "Red Scarf", "category": "scarf", "cost": 80,
		"desc": "A classic look for a classy bird.",
		"color": Color(0.85, 0.2, 0.22),
	},
	"scarf_rainbow": {
		"name": "Rainbow Scarf", "category": "scarf", "cost": 250,
		"desc": "Knitted from pure joy.",
		"color": Color(0.9, 0.4, 0.7),
	},
	"scarf_bowtie": {
		"name": "Bow Tie", "category": "scarf", "cost": 100,
		"desc": "Formal wear for formal waddling.",
		"color": Color(0.2, 0.45, 0.9),
	},
	"goggles_ski": {
		"name": "Ski Goggles", "category": "goggles", "cost": 150,
		"desc": "See the course. Be the course.",
		"color": Color(0.3, 0.85, 0.9),
	},
	"goggles_aviator": {
		"name": "Aviators", "category": "goggles", "cost": 220,
		"desc": "Penguins can't fly, but they can look like pilots.",
		"color": Color(0.25, 0.25, 0.3),
	},
	"trail_snowflake": {
		"name": "Snowflake Trail", "category": "trail", "cost": 300,
		"desc": "Leave a flurry wherever you waddle.",
		"color": Color(0.85, 0.95, 1.0),
	},
	"trail_fish": {
		"name": "Fish Trail", "category": "trail", "cost": 350,
		"desc": "A shimmering school follows your success.",
		"color": Color(0.5, 0.85, 0.95),
	},
	"trail_aurora": {
		"name": "Aurora Trail", "category": "trail", "cost": 500,
		"desc": "Carry the southern lights with you.",
		"color": Color(0.4, 0.95, 0.7),
	},
}


static func get_item(id: String) -> Dictionary:
	return ITEMS.get(id, {})


static func items_in_category(category: String) -> Array[String]:
	var result: Array[String] = []
	for id: String in ITEMS.keys():
		if ITEMS[id]["category"] == category:
			result.append(id)
	result.sort_custom(func(a: String, b: String) -> bool:
		return int(ITEMS[a]["cost"]) < int(ITEMS[b]["cost"]))
	return result
