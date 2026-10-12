extends Control
## Waddle Run's live board in an art-led race-arena layout.

var _page: Control = null
var _rows: VBoxContainer = null
var _status: Label = null
var _standings_scroll: ScrollContainer = null
var _board_stack: VBoxContainer = null
var _serial: int = 0
var _portrait: bool = true
var _safe_size := Vector2.ZERO
var _podium_labels: Array[Label] = []
var _local_rank: Label
var _local_name: Label
var _local_score: Label
var _post_button: Button
var _refresh_button: Button
var _post_status: Label
var _post_serial: int = 0
var _active_post_serial: int = -1
var _post_busy: bool = false
var _post_message: String = ""
var _known_server_best: int = 0
var _auth_button: Button
var _shown_auth_owner: String = ""
var _shown_auth_generation: int = -1
var _shown_signed_in: bool = false
var _auth_rebuild_queued: bool = false


func _ready() -> void:
	UITheme.apply_ui_scale(self)
	ExpeditionMenuStyle.add_backdrop(self, "leaderboard")
	_build()
	get_viewport().size_changed.connect(_rebuild)
	LeaderboardClient.auth_changed.connect(_on_auth_changed)
	LeaderboardClient.score_submission_changed.connect(_on_score_submission_changed)
	UITheme.attach_swipe_back(self, _back)
	_fetch()


func _rebuild() -> void:
	_serial += 1
	if _page != null:
		_page.free()
	_build()
	_fetch()


func _on_auth_changed() -> void:
	if _shown_auth_owner == LeaderboardClient._auth_owner_id \
			and _shown_auth_generation == LeaderboardClient._auth_generation \
			and _shown_signed_in == LeaderboardClient.signed_in:
		AccountAuthPresentation.update_button(_auth_button, "SIGN IN")
		_update_post_controls()
		return
	# A pending callback belongs to the account that started it, even if that
	# same account signs back in after another account used this screen.
	_post_serial += 1
	_active_post_serial = -1
	_post_busy = false
	_post_message = ""
	_known_server_best = 0
	# Auth state may arrive synchronously from a button signal. Rebuild only
	# after that signal returns; status-only changes do not refetch the board.
	if not _auth_rebuild_queued:
		_auth_rebuild_queued = true
		_rebuild_after_auth.call_deferred()


func _rebuild_after_auth() -> void:
	_auth_rebuild_queued = false
	if is_inside_tree():
		_rebuild()


