extends Node
## Exercise the real HUD tweens with a deterministic presentation clock. A
## mission banner needs its reading interval before fade/hide, and replacing
## one must cancel its old exit. No window, player save, or gameplay clock used.

var _passes: int = 0
var _failures: int = 0


func _ready() -> void:
	var hud := RunnerHUD.new()
	add_child(hud)
	hud.setup()
	# Headless layout builds the same nodes. Enable only their real tween path;
	# custom_step drives it without a render or wall-time wait.
	hud._headless = false
	hud._reduced = false
	hud.show_mission_complete("Collect 60 fish")
	var normal := hud._banner_tween
	_check("normal_enters_visible_and_transparent", hud._banner.visible
		and is_zero_approx(hud._banner.modulate.a))
	normal.custom_step(0.24)
	_check("normal_entry_reaches_readable_alpha", hud._banner.visible
		and is_equal_approx(hud._banner.modulate.a, 1.0))
	normal.custom_step(0.31)
	_check("normal_still_visible_after_entry_at_055", hud._banner.visible
		and is_equal_approx(hud._banner.modulate.a, 1.0))
	normal.custom_step(1.50)
	_check("normal_holds_text_through_205", hud._banner.visible
		and is_equal_approx(hud._banner.modulate.a, 1.0))
	normal.custom_step(0.23)
	_check("normal_fades_before_hiding", hud._banner.visible
		and hud._banner.modulate.a > 0.0 and hud._banner.modulate.a < 1.0)
	normal.custom_step(0.30)
	_check("normal_hides_after_fade", not hud._banner.visible
		and is_zero_approx(hud._banner.modulate.a))

	hud.show_mission_complete("Run 500 m")
	var replaced := hud._banner_tween
	replaced.custom_step(0.55)
	hud.show_mission_complete("Collect 30 fish")
	var replacement := hud._banner_tween
	_check("replacement_cancels_previous_exit", not replaced.is_valid()
		and replacement != replaced and hud._banner_title.text == "Collect 30 fish")
	replacement.custom_step(0.55)
	_check("replacement_gets_its_own_reading_interval", hud._banner.visible
		and is_equal_approx(hud._banner.modulate.a, 1.0))
	replacement.custom_step(2.05)
	_check("replacement_eventually_hides", not hud._banner.visible)

	hud._reduced = true
	hud.show_mission_complete("Collect 60 fish")
	var reduced := hud._banner_tween
	_check("reduced_starts_readable_without_scale_motion", hud._banner.visible
		and is_equal_approx(hud._banner.modulate.a, 1.0) and hud._banner.scale == Vector2.ONE)
	reduced.custom_step(1.60)
	_check("reduced_holds_readable_text", hud._banner.visible
		and is_equal_approx(hud._banner.modulate.a, 1.0) and hud._banner.scale == Vector2.ONE)
	reduced.custom_step(0.30)
	_check("reduced_fades_before_hiding", hud._banner.visible
		and hud._banner.modulate.a > 0.0 and hud._banner.modulate.a < 1.0
		and hud._banner.scale == Vector2.ONE)
	reduced.custom_step(0.40)
	_check("reduced_hides_after_fade", not hud._banner.visible
		and is_zero_approx(hud._banner.modulate.a))
	hud.queue_free()
	await get_tree().process_frame
	print("[runner_banner_timing] DONE: %d passed, %d failed" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _check(label: String, passed: bool) -> void:
	if passed:
		_passes += 1
	else:
		_failures += 1
	print("[runner_banner_timing] %s %s" % ["PASS" if passed else "FAIL", label])
