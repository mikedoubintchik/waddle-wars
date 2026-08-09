extends Node
## Global game-flow context: selected mode/course/difficulty, Grand Prix
## state, and race-result handoff between gameplay and menu scenes.

enum Mode { QUICK_RACE, GRAND_PRIX, ENDLESS, TIME_TRIAL, TUTORIAL }

const SCENE_TITLE: String = "res://scenes/ui/title.tscn"
const SCENE_MAIN_MENU: String = "res://scenes/menus/main_menu.tscn"
const SCENE_MODE_SELECT: String = "res://scenes/menus/mode_select.tscn"
const SCENE_RACE: String = "res://scenes/gameplay/race.tscn"
const SCENE_RESULTS: String = "res://scenes/menus/results.tscn"
const SCENE_CUSTOMIZE: String = "res://scenes/menus/customize.tscn"
const SCENE_ACHIEVEMENTS: String = "res://scenes/menus/achievements.tscn"
const SCENE_LEADERBOARD: String = "res://scenes/menus/leaderboard.tscn"
const SCENE_SETTINGS: String = "res://scenes/menus/settings.tscn"
const SCENE_CREDITS: String = "res://scenes/menus/credits.tscn"

const GP_POINTS: PackedInt32Array = [10, 8, 6, 5, 4, 3, 2, 1]

var mode: Mode = Mode.QUICK_RACE
var course_id: String = "glacier"
var difficulty_id: String = "competitive"

## Grand Prix state.
var gp_round: int = 0
var gp_points: Dictionary = {}  # racer_key ("player" or personality id) -> points
var gp_times: Dictionary = {}  # racer_key -> accumulated race seconds (standings tiebreak)

## Result handoff. Race scene fills this, results scene reads it.
## Array of {key, name, is_player, position, time, fish, dnf}
var last_race_results: Array[Dictionary] = []
var last_endless_result: Dictionary = {}
var last_rewards: Dictionary = {}
## True while the current race is today's daily challenge. Cleared as soon as
## the result is recorded, so a rematch from the results screen is an ordinary
## race and cannot pay the daily reward twice.
var daily_active: bool = false
## What the last daily completion earned, for the results screen to show:
## {"first_today", "improved", "streak", "fish"}. Empty when the last race was
## not a daily.
var daily_result: Dictionary = {}
var used_item_this_race: bool = false
var was_last_place_this_race: bool = false


func start_quick_race(p_course: String, p_difficulty: String) -> void:
	mode = Mode.QUICK_RACE
	course_id = p_course
	difficulty_id = p_difficulty
	SceneRouter.go_to(SCENE_RACE)


## Today's daily challenge: a fixed course and field that everyone racing today
## gets, so times are directly comparable. Runs as a normal quick race and is
## tracked by `daily_active` rather than its own Mode, so nothing in the race,
## HUD or results pipeline has to learn a new case.
func start_daily_challenge() -> void:
	var challenge := DailyChallenge.for_day()
	daily_active = true
	daily_result = {}
	mode = Mode.QUICK_RACE
	course_id = String(challenge["course"])
	difficulty_id = String(challenge["difficulty"])
	SceneRouter.go_to(SCENE_RACE)


func start_grand_prix(p_difficulty: String) -> void:
	mode = Mode.GRAND_PRIX
	difficulty_id = p_difficulty
	gp_round = 0
	gp_points = {}
	gp_times = {}
	course_id = CoursesDB.GRAND_PRIX_ORDER[0]
	SceneRouter.go_to(SCENE_RACE)


func advance_grand_prix() -> bool:
	# Double-click guard: go_to drops calls while transitioning, but gp_round
	# must not increment for a dropped call or a fast second press skips a round.
	if SceneRouter.is_busy():
		return true
	gp_round += 1
	if gp_round >= CoursesDB.GRAND_PRIX_ORDER.size():
		return false
	course_id = CoursesDB.GRAND_PRIX_ORDER[gp_round]
	SceneRouter.go_to(SCENE_RACE)
	return true


func is_final_gp_round() -> bool:
	return gp_round >= CoursesDB.GRAND_PRIX_ORDER.size() - 1


func start_endless() -> void:
	mode = Mode.ENDLESS
	course_id = "endless"
	SceneRouter.go_to(SCENE_RACE)


func start_time_trial(p_course: String) -> void:
	mode = Mode.TIME_TRIAL
	course_id = p_course
	SceneRouter.go_to(SCENE_RACE)


func start_tutorial() -> void:
	mode = Mode.TUTORIAL
	course_id = "tutorial"
	SceneRouter.go_to(SCENE_RACE)


func gp_standings() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for key: Variant in gp_points.keys():
		var display := "You" if key == "player" else String(PersonalitiesDB.get_item(key).get("name", key))
		rows.append({
			"key": key, "name": display, "points": int(gp_points[key]),
			"time": float(gp_times.get(key, 0.0)),
		})
	# sort_custom is unstable; break points ties by total race time, then name.
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["points"]) != int(b["points"]):
			return int(a["points"]) > int(b["points"])
		if float(a["time"]) != float(b["time"]):
			return float(a["time"]) < float(b["time"])
		return String(a["name"]) < String(b["name"]))
	return rows


