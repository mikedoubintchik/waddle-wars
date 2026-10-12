extends Node
## Headless coroutine/state proof only. Draw signals are explicitly simulated;
## actual Chrome shader identity/timing establishes the rendered compile result.

var _checks: int = 0
var _failed: int = 0


func _ready() -> void:
	for reduced: bool in [false, true]:
		for initially_visible: bool in [false, true]:
			_check_draw_and_restore(reduced, initially_visible)
	_check_headless_and_unbuilt()
	_check_detached_during_draw()
	_check_freed_rectangle()
	_check_build_order()
	print("[runner_hud_shader_warmup] %d checks, %d failures" % [_checks, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _make_hud() -> RunnerHUD:
	var hud := RunnerHUD.new()
	add_child(hud)
	hud.set_process(false)
	hud._root = Control.new()
	hud.add_child(hud._root)
	hud._root.size = Vector2(960.0, 540.0)
	hud._build_speed_lines()
	return hud


func _await_warmup(hud: RunnerHUD, state: Dictionary) -> void:
	await hud.warm_render_resources()
	state["finished"] = true


func _check_draw_and_restore(reduced: bool, initially_visible: bool) -> void:
	var hud := _make_hud()
	hud._reduced = reduced
	hud._speed_lines.visible = initially_visible
	hud._speed_material.set_shader_parameter("intensity", 0.37)
	hud._speed_material.set_shader_parameter("aspect", 1.777)
	hud._speed_material.set_shader_parameter("tint", Vector3(0.7, 0.8, 0.9))
	hud._speed_sent = 0.37
	hud._speed_ratio = 0.29
	var material := hud._speed_material
	var state := {"finished": false}
	_await_warmup(hud, state)
	_check(not state["finished"], "waits for actual draw boundary")
	_check(hud._speed_lines.visible, "real speed rectangle is submitted")
	_check(hud._speed_lines.material == material, "real material identity retained")
	_check(is_zero_approx(float(material.get_shader_parameter("intensity"))),
		"zero-intensity shader cannot show streaks during warmup")
	RenderingServer.frame_post_draw.emit()
	_check(state["finished"], "warmup completes only after draw signal")
	_check(hud._speed_lines.visible == initially_visible, "original visibility restored")
	_check(is_equal_approx(float(material.get_shader_parameter("intensity")), 0.37),
		"original intensity restored")
	_check(is_equal_approx(hud._speed_sent, 0.37) and is_equal_approx(hud._speed_ratio, 0.29),
		"gameplay uniform cache and speed ratio unchanged")
	_check(is_equal_approx(float(material.get_shader_parameter("aspect")), 1.777) \
		and material.get_shader_parameter("tint") == Vector3(0.7, 0.8, 0.9),
		"aspect and tint unchanged")
	_check(hud._reduced == reduced, "accessibility setting unchanged")
	hud.free()


func _check_headless_and_unbuilt() -> void:
	var unbuilt := RunnerHUD.new()
	add_child(unbuilt)
	unbuilt.set_process(false)
	var state := {"finished": false}
	_await_warmup(unbuilt, state)
	_check(state["finished"], "unbuilt HUD exits without waiting")
	unbuilt.free()
	var hud := _make_hud()
	hud._headless = true
	state = {"finished": false}
	_await_warmup(hud, state)
	_check(state["finished"] and not hud._speed_lines.visible,
		"headless HUD exits without changing visibility")
	hud.free()


func _check_detached_during_draw() -> void:
	var hud := _make_hud()
	var original_intensity: Variant = hud._speed_material.get_shader_parameter("intensity")
	var state := {"finished": false}
	_await_warmup(hud, state)
	remove_child(hud)
	RenderingServer.frame_post_draw.emit()
	_check(state["finished"] and not hud._speed_lines.visible,
		"detached surviving HUD restores original visibility")
	_check(hud._speed_material.get_shader_parameter("intensity") == original_intensity,
		"shader's original default override state restored, including null")
	hud.free()


func _check_freed_rectangle() -> void:
	var hud := _make_hud()
	var state := {"finished": false}
	_await_warmup(hud, state)
	hud._speed_lines.free()
	RenderingServer.frame_post_draw.emit()
	_check(state["finished"], "freed rectangle does not cause invalid access")
	hud.free()


func _check_build_order() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/runner/runner_game.gd")
	var submission := source.find("await hud.warm_render_resources()")
	var completion := source.find("\tbuild_finished = true\n")
	var subsequent := source.find("\t_startup_warmup = ShaderWarmup.warm(self, {}, RunnerTrack.SHADER_WARMUP_SCOPE)")
	_check(submission >= 0 and completion > submission and subsequent > completion,
		"runner cannot release countdown before HUD warmup")
	_check(source.contains("await hud.warm_render_resources()\n\t\tawait _stage()"),
		"subsequent warmup begins outside the completed draw callback")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failed += 1
		push_error("[runner_hud_shader_warmup] " + message)
