extends Node
## Real board presentation with deterministic data and no network/share action.
class SampleBoard extends "res://scripts/ui/leaderboard_premium.gd":
	func _fetch() -> void: pass

var passed := 0
var failed := 0

func _ready() -> void:
	LeaderboardClient.set_process(false)
	for shape: Vector2i in [Vector2i(800,1422), Vector2i(1920,1080)]:
		GameConfig.force_touch = shape.y > shape.x
		LayoutProfile.forced_insets = Vector4.ONE * (24.0 if GameConfig.force_touch else 0.0)
		var viewport := SubViewport.new()
		viewport.size = shape
		add_child(viewport)
		var board := SampleBoard.new()
		viewport.add_child(board)
		board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		await settle()
		check_title_clearance(board)
		check(board._status.visible and board._status.text.contains("Loading"), "initial loading status is truthful")
		check(not board._standings_scroll.visible, "loading reserves no empty standings viewport")
		check_actions(board, shape, "loading")
		var entries: Array[Dictionary] = []
		for i: int in 20:
			entries.append({"rank":i+1,"name":"Explorer %02d" % (i+1),"value":95000-i*2731,"is_me":i==3})
		board._receive(board._serial,true,{"entries":entries,"me":{"rank":4,"value":86807}})
		for i: int in 5: await get_tree().process_frame
		var expected_rows := 16 if shape.y > shape.x else 19
		check(board._rows.get_child_count()==expected_rows,"all remote entries retained across podium and scroll; own result pinned separately")
		for i: int in 3:
			var podium_rank := board.find_child("PodiumRank%d" % (i+1),true,false) as Label
			if shape.y > shape.x:
				check(podium_rank != null and podium_rank.text == str(i+1) and Rect2(Vector2.ZERO,Vector2(shape)).encloses(podium_rank.get_global_rect()),"portrait podium rank visible and correctly numbered")
			else:
				check(podium_rank == null,"desktop embossed podium rank is not duplicated")
		check(board._local_rank.text=="YOUR RANK\n4" and board._local_score.text=="86,807" and board._local_name.text=="Explorer 04","pinned row shows authoritative global rank/name/score")
		var challenge := board.find_child("ChallengeFriends",true,false) as Button
		check(challenge.pressed.get_connections().size()>=1,"challenge retains real share action")
		check(Rect2(Vector2.ZERO,Vector2(shape)).encloses(challenge.get_global_rect()),"challenge stays reachable in first view despite full20 board")
		for key: String in ["BoardFishBalance", "BoardRefresh"]:
			check(Rect2(Vector2.ZERO,Vector2(shape)).encloses((board.find_child(key,true,false) as Control).get_global_rect()),"currency and utility actions stay inside first view: "+key)
		var list := board.find_child("StandingsScroll",true,false) as ScrollContainer
		check(list.get_v_scroll_bar().max_value > list.size.y,"remaining standings reachable by scrolling")
		check(list.visible, "populated standings have a visible scrolling viewport")
		check_actions(board, shape, "populated")
		if shape.y > shape.x:
			for i: int in 3:
				check(board._podium_labels[i].text=="Explorer %02d" % (i+1) and board._podium_labels[i].is_visible_in_tree(),"podium uses actual ranked names")
				check(board._podium_labels[i].size.x > 0 and board._podium_labels[i].get_visible_line_count() >= 1,"podium name has a visible text line inside its plate")
		board._receive(board._serial-1,true,{"entries":[]})
		check(board._rows.get_child_count()==expected_rows,"stale network reply cannot clear current board")
		board._receive(board._serial,false,{})
		check(board._status.visible and board._status.text.contains("unavailable"),"offline state remains visible")
		check(board._local_rank.text=="LOCAL\nBEST","network failure does not show stale global rank")
		await settle()
		check(not list.visible, "unavailable board reserves no empty standings viewport")
		check_actions(board, shape, "unavailable")
		board._receive(board._serial,true,{"entries":[]})
		await settle()
		check(board._status.visible and board._status.text.contains("No scores"), "empty success has its own truthful status")
		check(not list.visible and board._rows.get_child_count() == 0, "empty success has no standings viewport or stale rows")
		check_actions(board, shape, "empty")
		board._receive(board._serial,true,{"entries":entries,"me":{"rank":4,"value":86807}})
		await settle()
		check(list.visible and not board._status.visible and board._rows.get_child_count() == expected_rows, "recovery restores real standings and hides status")
		check_actions(board, shape, "recovered")
		var tied_entries := entries.duplicate(true)
		tied_entries[1]["rank"] = 1
		board._receive(board._serial, true, {"entries": tied_entries, "me": {"rank": 4, "value": 86807}})
		await settle()
		check(board._rows.get_child_count() == (17 if shape.y > shape.x else 19), "tied podium peer remains represented in scrolling standings")
		if shape.y > shape.x:
			check(board._podium_labels[0].text == "Explorer 01" and board._podium_labels[0].is_visible_in_tree(), "first tied leader keeps podium name without being overwritten")
			check(not board._podium_labels[1].is_visible_in_tree() and board._podium_labels[2].text == "Explorer 03", "competition ranks 1,1,3 leave unassigned second podium empty")
			check(_has_label(board._rows, "Explorer 02"), "second tied leader remains visible in rank-one list row")
		check_actions(board, shape, "tied ranks")
		viewport.free()
	LayoutProfile.forced_insets = Vector4(-1,-1,-1,-1)
	for player: AudioStreamPlayer in AudioManager._sfx_pool:
		player.stop(); player.stream=null
	for player: AudioStreamPlayer in [AudioManager._music_a,AudioManager._music_b]:
		player.stop(); player.stream=null
	await get_tree().create_timer(0.1).timeout
	print("[leaderboard-reference] DONE: %d passed, %d failed" % [passed,failed])
	get_tree().quit(1 if failed else 0)