func _build() -> void:
	_shown_auth_owner = LeaderboardClient._auth_owner_id
	_shown_auth_generation = LeaderboardClient._auth_generation
	_shown_signed_in = LeaderboardClient.signed_in
	var shell := ExpeditionSubmenuShell.build(self, "leaderboard",
		"Leaderboard", 0.25)
	_page = shell["root"] as Control
	var content := shell["content"] as VBoxContainer
	_portrait = bool(shell["portrait"])
	_safe_size = (shell["profile"] as LayoutProfile).safe_rect.size
	_podium_labels.clear()
	if _portrait:
		var podium_overlay := Control.new()
		podium_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_page.add_child(podium_overlay)
		for point: Vector2 in [Vector2(0.50, 0.419), Vector2(0.25, 0.431), Vector2(0.77, 0.442)]:
			var plate := Panel.new()
			plate.name = "PodiumName%d" % _podium_labels.size()
			plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
			plate.add_theme_stylebox_override("panel", ExpeditionMenuStyle.material_box(false, 4.0, 2.0))
			podium_overlay.add_child(plate)
			plate.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			plate.position = _safe_size * point - Vector2(_safe_size.x * 0.10, 0.0)
			plate.size = Vector2(_safe_size.x * 0.20, _safe_size.y * 0.033)
			var label := ExpeditionMenuStyle.label("", roundi(_safe_size.y * 0.016))
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.clip_text = true
			label.autowrap_mode = TextServer.AUTOWRAP_OFF
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			plate.add_child(label)
			label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			label.offset_left = 5.0
			label.offset_right = -5.0
			plate.hide()
			_podium_labels.append(label)
	content.add_theme_constant_override("separation", roundi(_safe_size.y * 0.015))
	_add_podium_rank_labels()
	var header := shell["header"] as Control
	var balance := ExpeditionMenuStyle.currency_pill(Progression.get_fish(), false)
	balance.name = "BoardFishBalance"
	balance.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	balance.offset_left = -_safe_size.x * (0.22 if _portrait else 0.15)
	balance.offset_right = 0.0
	# Put the compact phone cap in the shell's top gutter, clear of the
	# title's rising right edge while retaining the physical safe inset.
	if _portrait:
		balance.offset_top = -float(_page.get_theme_constant("margin_top"))
	balance.offset_bottom = balance.offset_top + _safe_size.y * (0.045 if _portrait else 0.10)
	header.add_child(balance)
	var fish_icon := balance.find_child("FishSymbol", true, false) as TextureRect
	fish_icon.custom_minimum_size = Vector2.ONE * _safe_size.y * (0.032 if _portrait else 0.07)
	var fish_count := balance.find_child("FishAmount", true, false) as Label
	fish_count.add_theme_font_size_override("font_size", roundi(_safe_size.y * (0.021 if _portrait else 0.052)))
	var title_art := header.find_child("ApprovedTitleArtwork", true, false) as TextureRect
	if title_art != null:
		var title_width := _safe_size.x * (0.73 if _portrait else 0.49)
		title_art.offset_left = -title_width * 0.5
		title_art.offset_right = title_width * 0.5
		if _portrait: title_art.offset_bottom = header.custom_minimum_size.y * 0.80
		if _portrait:
			title_art.offset_top = 0.0
		else:
			header.custom_minimum_size.y = _safe_size.y * 0.18
			title_art.offset_bottom = _safe_size.y * 0.24
	UtilityScreenLayout.defer_header_alignment(self, title_art, shell["back"] as Control, [balance])
	var board := ExpeditionSubmenuShell.card(content)
	_board_stack = board
	board.name = "StandingsSheet"
	(board.get_parent() as PanelContainer).add_theme_stylebox_override("panel", ExpeditionMenuStyle.material_card(20.0, 18.0))
	board.custom_minimum_size.y = _safe_size.y * (0.28 if _portrait else 0.43)
	board.add_theme_constant_override("separation", 4)
	_status = ExpeditionSubmenuShell.note(board, "Loading global scores…", 18)
	_status.add_theme_font_size_override("font_size", roundi(_safe_size.y * (0.022 if _portrait else 0.032)))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.custom_minimum_size.y = _safe_size.y * (0.14 if _portrait else 0.25)
	_status.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var standings_scroll := ScrollContainer.new()
	_standings_scroll = standings_scroll
	standings_scroll.name = "StandingsScroll"
	standings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	standings_scroll.custom_minimum_size.y = _safe_size.y * (0.218 if _portrait else 0.335)
	standings_scroll.follow_focus = true
	TouchScroll.attach(standings_scroll)
	board.add_child(standings_scroll)
	# Loading/empty/error states have their own status area. Reserving an
	# additional empty list here pushes the real footer actions off screen.
	standings_scroll.hide()
	_rows = VBoxContainer.new()
	_rows.name = "GlobalStandings"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 4)
	standings_scroll.add_child(_rows)
	var local := ExpeditionMenuStyle.panel(board)
	local.name = "LocalBestRow"
	local.add_theme_stylebox_override("panel", ExpeditionMenuStyle.material_box(true, 14.0, 7.0))
	local.custom_minimum_size.y = _safe_size.y * (0.075 if _portrait else 0.10)
	var local_row := HBoxContainer.new()
	local_row.add_theme_constant_override("separation", 12)
	local.add_child(local_row)
	var local_badge := ExpeditionSubmenuShell.heading(local_row, "LOCAL\nBEST", 18)
	local_badge.add_theme_font_size_override("font_size", roundi(_safe_size.y * (0.015 if _portrait else 0.022)))
	_local_rank = local_badge
	local_badge.add_theme_color_override("font_color", Color.WHITE)
	local_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	local_badge.autowrap_mode = TextServer.AUTOWRAP_OFF
	var avatar := TextureRect.new()
	avatar.texture = ExpeditionMenuStyle._material_texture("res://assets/art/ui/menu/home_profile_icon_exact_v1.webp")
	avatar.custom_minimum_size = Vector2.ONE * local.custom_minimum_size.y * 0.78
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	local_row.add_child(avatar)
	var name := ExpeditionSubmenuShell.heading(local_row, LeaderboardClient.player_display_name()
		if LeaderboardClient.signed_in else "You", 25)
	_local_name = name
	name.add_theme_font_size_override("font_size", roundi(_safe_size.y * (0.024 if _portrait else 0.028)))
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.autowrap_mode = TextServer.AUTOWRAP_OFF
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name.add_theme_color_override("font_color", Color.WHITE)
	_add_score_star(local_row, local.custom_minimum_size.y * 0.76)
	var best := ExpeditionSubmenuShell.heading(local_row,
		_format_score(Progression.runner_high_score()), 28)
	_local_score = best
	best.add_theme_font_size_override("font_size", roundi(_safe_size.y * (0.026 if _portrait else 0.032)))
	best.add_theme_color_override("font_color", Color.WHITE)
	best.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	best.autowrap_mode = TextServer.AUTOWRAP_OFF
	var challenge := ExpeditionMenuStyle.button("CHALLENGE FRIENDS", true,
		roundi(_safe_size.y * (0.032 if _portrait else 0.047)), _safe_size.y * (0.087 if _portrait else 0.12))
	challenge.name = "ChallengeFriends"
	challenge.add_theme_font_override("font", ExpeditionMenuStyle.display_font())
	challenge.icon = UITheme.make_icon('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><path d="m16 32 32-18M16 32l32 18" stroke="white" stroke-width="7"/><g fill="white"><circle cx="14" cy="32" r="10"/><circle cx="49" cy="13" r="10"/><circle cx="49" cy="51" r="10"/></g></svg>')
	ExpeditionMenuStyle.illustrated_action(challenge, "CHALLENGE FRIENDS", challenge.icon,
		roundi(_safe_size.y * (0.032 if _portrait else 0.047)), challenge.custom_minimum_size.y * 0.70, false)
	challenge.pressed.connect(func() -> void:
		ShareManager.share_with_toast(self, ShareManager.compose_challenge_text()))
	content.add_child(challenge)
	var utility_group := VBoxContainer.new()
	utility_group.add_theme_constant_override("separation", 4)
	content.add_child(utility_group)
	_post_status = ExpeditionSubmenuShell.note(utility_group, "", 18)
	_post_status.name = "BoardPostStatus"
	_post_status.add_theme_font_size_override("font_size", roundi(_safe_size.y * (0.017 if _portrait else 0.026)))
	_post_status.custom_minimum_size.y = _safe_size.y * (0.042 if _portrait else 0.055)
	_post_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_post_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_post_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var utilities := HBoxContainer.new()
	utilities.add_theme_constant_override("separation", 12)
	utility_group.add_child(utilities)
	_post_button = null
	_auth_button = null
	if not LeaderboardClient.signed_in and LeaderboardClient.can_sign_in():
		var sign_in := ExpeditionMenuStyle.button("SIGN IN", false, roundi(_safe_size.y * (0.019 if _portrait else 0.028)), _safe_size.y * (0.048 if _portrait else 0.07))
		_auth_button = sign_in
		sign_in.name = "BoardAuthAction"
		sign_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sign_in.pressed.connect(AccountAuthPresentation.activate)
		utilities.add_child(sign_in)
		AccountAuthPresentation.update_button(sign_in, "SIGN IN")
	elif LeaderboardClient.signed_in and LeaderboardClient.can_sign_in() and AccountAuthPresentation.account_surface_enabled():
		_post_button = ExpeditionMenuStyle.button("POST LOCAL BEST", false,
			roundi(_safe_size.y * (0.019 if _portrait else 0.028)), _safe_size.y * (0.048 if _portrait else 0.07))
		_post_button.name = "BoardPostLocalBest"
		_post_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_post_button.pressed.connect(_post_local_best)
		utilities.add_child(_post_button)
	var retry := ExpeditionMenuStyle.button("REFRESH BOARD", false, roundi(_safe_size.y * (0.019 if _portrait else 0.028)), _safe_size.y * (0.048 if _portrait else 0.07))
	_refresh_button = retry
	retry.name = "BoardRefresh"
	retry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	retry.pressed.connect(_fetch)
	utilities.add_child(retry)
	_update_post_controls()


