class_name TiltSteering
extends Node
## Steer by leaning the phone.
##
## Reads the device's orientation and turns the left/right lean into the same
## -1..1 axis the keyboard and the drag-steer produce, so nothing downstream
## has to know where the input came from.
##
## Three things make this harder than "read the sensor":
##
##  1. PERMISSION. iOS 13+ refuses DeviceOrientation events until a page asks
##     for them from inside a real user gesture, and it only asks once. So the
##     request is fired from the settings toggle's own press, not from the race
##     -- by the time a race starts there is no gesture left to spend.
##  2. ORIENTATION. The phone's own axes do not rotate with the screen. Which
##     device axis means "screen left/right" depends on screen.orientation.angle,
##     and this game is playable both ways up, so the reading is rotated into
##     screen space rather than assuming landscape.
##  3. NEUTRAL. Nobody holds a phone at zero degrees. Steering off the absolute
##     angle would mean fighting a constant pull, so a neutral pose is captured
##     and the axis measures deviation from it.
##
## The drag-steer is deliberately left working at the same time: a finger on
## the screen overrides the tilt (see PlayerController). If the sensor is
## missing, refused, or silent, this reports unavailable and the touch controls
## carry on exactly as before -- tilt can never leave a player unable to steer.

## Lean, in degrees from the neutral pose, that produces full lock at
## sensitivity 1.0. About the range of a comfortable wrist roll.
const FULL_LOCK_DEG: float = 26.0
## Degrees of slop around neutral that produce nothing, so a hand that is not
## perfectly still does not wander.
const DEADZONE_DEG: float = 2.2
## Seconds without a fresh reading before the sensor is treated as gone.
const STALE_AFTER: float = 1.5
## Readings averaged into the neutral pose when calibrating.
const CALIBRATION_SAMPLES: int = 12

