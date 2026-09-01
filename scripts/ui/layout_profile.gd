class_name LayoutProfile
extends Resource
## Shared viewport contract for gameplay cameras, HUDs, touch zones and menus.
##
## Layout decisions are based on usable geometry, never device labels. A large
## accessibility scale can make a tablet behave like a narrow phone; a small
## desktop window can behave like a compact landscape handset. Consumers keep
## their authored layout, then read these semantic values instead of each
## inventing a different `width < height` branch.

enum ViewClass {
	PORTRAIT_NARROW,
	PORTRAIT_TABLET,
	LANDSCAPE_COMPACT,
	LANDSCAPE_WIDE,
}

const PORTRAIT_TABLET_MIN_WIDTH: float = 900.0
const LANDSCAPE_WIDE_MIN_WIDTH: float = 1500.0
const LANDSCAPE_WIDE_MIN_HEIGHT: float = 820.0
const TOUCH_EDGE_FRACTION: float = 0.36
const TOUCH_SAFE_FLOOR: float = 24.0

var view_class: ViewClass = ViewClass.LANDSCAPE_WIDE
var viewport_size: Vector2 = Vector2(1920.0, 1080.0)
## Insets use left/top/right/bottom ordering in logical viewport units.
var safe_insets: Vector4 = Vector4.ZERO
var safe_rect: Rect2 = Rect2(Vector2.ZERO, viewport_size)

## Presentation targets. Gameplay remains authoritative; these only compose it.
var hero_frame_height: float = 0.16
var decision_horizon_m: float = 60.0
var chase_distance: float = 5.0
var chase_height: float = 2.5
var base_fov: float = 68.0
var look_ahead: float = 3.2
var runner_chase_distance: float = 5.9
var runner_chase_height: float = 2.95
var runner_base_fov: float = 74.0
var runner_look_ahead: float = 11.0

## UI/touch policy shared across controllers.
var hud_edge_margin: float = 24.0
var menu_width_fraction: float = 0.78
var touch_left_zone: Rect2 = Rect2()
var touch_right_zone: Rect2 = Rect2()


static func for_view_size(size: Vector2, insets: Vector4 = Vector4.ZERO) -> LayoutProfile:
	var profile := LayoutProfile.new()
	profile.viewport_size = Vector2(maxf(size.x, 1.0), maxf(size.y, 1.0))
	var left := clampf(insets.x, 0.0, profile.viewport_size.x - 1.0)
	var top := clampf(insets.y, 0.0, profile.viewport_size.y - 1.0)
	profile.safe_insets = Vector4(
		left, top,
		clampf(insets.z, 0.0, profile.viewport_size.x - left - 1.0),
		clampf(insets.w, 0.0, profile.viewport_size.y - top - 1.0))
	# Classify the rectangle that content and cameras can actually use. A tablet
	# split view or asymmetric fold/notch may have a wide raw framebuffer while
	# exposing only compact geometry; classifying the raw viewport would choose
	# controls and framing that cannot fit inside its safe area.
	var usable_size := Vector2(
		maxf(profile.viewport_size.x - profile.safe_insets.x - profile.safe_insets.z, 1.0),
		maxf(profile.viewport_size.y - profile.safe_insets.y - profile.safe_insets.w, 1.0))
	profile.view_class = classify(usable_size)
	profile._apply_contract()
	return profile


## Builds the shared contract from a live viewport, including platform safe
## area insets converted into logical canvas units. Tests and layout previews
## should prefer for_view_size() so their geometry remains deterministic.
static func for_viewport(viewport: Viewport) -> LayoutProfile:
	if viewport == null:
		return for_view_size(Vector2.ONE)
	return for_view_size(viewport.get_visible_rect().size,
		safe_insets_for_viewport(viewport))


