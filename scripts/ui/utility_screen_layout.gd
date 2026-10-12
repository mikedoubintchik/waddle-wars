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


## Shared phone header contract. Artwork remains full bleed; readable titles,
## back buttons and balances share one center line below the camera cutout.
## Call after authored page sizing, since several pages override shell sizes.
static func align_header_controls(profile: LayoutProfile, title: Control,
		back: Control, companions: Array[Control] = []) -> void:
	if profile == null or title == null or not is_instance_valid(title):
		return
	# Preserve the deliberately asymmetric desktop art compositions.
	if not profile.is_portrait() and profile.safe_insets == Vector4.ZERO:
		return
	var controls: Array[Control] = [title]
	if is_instance_valid(back): controls.append(back)
	for control: Control in companions:
		if is_instance_valid(control): controls.append(control)
	var gap := minf(12.0, profile.viewport_size.x * 0.012)
	var left := profile.safe_rect.position.x
	var right := profile.safe_rect.end.x
	var original_center_x := title.global_position.x + title.size.x * 0.5
	for control: Control in controls:
		if control == title: continue
		var rect := control.get_global_rect()
		if rect.get_center().x < original_center_x:
			left = maxf(left, rect.end.x + gap)
		else:
			right = minf(right, rect.position.x - gap)
	# Side controls need their own columns. Shrink the title art into the
	# remaining interval rather than letting large titles cover Back/currency.
	if right > left:
		title.size.x = minf(title.size.x, right - left)
		title.global_position.x = clampf(original_center_x - title.size.x * 0.5,
			left, maxf(left, right - title.size.x))
	var tallest := 0.0
	for control: Control in controls:
		tallest = maxf(tallest, control.size.y)
	var center_y := maxf(title.global_position.y + title.size.y * 0.5,
		profile.safe_rect.position.y + gap + tallest * 0.5)
	for control: Control in controls:
		var position := control.global_position
		position.y = center_y - control.size.y * 0.5
		position.x = clampf(position.x, profile.safe_rect.position.x,
			maxf(profile.safe_rect.position.x, profile.safe_rect.end.x - control.size.x))
		control.global_position = position


## Containers settle after page construction. Weak references avoid retaining
## old headers when rotation/navigation replaces a page before the next frame.
static func defer_header_alignment(host: Node, title: Control, back: Control,
		companions: Array[Control] = []) -> void:
	if host == null or not host.is_inside_tree() or title == null:
		return
	var host_ref: WeakRef = weakref(host)
	var title_ref: WeakRef = weakref(title)
	var back_ref: WeakRef = weakref(back) if back != null else null
	var companion_refs: Array[WeakRef] = []
	for control: Control in companions:
		if is_instance_valid(control): companion_refs.append(weakref(control))
	var apply := func() -> void:
		var live_host := host_ref.get_ref() as Node
		var live_title := title_ref.get_ref() as Control
		if live_host == null or not live_host.is_inside_tree() or live_title == null:
			return
		var live_companions: Array[Control] = []
		for reference: WeakRef in companion_refs:
			var control := reference.get_ref() as Control
			if control != null: live_companions.append(control)
		align_header_controls(LayoutProfile.for_viewport(live_host.get_viewport()),
			live_title, back_ref.get_ref() as Control if back_ref != null else null,
			live_companions)
	host.get_tree().process_frame.connect(func() -> void: apply.call_deferred(), CONNECT_ONE_SHOT)


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
	# A resize listener earlier in the signal can rebuild/free this page before
	# our already-dispatched callback runs. Weak captures remain valid objects
	# even then; capturing the page itself warns before a validity guard executes.
	var host_ref: WeakRef = weakref(host)
	var page_ref: WeakRef = weakref(page)
	var viewport_ref: WeakRef = weakref(viewport)
	var refresh := func() -> void:
		var live_host := host_ref.get_ref() as Control
		var live_page := page_ref.get_ref() as Control
		if live_host == null or live_page == null or not live_host.is_inside_tree():
			return
		apply_safe_rect(live_page, LayoutProfile.for_viewport(live_host.get_viewport()))
	viewport.size_changed.connect(refresh)
	var teardown := func() -> void:
		var live_viewport := viewport_ref.get_ref() as Viewport
		if live_viewport != null and live_viewport.size_changed.is_connected(refresh):
			live_viewport.size_changed.disconnect(refresh)
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
