class_name RunnerMissions
extends RefCounted
## Three persistent goals. New players start with plain cumulative distance,
## fish and jumps; later boards introduce at most one single-run challenge.
## Completed goals award immediately. A finished board stays visible through
## Results, and its replacement starts at the next run, never mid-run.
## "In total" goals carry across runs, quits and sessions. "In one run" goals
## reset at the next countdown unless already completed. Saved active targets
## and earned progress survive calibration changes.
##
## Ownership: this object draws nothing and touches no node. RunnerGame feeds
## it through the note_* calls and reads it back through rows(); everything it
## keeps goes through SaveManager, exactly like Progression.

## One mission finished. Carries the text the player was reading, so the banner
## can name what they just did rather than a generic "mission complete".
signal completed(mission_text: String)
## All three finished: a star was earned. The next set starts next run.
signal set_cleared(star_count: int)

## --- Save keys --------------------------------------------------------------
## Top-level keys alongside Progression's, not nested under "stats": these are
## live state rather than a tally, and SaveManager's defaults merge leaves
## unknown top-level keys untouched, so no change to default_save() is needed.
const SAVE_KEY_SET: String = "runner_missions"
const SAVE_KEY_STARS: String = "runner_mission_stars"
const SAVE_KEY_CHANNELS: String = "runner_mission_channels"
const SAVE_KEY_NEXT_SET: String = "runner_missions_next_run"
const SAVE_KEY_PACING: String = "runner_progression_pacing_version"
const PACING_VERSION: int = 2
const PREVIOUS_BIOME_LENGTH: float = 600.0

const SET_SIZE: int = 3

## --- Difficulty -------------------------------------------------------------
## Four rungs per mission. The set is drawn at the rung the player's stars have
## earned, so mission three of the game is not "collect 600 fish" and mission
## three hundred is not "jump 8 times".
const TIER_COUNT: int = 4
const STARS_PER_TIER: int = 8

## --- Star reward ------------------------------------------------------------
## A star has to buy something or it is a sticker. Fish grow slightly with the
## star count and then cap, so a long-running player is rewarded without the
## mission board turning into the only sane way to earn.
const STAR_FISH: int = 25
const STAR_FISH_PER_STAR: int = 5
const STAR_FISH_CAP: int = 120
const STAR_XP: int = 120

## Metres of running between background writes of cumulative progress. Writing
## every frame would rebuild the save dictionary sixty times a second; writing
## only at death would lose a whole run's cumulative progress to a mid-run quit
## to the main menu. Thirty metres is around a second of running at speed, so
## in-memory mission snapshot is refreshed this often. Disk durability still
## follows SaveManager autosave/close, plus synchronous completion/end writes.
const PERSIST_EVERY_METRES: float = 30.0

## --- Channels ---------------------------------------------------------------
## A channel is a note_* feed. A mission is only ever drawn on a channel that
## has been PROVEN to fire, because a mission nobody can make progress on locks
## the whole set forever — the set only rerolls when all three are done. The
## distance/fish/clean/jump core channels have tested RunnerGame wiring;
## every other channel proves itself the first time its
## note_* call arrives and is then remembered in the save. Wiring a new call up
## in RunnerGame therefore widens the pool on its own, and forgetting to wire
## one costs variety instead of breaking the mode.
const CH_DISTANCE: String = "distance"
const CH_FISH: String = "fish"
const CH_CLEAN: String = "clean"
const CH_JUMP: String = "jump"
const CH_SLIDE: String = "slide"
const CH_LANE: String = "lane"
const CH_NEAR_MISS: String = "near_miss"
const CH_POWERUP: String = "powerup"
const CH_RAMP: String = "ramp"
const CORE_CHANNELS: PackedStringArray = [CH_DISTANCE, CH_FISH, CH_CLEAN, CH_JUMP]

