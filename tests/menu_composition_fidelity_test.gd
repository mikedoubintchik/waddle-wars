extends Node
## Current menu composition and truthful state, using isolated local progress.
## Native optional stills require foreground renderer and separate visual review.
var _checks := 0
var _failures: Array[String] = []
var _frames: Array[Dictionary] = []
var _out := ""

func _ready() -> void:
	if not String(ProjectSettings.get_setting("application/config/custom_user_dir_name", "")).begins_with("waddle-wars-wardrobe-"):
		push_error("Composition fixture requires isolated wardrobe user data")
		get_tree().quit(2)
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="): _out = arg.trim_prefix("out=")
	LeaderboardClient.set_process(false)
	CommerceClient.set_process(false)
	NativeAuthClient.set_process(false)
	LayoutProfile.forced_insets = Vector4.ZERO
	SaveManager.data = SaveManager.default_save()
	SaveManager.set_value("fish", 5000)
	SaveManager.set_value("stats", {"runner_fish_collected": 37})
	for shape: Vector2i in [Vector2i(540,960),Vector2i(960,540)]:
		GameConfig.force_touch = shape.y > shape.x
		SettingsManager.settings["display"]["window_mode"] = "windowed"
		SettingsManager.settings["display"]["resolution"] = "%dx%d" % [shape.x,shape.y]
		SettingsManager.settings["accessibility"]["reduced_flashing"] = true
		SettingsManager.apply_all()
		if GameConfig.is_headless():
			get_window().size = shape
			get_window().content_scale_size = Vector2i(800,1422) if shape.y > shape.x else Vector2i(1920,1080)
		await _settle()
		var menu := load("res://scenes/menus/customize.tscn").instantiate() as Control
		add_child(menu)
		await _settle()
		var before := SaveManager.data.duplicate(true)
		menu.call("_select_category","scarf")
		menu.call("_select_item","scarf_red")
		menu.call("_select_category","body")
		await _ready_preview(menu)
		_check(SaveManager.data == before,"multi-slot preview leaves actual save unchanged")
		_check(_visible(menu._detail_action),"wardrobe action visible")
		_check(_visible(menu._try_on_note) and _visible(menu._reset_try_on_button),"try-on status and Reset visible inside footer")
		_check(menu._try_on_note.get_parent().get_parent().name == "TryOnFooter","temporary state integrated into wardrobe footer")
		_check(_visible(menu.find_child("WardrobeCategories",true,false)),"all five categories visible")
		_check(_visible(menu._gallery_scroll),"carousel visible")
		_check(_feet_on_baseline(menu._outfit_stage),"transparent margins do not lift preview feet")
		if shape.x > shape.y:
			_check(menu.find_child("WardrobeEnclosure",true,false) != null,"desktop wardrobe has enclosing choice panel")
		await _capture(menu,"wardrobe-body",shape)
		menu.call("_select_category","hat")
		menu.call("_select_item","hat_beanie")
		await _ready_preview(menu)
		_check(SaveManager.data == before,"hat preview neither purchases nor equips")
		_check(_visible(menu._try_on_note),"multi-slot draft state visible")
		_check(_feet_on_baseline(menu._outfit_stage),"hat variation keeps same grounded baseline")
		await _capture(menu,"wardrobe-hat",shape)
		menu.queue_free()
		await _settle()
		var host := load("res://scenes/menus/cosmetic_shop.tscn").instantiate() as Control
		add_child(host)
		await _settle()
		var shop: Control
		for child in host.get_children():
			if child is PremiumCosmeticShop: shop = child
		_check(shop != null,"production Shop instantiated")
		_check(_visible(shop._currency_cap) and shop._currency_cap.tooltip_text == "5,000 fish","reference currency cap retains actual balance")
		var shop_art := host.get_node("ExpeditionMenuArt") as TextureRect
		_check(shop_art.texture.resource_path.ends_with("shop_background_%s_v3.webp" % ("portrait" if shape.y > shape.x else "desktop")), "Shop uses authored plate for current orientation")
		if shape.x > shape.y:
			_check(shop.find_child("ShopBundleEnclosure",true,false) != null,"desktop bundles share enclosing reference panel")
		for product: Dictionary in CommerceCatalog.products():
			var id := String(product["id"])
			shop.call("_select_product",id)
			await _settle()
			var panel: Control = shop._detail_cards[id]
			var action: Control = shop._fish_buttons[id]
			_check(_visible(panel),"whole selected bundle detail visible: "+id)
			_check(_visible(action) and panel.get_global_rect().encloses(action.get_global_rect()),"price CTA enclosed in selected detail and reachable: "+id)
			_check(_visible(shop._fish_prices[id]),"actual fish price visible: "+id)
			_check(shop._selected_banner.text == String(product["name"]).to_upper(),"real bundle name retained: "+id)
			var selector: Button = shop._selector_buttons[id]
			var caption := selector.find_child("BundleName",true,false) as Label
			_check(selector.get_global_rect().grow(-3.0).encloses(caption.get_global_rect()),"bundle caption has unclipped interior padding: "+id)
			for cosmetic: String in product["cosmetics"]:
				var item_icon := panel.find_child("BundleItem_" + cosmetic,true,false) as TextureRect
				_check(item_icon != null and item_icon.texture != null,"every bundle item has actual artwork: "+cosmetic)
			_check(SaveManager.data == before,"bundle browsing never purchases: "+id)
			await _capture(host,"shop-"+id,shape)
		_check(_visible(shop._status_label) and _visible(shop._refresh),"availability and sync visible")
		host.queue_free()
		await _settle()
		var achievements := load("res://scenes/menus/achievements.tscn").instantiate() as Control
		add_child(achievements)
		await _settle()
		_check(achievements._achievement_buttons.size() == AchievementsDB.RUNNER_ORDER.size(),"all32 runner trophies retained")
		_check(achievements._display_order().slice(0,3) == PackedStringArray(["runner_fish_bronze","runner_missions_bronze","runner_distance_bronze"]),"first trophy row follows reference order")
		if shape.x > shape.y:
			_check((achievements.get_node("ExpeditionMenuArt") as TextureRect).texture.resource_path.ends_with("achievement_background_desktop_v3.webp"),"desktop trophies use wide lodge plate")
		_check(_visible(achievements._detail.get_parent()),"selected trophy detail visible")
		_check(achievements._detail.find_child("AchievementReward",true,false) != null,"real XP reward represented")
		var detail_progress := achievements._detail.find_child("AchievementDetailProgress",true,false) as ProgressBar
		var fish_goal := AchievementsDB.get_item("runner_fish_bronze")
		_check(detail_progress != null and detail_progress.max_value == fish_goal["target"]
			and detail_progress.value == 37,"Fish Finder detail shows actual pickup progress independently of wallet balance")
		for id: String in AchievementsDB.RUNNER_ORDER:
			achievements.call("_select_achievement",id)
			_check(achievements._selected_id == id,"select exact trophy: "+id)
			var badge := achievements._achievement_buttons[id] as Button
			var track := badge.find_child("AchievementTileProgress",true,false) as ProgressBar
			_check(track != null and badge.get_global_rect().grow(-8.0).encloses(track.get_global_rect()),"trophy progress track stays inset inside its card: "+id)
		achievements.call("_select_achievement","runner_fish_bronze")
		await _settle()
		await _capture(achievements,"achievements",shape)
		achievements.queue_free()
		await _settle()
	for player: AudioStreamPlayer in [AudioManager._music_a,AudioManager._music_b]:
		player.stop()
		player.stream = null
	for player: AudioStreamPlayer in AudioManager._sfx_pool:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.25).timeout
	var receipt := {"checks":_checks,"passed":_checks-_failures.size(),"failures":_failures,"frames":_frames,"limits":"Isolated real menu controls and local state. No purchases/auth/restore dispatched. Native visual evidence valid only for listed focused frames."}
	if not _out.is_empty():
		DirAccess.make_dir_recursive_absolute(_out)
		var report := FileAccess.open(_out.path_join("composition.json"),FileAccess.WRITE)
		report.store_string(JSON.stringify(receipt,"\t"))
	print("[menu-composition] %d/%d passed; %d frames" % [receipt.passed,_checks,_frames.size()])
	get_tree().quit(0 if _failures.is_empty() else 1)

