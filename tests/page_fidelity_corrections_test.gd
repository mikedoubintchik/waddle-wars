extends "res://tests/mobile_ui_audit.gd"
## Real menu state, isolated offline transports. Native stills require visual
## reference review; these checks do not establish artwork fidelity.

var _checks := 0
var _frames: Array[Dictionary] = []
var _out := ""
var _shop_portrait_only := false
var _cozy_capture_only := false
var _owned_utility_only := false

func _ready() -> void:
	if not ProjectSettings.get_setting("application/config/use_custom_user_dir", false):
		get_tree().quit(2)
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="): _out = arg.trim_prefix("out=")
		if arg == "shop_portrait_only=1": _shop_portrait_only = true
		if arg == "cozy_capture_only=1": _cozy_capture_only = true
		if arg == "owned_utility_only=1": _owned_utility_only = true
	LeaderboardClient.set_script(OfflineLeaderboard)
	CommerceClient.set_script(OfflineCommerce)
	LeaderboardClient.set_process(false)
	CommerceClient.set_process(false)
	LeaderboardClient.force_available = false
	LayoutProfile.forced_insets = Vector4.ZERO
	for shape: Vector2i in [Vector2i(540, 960), Vector2i(960, 540)]:
		if _shop_portrait_only and shape.x > shape.y: continue
		GameConfig.force_touch = shape.y > shape.x
		SettingsManager.settings["display"]["window_mode"] = "windowed"
		SettingsManager.settings["display"]["resolution"] = "%dx%d" % [shape.x,shape.y]
		SettingsManager.settings["accessibility"]["reduced_flashing"] = true
		SettingsManager.apply_all()
		if GameConfig.is_headless():
			get_window().size = shape
			get_window().content_scale_size = Vector2i(800,1422) if shape.y > shape.x else Vector2i(1920,1080)
		await _settle()
		print("[page-corrections] shape=%s logical=%s" % [shape,get_viewport().get_visible_rect().size])
		if not _owned_utility_only:
			var host := load("res://scenes/menus/cosmetic_shop.tscn").instantiate() as Control
			add_child(host)
			await _settle()
			var shop: PremiumCosmeticShop = null
			for child in host.get_children():
				if child is PremiumCosmeticShop: shop = child
			var scroll := shop.find_child("ExpeditionContentScroll", true, false) as ScrollContainer
			for product: Dictionary in CommerceCatalog.products():
				var id := String(product["id"])
				shop._select_product(id)
				await _settle()
				var action := shop._fish_buttons[id] as Button
				print("[page-corrections] shop=%s scroll=%s action=%s" % [id,scroll.get_global_rect(),action.get_global_rect()])
				_check((shop._buttons[id] as Button).disabled and (shop._price_labels[id] as Label).text == "Price unavailable", "offline product retains truthful unavailable store price/action")
				_check(action.is_visible_in_tree() and _on_screen(action) and (shop._detail_cards[id] as Control).get_global_rect().grow(1.0).encloses(action.get_global_rect()), "selected purchase action fits fixed first view: " + id)
				_check(_on_screen(shop._fish_prices[id]), "selected earned-fish price remains visible: " + id)
				_check(shop._selected_banner.text == String(product["name"]).to_upper(), "selected banner retains catalogue title")
				# Info moved into the bundle title row so terms remain available
				# even when the native-store purchase row is unavailable/hidden.
				var info := (shop._detail_cards[id] as Control).find_child("PurchaseInformation",true,false) as Button
				_check(info != null and info.tooltip_text == CommerceCatalog.disclosure() and not info.pressed.get_connections().is_empty() and info.is_visible_in_tree() and _on_screen(info), "full purchase terms remain connected and visible in selected bundle header")
				if shape.y > shape.x:
					var summary := shop._detail_cards[id] as Control
					_check(scroll.get_global_rect().grow(1.0).encloses(summary.get_global_rect()), "whole selected bundle summary fits first portrait view: "+id)
					var contents := summary.find_child("BundleContents",true,false) as Label
					var actual_names: Array[String] = []
					for item: String in product["cosmetics"]:
						actual_names.append(String(CosmeticsDB.get_item(item).get("name",item)))
					_check(contents.text == "  •  ".join(actual_names), "summary lists all actual included cosmetics: "+id)
				await _save_frame("shop-"+id,shape)
				if shape.y > shape.x and id == "cozy_expedition" and info != null:
					info.pressed.emit()
					await _settle()
					_check(is_instance_valid(shop._purchase_info), "Info opens the actual local disclosure dialog")
					if not is_instance_valid(shop._purchase_info):
						continue
					var disclosure := shop._purchase_info.find_child("PurchaseDisclosure",true,false) as Label
					var close := shop._purchase_info.find_child("ClosePurchaseInformation",true,false) as Button
					_check(disclosure != null and disclosure.text == CommerceCatalog.disclosure() and _on_screen(disclosure), "themed Info displays full authoritative terms in view")
					_check(_on_screen(close), "themed Info close remains visible")
					await _save_frame("shop-info",shape)
					if close != null:
						close.pressed.emit()
					await _settle()
					_check(shop._purchase_info == null and shop._selected_product_id == id, "Info close returns to same selected bundle")
			_check(_on_screen(shop._refresh) and _on_screen(shop._status_label), "shop restore/status remain visible")
			_check(not _under_scroll(shop._refresh), "restore independent of product scroll")
			host.queue_free()
			await _settle()
			if _shop_portrait_only: continue
		var controls := load("res://scenes/menus/controls.tscn").instantiate() as Control
		add_child(controls)
		await _settle()
		for action: String in SettingsManager.REMAPPABLE_ACTIONS:
			var symbol := controls.find_child("ActionIcon_"+action,true,false) as TextureRect
			if symbol != null:
				var row := symbol.get_parent() as Control
				var text_stack := row.get_child(1) as Control
				var name_label := text_stack.get_child(0) as Label
				_check(row.get_global_rect().grow(1.0).encloses(symbol.get_global_rect()) and not symbol.get_global_rect().intersects(text_stack.get_global_rect()), "action icon fits beside readable name: "+action)
				_check(name_label.get_visible_line_count() == name_label.get_line_count() and not text_stack.get_global_rect().intersects(row.get_child(row.get_child_count()-1).get_global_rect()), "full action name clears binding caps: "+action)
			for family: String in ["key","joy"]:
				var cap := controls._binding_buttons[action+"/"+family] as Button
				if action == "pause" and family == "key": print("[page-corrections] controls scroll=%s pause=%s" % [controls._scroll.get_global_rect(),cap.get_global_rect()])
				_check(cap.text == controls._binding_glyph(SettingsManager.describe_action_binding(action,family),family) and cap.tooltip_text == SettingsManager.describe_action_binding(action,family), "real binding retained: "+action+"/"+family)
				_check(controls._scroll.get_global_rect().grow(1.0).encloses(cap.get_global_rect()), "complete keycap visible before scrolling: "+action+"/"+family)
				if shape.x > shape.y:
					var pixels := float(cap.get_theme_font_size("font_size")) * float(shape.x) / get_viewport().get_visible_rect().size.x
					_check(pixels >= 14.0, "desktop binding type reaches 14 native pixels")
		var binding_help := controls.find_child("ControlsRebindHelp",true,false) as Label
		print("[page-corrections] binding-help=%s scroll=%s" % [binding_help.get_global_rect(), controls._scroll.get_global_rect()])
		_check(controls._scroll.get_global_rect().grow(1.0).encloses(binding_help.get_global_rect()) and binding_help.get_visible_line_count() == binding_help.get_line_count(), "complete rebinding help visible before scrolling")
		controls._begin_capture("jump","key")
		_check(controls._capture_overlay.visible, "binding still opens capture")
		controls._end_capture()
		_check(not controls._capture_overlay.visible, "cancel closes capture")
		await _save_frame("controls",shape)
		controls.queue_free()
		await _settle()
		var credits := load("res://scenes/menus/credits.tscn").instantiate() as Control
		add_child(credits)
		await _settle()
		var journal := credits.find_child("ExpeditionContentScroll",true,false) as ScrollContainer
		for name: String in ["MadeWithCare","Team","ArtMusic","SpecialThanks"]:
			var section := credits.find_child("CreditsSection_"+name,true,false) as Control
			print("[page-corrections] credits=%s scroll=%s section=%s" % [name,journal.get_global_rect(),section.get_global_rect()])
			_check(section != null and journal.get_global_rect().grow(1.0).encloses(section.get_global_rect()), "complete credits section in first view: "+name)
		_check(credits.find_child("CreditsSection_Typefaces",true,false) != null, "font attribution retained below main credits")
		await _save_frame("credits",shape)
		credits.queue_free()
		await _settle()
		var settings := load("res://scenes/menus/settings.tscn").instantiate() as Control
		add_child(settings)
		await _settle()
		var note := settings.find_child("SettingsSaveNote",true,false) as Label
		_check(_on_screen(note) and not _under_scroll(note), "settings save note fully visible outside scroll")
		var settings_scroll := settings.find_child("SettingsContentScroll",true,false) as Control
		for key: String in ["camera_shake", "reduced_flashing", "high_contrast_pickups", "colorblind_cues", "audio_visual_cues", "pause_on_disconnect", "hud_scale", "ui_scale"]:
			var field := settings.find_child("Settings_accessibility_" + key, true, false) as Control
			_check(field != null and settings_scroll.get_global_rect().grow(1.0).encloses(field.get_global_rect()), "all comfort settings visible before scrolling: " + key)
		_check(_on_screen(settings.find_child("SettingsReset_accessibility", true, false)), "comfort reset remains visible")
		await _save_frame("settings",shape)
		settings.queue_free()
		await _settle()
		if _owned_utility_only:
			var modes := load("res://scenes/menus/mode_select.tscn").instantiate() as Control
			add_child(modes)
			await _settle()
			_check(modes._buttons.size() == 5, "four actual modes and top Back are connected")
			for title: String in ["QuickRace", "GrandPrix", "TimeTrial", "EndlessExpedition"]:
				var button := modes.find_child("RaceMode_" + title, true, false) as Button
				_check(button != null and _on_screen(button), "whole illustrated mode card visible: " + title)
				_check(not button.pressed.get_connections().is_empty(), "mode card has real action: " + title)
				var art := modes.find_child("ModeIllustration_" + title, true, false) as TextureRect
				_check(art != null and art.texture is AtlasTexture, "mode uses actual reference illustration: " + title)
				var mode_name := modes.find_child("ModeName_" + title, true, false) as Label
				_check(button.get_global_rect().grow(-4.0).encloses(mode_name.get_global_rect()) and mode_name.get_visible_line_count() == mode_name.get_line_count(), "whole mode name stays within card: " + title)
				_check(mode_name.get_line_count() == (2 if title == "EndlessExpedition" else 1), "mode title retains intended line count: " + title)
			_check(_on_screen(modes.find_child("RaceSetupBack", true, false)), "race top Back fits")
			await _save_frame("race-setup", shape)
			(modes.find_child("RaceMode_QuickRace", true, false) as Button).pressed.emit()
			await _settle()
			_check(modes._step == "course" and modes._chosen_mode == Game.Mode.QUICK_RACE, "Quick Race enters real course selection")
			modes._go_back_step()
			await _settle()
			_check(modes._step == "mode", "course Back restores mode selection")
			(modes.find_child("RaceMode_GrandPrix", true, false) as Button).pressed.emit()
			await _settle()
			_check(modes._step == "difficulty" and modes._chosen_mode == Game.Mode.GRAND_PRIX, "Grand Prix enters actual difficulty selection")
			modes._go_back_step()
			await _settle()
			_check(modes._step == "mode", "Grand Prix Back returns to mode selection")
			modes.queue_free()
			await _settle()

	for player: AudioStreamPlayer in [AudioManager._music_a,AudioManager._music_b]:
		player.stop()
		player.stream=null
	for player: AudioStreamPlayer in AudioManager._sfx_pool:
		player.stop()
		player.stream=null
	await get_tree().create_timer(0.25).timeout
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
		var report := FileAccess.open(_out.path_join("report.json"),FileAccess.WRITE)
		report.store_string(JSON.stringify({"checks":_checks,"failures":_failures,"frames":_frames,"limit":"Isolated offline UI state and native stills. No purchase, auth, restore, remapping write or network action."},"\t"))
	print("[page-corrections] %d/%d checks passed; %d captures" % [_checks-_failures.size(),_checks,_frames.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)

func _settle() -> void:
	for index in 6: await get_tree().process_frame

func _check(ok: bool,message: String) -> void:
	_checks+=1
	if not ok:
		_failures.append(message)
		push_error("[page-corrections] "+message)

func _on_screen(control: Control) -> bool:
	return control != null and get_viewport().get_visible_rect().grow(1.0).encloses(control.get_global_rect())

func _under_scroll(node: Node) -> bool:
	var parent := node.get_parent()
	while parent != null:
		if parent is ScrollContainer: return true
		parent=parent.get_parent()
	return false

func _save_frame(page: String,shape: Vector2i) -> void:
	if GameConfig.is_headless() or _out.is_empty(): return
	if _cozy_capture_only and page not in ["shop-cozy_expedition","shop-info"]: return
	DisplayServer.window_move_to_foreground()
	await get_tree().create_timer(0.45).timeout
	for attempt in 3:
		DisplayServer.window_move_to_foreground()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if get_window().has_focus(): break
	var pixels := get_viewport().get_texture().get_image()
	_check(get_window().has_focus() and pixels != null and pixels.get_size() == shape,"focused native capture: "+page)
	if pixels == null or not get_window().has_focus() or pixels.get_size() != shape: return
	DirAccess.make_dir_recursive_absolute(_out)
	var path := _out.path_join("%s-%dx%d.png" % [page,shape.x,shape.y])
	_check(pixels.save_png(path) == OK,"PNG saved: "+page)
	_frames.append({"page":page,"path":path,"focused":get_window().has_focus(),"visible":get_window().visible})
