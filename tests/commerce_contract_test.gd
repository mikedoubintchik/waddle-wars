extends Node
## Run only from an isolated user:// fixture. Backend trust is tested separately
## with real SQLite and cryptographic verification; this tests game integration.

const AuthScript = preload("res://scripts/commerce/native_auth_client.gd")

class BillingFixture extends WaddleNativeBilling:
	var verified: Array[Dictionary] = []
	var purchases: Array[String] = []
	var restore_calls: int = 0
	func start(bindings: Dictionary) -> void:
		provider = "apple"
		_bindings = bindings.duplicate()
	func available(product_id: String) -> bool:
		return not String(prices.get(product_id, "")).is_empty() and not String(_bindings.get("apple", "")).is_empty()
	func purchase(product_id: String) -> void:
		purchases.append(product_id)
	func restore() -> void:
		restore_calls += 1
	func finish_verified(receipt: Dictionary) -> void:
		verified.append(receipt.duplicate(true))

class CommerceFixture:
	extends "res://scripts/commerce/commerce_client.gd"
	var auth: Dictionary = {}
	var dispatched: Array[Dictionary] = []
	var adapters: Array[BillingFixture] = []
	func _ready() -> void:
		set_process(false)
	func _auth_context() -> Dictionary:
		return auth.duplicate()
	func set_identity(owner: String, token: String = "fixture-token", notify: bool = true) -> void:
		auth = {"user_id": owner, "token": token} if not owner.is_empty() else {}
		if notify:
			_on_auth_changed()
	func _dispatch_request(method: String, path: String, body: Dictionary, token: String, complete: Callable) -> void:
		# No timers, HTTP, billing plugin or auth bridge. Capture the actual
		# production _request completion guard, not a substitute callback guard.
		dispatched.append({"method": method, "path": path, "body": body.duplicate(true),
			"token": token, "owner": String(auth.get("user_id", "")), "complete": complete})
	func deliver(index: int, ok: bool, payload: Dictionary) -> void:
		var complete: Callable = dispatched[index]["complete"]
		complete.call(ok, payload)
	func _new_native_adapter() -> WaddleNativeBilling:
		var adapter := BillingFixture.new()
		adapters.append(adapter)
		return adapter
	func dispose() -> void:
		_requests.clear()
		dispatched.clear()
		adapters.clear()
		queue_free()

class IOSAuthFixture extends RefCounted:
	signal auth_session_started(request_id: String)
	signal auth_session_finished(request_id: String, outcome: String)
	signal auth_session_authorized(request_id: String, callback_code: String)
	var ended: Array[String] = []
	func begin_auth_session(_authorize_url: String, _request_id: String) -> void:
		pass
	func end_auth_session(request_id: String) -> void:
		ended.append(request_id)
		# Native cancellation may be synchronous; runtime guards must reject it.
		auth_session_finished.emit(request_id, "cancelled")

var _passed: int = 0
var _failed: int = 0
var _saved_data: Dictionary
var _saved_cache: Dictionary
var _earned: Array
var _saved_unlock_stream: Variant
var _saved_unlock_one_shot: Variant


