extends Node
## Central game configuration. The displayed game name lives here so it can be
## renamed in one place.

const GAME_NAME: String = "Waddle Wars"
const GAME_VERSION: String = "1.0.0"
## Short git hash of the build, stamped by tools/deploy_cloudflare.sh at export
## time. "dev" in a working tree.
##
## This exists because three separate bug reports this week turned out to be a
## stale cached build rather than the defect described, and there was no way to
## tell from a screenshot which code the player was actually running. Now there
## is.
const BUILD_ID: String = "dev"
const STUDIO_NAME: String = "Ninja Consulting"
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


## Cached is_web_chrome() probe: -1 unknown, 0 no, 1 yes.
static var _web_chrome: int = -1


static func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


static func is_mobile() -> bool:
	return OS.has_feature("mobile")


## True only for a web export running in a browser that reports itself as
## Chrome (Edge ships "Edg", Opera ships "OPR", Safari never says "Chrome").
##
## Chrome does not talk to the GPU directly on macOS: WebGL2 goes through
## ANGLE and out to Metal, and translating + linking a shader program there
## costs milliseconds where Safari's native GL path costs microseconds. The
## same course that plays clean in Safari stutters in Chrome purely on
## first-sight program links and per-draw-call driver overhead, so a few
## subsystems (ShaderWarmup, VisualLibrary dressing culling) spend extra
## budget up front or trim the far field when this is true.
##
## Probed once through JavaScriptBridge and cached; always false on desktop,
## on native mobile, and headless — the eval never runs off web.
static func is_web_chrome() -> bool:
	if _web_chrome >= 0:
		return _web_chrome == 1
	_web_chrome = 0
	if OS.has_feature("web") and not is_headless():
		var probe: Variant = JavaScriptBridge.eval("navigator.userAgent || ''", true)
		var agent := String(probe) if probe != null else ""
		if agent.contains("Chrome") and not agent.contains("Edg") and not agent.contains("OPR"):
			_web_chrome = 1
	return _web_chrome == 1


## QA override for the touch/phone code paths. Nothing in the game sets it;
## the screenshot harness does (`touch=1`).
##
## It has to live HERE rather than in UITheme, because the phone layout is
## decided in two places: UITheme.is_touch() picks the touch metrics, and
## SettingsManager._apply_ui_scale applies TOUCH_UI_BOOST, which shrinks the
## design canvas. Forcing only the first gives a canvas no phone ever has --
## which is exactly the mistake that made the last results-screen fix useless.
static var force_touch: bool = false


static func has_touchscreen() -> bool:
	return force_touch or DisplayServer.is_touchscreen_available()
