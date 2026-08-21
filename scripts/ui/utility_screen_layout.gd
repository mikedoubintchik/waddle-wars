class_name UtilityScreenLayout
extends RefCounted
## Shared geometry contract for secondary front-end screens.
##
## These screens contain dense, scrollable data rather than one hero action,
## but they still need the same orientation and safe-area rules as the main
## expedition hub.  Keeping the small amount of geometry here prevents each
## screen from inventing a different notch gutter or phone breakpoint.

const MIN_TOUCH_TARGET: float = 44.0
const PHONE_CONTENT_FRACTION: float = 0.94
const TABLET_CONTENT_FRACTION: float = 0.90
const COMPACT_LANDSCAPE_FRACTION: float = 0.92
const WIDE_LANDSCAPE_FRACTION: float = 0.78


## Width for a utility page. Portrait deliberately spends almost all usable
## width; landscape leaves key art visible around the glass workspace.
static func page_width(profile: LayoutProfile, authored_max: float,
		minimum: float = 320.0, wide_fraction: float = WIDE_LANDSCAPE_FRACTION) -> float:
	if profile == null:
		return authored_max
	var fraction := wide_fraction
	match profile.view_class:
		LayoutProfile.ViewClass.PORTRAIT_NARROW:
			fraction = PHONE_CONTENT_FRACTION
		LayoutProfile.ViewClass.PORTRAIT_TABLET:
			fraction = TABLET_CONTENT_FRACTION
		LayoutProfile.ViewClass.LANDSCAPE_COMPACT:
			fraction = COMPACT_LANDSCAPE_FRACTION
		_:
			fraction = wide_fraction
	var usable := maxf(profile.safe_rect.size.x, 1.0)
	return clampf(minf(authored_max, usable * fraction),
		minf(minimum, usable), usable)


## Insets a full-rect page control to the live safe rectangle. The backdrop
## stays full bleed; only interactive/readable content moves inward.
static func apply_safe_rect(page: Control, profile: LayoutProfile) -> void:
	if page == null or profile == null:
		return
	page.offset_left = profile.safe_insets.x
	page.offset_top = profile.safe_insets.y
	page.offset_right = -profile.safe_insets.z
	page.offset_bottom = -profile.safe_insets.w


## Installs resize-safe inset updates and returns the initial profile. Layout
## composition is selected by the screen at build time; insets continue to
## track browser/native furniture while it remains open.
static func bind_safe_rect(host: Control, page: Control) -> LayoutProfile:
	var profile := LayoutProfile.for_viewport(host.get_viewport()) \
		if host != null and host.is_inside_tree() else LayoutProfile.for_view_size(Vector2.ONE)
	apply_safe_rect(page, profile)
	if host == null or not host.is_inside_tree():
		return profile
	var viewport := host.get_viewport()
	if viewport == null:
		return profile
	var refresh := func() -> void:
		if not is_instance_valid(host) or not is_instance_valid(page):
			return
		apply_safe_rect(page, LayoutProfile.for_viewport(host.get_viewport()))
	viewport.size_changed.connect(refresh)
	var teardown := func() -> void:
		if is_instance_valid(viewport) and viewport.size_changed.is_connected(refresh):
			viewport.size_changed.disconnect(refresh)
	# Rebuilt layouts replace `page` while the screen root survives a rotation.
	# Disconnect with the page, otherwise every rotation leaves a dead resize
	# callback attached until the whole screen closes.
	page.tree_exiting.connect(teardown, CONNECT_ONE_SHOT)
	return profile


