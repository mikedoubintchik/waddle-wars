class_name UITheme
extends RefCounted
## Shared UI styling helpers: consistent colors, buttons with visible
## hover/focus/pressed/disabled states, panels, headings, and the animated
## menu backdrop (gradient + aurora sweep + drifting snow) used by every menu.

const COLOR_BG: Color = Color(0.078, 0.141, 0.239)  # deep navy
const COLOR_BG_DARK: Color = Color(0.055, 0.098, 0.172)
const COLOR_BG_DEEP: Color = Color(0.031, 0.055, 0.106)
const COLOR_PANEL: Color = Color(0.075, 0.129, 0.220, 0.94)
const COLOR_ACCENT: Color = Color(0.498, 0.816, 0.968)  # ice blue #7fd0f7
const COLOR_GOLD: Color = Color(0.961, 0.773, 0.259)  # gold #f5c542
const COLOR_TEXT: Color = Color(0.93, 0.96, 1.0)
const COLOR_TEXT_DIM: Color = Color(0.62, 0.72, 0.84)
const COLOR_DISABLED: Color = Color(0.42, 0.48, 0.58)
const COLOR_SHADOW: Color = Color(0.0, 0.0, 0.0, 0.35)

## --- Surface / depth tokens -------------------------------------------------
##
## Every surface in the game is lit from directly above: the rim is brightest
## along the top edge, the body darkens downward, and a soft blue-black shadow
## separates it from the animated backdrop. Keeping the light direction in one
## place is what makes cards, rows, buttons and chips read as one material.
const COLOR_CARD_TOP: Color = Color(0.114, 0.184, 0.298, 0.95)
const COLOR_CARD_BOTTOM: Color = Color(0.047, 0.086, 0.161, 0.95)
## Top-edge rim highlight (icy white) and the quieter hairline for the other
## three sides.
const COLOR_RIM: Color = Color(0.82, 0.93, 1.0, 0.34)
const COLOR_HAIRLINE: Color = Color(0.62, 0.78, 0.96, 0.14)
## Shadows are blue-black rather than neutral black: pure black over a navy
## backdrop reads as a hole, a deep indigo reads as depth.
const COLOR_SHADOW_SOFT: Color = Color(0.004, 0.016, 0.043, 0.52)

## Promoted-primary face: the saturated glacier blue of the menu icon set, one
## step deeper than the hover fill so the promoted action reads as solid rather
## than washed. Shared here so "the action to take next" is identical on every
## screen (main_menu's Play hero, results' Race Again, mode_select's Start…).
const PRIMARY_FILL: Color = Color(0.129, 0.361, 0.588)
const PRIMARY_FILL_HOVER: Color = Color(0.192, 0.478, 0.741)

## Corner language, shared so screens stop inventing radii: cards are soft,
## rows are tighter, buttons sit between them, chips are pills.
const RADIUS_CARD: int = 18
const RADIUS_ROW: int = 10
const RADIUS_BUTTON: int = 12
const RADIUS_PILL: int = 999

## --- Type ramp --------------------------------------------------------------
##
## Authored sizes on the 1920x1080 desktop canvas. Screens should pick a rung
## (make_display / make_headline / make_title / make_body / make_caption)
## instead of an ad-hoc number, so one screen's "small label" is the same size
## as the next screen's. The make_* helpers apply the touch step for you.
const FS_DISPLAY: int = 64
const FS_HEADLINE: int = 44
const FS_TITLE: int = 30
const FS_BODY: int = 22
const FS_CAPTION: int = 15
const FS_EYEBROW: int = 18

## Standard side margin for full-screen menu layouts.
const SCREEN_MARGIN: int = 48

## Spacing rhythm used across every menu: small (within a group), medium
## (between groups), large (between major regions). Prefer these three steps
## over ad-hoc values so screens share one vertical rhythm.
const SPACE_S: int = 16
const SPACE_M: int = 24
const SPACE_L: int = 40

## Minimum comfortable touch target height (logical px) and list spacing on
## touch devices. Applied centrally so every control inherits them, including
## the in-race HUD and the pause menu, which have their own vertical budgets —
## keep this floor conservative and use scaled_size for menu rows instead.
const TOUCH_MIN_HEIGHT: int = 48
const TOUCH_SPACING: int = 12

## Left-edge back-swipe gesture tuning (attach_swipe_back).
const SWIPE_BACK_EDGE_WIDTH: float = 36.0
const SWIPE_BACK_DISTANCE: float = 80.0
const SWIPE_BACK_TIME_MS: int = 600

## --- Touch enlargement ------------------------------------------------------
##
## Menus are authored against the 1920x1080 desktop canvas. SettingsManager
## already shrinks that canvas by TOUCH_UI_BOOST on touch devices, but a phone
## still reads the result as a small desktop screen rather than an app, so
## menus pass their authored metrics through the scaled*/content_width helpers
## below for a second, menu-only enlargement.
##
## The stretch aspect is "expand" and the design height is fixed, so a
## landscape phone always has ~1080/boost logical units of height no matter the
## device while width grows with the aspect ratio. Height is therefore the
## scarce dimension: widths and fonts take the full step, heights take the
## gentler MENU_TOUCH_SCALE_Y step, and display headings are capped outright.
const MENU_TOUCH_SCALE: float = 1.45
const MENU_TOUCH_SCALE_Y: float = 1.16

## Fraction of the viewport width a centered menu column should occupy on
## touch (content_width clamps into this band). Wide enough to read as a
## native app, narrow enough to keep a visible margin on both edges.
const TOUCH_CONTENT_MIN_FRAC: float = 0.70
const TOUCH_CONTENT_MAX_FRAC: float = 0.86

## Ceiling for display headings on touch. Headings are the tallest thing on a
## menu and the least interactive, so on a phone they are scaled up only until
## this cap and the reclaimed height goes to the rows below.
const TOUCH_HEADING_MAX: int = 56

## Floor for a menu row's height on touch, applied by scaled_size only. The
## design canvas keeps its 1080-unit height on every device, so a logical unit
## is roughly half a physical point on a landscape phone: 48 units would be a
## ~23pt target, well under the ~44pt a native app uses, while 88 lands at
## ~43pt. Menu screens opt into this through scaled_size; the race HUD and the
## pause menu stay on the conservative TOUCH_MIN_HEIGHT floor because their
## vertical budgets are already tight.
const MENU_TOUCH_ROW_HEIGHT: int = 88

## Three depth-layered bands (near green with curtain striations, mid violet,
## far faint magenta) — one draw pass, ALU only, so the layered-parallax read
## costs nothing extra on WebGL2. The curtain term drifts at ~0.4 rad/s, far
## below flashing territory even before the reduced_flashing strength cut.
const AURORA_SHADER_CODE: String = """
shader_type canvas_item;
render_mode blend_add;
uniform float strength = 0.16;
void fragment() {
	float t = TIME * 0.045;
	vec2 uv = UV;
	float wave1 = sin(uv.x * 4.4 + t * 6.0) * 0.13 + sin(uv.x * 9.7 - t * 4.0) * 0.05;
	float wave2 = sin(uv.x * 3.1 - t * 5.0 + 1.7) * 0.16 + sin(uv.x * 7.3 + t * 3.0) * 0.04;
	float wave3 = sin(uv.x * 2.3 + t * 3.2 + 4.1) * 0.11 + sin(uv.x * 5.9 - t * 2.2) * 0.03;
	float band1 = exp(-pow((uv.y - 0.30 - wave1) * 6.0, 2.0));
	float band2 = exp(-pow((uv.y - 0.52 - wave2) * 7.5, 2.0));
	float band3 = exp(-pow((uv.y - 0.15 - wave3) * 9.5, 2.0));
	float curtain = 0.82 + 0.18 * sin(uv.x * 46.0 + t * 9.0 + sin(uv.x * 13.0) * 2.0);
	// Hue drifts along x (~0.09 rad/s) so the near sheet is teal at one end and
	// green at the other instead of one flat colour across the whole screen.
	float hue = 0.5 + 0.5 * sin(uv.x * 2.0 - t * 2.0);
	vec3 near = mix(vec3(0.16, 0.95, 0.72), vec3(0.34, 0.86, 0.98), hue);
	vec3 aurora = near * band1 * curtain
			+ vec3(0.45, 0.35, 0.95) * band2
			+ vec3(0.78, 0.42, 0.85) * band3 * 0.55;
	// Broad sky bloom the bands sit inside: the backdrop gets a light source
	// near the top instead of reading as an even navy wash.
	float bloom = exp(-pow((uv.y - 0.08) * 2.1, 2.0)) * (0.40 + 0.22 * sin(uv.x * 1.7 + t * 1.5));
	aurora += vec3(0.26, 0.46, 0.72) * bloom * 0.32;
	float fade = smoothstep(1.0, 0.35, uv.y);
	float side = smoothstep(0.0, 0.12, uv.x) * smoothstep(1.0, 0.88, uv.x);
	COLOR = vec4(aurora * strength * fade * (0.6 + 0.4 * side), 1.0);
}
"""