func _settle() -> void:
	for i in 8: await get_tree().process_frame

func _ready_preview(menu: Control) -> void:
	var deadline := Time.get_ticks_msec()+5000
	while menu._outfit_library.state == "loading" and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(menu._outfit_library.state == "ready","exact complete outfit available")
	await _settle()

func _visible(control: Control) -> bool:
	if control == null or not control.is_visible_in_tree(): return false
	var rect := control.get_global_rect()
	if not get_viewport().get_visible_rect().grow(1.0).encloses(rect):
		print("[menu-composition] out of viewport: ",control.name," ",rect)
		return false
	var node := control.get_parent()
	while node != null:
		if node is ScrollContainer and not node.get_global_rect().grow(1.0).encloses(rect):
			print("[menu-composition] clipped: ",control.name," ",rect," by ",node.get_global_rect())
			return false
		node = node.get_parent()
	return true

func _feet_on_baseline(stage: Control) -> bool:
	var bounds: Rect2 = stage._opaque_bounds
	var sprite: TextureRect = stage.sprite
	if not bounds.has_area() or sprite.texture == null: return false
	var factor := sprite.size.y / sprite.texture.get_height()
	return absf(sprite.position.y + bounds.end.y * factor - stage.size.y * 0.96) < 1.0

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		push_error("[menu-composition] "+message)

func _capture(_page: Control, label: String,shape: Vector2i) -> void:
	if GameConfig.is_headless() or _out.is_empty(): return
	DisplayServer.window_move_to_foreground()
	await get_tree().create_timer(0.45).timeout
	DisplayServer.window_move_to_foreground()
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var valid := get_window().has_focus() and get_window().visible and image != null and image.get_size() == shape
	_check(valid,"focused frame: "+label)
	if not valid: return
	DirAccess.make_dir_recursive_absolute(_out)
	var path := _out.path_join("%s-%dx%d.png" % [label,shape.x,shape.y])
	_check(image.save_png(path) == OK,"saved frame: "+label)
	_frames.append({"page":label,"path":path,"focused":true,"visible":true})