## What a mission counts. Kept as an int on the mission slot so the 60 fps path
## branches on an integer instead of comparing strings.
enum Kind {
	DISTANCE_RUN,
	DISTANCE_TOTAL,
	CLEAN_RUN,
	MULTIPLIER_RUN,
	FISH_TOTAL,
	FISH_RUN,
	JUMP_TOTAL,
	JUMP_RUN,
	SLIDE_TOTAL,
	SLIDE_RUN,
	LANE_TOTAL,
	LANE_RUN,
	NEAR_MISS_TOTAL,
	NEAR_MISS_RUN,
	POWERUP_TOTAL,
	POWERUP_RUN,
	POWERUP_SPECIFIC,
	RAMP_TOTAL,
	RAMP_RUN,
}

## The pool. Every entry states its channel, whether it is per-run, whether a
## hit wipes it, and four target rungs. `per_run` is not cosmetic: it decides
## both the reset behaviour and the "in one run" wording, and the two must never
## disagree, so they are read from the same field.
const TEMPLATES: Array[Dictionary] = [
	{
		"id": "dist_run", "kind": Kind.DISTANCE_RUN, "channel": CH_DISTANCE,
		"per_run": true, "resets_on_hit": false,
		"format": "Run %s m in one run",
		"tiers": [1500, 2400, 3200, 4500],
	},
	{
		"id": "dist_total", "kind": Kind.DISTANCE_TOTAL, "channel": CH_DISTANCE,
		"per_run": false, "resets_on_hit": false,
		"format": "Run %s m in total",
		"tiers": [8000, 12000, 18000, 24000],
	},
	{
		# The only mission that visibly falls back when the player is hit, which
		# is the point: it turns the last stretch into something to protect.
		"id": "clean_run", "kind": Kind.CLEAN_RUN, "channel": CH_CLEAN,
		"per_run": true, "resets_on_hit": true,
		"format": "Dodge everything for %s m in one run",
		"tiers": [800, 1200, 1800, 2500],
	},
	{
		# A tally rather than a streak: metres banked at a high multiplier stay
		# banked, so a hit costs the rate, not the work already done.
		"id": "multi_run", "kind": Kind.MULTIPLIER_RUN, "channel": CH_CLEAN,
		"per_run": true, "resets_on_hit": false,
		"format": "Run %s m at x%d or better in one run",
		"tiers": [600, 900, 1200, 1600], "tier_mults": [2, 2, 3, 4],
	},
	{
		"id": "fish_total", "kind": Kind.FISH_TOTAL, "channel": CH_FISH,
		"per_run": false, "resets_on_hit": false,
		"format": "Collect %s fish in total",
		"tiers": [300, 500, 750, 1000],
	},
	{
		"id": "fish_run", "kind": Kind.FISH_RUN, "channel": CH_FISH,
		"per_run": true, "resets_on_hit": false,
		"format": "Collect %s fish in one run",
		"tiers": [80, 120, 180, 240],
	},
	{
		"id": "jump_total", "kind": Kind.JUMP_TOTAL, "channel": CH_JUMP,
		"per_run": false, "resets_on_hit": false,
		"format": "Jump %s times in total",
		"tiers": [40, 60, 80, 100],
	},
	{
		"id": "jump_run", "kind": Kind.JUMP_RUN, "channel": CH_JUMP,
		"per_run": true, "resets_on_hit": false,
		"format": "Jump %s times in one run",
		"tiers": [10, 15, 20, 25],
	},
	{
		"id": "slide_total", "kind": Kind.SLIDE_TOTAL, "channel": CH_SLIDE,
		"per_run": false, "resets_on_hit": false,
		"format": "Slide %s times in total",
		"tiers": [30, 45, 60, 80],
	},
	{
		"id": "slide_run", "kind": Kind.SLIDE_RUN, "channel": CH_SLIDE,
		"per_run": true, "resets_on_hit": false,
		"format": "Slide %s times in one run",
		"tiers": [8, 12, 16, 20],
	},
	{
		"id": "lane_total", "kind": Kind.LANE_TOTAL, "channel": CH_LANE,
		"per_run": false, "resets_on_hit": false,
		"format": "Change lanes %s times in total",
		"tiers": [80, 120, 170, 220],
	},
	{
		"id": "lane_run", "kind": Kind.LANE_RUN, "channel": CH_LANE,
		"per_run": true, "resets_on_hit": false,
		"format": "Change lanes %s times in one run",
		"tiers": [25, 40, 55, 70],
	},
	{
		"id": "near_total", "kind": Kind.NEAR_MISS_TOTAL, "channel": CH_NEAR_MISS,
		"per_run": false, "resets_on_hit": false,
		"format": "Pass close to %s hazards in total",
		"tiers": [10, 15, 20, 25],
	},
	{
		"id": "near_run", "kind": Kind.NEAR_MISS_RUN, "channel": CH_NEAR_MISS,
		"per_run": true, "resets_on_hit": false,
		"format": "Squeeze past %s hazards in one run",
		"tiers": [2, 3, 4, 5],
	},
	{
		"id": "power_total", "kind": Kind.POWERUP_TOTAL, "channel": CH_POWERUP,
		"per_run": false, "resets_on_hit": false,
		"format": "Collect %s power-ups in total",
		"tiers": [8, 12, 15, 18],
	},
	{
		"id": "power_run", "kind": Kind.POWERUP_RUN, "channel": CH_POWERUP,
		"per_run": true, "resets_on_hit": false,
		"format": "Use %s power-ups in one run",
		"tiers": [2, 3, 4, 5],
	},
	{
		# Names one crate, which sends the player after a specific pickup
		# instead of hoovering whatever appears.
		"id": "power_specific", "kind": Kind.POWERUP_SPECIFIC, "channel": CH_POWERUP,
		"per_run": false, "resets_on_hit": false,
		"format": "Use %s %s times",
		"tiers": [3, 4, 5, 6],
	},
	{
		"id": "ramp_total", "kind": Kind.RAMP_TOTAL, "channel": CH_RAMP,
		"per_run": false, "resets_on_hit": false,
		"format": "Use %s ramps in total",
		"tiers": [8, 12, 15, 18],
	},
	{
		"id": "ramp_run", "kind": Kind.RAMP_RUN, "channel": CH_RAMP,
		"per_run": true, "resets_on_hit": false,
		"format": "Launch off %s ramps in one run",
		"tiers": [2, 3, 4, 5],
	},
]

