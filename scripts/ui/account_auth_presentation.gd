class_name AccountAuthPresentation
extends RefCounted
## One pending/cancel/retry contract for account surfaces. Provider error codes
## are never shown; native status strings are authored by NativeAuthClient.

static func describe(signed_in: bool, pending: bool, error: String,
		status: String, native: bool) -> Dictionary:
	if signed_in:
		return {"caption": "SIGN OUT", "disabled": false, "message": "", "action": "sign_out"}
	if pending:
		return {"caption": "CANCEL SIGN IN" if native else "OPENING…", "disabled": not native,
			"message": status if not status.is_empty() else "Opening secure sign-in…", "action": "cancel"}
	if not error.is_empty():
		return {"caption": "RETRY SIGN IN", "disabled": false,
			"message": status if not status.is_empty() else "Sign-in could not open. Please try again.", "action": "sign_in"}
	return {"caption": "SIGN IN TO BACK UP", "disabled": false, "message": status, "action": "sign_in"}


static func current() -> Dictionary:
	return describe(LeaderboardClient.signed_in, LeaderboardClient.sign_in_pending,
		LeaderboardClient.auth_error, LeaderboardClient.auth_status, GameConfig.native_accounts_enabled())


static func account_surface_enabled() -> bool:
	return account_capability(GameConfig.native_offline_mvp(), GameConfig.native_accounts_enabled())


static func account_capability(offline_edition: bool, native_accounts: bool) -> bool:
	# Account capability does not alter the independent native purchase guard.
	return not offline_edition or native_accounts


static func message(fallback: String = "") -> String:
	var copy := String(current()["message"])
	return fallback if copy.is_empty() else copy


static func update_button(button: Button, initial_caption: String = "SIGN IN TO BACK UP") -> void:
	if not is_instance_valid(button):
		return
	var state := current()
	var caption := String(state["caption"])
	if state["action"] == "sign_in" and LeaderboardClient.auth_error.is_empty():
		caption = initial_caption
	button.disabled = bool(state["disabled"])
	button.accessibility_name = caption
	var illustrated := button.get_node_or_null("IllustratedAction")
	if illustrated != null:
		for child: Node in illustrated.get_children():
			if child is Label:
				(child as Label).text = caption
			elif child is TextureRect:
				(child as TextureRect).visible = not LeaderboardClient.signed_in
	else:
		button.text = caption


static func activate() -> void:
	var state := current()
	if bool(state["disabled"]):
		return
	match String(state["action"]):
		"sign_out": LeaderboardClient.sign_out()
		"cancel": LeaderboardClient.cancel_sign_in()
		"sign_in": LeaderboardClient.sign_in()
