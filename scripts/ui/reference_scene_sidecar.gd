class_name ReferenceSceneSidecar
extends RefCounted
## Preserve the whole illustrated cast beside a wide page. The original
## portrait plate remains untouched; the pale edge recedes under the cards.

static func bind(art: TextureRect, paper: Color = Color("b9d7e9")) -> void:
	var original := art.texture
	var owner := art.get_parent() as Control
	var wash := ColorRect.new()
	wash.name = "ReferenceSceneWash"
	wash.color = paper
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	owner.add_child(wash)
	owner.move_child(wash, art.get_index())
	var fade := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; void fragment(){ COLOR = texture(TEXTURE, UV); COLOR.a *= 1.0 - smoothstep(0.90, 1.0, UV.x); }"
	fade.shader = shader
	var reframe := func() -> void:
		if not is_instance_valid(art) or original == null:
			return
		var view := art.get_viewport_rect().size
		var wide := view.x > view.y
		wash.visible = wide
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.material = fade if wide else null
		art.texture = original
		if not wide:
			return
		art.anchor_right = 0.52
		var source := original.get_size()
		var height := minf(source.y, source.x * view.y / (view.x * 0.52))
		var crop := AtlasTexture.new()
		crop.atlas = original
		crop.region = Rect2(0.0, minf(source.y * 0.025, source.y - height), source.x, height)
		crop.filter_clip = true
		art.texture = crop
	owner.resized.connect(func() -> void: reframe.call_deferred())
	reframe.call_deferred()
