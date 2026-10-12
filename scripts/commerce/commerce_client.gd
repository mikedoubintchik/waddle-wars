extends Node
## Optional cosmetic store. No recurring per-frame commerce work; requests run
## only on shop actions, account changes or return from a purchase screen.
## Server entitlements remain separate from earned cosmetics in old saves.

signal entitlements_changed
signal store_changed
signal status_changed(message: String)
signal checkout_ready(url: String, product_id: String)

const API_BASE: String = "https://waddle-wars-leaderboard.ninjaconsultingllc.workers.dev"
const REQUEST_TIMEOUT: float = 15.0
const NATIVE_OFFLINE_STATUS: String = "This edition has no purchases. Earn cosmetics with fish in Customize."
const DESKTOP_STORE_STATUS: String = "Desktop payments unavailable. Fish unlocks work offline."

var status: String = ""
var busy: bool = false
var store_available: bool = false
var mode: String = ""
var prices: Dictionary = {}
var _owner_id: String = ""
var _cache: Dictionary = {}
var _native_token: String = ""
var _native_user_id: String = ""
var _native: WaddleNativeBilling = null
var _checkout_url: String = ""
var _checkout_product: String = ""
var _checkout_request_id: String = ""
var _last_checkout_product: String = ""
var _request_sequence: int = 0
var _requests: Dictionary = {}
var _native_receipts: Array[Dictionary] = []
var _verifying_native: bool = false
var _native_configured: bool = false
var _native_verification_configured: bool = false
var _session_owner: String = ""
var _session_auth_epoch: int = 0
var _session_generation: int = 0
var _native_signal_connections: Dictionary = {}
var _restore_pending: bool = false
var _restore_enumeration_finished: bool = false
var _restore_reconciling: bool = false


func _ready() -> void:
	set_process(false)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_reload_cache()
	var online := get_node_or_null("/root/LeaderboardClient")
	if online != null:
		online.auth_changed.connect(_on_auth_changed)
	SaveManager.save_loaded.connect(_reload_cache)


func _reload_cache() -> void:
	var value: Variant = SaveManager.get_value("commerce", {})
	_cache = value.duplicate(true) if value is Dictionary else {}
	var context := _auth_context()
	_synchronize_auth_identity(context)
	_owner_id = String(context.get("user_id", _cache.get("last_account", "")))
	if not SaveManager.account_deletion_state(_owner_id).is_empty():
		_owner_id = ""
	entitlements_changed.emit()


func configure_native_session(token: String, user_id: String) -> void:
	# Called by a real native auth integration. Tokens are not saved. The backend
	# still validates the JWT; a local user ID never authorizes a purchase.
	var next_user_id := user_id if not token.is_empty() else ""
	var changed := _native_user_id != next_user_id
	_native_token = token
	_native_user_id = user_id if not token.is_empty() else ""
	if changed:
		_on_auth_changed()


func signed_in() -> bool:
	var context := _auth_context()
	_synchronize_auth_identity(context)
	return not String(context.get("token", "")).is_empty() and not String(context.get("user_id", "")).is_empty()


func clear_offline_account() -> void:
	# Explicit logout removes the offline pointer. Per-account grants remain in
	# separate caches and become visible only after that account signs in again.
	_cache.erase("last_account")
	_owner_id = ""
	SaveManager.set_value("commerce", _cache.duplicate(true))
	entitlements_changed.emit()


func owns_product(product_id: String) -> bool:
	var account := _cached_account()
	return product_id in account.get("product_ids", [])


func owns_cosmetic(cosmetic_id: String) -> bool:
	# Grant lists derive from known product IDs. Never use a client-supplied
	# arbitrary cosmetic list or merge purchase grants into earned unlocks.
	return cosmetic_id in CommerceCatalog.cosmetic_ids(_cached_account().get("product_ids", []))


func localized_price(product_id: String) -> String:
	return String(prices.get(product_id, ""))


func payment_platform_supported() -> bool:
	return not GameConfig.native_offline_mvp() and (OS.has_feature("web") \
		or OS.has_feature("ios") or OS.has_feature("android"))


func can_purchase(product_id: String) -> bool:
	if GameConfig.native_offline_mvp():
		return false
	var authenticated := signed_in()
	if busy or not authenticated or not store_available or CommerceCatalog.product(product_id).is_empty() \
		or owns_product(product_id):
		return false
	if OS.has_feature("web"):
		return not localized_price(product_id).is_empty()
	return _native != null and _native.available(product_id)