func check(ok: bool, description: String) -> void:
	passed+=int(ok);failed+=int(not ok)
	print("[leaderboard-reference] %s %s" % ["PASS" if ok else "FAIL",description])

func settle() -> void:
	for frame: int in 5: await get_tree().process_frame

func _has_label(root: Node, text: String) -> bool:
	for child: Node in root.get_children():
		if child is Label and (child as Label).text == text:
			return true
		if _has_label(child, text):
			return true
	return false

func check_title_clearance(board: Control) -> void:
	var title := board.find_child("ApprovedTitleArtwork",true,false) as TextureRect
	var cap := board.find_child("BoardFishBalance",true,false) as Control
	var pixels := title.texture.get_image()
	check(pixels != null and not pixels.is_empty(), "actual title pixels decode for currency overlap check")
	if pixels == null or pixels.is_empty(): return
	if pixels.is_compressed(): pixels.decompress()
	var factor := minf(title.size.x / pixels.get_width(), title.size.y / pixels.get_height())
	var painted_size := Vector2(pixels.get_size()) * factor
	var painted_origin := title.global_position + (title.size - painted_size) * 0.5
	var cap_rect := cap.get_global_rect().grow(-2)
	print("[leaderboard-reference] title=%s size=%s pixels=%s cap=%s scale=%s" % [title.get_global_rect(),title.size,pixels.get_size(),cap_rect,title.get_global_transform().get_scale()])
	var overlap := 0
	for y: int in range(0,pixels.get_height(),2):
		for x: int in range(0,pixels.get_width(),2):
			if cap_rect.has_point(painted_origin + Vector2(x,y)*factor) and pixels.get_pixel(x,y).a > 0.5:
				overlap += 1
	check(overlap == 0, "currency cap clears actual opaque title artwork (%d overlapping samples)" % overlap)

func check_actions(board: Control, shape: Vector2i, state: String) -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(shape))
	for key: String in ["ChallengeFriends", "BoardRefresh", "LocalBestRow"]:
		var control := board.find_child(key, true, false) as Control
		check(control != null and control.is_visible_in_tree() and bounds.encloses(control.get_global_rect()), "%s %s visible in first view at %s" % [state, key, shape])
	var challenge := board.find_child("ChallengeFriends", true, false) as Control
	var local := board.find_child("LocalBestRow", true, false) as Control
	check(not challenge.get_global_rect().intersects(local.get_global_rect()), state + " local result and challenge do not overlap")