func _fetch() -> void:
	if _rows == null:
		return
	_clear_rows()
	_status.visible = true
	_status.text = "Loading global scores…"
	_status.custom_minimum_size.y = _empty_status_height()
	_refresh_button.disabled = true
	_serial += 1
	var requested := _serial
	var owner: WeakRef = weakref(self)
	var deliver := func(ok: bool, data: Dictionary) -> void:
		var screen: Variant = owner.get_ref()
		if screen != null and is_instance_valid(screen):
			(screen as Node).call("_receive", requested, ok, data)
	LeaderboardClient.fetch_board("runner", "runner", 20, deliver)


func _receive(requested: int, ok: bool, data: Dictionary) -> void:
	if requested != _serial or not is_inside_tree():
		return
	_refresh_button.disabled = false
	_clear_rows()
	if not ok:
		_status.show()
		_status.text = "Global board unavailable. Your local best is safe."
		_status.custom_minimum_size.y = _empty_status_height()
		_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if _post_message == "Best posted. Updating ranks…":
			_post_message = "Best posted. Refresh board to see your rank."
		_update_post_controls()
		return
	var entries: Array = data.get("entries", [])
	# The row ranks carry this information once loaded; reserve the status
	# line for actual loading, empty and unavailable states.
	_status.visible = entries.is_empty()
	_status.custom_minimum_size.y = 0.0
	var own: Variant = data.get("me")
	if own is Dictionary and int((own as Dictionary).get("rank", 0)) > 0:
		_known_server_best = maxi(_known_server_best, int((own as Dictionary).get("value", 0)))
		if _post_message.begins_with("Best posted."):
			_post_message = "Best posted. Your global rank is #%d." % int((own as Dictionary)["rank"])
		_status.text = "YOUR GLOBAL RANK  #%d" % int((own as Dictionary)["rank"])
		_local_rank.text = "YOUR RANK\n%d" % int((own as Dictionary)["rank"])
		_local_score.text = _format_score(int((own as Dictionary).get("value", 0)))
	elif entries.is_empty():
		_status.text = "No scores posted yet. Be first on the board!"
	else:
		_status.text = "TOP EXPLORERS"
	var occupied_podium_ranks: Dictionary = {}
	for entry: Variant in entries:
		if not entry is Dictionary:
			continue
		var row := entry as Dictionary
		var rank := int(row.get("rank", 0))
		var shown_on_podium := false
		if rank >= 1 and rank <= _podium_labels.size() and not occupied_podium_ranks.has(rank):
			var podium := _podium_labels[rank - 1]
			podium.text = String(row.get("name", "Explorer"))
			podium.tooltip_text = podium.text
			podium.get_parent().show()
			occupied_podium_ranks[rank] = true
			shown_on_podium = true
		if bool(row.get("is_me", false)):
			_local_name.text = String(row.get("name", "You"))
			continue
		# Tied ranks (for example 1, 1, 3) share a rank, not a display slot.
		# Keep the first name on that podium; retain every peer in the list.
		if _portrait and shown_on_podium:
			continue
		_add_row(int(row.get("rank", 0)), String(row.get("name", "Explorer")),
			int(row.get("value", 0)), bool(row.get("is_me", false)))
	_standings_scroll.visible = _rows.get_child_count() > 0
	if own is Dictionary and int((own as Dictionary).get("rank", 0)) > 0:
		var shown := false
		for entry: Variant in entries:
			if entry is Dictionary and bool((entry as Dictionary).get("is_me", false)):
				shown = true
		if not shown:
			_local_name.text = LeaderboardClient.player_display_name() if LeaderboardClient.signed_in else "You"
	_update_post_controls()