## Returns left/top/right/bottom insets in the same logical units as input
## events and Control rects. Native safe areas arrive in physical screen
## pixels; browser CSS env() values are promoted to device pixels first.
## A small touch-only floor protects rounded corners on platforms that report
## an empty safe area. Desktop/headless geometry remains bit-for-bit unchanged.
## Test hook, in the style of GameConfig.force_touch: forces the insets a
## notched phone reports. A desktop window has none, so without this a harness
## measures a screen 48 units wider than any real handset — which is exactly
## the margin the main menu's status chip was overflowing into.
static var forced_insets: Vector4 = Vector4(-1.0, -1.0, -1.0, -1.0)


static func safe_insets_for_viewport(viewport: Viewport) -> Vector4:
	if forced_insets.x >= 0.0:
		return forced_insets
	if viewport == null or GameConfig.is_headless():
		return Vector4.ZERO
	var view_size := viewport.get_visible_rect().size
	var window := viewport.get_window()
	if view_size.x <= 0.0 or view_size.y <= 0.0 or window == null \
			or window.size.x <= 0 or window.size.y <= 0:
		return Vector4.ZERO
	var logical_per_physical := Vector2(
		view_size.x / float(window.size.x), view_size.y / float(window.size.y))
	var physical := _web_safe_insets() if OS.has_feature("web") \
		else _native_safe_insets()
	var logical := Vector4(
		physical.x * logical_per_physical.x,
		physical.y * logical_per_physical.y,
		physical.z * logical_per_physical.x,
		physical.w * logical_per_physical.y)
	if GameConfig.has_touchscreen() or GameConfig.is_mobile():
		logical = Vector4(
			maxf(logical.x, TOUCH_SAFE_FLOOR),
			maxf(logical.y, TOUCH_SAFE_FLOOR),
			maxf(logical.z, TOUCH_SAFE_FLOOR),
			maxf(logical.w, TOUCH_SAFE_FLOOR))
	return logical


static func classify(size: Vector2) -> ViewClass:
	if size.y >= size.x:
		return ViewClass.PORTRAIT_TABLET \
			if size.x >= PORTRAIT_TABLET_MIN_WIDTH else ViewClass.PORTRAIT_NARROW
	return ViewClass.LANDSCAPE_WIDE \
		if size.x >= LANDSCAPE_WIDE_MIN_WIDTH and size.y >= LANDSCAPE_WIDE_MIN_HEIGHT \
		else ViewClass.LANDSCAPE_COMPACT


func is_portrait() -> bool:
	return view_class == ViewClass.PORTRAIT_NARROW \
		or view_class == ViewClass.PORTRAIT_TABLET


func is_compact() -> bool:
	return view_class == ViewClass.PORTRAIT_NARROW \
		or view_class == ViewClass.LANDSCAPE_COMPACT


func contains_safe_rect(rect: Rect2, epsilon: float = 0.001) -> bool:
	return rect.position.x >= safe_rect.position.x - epsilon \
		and rect.position.y >= safe_rect.position.y - epsilon \
		and rect.end.x <= safe_rect.end.x + epsilon \
		and rect.end.y <= safe_rect.end.y + epsilon


func class_name_text() -> StringName:
	match view_class:
		ViewClass.PORTRAIT_NARROW:
			return &"portrait_narrow"
		ViewClass.PORTRAIT_TABLET:
			return &"portrait_tablet"
		ViewClass.LANDSCAPE_COMPACT:
			return &"landscape_compact"
		_:
			return &"landscape_wide"


