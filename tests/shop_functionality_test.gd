extends Node
## Production Shop and commerce state machine with transport-only fixtures.
## Requires a separate user:// identity; never opens auth/payment providers.

const ShopScript = preload("res://scripts/commerce/premium_cosmetic_shop.gd")

class LocalCommerce extends "res://scripts/commerce/commerce_client.gd":
	var test_identity: Dictionary = {}
	var requests: Array[String] = []
	var fail_entitlements := false
	func _auth_context() -> Dictionary:
		return test_identity.duplicate()
	func _dispatch_request(_method: String, path: String, _body: Dictionary, _token: String, complete: Callable) -> void:
		requests.append(path)
		match path:
			"/catalog": complete.call(true, {"products": CommerceCatalog.products(), "native_verification_configured": {"apple": true}, "native_purchase_configured": {"apple": true}})
			"/entitlements": complete.call(not fail_entitlements, {"error": "network_unavailable"} if fail_entitlements else {"product_ids": [], "verified_at": "fixture"})
			_: complete.call(false, {"error": "test_blocked"})

class LocalAuth extends "res://scripts/commerce/native_auth_client.gd":
	var requests: Array[String] = []
	func _request(path: String, _body: Dictionary, _callback: Callable) -> void:
		# Hold at transport before any provider URL is received/opened. Actual
		# production pending/cancel state and status signals remain in use.
		requests.append(path)

var _checks := 0
var _failures: Array[String] = []
var _frames: Array[Dictionary] = []
var _out := ""
var _confirm_only := false