func refresh_store() -> void:
	if GameConfig.native_offline_mvp():
		store_available = false
		prices.clear()
		_set_status(NATIVE_OFFLINE_STATUS)
		store_changed.emit()
		return
	var authenticated := signed_in()
	if busy:
		return
	store_available = false
	prices.clear()
	if not authenticated:
		_set_status("Sign in to buy or restore cosmetics. You can still earn every item with fish." if payment_platform_supported() else DESKTOP_STORE_STATUS)
		store_changed.emit()
		return
	busy = true
	_set_status("Checking shop and purchases…")
	_request("GET", "/catalog", {}, func(ok: bool, payload: Dictionary) -> void:
		if not ok:
			busy = false
			_set_status(_error_message(String(payload.get("error", ""))))
			store_changed.emit()
			return
		mode = String(payload.get("mode", ""))
		var native_configuration: Variant = payload.get("native_purchase_configured", {})
		var provider := "google" if OS.has_feature("android") else "apple"
		_native_configured = native_configuration is Dictionary and bool(native_configuration.get(provider, false))
		var verification: Variant = payload.get("native_verification_configured", {})
		_native_verification_configured = verification is Dictionary and bool(verification.get(provider, false))
		if OS.has_feature("web"):
			store_available = bool(payload.get("web_checkout_configured", false))
			for raw: Variant in payload.get("products", []):
				if raw is Dictionary and not CommerceCatalog.product(String(raw.get("id", ""))).is_empty():
					prices[String(raw["id"])] = "$%.2f USD" % (float(raw.get("price_minor", 0)) / 100.0)
		_refresh_entitlements(func(synced: bool) -> void:
			busy = false
			if not synced:
				store_available = false
				store_changed.emit()
				return
			if not payment_platform_supported():
				_set_status("Verified purchases synced. Payments are unavailable on desktop; fish unlocks work offline.")
			elif not OS.has_feature("web") and _native_verification_configured:
				_prepare_native()
			elif not OS.has_feature("web"):
				_set_status("Shop is not open yet. Earn these items with fish.")
			else:
				_set_status("Cosmetics only · one-time purchases" if store_available else "Shop is not open yet. Earn these items with fish.")
			store_changed.emit()))


func purchase(product_id: String) -> void:
	if GameConfig.native_offline_mvp():
		_set_status(NATIVE_OFFLINE_STATUS)
		return
	if not can_purchase(product_id):
		_set_status("Purchase unavailable. Refresh the shop or restore your purchases.")
		return
	if not OS.has_feature("web"):
		busy = true
		_set_status("Checking purchase availability…")
		var provider := "google" if OS.has_feature("android") else "apple"
		_request("POST", "/prepare-native-purchase", {"provider": provider, "product_id": product_id},
			func(ok: bool, payload: Dictionary) -> void:
				if not ok or not bool(payload.get("approved", false)) or String(payload.get("product_id", "")) != product_id \
					or String(payload.get("provider", "")) != provider or _native == null or not _native.available(product_id):
					busy = false
					_set_status(_error_message(String(payload.get("error", "native_sales_unavailable"))))
					store_changed.emit()
					return
				_set_status("Complete your purchase in the store.")
				_native.purchase(product_id)
				store_changed.emit())
		store_changed.emit()
		return
	busy = true
	_checkout_url = ""
	_checkout_product = ""
	if _checkout_request_id.is_empty() or _last_checkout_product != product_id:
		_checkout_request_id = _uuid_v4()
		_last_checkout_product = product_id
	_set_status("Preparing secure checkout…")
	_request("POST", "/checkout", {"platform": "web", "product_id": product_id,
		"request_id": _checkout_request_id}, func(ok: bool, payload: Dictionary) -> void:
		busy = false
		if not ok:
			_set_status(_error_message(String(payload.get("error", ""))))
			if String(payload.get("error", "")) in ["checkout_closed", "already_owned"]:
				_checkout_request_id = ""
			store_changed.emit()
			return
		var url := String(payload.get("checkout_url", ""))
		# A server response still cannot open arbitrary application URLs.
		if not url.begins_with("https://checkout.stripe.com/") or String(payload.get("product_id", "")) != product_id:
			_set_status("Checkout unavailable. Try again.")
			store_changed.emit()
			return
		_checkout_url = url
		_checkout_product = product_id
		_set_status("Checkout ready. Continue to Stripe, then return here to refresh your purchases.")
		checkout_ready.emit(url, product_id)
		store_changed.emit())


func checkout_prepared_for(product_id: String) -> bool:
	return not _checkout_url.is_empty() and _checkout_product == product_id


func open_checkout(product_id: String) -> void:
	# Called by a second, direct user tap so popup policies retain user gesture.
	if not OS.has_feature("web") or not checkout_prepared_for(product_id):
		return
	OS.shell_open(_checkout_url)
	_set_status("After payment, return here and tap Refresh purchases. Payment alone does not unlock items until verified.")