func _apply_contract() -> void:
	match view_class:
		ViewClass.PORTRAIT_NARROW:
			hero_frame_height = 0.18
			decision_horizon_m = 62.0
			chase_distance = 7.2
			chase_height = 3.9
			base_fov = 78.0
			look_ahead = 5.0
			runner_chase_distance = 7.5
			runner_chase_height = 4.15
			runner_base_fov = 82.0
			runner_look_ahead = 15.0
			hud_edge_margin = 20.0
			menu_width_fraction = 0.88
		ViewClass.PORTRAIT_TABLET:
			hero_frame_height = 0.16
			decision_horizon_m = 68.0
			chase_distance = 6.7
			chase_height = 3.6
			base_fov = 75.0
			look_ahead = 4.5
			runner_chase_distance = 7.0
			runner_chase_height = 3.8
			runner_base_fov = 78.0
			runner_look_ahead = 14.0
			hud_edge_margin = 28.0
			menu_width_fraction = 0.82
		ViewClass.LANDSCAPE_COMPACT:
			hero_frame_height = 0.18
			decision_horizon_m = 55.0
			chase_distance = 5.0
			chase_height = 2.5
			base_fov = 68.0
			look_ahead = 3.2
			runner_chase_distance = 5.9
			runner_chase_height = 2.95
			runner_base_fov = 74.0
			runner_look_ahead = 11.0
			hud_edge_margin = 20.0
			menu_width_fraction = 0.86
		ViewClass.LANDSCAPE_WIDE:
			hero_frame_height = 0.15
			decision_horizon_m = 65.0
			chase_distance = 5.4
			chase_height = 2.7
			base_fov = 67.0
			look_ahead = 3.8
			runner_chase_distance = 6.2
			runner_chase_height = 3.1
			runner_base_fov = 72.0
			runner_look_ahead = 12.0
			hud_edge_margin = 28.0
			menu_width_fraction = 0.72

	var left := safe_insets.x
	var top := safe_insets.y
	var right := safe_insets.z
	var bottom := safe_insets.w
	var usable_size := Vector2(
		maxf(viewport_size.x - left - right, 1.0),
		maxf(viewport_size.y - top - bottom, 1.0))
	safe_rect = Rect2(Vector2(left, top), usable_size)

	# Bottom touch regions stay out of the central play-reading strip. They are
	# hints for explicit controls; runner swipes still use the whole safe rect.
	var zone_top := safe_rect.position.y + safe_rect.size.y * 0.58
	var zone_height := maxf(safe_rect.end.y - zone_top, 1.0)
	var edge_width := safe_rect.size.x * TOUCH_EDGE_FRACTION
	touch_left_zone = Rect2(Vector2(safe_rect.position.x, zone_top),
		Vector2(edge_width, zone_height))
	touch_right_zone = Rect2(Vector2(safe_rect.end.x - edge_width, zone_top),
		Vector2(edge_width, zone_height))


static func _native_safe_insets() -> Vector4:
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	var origin := DisplayServer.screen_get_position()
	if safe.size.x <= 0 or safe.size.y <= 0 or screen.x <= 0 or screen.y <= 0:
		return Vector4.ZERO
	return Vector4(
		maxf(float(safe.position.x - origin.x), 0.0),
		maxf(float(safe.position.y - origin.y), 0.0),
		maxf(float(origin.x + screen.x - safe.end.x), 0.0),
		maxf(float(origin.y + screen.y - safe.end.y), 0.0))


static func _web_safe_insets() -> Vector4:
	var raw: Variant = JavaScriptBridge.eval("""
		(function () {
			var d = document.createElement('div');
			d.style.cssText = 'position:fixed;left:0;top:0;width:0;height:0;' +
				'padding-left:env(safe-area-inset-left);' +
				'padding-top:env(safe-area-inset-top);' +
				'padding-right:env(safe-area-inset-right);' +
				'padding-bottom:env(safe-area-inset-bottom);';
			document.body.appendChild(d);
			var cs = getComputedStyle(d);
			var dpr = window.devicePixelRatio || 1;
			var values = [cs.paddingLeft, cs.paddingTop,
				cs.paddingRight, cs.paddingBottom].map(function (value) {
					return (parseFloat(value) || 0) * dpr;
				});
			d.remove();
			return values.join(',');
		})()
	""", true)
	var parts := String(raw).split(",") if raw != null else PackedStringArray()
	if parts.size() != 4:
		return Vector4.ZERO
	return Vector4(
		maxf(float(parts[0]), 0.0), maxf(float(parts[1]), 0.0),
		maxf(float(parts[2]), 0.0), maxf(float(parts[3]), 0.0))