## Installed once per page. Keeps the newest screen-space lean on the window so
## GDScript can read a property instead of eval-ing a string every frame.
const JS_SHIM := """
window.__ww_tilt = window.__ww_tilt || {ok: 0, x: 0.0, ts: 0, on: 0, state: 'idle'};

window.__ww_tilt_listen = function () {
	if (window.__ww_tilt.on) { return; }
	window.addEventListener('deviceorientation', function (e) {
		var g = (e.gamma == null) ? 0 : e.gamma;
		var b = (e.beta == null) ? 0 : e.beta;
		if (e.gamma == null && e.beta == null) { return; }
		var a = 0;
		try {
			a = (screen.orientation && screen.orientation.angle) || window.orientation || 0;
		} catch (_) { a = 0; }
		var r = a * Math.PI / 180.0;
		// Rotate the device's lean into the screen's own horizontal axis, so
		// the same physical movement steers the same way whichever way up the
		// phone is being held.
		window.__ww_tilt.x = g * Math.cos(r) + b * Math.sin(r);
		window.__ww_tilt.ok = 1;
		window.__ww_tilt.ts = Date.now();
		window.__ww_tilt.state = 'granted';
	}, true);
	window.__ww_tilt.on = 1;
};

// Asks, and reports what happened. Must run inside a real gesture on iOS.
window.__ww_tilt_ask = function () {
	try {
		if (typeof DeviceOrientationEvent === 'undefined') {
			window.__ww_tilt.state = 'nosensor';
			return;
		}
		if (typeof DeviceOrientationEvent.requestPermission === 'function') {
			window.__ww_tilt.state = 'pending';
			DeviceOrientationEvent.requestPermission().then(function (s) {
				if (s === 'granted') {
					window.__ww_tilt.state = 'listening';
					window.__ww_tilt_listen();
					return;
				}
				window.__ww_tilt.state = 'denied';
				window.__ww_tilt_rearm();
			}).catch(function () {
				// A throw here usually means "not allowed from this context"
				// rather than a real refusal, so it must not be terminal.
				window.__ww_tilt.state = 'denied';
				window.__ww_tilt_rearm();
			});
			return;
		}
	} catch (_) {
		window.__ww_tilt.state = 'denied';
		return;
	}
	// No permission gate (Android, desktop): just listen.
	window.__ww_tilt.state = 'listening';
	window.__ww_tilt_listen();
};

// A refusal is not necessarily the player's answer -- it is also what Safari
// returns when the call was made outside an activation. Re-arm a couple of
// times so a bad context costs one tap rather than the whole feature, while
// still giving up rather than nagging somebody who really did say no.
window.__ww_tilt_rearm = function () {
	window.__ww_tilt.tries = (window.__ww_tilt.tries || 0) + 1;
	if (window.__ww_tilt.tries >= 3) { return; }
	window.__ww_tilt._armed = 0;
	window.__ww_tilt_arm();
};

// Arms the ask on the next REAL DOM gesture.
//
// This has to happen in JavaScript, not in GDScript. Godot queues browser
// input and dispatches it during its own main-loop iteration, so by the time a
// GDScript _input handler runs it is no longer inside the DOM event handler --
// and Safari grants DeviceOrientation only to a request made from within one.
// Asking from GDScript looked correct and was silently refused, with no prompt
// shown and no error raised.
// Explicit retry: try right now AND arm the next tap.
//
// The immediate attempt is worth making because the press that triggered it is
// usually still inside the browser's activation window; the armed listener is
// the fallback for when it is not. Before this, a retry could only ever work
// on the tap AFTER the button, which is not what a button labelled "Try Again"
// leads anyone to expect.
window.__ww_tilt_retry = function () {
	window.__ww_tilt._armed = 0;
	window.__ww_tilt.state = 'idle';
	window.__ww_tilt_arm();
	window.__ww_tilt_ask();
};

window.__ww_tilt_arm = function () {
	// Re-arm after a refusal. The first version returned early whenever it had
	// ever been armed, which made the "Try Again" button a no-op -- it looked
	// like a retry and did nothing at all.
	var st = window.__ww_tilt.state;
	if (st === 'granted' || st === 'listening' || st === 'pending') { return; }
	if (window.__ww_tilt._armed) { return; }
	window.__ww_tilt._armed = 1;
	// Arm on the END of a press, never the start.
	//
	// This is why the prompt never appeared. pointerdown fires first, so it was
	// always the event that spent the arm -- and a press that has gone DOWN but
	// not yet UP does not give the page transient activation for a gated API.
	// Safari therefore rejected requestPermission() immediately, without ever
	// showing a prompt, and the handler had already unhooked touchend and click
	// so the events that WOULD have worked never got a turn. Reported as
	// "Blocked" by a player who had never been asked anything.
	var fire = function () {
		window.removeEventListener('touchend', fire, true);
		window.removeEventListener('pointerup', fire, true);
		window.removeEventListener('click', fire, true);
		window.__ww_tilt._armed = 0;
		window.__ww_tilt_ask();
	};
	window.addEventListener('touchend', fire, true);
	window.addEventListener('pointerup', fire, true);
	window.addEventListener('click', fire, true);
};
"""

static var _shim_installed: bool = false
static var _bridge: JavaScriptObject = null

var _neutral: float = 0.0
var _calibrated: bool = false
var _samples: Array[float] = []
var _last_raw: float = 0.0
var _fresh_timer: float = 0.0


## True where a lean could ever be read: a phone browser, or a native mobile
## build. Desktop never offers it, so the setting stays hidden there.
static func supported() -> bool:
	if GameConfig.is_headless():
		return false
	if OS.has_feature("web"):
		return SettingsManager.is_mobile_web() or GameConfig.has_touchscreen()
	# has_touchscreen() is false on a desktop, so this is still hidden there --
	# but it means GameConfig.force_touch reveals the rows for QA, which is the
	# only way to see this screen's phone layout on a workstation.
	return GameConfig.is_mobile() or GameConfig.has_touchscreen()


## Arms the sensor request against the next real DOM gesture. Safe to call
## repeatedly; the shim only arms once until it has fired.
static func request_permission(retry: bool = false) -> void:
	if not OS.has_feature("web") or GameConfig.is_headless():
		return
	_install_shim()
	JavaScriptBridge.eval(
		"window.__ww_tilt_retry()" if retry else "window.__ww_tilt_arm()", true)


