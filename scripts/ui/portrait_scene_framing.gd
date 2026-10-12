class_name PortraitSceneFraming
extends RefCounted
## Keep the authored upper scene in view when a portrait illustration is used
## behind a wide menu. Centered cover would show only empty lower ice/floor.

static func bind(art: TextureRect, top_fraction: float = 0.035) -> void:
	var original := art.texture
	var owner := art.get_parent() as Control
	var reframe := func() -> void:
		if not is_instance_valid(art) or original == null:
			return
		var view := art.get_viewport_rect().size
		if view.y >= view.x:
			art.texture = original
			return
		var source := original.get_size()
		var crop_height := minf(source.y, source.x * view.y / view.x)
		var atlas := AtlasTexture.new()
		atlas.atlas = original
		atlas.region = Rect2(0.0, minf(source.y * top_fraction, source.y - crop_height),
			source.x, crop_height)
		atlas.filter_clip = true
		art.texture = atlas
	if owner != null:
		owner.resized.connect(func() -> void: reframe.call_deferred())
	reframe.call_deferred()

static func readable_size(base: int) -> int:
	return base if UITheme.is_touch() else roundi(float(base) * 1.6)
