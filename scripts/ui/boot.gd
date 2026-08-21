extends Control
## Branded expedition departure splash.
##
## First frame is simple Canvas UI. BootWarmup then fills front-end caches;
## authored backdrop and cached wordmark attach without further decoding.

const MIN_HOLD: float = 1.25
const MAX_HOLD: float = 3.5
const UPDATE_STEP: float = 1.0 / 30.0

var _elapsed: float = 0.0
var _accumulator: float = 0.0
var _routed: bool = false
var _reduced_motion: bool = false
var _art_installed: bool = false

var _base: ColorRect = null
var _first_mark: Label = null
var _content: VBoxContainer = null
var _logo_slot: Control = null
var _fallback_logo: Label = null
var _route_fill: ColorRect = null
var _waypoints: Array[Panel] = []
var _studio_label: Label = null


func _ready() -> void:
	_build_first_frame()
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_apply_layout):
		viewport.size_changed.connect(_apply_layout)
	BootWarmup.warm(self)
	_upgrade_after_first_present()


func _build_first_frame() -> void:
	_base = ColorRect.new()
	_base.name = "PolarNightBase"
	_base.color = Color(0.018, 0.045, 0.085, 1.0)
	_base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_base)
	# Built-in font only. Custom fonts, styles, route chrome, and key art wait
	# until this frame reaches screen; cold launch must present under 100 ms.
	_first_mark = Label.new()
	_first_mark.name = "ImmediateWordmark"
	_first_mark.text = GameConfig.GAME_NAME.to_upper()
	_first_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_first_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_first_mark.add_theme_font_size_override("font_size", 58)
	_first_mark.add_theme_color_override("font_color", Color(0.93, 0.98, 1.0))
	_first_mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_first_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_first_mark)


func _upgrade_after_first_present() -> void:
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	_reduced_motion = UITheme.reduced_motion()
	_build_rich_presentation()
	_apply_layout()
	if _first_mark != null:
		_first_mark.queue_free()
		_first_mark = null
	if not _art_installed and FrontEndBackdrop.textures_ready():
		_install_cached_art()


func _build_rich_presentation() -> void:

	var center := CenterContainer.new()
	center.name = "DepartureCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_content = VBoxContainer.new()
	_content.name = "DepartureStack"
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_theme_constant_override("separation", 10)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_content)

	var eyebrow := Label.new()
	eyebrow.text = "ANTARCTIC EXPEDITION NETWORK"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_font_override("font", UITheme.bold_font())
	eyebrow.add_theme_font_size_override("font_size", 17)
	eyebrow.add_theme_color_override("font_color", Color(1.0, 0.81, 0.34))
	eyebrow.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.10, 0.94))
	eyebrow.add_theme_constant_override("outline_size", 6)
	_content.add_child(eyebrow)

	_logo_slot = Control.new()
	_logo_slot.name = "LogoSlot"
	_logo_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_logo_slot)
	_fallback_logo = Label.new()
	_fallback_logo.text = GameConfig.GAME_NAME.to_upper()
	_fallback_logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fallback_logo.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fallback_logo.add_theme_font_override("font", UITheme.display_font())
	_fallback_logo.add_theme_font_size_override("font_size", 72)
	_fallback_logo.add_theme_color_override("font_color", Color(0.93, 0.98, 1.0))
	_fallback_logo.add_theme_color_override("font_outline_color", Color(0.04, 0.12, 0.22))
	_fallback_logo.add_theme_constant_override("outline_size", 12)
	_fallback_logo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fallback_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo_slot.add_child(_fallback_logo)

	var status := Label.new()
	status.text = "DEPARTURE CONTROL  ·  ROUTE TO RESEARCH CITY"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_override("font", UITheme.caption_font())
	status.add_theme_font_size_override("font_size", 15)
	status.add_theme_color_override("font_color", Color(0.75, 0.88, 0.98))
	status.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.10, 0.92))
	status.add_theme_constant_override("outline_size", 5)
	_content.add_child(status)
	_content.add_child(_build_route())

	_studio_label = Label.new()
	_studio_label.text = "%s  ·  PRESENTS" % GameConfig.STUDIO_NAME.to_upper()
	_studio_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_studio_label.add_theme_font_override("font", UITheme.caption_font())
	_studio_label.add_theme_font_size_override("font_size", 13)
	_studio_label.add_theme_color_override("font_color", Color(0.58, 0.72, 0.84))
	_studio_label.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.10, 0.88))
	_studio_label.add_theme_constant_override("outline_size", 4)
	_studio_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_studio_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_studio_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_studio_label)

	if not _reduced_motion and not GameConfig.is_headless():
		_content.modulate.a = 0.0
		_content.position.y = 12.0
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(_content, "modulate:a", 1.0, 0.35)
		tween.tween_property(_content, "position:y", 0.0, 0.48) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _build_route() -> Control:
	var route := Control.new()
	route.name = "DepartureRoute"
	route.custom_minimum_size = Vector2(360.0, 28.0)
	route.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rail := ColorRect.new()
	rail.color = Color(0.36, 0.68, 0.88, 0.34)
	rail.anchor_left = 0.06
	rail.anchor_right = 0.94
	rail.anchor_top = 0.45
	rail.anchor_bottom = 0.57
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	route.add_child(rail)
	_route_fill = ColorRect.new()
	_route_fill.name = "DepartureProgress"
	_route_fill.color = Color(1.0, 0.80, 0.28, 0.96)
	_route_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_route_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail.add_child(_route_fill)
	for i: int in 3:
		var dot := Panel.new()
		dot.name = "DepartureWaypoint%d" % (i + 1)
		dot.anchor_left = 0.06 + float(i) * 0.44
		dot.anchor_right = dot.anchor_left
		dot.anchor_top = 0.5
		dot.anchor_bottom = 0.5
		dot.offset_left = -6.0
		dot.offset_right = 6.0
		dot.offset_top = -6.0
		dot.offset_bottom = 6.0
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.90, 0.97, 1.0)
		style.border_color = Color(0.18, 0.44, 0.67)
		style.set_border_width_all(2)
		style.set_corner_radius_all(8)
		dot.add_theme_stylebox_override("panel", style)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		route.add_child(dot)
		_waypoints.append(dot)
	return route


