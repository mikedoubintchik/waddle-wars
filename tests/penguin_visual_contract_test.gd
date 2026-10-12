extends Node
## Compatibility contract for the shared character presentation facade.

var _failures: int = 0
var _checks: int = 0


func _ready() -> void:
	var previous_qa_backend := PenguinVisual.use_authored_backend_for_qa
	_check(not previous_qa_backend, "production keeps unapproved authored backend disabled")
	# Exercise the retained authored candidate explicitly, without promoting it
	# in normal gameplay. Other fixtures cover the default procedural backend.
	PenguinVisual.use_authored_backend_for_qa = true
	var look := CharacterLook.from_legacy_config({
		"species": "gentoo",
		"display_name": "Contract Gentoo",
		"hat": "hat_beanie",
		"accent_color": Color(0.2, 0.8, 1.0),
	}, CharacterLook.RenderRole.HERO)
	_check(look.species_id == "gentoo", "legacy look keeps species")
	_check(look.to_legacy_config().get("hat", "") == "hat_beanie", "legacy look keeps cosmetic")

	var visual := PenguinVisual.new()
	add_child(visual)
	visual.position = Vector3(3.0, 2.0, -8.0)
	var gameplay_position := visual.position
	visual.setup_look(look)
	_check(visual.position.is_equal_approx(gameplay_position), "setup_look preserves gameplay transform")
	for socket_id: StringName in [&"head_socket", &"face_socket", &"neck_socket", &"trail_socket"]:
		_check(visual.get_socket(socket_id) != null, "%s exists" % socket_id)
	var authored := visual.find_child("AuthoredHeroPenguin", false, false) as Node3D
	_check(authored != null, "hero look enables authored backend")
	var animation_player: AnimationPlayer = null
	if authored != null:
		var players := authored.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			animation_player = players[0] as AnimationPlayer
	_check(animation_player != null, "authored backend exposes animation player")

	visual.set_pose(PenguinVisual.Pose.RUN)
	_check(_current_clip(animation_player) == &"run", "RUN forwards to authored backend")
	visual.set_pose(PenguinVisual.Pose.SLIDE)
	_check(_current_clip(animation_player) == &"slide_loop", "SLIDE forwards to authored backend")
	visual.set_pose(PenguinVisual.Pose.AIR)
	_check(_current_clip(animation_player) == &"jump_air", "AIR forwards to authored backend")
	visual.set_pose(PenguinVisual.Pose.RUN)
	visual.trigger_event(&"hit", {"side": -1.0})
	_check(_current_clip(animation_player) == &"hit_left", "semantic one-shot reaches authored backend")
	for _frame: int in 40:
		visual.tick(0.05, 1.0)
	_check(_current_clip(animation_player) == &"run", "facade tick returns one-shot to run state")
	visual.drive_motion(1.0, 0.7, 0.1, 5.0, false)
	_check(visual.position.is_equal_approx(gameplay_position), "drive_motion never applies root motion")
	_check(visual.pose == PenguinVisual.Pose.AIR, "airborne motion selects air pose")
	visual.drive_motion(1.0, 0.0, 0.0, 0.0, true)
	_check(visual.pose == PenguinVisual.Pose.RUN, "grounded motion recovers run pose")
	visual.trigger_event(&"slid", {"strength": 1.0})
	_check(visual.pose == PenguinVisual.Pose.SLIDE, "slide event selects slide pose")
	visual.trigger_event(&"died", {"side": -1.0})
	_check(visual.pose == PenguinVisual.Pose.DEFEAT, "death event selects defeat pose")

	visual.set_render_role(PenguinVisual.RenderRole.GHOST)
	var geometry_count := 0
	var visible_geometry_count := 0
	for child: Node in visual.find_children("*", "GeometryInstance3D", true, false):
		var geometry := child as GeometryInstance3D
		geometry_count += 1
		_check(geometry.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"ghost geometry disables shadow")
		if geometry.is_visible_in_tree():
			visible_geometry_count += 1
			_check(is_equal_approx(geometry.transparency, 0.42),
					"visible ghost backend uses instance fade")
	_check(geometry_count > 0, "character builds render geometry")
	_check(visible_geometry_count > 0, "ghost keeps one visible render backend")

	visual.set_render_role(PenguinVisual.RenderRole.HERO)
	var hero_shadow_count := 0
	var apparel_shadow_exemptions := 0
	for child: Node in visual.find_children("*", "GeometryInstance3D", true, false):
		var geometry := child as GeometryInstance3D
		var tagged_apparel := bool(geometry.get_meta("apparel_no_shadow", false))
		# The retained authored candidate applies one shadow policy to its whole
		# rig. Production procedural apparel is checked independently below.
		var no_apparel_shadow := tagged_apparel and not authored.is_ancestor_of(geometry)
		if tagged_apparel:
			apparel_shadow_exemptions += 1
		if no_apparel_shadow:
			_check(geometry.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"small apparel geometry preserves explicit no-shadow contract")
		else:
			hero_shadow_count += 1
			_check(geometry.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
				"hero geometry restores shadow")
		if geometry.is_visible_in_tree():
			_check(is_zero_approx(geometry.transparency),
					"visible hero backend restores opacity")
	_check(hero_shadow_count > 0, "hero body still owns shadow-casting geometry")
	_check(apparel_shadow_exemptions > 0, "beanie carries explicit apparel shadow metadata")

	PenguinVisual.use_authored_backend_for_qa = previous_qa_backend
	var production_visual := PenguinVisual.new()
	add_child(production_visual)
	production_visual.setup_look(look)
	_check(not production_visual.is_authored_backend_active(),
		"production role checks retain procedural backend")
	for role: PenguinVisual.RenderRole in [PenguinVisual.RenderRole.GHOST, PenguinVisual.RenderRole.HERO]:
		production_visual.set_render_role(role)
		for child: Node in production_visual.find_children("*", "GeometryInstance3D", true, false):
			var geometry := child as GeometryInstance3D
			var expected_shadow := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
				if role == PenguinVisual.RenderRole.GHOST or geometry.get_meta("apparel_no_shadow", false) \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			_check(geometry.cast_shadow == expected_shadow,
				"production role preserves body shadow and exact apparel exemption")

	if _failures == 0:
		print("PENGUIN VISUAL CONTRACT: PASS (%d checks)" % _checks)
	else:
		push_error("PENGUIN VISUAL CONTRACT: %d failure(s)" % _failures)
	PenguinVisual.use_authored_backend_for_qa = previous_qa_backend
	get_tree().quit(_failures)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("FAIL: %s" % label)


func _current_clip(player: AnimationPlayer) -> StringName:
	return StringName(player.current_animation) if player != null else StringName()
