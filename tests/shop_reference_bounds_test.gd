extends Node
## Reproduces Chrome's portrait safe-area floor and long signed-out status.
var passed := 0
var failed := 0

# Native headless cannot claim OS.has_feature("web"). Supply the real shop's
# platform/catalog capability boundary so its Web-only row path is exercised.
class WebStoreState extends Node:
	var authenticated := false
	var store_available := false
	var busy := false
	var prepared := false
	var price := ""
	var status := "Sign in to buy or restore cosmetics. You can still earn every item with fish."
	var purchases := 0
	var checkout_opens := 0
	func payment_platform_supported() -> bool: return true
	func signed_in() -> bool: return authenticated
	func owns_product(_id: String) -> bool: return false
	func checkout_prepared_for(_id: String) -> bool: return prepared
	func localized_price(_id: String) -> String: return price
	func can_purchase(_id: String) -> bool: return authenticated and store_available and not busy and not price.is_empty()
	func purchase(_id: String) -> void: purchases += 1
	func open_checkout(_id: String) -> void: checkout_opens += 1

func _ready() -> void:
	CommerceClient.set_process(false)
	LeaderboardClient.set_process(false)
	SaveManager.data = SaveManager.default_save()
	SettingsManager.settings["accessibility"]["reduced_flashing"] = true
	for shape: Vector2i in [Vector2i(800,1422), Vector2i(941,1672), Vector2i(1920,1080), Vector2i(1672,941)]:
		GameConfig.force_touch = shape.y > shape.x or shape == Vector2i(1672,941)
		LayoutProfile.forced_insets = Vector4.ONE * (24.0 if GameConfig.force_touch else 0.0)
		var viewport := SubViewport.new()
		viewport.size = shape
		add_child(viewport)
		var host := load("res://scenes/menus/cosmetic_shop.tscn").instantiate() as Control
		viewport.add_child(host)
		var shop: Control
		for child in host.get_children():
			if child.get_script() == load("res://scripts/commerce/premium_cosmetic_shop.gd"): shop = child
		var web_store := WebStoreState.new()
		add_child(web_store)
		shop._client = web_store
		for product: Dictionary in CommerceCatalog.products():
			shop._select_product(String(product["id"]))
			shop._update()
			shop._status_label.text = "Sign in to buy or restore cosmetics. You can still earn every item with fish."
			for frame: int in 6: await get_tree().process_frame
			var scroll := shop.find_child("ExpeditionContentScroll",true,false) as ScrollContainer
			var summary: Control = shop._detail_cards[shop._selected_product_id]
			var title := summary.find_child("BundleTitle",true,false) as Label
			var action: Control = shop._fish_buttons[shop._selected_product_id]
			var footer: Control = shop._purchase_footer
			check(not (shop._store_rows[shop._selected_product_id] as Control).visible, "unpriced signed-out Web checkout row hidden; footer sign-in retained")
			check(shop._sign_in.visible and shop._status_label.text.contains("Sign in"), "Web unavailable state remains explained with sign-in action")
			print("[shop-reference] %s %s scroll=%s summary=%s title=%s action=%s footer=%s" % [shape,product["id"],scroll.get_global_rect(),summary.get_global_rect(),title.get_global_rect(),action.get_global_rect(),footer.get_global_rect()])
			check(scroll.get_global_rect().grow(1).encloses(summary.get_global_rect()), "complete rounded selected card in first view")
			check(summary.get_global_rect().grow(-8).encloses(title.get_global_rect()), "title inside selected card with interior padding")
			check(summary.get_global_rect().grow(-8).encloses(action.get_global_rect()), "CTA inside selected card with interior padding")
			check(not footer.get_global_rect().intersects(summary.get_global_rect()) and footer.global_position.y-summary.get_global_rect().end.y >= 12, "selected card and footer separated")
			check(Rect2(Vector2.ZERO,Vector2(shape)).encloses(footer.get_global_rect()), "status and account actions fully visible")
			var balance := shop._currency_cap.find_child("FishAmount", true, false) as Label
			check(balance.is_visible_in_tree() and balance.text == "0" and shop._currency_cap.get_global_rect().grow(1).encloses(balance.get_global_rect()), "real numeric header balance fits its badge")
			check(Rect2(Vector2.ZERO,Vector2(shape)).encloses(shop._currency_cap.get_global_rect()), "header balance badge stays on screen")
			for icon: TextureRect in summary.find_children("BundleItem_*", "TextureRect", true, false):
				check(not icon.accessibility_name.is_empty() and icon.accessibility_name == icon.tooltip_text, "bundle item retains accessible identity without redundant desktop caption")
			for caption: Label in shop.find_children("BundleName", "Label", true, false):
				check(caption.get_line_count() == 1 and caption.get_global_rect().end.x <= shape.x, "complete one-line catalog caption")

			web_store.authenticated = true
			web_store.store_available = true
			web_store.price = "$4.99"
			shop._update()
			check((shop._store_rows[shop._selected_product_id] as Control).visible and not (shop._buttons[shop._selected_product_id] as Button).disabled, "available priced Web checkout stays visible and enabled")
			check((shop._price_labels[shop._selected_product_id] as Label).text == "$4.99", "checkout displays authentic supplied price")
			for frame: int in 6: await get_tree().process_frame
			scroll.ensure_control_visible(shop._buttons[shop._selected_product_id])
			for frame: int in 3: await get_tree().process_frame
			check(scroll.get_global_rect().grow(1).encloses((shop._buttons[shop._selected_product_id] as Control).get_global_rect()), "additional available checkout is reachable within real scroll viewport")
			await click(viewport, shop._buttons[shop._selected_product_id])
			check(web_store.purchases == 1, "priced checkout action reaches commerce purchase once")
			web_store.busy = true
			shop._update()
			check((shop._store_rows[shop._selected_product_id] as Control).visible and (shop._buttons[shop._selected_product_id] as Button).disabled, "busy priced checkout retains row while disabling action")
			web_store.prepared = true
			web_store.price = ""
			web_store.store_available = false
			shop._update()
			check((shop._store_rows[shop._selected_product_id] as Control).visible and not (shop._buttons[shop._selected_product_id] as Button).disabled, "prepared checkout survives catalog refresh and stays actionable")
			await click(viewport, shop._buttons[shop._selected_product_id])
			check(web_store.checkout_opens == 1, "prepared checkout opens existing payment once")
			web_store.prepared = false
			web_store.busy = false
			web_store.price = "$4.99"
			shop._update()
			check(not (shop._store_rows[shop._selected_product_id] as Control).visible, "unavailable signed-in store hides stale priced row")
			web_store.authenticated = false
			web_store.price = ""
			web_store.purchases = 0
			web_store.checkout_opens = 0
			scroll.scroll_vertical = 0
		viewport.free()
		web_store.free()
	LayoutProfile.forced_insets = Vector4(-1,-1,-1,-1)
	for voice in AudioManager._sfx_pool:
		voice.stop(); voice.stream=null
	for player in [AudioManager._music_a,AudioManager._music_b]:
		player.stop();player.stream=null
	await get_tree().create_timer(0.1).timeout
	print("[shop-reference] DONE: %d passed, %d failed" % [passed,failed])
	get_tree().quit(1 if failed else 0)

func check(ok: bool, label: String) -> void:
	passed+=int(ok);failed+=int(not ok)
	print("[shop-reference] %s %s" % ["PASS" if ok else "FAIL",label])


func click(viewport: SubViewport, control: Control) -> void:
	var at := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	viewport.push_input(motion, true)
	for down: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
		event.position = at
		event.global_position = at
		event.pressed = down
		viewport.push_input(event, true)
		await get_tree().process_frame