## --- Live set ---------------------------------------------------------------
## Split into parallel packed arrays rather than three dictionaries because
## note_distance walks this every frame; the dictionary form is rebuilt only
## when the set is written to the save.
var _ids := PackedStringArray()
var _texts := PackedStringArray()
var _kind := PackedInt32Array()
var _target := PackedFloat32Array()
var _progress := PackedFloat32Array()
var _mult := PackedInt32Array()
var _param := PackedStringArray()
var _done := PackedByteArray()
var _per_run := PackedByteArray()
var _resets_on_hit := PackedByteArray()
## Announced separately from done: a set loaded half-finished must not fire the
## celebration again for missions the player cleared in a previous session.
var _announced := PackedByteArray()

var _stars: int = 0
var _channels := PackedStringArray()
var _next_set_pending := false
var _completed_run := PackedStringArray()

## --- Run state --------------------------------------------------------------
## Total metres last reported, which is also the delta baseline.
var _last_distance: float = 0.0
## Distance the current clean streak started at. note_hit moves it forward,
## which is what makes both the streak mission and the multiplier fall back.
var _clean_base: float = 0.0
var _persist_distance: float = 0.0
## True while any live mission cares about distance, so a set of three
## fish/jump missions costs a single bool test per frame instead of a walk.
var _watch_distance: bool = false
var _pending: bool = false
## `note_run_ended()` can enter `_resolve()` through both its defensive distance
## replay and its final fish replay. Keep mission-clear durability everywhere
## else, but coalesce those nested writes into the run-end transaction's one
## final flush.
var _flush_suppression_depth: int = 0

var _rng := RandomNumberGenerator.new()
## Returned by rows() and mutated in place, so a HUD that polls every frame
## does not allocate three dictionaries and an array each time.
var _rows: Array = []


