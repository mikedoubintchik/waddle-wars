class_name SurfacesDB
extends RefCounted
## Surface physics tuning. Surfaces are tagged on course geometry via metadata.

enum Surface { PACKED_SNOW, DEEP_SNOW, ICE_SMOOTH, ICE_ROUGH, WATER, BOOST }

## accel: ground acceleration multiplier. max_speed: top speed multiplier.
## grip: steering authority (1 = full). slide_keep: momentum kept per second
## while belly sliding (higher = slicker). slide_bonus: flat slide accel bonus.
const ITEMS: Dictionary = {
	Surface.PACKED_SNOW: {
		"name": "Packed Snow",
		"accel": 1.0, "max_speed": 1.0, "grip": 1.0,
		"slide_keep": 0.90, "slide_bonus": 0.0,
	},
	Surface.DEEP_SNOW: {
		"name": "Deep Snow",
		"accel": 0.55, "max_speed": 0.72, "grip": 0.85,
		"slide_keep": 0.62, "slide_bonus": -3.0,
	},
	Surface.ICE_SMOOTH: {
		"name": "Smooth Ice",
		"accel": 0.8, "max_speed": 1.12, "grip": 0.45,
		"slide_keep": 0.985, "slide_bonus": 2.0,
	},
	Surface.ICE_ROUGH: {
		"name": "Rough Ice",
		"accel": 0.9, "max_speed": 1.05, "grip": 0.7,
		"slide_keep": 0.94, "slide_bonus": 1.0,
	},
	Surface.WATER: {
		"name": "Water",
		"accel": 0.75, "max_speed": 0.95, "grip": 0.8,
		"slide_keep": 0.9, "slide_bonus": 0.0,
	},
	Surface.BOOST: {
		"name": "Boost",
		"accel": 1.4, "max_speed": 1.45, "grip": 0.9,
		"slide_keep": 0.97, "slide_bonus": 4.0,
	},
}


static func get_item(surface: Surface) -> Dictionary:
	return ITEMS.get(surface, ITEMS[Surface.PACKED_SNOW])