func restore_purchases() -> void:
	if GameConfig.native_offline_mvp():
		_set_status(NATIVE_OFFLINE_STATUS)
		return
	var authenticated := signed_in()
	if busy:
		return
	if not authenticated:
		_set_status("Sign in to the account used for your purchase, then restore.")
		return
	if OS.has_feature("web"):
		refresh_store()
	elif _native != null:
		_restore_pending = true
		_restore_enumeration_finished = false
		_restore_reconciling = false
		busy = true
		_set_status("Checking store purchases…")
		_native.restore()
	else:
		refresh_store()


func _prepare_native() -> void:
	# Account switching must not expose an old adapter's prices while the new
	# server account binding is still loading. Purchase requires busy == false.
	busy = true
	_request("GET", "/account", {}, func(ok: bool, payload: Dictionary) -> void:
		busy = false
		if not ok or not payload.get("bindings", {}) is Dictionary:
			_set_status("Could not connect your account to the store. Try again.")
			store_changed.emit()
			return
		if _native == null:
			var adapter := _new_native_adapter()
			var generation := _session_generation
			_native = adapter
			add_child(adapter)
			_native_signal_connections["products_changed"] = func() -> void:
				if not _native_callback_current(adapter, generation):
					return
				prices = adapter.prices.duplicate()
				store_available = _native_configured and not prices.is_empty()
				_set_status("Cosmetics only · one-time purchases" if store_available else "Shop is not open yet. Restore purchases or earn items with fish.")
				store_changed.emit()
			_native_signal_connections["failed"] = func(message: String) -> void:
				if not _native_callback_current(adapter, generation):
					return
				if not _restore_reconciling:
					_restore_pending = false
					_restore_enumeration_finished = false
				busy = _verifying_native or _restore_reconciling or not _native_receipts.is_empty()
				_set_status(message)
				store_changed.emit()
			_native_signal_connections["receipt_received"] = func(provider: String, product_id: String, receipt: Dictionary) -> void:
				if _native_callback_current(adapter, generation):
					_on_native_receipt(provider, product_id, receipt)
			_native_signal_connections["restore_finished"] = func() -> void:
				if not _native_callback_current(adapter, generation):
					return
				if _restore_pending:
					_restore_enumeration_finished = true
					_reconcile_native_restore_if_ready()
			for signal_name: String in _native_signal_connections:
				adapter.connect(signal_name, _native_signal_connections[signal_name])
		_native.start(payload["bindings"]))


func _new_native_adapter() -> WaddleNativeBilling:
	return WaddleNativeBilling.new()


func _native_callback_current(adapter: WaddleNativeBilling, generation: int) -> bool:
	_synchronize_auth_identity(_auth_context())
	return generation == _session_generation and adapter == _native and not _session_owner.is_empty()


func _on_native_receipt(provider: String, product_id: String, receipt: Dictionary) -> void:
	if not signed_in():
		return
	var entry := receipt.duplicate()
	entry["provider"] = provider
	entry["product_id"] = product_id
	_native_receipts.append(entry)
	_verify_next_native_receipt()


func _verify_next_native_receipt() -> void:
	var authenticated := signed_in()
	if _verifying_native or _restore_reconciling or _native_receipts.is_empty():
		return
	if not authenticated:
		busy = false
		_set_status("Sign in to verify and restore this purchase.")
		return
	_verifying_native = true
	busy = true
	var receipt: Dictionary = _native_receipts.pop_front()
	_set_status("Verifying your purchase…")
	_request("POST", "/verify", receipt, func(ok: bool, payload: Dictionary) -> void:
		_verifying_native = false
		busy = _restore_pending
		if ok and _accept_entitlements(payload):
			if _native != null:
				_native.finish_verified(receipt)
			_set_status("Purchase restored." if String(payload.get("state", "")) == "active" else "Purchase no longer active.")
		else:
			# Platform transactions remain unfinished and replay on restore. No
			# local success shortcut or acknowledgment on failed verification.
			_set_status(_error_message(String(payload.get("error", ""))))
		store_changed.emit()
		_verify_next_native_receipt()
		_reconcile_native_restore_if_ready())