func _init() -> void:
	_rng.randomize()
	_ids.resize(SET_SIZE)
	_texts.resize(SET_SIZE)
	_kind.resize(SET_SIZE)
	_target.resize(SET_SIZE)
	_progress.resize(SET_SIZE)
	_mult.resize(SET_SIZE)
	_param.resize(SET_SIZE)
	_done.resize(SET_SIZE)
	_per_run.resize(SET_SIZE)
	_resets_on_hit.resize(SET_SIZE)
	_announced.resize(SET_SIZE)
	for i in SET_SIZE:
		_target[i] = 1.0
		_rows.append({"id": "", "text": "", "progress": 0.0, "done": false})


## --- Lifecycle --------------------------------------------------------------

## Restores the live set and star count, drawing a fresh set when the save has
## none or holds something this build no longer understands.
func load_state(persist_after: bool = true) -> void:
	_migrate_pacing()
	_stars = maxi(int(SaveManager.get_value(SAVE_KEY_STARS, 0)), 0)
	_channels = _read_channels()
	var stored: Variant = SaveManager.get_value(SAVE_KEY_SET, null)
	if not (stored is Array and (stored as Array).size() == SET_SIZE and _adopt(stored)):
		_roll_set()
	_next_set_pending = true
	for done: int in _done:
		if done == 0:
			_next_set_pending = false
			break
	_refresh_watch()
	if persist_after:
		_persist()


## Called when a run actually starts, including every retry. Per-run missions
## start from zero here; cumulative ones are untouched.
func begin_run() -> void:
	_completed_run.clear()
	if _next_set_pending:
		_roll_set()
	_last_distance = 0.0
	_clean_base = 0.0
	_persist_distance = 0.0
	for i in SET_SIZE:
		if _per_run[i] == 1 and _done[i] == 0:
			_progress[i] = 0.0
	_refresh_watch()
	_persist()


## --- Feeds ------------------------------------------------------------------

## Total metres run so far this run. This is the only note_* that runs at frame
## rate, so it early-outs before doing anything a set without distance missions
## would not use.
func note_distance(total_metres: float) -> void:
	var gained := total_metres - _last_distance
	if gained <= 0.0:
		# A retry hands back a smaller total. Re-baseline rather than crediting
		# a phantom sprint or subtracting the previous run.
		_last_distance = total_metres
		_clean_base = minf(_clean_base, total_metres)
		_persist_distance = minf(_persist_distance, total_metres)
		return
	_last_distance = total_metres
	if _watch_distance:
		var clean := total_metres - _clean_base
		# The base multiplier, deliberately without the Double Points doubling
		# RunnerGame applies to scoring: the mission asks for clean running, not
		# for holding a crate at the right moment.
		for i in SET_SIZE:
			if _done[i] == 1:
				continue
			match _kind[i]:
				Kind.DISTANCE_RUN:
					_add_progress(i, gained)
				Kind.DISTANCE_TOTAL:
					_add_progress(i, gained)
				Kind.CLEAN_RUN:
					_add_progress(i, gained)
				Kind.MULTIPLIER_RUN:
					var threshold := float(_mult[i] - 1) * RunnerConfig.MULTIPLIER_STEP_METRES
					# Credit only the portion after crossing the required multiplier.
					_add_progress(i, clampf(clean - threshold, 0.0, gained))
		_resolve()
	if total_metres - _persist_distance >= PERSIST_EVERY_METRES:
		_persist()


## Fish just picked up, as an amount rather than a running total.
func note_fish(count: int) -> void:
	if count <= 0:
		return
	_count(Kind.FISH_TOTAL, Kind.FISH_RUN, float(count))


func note_powerup(id: StringName) -> void:
	_prove(CH_POWERUP)
	var name := String(id)
	for i in SET_SIZE:
		if _done[i] == 0 and _kind[i] == Kind.POWERUP_SPECIFIC and _param[i] == name:
			_add_progress(i, 1.0)
	_count(Kind.POWERUP_TOTAL, Kind.POWERUP_RUN, 1.0)


func note_jump() -> void:
	_prove(CH_JUMP)
	_count(Kind.JUMP_TOTAL, Kind.JUMP_RUN, 1.0)


