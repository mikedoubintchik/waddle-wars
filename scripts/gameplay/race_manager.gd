class_name RaceManager
extends Node
## Runs a standard race: spawns racers, countdown, live positions, bounded
## rubberbanding, finish handling, and result reporting to Game.

signal countdown_tick(value: int)  # 3, 2, 1, 0 (=GO)
signal race_started
signal positions_updated(standings: Array[Racer])
signal player_finished(racer: Racer)
signal race_completed
signal message(text: String)

const FINISH_TIMEOUT: float = 18.0
const DNF_TIME_PENALTY: float = 30.0

var course: CourseBase = null
var powerups: PowerupSystem = null
var racers: Array[Racer] = []
var player: Racer = null
var race_time: float = 0.0
var started: bool = false
var finished_order: Array[Racer] = []
var single_racer_mode: bool = false  # Time Trial

## Test hook: when true the "player" racer is driven by AI (headless sims).
static var autopilot_player: bool = false

var _countdown_value: int = 4
var _countdown_timer: float = 0.0
var _position_timer: float = 0.0
var _finish_countdown: float = -1.0
var _completed: bool = false
var _final_music: bool = false
var _rng := RandomNumberGenerator.new()


func setup(p_course: CourseBase, p_powerups: PowerupSystem, time_trial: bool = false) -> void:
	course = p_course
	powerups = p_powerups
	powerups.course = course
	single_racer_mode = time_trial
	course.racer_crossed_finish.connect(_on_finish_crossed)
	_rng.randomize()
	_spawn_racers()
	_countdown_timer = 1.0
	for racer: Racer in racers:
		racer.set_physics_process(false)
	# Let visuals idle during countdown.
	set_physics_process(true)


func _spawn_racers() -> void:
	var difficulty := DifficultyDB.get_item(Game.difficulty_id)
	# Player.
	player = Racer.new()
	var equipped := Progression.equipped()
	var body_info := CosmeticsDB.get_item(String(equipped.get("body", "body_classic")))
	var config := {
		"body_color": body_info.get("body_color", Color(0.13, 0.16, 0.22)),
		"belly_color": body_info.get("belly_color", Color(0.95, 0.94, 0.9)),
		"hat": equipped.get("hat", ""),
		"scarf": equipped.get("scarf", ""),
		"goggles": equipped.get("goggles", ""),
		"trail": equipped.get("trail", ""),
	}
	if body_info.has("crest_color"):
		config["crest_color"] = body_info["crest_color"]
	var player_controller: RacerController
	if autopilot_player:
		var auto := AIController.new()
		player_controller = auto
	else:
		var human := PlayerController.new()
		human.input_enabled = false
		player_controller = human
	get_parent().add_child.call_deferred(player)
	player.setup.call_deferred("player", "You", true, config, player_controller, course)
	if autopilot_player:
		(player_controller as AIController).configure(player, course, PersonalitiesDB.get_item("gus"), difficulty, _rng.randi())
	player.item_used.connect(_on_item_used)
	player.shove_landed.connect(_on_shove_landed)
	racers.append(player)

	if not single_racer_mode:
		for i: int in PersonalitiesDB.ORDER.size():
			var key := PersonalitiesDB.ORDER[i]
			var personality := PersonalitiesDB.get_item(key)
			var ai := Racer.new()
			var ai_config := {
				"body_color": personality.get("body_color", Color(0.13, 0.16, 0.22)),
				"belly_color": personality.get("belly_color", Color(0.95, 0.94, 0.9)),
			}
			var hat := String(personality.get("hat", ""))
			if hat != "":
				var cat := String(CosmeticsDB.get_item(hat).get("category", "hat"))
				ai_config[cat if cat in ["hat", "scarf", "goggles"] else "hat"] = hat
			var controller := AIController.new()
			get_parent().add_child.call_deferred(ai)
			ai.setup.call_deferred(key, String(personality["name"]), false, ai_config, controller, course)
			ai.item_used.connect(_on_item_used)
			controller.configure(ai, course, personality, difficulty, _rng.randi())
			ai.speed_scale = float(difficulty.get("speed_scale", 0.95)) * (0.94 + 0.08 * float(personality.get("skill", 0.6)))
			racers.append(ai)

	# Place on the grid (deferred so setup has run).
	call_deferred("_place_on_grid")


func _place_on_grid() -> void:
	for i: int in racers.size():
		var racer := racers[i]
		var slot := i if not single_racer_mode else 0
		var xform := course.start_grid_transform(slot)
		racer.global_transform = xform
		var forward := -xform.basis.z
		var yaw := atan2(-forward.x, -forward.z)
		racer.rotation.y = yaw
		racer.set("_facing_yaw", yaw)
		racer.set("_velocity_yaw", yaw)
		racer.last_checkpoint_transform = xform


