class_name DailyChallenge
## The same race for everybody, every day, decided by the calendar rather than
## by a server.
##
## The game had no reason to come back tomorrow: fish, XP, achievements and
## cosmetics all reward playing more in one sitting, and nothing rewards
## returning. A daily is the standard answer because it does three jobs at
## once -- it gives a reason to return, it gives a score worth comparing (one
## fixed course and modifier means times are directly comparable, unlike a
## free-choice race), and it gives something worth sharing, because a friend
## who opens the link races the identical course rather than merely hearing
## about it.
##
## Everything here derives from the UTC date, so two players get the same
## challenge without any coordination and without a round trip. UTC rather
## than local time so a shared result never refers to a challenge the
## recipient's device has already rolled past.

## Course rotation. Endless and the tutorial are excluded: a daily has to be a
## single comparable run with an end.
const COURSES: PackedStringArray = ["glacier", "aurora", "iceberg"]

## Modifiers keep the same course feeling different across the rotation, and
## give the day a name worth repeating. Each is a display name plus the
## difficulty the field races at.
const MODIFIERS: Array[Dictionary] = [
	{"id": "sprint", "name": "Sprint", "difficulty": "competitive",
		"blurb": "Standard race, standard field. A clean lap is the whole test."},
	{"id": "gauntlet", "name": "Gauntlet", "difficulty": "emperor",
		"blurb": "The fastest field in the game. Hold your line."},
	{"id": "chill", "name": "Cruise", "difficulty": "chill",
		"blurb": "A gentle field -- this one is about your own time, not theirs."},
]

## Fish awarded for the day's first completion, before the streak bonus.
const BASE_REWARD: int = 40
## Extra fish per consecutive day, capped so a long streak stays a bonus
## rather than the only sane way to earn.
const STREAK_BONUS: int = 15
const STREAK_BONUS_CAP: int = 120


## Days since the Unix epoch, in UTC. This is the challenge's identity: it is
## what seeds the course choice, what the save compares against to decide
## whether today has been played, and what travels in a shared link.
static func today_id() -> int:
	return int(Time.get_unix_time_from_system()) / 86400


## The challenge for a given day. Pass no argument for today's.
static func for_day(day_id: int = -1) -> Dictionary:
	var day := day_id if day_id >= 0 else today_id()
	# Hash the day so consecutive days do not walk the rotation in lockstep
	# (course 0/mod 0, course 1/mod 1, ...), which would make the whole cycle
	# guessable after two days and repeat every three.
	var hashed := _hash_day(day)
	var course: String = COURSES[hashed % COURSES.size()]
	var modifier: Dictionary = MODIFIERS[(hashed / 7) % MODIFIERS.size()]
	return {
		"day": day,
		"course": course,
		"modifier": modifier["id"],
		"name": String(modifier["name"]),
		"blurb": String(modifier["blurb"]),
		"difficulty": String(modifier["difficulty"]),
		"seed": hashed,
	}


## Deterministic scramble of a day number. Cheap integer mix -- the point is
## decorrelating neighbouring days, not cryptographic quality.
static func _hash_day(day: int) -> int:
	var h := day * 2654435761
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))


## A one-line human label, e.g. "Aurora Ridge Gauntlet".
static func title_for(challenge: Dictionary) -> String:
	var course_name := String(challenge.get("course", ""))
	var info := CoursesDB.get_item(course_name)
	var display := String(info.get("name", course_name.capitalize())) if not info.is_empty() \
		else course_name.capitalize()
	return "%s %s" % [display, String(challenge.get("name", ""))]


## Day number requested by the page URL (?d=NNN), or -1 when there is none.
##
## This is the receiving half of a shared challenge: a friend who opens the
## link should land on that exact race, not on whatever today happens to be for
## them. Web only -- there is no URL to read anywhere else.
static func incoming_day() -> int:
	if GameConfig.is_headless() or not OS.has_feature("web"):
		return -1
	var probe: Variant = JavaScriptBridge.eval(
		"new URLSearchParams(location.search).get('d') || ''", true)
	var text := String(probe) if probe != null else ""
	if not text.is_valid_int():
		return -1
	var day := text.to_int()
	# Sanity bound: reject nonsense rather than seeding a course from it.
	# 19000 is early 2022; a century of headroom above today.
	if day < 19000 or day > today_id() + 36500:
		return -1
	return day


## --- Save state -------------------------------------------------------------

## True when today's challenge has already been completed.
static func is_complete_today() -> bool:
	return int(SaveManager.data.get("daily_last_day", -1)) == today_id()


## Best time recorded for today's challenge, or 0.0 if unplayed.
static func today_best() -> float:
	if not is_complete_today():
		return 0.0
	return float(SaveManager.data.get("daily_last_time", 0.0))


## Current consecutive-day streak.
static func streak() -> int:
	return int(SaveManager.data.get("daily_streak", 0))


## Records a completed daily. Returns a dictionary describing what the player
## earned: {"first_today": bool, "improved": bool, "streak": int, "fish": int}.
##
## Only the first completion of a day pays out, but later runs still record a
## better time -- so chasing your own time stays worthwhile without turning
## the daily into an infinite fish tap.
static func record_completion(time_seconds: float) -> Dictionary:
	var day := today_id()
	var last_day := int(SaveManager.data.get("daily_last_day", -1))
	var first_today := last_day != day
	var improved := false
	var current_streak := int(SaveManager.data.get("daily_streak", 0))

	if first_today:
		# Consecutive only if the previous completion was literally yesterday.
		current_streak = current_streak + 1 if last_day == day - 1 else 1
		SaveManager.data["daily_streak"] = current_streak
		SaveManager.data["daily_last_day"] = day
		SaveManager.data["daily_last_time"] = time_seconds
		if current_streak > int(SaveManager.data.get("daily_best_streak", 0)):
			SaveManager.data["daily_best_streak"] = current_streak
	else:
		var previous := float(SaveManager.data.get("daily_last_time", 0.0))
		if time_seconds < previous or previous <= 0.0:
			SaveManager.data["daily_last_time"] = time_seconds
			improved = true

	var fish := 0
	if first_today:
		fish = BASE_REWARD + mini((current_streak - 1) * STREAK_BONUS, STREAK_BONUS_CAP)
		Progression.add_fish(fish)
	SaveManager.save_now()
	return {
		"first_today": first_today,
		"improved": improved,
		"streak": current_streak,
		"fish": fish,
	}


## Streak the player would hold after playing today -- what the menu should
## advertise. A streak only breaks once a full day has been missed, so a
## player who last played yesterday is still being offered a continuation.
static func pending_streak() -> int:
	var day := today_id()
	var last_day := int(SaveManager.data.get("daily_last_day", -1))
	if last_day == day:
		return int(SaveManager.data.get("daily_streak", 0))
	if last_day == day - 1:
		return int(SaveManager.data.get("daily_streak", 0)) + 1
	return 1