func _update_post_controls() -> void:
	if _post_status == null:
		return
	var local_best := Progression.runner_high_score()
	var can_post := _post_button != null and LeaderboardClient.signed_in and local_best > 0
	var auth_message := AccountAuthPresentation.message() if not LeaderboardClient.signed_in and LeaderboardClient.can_sign_in() else ""
	_post_status.visible = can_post or not auth_message.is_empty()
	if not can_post:
		_post_status.text = auth_message
	if _post_button != null:
		_post_button.visible = can_post
	if can_post:
		var state := LeaderboardClient.score_submission_status("runner", "runner")
		var posting := _post_busy or state == "posting"
		var pending := state == "pending"
		var posted_best := maxi(_known_server_best, LeaderboardClient.posted_score_value("runner", "runner"))
		var already_posted := posted_best >= local_best and not pending
		_post_button.disabled = posting or already_posted
		_post_button.text = "POSTING…" if posting else ("RETRY POST" if pending else
			("BEST POSTED" if already_posted else "POST LOCAL BEST"))
		if posting:
			_post_status.text = "Posting your best…"
		elif not _post_message.is_empty():
			_post_status.text = _post_message
		elif pending:
			_post_status.text = "Your best is waiting to post. Try again."
		elif already_posted:
			_post_status.text = "Your best is on the global board."
		else:
			_post_status.text = "Share your best: %s points." % _format_score(local_best)
	# The message takes space from the standings, preserving the existing
	# first-screen footer bounds on both portrait and desktop layouts.
	# Four pixels separate the utility rows; another eight keep their painted
	# button edges clear of the outer scroll boundary at smaller viewports.
	var reserved := _post_status.custom_minimum_size.y + 12.0 if _post_status.visible else 0.0
	# Empty boards otherwise retain this larger minimum after their status
	# area shrinks, pushing the post actions below the outer scroll clip.
	_board_stack.custom_minimum_size.y = _safe_size.y * (0.28 if _portrait else 0.43) - reserved
	_standings_scroll.custom_minimum_size.y = _safe_size.y * (0.218 if _portrait else 0.335) - reserved
	if _status.visible and _status.custom_minimum_size.y > 0.0:
		_status.custom_minimum_size.y = _empty_status_height()


