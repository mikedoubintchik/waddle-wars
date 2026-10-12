class_name FeedbackClient
extends Node
## Public support transport. AWS credentials and the recipient stay server-side.

signal completed(ok: bool, message: String)

const ENDPOINT := "https://waddlewars.io/api/feedback"
const CATEGORIES := ["bug", "idea", "other"]
const MAX_MESSAGE := 2000
const TIMEOUT := 16.0

var busy := false
var _http: HTTPRequest


static func validation_error(category: String, message: String, email: String) -> String:
	if not CATEGORIES.has(category):
		return "Choose a feedback type."
	var clean := message.strip_edges()
	if clean.length() < 10:
		return "Tell us a little more (at least 10 characters)."
	# SES endpoint counts UTF-16 code units, as JavaScript does.
	if clean.to_utf16_buffer().size() / 2 > MAX_MESSAGE:
		return "Keep your message under 2,000 characters."
	var address := email.strip_edges()
	if not address.is_empty():
		var format := RegEx.create_from_string("^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$")
		if address.length() > 254 or format.search(address) == null:
			return "Check your email, or leave it blank."
	return ""


func submit(category: String, message: String, email: String) -> void:
	if busy:
		return
	var invalid := validation_error(category, message, email)
	if not invalid.is_empty():
		completed.emit(false, invalid)
		return
	busy = true
	_http = HTTPRequest.new()
	_http.process_mode = Node.PROCESS_MODE_ALWAYS
	_http.timeout = TIMEOUT
	_http.max_redirects = 0
	add_child(_http)
	_http.request_completed.connect(_received)
	var headers := PackedStringArray(["Content-Type: application/json"])
	# Browsers set Origin themselves; it is forbidden to override it there.
	if not OS.has_feature("web"):
		headers.append("Origin: https://play.waddlewars.io")
	var payload := {"category": category, "message": message.strip_edges(),
		"email": email.strip_edges(), "context": "%s | %s" % [GameConfig.BUILD_ID, OS.get_name()]}
	var error := _http.request(ENDPOINT, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		_finish(false, "Could not connect. Your message is still here; please try again.")


func _received(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
	var parser := JSON.new()
	var parsed: Variant = parser.data if not bytes.is_empty() and parser.parse(bytes.get_string_from_utf8()) == OK else null
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and parsed is Dictionary \
			and parsed.get("ok", false) == true:
		_finish(true, "Your message is on its way to support@waddlewars.io.")
		return
	if code == 429:
		_finish(false, "A few too many messages. Wait a minute, then try again.")
	elif code == 400 or code == 413:
		_finish(false, "Please check your message and optional email, then try again.")
	else:
		_finish(false, "Could not confirm delivery. Your message is saved here. Try again, or email support@waddlewars.io.")


func _finish(ok: bool, message: String) -> void:
	if is_instance_valid(_http):
		_http.queue_free()
	_http = null
	busy = false
	completed.emit(ok, message)