func _process(delta: float) -> void:
	_elapsed += delta
	_accumulator += delta
	if not _art_installed and FrontEndBackdrop.textures_ready():
		_install_cached_art()
	if _accumulator >= UPDATE_STEP:
		_accumulator = fmod(_accumulator, UPDATE_STEP)
		_update_route()
	var skip := Input.is_action_just_pressed("ui_accept") \
		or Input.is_action_just_pressed("pause")
	if skip or _elapsed > MAX_HOLD:
		_route()
	elif _elapsed > MIN_HOLD and BootWarmup.is_finished():
		_route()


func _install_cached_art() -> void:
	if _logo_slot == null:
		return
	_art_installed = true
	var backdrop := FrontEndBackdrop.new()
	backdrop.name = "ExpeditionBackdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.set_presentation(FrontEndBackdrop.Context.LOADING, 0.78,
		not _reduced_motion)
	add_child(backdrop)
	move_child(backdrop, 0)
	_base.color = Color(0.018, 0.045, 0.085, 0.52)
	var texture := TitleScreen.logo_texture()
	if texture == null:
		return
	var logo := TextureRect.new()
	logo.name = "WaddleWarsLogo"
	logo.texture = texture
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_logo_slot.add_child(logo)
	if _fallback_logo != null:
		_fallback_logo.queue_free()
		_fallback_logo = null


func _update_route() -> void:
	if _route_fill == null:
		return
	var progress := clampf(_elapsed / MAX_HOLD, 0.06, 0.90)
	if BootWarmup.is_finished():
		progress = 1.0
	_route_fill.scale = Vector2(progress, 1.0)
	for i: int in _waypoints.size():
		var reached := progress + 0.02 >= float(i) * 0.5
		_waypoints[i].modulate = Color.WHITE if reached \
			else Color(0.46, 0.58, 0.70, 0.58)


func _apply_layout() -> void:
	if _logo_slot == null or _studio_label == null:
		return
	var profile := LayoutProfile.for_viewport(get_viewport())
	var portrait := profile.is_portrait()
	var logo_width := minf(profile.safe_rect.size.x * (0.78 if portrait else 0.38),
		500.0)
	_logo_slot.custom_minimum_size = Vector2(logo_width, logo_width * 0.51)
	_studio_label.offset_left = -250.0
	_studio_label.offset_right = 250.0
	_studio_label.offset_top = -38.0 - profile.safe_insets.w
	_studio_label.offset_bottom = -16.0 - profile.safe_insets.w


func _input(event: InputEvent) -> void:
	if (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventMouseButton and event.pressed):
		_route()


func _route() -> void:
	if _routed:
		return
	_routed = true
	SceneRouter.go_to(Game.SCENE_TITLE)