func _reconcile_native_restore_if_ready() -> void:
	if not _restore_pending or not _restore_enumeration_finished or _restore_reconciling \
			or _verifying_native or not _native_receipts.is_empty():
		return
	_restore_reconciling = true
	busy = true
	_set_status("Refreshing verified purchases…")
	_request("GET", "/entitlements", {}, func(ok: bool, payload: Dictionary) -> void:
		_restore_pending = false
		_restore_enumeration_finished = false
		_restore_reconciling = false
		busy = false
		# Empty native enumeration is not proof of a refund. Only a validated
		# authoritative account snapshot can revoke cached purchase grants.
		if ok and _accept_entitlements(payload):
			_set_status("Store purchases checked.")
		else:
			_set_status("Could not refresh verified purchases. Previous verified purchases remain unchanged; try again.")
		# A store event may arrive while this snapshot is pending. It was queued,
		# never verified concurrently, so this older snapshot cannot overwrite a
		# newer grant. Start its verification only after the snapshot is applied.
		_verify_next_native_receipt()
		store_changed.emit())


func _refresh_entitlements(done: Callable) -> void:
	_request("GET", "/entitlements", {}, func(ok: bool, payload: Dictionary) -> void:
		var accepted := ok and _accept_entitlements(payload)
		if not accepted:
			_set_status(_error_message(String(payload.get("error", ""))))
		done.call(accepted))


func _accept_entitlements(payload: Dictionary) -> bool:
	if _owner_id.is_empty() or not SaveManager.account_deletion_state(_owner_id).is_empty() \
		or not payload.get("product_ids") is Array:
		return false
	var ids: Array[String] = []
	for value: Variant in payload["product_ids"]:
		if not value is String or CommerceCatalog.product(String(value)).is_empty():
			return false
		if not ids.has(String(value)):
			ids.append(String(value))
	ids.sort()
	var raw_accounts: Variant = _cache.get("accounts", {})
	var accounts: Dictionary = raw_accounts if raw_accounts is Dictionary else {}
	accounts[_owner_id] = {"product_ids": ids, "verified_at": String(payload.get("verified_at", ""))}
	_cache["accounts"] = accounts
	_cache["last_account"] = _owner_id
	SaveManager.set_value("commerce", _cache.duplicate(true))
	entitlements_changed.emit()
	return true


func _cached_account() -> Dictionary:
	if not SaveManager.account_deletion_journal_available() \
		or not SaveManager.account_deletion_state(_owner_id).is_empty():
		return {}
	var accounts: Variant = _cache.get("accounts", {})
	if not accounts is Dictionary:
		return {}
	var account: Variant = accounts.get(_owner_id, {})
	if not account is Dictionary or not account.get("product_ids") is Array:
		return {}
	var ids: Array[String] = []
	for id: Variant in account["product_ids"]:
		if id is String and not CommerceCatalog.product(String(id)).is_empty() and not ids.has(String(id)):
			ids.append(String(id))
	return {"product_ids": ids}


func _auth_context() -> Dictionary:
	if OS.has_feature("web"):
		var online := get_node_or_null("/root/LeaderboardClient")
		if online == null or not bool(online.get("signed_in")):
			return {}
		var token := String(online.get("_token"))
		var parts := token.split(".")
		if parts.size() != 3:
			return {}
		var encoded := parts[1].replace("-", "+").replace("_", "/")
		while encoded.length() % 4 != 0:
			encoded += "="
		var payload: Variant = JSON.parse_string(Marshalls.base64_to_utf8(encoded))
		if not payload is Dictionary or not payload.get("sub") is String:
			return {}
		# Decoding selects the local cache only. JWT verification is server-side.
		if not SaveManager.account_deletion_state(String(payload["sub"])).is_empty():
			return {}
		return {"token": token, "user_id": String(payload["sub"]),
			"session_epoch": int(online.get("_auth_generation"))}
	return {"token": _native_token, "user_id": _native_user_id} \
		if not _native_token.is_empty() and SaveManager.account_deletion_state(_native_user_id).is_empty() else {}


func _on_auth_changed() -> void:
	_synchronize_auth_identity(_auth_context())