## Where the sensor currently stands, for the settings row to show. One of
## "idle", "pending", "listening", "granted", "denied", "nosensor" -- or
## "unsupported" off the web.
static func permission_state() -> String:
	if not OS.has_feature("web") or GameConfig.is_headless():
		return "unsupported"
	_install_shim()
	if _bridge == null:
		return "idle"
	return String(_bridge.state)


## Fires the permission request on the player's NEXT real tap, then stops
## listening. Nothing to dismiss and nothing extra to press.
##
## The setting is on by default, but iOS will not grant motion access to a page
## that has not asked from inside a gesture -- and a page cannot manufacture
## one. So rather than putting a modal in front of somebody just to harvest a
## press, the ask rides whatever they were going to tap anyway. On Android and
## desktop browsers there is no permission at all and this is a no-op beyond
## installing the listener.
static func arm_permission_on_first_gesture(_host: Node) -> void:
	if GameConfig.is_headless() or not supported():
		return
	if not bool(SettingsManager.get_setting("gameplay", "tilt_steering")):
		return
	request_permission()


static func _install_shim() -> void:
	if _shim_installed or not OS.has_feature("web") or GameConfig.is_headless():
		return
	JavaScriptBridge.eval(JS_SHIM, true)
	_shim_installed = true
	_bridge = JavaScriptBridge.get_interface("__ww_tilt")


func _ready() -> void:
	_install_shim()


## Re-reads the neutral pose from however the phone is being held right now.
## Called when a race starts, and available to the player as a settings action.
func recalibrate() -> void:
	_calibrated = false
	_samples.clear()


## True when readings are actually arriving. False before permission is
## granted, on a device with no sensor, and if the stream stops.
func active() -> bool:
	return _fresh_timer > 0.0


## Screen-space lean, in degrees, or 0.0 when nothing is reporting.
func _read_raw() -> float:
	if OS.has_feature("web"):
		if _bridge == null:
			_install_shim()
			if _bridge == null:
				return 0.0
		if int(_bridge.ok) != 1:
			return 0.0
		return float(_bridge.x)
	# Native mobile: gravity is already in the viewport's frame, so its X
	# component IS the screen-space lean. Converted to degrees to share the
	# tuning constants with the web path.
	var gravity := Input.get_gravity()
	if gravity.length_squared() < 0.01:
		return 0.0
	return rad_to_deg(asin(clampf(gravity.normalized().x, -1.0, 1.0)))


## Steering axis in the same convention as Input.get_axis("steer_left",
## "steer_right"): -1 hard left, +1 hard right. 0.0 when unavailable.
func poll(delta: float) -> float:
	var raw := _read_raw()
	# A sensor that stops reporting must not leave the racer steering into a
	# wall forever, so the value has to go stale rather than persist.
	if not is_equal_approx(raw, _last_raw) or raw != 0.0:
		_fresh_timer = STALE_AFTER
		_last_raw = raw
	else:
		_fresh_timer = maxf(_fresh_timer - delta, 0.0)
	if _fresh_timer <= 0.0:
		return 0.0

	if not _calibrated:
		_samples.append(raw)
		if _samples.size() < CALIBRATION_SAMPLES:
			return 0.0
		var total := 0.0
		for sample: float in _samples:
			total += sample
		_neutral = total / float(_samples.size())
		_samples.clear()
		_calibrated = true

	return axis_for_lean(
		raw - _neutral,
		float(SettingsManager.get_setting("gameplay", "tilt_sensitivity")),
		bool(SettingsManager.get_setting("gameplay", "tilt_invert")))


## Lean in degrees (relative to neutral) -> steering axis. Pure maths, kept
## separate from the sensor plumbing so it can be tested without a phone --
## which matters here, because the one thing I cannot check by running the game
## on this machine is the thing the player actually feels.
static func axis_for_lean(lean_deg: float, sensitivity: float, invert: bool) -> float:
	var slack := signf(lean_deg) * maxf(absf(lean_deg) - DEADZONE_DEG, 0.0)
	if is_zero_approx(slack):
		return 0.0
	var scale := clampf(sensitivity, 0.4, 2.0)
	var axis := clampf(slack / (FULL_LOCK_DEG / scale), -1.0, 1.0)
	return -axis if invert else axis
