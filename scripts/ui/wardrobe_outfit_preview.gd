extends Control
## A finished transparent outfit illustration; garments are never overlaid.
## Separate ambient trail uses the same particle artwork/colors as gameplay.

const LIBRARY = preload("res://scripts/ui/wardrobe_outfit_library.gd")
const TRAIL_GLYPH_MIN_FRACTION := 0.04
const TRAIL_GLYPH_MAX_FRACTION := 0.06
var library: LIBRARY = null
var sprite: TextureRect
var message: Label
var trail: CPUParticles2D = null
var trail_id := ""
var equipped: Dictionary = {}
var displayed_key := ""
var _opaque_bounds := Rect2()
var _bounds_cache: Dictionary = {}


func _ready() -> void:
	name = "FinishedWardrobePreview"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	sprite = TextureRect.new()
	sprite.name = "CompleteOutfitImage"
	sprite.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sprite)
	message = ExpeditionMenuStyle.label("Loading outfit preview…", PortraitSceneFraming.readable_size(20))
	message.name = "OutfitPreviewStatus"
	message.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(message)
	resized.connect(_layout_trail)
	resized.connect(_layout_character)
	if library != null:
		library.preview_changed.connect(_on_preview_changed)
		_on_preview_changed(library.requested_key, library.current_texture, library.state)


func show_equipped(look: Dictionary) -> void:
	equipped = look.duplicate()
	_show_trail(String(equipped.get("trail", "")))
	if library != null:
		library.select_outfit(equipped)


func _on_preview_changed(key: String, texture: Texture2D, status: String) -> void:
	sprite.texture = texture
	sprite.visible = status == "ready" and texture != null
	displayed_key = key if sprite.visible else ""
	if sprite.visible:
		if not _bounds_cache.has(key):
			# Generated full-character images retain different transparent margins.
			# Measure their silhouette once; keep the untouched complete texture.
			var pixels := texture.get_image()
			var left := pixels.get_width()
			var top := pixels.get_height()
			var right := 0
			var bottom := 0
			for y: int in pixels.get_height():
				for x: int in pixels.get_width():
					if pixels.get_pixel(x, y).a >= 0.25:
						left = mini(left, x)
						top = mini(top, y)
						right = maxi(right, x + 1)
						bottom = maxi(bottom, y + 1)
			_bounds_cache[key] = Rect2(left, top, right - left, bottom - top)
			if _bounds_cache.size() > LIBRARY.CACHE_LIMIT:
				_bounds_cache.erase(_bounds_cache.keys()[0])
		_opaque_bounds = _bounds_cache[key]
		_layout_character()
	message.visible = not sprite.visible
	message.text = "Loading outfit preview…" if status == "loading" else "Outfit preview unavailable.\nChoose another combination."
	if trail != null:
		trail.visible = sprite.visible
		trail.emitting = sprite.visible


func _layout_character() -> void:
	if sprite == null or sprite.texture == null or not _opaque_bounds.has_area():
		return
	# Preserve authored body/hat proportions; only compensate transparent margins
	# for the common ground line rather than stretching every silhouette to fit.
	var factor := minf(size.x * 0.92 / sprite.texture.get_width(),
		size.y / sprite.texture.get_height())
	sprite.set_anchors_preset(Control.PRESET_TOP_LEFT)
	sprite.size = sprite.texture.get_size() * factor
	sprite.position = Vector2((size.x - _opaque_bounds.size.x * factor) * 0.5 - _opaque_bounds.position.x * factor,
		size.y * 0.96 - _opaque_bounds.end.y * factor)


func _show_trail(id: String) -> void:
	if trail_id == id:
		return
	trail_id = id
	if trail != null:
		trail.emitting = false
		trail.hide()
		trail.queue_free()
		trail = null
	if id.is_empty() or String(CosmeticsDB.get_item(id).get("category", "")) != "trail":
		return
	trail = CPUParticles2D.new()
	trail.name = "IndependentTrailPreview"
	trail.set_meta("cosmetic_id", id)
	trail.texture = TrailEffect._particle_texture(id)
	trail.amount = 12
	trail.lifetime = 1.5
	trail.preprocess = 0.5
	trail.direction = Vector2(-1, -0.12)
	trail.spread = 20.0
	trail.gravity = Vector2(0, 12)
	# Match the full-color gameplay artwork without a second hue/tint pass.
	trail.color = Color(1, 1, 1, 0.75)
	trail.color_ramp = TrailEffect.fade_gradient()
	trail.visible = sprite.visible
	trail.emitting = sprite.visible
	add_child(trail)
	move_child(trail, 0)
	_layout_trail()


func _layout_trail() -> void:
	if trail == null:
		return
	trail.position = Vector2(size.x * 0.47, size.y * 0.88)
	trail.initial_velocity_min = size.y * 0.12
	trail.initial_velocity_max = size.y * 0.22
	# A modest1.5x enlargement: artwork spans4–6% of the stage height rather
	# than2.7–4%. Normalise by texture pixels, never by import resolution.
	var texture_width := maxf(1.0, trail.texture.get_width() if trail.texture != null else 64.0)
	trail.scale_amount_min = size.y * TRAIL_GLYPH_MIN_FRACTION / texture_width
	trail.scale_amount_max = size.y * TRAIL_GLYPH_MAX_FRACTION / texture_width