## Drawn menu icon glyphs (64x64 SVG, same hand-drawn style as the fish icon
## in main_menu/race_hud). Used by make_menu_button for the primary menus.
const ICON_PLAY: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M18 10 L54 32 L18 54 Z" fill="#7fe08f" stroke="#3f8f55" stroke-width="3" stroke-linejoin="round"/>
<path d="M24 18 L24 46" stroke="#b8f0c4" stroke-width="3" stroke-linecap="round" opacity="0.7"/>
</svg>"""

const ICON_SCHOOL: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M32 10 L60 23 L32 36 L4 23 Z" fill="#6fa8d8" stroke="#3d6d94" stroke-width="2" stroke-linejoin="round"/>
<path d="M16 30 V44 Q32 52 48 44 V30" fill="#4d7fae" stroke="#3d6d94" stroke-width="2"/>
<path d="M56 25 V42" stroke="#f5c542" stroke-width="3" stroke-linecap="round"/>
<circle cx="56" cy="45" r="3" fill="#f5c542"/>
</svg>"""

const ICON_PALETTE: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M32 6 C17 6 5 17 5 31 C5 45 16 57 30 58 C36 58 38 52 34 48 C30 44 33 39 39 39 L46 39 C53 39 59 33 59 25 C59 13 47 6 32 6 Z" fill="#e8ddc8" stroke="#a08e6e" stroke-width="2"/>
<circle cx="20" cy="22" r="4" fill="#ff6b57"/>
<circle cx="34" cy="16" r="4" fill="#f5c542"/>
<circle cx="46" cy="22" r="4" fill="#7fe08f"/>
<circle cx="16" cy="36" r="4" fill="#6fa8d8"/>
</svg>"""

const ICON_TROPHY: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M17 12 C7 12 7 28 19 29" stroke="#f5c542" stroke-width="4" fill="none"/>
<path d="M47 12 C57 12 57 28 45 29" stroke="#f5c542" stroke-width="4" fill="none"/>
<path d="M18 8 H46 V22 C46 34 40 40 32 40 C24 40 18 34 18 22 Z" fill="#f5c542" stroke="#c98f1b" stroke-width="2"/>
<rect x="28" y="40" width="8" height="8" fill="#e0b030"/>
<rect x="20" y="48" width="24" height="7" rx="2" fill="#c98f1b"/>
<path d="M24 14 L27 22 L24 30" stroke="#fff2c0" stroke-width="3" fill="none" opacity="0.8"/>
</svg>"""

const ICON_PODIUM: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<rect x="6" y="34" width="17" height="22" fill="#c9d2dc" stroke="#8d99a6" stroke-width="2"/>
<rect x="23" y="24" width="18" height="32" fill="#f5c542" stroke="#c98f1b" stroke-width="2"/>
<rect x="41" y="40" width="17" height="16" fill="#cd8f5a" stroke="#96683f" stroke-width="2"/>
<path d="M32 8 L34.4 13.4 L40 14 L35.8 17.8 L37 23.4 L32 20.5 L27 23.4 L28.2 17.8 L24 14 L29.6 13.4 Z" fill="#f5c542" stroke="#c98f1b" stroke-width="1.5"/>
</svg>"""

const ICON_GEAR: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<g stroke="#9fc4e0" stroke-width="7" stroke-linecap="round" fill="none">
<path d="M32 8 V16 M32 48 V56 M8 32 H16 M48 32 H56 M15 15 L21 21 M43 43 L49 49 M49 15 L43 21 M21 43 L15 49"/>
<circle cx="32" cy="32" r="14"/>
</g>
<circle cx="32" cy="32" r="5" fill="#22303f"/>
</svg>"""

const ICON_FILM: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<rect x="8" y="14" width="48" height="40" rx="4" fill="#5a7ba6" stroke="#3d5578" stroke-width="2"/>
<path d="M8 26 H56" stroke="#3d5578" stroke-width="2.5"/>
<path d="M12 14 L20 26 M24 14 L32 26 M36 14 L44 26 M48 14 L56 26" stroke="#d7e6f5" stroke-width="3"/>
<path d="M16 38 L28 34 M16 46 L34 44" stroke="#9fc4e0" stroke-width="3" stroke-linecap="round" opacity="0.8"/>
</svg>"""

const ICON_DOOR: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M10 8 H38 V56 H10 Z" fill="#7a5c40" stroke="#54402c" stroke-width="2" stroke-linejoin="round"/>
<circle cx="31" cy="33" r="2.6" fill="#f5c542"/>
<path d="M42 32 H58 M51 24 L59 32 L51 40" stroke="#9fc4e0" stroke-width="4" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
</svg>"""

## Back chevron shared by every screen's Back affordance so "leave this page"
## always looks the same.
const ICON_BACK: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M38 12 L18 32 L38 52" stroke="#9fc4e0" stroke-width="7" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
</svg>"""

## Directional arrows, drawn rather than typed.
##
## ThemeDB.fallback_font is Godot's bundled subset and carries NO arrows,
## triangles, stars or emoji -- has_char() is false for U+2190..U+2194,
## U+25B2/BC/C4/BA, U+2605 and every emoji codepoint. A desktop editor run can
## paper over that with an OS font fallback; a web export cannot, so on the
## deployed build each of those characters rendered as a .notdef box with its
## hex digits inside (the "weird numbers" on the Finish Race button). Anything
## symbolic in player-facing text is built from these instead.
const ARROW_SVG: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M14 32 H48 M36 20 L48 32 L36 44" stroke="%s" stroke-width="7" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
</svg>"""