## Called by the race scene when a standard race completes.
func finish_race(results: Array[Dictionary]) -> void:
	last_race_results = results
	var player_row: Dictionary = {}
	for row: Dictionary in results:
		if bool(row.get("is_player", false)):
			player_row = row
			break

	if mode == Mode.GRAND_PRIX:
		for row: Dictionary in results:
			var key := String(row.get("key", ""))
			var pos := int(row.get("position", 8))
			var pts := GP_POINTS[clampi(pos - 1, 0, GP_POINTS.size() - 1)]
			gp_points[key] = int(gp_points.get(key, 0)) + pts
			gp_times[key] = float(gp_times.get(key, 0.0)) + float(row.get("time", 0.0))

	if daily_active:
		daily_active = false
		# Only a finish counts. A DNF leaves the streak alone rather than
		# spending it, so a bad run costs the day's reward and nothing more.
		if not bool(player_row.get("dnf", false)) and float(player_row.get("time", 0.0)) > 0.0:
			daily_result = DailyChallenge.record_completion(float(player_row["time"]))

	_grant_race_rewards(player_row)
	SceneRouter.go_to(SCENE_RESULTS)


func finish_endless(score: int, distance: float, fish: int) -> void:
	var is_record := Progression.submit_endless_score(score, distance)
	last_endless_result = {
		"score": score, "distance": distance, "fish": fish, "is_record": is_record,
	}
	var fish_reward := fish + score / 100
	Progression.add_fish(fish_reward)
	Progression.add_xp(50 + score / 50)
	Progression.increment_stat("races_finished")
	last_rewards = {"fish": fish_reward, "xp": 50 + score / 50, "unlocks": []}
	SceneRouter.go_to(SCENE_RESULTS)


func finish_time_trial(time_seconds: float, fish: int) -> void:
	var is_record := Progression.submit_time(course_id, time_seconds)
	last_race_results = [{
		"key": "player", "name": "You", "is_player": true, "position": 1,
		"time": time_seconds, "fish": fish, "dnf": false, "is_record": is_record,
	}]
	Progression.add_fish(fish)
	Progression.add_xp(40)
	last_rewards = {"fish": fish, "xp": 40, "unlocks": [], "is_record": is_record}
	SceneRouter.go_to(SCENE_RESULTS)


func finish_tutorial() -> void:
	Progression.complete_tutorial()
	Progression.add_fish(50)
	last_rewards = {"fish": 50, "xp": 100, "unlocks": []}
	Progression.add_xp(100)
	SceneRouter.go_to(SCENE_RESULTS)


func quit_race_to_menu() -> void:
	# Abandoning mid-race must not leave the next ordinary race flagged daily.
	daily_active = false
	SceneRouter.go_to(SCENE_MAIN_MENU)


## Which step the setup flow opens on: "mode", "course" or "difficulty".
## Consumed and reset by mode_select, so it only ever affects the next entry.
##
## Exists so somewhere other than the top of the flow can send a player back
## into it. Wanting a different course used to mean quitting to the main menu
## and walking the whole flow again, with the mode and difficulty re-picked on
## the way past.
var setup_entry_step: String = "mode"


## Leaves a race for the setup flow, at whatever step setup_entry_step names.
func quit_race_to_setup() -> void:
	daily_active = false
	SceneRouter.go_to(SCENE_MODE_SELECT)


## Reads and clears the pending entry step.
func take_setup_entry_step() -> String:
	var step := setup_entry_step
	setup_entry_step = "mode"
	return step


func _grant_race_rewards(player_row: Dictionary) -> void:
	var position := int(player_row.get("position", 8))
	var fish_collected := int(player_row.get("fish", 0))
	var placement_bonus: int = [60, 45, 35, 25, 18, 12, 8, 5][clampi(position - 1, 0, 7)]
	var fish_reward := fish_collected + placement_bonus
	var xp_reward := 40 + (9 - position) * 15
	Progression.add_fish(fish_reward)
	Progression.add_xp(xp_reward)
	Progression.increment_stat("races_finished")
	last_rewards = {"fish": fish_reward, "xp": xp_reward, "unlocks": []}

	if position == 1:
		Progression.increment_stat("races_won")
		if mode == Mode.QUICK_RACE:
			Progression.unlock_achievement("first_win")
		match course_id:
			"glacier":
				Progression.unlock_achievement("glacier_champ")
			"aurora":
				Progression.unlock_achievement("aurora_champ")
			"iceberg":
				Progression.unlock_achievement("iceberg_champ")
		if not used_item_this_race:
			Progression.unlock_achievement("purist")
		if was_last_place_this_race:
			Progression.unlock_achievement("comeback")
