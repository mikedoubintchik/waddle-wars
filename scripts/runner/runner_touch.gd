class_name RunnerTouch
extends Node
## Swipe input for Waddle Run.
##
## The racing game's TouchControls is a set of on-screen buttons plus a steering
## drag, which is right for a racer you hold a line in. A runner is a gesture
## game: four swipes, no thumbs parked over the picture. This is deliberately
## its own thing rather than a mode on TouchControls — the two share no state
## and one file each is easier to reason about than one file with two brains.
##
## Recognition is direction-dominant with a distance threshold: whichever axis
## moved further wins, so a diagonal flick still does something rather than
## nothing, which is what players actually produce at speed.

## Fraction of the shorter screen edge a finger must travel to count as a
## swipe. Proportional rather than absolute so a phone and a tablet feel the
## same, and low enough that a flick counts before the finger leaves the glass.
const SWIPE_FRACTION: float = 0.045
## Below this, a touch is a tap rather than a swipe.
const TAP_MAX_FRACTION: float = 0.02
## A swipe must complete within this long, so a slow drag while dodging is not
## mistaken for a gesture.
const SWIPE_TIME: float = 0.42

var _player: RunnerPlayer = null
var _start: Vector2 = Vector2.ZERO
var _start_time: float = 0.0
var _tracking: bool = false
var _fired: bool = false


func setup(player: RunnerPlayer) -> void:
	_player = player
	# Runs while the tree is paused so a swipe cannot be swallowed mid-pause and
	# then applied on resume.
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _unhandled_input(event: InputEvent) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_begin(touch.position)
		else:
			_end(touch.position)
		return
	if event is InputEventScreenDrag:
		_drag((event as InputEventScreenDrag).position)


func _begin(at: Vector2) -> void:
	_start = at
	_start_time = float(Time.get_ticks_msec()) * 0.001
	_tracking = true
	_fired = false


## Fires as soon as the threshold is crossed rather than on release: waiting
## for the finger to lift adds a whole gesture of latency, and at 38 m/s that
## is the difference between clearing an obstacle and eating it.
func _drag(at: Vector2) -> void:
	if not _tracking or _fired:
		return
	var travel := at - _start
	var threshold := _threshold()
	if travel.length() < threshold:
		return
	if float(Time.get_ticks_msec()) * 0.001 - _start_time > SWIPE_TIME:
		_tracking = false
		return
	_fired = true
	if absf(travel.x) > absf(travel.y):
		_player.move_lane(1 if travel.x > 0.0 else -1)
	elif travel.y < 0.0:
		_player.jump()
	else:
		_player.slide()


func _end(at: Vector2) -> void:
	if not _tracking:
		return
	_tracking = false
	if _fired:
		return
	# A tap jumps. It is the most common accidental input and the most useful
	# default, and it gives one-handed players a way to clear low obstacles.
	if (at - _start).length() <= _threshold() * (TAP_MAX_FRACTION / SWIPE_FRACTION):
		_player.jump()


func _threshold() -> float:
	var viewport := get_viewport()
	if viewport == null:
		return 40.0
	var size := viewport.get_visible_rect().size
	return maxf(minf(size.x, size.y) * SWIPE_FRACTION, 24.0)
