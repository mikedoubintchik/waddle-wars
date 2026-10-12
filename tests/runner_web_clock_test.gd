extends Node

const CLOCK := preload("res://tests/runner_web_clock.gd")
var _checks := 0
var _failed := 0


func _check(value: bool, label: String) -> void:
	_checks += 1
	if not value:
		_failed += 1
		push_error("[runner_web_clock] FAIL " + label)


func _ready() -> void:
	var sample := CLOCK.bracket("first_running", 10000, 42.0, 10050)
	_check(sample.valid, "finite ordered bracket valid")
	_check(sample.label == "first_running", "label retained")
	_check(sample.bracket_width_us == 50, "uncertainty width retained")
	_check(sample.browser_minus_godot_min_us == 31950.0, "offset lower bound uses latest Godot read")
	_check(sample.browser_minus_godot_max_us == 32000.0, "offset upper bound uses earliest Godot read")
	for anchor: int in [10000, 10025, 10050]:
		var offset := 42000.0 - float(anchor)
		_check(offset >= sample.browser_minus_godot_min_us and offset <= sample.browser_minus_godot_max_us,
				"every possible synchronous read is enclosed")
	var exact := CLOCK.bracket("report", 10000, 0, 10000)
	_check(exact.valid and exact.bracket_width_us == 0, "zero-width bracket and integer zero are valid")
	_check(exact.browser_minus_godot_min_us == -10000.0, "negative offset allowed")
	for invalid: Variant in [null, true, "42", NAN, INF, -1.0, 1.0e308]:
		var rejected := CLOCK.bracket("report", 0, invalid, 1)
		_check(not rejected.valid and not rejected.has("browser_minus_godot_min_us"),
				"unavailable/nonfinite browser value never becomes zero offset")
		_check(not rejected.has("browser_ms"), "invalid value never enters JSON report")
	_check(not CLOCK.bracket("report", 20, 1.0, 19).valid, "reversed bracket rejected")
	_check(not CLOCK.bracket("report", -1, 1.0, 19).valid, "negative Godot timestamp rejected")
	print("[runner_web_clock] %d checks, %d failures" % [_checks, _failed])
	get_tree().quit(1 if _failed else 0)