func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false) or not String(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("waddle-wars-shop-"):
		push_error("Shop fixture requires isolated waddle-wars-shop-* user data")
		get_tree().quit(2)
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="): _out = arg.trim_prefix("out=")
		if arg == "confirm_only=1": _confirm_only = true
	CommerceClient.set_script(LocalCommerce)
	NativeAuthClient.set_script(LocalAuth)
	CommerceClient.set_process(false)
	NativeAuthClient.set_process(false)
	LeaderboardClient.set_process(false)
	SaveManager.data = SaveManager.default_save()
	LayoutProfile.forced_insets = Vector4.ZERO
	for shape: Vector2i in [Vector2i(540, 960), Vector2i(960, 540)]:
		GameConfig.force_touch = shape.y > shape.x
		SettingsManager.settings["display"]["window_mode"] = "windowed"
		SettingsManager.settings["display"]["resolution"] = "%dx%d" % [shape.x, shape.y]
		SettingsManager.settings["accessibility"]["reduced_flashing"] = true
		SettingsManager.apply_all()
		if GameConfig.is_headless():
			get_window().size = shape
			get_window().content_scale_size = Vector2i(800,1422) if shape.y > shape.x else Vector2i(1920,1080)
		await _settle()
		SaveManager.data = SaveManager.default_save()
		SaveManager.set_value("fish", 0)
		var host := load("res://scenes/menus/cosmetic_shop.tscn").instantiate() as Control
		add_child(host)
		await _settle()
		var shop: Control = null
		for child in host.get_children():
			if child.get_script() == ShopScript: shop = child
		_check(shop != null, "real routed Shop scene instantiates")
		if shop == null:
			host.queue_free()
			continue
		_check(not CommerceClient.payment_platform_supported(), "actual desktop reports no native payment adapter")
		_check(CommerceClient.requests.is_empty(), "signed-out Shop opens without requests")
		_check(shop._refresh.disabled and shop._sign_in.visible, "signed-out sync disabled; real sign-in available")
		_check("desktop" in shop._status_label.text.to_lower() and "fish" in shop._status_label.text.to_lower(), "desktop status names working fish route")
		var header_balance := shop._currency_cap.find_child("FishAmount", true, false) as Label
		_check(header_balance.is_visible_in_tree() and header_balance.text == "0", "header shows actual fish balance")
		await _frame(shop, "empty-balance", shape)
		var expected := {"cozy_expedition": 2000, "research_crew": 2200, "aurora_celebration": 6000}
		for product: Dictionary in CommerceCatalog.products():
			var id := String(product["id"])
			SaveManager.data = SaveManager.default_save()
			shop._update()
			var before := SaveManager.data.duplicate(true)
			var selector := shop._selector_buttons[id] as Button
			# Click the portrait, not a bare border: decorative children must not
			# swallow the real mouse or touch-emulated GUI event.
			await _click(selector.get_global_rect().position + selector.size * Vector2(0.5, 0.35), shape.y > shape.x)
			await _settle()
			_check(shop._selected_product_id == id, "portrait pointer selects " + id)
			_check(SaveManager.data == before, "selecting " + id + " never purchases")
			var quote: Dictionary = shop._fish_quote(id)
			_check(quote["cost"] == expected[id], id + " costs exact sum of real cosmetic prices")
			var fish_action := shop._fish_buttons[id] as Button
			_check(not fish_action.disabled and fish_action.text == "VIEW BUNDLE", id + " remains inspectable with insufficient fish")
			_check(not (shop._store_rows[id] as Control).visible and (shop._buttons[id] as Button).disabled and (shop._price_labels[id] as Label).text == "Price unavailable", "no invented cash price or desktop payment action")
			await _click(fish_action.get_global_rect().get_center(), shape.y > shape.x)
			await _settle()
			_check(is_instance_valid(shop._purchase_info), "real pointer opens insufficient-fish bundle details")
			if not is_instance_valid(shop._purchase_info):
				continue
			var insufficient_confirm := shop._purchase_info.find_child("ConfirmFishPurchase", true, false) as Button
			var shortfall := shop._purchase_info.find_child("FishPurchaseBalance", true, false) as Label
			_check(insufficient_confirm.disabled and shortfall.text.contains(ExpeditionMenuStyle.grouped_amount(expected[id])) and shortfall.text.contains("Earn"), "shortfall shown; spending disabled")
			_check(_on_screen(shortfall) and _on_screen(insufficient_confirm), "shortfall and disabled spend visible")
			await _click(insufficient_confirm.get_global_rect().get_center(), shape.y > shape.x)
			_check(SaveManager.data == before, "disabled spend pointer never mutates fish or ownership")
			SaveManager.set_value("fish", int(expected[id]) + 100)
			Progression.fish_changed.emit(Progression.get_fish())
			_check(not insufficient_confirm.disabled and shortfall.text.contains("Fish remaining: 100"), "open confirmation updates when fish arrive")
			_check(header_balance.text == ExpeditionMenuStyle.grouped_amount(expected[id] + 100), "header balance refreshes from real signal")
			await _settle()
			_check(shop._purchase_info != null and Progression.get_fish() == int(expected[id]) + 100, "fish action asks before spending")
			_check(_on_screen(shop._purchase_info.find_child("ConfirmFishPurchase", true, false)), "confirm remains visible")
			if shape.x > shape.y:
				var disclosure := shop._purchase_info.find_child("PurchaseDisclosure", true, false) as Label
				_check(disclosure.get_theme_font_size("font_size") * float(shape.x) / get_viewport().get_visible_rect().size.x >= 14.0, "desktop confirmation copy at least14 physical pixels")
			await _click((shop._purchase_info.find_child("ClosePurchaseInformation", true, false) as Control).get_global_rect().get_center(), shape.y > shape.x)
			_check(Progression.get_fish() == int(expected[id]) + 100 and not Progression.is_cosmetic_unlocked(product["cosmetics"][0]), "cancel preserves balance and ownership")
			_check(get_viewport().gui_get_focus_owner() == fish_action, "cancel returns keyboard focus to bundle action")
			await _click(fish_action.get_global_rect().get_center(), shape.y > shape.x)
			await _settle()
			if id == "cozy_expedition": await _frame(shop, "confirm-fish", shape)
			var equipped_before := Progression.equipped().duplicate(true)
			await _click((shop._purchase_info.find_child("ConfirmFishPurchase", true, false) as Control).get_global_rect().get_center(), shape.y > shape.x)
			_check(Progression.get_fish() == 100, "confirmed " + id + " spends exactly once")
			for cosmetic: String in product["cosmetics"]:
				_check(Progression.is_cosmetic_unlocked(cosmetic), "confirmed bundle unlocks " + cosmetic)
			_check(Progression.equipped() == equipped_before and not CommerceClient.owns_product(id), "fish unlock changes neither equipment nor paid ledger")
			shop._confirm_fish_purchase()
			_check(Progression.get_fish() == 100, "duplicate confirmation cannot spend twice")
			SaveManager.load_save()
			_check(Progression.get_fish() == 100 and Progression.is_cosmetic_unlocked(product["cosmetics"][2]), "fish and unlock survive real save reload")
			_check((shop._fish_buttons[id] as Button).disabled and (shop._fish_buttons[id] as Button).text == "OWNED", "owned bundle disables repeat purchase")
			await _frame(shop, "owned-" + id, shape)
		SaveManager.data = SaveManager.default_save()
		SaveManager.set_value("fish", 5000)
		_check(Progression.try_unlock_cosmetic("hat_beanie"), "partial ownership uses existing individual unlock")
		shop._select_product("cozy_expedition")
		shop._update()
		_check(shop._fish_quote("cozy_expedition")["cost"] == 1650, "owned beanie deducted from fish quote")
		shop._preview_fish_purchase("cozy_expedition")
		Progression.try_unlock_cosmetic("scarf_red")
		var balance_before := Progression.get_fish()
		shop._confirm_fish_purchase()
		_check(Progression.get_fish() == balance_before and not Progression.is_cosmetic_unlocked("trail_snowflake"), "stale ownership quote refuses purchase without partial spend")
		shop._sign_in.pressed.emit()
		_check(NativeAuthClient.pending and shop._sign_in.text == "Cancel sign-in" and NativeAuthClient.requests.back() == "/start", "real sign-in dispatch and cancel state wired")
		shop._sign_in.pressed.emit()
		_check(not NativeAuthClient.pending, "cancel sign-in wired without opening provider")
		CommerceClient.test_identity = {"user_id": "shop-fixture", "token": "fixture-token"}
		CommerceClient._on_auth_changed()
		shop._update()
		_check(not shop._refresh.disabled and shop._refresh.text == "SYNC PURCHASES", "desktop account can sync verified purchases")
		shop._refresh.pressed.emit()
		_check(CommerceClient.requests.slice(-2) == ["/catalog", "/entitlements"] and CommerceClient._native == null, "desktop sync uses real request guards without creating unsupported adapter")
		CommerceClient.fail_entitlements = true
		shop._refresh.pressed.emit()
		_check(not CommerceClient.busy and not CommerceClient.store_available and "Could not reach" in shop._status_label.text, "failed entitlements never claim successful sync")
		_check(shop._status_label.text.contains("online purchases") and shop._status_label.text.contains("Fish unlocks still work"), "online failure explains local fish availability")
		_check(Progression.get_fish() == balance_before, "network failure leaves earned balance intact")
		CommerceClient.test_identity = {}
		CommerceClient._on_auth_changed()
		CommerceClient.requests.clear()
		CommerceClient.fail_entitlements = false
		host.queue_free()
		await _settle()
	for player: AudioStreamPlayer in [AudioManager._music_a, AudioManager._music_b]:
		player.stop()
		player.stream = null
	for player: AudioStreamPlayer in AudioManager._sfx_pool:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.25).timeout
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
		var file := FileAccess.open(_out.path_join("report.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks": _checks, "failures": _failures, "frames": _frames, "limits": "Isolated real earned-fish save operations. Auth dispatch and HTTP transport controlled; no live sign-in, payment, or store entitlement verified."}, "\t"))
	print("[shop-functionality] %d/%d checks passed; %d frames" % [_checks - _failures.size(), _checks, _frames.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)


func _settle() -> void:
	for index in 8: await get_tree().process_frame


func _click(at: Vector2, touch: bool = false) -> void:
	var viewport := get_viewport()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	viewport.push_input(motion, true)
	for down: bool in [true, false]:
		if touch:
			var finger := InputEventScreenTouch.new()
			finger.position = at
			finger.pressed = down
			viewport.push_input(finger, true)
		var mouse := InputEventMouseButton.new()
		mouse.device = InputEvent.DEVICE_ID_EMULATION if touch else 0
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		mouse.position = at
		mouse.global_position = at
		mouse.pressed = down
		viewport.push_input(mouse, true)
		await get_tree().process_frame


func _on_screen(control: Control) -> bool:
	return control != null and get_viewport().get_visible_rect().grow(1.0).encloses(control.get_global_rect())


func _frame(shop: Control, state: String, shape: Vector2i) -> void:
	await _settle()
	_check(_on_screen(shop._fish_buttons[shop._selected_product_id]) and _on_screen(shop._fish_balance) and _on_screen(shop._status_label), "fish action/balance/status visible: " + state)
	var scroll := shop.find_child("ExpeditionContentScroll", true, false) as ScrollContainer
	var summary := shop._detail_cards[shop._selected_product_id] as Control
	print("[shop-functionality] layout %s %s scroll=%s detail=%s footer=%s" % [shape, state, scroll.get_global_rect(), summary.get_global_rect(), shop._purchase_footer.get_global_rect()])
	_check(scroll.get_global_rect().grow(1.0).encloses(summary.get_global_rect()), "complete selected bundle summary visible: " + state)
	if GameConfig.is_headless() or _out.is_empty(): return
	if _confirm_only and state not in ["confirm-fish", "empty-balance"]: return
	DisplayServer.window_move_to_foreground()
	await get_tree().create_timer(0.3).timeout
	DisplayServer.window_move_to_foreground()
	await RenderingServer.frame_post_draw
	var foreground := DisplayServer.window_is_focused()
	_check(foreground, "foreground at frame readback: " + state)
	if not foreground: return
	DirAccess.make_dir_recursive_absolute(_out)
	var path := _out.path_join("%s-%s.png" % ["portrait" if shape.y > shape.x else "landscape", state])
	var pixels := get_viewport().get_texture().get_image()
	_check(pixels.save_png(path) == OK, "saved " + path.get_file())
	_frames.append({"path": path, "foreground": foreground, "size": [pixels.get_width(), pixels.get_height()]})


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error("[shop-functionality] " + message)
