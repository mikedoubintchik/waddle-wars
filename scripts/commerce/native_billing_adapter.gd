class_name WaddleNativeBilling
extends Node
## Official Play Billing wrapper / StoreKit 2 plugin, initialized only on shop
## use. Platform callbacks provide receipts, never cosmetic unlocks.

signal products_changed
signal receipt_received(provider: String, product_id: String, receipt: Dictionary)
signal failed(message: String)
signal restore_finished

const ANDROID_WRAPPER: String = "res://addons/GodotGooglePlayBilling/BillingClient.gd"

var provider: String = ""
var prices: Dictionary = {}
var _details: Dictionary = {}
var _billing: Object = null
var _bindings: Dictionary = {}
var _restore_requested: bool = false
var _started: bool = false


func start(bindings: Dictionary) -> void:
	_bindings = bindings.duplicate()
	if _started:
		if provider == "google" and _billing != null and not bool(_billing.call("is_ready")):
			_billing.call("start_connection")
			return
		_query_products()
		return
	_started = true
	if OS.has_feature("android"):
		provider = "google"
		var wrapper_path := String(ProjectSettings.get_setting("commerce/android_billing_wrapper", ANDROID_WRAPPER))
		if not Engine.has_singleton("GodotGooglePlayBilling") or not ResourceLoader.exists(wrapper_path):
			failed.emit("Google Play purchases unavailable on this build.")
			return
		var wrapper := load(wrapper_path) as Script
		if wrapper == null:
			failed.emit("Google Play purchases unavailable on this build.")
			return
		_billing = wrapper.new()
		if _billing is Node:
			add_child(_billing as Node)
		_billing.connect("connected", _query_products)
		_billing.connect("disconnected", _on_disconnected)
		_billing.connect("connect_error", _on_google_connect_error)
		_billing.connect("query_product_details_response", _on_google_products)
		_billing.connect("on_purchase_updated", _on_google_purchases)
		_billing.connect("query_purchases_response", _on_google_restore)
		_billing.call("set_obfuscated_account_id", String(_bindings.get("google", "")))
		_billing.call("start_connection")
	elif OS.has_feature("ios"):
		provider = "apple"
		if not Engine.has_singleton("WaddleStoreKit"):
			failed.emit("App Store purchases unavailable on this build.")
			return
		_billing = Engine.get_singleton("WaddleStoreKit")
		_billing.connect("products_received", _on_apple_products)
		_billing.connect("purchase_received", _on_apple_purchase)
		_billing.connect("purchase_failed", _on_apple_failure)
		_billing.connect("restore_finished", _on_restore_finished)
		_query_products()
	else:
		failed.emit("Purchases available in the web, App Store and Google Play editions.")


func available(product_id: String) -> bool:
	return _billing != null and not String(prices.get(product_id, "")).is_empty() \
		and not String(_bindings.get(provider, "")).is_empty()


func purchase(product_id: String) -> void:
	if not available(product_id):
		failed.emit("This purchase is not available. Refresh the shop and try again.")
		return
	var item := CommerceCatalog.product(product_id)
	var store_id := String(item.get("%s_product_id" % provider, ""))
	if provider == "google":
		_billing.call("set_obfuscated_account_id", String(_bindings.get("google", "")))
		var detail: Dictionary = _details.get(product_id, {})
		var result: Variant = _billing.call("purchase", store_id, String(detail.get("purchase_option_id", "")),
			String(detail.get("offer_id", "")), false)
		if not result is Dictionary or int(result.get("response_code", -1)) != 0:
			failed.emit("Google Play could not open the purchase. Try again.")
	else:
		_billing.call("purchase", store_id, String(_bindings.get("apple", "")))


func restore() -> void:
	if _billing == null:
		failed.emit("Purchases unavailable on this build.")
		return
	_restore_requested = true
	if provider == "google":
		_billing.call("query_purchases", 0)
	else:
		_billing.call("restore_purchases")


