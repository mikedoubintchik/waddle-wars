extends Node
## Best-effort anonymous counters. No per-frame work, persistent queue, or IDs.

const ENDPOINT := "https://waddlewars.io/api/telemetry"

var _opened := false


func app_open_once() -> void:
	if _opened:
		return
	_opened = true
	_record("app_open")


func run_started() -> void:
	_record("run_start")


func run_ended(distance: float, score: int, fish: int) -> void:
	_record("run_end", {
		"distance": clampf(distance, 0.0, 1000000000.0),
		"score": clampi(score, 0, 1000000000),
		"fish": clampi(fish, 0, 1000000000),
	})


func client_error(code: String) -> void:
	if code in ["loader", "scene_load", "network", "runtime"]:
		_record("client_error", {"code": code})


func _record(event_name: String, fields: Dictionary = {}) -> void:
	# Native collection awaits matching store privacy disclosures. The browser
	# privacy page covers these aggregate events now. The existing web HTTPRequest
	# path has been unreliable, so use browser fetch and swallow network failure.
	if not OS.has_feature("web") or GameConfig.is_headless():
		return
	var payload := {"event": event_name, "platform": "web", "build": GameConfig.BUILD_ID}
	payload.merge(fields)
	var script := "fetch(%s,{method:'POST',headers:{'Content-Type':'application/json'},body:%s,keepalive:true}).catch(()=>{});" % [
		JSON.stringify(ENDPOINT), JSON.stringify(JSON.stringify(payload))]
	JavaScriptBridge.eval(script, false)