func _ready() -> void:
	_saved_data = SaveManager.data.duplicate(true)
	_saved_cache = CommerceClient._cache.duplicate(true)
	SaveManager.data = SaveManager.default_save()
	CommerceClient._cache = {}
	CommerceClient.configure_native_session("fixture-token", "fixture-account-one")
	# This fixture covers entitlement/save logic, not AudioServer playback.
	# Remove only its incidental unlock sound through the existing library seam;
	# otherwise the headless dummy mixer retains a WAV playback at immediate exit.
	_saved_unlock_stream = AudioManager._library.get("sfx_unlock")
	_saved_unlock_one_shot = AudioManager._one_shot_cache.get("sfx_unlock")
	AudioManager._library.erase("sfx_unlock")
	AudioManager._one_shot_cache.erase("sfx_unlock")
	_test_earned_and_purchase_overlay()
	_test_account_switch_and_offline_cache()
	_test_invalid_data_and_old_save()
	_test_in_flight_account_races()
	_test_native_account_races()
	_test_native_restore_reconciliation()
	_test_native_events_are_receipts_only()
	_test_native_auth_cancellation()
	_test_ios_auth_presentation()
	SaveManager.data = _saved_data
	CommerceClient._cache = _saved_cache
	CommerceClient.configure_native_session("", "")
	if _saved_unlock_stream != null:
		AudioManager._library["sfx_unlock"] = _saved_unlock_stream
	if _saved_unlock_one_shot != null:
		AudioManager._one_shot_cache["sfx_unlock"] = _saved_unlock_one_shot
	# A fixture cannot free itself while dispose() is on its call stack. Let
	# queued fixture/retired-adapter disposal finish before immediate test exit.
	await get_tree().process_frame
	await get_tree().process_frame
	print("[commerce_contract] DONE: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _test_earned_and_purchase_overlay() -> void:
	SaveManager.set_value("fish", int(CosmeticsDB.get_item("hat_beanie")["cost"]))
	_check("earned_hat_unlock", Progression.try_unlock_cosmetic("hat_beanie"))
	_earned = Progression.unlocked_cosmetics().duplicate()
	var fish_before := Progression.get_fish()
	_check("verified_bundle_accepted", CommerceClient._accept_entitlements({"product_ids": ["cozy_expedition"], "verified_at": "fixture"}))
	_check("purchase_grants_named_items", Progression.is_cosmetic_unlocked("scarf_red")
		and Progression.is_cosmetic_unlocked("trail_snowflake"))
	_check("purchase_does_not_grant_unrelated_items", not Progression.is_cosmetic_unlocked("hat_crown"))
	_check("earned_list_unchanged", Progression.unlocked_cosmetics() == _earned)
	_check("fish_unchanged", Progression.get_fish() == fish_before)
	Progression.equip("scarf", "scarf_red")
	Progression.equip("hat", "hat_beanie")
	_check("purchased_cosmetic_equip", Progression.get_equipped("scarf") == "scarf_red")
	_check("verified_refund_snapshot_accepted", CommerceClient._accept_entitlements({"product_ids": [], "verified_at": "refund"}))
	_check("refunded_unearned_cosmetics_revoked", not Progression.is_cosmetic_unlocked("scarf_red"))
	_check("refund_preserves_earned_hat", Progression.is_cosmetic_unlocked("hat_beanie")
		and Progression.get_equipped("hat") == "hat_beanie")
	_check("refund_runtime_equip_falls_back", Progression.get_equipped("scarf") == "")
	_check("refund_keeps_raw_equipped_save", SaveManager.get_value("equipped", {}).get("scarf") == "scarf_red")
	_check("refund_keeps_earned_list", Progression.unlocked_cosmetics() == _earned)


func _test_account_switch_and_offline_cache() -> void:
	CommerceClient._accept_entitlements({"product_ids": ["research_crew"], "verified_at": "fixture"})
	_check("first_account_owns_research", CommerceClient.owns_cosmetic("hat_headset"))
	CommerceClient.configure_native_session("other-fixture-token", "fixture-account-two")
	_check("second_account_no_first_account_grants", not CommerceClient.owns_cosmetic("hat_headset"))
	CommerceClient._accept_entitlements({"product_ids": ["aurora_celebration"], "verified_at": "fixture"})
	_check("second_account_own_grants", CommerceClient.owns_cosmetic("hat_crown"))
	CommerceClient.configure_native_session("fixture-token", "fixture-account-one")
	_check("switch_back_restores_separate_cache", CommerceClient.owns_cosmetic("hat_headset")
		and not CommerceClient.owns_cosmetic("hat_crown"))
	var saved_cache: Dictionary = SaveManager.get_value("commerce", {}).duplicate(true)
	saved_cache["last_account"] = "fixture-account-one"
	SaveManager.set_value("commerce", saved_cache)
	CommerceClient.configure_native_session("", "")
	_check("sign_out_hides_account_grants", not CommerceClient.owns_cosmetic("hat_headset"))
	CommerceClient._reload_cache()
	_check("offline_resume_remembers_last_verified_account", CommerceClient.owns_cosmetic("hat_headset"))
	_check("offline_resume_cannot_purchase", not CommerceClient.can_purchase("aurora_celebration"))
	CommerceClient.clear_offline_account()
	CommerceClient._reload_cache()
	_check("explicit_logout_no_offline_restore", not CommerceClient.owns_cosmetic("hat_headset"))
	_check("commerce_no_frame_processing", not CommerceClient.is_processing())
	CommerceClient.configure_native_session("fixture-token", "fixture-account-one")
	CommerceClient._cache = {}
	CommerceClient._accept_entitlements({"product_ids": ["cozy_expedition"], "verified_at": "fixture"})
	CommerceClient.store_available = true
	CommerceClient.configure_native_session("fresh-short-lived-token", "fixture-account-one")
	_check("token_refresh_preserves_shop_state", CommerceClient.store_available)


func _test_invalid_data_and_old_save() -> void:
	var before := CommerceClient._cache.duplicate(true)
	_check("unknown_product_rejected", not CommerceClient._accept_entitlements({"product_ids": ["free_all_cosmetics"]}))
	_check("arbitrary_cosmetic_list_not_a_grant", not CommerceClient._accept_entitlements({"cosmetic_ids": ["hat_crown"]}))
	_check("rejected_data_keeps_cache", CommerceClient._cache == before)
	CommerceClient._cache = {"accounts": {"fixture-account-one": {"product_ids": "bad"}}}
	_check("malformed_cache_fails_closed", not CommerceClient.owns_cosmetic("hat_crown"))
	var old_save := {"version": 1, "fish": 777, "unlocked_cosmetics": ["body_classic", "hat_beanie"],
		"equipped": {"body": "body_classic", "hat": "hat_beanie"}, "custom_legacy_key": {"keep": true}}
	SaveManager.adopt_cloud_save(old_save)
	_check("legacy_fish_preserved", Progression.get_fish() == 777)
	_check("legacy_unlocks_preserved", Progression.is_cosmetic_unlocked("hat_beanie"))
	_check("legacy_optional_field_preserved", SaveManager.get_value("custom_legacy_key", {}).get("keep", false))
	_check("legacy_save_no_phantom_paid_grants", not CommerceClient.owns_cosmetic("hat_crown"))


func _test_native_events_are_receipts_only() -> void:
	# This case starts without paid ownership. Cloud adoption now correctly
	# preserves prior local verified purchases; do not rely on the preceding
	# legacy-save case to erase them as an incidental fixture reset.
	_check("native_receipt_fixture_starts_without_paid_grants",
		CommerceClient._accept_entitlements({"product_ids": [], "verified_at": "fixture-empty"})
		and not Progression.is_cosmetic_unlocked("scarf_red"))
	var prior_cache := CommerceClient._cache.duplicate(true)
	var billing := WaddleNativeBilling.new()
	var receipts: Array[Dictionary] = []
	var errors: Array[String] = []
	billing.receipt_received.connect(func(provider: String, id: String, receipt: Dictionary) -> void:
		receipts.append({"provider": provider, "id": id, "receipt": receipt}))
	billing.failed.connect(func(message: String) -> void: errors.append(message))
	var store_id := "com.blubberandbyte.waddlewars.cozy_expedition"
	billing._on_apple_purchase({"state": "pending", "product_id": store_id})
	_check("pending_no_receipt", receipts.is_empty())
	billing._on_apple_purchase({"state": "cancelled", "product_id": store_id})
	_check("cancelled_no_receipt", receipts.is_empty() and errors.back() == "Purchase cancelled.")
	billing._on_apple_purchase({"state": "purchased", "product_id": store_id, "transaction_id": "200000000000001"})
	_check("purchased_emits_verification_receipt", receipts.size() == 1 and receipts[0]["id"] == "cozy_expedition")
	billing._on_apple_purchase({"state": "refunded", "product_id": store_id, "transaction_id": "200000000000001"})
	_check("refunded_receipt_reconciles_server", receipts.size() == 2)
	_check("native_event_does_not_unlock_locally", not Progression.is_cosmetic_unlocked("scarf_red"))
	_check("native_events_leave_verified_cache_unchanged", CommerceClient._cache == prior_cache)
	billing._on_google_purchases({"response_code": 0, "purchases": [{"purchase_state": 2, "product_ids": [store_id]}]})
	_check("google_pending_no_receipt", receipts.size() == 2)
	billing._on_google_products({"response_code": 0, "product_details": [{"product_id": store_id,
		"one_time_purchase_offer_details_list": [{"formatted_price": "$0.50 rental", "offer_id": null, "purchase_option_id": "rent", "rental_details": {"rental_period": "P1D"}},
			{"formatted_price": "$1 promotional", "offer_id": "sale", "purchase_option_id": "sale"},
			{"formatted_price": "$2.99", "offer_id": null, "purchase_option_id": "buy"}]}]})
	_check("native_price_uses_base_platform_offer", billing.prices.get("cozy_expedition") == "$2.99"
		and billing._details.get("cozy_expedition", {}).get("purchase_option_id") == "buy")
	billing._on_google_products({"response_code": 0, "product_details": [{"product_id": store_id,
		"one_time_purchase_offer_details_list": [{"formatted_price": "$0.50 rental", "offer_id": null,
			"purchase_option_id": "rent", "rental_details": {"rental_period": "P1D"}}]}]})
	_check("rental_only_product_never_exposes_permanent_cosmetic_price", billing.prices.is_empty() and billing._details.is_empty())
	billing.free()


func _client_fixture(owner: String) -> CommerceFixture:
	var client := CommerceFixture.new()
	add_child(client)
	client.set_identity(owner)
	return client


func _catalog_fixture() -> Dictionary:
	return {"mode": "test", "web_checkout_configured": true,
		"native_purchase_configured": {"apple": false, "google": false},
		"native_verification_configured": {"apple": false, "google": false}, "products": []}


func _prepare_fixture_adapter(client: CommerceFixture) -> BillingFixture:
	client._native_configured = true
	client._native_verification_configured = true
	client._prepare_native()
	client.deliver(client.dispatched.size() - 1, true, {"bindings": {"apple": "binding-" + String(client.auth["user_id"])}})
	var adapter: BillingFixture = client.adapters.back()
	adapter.prices = {"cozy_expedition": "$2.99", "aurora_celebration": "$2.99"}
	adapter.products_changed.emit()
	return adapter


func _test_in_flight_account_races() -> void:
	var client := _client_fixture("request-account-A")
	client.refresh_store()
	_check("pending_refresh_captured_without_network", client.busy and client.dispatched.size() == 1
		and client.dispatched[0]["path"] == "/catalog" and client._requests.size() == 1)
	client.set_identity("request-account-B", "token-B")
	_check("identity_switch_immediately_cancels_busy_requests", not client.busy and client._requests.is_empty()
		and not client.store_available and client.prices.is_empty())
	client.refresh_store()
	var new_status := client.status
	_check("replacement_account_can_refresh_immediately", client.busy and client.dispatched.size() == 2
		and client.dispatched[1]["owner"] == "request-account-B")
	client.deliver(0, false, {"error": "unauthorized"})
	client.deliver(0, true, _catalog_fixture())
	_check("old_response_and_timeout_leave_new_busy_status_untouched", client.busy
		and client.status == new_status and client.dispatched.size() == 2 and client._requests.size() == 1)
	client.deliver(1, true, _catalog_fixture())
	_check("new_refresh_follows_entitlement_request", client.dispatched.size() == 3
		and client.dispatched[2]["path"] == "/entitlements")
	client.deliver(2, true, {"product_ids": ["aurora_celebration"], "verified_at": "B-current"})
	_check("new_account_snapshot_accepted_without_old_grants", not client.busy
		and client.owns_product("aurora_celebration") and not client.owns_product("cozy_expedition"))
	client.dispose()

	client = _client_fixture("return-account-A")
	var completions := {"old": 0, "new": 0, "refresh": 0, "timeout": 0}
	client._refresh_entitlements(func(_accepted: bool) -> void: completions["old"] += 1)
	var old_generation := client._session_generation
	client.set_identity("return-account-B")
	client.set_identity("return-account-A", "token-A-new")
	client._refresh_entitlements(func(_accepted: bool) -> void: completions["new"] += 1)
	client.deliver(1, true, {"product_ids": ["aurora_celebration"], "verified_at": "A-new"})
	var new_cache := client._cache.duplicate(true)
	var current_status := client.status
	client.deliver(0, true, {"product_ids": ["cozy_expedition"], "verified_at": "A-old"})
	_check("return_to_same_owner_rejects_old_generation", client._session_generation > old_generation
		and completions["old"] == 0 and completions["new"] == 1
		and client._cache == new_cache and client.status == current_status)
	var current_generation := client._session_generation
	client.store_available = true
	client.prices = {"research_crew": "$2.99"}
	client._refresh_entitlements(func(_accepted: bool) -> void: completions["refresh"] += 1)
	client.set_identity("return-account-A", "token-A-refreshed")
	_check("same_owner_refresh_keeps_epoch_prices_and_pending_request", client._session_generation == current_generation
		and client.store_available and client.prices.has("research_crew") and client._requests.size() == 1)
	client.deliver(2, true, {"product_ids": ["research_crew"], "verified_at": "A-refreshed"})
	_check("same_owner_refresh_retains_valid_entitlement_completion", completions["refresh"] == 1
		and client.owns_product("research_crew"))
	client._request("GET", "/fixture", {}, func(_ok: bool, _payload: Dictionary) -> void: completions["timeout"] += 1)
	client.deliver(3, false, {"error": "network_unavailable"})
	client.deliver(3, true, {})
	client.deliver(3, false, {"error": "network_unavailable"})
	_check("timeout_and_response_complete_exactly_once", completions["timeout"] == 1 and client._requests.is_empty())
	client.dispose()

	client = _client_fixture("silent-account-A")
	client._accept_entitlements({"product_ids": ["cozy_expedition"]})
	client.refresh_store()
	client.set_identity("silent-account-B", "silent-token-B", false)
	client.refresh_store()
	_check("eligibility_sync_detects_identity_before_upstream_poll", client.dispatched.size() == 2
		and client.dispatched[1]["owner"] == "silent-account-B" and client.busy
		and not client.owns_product("cozy_expedition"))
	client.deliver(0, true, _catalog_fixture())
	_check("silent_switch_old_completion_cannot_start_followup", client.dispatched.size() == 2 and client.busy)
	client.set_identity("")
	var signout_status := client.status
	client.deliver(1, false, {"error": "network_unavailable"})
	_check("signout_immediately_clears_pending_work_without_stale_status", not client.busy
		and client._requests.is_empty() and client.status == signout_status)
	client.dispose()

	client = _client_fixture("bridge-return-account-A")
	var bridge_completions := {"old": 0, "new": 0}
	client._refresh_entitlements(func(_accepted: bool) -> void: bridge_completions["old"] += 1)
	var before_epoch := client._session_generation
	# Page observed A -> B -> A between game polls. Owner stayed A at both
	# polls, but upstream identity epoch reveals the intervening session change.
	client.auth["session_epoch"] = 7
	client._on_auth_changed()
	client._refresh_entitlements(func(_accepted: bool) -> void: bridge_completions["new"] += 1)
	client.deliver(1, true, {"product_ids": ["research_crew"], "verified_at": "new-epoch"})
	var epoch_cache := client._cache.duplicate(true)
	client.deliver(0, true, {"product_ids": ["cozy_expedition"], "verified_at": "old-epoch"})
	_check("web_bridge_epoch_rejects_unobserved_roundtrip_to_same_owner", client._session_generation > before_epoch
		and bridge_completions["old"] == 0 and bridge_completions["new"] == 1 and client._cache == epoch_cache)
	client.dispose()


func _test_native_account_races() -> void:
	var client := _client_fixture("native-account-A")
	var old_adapter := _prepare_fixture_adapter(client)
	var queued_signals := client._native_signal_connections.duplicate()
	old_adapter.receipt_received.emit("apple", "cozy_expedition", {"transaction_id": "old-first"})
	old_adapter.receipt_received.emit("apple", "cozy_expedition", {"transaction_id": "old-second"})
	_check("native_receipts_serialize_with_pending_queue", client._verifying_native and client.busy
		and client._native_receipts.size() == 1 and client.dispatched.size() == 2)
	client.set_identity("native-account-B", "native-token-B")
	_check("native_switch_resets_verification_queue_and_adapter", not client._verifying_native and not client.busy
		and client._native_receipts.is_empty() and client._requests.is_empty() and client._native == null
		and not client._native_configured and not client._native_verification_configured)
	var disconnected := true
	for signal_name: String in queued_signals:
		disconnected = disconnected and not old_adapter.is_connected(signal_name, queued_signals[signal_name])
	_check("native_switch_disconnects_every_old_client_signal", disconnected)
	var new_adapter := _prepare_fixture_adapter(client)
	_check("replacement_adapter_uses_replacement_account_binding", new_adapter != old_adapter
		and new_adapter._bindings["apple"] == "binding-native-account-B"
		and old_adapter._bindings["apple"] == "binding-native-account-A")
	new_adapter.receipt_received.emit("apple", "aurora_celebration", {"transaction_id": "new-first"})
	var current_status := client.status
	var current_prices := client.prices.duplicate()
	var current_count := client.dispatched.size()
	client.deliver(1, true, {"product_ids": ["cozy_expedition"], "state": "active"})
	queued_signals["products_changed"].call()
	queued_signals["failed"].call("Old adapter failure")
	queued_signals["receipt_received"].call("apple", "cozy_expedition", {"transaction_id": "late-old"})
	queued_signals["restore_finished"].call()
	_check("late_native_response_and_queued_signals_do_not_touch_replacement", client.busy and client._verifying_native
		and client.status == current_status and client.prices == current_prices
		and client.dispatched.size() == current_count and client._native_receipts.is_empty())
	_check("stale_native_receipts_never_finish_or_grant", old_adapter.verified.is_empty()
		and new_adapter.verified.is_empty() and not client.owns_product("cozy_expedition"))
	var old_queue_submitted := false
	for request: Dictionary in client.dispatched:
		old_queue_submitted = old_queue_submitted or String(request["body"].get("transaction_id", "")) == "old-second"
	_check("old_queued_receipt_not_posted_under_replacement_account", not old_queue_submitted
		and client.dispatched.back()["token"] == "native-token-B")
	client.deliver(current_count - 1, true, {"product_ids": ["aurora_celebration"], "state": "active"})
	_check("current_native_receipt_finishes_only_after_verified_snapshot", not client.busy
		and not client._verifying_native and new_adapter.verified.size() == 1
		and new_adapter.verified[0]["transaction_id"] == "new-first" and client.owns_product("aurora_celebration"))
	var generation := client._session_generation
	client.set_identity("native-account-B", "native-token-B-refreshed")
	_check("same_owner_refresh_retains_current_native_adapter", client._native == new_adapter
		and client._session_generation == generation and client.store_available)
	client.dispose()


func _test_native_restore_reconciliation() -> void:
	var client := _client_fixture("restore-account-A")
	var adapter := _prepare_fixture_adapter(client)
	client._accept_entitlements({"product_ids": ["cozy_expedition"], "verified_at": "old"})
	client.restore_purchases()
	_check("restore_begins_platform_enumeration_without_local_revoke", adapter.restore_calls == 1
		and client.busy and client.owns_product("cozy_expedition") and client.dispatched.size() == 1)
	adapter.restore_finished.emit()
	adapter.restore_finished.emit()
	_check("empty_restore_reconciles_server_exactly_once", client.busy and client.dispatched.size() == 2
		and client.dispatched.back()["path"] == "/entitlements" and client.owns_product("cozy_expedition"))
	client.deliver(1, false, {"error": "network_unavailable"})
	_check("restore_server_failure_preserves_cached_grants_truthfully", not client.busy
		and client.owns_product("cozy_expedition") and client.status.contains("Previous verified purchases remain unchanged")
		and not client._restore_pending and not client._restore_reconciling)
	adapter.restore_finished.emit()
	_check("duplicate_restore_end_after_failure_does_not_retry_implicitly", client.dispatched.size() == 2)
	client.restore_purchases()
	adapter.restore_finished.emit()
	client.deliver(2, true, {"product_ids": [], "verified_at": "server-refund"})
	_check("authoritative_empty_snapshot_revokes_refunded_grants", not client.busy
		and not client.owns_product("cozy_expedition") and client.status == "Store purchases checked.")
	client.dispose()

	client = _client_fixture("restore-queue-account")
	adapter = _prepare_fixture_adapter(client)
	client.restore_purchases()
	adapter.receipt_received.emit("apple", "cozy_expedition", {"transaction_id": "restore-first"})
	adapter.receipt_received.emit("apple", "research_crew", {"transaction_id": "restore-second"})
	adapter.restore_finished.emit()
	_check("restore_reconcile_waits_for_in_flight_and_queued_receipts", client.dispatched.size() == 2
		and client._verifying_native and client._native_receipts.size() == 1 and not client._restore_reconciling)
	client.deliver(1, true, {"product_ids": ["cozy_expedition"], "state": "active"})
	_check("restore_verifies_second_receipt_before_reconcile", client.dispatched.size() == 3
		and client.dispatched.back()["path"] == "/verify" and not client._restore_reconciling)
	client.deliver(2, true, {"product_ids": ["cozy_expedition", "research_crew"], "state": "active"})
	_check("restore_reconciles_once_after_verification_queue_drains", client.dispatched.size() == 4
		and client.dispatched.back()["path"] == "/entitlements" and client._restore_reconciling
		and client.busy and adapter.verified.size() == 2)
	adapter.restore_finished.emit()
	_check("restore_duplicate_end_during_reconciliation_is_idempotent", client.dispatched.size() == 4)
	client.set_identity("restore-other-account")
	var replacement_status := client.status
	client.deliver(3, true, {"product_ids": ["cozy_expedition", "research_crew"]})
	_check("restore_snapshot_after_account_switch_cannot_mutate_new_account", not client.busy
		and not client._restore_pending and not client._restore_reconciling
		and client.status == replacement_status and not client.owns_product("cozy_expedition"))
	client.dispose()

	client = _client_fixture("restore-late-receipt-account")
	adapter = _prepare_fixture_adapter(client)
	client.restore_purchases()
	adapter.receipt_received.emit("apple", "cozy_expedition", {"transaction_id": "before-enumeration-end"})
	client.deliver(1, true, {"product_ids": ["cozy_expedition"], "state": "active"})
	_check("restore_keeps_busy_until_enumeration_finishes", client.busy and client._restore_pending
		and not client._verifying_native and not client._restore_reconciling and client.dispatched.size() == 2)
	client.restore_purchases()
	_check("pending_enumeration_cannot_start_second_restore", adapter.restore_calls == 1)
	adapter.restore_finished.emit()
	adapter.receipt_received.emit("apple", "research_crew", {"transaction_id": "during-final-snapshot"})
	_check("late_restore_receipt_queues_behind_authoritative_snapshot", client.dispatched.size() == 3
		and client.dispatched.back()["path"] == "/entitlements" and client._native_receipts.size() == 1
		and client._restore_reconciling and not client._verifying_native and client.busy)
	client.deliver(2, true, {"product_ids": [], "verified_at": "before-late-receipt"})
	_check("late_receipt_verification_starts_only_after_snapshot_applied", client.dispatched.size() == 4
		and client.dispatched.back()["path"] == "/verify" and client._verifying_native and client.busy
		and not client._restore_reconciling and not client.owns_product("cozy_expedition"))
	client.deliver(3, true, {"product_ids": ["research_crew"], "state": "active"})
	var latest_cache := client._cache.duplicate(true)
	var latest_status := client.status
	client.deliver(2, true, {"product_ids": [], "verified_at": "duplicate-old-snapshot"})
	_check("old_restore_snapshot_cannot_overwrite_late_verified_grant", client._cache == latest_cache
		and client.status == latest_status and client.owns_product("research_crew") and not client.busy
		and adapter.verified.size() == 2 and client._native_receipts.is_empty())
	client.dispose()


func _test_native_auth_cancellation() -> void:
	var auth := AuthScript.new()
	add_child(auth)
	auth._ensure_timers()
	auth.pending = true
	auth._generation = 7
	auth._request_id = "fixture"
	auth._verifier = "secret-never-saved"
	auth._cancel_local()
	_check("native_cancel_invalidates_callback_generation", auth._generation == 8)
	_check("native_cancel_clears_memory_secret", auth._request_id == "" and auth._verifier == "" and not auth.pending)
	_check("native_cancel_stops_poll", auth._poll_timer.is_stopped())
	_check("native_auth_no_frame_processing", not auth.is_processing())
	auth.free()


func _test_ios_auth_presentation() -> void:
	var auth := AuthScript.new()
	add_child(auth)
	auth._ensure_timers()
	var helper := IOSAuthFixture.new()
	_check("ios_auth_helper_contract_valid", auth._bind_ios_helper(helper))
	var incomplete := RefCounted.new()
	_check("ios_auth_missing_methods_fail_closed", not auth._bind_ios_helper(incomplete))
	_check("ios_auth_malformed_signature_rejected", not auth._has_string_signature(
		[{"name": "begin_auth_session", "args": [{"type": TYPE_STRING}, {"type": TYPE_INT}]}], "begin_auth_session", 2))
	var request_id := "287ead21-9496-4220-8dc9-5e939c04a60c"
	_check("ios_auth_uuid_validated", auth._valid_request_id(request_id) and not auth._valid_request_id("https://attacker.example"))
	auth.pending = true
	auth._generation = 12
	auth._ios_generation = 12
	auth._ios_request_id = request_id
	auth._request_id = request_id
	auth._expires_at_ms = Time.get_ticks_msec() + 60000
	auth._poll_authorization()
	_check("ios_auth_no_poll_before_native_start", not auth._poll_in_flight and auth._poll_timer.is_stopped())
	auth._on_ios_session_started("different-request")
	_check("ios_auth_foreign_start_ignored", not auth._ios_start_confirmed)
	auth._ios_generation = 11
	auth._on_ios_session_started(request_id)
	_check("ios_auth_stale_generation_ignored", not auth._ios_start_confirmed)
	auth._ios_generation = 12
	helper.auth_session_started.emit(request_id)
	_check("ios_auth_started_waits_for_callback_without_polling", auth._ios_start_confirmed and auth._poll_timer.is_stopped()
		and not auth._presentation_timer.is_stopped())
	auth._poll_authorization()
	_check("ios_auth_started_alone_never_requests_token", not auth._poll_in_flight and auth._poll_timer.is_stopped())
	# A callback supplies the additional secret, but cannot duplicate an active
	# HTTP request or grant credentials. No real transport runs in this fixture.
	auth._poll_in_flight = true
	helper.auth_session_authorized.emit(request_id, "a".repeat(43))
	_check("ios_auth_return_does_not_authenticate", auth.pending and not auth.signed_in())
	helper.auth_session_finished.emit(request_id, "cancelled")
	_check("ios_auth_duplicate_terminal_callback_ignored", auth.pending)
	auth._verifier = "secret-cleared-on-cancel"
	auth._cancel_local()
	_check("ios_auth_cancel_ends_native_session", helper.ended == [request_id])
	_check("ios_auth_sync_teardown_callback_ignored", not auth.pending and auth._verifier == "" and auth._ios_callback_code == "" and auth._generation == 13)
	_check("ios_auth_cancel_stops_presentation_timer", auth._presentation_timer.is_stopped() and auth._poll_timer.is_stopped())
	helper.auth_session_started.emit(request_id)
	helper.auth_session_authorized.emit(request_id, "a".repeat(43))
	_check("ios_auth_callbacks_after_cancel_ignored", not auth.pending and not auth.signed_in())
	# Teardown after a server token has been accepted must not undo that token,
	# even if the plugin synchronously emits cancelled while closing its sheet.
	auth.pending = true
	auth._token = "verified-server-token-fixture"
	auth.user_id = "fixture-user"
	auth._request_id = request_id
	auth._ios_request_id = request_id
	auth._ios_generation = auth._generation
	auth._end_ios_presentation()
	_check("ios_auth_end_after_token_preserves_account", auth.signed_in() and auth.pending)
	auth._cancel_local()
	auth.free()


func _check(name: String, ok: bool) -> void:
	if ok:
		_passed += 1
		print("[commerce_contract] PASS %s" % name)
	else:
		_failed += 1
		print("[commerce_contract] FAIL %s" % name)
