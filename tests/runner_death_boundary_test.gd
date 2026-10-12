extends Node
## Death must finish the current gameplay tick while preserving its visible
## presentation. Ordered contacts reproduce a fatal obstacle followed by loot
## and a ramp; only the contact inventory is synthetic.

class ContactPlayer:
	extends RunnerPlayer

	var contacts: Array[Area3D] = []
	var magnet_ticks: int = 0
	var near_miss_ticks: int = 0

	func _overlapping_areas() -> Array[Area3D]:
		return contacts

	func _advance_magnet(_delta: float) -> void:
		magnet_ticks += 1

	func _scan_near_miss(_delta: float) -> void:
		near_miss_ticks += 1


class FishContact:
	extends Area3D
	var collections: int = 0
	func collect() -> int:
		collections += 1
		return 1


class PowerContact:
	extends Area3D
	var collections: int = 0
	func collect() -> StringName:
		collections += 1
		return RunnerConfig.POWERUP_SHIELD


var _passes: int = 0
var _failures: int = 0


func _ready() -> void:
	var access: Dictionary = SettingsManager.settings.get("accessibility", {})
	var original: Variant = access.get("reduced_flashing", false)
	for reduced: bool in [false, true]:
		access["reduced_flashing"] = reduced
		_test_fatal_contacts(reduced)
	access["reduced_flashing"] = original
	await get_tree().process_frame
	print("[runner_death_boundary] DONE: %d passed, %d failed" % [_passes, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _test_fatal_contacts(reduced: bool) -> void:
	var label := "reduced" if reduced else "normal"
	var fixture := Node3D.new()
	add_child(fixture)
	var player := ContactPlayer.new()
	fixture.add_child(player)
	player.setup({})
	player.set_input_enabled(false)
	# Headless setup omits GPU cosmetics; install only the real emitter node
	# to verify its shutdown property without claiming particle raster output.
	player._cosmetic_trail = TrailEffect.new()
	player.add_child(player._cosmetic_trail)
	player._cosmetic_trail.emitting = true
	# Preserve surviving-hit feedback at the exact phase frozen by a fatal hit.
	player.invulnerable_for = RunnerConfig.HIT_IFRAMES
	player._drive_visual(0.0)
	_check(label + "_surviving_hit_feedback", player._visual.visible == reduced)
	player.invulnerable_for = 0.0
	player.hits_left = 1
	var block := Area3D.new()
	fixture.add_child(block)
	block.add_to_group(RunnerConfig.GROUP_HAZARD)
	var fish := FishContact.new()
	fixture.add_child(fish)
	fish.add_to_group(RunnerConfig.GROUP_PICKUP)
	var power := PowerContact.new()
	fixture.add_child(power)
	power.add_to_group(RunnerConfig.GROUP_POWERUP)
	var ramp := Area3D.new()
	fixture.add_child(ramp)
	ramp.add_to_group(RunnerConfig.GROUP_HAZARD)
	ramp.set_meta("kind", "ramp")
	player.contacts.assign([block, fish, power, ramp])
	var signals := {"deaths": 0, "fish": 0, "power": 0, "ramps": 0}
	player.died.connect(func() -> void: signals["deaths"] += 1)
	player.fish_collected.connect(func(_value: int) -> void: signals["fish"] += 1)
	player.powerup_gained.connect(func(_id: StringName) -> void: signals["power"] += 1)
	player.ramp_launched.connect(func() -> void: signals["ramps"] += 1)
	player.tick(0.01, RunnerConfig.START_SPEED)
	_check(label + "_lethal_hit_stays_dead", player.hits_left == 0
		and player.state == RunnerPlayer.State.DEAD and signals["deaths"] == 1)
	_check(label + "_later_contacts_remain_uncollected", fish.collections == 0
		and power.collections == 0 and player.powerups.is_empty())
	_check(label + "_no_rewards_after_death", signals["fish"] == 0
		and signals["power"] == 0 and signals["ramps"] == 0)
	_check(label + "_tick_stops_gameplay_after_death", player.magnet_ticks == 0
		and player.near_miss_ticks == 0)
	_check(label + "_fatal_hit_hero_visible", player._visual.visible)
	_check(label + "_fatal_hit_stops_cosmetic_emission", not player._cosmetic_trail.emitting)
	var distance_at_death := player.distance
	var visible_through_catch := true
	for frame: int in ceili(RunnerGame.CATCH_TIME / 0.05) + 1:
		player.tick(0.05, RunnerConfig.START_SPEED)
		visible_through_catch = visible_through_catch and player._visual.visible
	_check(label + "_hero_stays_visible_through_catch", visible_through_catch)
	_check(label + "_catch_preserves_gameplay_boundary", player.state == RunnerPlayer.State.DEAD
		and is_equal_approx(player.distance, distance_at_death) and signals["deaths"] == 1
		and player.magnet_ticks == 0 and player.near_miss_ticks == 0)
	fixture.queue_free()


func _check(label: String, passed: bool) -> void:
	if passed:
		_passes += 1
	else:
		_failures += 1
	print("[runner_death_boundary] %s %s" % ["PASS" if passed else "FAIL", label])