func note_slide() -> void:
	_prove(CH_SLIDE)
	_count(Kind.SLIDE_TOTAL, Kind.SLIDE_RUN, 1.0)


func note_lane_change() -> void:
	_prove(CH_LANE)
	_count(Kind.LANE_TOTAL, Kind.LANE_RUN, 1.0)


func note_near_miss() -> void:
	_prove(CH_NEAR_MISS)
	_count(Kind.NEAR_MISS_TOTAL, Kind.NEAR_MISS_RUN, 1.0)


## A ramp launch. Ramp missions stay out of the pool until this has been called
## at least once on this save, so the set can never stall on a verb the track
## is not reporting.
func note_ramp() -> void:
	_prove(CH_RAMP)
	_count(Kind.RAMP_TOTAL, Kind.RAMP_RUN, 1.0)


## The player was hit: streak missions fall back to zero and the multiplier
## baseline moves up to here, mirroring RunnerGame's own clean_metres reset.
func note_hit() -> void:
	_clean_base = _last_distance
	for i in SET_SIZE:
		if _done[i] == 0 and _resets_on_hit[i] == 1:
			_progress[i] = 0.0
	_persist()


## End of a run. Final distance is reconciled; pickup feeds are authoritative
## deltas, so a newly assigned mission cannot inherit earlier fish. Then
## everything is flushed to disk rather than left to the autosave tick, because
## the player may go straight to the menu and close the tab. RunnerGame passes
## `false` so it can first bank score/fish and build the result, then synchronously
## flush the complete end state once. Existing standalone callers keep the
## durable default.
## `_score` is accepted so a future "score N points in one run" template can be
## added without touching RunnerGame's call; nothing in the pool counts points
## today, because a score mission only moves at the tombstone screen and a
## mission the player cannot watch fill up is a mission they will not chase.
func note_run_ended(distance: float, _fish: int, _score: int,
		flush_save: bool = true) -> void:
	_flush_suppression_depth += 1
	note_distance(distance)
	_resolve()
	_persist()
	_flush_suppression_depth -= 1
	if flush_save:
		SaveManager.save_now()


## Leaving a living run preserves its current board without banking a score.
func checkpoint() -> void:
	_persist()


## --- Readouts ---------------------------------------------------------------

## Always exactly SET_SIZE rows. The array and its dictionaries are reused
## between calls, so callers must read them rather than hold them as a snapshot.
func rows() -> Array:
	for i in SET_SIZE:
		var row: Dictionary = _rows[i]
		row["id"] = _ids[i]
		row["text"] = _texts[i]
		# Presentation metadata avoids deriving compact HUD labels from prose.
		# Full mission-page wording, progress and persistence remain unchanged.
		row["kind"] = _kind[i]
		row["mult"] = _mult[i]
		row["param"] = _param[i]
		row["per_run"] = _per_run[i] == 1
		row["scope"] = "One run" if _per_run[i] == 1 else "Across runs"
		row["current"] = minf(_progress[i], _target[i])
		row["target"] = _target[i]
		row["done"] = _done[i] == 1
		row["progress"] = 1.0 if _done[i] == 1 \
			else clampf(_progress[i] / maxf(_target[i], 0.001), 0.0, 1.0)
	return _rows


func stars() -> int:
	return _stars


func completed_this_run() -> PackedStringArray:
	return _completed_run.duplicate()


func next_set_pending() -> bool:
	return _next_set_pending


## Never revoke earned badges, stars or known discoveries. Saved active mission
## targets/progress are grandfathered for their current board, then the next
## board uses this calibration. Older distance-only saves keep their old map
## unlocks without claiming they actually ran the new, longer distance.
static func _migrate_pacing() -> void:
	if int(SaveManager.get_value(SAVE_KEY_PACING, 0)) >= PACING_VERSION:
		return
	var best := Progression.runner_best_distance()
	if not is_finite(best): best = 0.0
	var old_region := clampi(floori(maxf(best, 0.0) / PREVIOUS_BIOME_LENGTH), 0, 3)
	var earned := clampi(int(SaveManager.get_value("runner_biome_milestone", 0)), 0, 3)
	SaveManager.set_value("runner_biome_milestone", maxi(earned, old_region))
	SaveManager.set_value(SAVE_KEY_PACING, PACING_VERSION)