func _physics_process(delta: float) -> void:
	if not started:
		_countdown_timer -= delta
		if _countdown_timer <= 0.0:
			_countdown_value -= 1
			if _countdown_value > 0:
				countdown_tick.emit(_countdown_value)
				AudioManager.play_sfx("sfx_countdown", 1.0 if _countdown_value > 1 else 1.0)
				_countdown_timer = 1.0
			else:
				countdown_tick.emit(0)
				AudioManager.play_sfx("sfx_go")
				_start_race()
		return

	race_time += delta
	_position_timer -= delta
	if _position_timer <= 0.0:
		_position_timer = 0.25
		_update_positions()
		_update_rubberband()
		# Final-stretch music escalation.
		if not _final_music and player != null and is_instance_valid(player) \
				and course.finish_offset > 0.0 and player.progress > course.finish_offset * 0.78:
			_final_music = true
			AudioManager.play_music("music_final", 0.8)

	if _finish_countdown > 0.0:
		_finish_countdown -= delta
		if _finish_countdown <= 0.0:
			_complete_race()


func _start_race() -> void:
	started = true
	for racer: Racer in racers:
		racer.set_physics_process(true)
		if racer.controller is PlayerController:
			(racer.controller as PlayerController).input_enabled = true
	race_started.emit()


func _update_positions() -> void:
	var sorted := racers.duplicate()
	sorted.sort_custom(func(a: Racer, b: Racer) -> bool:
		if (a.state == Racer.State.FINISHED) != (b.state == Racer.State.FINISHED):
			return a.state == Racer.State.FINISHED
		if a.state == Racer.State.FINISHED and b.state == Racer.State.FINISHED:
			return a.finish_time < b.finish_time
		return a.total_progress > b.total_progress)
	var typed: Array[Racer] = []
	for i: int in sorted.size():
		var racer: Racer = sorted[i]
		racer.race_position = i + 1
		typed.append(racer)
	if player != null and player.race_position == racers.size() and racers.size() > 1 and started and race_time > 20.0:
		Game.was_last_place_this_race = true
	positions_updated.emit(typed)


## Bounded catch-up: AI far behind the leader gets a small speed bonus, the
## AI leader is slightly reined in when far ahead of the player. No teleports.
func _update_rubberband() -> void:
	if single_racer_mode:
		return
	var strength := float(DifficultyDB.get_item(Game.difficulty_id).get("rubberband", 0.12))
	var player_progress := player.total_progress if player != null else 0.0
	for racer: Racer in racers:
		if racer.is_player or racer.state == Racer.State.FINISHED:
			continue
		var base := float(DifficultyDB.get_item(Game.difficulty_id).get("speed_scale", 0.95))
		var personality := PersonalitiesDB.get_item(racer.racer_key)
		base *= 0.94 + 0.08 * float(personality.get("skill", 0.6))
		var gap := player_progress - racer.total_progress
		var adjust := clampf(gap / 600.0, -1.0, 1.0) * strength
		racer.speed_scale = clampf(base + adjust, 0.78, 1.14)


func _on_finish_crossed(racer: Racer) -> void:
	if racer.state == Racer.State.FINISHED:
		return
	racer.finish_race_now(race_time)
	finished_order.append(racer)
	AudioManager.play_sfx_3d("sfx_finish", racer.global_position)
	if racer.is_player:
		player_finished.emit(racer)
		message.emit("FINISH!")
		AudioManager.play_sfx("sfx_victory" if racer.race_position <= 3 else "sfx_finish")
		if _finish_countdown < 0.0:
			_finish_countdown = FINISH_TIMEOUT
	if finished_order.size() >= racers.size():
		_finish_countdown = 0.4


func _on_item_used(racer: Racer, item_id: String) -> void:
	powerups.activate(racer, item_id)


func _on_shove_landed(_attacker: Racer, _victim: Racer) -> void:
	Progression.record_shove_landed()
	var camera := get_viewport().get_camera_3d()
	if camera != null and camera.get_parent() is ChaseCamera:
		(camera.get_parent() as ChaseCamera).add_shake(0.3)


func _complete_race() -> void:
	if _completed:
		return
	_completed = true
	_update_positions()
	var results: Array[Dictionary] = []
	var sorted := racers.duplicate()
	sorted.sort_custom(func(a: Racer, b: Racer) -> bool:
		return a.race_position < b.race_position)
	var course_length := course.finish_offset
	for racer: Racer in sorted:
		var finished := racer.state == Racer.State.FINISHED
		var remaining := maxf(course_length - racer.progress, 0.0)
		# Racers still on course when the race resolves get a projected time;
		# only racers that never made real progress count as DNF.
		var dnf := not finished and remaining > course_length * 0.4
		var projected := race_time + remaining / 11.0
		results.append({
			"key": racer.racer_key,
			"name": racer.display_name,
			"is_player": racer.is_player,
			"position": racer.race_position,
			"time": racer.finish_time if finished else (projected if not dnf else race_time + DNF_TIME_PENALTY),
			"fish": racer.fish_count,
			"dnf": dnf,
		})
	race_completed.emit()
	if Game.mode == Game.Mode.TIME_TRIAL:
		Game.finish_time_trial(player.finish_time, player.fish_count)
	else:
		Game.finish_race(results)
