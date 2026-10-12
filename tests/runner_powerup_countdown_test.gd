extends Node
## Gameplay time is the only countdown clock. Covers pickup, refresh, pause,
## expiry, shield consumption and the HUD's immediate state reconciliation.

var passed := 0
var failed := 0


func _ready() -> void:
	var player := RunnerPlayer.new()
	add_child(player)
	var hud := RunnerHUD.new()
	add_child(hud)
	hud.setup()
	for id: StringName in [RunnerConfig.POWERUP_MAGNET, RunnerConfig.POWERUP_SHIELD]:
		var index := RunnerConfig.POWERUP_IDS.find(id)
		player.grant_powerup(id)
		hud.set_powerups(player.powerups)
		check(hud._powerup_on[index] and hud._powerup_slots[index].visible, "%s pickup shows countdown" % id)
		check(hud._powerup_times[index].text == "%ds" % int(RunnerConfig.POWERUP_TIME), "%s begins at full duration" % id)
		player._advance_powerups(2.25)
		hud.set_powerups(player.powerups)
		var expected := RunnerConfig.POWERUP_TIME - 2.25
		check(is_equal_approx(hud._powerup_rings[index].value, expected / RunnerConfig.POWERUP_TIME), "%s ring follows remaining gameplay time" % id)
		check(hud._powerup_times[index].text == "%ds" % int(ceil(expected)), "%s label counts remaining seconds" % id)
		# Rendering can tick while gameplay is stopped. It must not invent expiry.
		hud._tick_powerups(3.0)
		check(is_equal_approx(hud._powerup_left[index], expected), "%s pause does not spend gameplay duration" % id)
		player.grant_powerup(id)
		hud.set_powerups(player.powerups)
		check(hud._powerup_times[index].text == "%ds" % int(RunnerConfig.POWERUP_TIME) and is_equal_approx(hud._powerup_rings[index].value, 1.0), "%s repeat pickup refreshes countdown" % id)
		player._advance_powerups(RunnerConfig.POWERUP_TIME + 0.1)
		hud.set_powerups(player.powerups)
		check(not player.has_powerup(id) and not hud._powerup_on[index] and not hud._powerup_slots[index].visible, "%s expiry removes effect and chip together" % id)
	player.grant_powerup(RunnerConfig.POWERUP_SHIELD)
	hud.set_powerups(player.powerups)
	player.take_hit()
	hud.set_powerups(player.powerups)
	var shield := RunnerConfig.POWERUP_IDS.find(RunnerConfig.POWERUP_SHIELD)
	check(player.hits_left == RunnerConfig.MAX_HITS, "shield absorbs hit without spending life")
	check(not hud._powerup_on[shield] and hud._powerup_times[shield].text == "0s", "consumed shield clears countdown immediately")
	hud.set_missions([{"id": "count", "text": "Collect 60 fish", "current": 13.0, "target": 60.0, "progress": 13.0 / 60.0, "done": false}])
	hud._tick_missions(0.5)
	check(hud._mission_pcts[0].text == "13 / 60", "challenge displays actual count and goal")
	check(is_equal_approx(hud._mission_bars[0].value, 13.0 / 60.0), "challenge bar follows actual fraction")
	hud.free()
	player.free()
	await get_tree().process_frame
	print("[runner_powerup_countdown] DONE: %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)


func check(ok: bool, message: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("[runner_powerup_countdown] %s %s" % ["PASS" if ok else "FAIL", message])