func finish_verified(receipt: Dictionary) -> void:
	# Google acknowledgment occurs on the secure backend after durable grant.
	# Apple transactions remain unfinished across network failure and retries.
	if provider == "apple" and _billing != null:
		_billing.call("finish_transaction", String(receipt.get("transaction_id", "")))


func _query_products() -> void:
	if _billing == null:
		return
	var ids := PackedStringArray()
	for item: Dictionary in CommerceCatalog.products():
		ids.append(String(item.get("%s_product_id" % provider, "")))
	if provider == "google":
		_billing.call("query_product_details", ids, 0)
	else:
		_billing.call("request_products", ids)


func _on_google_connect_error(_code: int, _debug: String) -> void:
	failed.emit("Could not connect to Google Play. Check your connection and try again.")


func _on_disconnected() -> void:
	prices.clear()
	products_changed.emit()


func _on_google_products(response: Dictionary) -> void:
	prices.clear()
	_details.clear()
	if int(response.get("response_code", -1)) != 0:
		failed.emit("Could not load Google Play prices.")
		return
	for raw: Variant in response.get("product_details", []):
		if not raw is Dictionary:
			continue
		var item := CommerceCatalog.from_store_id(String(raw.get("product_id", "")), "google")
		if item.is_empty():
			continue
		var offer: Dictionary = {}
		var offers: Variant = raw.get("one_time_purchase_offer_details_list", [])
		if offers is Array:
			for candidate: Variant in offers:
				if candidate is Dictionary and candidate.get("offer_id") == null \
					and candidate.get("rental_details") == null \
					and not String(candidate.get("purchase_option_id", "")).is_empty():
					offer = candidate
					break
		var price := String(offer.get("formatted_price", ""))
		if not price.is_empty():
			prices[item["id"]] = price
			_details[item["id"]] = offer.duplicate()
			_details[item["id"]]["offer_id"] = ""
	products_changed.emit()


func _on_google_purchases(response: Dictionary) -> void:
	var code := int(response.get("response_code", -1))
	if code != 0:
		failed.emit("Purchase cancelled." if code == 1 else "Google Play purchase unavailable. Try again.")
		return
	for raw: Variant in response.get("purchases", []):
		if not raw is Dictionary:
			continue
		if int(raw.get("purchase_state", 0)) == 2:
			failed.emit("Payment pending. Your items unlock after payment completes.")
			continue
		if int(raw.get("purchase_state", 0)) != 1:
			continue
		for store_id: String in raw.get("product_ids", []):
			var item := CommerceCatalog.from_store_id(store_id, "google")
			if not item.is_empty():
				receipt_received.emit("google", String(item["id"]), {
					"purchase_token": String(raw.get("purchase_token", "")),
				})


func _on_google_restore(response: Dictionary) -> void:
	_on_google_purchases(response)
	_on_restore_finished()


func _on_apple_products(products: Array) -> void:
	prices.clear()
	for raw: Variant in products:
		if not raw is Dictionary:
			continue
		var item := CommerceCatalog.from_store_id(String(raw.get("product_id", "")), "apple")
		var price := String(raw.get("localized_price", ""))
		if not item.is_empty() and not price.is_empty():
			prices[item["id"]] = price
	products_changed.emit()


func _on_apple_purchase(receipt: Dictionary) -> void:
	var state := String(receipt.get("state", ""))
	if state == "cancelled":
		failed.emit("Purchase cancelled.")
		return
	if state not in ["purchased", "refunded"]:
		failed.emit("Payment pending. Your items unlock after payment completes.")
		return
	var item := CommerceCatalog.from_store_id(String(receipt.get("product_id", "")), "apple")
	if not item.is_empty():
		receipt_received.emit("apple", String(item["id"]), {"transaction_id": String(receipt.get("transaction_id", ""))})


func _on_apple_failure(message: String) -> void:
	failed.emit(message)


func _on_restore_finished() -> void:
	_restore_requested = false
	restore_finished.emit()


func _exit_tree() -> void:
	if provider == "google" and _billing != null:
		_billing.call("end_connection")
