extends RefCounted
## Orientation-specific scene plates contain no interactive UI.

static func bind(art: TextureRect, portrait: String, desktop: String) -> void:
	var owner := art.get_parent() as Control
	var reframe := func() -> void:
		if not is_instance_valid(art): return
		var view := art.get_viewport_rect().size
		art.texture = ExpeditionMenuStyle._material_texture(portrait if view.y >= view.x else desktop)
		art.material = null
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	owner.resized.connect(func() -> void: reframe.call_deferred())
	reframe.call_deferred()
