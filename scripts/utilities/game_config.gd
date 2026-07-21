extends Node
## Central game configuration. The displayed game name lives here so it can be
## renamed in one place.

const GAME_NAME: String = "Waddle Wars"
const GAME_VERSION: String = "1.0.0"
const STUDIO_NAME: String = "Blubber & Byte"
const SAVE_VERSION: int = 1

## Physics layers (keep in sync with project.godot layer_names).
const LAYER_WORLD: int = 1
const LAYER_RACERS: int = 2
const LAYER_PICKUPS: int = 4
const LAYER_HAZARDS: int = 8
const LAYER_WATER: int = 16
const LAYER_TRIGGERS: int = 32

## Node groups.
const GROUP_RACERS: StringName = &"racers"
const GROUP_PLAYER: StringName = &"player"
const GROUP_CHECKPOINTS: StringName = &"checkpoints"

const RACER_COUNT: int = 8


static func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


static func is_mobile() -> bool:
	return OS.has_feature("mobile")


static func has_touchscreen() -> bool:
	return DisplayServer.is_touchscreen_available()
