extends Node
## Synthetic authentication states only. Never opens Clerk, sends HTTP, or edits
## a real account. Native adapter tests separately exercise system-sheet cancel.

class FakeLeaderboard extends "res://scripts/network/leaderboard_client.gd":
	var starts := 0
	var exits := 0
	func can_sign_in() -> bool: return true
	func sign_in() -> void:
		starts += 1
		sign_in_pending = true
		auth_error = ""
		auth_status = "Complete sign-in in the secure window."
		auth_changed.emit()
	func sign_out() -> void:
		exits += 1
		signed_in = false
		auth_status = "Signed out. Your progress stays on this device."
		auth_changed.emit()
	func _dispatch_request(_method: String, _url: String, _body: String, cb: Callable) -> void:
		cb.call(false, {"error": "synthetic_offline"})

class BoardFixture extends "res://scripts/ui/leaderboard_premium.gd":
	var fetches := 0
	func _fetch() -> void: fetches += 1

var _checks := 0
var _failed := 0

func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		get_tree().quit(2)
		return
	LeaderboardClient.set_script(FakeLeaderboard)
	LeaderboardClient.set_process(false)
	NativeAuthClient.set_process(false)
	SaveManager.data = SaveManager.default_save()
	_check_presenter()
	for shape: Vector2i in [Vector2i(800,1734), Vector2i(1734,800), Vector2i(1280,720)]:
		await _check_pages(shape)
	for player: AudioStreamPlayer in AudioManager._sfx_pool + [AudioManager._music_a, AudioManager._music_b]:
		player.stop()
		player.stream = null
	LayoutProfile.forced_insets = Vector4(-1,-1,-1,-1)
	GameConfig.force_touch = false
	await get_tree().create_timer(0.2).timeout
	print("[account-auth-ui] DONE: %d/%d passed" % [_checks-_failed,_checks])
	get_tree().quit(1 if _failed else 0)

func _check_presenter() -> void:
	var pending := AccountAuthPresentation.describe(false,true,"","Complete sign-in in the secure window.",true)
	_check(pending["caption"] == "CANCEL SIGN IN" and not pending["disabled"] and pending["action"] == "cancel",
		"native pending remains cancellable")
	var failed := AccountAuthPresentation.describe(false,false,"native_auth","Could not connect. Please try again.",true)
	_check(failed["caption"] == "RETRY SIGN IN" and failed["action"] == "sign_in" and not failed["disabled"], "native error enables explicit retry")
	_check(not String(failed["message"]).contains("native_auth"), "provider/internal error codes never rendered")
	var canceled := AccountAuthPresentation.describe(false,false,"","Sign-in cancelled.",true)
	_check(canceled["action"] == "sign_in" and canceled["message"] == "Sign-in cancelled.", "cancel explains result and permits later sign-in")
	var signed := AccountAuthPresentation.describe(true,false,"","Connected.",true)
	_check(signed["caption"] == "SIGN OUT" and signed["message"] == "", "connected account yields to sync status")
	_check(AccountAuthPresentation.account_capability(true,true), "iOS account capability remains available in offline-first edition")
	_check(not AccountAuthPresentation.account_capability(true,false), "Android/older offline edition remains account-free")
	_check(AccountAuthPresentation.account_capability(false,false), "existing web account capability remains available")

func _check_pages(shape: Vector2i) -> void:
	GameConfig.force_touch = shape.y > shape.x
	LayoutProfile.forced_insets = Vector4(0,59,0,34)*(800.0/430.0) if shape.y>shape.x else Vector4.ZERO
	var viewport := SubViewport.new()
	viewport.size = shape
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	for kind: String in ["account","settings","board"]:
		_state(false,false,"","")
		var page: Control
		var action_name := ""
		var status_name := ""
		match kind:
			"account":
				page = load("res://scenes/menus/main_menu.tscn").instantiate()
				action_name = "AccountAuthAction"
				status_name = "AccountSyncStatus"
			"settings":
				page = load("res://scenes/menus/settings.tscn").instantiate()
				action_name = "SettingsAccountAuth"
				status_name = "SettingsAccountAuthStatus"
			"board":
				page = BoardFixture.new()
				action_name = "BoardAuthAction"
				status_name = "BoardPostStatus"
		viewport.add_child(page)
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if kind == "account": page.call("_show_account")
		if kind == "settings":
			page.set("_active","online")
			page.call("_rebuild")
		await _settle()
		var button := page.find_child(action_name,true,false) as Button
		_check(button != null and not button.disabled, kind+" offers account action "+str(shape))
		if button == null:
			page.free()
			continue
		var before := int(LeaderboardClient.get("starts"))
		button.pressed.emit()
		await _settle()
		_check(int(LeaderboardClient.get("starts")) == before+1, kind+" tap starts exactly one sign-in")
		_check(is_instance_valid(button) and page.find_child(action_name,true,false)==button, kind+" keeps page/action mounted while auth opens")
		var status := page.find_child(status_name,true,false) as Label
		_check(status != null and status.visible and status.text.contains("secure window"), kind+" pending status visible")
		_check(button.disabled and button.accessibility_name=="OPENING…", kind+" web pending prevents duplicate starts")
		var board_fetches := int(page.get("fetches")) if kind=="board" else 0
		_state(false,false,"native_auth","Could not connect. Please try again.")
		await _settle()
		_check(not button.disabled and button.accessibility_name=="RETRY SIGN IN",kind+" error changes button to retry")
		_check(status.text=="Could not connect. Please try again.",kind+" error shows authored reason")
		if kind=="board": _check(int(page.get("fetches"))==board_fetches,"auth status alone does not refetch leaderboard")
		_check_caption_fits(button,kind+" retry caption")
		_state(false,false,"","Sign-in cancelled.")
		await _settle()
		_check(not button.disabled and status.text=="Sign-in cancelled.",kind+" cancel status remains visible")
		if kind != "board":
			_state(true,false,"","Connected.")
			await _settle()
			_check(button.accessibility_name=="SIGN OUT" and not button.disabled,kind+" sign-in completion changes action")
			button.pressed.emit()
			await _settle()
			_check(not LeaderboardClient.signed_in and is_instance_valid(button),kind+" sign-out preserves page and updates state")
		page.free()
		await get_tree().process_frame
	viewport.free()

func _state(signed_in: bool,pending: bool,error: String,status: String) -> void:
	LeaderboardClient.signed_in=signed_in
	LeaderboardClient.sign_in_pending=pending
	LeaderboardClient.auth_error=error
	LeaderboardClient.auth_status=status
	LeaderboardClient.auth_changed.emit()

func _check_caption_fits(button: Button, context: String) -> void:
	var row := button.get_node_or_null("IllustratedAction") as Control
	if row != null:
		_check(row.get_combined_minimum_size().x <= button.size.x+1.0,context+" fits illustrated button")
	else:
		var width := button.get_theme_font("font").get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,button.get_theme_font_size("font_size")).x
		_check(width <= button.size.x+1.0,context+" fits button")

func _settle() -> void:
	for frame: int in 6: await get_tree().process_frame

func _check(ok: bool,description: String) -> void:
	_checks+=1
	_failed+=int(not ok)
	print("[account-auth-ui] %s %s" % ["PASS" if ok else "FAIL",description])