func _empty_status_height() -> float:
	var reserved := _post_status.custom_minimum_size.y + 12.0 if _post_status != null and _post_status.visible else 0.0
	return _safe_size.y * (0.14 if _portrait else 0.25) - reserved


func _post_local_best() -> void:
	if _post_busy or not LeaderboardClient.signed_in or not LeaderboardClient.can_sign_in() \
			or not AccountAuthPresentation.account_surface_enabled() \
			or LeaderboardClient.score_submission_status("runner", "runner") == "posting":
		return
	var value := Progression.runner_high_score()
	if value <= 0:
		return
	var pending := LeaderboardClient.score_submission_status("runner", "runner") == "pending"
	if not pending and maxi(_known_server_best, LeaderboardClient.posted_score_value("runner", "runner")) >= value:
		return
	_post_busy = true
	_post_message = ""
	_post_serial += 1
	var requested := _post_serial
	_active_post_serial = requested
	var owner: WeakRef = weakref(self)
	var deliver := func(ok: bool, data: Dictionary) -> void:
		var screen: Variant = owner.get_ref()
		if screen != null and is_instance_valid(screen):
			(screen as Node).call("_receive_post", requested, ok, data)
	_update_post_controls()
	_send_local_score(value, pending and LeaderboardClient.pending_score_value("runner", "runner") >= value, deliver)


func _send_local_score(value: int, retry_pending: bool, deliver: Callable) -> void:
	if retry_pending:
		if not LeaderboardClient.retry_pending_score("runner", "runner", deliver):
			deliver.call(false, {"error": "retry unavailable"})
	else:
		LeaderboardClient.submit_score("runner", "runner", value, deliver)


func _receive_post(requested: int, ok: bool, data: Dictionary) -> void:
	if requested != _post_serial or requested != _active_post_serial \
			or not is_inside_tree() or not LeaderboardClient.signed_in:
		return
	_active_post_serial = -1
	_post_busy = false
	if ok:
		_known_server_best = maxi(_known_server_best, int(data.get("best", 0)))
		var rank := int(data.get("rank", 0))
		if LeaderboardClient.score_submission_status("runner", "runner") == "pending":
			_post_message = "Score posted. A newer best is waiting."
		else:
			_post_message = "Best posted. Your global rank is #%d." % rank if rank > 0 else "Best posted. Updating ranks…"
	else:
		_post_message = "Post failed. Your local best is safe. Try again."
	_update_post_controls()
	if ok:
		_fetch()


func _on_score_submission_changed(mode: String, course: String) -> void:
	if mode != "runner" or course != "runner" or not is_inside_tree():
		return
	var state := LeaderboardClient.score_submission_status(mode, course)
	var own_request := _post_busy
	if state == "pending":
		_post_busy = false
		_post_message = "Your best is waiting to post. Try again."
	elif state == "posted":
		_post_busy = false
		_post_message = "Best posted. Updating ranks…"
	_update_post_controls()
	if state == "posted" and not own_request:
		_fetch()


