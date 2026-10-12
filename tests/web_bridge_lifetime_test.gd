extends Node
## Exact production queue/poll loop with synthetic clock and transport.
## No browser/network or account data. Run with isolated user:// identity.

class BridgeFixture extends "res://scripts/network/leaderboard_client.gd":
	var clock: int = 0
	var replies: Dictionary = {}
	var cancelled: Array[int] = []
	func _ready() -> void:
		set_process(false)
	func _bridge_clock_msec() -> int:
		return clock
	func _read_bridge_result(req_id: int) -> Variant:
		var value: Variant = replies.get(req_id, "")
		replies.erase(req_id)
		return value
	func _cancel_bridge_request(req_id: int) -> void:
		cancelled.append(req_id)
		replies.erase(req_id)

class Receiver extends Node:
	func receive(_ok: bool, _payload: Dictionary) -> void:
		pass

var _passed := 0
var _failed := 0


func _ready() -> void:
	var identity := String(ProjectSettings.get_setting("application/config/custom_user_dir_name", ""))
	if not identity.begins_with("waddle-wars-tests-"):
		push_error("web_bridge_lifetime: isolated test identity required")
		get_tree().quit(2)
		return
	_test_timeout()
	_test_response_after_pause()
	_test_failures_and_reentry()
	_test_invalid_callback()
	_test_exit_cleanup()
	print("[web_bridge_lifetime] DONE: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed else 0)


func _fixture() -> BridgeFixture:
	var client := BridgeFixture.new()
	add_child(client)
	return client


func _test_timeout() -> void:
	var client := _fixture()
	var deliveries: Array[Dictionary] = []
	for id: int in range(1, 101):
		client._track_bridge_request(id, func(ok: bool, payload: Dictionary) -> void:
			deliveries.append({"ok": ok, "payload": payload}))
	client.clock = client.BRIDGE_TIMEOUT_MSEC - 1
	client._poll_bridge()
	_check("unexpired callbacks remain pending", client._pending_bridge.size() == 100 and deliveries.is_empty())
	client.clock += 1
	client._poll_bridge()
	_check("100 hung requests delivered once", deliveries.size() == 100)
	_check("all hung requests aborted", client.cancelled.size() == 100)
	_check("queue and deadlines drained", client._pending_bridge.is_empty() and client._pending_bridge_started.is_empty())
	_check("failure is truthful", deliveries.all(func(row: Dictionary) -> bool:
		return row["ok"] == false and row["payload"] == {"error": "network_unavailable"}))
	client.clock += 100000
	client._poll_bridge()
	_check("later polling cannot redeliver", deliveries.size() == 100 and client.cancelled.size() == 100)
	client.free()


func _test_response_after_pause() -> void:
	var client := _fixture()
	var deliveries: Array[Dictionary] = []
	client._track_bridge_request(1, func(ok: bool, payload: Dictionary) -> void:
		deliveries.append({"ok": ok, "payload": payload}))
	# A completed request can wait behind a paused/hidden tab. Read it before
	# evaluating the engine fallback so that elapsed wall time cannot falsify it.
	client.clock = client.BRIDGE_TIMEOUT_MSEC * 10
	client.replies[1] = JSON.stringify({"ok": true, "status": 200, "body": '{"entries":["one","two"]}'})
	client._poll_bridge()
	_check("settled success survives delayed poll", deliveries == [{"ok": true, "payload": {"entries": ["one", "two"]}}])
	_check("success does not abort", client.cancelled.is_empty())
	_check("successful callback and deadline removed", client._pending_bridge.is_empty() and client._pending_bridge_started.is_empty())
	client._poll_bridge()
	_check("success delivered once", deliveries.size() == 1)
	client.free()


func _test_failures_and_reentry() -> void:
	var client := _fixture()
	var deliveries: Array[Dictionary] = []
	client._track_bridge_request(1, func(ok: bool, payload: Dictionary) -> void:
		deliveries.append({"ok": ok, "payload": payload})
		_check("old request removed before delivery", not client._pending_bridge.has(1))
		client._track_bridge_request(2, func(next_ok: bool, next_payload: Dictionary) -> void:
			deliveries.append({"ok": next_ok, "payload": next_payload})))
	client.replies[1] = JSON.stringify({"ok": false, "status": 503, "body": '{"error":"unavailable"}'})
	client._poll_bridge()
	_check("HTTP error retained", deliveries == [{"ok": false, "payload": {"error": "unavailable"}}])
	_check("reentrant request remains registered", client._pending_bridge.has(2) and client._pending_bridge_started.has(2))
	client.replies[2] = "[]"
	client._poll_bridge()
	_check("bad bridge shape returns failure", deliveries[1] == {"ok": false, "payload": {"error": "bad bridge response"}})
	_check("bad response also drains", client._pending_bridge.is_empty() and client._pending_bridge_started.is_empty())
	client.free()


func _test_invalid_callback() -> void:
	var client := _fixture()
	var receiver := Receiver.new()
	client._track_bridge_request(3, receiver.receive)
	receiver.free()
	client._poll_bridge()
	_check("freed receiver request cancelled", client.cancelled == [3])
	_check("freed receiver leaves no callback/deadline", client._pending_bridge.is_empty() and client._pending_bridge_started.is_empty())
	client.free()


func _test_exit_cleanup() -> void:
	var client := _fixture()
	var deliveries: Array = []
	client._track_bridge_request(4, func(_ok: bool, _payload: Dictionary) -> void: deliveries.append(true))
	client._track_bridge_request(5, func(_ok: bool, _payload: Dictionary) -> void: deliveries.append(true))
	var cancellations := client.cancelled
	var pending := client._pending_bridge
	var deadlines := client._pending_bridge_started
	client.free()
	_check("exit aborts each outstanding request", cancellations == [4, 5])
	_check("exit releases callback and clock storage", pending.is_empty() and deadlines.is_empty())
	_check("teardown does not invoke dead consumers", deliveries.is_empty())


func _check(label: String, ok: bool) -> void:
	if ok:
		_passed += 1
		print("[web_bridge_lifetime] PASS: ", label)
	else:
		_failed += 1
		push_error("[web_bridge_lifetime] FAIL: " + label)