## The map is a record of the farthest real run, not mission currency or the
## destination selected for inspection. Existing milestone saves are retained
## even when an older save has no best-distance statistic.
static func map_progress() -> Dictionary:
	_migrate_pacing()
	var length := RunnerTrack.BIOME_LENGTH
	var earned := clampi(int(SaveManager.get_value("runner_biome_milestone", 0)), 0, 3)
	var best := Progression.runner_best_distance()
	if not is_finite(best):
		best = 0.0
	var distance := maxf(best, 0.0)
	var current := maxi(earned, clampi(floori(distance / length), 0, 3))
	var names := ["DAY ICE", "TWILIGHT", "CAVES", "AURORA"]
	var regions: Array[Dictionary] = []
	for index: int in names.size():
		regions.append({"index":index, "name":names[index],
			"required_metres":float(index) * length,
			"unlocked":index <= current, "current":index == current})
	return {"distance":distance, "current_region":current,
		"route_position":clampf(maxf(distance / length, float(earned)), 0.0, 3.0),
		"legacy_discovery_retained":float(earned) * length > distance,
		"next_metres":float(current + 1) * length if current < 3 else 0.0,
		"regions":regions}


## --- Progress ---------------------------------------------------------------

## Adds to whichever of a cumulative/per-run pair is live. Both can be live at
## once only across different sets; within a set they share a channel and the
## draw refuses duplicates.
func _count(total_kind: int, run_kind: int, amount: float) -> void:
	for i in SET_SIZE:
		if _done[i] == 1:
			continue
		if _kind[i] == total_kind or _kind[i] == run_kind:
			_add_progress(i, amount)
	_resolve()


func _add_progress(slot: int, amount: float) -> void:
	_progress[slot] += amount
	if _progress[slot] >= _target[slot]:
		_done[slot] = 1
		_pending = true


## Absolute set, which must be allowed to go DOWN: the clean-streak mission
## reads the current streak, not the best one.
func _set_progress(slot: int, value: float) -> void:
	_progress[slot] = value
	if value >= _target[slot]:
		_done[slot] = 1
		_pending = true


## Award immediately, but retain the completed board until the next run. A long
## first run can complete three goals, never chain through new mission boards.
func _resolve() -> void:
	if not _pending:
		return
	_pending = false
	var announcements := PackedStringArray()
	for i in SET_SIZE:
		if _done[i] == 1 and _announced[i] == 0:
			_announced[i] = 1
			announcements.append(_texts[i])
			_completed_run.append(_texts[i])
	if announcements.is_empty():
		return
	var cleared := true
	for i in SET_SIZE:
		if _done[i] == 0:
			cleared = false
			break
	if cleared:
		_stars += 1
		_award_star()
		_next_set_pending = true
	_refresh_watch()
	_persist()
	Progression.record_runner_event("runner_missions_done", announcements.size())
	# Completion state, counters, trophies and rewards are one durable unit.
	if _flush_suppression_depth == 0:
		SaveManager.save_now()
	for text in announcements:
		completed.emit(text)
	if cleared:
		set_cleared.emit(_stars)


## A star pays out in the racing game's currencies on purpose: the runner is
## the same penguin and the same wardrobe, so time spent here has to buy hats.
func _award_star() -> void:
	Progression.add_fish(mini(STAR_FISH + (_stars - 1) * STAR_FISH_PER_STAR, STAR_FISH_CAP), "runner_board:%d" % _stars)
	Progression.add_xp(STAR_XP)


func _refresh_watch() -> void:
	_watch_distance = false
	for i in SET_SIZE:
		if _done[i] == 1:
			continue
		match _kind[i]:
			Kind.DISTANCE_RUN, Kind.DISTANCE_TOTAL, Kind.CLEAN_RUN, Kind.MULTIPLIER_RUN:
				_watch_distance = true
				return