## Double-headed arrow for "drag sideways" style gesture hints.
const ARROW_BOTH_SVG: String = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
<path d="M10 32 H54 M22 20 L10 32 L22 44 M42 20 L54 32 L42 44" stroke="%s" stroke-width="7" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
</svg>"""

## Rotation (degrees) applied to ARROW_SVG per direction name.
const ARROW_ROTATION: Dictionary = {
	"right": 0.0, "down": 90.0, "left": 180.0, "up": 270.0,
}

static var _arrow_cache: Dictionary = {}
static var _display_font: FontVariation = null
static var _button_font: FontVariation = null
static var _caption_font: FontVariation = null
## Aurora backdrop shader/materials are cached and shared across every menu
## screen: one compile, one material per strength (WebGL2 jank guard — menus
## rebuild on every navigation).
static var _aurora_shader: Shader = null
static var _aurora_materials: Dictionary = {}
## Baked-once, shared-forever textures. Menus rebuild their whole tree on every
## navigation, so anything procedural here is generated a single time per run
## and then handed to every screen by reference — the mobile-web frame budget
## cannot afford re-baking gradients or noise on each screen change.
static var _card_texture: ImageTexture = null
static var _gloss_texture: GradientTexture2D = null
static var _bg_gradient: ImageTexture = null
static var _vignette_texture: GradientTexture2D = null
static var _star_texture: ImageTexture = null
static var _grain_texture: ImageTexture = null
## Slider knobs, keyed by tint (normal / hover / disabled).
static var _knob_textures: Dictionary = {}


## True when a touchscreen is present (phones, tablets, touch laptops).
## Headless runs always report false so sims stay deterministic.
static func is_touch() -> bool:
	if GameConfig.is_headless():
		return false
	return DisplayServer.is_touchscreen_available()


## Central reduced-motion gate for menu flourishes. The project exposes one
## accessibility switch for this family (reduced_flashing); every large or
## eye-catching ambient animation checks it through this helper so the
## setting reliably calms the whole menu system.
static func reduced_motion() -> bool:
	return bool(SettingsManager.get_setting("accessibility", "reduced_flashing"))


## SubViewportContainer.stretch sizes its SubViewport in *logical* (design
## 1920x1080) pixels; on hi-dpi and large windows the canvas transform then
## upscales the texture, so menu 3D dioramas rendered blocky. Supersample the
## 3D pass by the actual canvas scale (bilinear downscale back to the texture)
## so the diorama is effectively native-resolution. Tracks window resizes.
static func crisp_subviewport(viewport: SubViewport, host: Node) -> void:
	if GameConfig.is_headless():
		return
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	var apply := func() -> void:
		if not is_instance_valid(viewport) or not is_instance_valid(host):
			return
		var win := host.get_window()
		if win == null:
			return
		var logical := host.get_viewport().get_visible_rect().size
		if logical.y <= 0.0:
			return
		var scale := maxf(
			float(win.size.x) / logical.x, float(win.size.y) / logical.y)
		# Trimmed by the platform's 3D render scale for the same reason the main
		# viewport is: on web, rendering menu dioramas at every device pixel is
		# what pushes a frame past its budget. UI drawn over them is unaffected.
		# The floor is the platform's own render scale, never lower. Clamping to
		# a flat 0.6 meant any window narrower than the 1920 design size -- a
		# 1600px desktop window included -- rendered menu 3D BELOW native and
		# came out soft. On desktop the floor is 1.0, so a small window still
		# supersamples to at least native; on web it is whatever the platform
		# scale allows, which is the whole point of that setting.
		var platform_scale := SettingsManager.render_scale_3d()
		viewport.scaling_3d_scale = clampf(
			scale * platform_scale, minf(platform_scale, 1.0), 2.0)
	apply.call()
	host.get_window().size_changed.connect(apply)
	host.tree_exiting.connect(func() -> void:
		var win := host.get_window()
		if win != null and win.size_changed.is_connected(apply):
			win.size_changed.disconnect(apply))


## Menu enlargement factor: 1.0 on desktop, MENU_TOUCH_SCALE on touch. Use the
## scaled* helpers below in preference to multiplying by this directly.
static func menu_scale() -> float:
	return MENU_TOUCH_SCALE if is_touch() else 1.0


## Authored horizontal metric (width, inset, icon size) -> on-screen metric.
static func scaled(value: float) -> float:
	return value * menu_scale()


## Integer flavour of scaled(), for container theme constants.
static func scaled_int(value: int) -> int:
	return roundi(float(value) * menu_scale())


## Authored font size -> on-screen font size. Body and control text takes the
## full touch step; use scaled_heading for display headings instead.
static func scaled_font(size: int) -> int:
	return roundi(float(size) * menu_scale())


## Authored control size -> on-screen control size. Width takes the full touch
## step, height the gentler vertical step, and any positive height is floored
## at MENU_TOUCH_ROW_HEIGHT so every menu row is a comfortable target. A zero
## axis means "let the container decide" and is passed through untouched.
static func scaled_size(size: Vector2) -> Vector2:
	if not is_touch():
		return size
	var out := size
	if out.x > 0.0:
		out.x *= MENU_TOUCH_SCALE
	if out.y > 0.0:
		out.y = maxf(out.y * MENU_TOUCH_SCALE_Y, float(MENU_TOUCH_ROW_HEIGHT))
	return out


## Display-heading size: scaled up like body text but capped at
## TOUCH_HEADING_MAX, because on a landscape phone vertical space runs out
## long before horizontal space does.
static func scaled_heading(size: int) -> int:
	return mini(scaled_font(size), TOUCH_HEADING_MAX) if is_touch() else size


## Width for a centered menu column (button stack, card list, result panel).
## Desktop keeps the authored width exactly; touch enlarges it and then clamps
## it into the TOUCH_CONTENT_* band of the live viewport, so the column fills
## most of a landscape phone without ever running past the screen edge.
## `host` only supplies the viewport — pass the screen root. Falls back to the
## plainly scaled width when no viewport is available.
static func content_width(base: float, host: Control) -> float:
	if not is_touch():
		return base
	var width := scaled(base)
	if host == null or not host.is_inside_tree():
		return width
	var view_width := host.get_viewport_rect().size.x
	if view_width <= 0.0:
		return width
	return clampf(width, view_width * TOUCH_CONTENT_MIN_FRAC, view_width * TOUCH_CONTENT_MAX_FRAC)


## Height for a fixed-size menu block (a list panel, a preview frame). Desktop
## keeps the authored height; touch scales it vertically but never lets it grow
## past `max_fraction` of the viewport, so the surrounding header and buttons
## always keep their room on a short landscape viewport.
static func content_height(base: float, host: Control, max_fraction: float) -> float:
	if not is_touch():
		return base
	var height := maxf(base * MENU_TOUCH_SCALE_Y, float(TOUCH_MIN_HEIGHT))
	if host == null or not host.is_inside_tree():
		return height
	var view_height := host.get_viewport_rect().size.y
	if view_height <= 0.0:
		return height
	return minf(height, view_height * max_fraction)


## List/row separation helper: authored value on desktop, at least
## TOUCH_SPACING on touch devices so rows never crowd fingertips. Gaps follow
## the vertical step — widening them at the full step would eat the height the
## enlarged rows need.
static func spacing(base: int) -> int:
	if not is_touch():
		return base
	return maxi(roundi(float(base) * MENU_TOUCH_SCALE_Y), TOUCH_SPACING)


## Side margin for full-screen menu layouts: SCREEN_MARGIN on desktop, the
## enlarged large rhythm step on touch so full-bleed list screens keep a
## visible but thin gutter.
static func screen_margin() -> int:
	return scaled_int(SPACE_L) if is_touch() else SCREEN_MARGIN


## Emboldened, letter-spaced variation of the default font for large headers.
static func display_font() -> FontVariation:
	if _display_font == null:
		_display_font = FontVariation.new()
		_display_font.base_font = ThemeDB.fallback_font
		_display_font.variation_embolden = 0.65
		_display_font.spacing_glyph = 2
	return _display_font


## Slightly emboldened variation for buttons and emphasis labels.
static func bold_font() -> FontVariation:
	if _button_font == null:
		_button_font = FontVariation.new()
		_button_font.base_font = ThemeDB.fallback_font
		_button_font.variation_embolden = 0.35
	return _button_font


## Wide-tracked variation for the small uppercase rungs of the ramp (eyebrows,
## card titles, stat captions, table headings). Small uppercase text needs more
## letter-spacing than body text to stay legible, and the extra tracking is what
## makes a caption read as a caption rather than as shrunken body copy.
static func caption_font() -> FontVariation:
	if _caption_font == null:
		_caption_font = FontVariation.new()
		_caption_font.base_font = ThemeDB.fallback_font
		_caption_font.variation_embolden = 0.45
		_caption_font.spacing_glyph = 3
	return _caption_font


## --- Button state ramp ------------------------------------------------------
##
## Five states, one material, one light direction. Read as a ramp:
##   normal    quiet frosted glass, top rim only, small grounded shadow
##   hover     fill brightens a step, rim goes full accent, shadow lifts
##   pressed   fill drops below the backdrop, shadow collapses, face sinks 2px
##   focus     an accent ring drawn *outside* the face (never moves layout)
##   disabled  fill and rim collapse toward the background, shadow removed
## Kept as module constants so OptionButtons, popups and the promoted-primary
## variant below all sample the same ramp instead of re-picking colors.
const BTN_FILL: Color = Color(0.141, 0.227, 0.369, 0.68)
const BTN_FILL_HOVER: Color = Color(0.200, 0.325, 0.502, 0.84)
const BTN_FILL_PRESSED: Color = Color(0.043, 0.086, 0.157, 0.90)
const BTN_FILL_DISABLED: Color = Color(0.078, 0.110, 0.161, 0.50)


static func make_button(text: String, size: Vector2 = Vector2(320, 52), font_size: int = 24) -> Button:
	var button := Button.new()
	button.text = text
	if is_touch():
		size.y = maxf(size.y, float(TOUCH_MIN_HEIGHT))
	button.custom_minimum_size = size
	button.add_theme_font_override("font", bold_font())
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", COLOR_GOLD)
	button.add_theme_color_override("font_disabled_color", COLOR_DISABLED)
	button.add_theme_color_override("font_outline_color", Color(0.02, 0.04, 0.08, 0.55))
	button.add_theme_constant_override("outline_size", 0)

	# Frosted-glass state family: the translucent fill lets the animated backdrop
	# glow through; the top-weighted rim plus the gloss/shade overlay strips
	# (added below) give each button a lit-from-above read. Hover lifts (brighter
	# rim, larger shadow, 1.02 scale); pressed compresses (0.98 scale, tight
	# shadow, face sinks 2px).
	var normal := _button_box(BTN_FILL, COLOR_RIM, 1)
	var hover := _button_box(BTN_FILL_HOVER, Color(COLOR_ACCENT, 0.95), 2)
	hover.shadow_color = Color(0.086, 0.267, 0.435, 0.55)
	hover.shadow_size = 12
	hover.shadow_offset = Vector2(0.0, 6.0)
	var pressed := _button_box(BTN_FILL_PRESSED, Color(COLOR_GOLD, 0.9), 2)
	pressed.shadow_size = 2
	pressed.shadow_offset = Vector2(0.0, 1.0)
	pressed.content_margin_top = 12.0
	pressed.content_margin_bottom = 8.0
	var focus := _focus_ring(RADIUS_BUTTON + 2)
	var disabled := _button_box(BTN_FILL_DISABLED, Color(0.30, 0.37, 0.47, 0.28), 1)
	disabled.border_width_top = 1
	disabled.shadow_size = 0

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_stylebox_override("disabled", disabled)
	_attach_glass_edges(button)
	attach_hover_scale(button, 1.02)
	attach_hover_glow(button)
	return button


## The one focus affordance in the game: a bright accent ring drawn outside the
## control's face with a soft halo behind it. Expand margins mean focus never
## changes a control's size, so keyboard/gamepad navigation cannot reflow a
## menu. Shared by buttons, pickers and anything else that takes focus.
static func _focus_ring(radius: int) -> StyleBoxFlat:
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = Color(0.75, 0.93, 1.0, 0.98)
	ring.set_border_width_all(2)
	ring.set_corner_radius_all(radius)
	ring.set_expand_margin_all(3.0)
	ring.shadow_color = Color(COLOR_ACCENT, 0.30)
	ring.shadow_size = 8
	ring.anti_aliasing = true
	return ring


## Promoted-primary treatment: the single action a screen most wants pressed.
## Formalised here so main_menu's Play hero, results' Race Again and every
## screen an agent writes next promote their action identically — only the fill
## weight changes relative to make_button, so the family stays coherent.
## A translucent accent wash reads as *disabled*, and darkening COLOR_ACCENT
## (a pale cyan) only greys it, so the promoted face is a saturated glacier
## blue rimmed with COLOR_ACCENT instead.
static func style_primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal",
		_primary_box(PRIMARY_FILL, Color(COLOR_ACCENT, 0.85), 8))
	button.add_theme_stylebox_override("hover",
		_primary_box(PRIMARY_FILL_HOVER, Color(0.90, 0.98, 1.0, 0.95), 16))
	button.add_theme_stylebox_override("pressed",
		_primary_box(PRIMARY_FILL.darkened(0.35), Color(COLOR_GOLD, 0.9), 2))
	var disabled := _primary_box(PRIMARY_FILL.darkened(0.55).lerp(COLOR_BG_DARK, 0.5),
		Color(0.30, 0.37, 0.47, 0.30), 0)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_color", Color(0.98, 0.995, 1.0))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)


static func _primary_box(bg: Color, border: Color, shadow: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(2)
	box.border_width_top = 3
	box.border_blend = true
	box.set_corner_radius_all(RADIUS_BUTTON)
	box.content_margin_left = 22.0
	box.content_margin_right = 22.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 10.0
	box.shadow_color = Color(COLOR_ACCENT, 0.30)
	box.shadow_size = shadow
	box.shadow_offset = Vector2(0.0, 3.0)
	box.anti_aliasing = true
	return box


## Promoted button in one call: make_button + style_primary.
static func make_primary_button(text: String, size: Vector2 = Vector2(320, 60),
		font_size: int = 26) -> Button:
	var button := make_button(text, size, font_size)
	style_primary(button)
	return button


## The quiet end of the ramp: a borderless text button for tertiary actions
## ("Skip", "Reset", "Learn more") that must not compete with the row of real
## buttons beside it. Still hovers, focuses and presses like the rest.
static func style_ghost(button: Button) -> void:
	var flat := StyleBoxFlat.new()
	flat.bg_color = Color(1.0, 1.0, 1.0, 0.0)
	flat.set_corner_radius_all(RADIUS_BUTTON)
	flat.content_margin_left = 16.0
	flat.content_margin_right = 16.0
	flat.content_margin_top = 8.0
	flat.content_margin_bottom = 8.0
	var hover := flat.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.78, 0.90, 1.0, 0.10)
	var pressed := flat.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.02, 0.05, 0.10, 0.45)
	button.add_theme_stylebox_override("normal", flat)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", flat)
	button.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	# A ghost has no face, so it must not carry the glass gloss/shade strips —
	# they would draw a phantom rectangle where the button is not.
	for child in button.get_children():
		if child is Control and (child.name == "GlassSheen" or child.name == "GlassShade"):
			(child as Control).visible = false


static func make_ghost_button(text: String, size: Vector2 = Vector2(180, 48),
		font_size: int = 20) -> Button:
	var button := make_button(text, size, font_size)
	style_ghost(button)
	return button


## Standard stacked-menu button with a leading drawn-icon glyph (see the
## ICON_* consts). Falls back to the plain themed button when the SVG module
## is unavailable, so headless runs and sims are unaffected.
## Stacked-menu buttons only ever appear on menu screens (never in the race
## HUD, which has its own hud_scale), so the touch enlargement is applied here
## rather than at every call site. Callers that need a viewport-relative width
## override custom_minimum_size.x with content_width afterwards.
static func make_menu_button(text: String, icon_svg: String, size: Vector2 = Vector2(520, 72), font_size: int = 32) -> Button:
	var button := make_button(text, scaled_size(size), scaled_font(font_size))
	if icon_svg != "":
		var texture := make_icon(icon_svg, 1.0)
		if texture != null:
			button.icon = texture
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width", scaled_int(34))
			button.add_theme_constant_override("h_separation", scaled_int(14))
	return button


## Top gloss + bottom shade overlay: the two-tone, falling-off edge treatment
## StyleBoxFlat cannot express (one border color, no gradient). The gloss is a
## shared baked gradient — bright at the very top edge, gone by ~40% down — so
## the face reads as a curved glass surface lit from above rather than a flat
## fill with a line on it. Both strips are inert and inset past the corner
## radius, and the gradient texture is baked once for the whole game.
static func _attach_glass_edges(button: Button) -> void:
	var sheen := TextureRect.new()
	sheen.name = "GlassSheen"
	sheen.texture = _gloss()
	sheen.stretch_mode = TextureRect.STRETCH_SCALE
	sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheen.focus_mode = Control.FOCUS_NONE
	sheen.anchor_left = 0.0
	sheen.anchor_right = 1.0
	sheen.anchor_top = 0.0
	sheen.anchor_bottom = 0.42
	sheen.offset_left = 13.0
	sheen.offset_right = -13.0
	sheen.offset_top = 1.0
	sheen.offset_bottom = 0.0
	button.add_child(sheen)
	var shade := ColorRect.new()
	shade.name = "GlassShade"
	shade.color = Color(0.0, 0.008, 0.031, 0.11)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.focus_mode = Control.FOCUS_NONE
	shade.anchor_left = 0.0
	shade.anchor_right = 1.0
	shade.anchor_top = 1.0
	shade.anchor_bottom = 1.0
	shade.offset_left = 13.0
	shade.offset_right = -13.0
	shade.offset_top = -2.5
	shade.offset_bottom = -1.0
	button.add_child(shade)


## Shared white-to-transparent vertical gradient (the button gloss). One
## GradientTexture2D for every button in the game.
static func _gloss() -> GradientTexture2D:
	if _gloss_texture == null:
		# Cool-tinted, not pure white: white over navy desaturates into grey and
		# the face stops reading as ice. Falls off fast so it is a specular edge,
		# not a two-tone paint job.
		var sheen := Color(0.82, 0.92, 1.0)
		var grad := Gradient.new()
		grad.colors = PackedColorArray([
			Color(sheen.r, sheen.g, sheen.b, 0.13),
			Color(sheen.r, sheen.g, sheen.b, 0.035),
			Color(sheen.r, sheen.g, sheen.b, 0.0),
		])
		grad.offsets = PackedFloat32Array([0.0, 0.30, 1.0])
		_gloss_texture = GradientTexture2D.new()
		_gloss_texture.gradient = grad
		_gloss_texture.width = 2
		_gloss_texture.height = 48
		_gloss_texture.fill_from = Vector2(0.0, 0.0)
		_gloss_texture.fill_to = Vector2(0.0, 1.0)
	return _gloss_texture


## Button face for one state. The rim is one step thicker along the top edge
## and blends inward, so every control in the game is lit from the same
## direction as the cards behind it.
static func _button_box(bg: Color, border: Color, border_width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(border_width)
	# Crisp, not blended: a button's top edge is a specular highlight and needs
	# a hard line. The gloss overlay supplies the falloff beneath it. (Cards use
	# the opposite treatment — see make_panel_style.)
	box.border_width_top = border_width + 1
	box.set_corner_radius_all(RADIUS_BUTTON)
	box.content_margin_left = 18.0
	box.content_margin_right = 18.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 10.0
	box.shadow_color = COLOR_SHADOW_SOFT
	box.shadow_size = 7
	box.shadow_offset = Vector2(0.0, 4.0)
	box.anti_aliasing = true
	return box


## Soft icy glow ring that fades in behind a button on hover/focus and back
## out on exit — the "lift" half of the hover micro-animation (scale is the
## other half). Event-driven tweens only; zero per-frame cost at rest.
## Headless runs skip the extra node so sims stay lean.
static func attach_hover_glow(button: BaseButton, color: Color = COLOR_ACCENT) -> void:
	if GameConfig.is_headless():
		return
	var glow := Panel.new()
	glow.name = "HoverGlow"
	glow.show_behind_parent = true
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.offset_left = -3.0
	glow.offset_top = -3.0
	glow.offset_right = 3.0
	glow.offset_bottom = 3.0
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.focus_mode = Control.FOCUS_NONE
	glow.modulate.a = 0.0
	var box := StyleBoxFlat.new()
	box.draw_center = false
	box.border_color = Color(color, 0.55)
	box.set_border_width_all(2)
	box.set_corner_radius_all(14)
	box.shadow_color = Color(color, 0.38)
	box.shadow_size = 12
	glow.add_theme_stylebox_override("panel", box)
	button.add_child(glow)
	var fade := func(target: float, time: float) -> void:
		if not glow.is_inside_tree():
			return
		if glow.has_meta("_glow_tween"):
			var old: Variant = glow.get_meta("_glow_tween")
			if old is Tween and (old as Tween).is_valid():
				(old as Tween).kill()
		var tween := glow.create_tween()
		tween.tween_property(glow, "modulate:a", target, time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		glow.set_meta("_glow_tween", tween)
	var lift := func() -> void: fade.call(0.9, 0.14)
	var rest := func() -> void:
		if button.is_hovered() or button.has_focus():
			return
		fade.call(0.0, 0.28)
	button.mouse_entered.connect(lift)
	button.focus_entered.connect(lift)
	button.mouse_exited.connect(rest)
	button.focus_exited.connect(rest)


## Subtle grow-on-hover/focus with a press-down dip. Pivot tracks center.
static func attach_hover_scale(control: Control, amount: float = 1.02) -> void:
	control.pivot_offset = control.size * 0.5
	control.resized.connect(func() -> void:
		control.pivot_offset = control.size * 0.5)
	var grow := func() -> void: _scale_to(control, amount)
	var rest := func() -> void: _scale_to(control, 1.0)
	control.mouse_entered.connect(grow)
	control.mouse_exited.connect(rest)
	control.focus_entered.connect(grow)
	control.focus_exited.connect(rest)
	if control is BaseButton:
		var button := control as BaseButton
		button.button_down.connect(func() -> void:
			_scale_to(control, amount - 0.04))
		button.button_up.connect(func() -> void:
			var engaged := button.is_hovered() or button.has_focus()
			_scale_to(control, amount if engaged else 1.0))


static func _scale_to(control: Control, target: float) -> void:
	if not control.is_inside_tree():
		return
	if control.has_meta("_hover_tween"):
		var old: Variant = control.get_meta("_hover_tween")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	var tween := control.create_tween()
	tween.tween_property(control, "scale", Vector2(target, target), 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	control.set_meta("_hover_tween", tween)


## --- Surfaces ---------------------------------------------------------------

## Panel face used by every card, chip, tile and popup that is not built with
## make_card(). StyleBoxFlat cannot express a gradient body, so depth comes
## from the three cues it *can* express: a rim that is one step thicker along
## the top edge and blends inward (a lit upper edge with falloff), the shared
## card radius, and a large, soft, blue-black drop shadow offset downward.
## Signature is load-bearing — ~20 call sites pass their own bg/border and then
## adjust radius, margins and shadow on the returned box.
static func make_panel_style(bg: Color = COLOR_PANEL, border: Color = Color(COLOR_ACCENT, 0.20)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.border_width_top = 2
	box.border_blend = true
	box.set_corner_radius_all(RADIUS_CARD)
	box.content_margin_left = float(SPACE_M)
	box.content_margin_right = float(SPACE_M)
	box.content_margin_top = float(SPACE_S)
	box.content_margin_bottom = float(SPACE_S)
	box.shadow_color = COLOR_SHADOW_SOFT
	box.shadow_size = 14
	box.shadow_offset = Vector2(0.0, 7.0)
	box.anti_aliasing = true
	return box


## The premium card face: a genuinely graded body (lighter at the top, darker
## at the bottom), a bright 1px rim along the top edge, and a soft drop shadow
## — all baked into one shared nine-patch texture. StyleBoxFlat has no gradient
## and no per-side border color, so this is the only way to get the real thing;
## baking it once and handing the same ImageTexture to every card keeps the
## cost at zero for mobile web no matter how many cards a screen builds.
## Each call returns a fresh (cheap) StyleBoxTexture wrapper so a screen can
## adjust content margins without mutating everyone else's cards.
static func make_card_style() -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = _card_tex()
	box.set_texture_margin_all(float(CARD_TEX_MARGIN))
	# The baked shadow lives in the outer CARD_PAD ring; expanding by exactly
	# that much makes the card's *body* land on the control rect, so the shadow
	# costs no layout space.
	box.set_expand_margin_all(float(CARD_PAD))
	box.content_margin_left = float(scaled_int(SPACE_M))
	box.content_margin_right = float(scaled_int(SPACE_M))
	box.content_margin_top = float(scaled_int(SPACE_S))
	box.content_margin_bottom = float(scaled_int(SPACE_S))
	return box


## A card in one call: PanelContainer wearing make_card_style(), optionally
## parented. Use this for every "block of related content" — a settings
## section, a standings table, a reward group — so every screen's blocks share
## one radius, one rim, one shadow and one padding rhythm.
static func make_card(parent: Control = null) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", make_card_style())
	if parent != null:
		parent.add_child(card)
	return card


## Row face inside a card: tighter radius, no shadow, an almost-invisible zebra
## so long lists stay scannable. `highlight` promotes the row the player cares
## about (their standings line, the selected option) to a filled accent card
## with a thick left edge.
static func make_row_style(index: int = 0, highlight: bool = false,
		accent: Color = COLOR_GOLD) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(RADIUS_ROW)
	box.content_margin_left = float(scaled_int(12))
	box.content_margin_right = float(scaled_int(14))
	box.content_margin_top = float(scaled_int(6))
	box.content_margin_bottom = float(scaled_int(6))
	box.anti_aliasing = true
	if highlight:
		# Deliberately light on fill: a saturated accent wash over a navy card
		# turns olive. The row is identified by its bright rim, its thick left
		# edge and its glow — the fill only has to lift it off the zebra.
		box.bg_color = Color(accent.r, accent.g, accent.b, 0.11)
		box.border_color = Color(accent, 0.70)
		box.set_border_width_all(1)
		box.border_width_left = 5
		box.shadow_color = Color(accent, 0.18)
		box.shadow_size = 9
	else:
		box.bg_color = Color(1.0, 1.0, 1.0, 0.035 if index % 2 == 0 else 0.0)
	return box


## --- Baked card texture -----------------------------------------------------
##
## Nine-patch geometry. The outer CARD_PAD ring holds the baked shadow, the
## next CARD_RADIUS holds the rounded corner, and the 2px middle is what
## stretches — so a card of any size keeps a pixel-exact corner, a graded top
## band, a graded bottom band, and a flat middle.
const CARD_PAD: int = 22
const CARD_TEX_MARGIN: int = CARD_PAD + RADIUS_CARD + 2
const CARD_TEX_SIZE: int = CARD_TEX_MARGIN * 2 + 2


static func _card_tex() -> ImageTexture:
	if _card_texture != null:
		return _card_texture
	var size := CARD_TEX_SIZE
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var half := Vector2(float(size) * 0.5 - float(CARD_PAD), float(size) * 0.5 - float(CARD_PAD))
	var center := Vector2(float(size) * 0.5, float(size) * 0.5) - Vector2(0.5, 0.5)
	var radius := float(RADIUS_CARD)
	var mid := COLOR_CARD_TOP.lerp(COLOR_CARD_BOTTOM, 0.55)
	# Falloff over which the top band brightens and the bottom band darkens.
	var band := float(CARD_TEX_MARGIN - CARD_PAD)
	for y: int in size:
		# Vertical body gradient, defined from the nearest edge so the stretched
		# middle rows are exactly `mid` and the bands survive nine-patching.
		var from_top := (float(y) - float(CARD_PAD)) / band
		var from_bottom := (float(size - 1 - y) - float(CARD_PAD)) / band
		var body := mid
		if from_top < 1.0:
			body = COLOR_CARD_TOP.lerp(mid, clampf(from_top, 0.0, 1.0))
		elif from_bottom < 1.0:
			body = COLOR_CARD_BOTTOM.lerp(mid, clampf(from_bottom, 0.0, 1.0))
		for x: int in size:
			var p := Vector2(float(x), float(y)) - center
			var sd := _round_rect_sdf(p, half, radius)
			# Shadow: same shape, pushed down and softened outward.
			var sds := _round_rect_sdf(p - Vector2(0.0, 5.0), half, radius)
			var k := clampf(1.0 - sds / float(CARD_PAD), 0.0, 1.0)
			var out := Color(COLOR_SHADOW_SOFT.r, COLOR_SHADOW_SOFT.g, COLOR_SHADOW_SOFT.b,
				COLOR_SHADOW_SOFT.a * k * k * k)
			var cover := clampf(0.5 - sd, 0.0, 1.0)
			if cover > 0.0:
				var face := body
				# Rim: brightest exactly on the top edge, gone 2px in. Only the
				# upper arc gets it, so the light stays overhead.
				var depth := -sd
				if depth < 2.2 and p.y < 0.0:
					var rim_t := clampf(1.0 - depth / 2.2, 0.0, 1.0) \
						* clampf(-p.y / (half.y * 0.85), 0.0, 1.0)
					face = face.lerp(Color(COLOR_RIM.r, COLOR_RIM.g, COLOR_RIM.b, 1.0),
						COLOR_RIM.a * rim_t)
				out = _over(Color(face.r, face.g, face.b, face.a * cover), out)
			img.set_pixel(x, y, out)
	_card_texture = ImageTexture.create_from_image(img)
	return _card_texture


## Signed distance to a rounded rectangle centered on the origin.
static func _round_rect_sdf(p: Vector2, half: Vector2, radius: float) -> float:
	var q := Vector2(absf(p.x), absf(p.y)) - half + Vector2(radius, radius)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius


## Straight source-over composite in unpremultiplied color.
static func _over(src: Color, dst: Color) -> Color:
	var a := src.a + dst.a * (1.0 - src.a)
	if a <= 0.0001:
		return Color(0.0, 0.0, 0.0, 0.0)
	var inv := 1.0 / a
	return Color(
		(src.r * src.a + dst.r * dst.a * (1.0 - src.a)) * inv,
		(src.g * src.a + dst.g * dst.a * (1.0 - src.a)) * inv,
		(src.b * src.a + dst.b * dst.a * (1.0 - src.a)) * inv,
		a)


## --- Type ramp helpers ------------------------------------------------------
##
## Five rungs, all applying the touch step for you. Reach for the rung, not a
## number: display (one per screen, the thing you came to see), headline
## (screen title), title (card/section heading), body (everything readable),
## caption (uppercase, tracked, dim — the label *under* a value).

## Biggest rung: a screen's one hero line. Uses scaled_heading so a landscape
## phone does not spend its scarce height on the title.
static func make_display(text: String, size: int = FS_DISPLAY) -> Label:
	return heading(text, scaled_heading(size))


## Screen title.
static func make_headline(text: String, size: int = FS_HEADLINE) -> Label:
	return heading(text, scaled_heading(size))


## Card/section heading, or any emphasised line inside a card.
static func make_title(text: String, size: int = FS_TITLE, color: Color = COLOR_TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", display_font())
	label.add_theme_font_size_override("font_size", scaled_font(size))
	label.add_theme_color_override("font_color", color)
	return label


## Readable body copy. Deliberately does NOT autowrap: most body labels are
## cells in a row, and an autowrapping label squeezed by an expanding sibling
## wraps one character per line. Use make_paragraph for real prose.
static func make_body(text: String, size: int = FS_BODY, color: Color = COLOR_TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", scaled_font(size))
	label.add_theme_color_override("font_color", color)
	return label


## Body copy that is meant to flow over several lines (descriptions, empty
## states, credits). Give it a width — either a custom_minimum_size.x or an
## expanding container — or it will wrap to nothing.
static func make_paragraph(text: String, size: int = FS_BODY,
		color: Color = COLOR_TEXT_DIM) -> Label:
	var label := make_body(text, size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## Small uppercase tracked caption — the quiet line under a value, or a column
## heading. Always COLOR_TEXT_DIM unless a screen has a reason otherwise.
static func make_caption(text: String, size: int = FS_CAPTION,
		color: Color = COLOR_TEXT_DIM) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_override("font", caption_font())
	label.add_theme_font_size_override("font_size", scaled_font(size))
	label.add_theme_color_override("font_color", color)
	return label


## Context line *above* a headline ("QUICK RACE · GLACIER GAUNTLET"). Same
## treatment as a caption but accent-tinted, because it belongs to the headline
## rather than to the value below it.
static func make_eyebrow(text: String, size: int = FS_EYEBROW,
		color: Color = Color(COLOR_ACCENT, 0.75)) -> Label:
	var label := make_caption(text, size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## A number the player is meant to read at a glance: display font, larger,
## tinted. Pair with make_caption underneath.
static func make_value(text: String, size: int = FS_TITLE,
		color: Color = COLOR_TEXT) -> Label:
	var label := make_title(text, size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


## Value-over-caption pair, the atom the whole game's stat strips are built
## from. Returns the tile so callers can size or restyle it.
static func make_stat(value: String, caption: String, color: Color = COLOR_TEXT) -> VBoxContainer:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	stack.add_child(make_value(value, FS_TITLE, color))
	var cap := make_caption(caption)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(cap)
	return stack


## Card caption: a short accent tick followed by an uppercase tracked label, so
## every card in the game announces itself the same way. Adds the row to
## `parent` and returns it.
static func card_title(parent: Control, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", scaled_int(10))
	parent.add_child(row)
	var tick := ColorRect.new()
	tick.color = Color(COLOR_ACCENT, 0.85)
	tick.custom_minimum_size = Vector2(scaled(4.0), scaled(17.0))
	tick.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tick)
	row.add_child(make_caption(text, FS_EYEBROW - 1, Color(0.72, 0.83, 0.94)))
	return row


## Hairline separator between groups inside a card or column.
static func make_divider(thickness: float = 1.0) -> ColorRect:
	var rule := ColorRect.new()
	rule.color = Color(COLOR_ACCENT, 0.16)
	rule.custom_minimum_size = Vector2(0.0, thickness)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


## Fixed vertical gap on the SPACE_S/M/L rhythm. Takes the touch step, so a
## phone's spacing grows with its controls.
static func make_spacer(height: int = SPACE_M) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0.0, float(spacing(height)))
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


static func heading(text: String, size: int = 44) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", display_font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	label.add_theme_color_override("font_outline_color", COLOR_BG_DEEP)
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.4))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 4)
	label.add_theme_constant_override("shadow_outline_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


static func sub_label(text: String, size: int = 20) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	return label


## Thin horizontal accent rule used under headers and between sections.
## Grows from its center on screen entry (headless-safe no-op).
static func accent_rule(width: float = 220.0, color: Color = COLOR_ACCENT) -> Control:
	var holder := CenterContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rule := ColorRect.new()
	rule.color = Color(color, 0.75)
	rule.custom_minimum_size = Vector2(width, 3.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(rule)
	animate_rule(rule)
	return holder


## Full-width thin divider used directly under screen headers (Settings,
## Achievements, Controls…) so every menu shares the same header rhythm.
## Stretches to the parent's width and sweeps in from the left.
static func make_header_rule(color: Color = COLOR_ACCENT) -> Control:
	var rule := ColorRect.new()
	rule.color = Color(color, 0.30)
	rule.custom_minimum_size = Vector2(0.0, 2.0)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	animate_rule(rule)
	return rule


## Grow-from-zero entrance for a rule/underline Control. Scale-only, so it
## never triggers container relayout; pivot centers when the rule has a fixed
## authored width and stays left-anchored for stretch-to-fill rules.
static func animate_rule(rule: Control) -> void:
	if GameConfig.is_headless():
		return
	var start := func() -> void:
		rule.pivot_offset = Vector2(rule.custom_minimum_size.x * 0.5, rule.custom_minimum_size.y * 0.5)
		rule.scale.x = 0.0
		var tween := rule.create_tween()
		tween.tween_interval(0.12)
		tween.tween_property(rule, "scale:x", 1.0, 0.5) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	rule.ready.connect(start, CONNECT_ONE_SHOT)


## Unified screen-entry transition: staggered fade + rise for a screen's main
## blocks (title, cards, buttons). Call from _ready after building children;
## no await needed by callers. Headless runs skip it entirely so sims and the
## unit suite see final layout immediately. Items freed mid-flight are skipped.
static func play_entrance(root: Control, items: Array[Control], rise: float = 20.0) -> void:
	if GameConfig.is_headless():
		return
	for item: Control in items:
		item.modulate.a = 0.0
	var tree := root.get_tree()
	if tree == null:
		for item: Control in items:
			item.modulate.a = 1.0
		return
	# Two frames before capturing target positions: queue_freed siblings leave
	# the tree and containers finish sorting (mode_select rebuilds steps).
	var second_frame := func() -> void:
		_start_entrance(root, items, rise)
	var first_frame := func() -> void:
		tree.process_frame.connect(second_frame, CONNECT_ONE_SHOT)
	tree.process_frame.connect(first_frame, CONNECT_ONE_SHOT)


static func _start_entrance(root: Control, items: Array[Control], rise: float) -> void:
	if not is_instance_valid(root) or not root.is_inside_tree():
		return
	for i: int in items.size():
		var item := items[i]
		if not is_instance_valid(item) or not item.is_inside_tree():
			continue
		var target_y := item.position.y
		item.position.y = target_y + rise
		# Tight stagger: the whole cascade lands inside ~0.6s so menus feel
		# instant while still reading as a choreographed entrance.
		var delay := minf(0.02 + 0.04 * float(i), 0.38)
		var tween := item.create_tween()
		tween.set_parallel(true)
		tween.tween_property(item, "modulate:a", 1.0, 0.20).set_delay(delay)
		tween.tween_property(item, "position:y", target_y, 0.28) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(delay)


## Rasterizes an inline SVG string into a texture. Returns null when the
## SVG module is unavailable (callers should fall back to text glyphs).
static func make_icon(svg: String, scale: float = 1.0) -> ImageTexture:
	var img := Image.new()
	if img.load_svg_from_string(svg, scale) != OK:
		return null
	return ImageTexture.create_from_image(img)


## A drawn arrow. `dir` is "left", "right", "up", "down" or "both".
##
## One source path rotated in image space, so all five read as the same pen at
## the same weight. Cached per direction/colour/size -- control hints rebuild
## on every HUD and menu construction and this must not rasterize each time.
static func arrow_texture(dir: String, color: Color = COLOR_TEXT, px: int = 40) -> ImageTexture:
	var key := "%s|%s|%d" % [dir, color.to_html(true), px]
	if _arrow_cache.has(key):
		return _arrow_cache[key] as ImageTexture
	var svg: String = ARROW_BOTH_SVG if dir == "both" else ARROW_SVG
	var img := Image.new()
	if img.load_svg_from_string(svg % ("#" + color.to_html(false)),
			maxf(float(px), 8.0) / 64.0) != OK:
		return null
	match dir:
		"down":
			img.rotate_90(CLOCKWISE)
		"up":
			img.rotate_90(COUNTERCLOCKWISE)
		"left":
			img.rotate_180()
	var tex := ImageTexture.create_from_image(img)
	_arrow_cache[key] = tex
	return tex


## Arrow as a laid-out control, sized in logical pixels.
static func arrow_icon(dir: String, side: float, color: Color = COLOR_TEXT) -> Control:
	var tex := arrow_texture(dir, color, maxi(16, int(side * 2.0)))
	if tex == null:
		# SVG module unavailable: a plain ASCII stand-in still reads, where the
		# Unicode arrow would have been an empty box.
		var glyph := Label.new()
		glyph.text = {"left": "<", "right": ">", "up": "^", "down": "v"}.get(dir, "<>")
		glyph.add_theme_font_size_override("font_size", maxi(10, int(side)))
		glyph.add_theme_color_override("font_color", color)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return glyph
	var rect := TextureRect.new()
	rect.texture = tex
	rect.custom_minimum_size = Vector2(side, side)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## Rounded gradient fill texture for ProgressBar fills (StyleBoxFlat cannot
## gradient). Lighter crest at the top gives bars a glassy read.
static func make_bar_fill(from: Color, to: Color) -> StyleBoxTexture:
	var w := 96
	var h := 16
	var radius := 6.0
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y: int in h:
		var shade := 1.0 + (0.5 - float(y) / float(h - 1)) * 0.28
		for x: int in w:
			var color := from.lerp(to, float(x) / float(w - 1))
			color.r = minf(color.r * shade, 1.0)
			color.g = minf(color.g * shade, 1.0)
			color.b = minf(color.b * shade, 1.0)
			var ax := minf(float(x), float(w - 1 - x))
			var ay := minf(float(y), float(h - 1 - y))
			if ax < radius and ay < radius:
				var dx := radius - ax
				var dy := radius - ay
				var dist := sqrt(dx * dx + dy * dy) - radius
				color.a *= clampf(0.5 - dist, 0.0, 1.0)
			img.set_pixel(x, y, color)
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(img)
	sb.texture_margin_left = radius
	sb.texture_margin_right = radius
	return sb


## Themed track/fill/knob for HSliders. Same material as everything else: the
## track is an inset channel (darkest along its *top* edge, the inverse of a
## raised surface), the fill is a glossy accent bar lit from above, and the
## grabber is a baked knob with its own rim and shadow so the control has a
## real handle instead of the engine's default white dot.
static func style_slider(slider: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.024, 0.051, 0.098, 0.92)
	track.set_corner_radius_all(6)
	track.set_border_width_all(1)
	track.border_color = Color(0.0, 0.008, 0.031, 0.55)
	track.border_width_top = 2
	track.border_blend = true
	track.content_margin_top = 6.0
	track.content_margin_bottom = 6.0
	track.anti_aliasing = true
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.235, 0.573, 0.847)
	fill.border_color = Color(0.76, 0.94, 1.0, 0.90)
	fill.set_border_width_all(0)
	fill.border_width_top = 3
	fill.border_blend = true
	fill.set_corner_radius_all(6)
	fill.content_margin_top = 6.0
	fill.content_margin_bottom = 6.0
	fill.anti_aliasing = true
	var fill_hot := fill.duplicate() as StyleBoxFlat
	fill_hot.bg_color = Color(0.310, 0.678, 0.949)
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill_hot)
	slider.add_theme_icon_override("grabber", _knob_tex(Color(0.90, 0.96, 1.0)))
	slider.add_theme_icon_override("grabber_highlight", _knob_tex(Color(0.72, 0.92, 1.0)))
	slider.add_theme_icon_override("grabber_disabled", _knob_tex(Color(0.42, 0.48, 0.58)))
	# Touchscreens get a taller control rect: the track stays slim but the
	# whole rect accepts drags, so fingertips land reliably.
	if is_touch():
		slider.custom_minimum_size.y = maxf(slider.custom_minimum_size.y, float(TOUCH_MIN_HEIGHT))


## Baked slider knob: a domed disc, lit from above, with its own rim and a soft
## drop shadow. Cached per tint, so the whole game shares three of them.
static func _knob_tex(tint: Color) -> ImageTexture:
	var key := tint.to_html(false)
	if _knob_textures.has(key):
		return _knob_textures[key] as ImageTexture
	var size := 30
	var radius := 10.0
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(float(size) * 0.5 - 0.5, float(size) * 0.5 - 0.5)
	for y: int in size:
		for x: int in size:
			var p := Vector2(float(x), float(y)) - center
			var shadow_d := (p - Vector2(0.0, 1.5)).length() - radius
			var k := clampf(1.0 - shadow_d / 6.0, 0.0, 1.0)
			var out := Color(COLOR_SHADOW_SOFT.r, COLOR_SHADOW_SOFT.g, COLOR_SHADOW_SOFT.b,
				0.55 * k * k * k)
			var cover := clampf(radius + 0.5 - p.length(), 0.0, 1.0)
			if cover > 0.0:
				var down := clampf((p.y + radius) / (radius * 2.0), 0.0, 1.0)
				var face := tint.lerp(tint.darkened(0.30), down)
				var edge := p.length() - (radius - 1.8)
				if edge > 0.0:
					face = face.lerp(Color(1.0, 1.0, 1.0), 0.45 * clampf(edge / 1.8, 0.0, 1.0))
				out = _over(Color(face.r, face.g, face.b, cover), out)
			img.set_pixel(x, y, out)
	var texture := ImageTexture.create_from_image(img)
	_knob_textures[key] = texture
	return texture


## Applies the button style family to an OptionButton picker.
static func style_option_button(picker: OptionButton) -> void:
	picker.add_theme_color_override("font_color", COLOR_TEXT)
	picker.add_theme_color_override("font_hover_color", Color.WHITE)
	picker.add_theme_color_override("font_focus_color", Color.WHITE)
	var normal := _button_box(BTN_FILL, COLOR_RIM, 1)
	normal.shadow_size = 4
	normal.shadow_offset = Vector2(0.0, 2.0)
	var hover := _button_box(BTN_FILL_HOVER, Color(COLOR_ACCENT, 0.95), 2)
	hover.shadow_size = 6
	hover.shadow_offset = Vector2(0.0, 3.0)
	var focus := _focus_ring(RADIUS_BUTTON + 2)
	picker.add_theme_stylebox_override("normal", normal)
	picker.add_theme_stylebox_override("hover", hover)
	picker.add_theme_stylebox_override("pressed", hover)
	picker.add_theme_stylebox_override("focus", focus)
	# Touchscreens: taller picker plus a roomier dropdown so each popup row
	# is a comfortable tap target.
	if is_touch():
		picker.custom_minimum_size.y = maxf(picker.custom_minimum_size.y, float(TOUCH_MIN_HEIGHT))
		var popup := picker.get_popup()
		popup.add_theme_font_size_override("font_size", scaled_font(19))
		popup.add_theme_constant_override("v_separation", scaled_int(14))


## Wires standard UI sounds onto a button. Call for every interactive button.
static func hook_sounds(button: BaseButton) -> void:
	button.mouse_entered.connect(AudioManager.ui_hover)
	button.focus_entered.connect(AudioManager.ui_hover)
	button.pressed.connect(AudioManager.ui_click)


## Left-edge right-swipe "back" gesture for touch menus. Adds an invisible
## SWIPE_BACK_EDGE_WIDTH-wide full-height strip along the left edge of
## `node`; a touch (or drag with the mouse) that starts inside the strip and
## travels right more than SWIPE_BACK_DISTANCE within SWIPE_BACK_TIME_MS
## fires `callback` once. The strip is edge-only, so sliders, lists, and
## buttons elsewhere on screen are unaffected. Call after building the
## menu's children so the strip sits on top of them. The callback should be
## the same action as the screen's Back button.
static func attach_swipe_back(node: Control, callback: Callable) -> void:
	var edge := Control.new()
	edge.name = "SwipeBackEdge"
	edge.anchor_left = 0.0
	edge.anchor_right = 0.0
	edge.anchor_top = 0.0
	edge.anchor_bottom = 1.0
	edge.offset_left = 0.0
	edge.offset_right = SWIPE_BACK_EDGE_WIDTH
	edge.offset_top = 0.0
	edge.offset_bottom = 0.0
	edge.mouse_filter = Control.MOUSE_FILTER_STOP
	edge.focus_mode = Control.FOCUS_NONE
	node.add_child(edge)
	# Gesture state shared by the lambda across events.
	var state := {"tracking": false, "start_x": 0.0, "start_ms": 0}
	edge.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			var touch := event as InputEventScreenTouch
			if touch.pressed:
				state["tracking"] = true
				state["start_x"] = touch.position.x
				state["start_ms"] = Time.get_ticks_msec()
			else:
				state["tracking"] = false
			return
		if event is InputEventMouseButton:
			var click := event as InputEventMouseButton
			if click.button_index == MOUSE_BUTTON_LEFT:
				if click.pressed:
					state["tracking"] = true
					state["start_x"] = click.position.x
					state["start_ms"] = Time.get_ticks_msec()
				else:
					state["tracking"] = false
			return
		if not bool(state["tracking"]):
			return
		var drag_x: float
		if event is InputEventScreenDrag:
			drag_x = (event as InputEventScreenDrag).position.x
		elif event is InputEventMouseMotion:
			drag_x = (event as InputEventMouseMotion).position.x
		else:
			return
		if Time.get_ticks_msec() - int(state["start_ms"]) > SWIPE_BACK_TIME_MS:
			state["tracking"] = false
			return
		if drag_x - float(state["start_x"]) >= SWIPE_BACK_DISTANCE:
			state["tracking"] = false
			AudioManager.ui_click()
			callback.call())


## Full-rect animated menu backdrop, built as a real sky rather than a navy
## wash. Layers, back to front:
##   1. flat deep base (nothing shows through it)
##   2. the sky: a five-stop vertical gradient with an indigo horizon band and
##      a wide cyan bloom high on the screen — the light source that makes the
##      vignette and the card rims make sense. Both are baked into ONE texture
##      rather than two stacked layers, because a menu's cost on mobile web is
##      full-screen overdraw and the bloom does not need its own pass.
##   3. a baked star field, fading out before it reaches the content
##   4. the aurora sheet (shader) and two parallax snow layers
##   5. a tiled grain wash that dithers away the banding a full-screen navy
##      gradient produces on 8-bit displays and cheap phone panels
##   6. an elliptical vignette that closes the corners
## Every texture here is baked once into a static and shared by every screen —
## menus rebuild their whole tree on each navigation, and re-generating
## gradients per screen was pure waste on single-threaded WASM.
## Quality-gated so low-end and headless runs stay cheap: "low" keeps exactly
## the three layers it had before this pass, and grain is high-only.
static func make_background(parent: Control) -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_BG_DEEP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)
	parent.add_child(_full_rect(_sky_tex()))

	var quality := String(SettingsManager.get_setting("display", "particle_quality"))
	if not GameConfig.is_headless() and quality != "low":
		_add_stars(parent)
		_add_aurora(parent)
		_add_snow(parent, quality)
		if quality == "high":
			_add_grain(parent)
	_add_vignette(parent)


## Inert full-screen TextureRect: the shape every backdrop layer takes.
static func _full_rect(texture: Texture2D) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = texture
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## The sky, baked once: a five-stop vertical ramp (cool upper band, mid navy,
## indigo horizon for the aurora to sit on, deep floor) with a wide elliptical
## cyan bloom composited into it high on the screen. Low-res on purpose — it is
## stretched over the whole viewport, so 128x72 is plenty and costs 36 KB.
static func _sky_tex() -> ImageTexture:
	if _bg_gradient != null:
		return _bg_gradient
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(0.075, 0.145, 0.278),
		Color(0.106, 0.180, 0.310),
		COLOR_BG,
		Color(0.043, 0.082, 0.157),
		COLOR_BG_DEEP,
	])
	grad.offsets = PackedFloat32Array([0.0, 0.22, 0.48, 0.76, 1.0])
	var w := 128
	var h := 72
	var glow := Color(0.38, 0.64, 0.90)
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y: int in h:
		var base := grad.sample(float(y) / float(h - 1))
		for x: int in w:
			var u := Vector2(float(x) / float(w - 1), float(y) / float(h - 1))
			# Wide, high ellipse: reads as "the sky is lit from up there",
			# never as a visible blob.
			var d := Vector2((u.x - 0.5) / 0.80, (u.y - 0.15) / 0.46).length()
			var k := clampf(1.0 - d, 0.0, 1.0)
			k = k * k * (3.0 - 2.0 * k)  # smoothstep falloff
			var color := base.lerp(glow, k * 0.22)
			img.set_pixel(x, y, Color(color.r, color.g, color.b, 1.0))
	_bg_gradient = ImageTexture.create_from_image(img)
	return _bg_gradient


## Baked star field: deterministic, dim, top-weighted, and gone well before the
## content column starts. Costs one shared texture and one TextureRect — no
## particles, no shader, no per-frame work.
static func _add_stars(parent: Control) -> void:
	var stars := _full_rect(_star_tex())
	# Cover, not scale: stretching the field to a portrait viewport turned every
	# star into a vertical dash. Cropping keeps them round on any aspect.
	stars.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	parent.add_child(stars)


static func _star_tex() -> ImageTexture:
	if _star_texture != null:
		return _star_texture
	var w := 480
	var h := 270
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x57ADD1E  # fixed: the sky is the same every launch
	for i: int in 260:
		var x := rng.randi_range(1, w - 2)
		var y := rng.randi_range(1, h - 2)
		# Stars thin out toward the bottom so they never fight the menu column.
		var height_fade := clampf(1.0 - float(y) / float(h) * 1.35, 0.0, 1.0)
		if height_fade <= 0.02:
			continue
		var bright := rng.randf_range(0.18, 0.85) * height_fade
		var tint := Color(1.0, 1.0, 1.0).lerp(Color(0.62, 0.82, 1.0), rng.randf())
		img.set_pixel(x, y, Color(tint.r, tint.g, tint.b, bright))
		# A handful of brighter stars get a one-pixel halo so they twinkle when
		# the texture is scaled up to the screen.
		if bright > 0.62:
			var halo := Color(tint.r, tint.g, tint.b, bright * 0.28)
			img.set_pixel(x - 1, y, halo)
			img.set_pixel(x + 1, y, halo)
			img.set_pixel(x, y - 1, halo)
			img.set_pixel(x, y + 1, halo)
	_star_texture = ImageTexture.create_from_image(img)
	return _star_texture


## Tiled monochrome grain at ~2% alpha. Its job is dithering: a full-screen
## navy gradient bands badly on 8-bit panels, and the banding is the single
## most "cheap" looking thing about a dark menu. Also adds a faint film texture
## that makes the flat regions read as a surface.
static func _add_grain(parent: Control) -> void:
	var grain := TextureRect.new()
	grain.texture = _grain_tex()
	grain.stretch_mode = TextureRect.STRETCH_TILE
	grain.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	grain.set_anchors_preset(Control.PRESET_FULL_RECT)
	grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(grain)


static func _grain_tex() -> ImageTexture:
	if _grain_texture != null:
		return _grain_texture
	var size := 64
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x6A41
	for y: int in size:
		for x: int in size:
			var v := rng.randf()
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, v * 0.028))
	_grain_texture = ImageTexture.create_from_image(img)
	return _grain_texture


static func _add_aurora(parent: Control) -> void:
	var aurora := ColorRect.new()
	aurora.anchor_left = 0.0
	aurora.anchor_top = 0.0
	aurora.anchor_right = 1.0
	aurora.anchor_bottom = 0.62
	aurora.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var strength := 0.09 if reduced_motion() else 0.16
	aurora.material = _aurora_material(strength)
	parent.add_child(aurora)


## Shared aurora material per strength value: menus rebuild the backdrop on
## every navigation, so caching avoids a shader recompile + new material each
## screen change (single-threaded WASM jank guard).
static func _aurora_material(strength: float) -> ShaderMaterial:
	var key := "%.2f" % strength
	if _aurora_materials.has(key):
		return _aurora_materials[key] as ShaderMaterial
	if _aurora_shader == null:
		_aurora_shader = Shader.new()
		_aurora_shader.code = AURORA_SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = _aurora_shader
	material.set_shader_parameter("strength", strength)
	_aurora_materials[key] = material
	return material


## Two parallax snow layers: a dim, small, slow "far" layer behind a brighter
## "near" layer. The depth split is what sells the backdrop; the far layer is
## high-quality only so low/medium budgets are unchanged.
static func _add_snow(parent: Control, quality: String) -> void:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(holder)
	var center_x := parent.get_viewport_rect().size.x * 0.5
	if quality == "high":
		var far := _make_snow_layer(16, 0.7, 1.6, 12.0, 26.0, 0.26)
		far.position = Vector2(center_x, -16.0)
		holder.add_child(far)
	var near := _make_snow_layer(40 if quality == "high" else 22, 1.2, 3.2, 26.0, 58.0, 0.5)
	near.position = Vector2(center_x, -16.0)
	holder.add_child(near)


static func _make_snow_layer(amount: int, scale_min: float, scale_max: float,
		vel_min: float, vel_max: float, alpha: float) -> CPUParticles2D:
	var snow := CPUParticles2D.new()
	snow.amount = amount
	snow.lifetime = 14.0
	snow.preprocess = 14.0
	snow.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	snow.emission_rect_extents = Vector2(1400.0, 8.0)
	snow.direction = Vector2(0.05, 1.0)
	snow.spread = 12.0
	snow.gravity = Vector2(0.0, 4.0)
	snow.initial_velocity_min = vel_min
	snow.initial_velocity_max = vel_max
	snow.scale_amount_min = scale_min
	snow.scale_amount_max = scale_max
	snow.angular_velocity_min = -40.0
	snow.angular_velocity_max = 40.0
	snow.color = Color(0.92, 0.96, 1.0, alpha)
	return snow


## Corner vignette. Blue-black rather than neutral (matching COLOR_SHADOW_SOFT)
## and a touch deeper than before, so the lit upper-centre reads as a real
## light source instead of the screen being evenly bright. Shared texture.
static func _add_vignette(parent: Control) -> void:
	if _vignette_texture == null:
		var edge := Color(0.004, 0.012, 0.031)
		var grad := Gradient.new()
		grad.colors = PackedColorArray([
			Color(edge.r, edge.g, edge.b, 0.0),
			Color(edge.r, edge.g, edge.b, 0.06),
			Color(edge.r, edge.g, edge.b, 0.44),
		])
		grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		_vignette_texture = GradientTexture2D.new()
		_vignette_texture.gradient = grad
		_vignette_texture.fill = GradientTexture2D.FILL_RADIAL
		_vignette_texture.fill_from = Vector2(0.5, 0.46)
		_vignette_texture.fill_to = Vector2(0.5, -0.20)
		_vignette_texture.width = 128
		_vignette_texture.height = 128
	parent.add_child(_full_rect(_vignette_texture))


## Screen roots call this on entry. It now only guarantees an identity
## transform -- the accessibility ui_scale is applied elsewhere, and applying
## it here as well was cutting every menu off at its edges.
##
## SettingsManager._apply_ui_scale already implements the setting the right
## way: it SHRINKS window.content_scale_size, which makes each logical unit
## cover more physical pixels while leaving the layout a smaller logical canvas
## to reflow into. Containers then genuinely re-fit -- columns narrow, grids
## drop to fewer columns, text wraps.
##
## This function used to multiply the screen root's transform by the same
## setting on top of that. A Control transform cannot reflow anything; it just
## magnifies about the pivot, so at ui_scale 1.5 the layout was first fitted
## correctly to a 1280x720 canvas and then blown up 1.4x about the centre,
## pushing roughly forty per cent of every screen past the edges of the
## display. Tabs, cards, the Back button and the account chip all lost their
## outer edges, and the larger the player set the scale -- that is, the more
## they needed to read it -- the more of the screen went missing.
##
## Kept as a no-op rather than deleted so the eleven screens that call it stay
## explicit about resetting any inherited scale.
static func apply_ui_scale(root: Control) -> void:
	root.scale = Vector2.ONE