## Calls `reflow` once, on the next frame, only when the semantic layout class
## changes. Raw resize events can arrive several times during sensor rotation;
## a mutable state capsule makes that burst one rebuild. Safe-area-only changes
## continue through bind_safe_rect() without rebuilding the screen.
static func bind_view_class(host: Node, reflow: Callable) -> LayoutProfile:
	var profile := LayoutProfile.for_viewport(host.get_viewport()) \
		if host != null and host.is_inside_tree() else LayoutProfile.for_view_size(Vector2.ONE)
	if host == null or not host.is_inside_tree() or not reflow.is_valid():
		return profile
	var viewport := host.get_viewport()
	if viewport == null:
		return profile
	var state := {"class": int(profile.view_class), "pending": false}
	var refresh := func() -> void:
		if bool(state["pending"]) or not is_instance_valid(host):
			return
		state["pending"] = true
		var apply := func() -> void:
			state["pending"] = false
			if not is_instance_valid(host) or not host.is_inside_tree():
				return
			var next := LayoutProfile.for_viewport(host.get_viewport())
			if int(next.view_class) == int(state["class"]):
				return
			state["class"] = int(next.view_class)
			reflow.call(next)
		var tree := host.get_tree()
		if tree != null:
			tree.process_frame.connect(apply, CONNECT_ONE_SHOT)
	viewport.size_changed.connect(refresh)
	var teardown := func() -> void:
		if is_instance_valid(viewport) and viewport.size_changed.is_connected(refresh):
			viewport.size_changed.disconnect(refresh)
	host.tree_exiting.connect(teardown, CONNECT_ONE_SHOT)
	return profile


static func scroll_fraction(scroll: ScrollContainer) -> float:
	if scroll == null or not is_instance_valid(scroll):
		return 0.0
	var bar := scroll.get_v_scroll_bar()
	if bar == null:
		return 0.0
	var travel := maxf(bar.max_value - bar.page, 0.0)
	return 0.0 if travel <= 0.0 else clampf(float(scroll.scroll_vertical) / travel, 0.0, 1.0)


## Restores after containers have completed their first sort in the new class.
static func restore_scroll_fraction(host: Node, scroll: ScrollContainer,
		fraction: float) -> void:
	if host == null or not host.is_inside_tree() or scroll == null:
		return
	var apply := func() -> void:
		if not is_instance_valid(scroll):
			return
		var bar := scroll.get_v_scroll_bar()
		if bar == null:
			return
		var travel := maxf(bar.max_value - bar.page, 0.0)
		scroll.scroll_vertical = roundi(travel * clampf(fraction, 0.0, 1.0))
	var tree := host.get_tree()
	if tree != null:
		tree.process_frame.connect(apply, CONNECT_ONE_SHOT)


## All actionable controls keep a physical-looking minimum even when a theme
## or a short landscape viewport asks a container to collapse them.
static func enforce_target(control: Control, authored_height: float = MIN_TOUCH_TARGET) -> Control:
	if control != null:
		control.custom_minimum_size.y = maxf(control.custom_minimum_size.y,
			UITheme.scaled_size(Vector2(0.0, authored_height)).y)
	return control


static func style_scrollbar(scroll: ScrollContainer, width: float = 9.0) -> void:
	if scroll == null:
		return
	var bar := scroll.get_v_scroll_bar()
	if bar == null:
		return
	bar.custom_minimum_size.x = width
	var track := StyleBoxFlat.new()
	track.bg_color = Color(UITheme.COLOR_BG_DEEP, 0.30)
	track.set_corner_radius_all(4)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(UITheme.COLOR_ACCENT, 0.34)
	grabber.set_corner_radius_all(4)
	grabber.anti_aliasing = true
	var hot := grabber.duplicate() as StyleBoxFlat
	hot.bg_color = Color(UITheme.COLOR_ACCENT, 0.68)
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)
	bar.add_theme_stylebox_override("grabber", grabber)
	bar.add_theme_stylebox_override("grabber_highlight", hot)
	bar.add_theme_stylebox_override("grabber_pressed", hot)


static func is_phone(profile: LayoutProfile) -> bool:
	return profile != null \
		and profile.view_class == LayoutProfile.ViewClass.PORTRAIT_NARROW


static func uses_stacked_rows(profile: LayoutProfile) -> bool:
	return profile != null and profile.is_portrait()


static func is_wide_landscape(profile: LayoutProfile) -> bool:
	return profile != null \
		and profile.view_class == LayoutProfile.ViewClass.LANDSCAPE_WIDE