## --- Drawing a set ----------------------------------------------------------

## Three missions, no two on the same channel, none repeating the set that just
## finished unless the live pool is too thin to avoid it.
func _roll_set() -> void:
	_next_set_pending = false
	_pending = false
	# Predictable onboarding: straightforward totals that survive short runs.
	if _stars == 0:
		for slot: int in SET_SIZE:
			_fill_slot(slot, _template_index(["dist_total", "fish_total", "jump_total"][slot]), 0, "")
			_progress[slot] = 0.0
			_done[slot] = 0
			_announced[slot] = 0
		return
	var pool: Array[int] = []
	for i in TEMPLATES.size():
		if _channel_live(String(TEMPLATES[i]["channel"])) and _template_unlocked(TEMPLATES[i]):
			pool.append(i)
	# Shuffled with the local generator rather than Array.shuffle, which draws
	# from the global seed the rest of the game also perturbs.
	for i in range(pool.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var swap := pool[i]
		pool[i] = pool[j]
		pool[j] = swap

	var previous := _ids.duplicate()
	var chosen: Array[int] = []
	var used := PackedStringArray()
	var has_run_goal := false
	# Each pass drops one constraint, so a thin pool degrades to a duller set
	# instead of an incomplete one.
	for relaxation in 3:
		for index in pool:
			if chosen.size() >= SET_SIZE:
				break
			if chosen.has(index):
				continue
			var tpl: Dictionary = TEMPLATES[index]
			if bool(tpl["per_run"]) and has_run_goal:
				continue
			if relaxation < 2 and used.has(String(tpl["channel"])):
				continue
			if relaxation < 1 and previous.has(String(tpl["id"])):
				continue
			chosen.append(index)
			used.append(String(tpl["channel"]))
			has_run_goal = has_run_goal or bool(tpl["per_run"])
		if chosen.size() >= SET_SIZE:
			break

	var base_tier := clampi(_stars / STARS_PER_TIER, 0, TIER_COUNT - 1)
	for slot in SET_SIZE:
		var index: int = chosen[slot] if slot < chosen.size() else 0
		_fill_slot(slot, index, base_tier, _draw_param(TEMPLATES[index]))
		_progress[slot] = 0.0
		_done[slot] = 0
		_announced[slot] = 0


func _template_unlocked(tpl: Dictionary) -> bool:
	match int(tpl["kind"]):
		Kind.MULTIPLIER_RUN, Kind.POWERUP_SPECIFIC: return _stars >= 12
		Kind.NEAR_MISS_TOTAL, Kind.NEAR_MISS_RUN: return _stars >= 8
		Kind.POWERUP_RUN, Kind.RAMP_RUN: return _stars >= 8
		Kind.POWERUP_TOTAL, Kind.RAMP_TOTAL: return _stars >= 4
		Kind.SLIDE_TOTAL, Kind.LANE_TOTAL: return _stars >= 1
	return _stars >= 3 if bool(tpl["per_run"]) else true


## The extra noun a template needs, or "" for the ones that need none.
func _draw_param(tpl: Dictionary) -> String:
	if int(tpl["kind"]) == Kind.POWERUP_SPECIFIC:
		return String(RunnerConfig.POWERUP_IDS[_rng.randi_range(
			0, RunnerConfig.POWERUP_IDS.size() - 1)])
	return ""


func _fill_slot(slot: int, index: int, tier: int, param: String) -> void:
	var tpl: Dictionary = TEMPLATES[index]
	var tiers: Array = tpl["tiers"]
	var target := float(tiers[clampi(tier, 0, tiers.size() - 1)])
	var mult := 0
	if tpl.has("tier_mults"):
		var mults: Array = tpl["tier_mults"]
		mult = int(mults[clampi(tier, 0, mults.size() - 1)])
	_ids[slot] = String(tpl["id"])
	_kind[slot] = int(tpl["kind"])
	_target[slot] = target
	_mult[slot] = mult
	_param[slot] = param
	_per_run[slot] = 1 if bool(tpl["per_run"]) else 0
	_resets_on_hit[slot] = 1 if bool(tpl["resets_on_hit"]) else 0
	_texts[slot] = _build_text(tpl, target, param, mult)


## --- Persistence ------------------------------------------------------------

func _persist() -> void:
	var stored: Array = []
	for i in SET_SIZE:
		stored.append({
			"id": _ids[i],
			"target": _target[i],
			"progress": _progress[i],
			"done": _done[i] == 1,
			"param": _param[i],
			"mult": _mult[i],
		})
	SaveManager.set_value(SAVE_KEY_SET, stored)
	SaveManager.set_value(SAVE_KEY_STARS, _stars)
	SaveManager.set_value(SAVE_KEY_NEXT_SET, _next_set_pending)
	_persist_distance = _last_distance


## Rebuilds the live set from a saved one. Returns false — and leaves the slots
## half-written for the caller's fresh draw to overwrite — if anything in there
## no longer matches this build's pool, which is what makes editing TEMPLATES a
## safe operation on an existing save.
func _adopt(stored: Array) -> bool:
	for i in SET_SIZE:
		if not (stored[i] is Dictionary):
			return false
		var entry: Dictionary = stored[i]
		var index := _template_index(String(entry.get("id", "")))
		if index < 0:
			return false
		var target := float(entry.get("target", 0.0))
		if target <= 0.0:
			return false
		var tpl: Dictionary = TEMPLATES[index]
		var param := String(entry.get("param", ""))
		var mult := int(entry.get("mult", 0))
		_ids[i] = String(tpl["id"])
		_kind[i] = int(tpl["kind"])
		_target[i] = target
		_mult[i] = mult
		_param[i] = param
		_per_run[i] = 1 if bool(tpl["per_run"]) else 0
		_resets_on_hit[i] = 1 if bool(tpl["resets_on_hit"]) else 0
		# Rebuilt rather than restored so a reworded template reaches players
		# who are already carrying that mission.
		_texts[i] = _build_text(tpl, target, param, mult)
		_progress[i] = maxf(float(entry.get("progress", 0.0)), 0.0)
		_done[i] = 1 if bool(entry.get("done", false)) else 0
		_announced[i] = _done[i]
	return true


func _read_channels() -> PackedStringArray:
	var live := PackedStringArray()
	var stored: Variant = SaveManager.get_value(SAVE_KEY_CHANNELS, null)
	if stored is Array:
		for entry: Variant in stored as Array:
			var name := String(entry)
			if name != "" and not live.has(name):
				live.append(name)
	return live


## Records that a feed is wired and firing. Written straight through, because
## the very first jump of a save has to widen the pool for the reroll that may
## happen seconds later.
func _prove(channel: String) -> void:
	if _channels.has(channel):
		return
	_channels.append(channel)
	var stored: Array = []
	for name in _channels:
		stored.append(name)
	SaveManager.set_value(SAVE_KEY_CHANNELS, stored)


func _channel_live(channel: String) -> bool:
	return CORE_CHANNELS.has(channel) or _channels.has(channel)


## --- Text -------------------------------------------------------------------

static func _template_index(id: String) -> int:
	for i in TEMPLATES.size():
		if String(TEMPLATES[i]["id"]) == id:
			return i
	return -1


static func _build_text(tpl: Dictionary, target: float, param: String, mult: int) -> String:
	var format := String(tpl["format"])
	match int(tpl["kind"]):
		Kind.MULTIPLIER_RUN:
			return format % [_group(int(target)), mult]
		Kind.POWERUP_SPECIFIC:
			return format % [_powerup_name(param), _group(int(target))]
	return format % _group(int(target))


static func _powerup_name(id: String) -> String:
	match id:
		"magnet":
			return "the fish magnet"
		"shield":
			return "the shield"
		"double":
			return "double points"
	return id


## Thousands separators. "Run 20000 m" is a wall of digits at a glance, and the
## mission row is read in peripheral vision while the player is dodging.
static func _group(value: int) -> String:
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" + out) if value < 0 else out
