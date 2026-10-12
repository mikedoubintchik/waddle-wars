extends "res://tests/runner_life_pressure_test.gd"
## Shared clock/real accepted-hit cases plus actual authored-alpha sampling.
## Headless proves composition bounds/resources, not Chrome pixel acceptance.

func _ready() -> void:
	_test_clock()
	_test_real_hits()
	_check(passed + failed == 42, "all existing clock and accepted-hit cases reached")
	for shape: Vector2i in [Vector2i(1920,1080), Vector2i(800,1422)]:
		await _test_rear_snow(shape)
	await get_tree().create_timer(0.1).timeout
	print("[runner_rear_pressure] %d/%d passed" % [passed, passed + failed])
	get_tree().quit(1 if failed else 0)

func _test_rear_snow(shape: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.size = shape
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var effect := Effect.new()
	viewport.add_child(effect)
	effect.setup()
	effect.setup()
	effect.finish_warmup()
	var nodes := effect.get_children()
	var front_texture := effect._rear_front.texture
	var material := effect._effect_material
	_check(nodes.size() == 3 and effect.layer == 0, "one screen pass/two quads below HUD %s" % shape)
	_check(not effect.visible and effect._rear_front.modulate.a == 0.0
		and effect._rear_surround.modulate.a == 0.0, "normal run has no extra visible snow %s" % shape)
	for hits_left: int in [2,1]:
		effect.lost_life(hits_left)
		_check(effect.strength == 0.0 and effect.haze_opacity == 0.0,
			"hit enters smoothly from normal %s lives%d" % [shape,hits_left])
		effect.advance(1.0,true,false,"full")
		var haze := effect.haze_opacity
		var expected_low := 0.30 if hits_left == 2 else 0.46
		var expected_high := 0.34 if hits_left == 2 else 0.50
		_check(haze >= expected_low and haze <= expected_high
			and is_equal_approx(float(material.get_shader_parameter("haze_opacity")),haze),
			"visible bounded whole-world haze reaches shader %s lives%d" % [shape,hits_left])
		_check(effect.rear_snow_alpha > (0.5 if hits_left == 2 else 0.8),
			"rear snow has readable opacity %s lives%d" % [shape,hits_left])
		_check(effect._rear_surround.texture == effect._surround_portrait if shape.y >= shape.x
			else effect._rear_surround.texture == effect._surround_desktop,
			"correct cached orientation %s lives%d" % [shape,hits_left])
		_check(effect._rear_surround.position.y >= shape.y * 0.10
			and effect._rear_surround.get_rect().end.y > shape.y
			and effect._rear_front.get_rect().end.y > shape.y,
			"rear-only banks and texture undersides stay below viewport %s lives%d" % [shape,hits_left])
		for point: Vector2 in [Vector2(0.50,0.50),Vector2(0.50,0.65),Vector2(0.50,0.72)]:
			_check(_snow_alpha(effect,point * Vector2(shape)) < 0.12,
				"authored alpha leaves central route/hero open %s lives%d point%s" % [shape,hits_left,point])
		for point: Vector2 in [Vector2(0.08,0.94),Vector2(0.92,0.94)]:
			_check(_snow_alpha(effect,point * Vector2(shape)) > 0.30,
				"painted snow visibly encroaches from rear corner %s lives%d point%s" % [shape,hits_left,point])
		effect.advance(0.0,true,true,"full")
		var static_pos := effect._rear_surround.position
		effect.advance(4.0,true,true,"full")
		_check(effect.motion_scale == 0.0 and effect._rear_surround.position == static_pos
			and float(material.get_shader_parameter("effect_clock")) == 0.0,
			"reduced motion keeps steady snow with no displacement %s lives%d" % [shape,hits_left])
		effect.advance(0.0,true,false,"off")
		_check(effect.motion_scale == 0.0 and effect.haze_opacity == haze,
			"motion off keeps readable static warning %s lives%d" % [shape,hits_left])
		effect.advance(9.0,true,false,"full")
		_check(effect.haze_opacity > 0.0 and effect.haze_opacity < haze
			and effect.rear_crest > (0.86 if hits_left == 2 else 0.82),
			"final second lowers snow and fades atmosphere together %s lives%d" % [shape,hits_left])
		effect.advance(1.0,true,false,"full")
		_check(not effect.visible and effect.haze_opacity == 0.0 and effect.rear_snow_alpha == 0.0
			and effect._rear_front.modulate.a == 0.0 and effect.rear_crest == 1.0,
			"exact15s returns complete normal image %s lives%d" % [shape,hits_left])
	for cycle: int in 20:
		effect.lost_life(1)
		effect.advance(1.0,true,false,"full")
		effect.reset()
	_check(effect.get_children() == nodes and effect._effect_material == material
		and effect._rear_front.texture == front_texture,
		"20 repeated hits/retries allocate no extra nodes/materials/textures %s" % shape)
	_check(not effect.visible and float(material.get_shader_parameter("haze_opacity")) == 0.0
		and effect._rear_surround.modulate.a == 0.0, "reset clears every presentation layer %s" % shape)
	viewport.queue_free()
	await get_tree().process_frame

func _snow_alpha(effect: Node, point: Vector2) -> float:
	var alpha := 0.0
	for quad: TextureRect in [effect._rear_surround,effect._rear_front]:
		if not quad.get_rect().has_point(point): continue
		var uv := (point - quad.position) / quad.size
		var pixels := quad.texture.get_image()
		var sampled := pixels.get_pixel(clampi(int(uv.x * pixels.get_width()),0,pixels.get_width()-1),
			clampi(int(uv.y * pixels.get_height()),0,pixels.get_height()-1)).a * quad.modulate.a
		alpha = sampled + alpha * (1.0 - sampled)
	return alpha