func _add_row(rank: int, player_name: String, score: int,
		mine: bool) -> void:
	var desktop := not UITheme.is_touch()
	var panel := ExpeditionMenuStyle.panel(_rows,
		Color("ffe8d8") if mine else ExpeditionMenuStyle.IVORY)
	panel.custom_minimum_size.y = _safe_size.y * (0.075 if desktop else 0.053)
	panel.add_theme_stylebox_override("panel", ExpeditionMenuStyle.material_box(true, 10.0, 2.0) if mine else _standing_row())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14 if desktop else 10)
	panel.add_child(row)
	var rank_label := ExpeditionSubmenuShell.heading(row, "%d" % rank,
		30 if desktop else 22)
	rank_label.custom_minimum_size.x = _safe_size.x * (0.040 if desktop else 0.060)
	var avatar := TextureRect.new()
	# Board API supplies no species/avatar contract. A neutral explorer badge
	# must not imply every remote player selected the same species as this user.
	avatar.texture = ExpeditionMenuStyle._material_texture(
		"res://assets/art/ui/menu/home_profile_icon_exact_v1.webp" if mine else
		"res://assets/art/ui/menu/base_guest_icon_exact_v1.webp")
	avatar.custom_minimum_size = Vector2.ONE * panel.custom_minimum_size.y * 0.85
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(avatar)
	var name_label := ExpeditionSubmenuShell.heading(row, player_name,
		28 if desktop else 20)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.tooltip_text = player_name
	_add_score_star(row, panel.custom_minimum_size.y * 0.72)
	var value := ExpeditionSubmenuShell.heading(row, _format_score(score),
		30 if desktop else 20)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for label: Label in [rank_label, name_label, value]:
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Ellipsis and zero intrinsic width reserve score/rank space even when a
	# public handle is much wider than the available row.
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if mine:
		for label: Label in [rank_label, name_label, value]:
			label.add_theme_color_override("font_color", Color.WHITE)


func _add_score_star(parent: Control, extent: float) -> void:
	var icon := TextureRect.new()
	var region := AtlasTexture.new()
	region.atlas = ExpeditionMenuStyle._material_texture("res://assets/art/ui/menu/controls_icons_v2.webp")
	region.region = Rect2(836, 836, 418, 418)
	region.filter_clip = true
	icon.texture = region
	icon.custom_minimum_size = Vector2.ONE * extent
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(icon)


func _standing_row() -> StyleBoxFlat:
	var style := ExpeditionMenuStyle.surface(Color("faf7ee"), 15, false)
	style.border_color = Color("dfd8cc")
	style.set_border_width_all(1)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	return style


func _clear_rows() -> void:
	_standings_scroll.hide()
	for child in _rows.get_children():
		child.free()
	for podium: Label in _podium_labels:
		podium.get_parent().hide()
	_local_rank.text = "LOCAL\nBEST"
	_local_name.text = LeaderboardClient.player_display_name() if LeaderboardClient.signed_in else "You"
	_local_score.text = _format_score(Progression.runner_high_score())


static func _format_score(value: int) -> String:
	var digits := str(absi(value))
	var formatted := ""
	for index: int in digits.length():
		if index > 0 and (digits.length() - index) % 3 == 0:
			formatted += ","
		formatted += digits[index]
	return ("-" if value < 0 else "") + formatted


func _back() -> void:
	SceneRouter.go_back()


func _font(size: int) -> int:
	return maxi(1, roundi(float(UITheme.scaled_font(size)) *
		(1.25 if UITheme.is_touch() else 1.65)))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		_back()


func _add_podium_rank_labels() -> void:
	# Desktop scene already contains its embossed ranks. Portrait uses clean
	# pedestals so live name plates can fit beneath separately drawn numerals.
	if not _portrait:
		return
	var overlay := Control.new()
	overlay.name = "PodiumRanks"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(overlay)
	var centers: Array = [Vector2(0.50,0.371),Vector2(0.25,0.390),Vector2(0.77,0.410)] if _portrait else [Vector2(0.29,0.733),Vector2(0.15,0.754),Vector2(0.44,0.795)]
	var colors: Array[Color] = [Color("ffda42"),Color("d7e6f2"),Color("e68e52")]
	for index: int in 3:
		var rank := ExpeditionMenuStyle.label(str(index+1),roundi(_safe_size.y*(0.072 if _portrait else 0.14)),colors[index])
		rank.name = "PodiumRank%d" % (index+1)
		rank.add_theme_font_override("font",ExpeditionMenuStyle.display_font())
		rank.add_theme_color_override("font_outline_color",Color("715026") if index != 1 else Color("6683a0"))
		rank.add_theme_constant_override("outline_size",maxi(2,roundi(_safe_size.y*0.003)))
		rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rank.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rank.position = _safe_size*centers[index]-Vector2(_safe_size.x*0.06,_safe_size.y*0.055)
		rank.size = Vector2(_safe_size.x*0.12,_safe_size.y*0.11)
		rank.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(rank)