func _synchronize_auth_identity(context: Dictionary) -> void:
	var owner := String(context.get("user_id", "")) if not String(context.get("token", "")).is_empty() else ""
	var auth_epoch := int(context.get("session_epoch", 0))
	if owner == _session_owner and auth_epoch == _session_auth_epoch:
		return
	_session_owner = owner
	_session_auth_epoch = auth_epoch
	_session_generation += 1
	_owner_id = owner
	# A cancelled request never runs its old callback against replacement UI.
	# Same-owner token refresh retains this epoch and valid in-flight work.
	_requests.clear()
	busy = false
	_verifying_native = false
	_restore_pending = false
	_restore_enumeration_finished = false
	_restore_reconciling = false
	# Clear only local pending work. Unverified platform transactions remain
	# unfinished and can be replayed by their legitimate owner's restore.
	_native_receipts.clear()
	var retired_adapter := _native
	_native = null
	if is_instance_valid(retired_adapter):
		for signal_name: String in _native_signal_connections:
			var connection: Callable = _native_signal_connections[signal_name]
			if retired_adapter.is_connected(signal_name, connection):
				retired_adapter.disconnect(signal_name, connection)
		retired_adapter.queue_free()
	_native_signal_connections.clear()
	_checkout_url = ""
	_checkout_product = ""
	_checkout_request_id = ""
	_last_checkout_product = ""
	_native_configured = false
	_native_verification_configured = false
	mode = ""
	store_available = false
	prices.clear()
	_set_status("Shop account changed. Refresh purchases." if not owner.is_empty() else "Sign in to buy or restore cosmetics. You can still earn every item with fish.")
	if OS.has_feature("web") and _owner_id.is_empty():
		_cache.erase("last_account")
		SaveManager.set_value("commerce", _cache.duplicate(true))
	entitlements_changed.emit()
	store_changed.emit()
	# No network or billing initialization during gameplay. Shop refresh is an
	# explicit action; login updates ownership cache without touching renderer.


func _request(method: String, path: String, body: Dictionary, callback: Callable) -> void:
	var context := _auth_context()
	_synchronize_auth_identity(context)
	var token := String(context.get("token", ""))
	var owner := String(context.get("user_id", ""))
	if token.is_empty() or owner.is_empty():
		callback.call(false, {"error": "unauthorized"})
		return
	_owner_id = owner
	_request_sequence += 1
	var sequence := _request_sequence
	var generation := _session_generation
	_requests[sequence] = callback
	var complete := func(ok: bool, payload: Dictionary) -> void:
		var current_context := _auth_context()
		_synchronize_auth_identity(current_context)
		if generation != _session_generation or not _requests.has(sequence):
			return
		_requests.erase(sequence)
		if String(current_context.get("user_id", "")) != owner:
			return
		callback.call(ok, payload)
	_dispatch_request(method, path, body, token, complete)


func _dispatch_request(method: String, path: String, body: Dictionary, token: String, complete: Callable) -> void:
	# Narrow transport seam: fixtures capture completion without network/timers,
	# while exercising the production identity and exactly-once guard above.
	var timer := get_tree().create_timer(REQUEST_TIMEOUT, true)
	timer.timeout.connect(func() -> void: complete.call(false, {"error": "network_unavailable"}))
	var base := String(ProjectSettings.get_setting("commerce/api_base", API_BASE)).trim_suffix("/")
	if not base.begins_with("https://"):
		complete.call(false, {"error": "store_unavailable"})
		return
	var text := JSON.stringify(body) if not body.is_empty() else ""
	if OS.has_feature("web"):
		var online := get_node_or_null("/root/LeaderboardClient")
		if online == null:
			complete.call(false, {"error": "network_unavailable"})
			return
		online.call("_request", method, "%s/api/commerce%s" % [base, path], text, complete)
	else:
		var http := HTTPRequest.new()
		http.timeout = 12.0
		add_child(http)
		http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, bytes: PackedByteArray) -> void:
			http.queue_free()
			var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
			var payload: Dictionary = parsed if parsed is Dictionary else {"error": "network_unavailable"}
			complete.call(result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300, payload))
		var headers := PackedStringArray(["Authorization: Bearer %s" % token, "Content-Type: application/json"])
		var error := http.request("%s/api/commerce%s" % [base, path], headers,
			HTTPClient.METHOD_POST if method == "POST" else HTTPClient.METHOD_GET, text)
		if error != OK:
			http.queue_free()
			complete.call(false, {"error": "network_unavailable"})


func _set_status(message: String) -> void:
	status = message
	status_changed.emit(message)


static func _uuid_v4() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 15) | 64
	bytes[8] = (bytes[8] & 63) | 128
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]


static func _error_message(code: String) -> String:
	match code:
		"unauthorized": return "Sign in to the account used for this purchase."
		"already_owned": return "You already own this bundle. Refresh purchases to restore it."
		"purchase_pending": return "Payment pending. Items unlock after payment completes."
		"purchase_already_linked": return "This purchase belongs to another game account. Sign in to that account."
		"store_unavailable", "stripe_unavailable", "checkout_unavailable", "store_verifier_unavailable", "native_sales_unavailable":
			return "Shop is not open yet. Every cosmetic can still be earned with fish."
		"invalid_purchase", "purchase_verification_failed": return "Purchase could not be verified. Restore purchases or contact support."
		_: return "Could not reach online purchases. Fish unlocks still work. Try online purchases again later."
