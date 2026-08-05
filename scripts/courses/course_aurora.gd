class_name CourseAurora
extends CourseBase
## AURORA ASCENT: twilight mountain under the southern lights. Switchback
## climb, windy ridge traverse, icicle cavern, a narrow no-wall ridge
## shortcut, an ice geyser field, and a huge 270-degree corkscrew descent
## to a research-station finish. Deep star-strewn twilight sky, animated
## aurora curtains (shared VisualLibrary shader), dark-blue ambient snow,
## glowing crystals along the route, warm research lamps (sparse real
## lights), blowing-snow wisps across the windy ridge.

const SNOW := SurfacesDB.Surface.PACKED_SNOW
const ICE := SurfacesDB.Surface.ICE_SMOOTH
const RICE := SurfacesDB.Surface.ICE_ROUGH

## Hard cap on real OmniLight3Ds (mobile renderer: keep the cluster light
## count tiny). Everything else glows via emissive materials only.
const MAX_OMNI_LIGHTS: int = 5

var _aurora_ribbons: Array[Node3D] = []
var _aurora_time: float = 0.0
var _omni_lights: int = 0
var _crystal_mats: Dictionary = {}

## Cumulative true arc length per guide sample index. Godot 4.7 bakes curve
## samples ~1.0-2.0m apart (tessellation), not the uniform 2.0m PathGuide
## assumes, so index-derived offsets (racer progress, hints) and arc-length
## offsets (point_at/transform_at placement) are different coordinate spaces.
## These tables convert between them exactly.
var _main_cum: PackedFloat32Array = PackedFloat32Array()
var _short_cum: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	course_id = "aurora"


static func p(x: float, y: float, z: float, extra: Dictionary = {}) -> Dictionary:
	var d := {"pos": Vector3(x, y, z)}
	d.merge(extra)
	return d


func build_course() -> void:
	var pts: Array = [
		# 1) Start ridge plateau.
		p(0, 40, 35, {"width": 18.0}),
		p(0, 40, -25, {"width": 18.0}),
		p(0, 40, -62, {"width": 18.0}),
		# 2) Zigzag switchback climb (+27m over ~560m, three gentle hairpins).
		p(16, 41, -94, {"width": 16.0}),
		p(48, 43, -108, {"width": 16.0}),
		p(84, 45, -114, {"width": 16.0}),
		p(112, 46.2, -122, {"width": 16.0}),
		p(127, 47.6, -146, {"width": 16.0}),  # hairpin 1 apex
		p(112, 49, -170, {"width": 16.0}),
		p(64, 51.4, -180, {"width": 16.0}),
		p(12, 54, -188, {"width": 16.0}),
		p(-38, 56.4, -196, {"width": 16.0}),
		p(-70, 57.8, -206, {"width": 16.0}),
		p(-87, 59.2, -230, {"width": 16.0}),  # hairpin 2 apex
		p(-70, 60.6, -254, {"width": 16.0}),
		p(-28, 62.6, -264, {"width": 16.0}),
		p(14, 64.6, -272, {"width": 16.0}),
		p(42, 65.6, -282, {"width": 16.0}),   # hairpin 3 (turn back to -Z)
		p(58, 66.4, -306, {"width": 15.0}),
		# 3) Windy ridge traverse: narrow, low walls ON, crosswinds.
		p(60, 67, -340, {"width": 12.0}),
		p(55, 67, -386, {"width": 12.0}),
		p(61, 66.6, -430, {"width": 12.0}),
		p(56, 66.2, -466, {"width": 12.0}),
		# 4) Icicle cavern: rough ice, gentle downhill.
		p(48, 64.6, -502, {"width": 13.0, "surface": RICE}),
		p(42, 62.6, -540, {"width": 13.0, "surface": RICE}),
		p(50, 60.6, -578, {"width": 13.0, "surface": RICE}),
		p(46, 58.6, -616, {"width": 13.0, "surface": RICE, "wall_r": false}),
		# 5) Safe switchback descent (shortcut branch cuts this loop).
		p(28, 56.8, -648, {"width": 16.0, "wall_r": false}),
		p(-6, 54.4, -670, {"width": 16.0, "wall_r": false}),
		p(-38, 51.8, -690, {"width": 16.0}),
		p(-58, 49.8, -708, {"width": 15.0}),
		p(-70, 48.2, -728, {"width": 15.0}),
		p(-74, 46.6, -752, {"width": 15.0}),  # descent hairpin apex
		p(-62, 45.0, -774, {"width": 15.0}),
		p(-34, 43.0, -792, {"width": 15.0}),
		p(4, 40.8, -808, {"width": 16.0}),
		p(30, 39.0, -822, {"width": 16.0}),
		p(44, 37.8, -840, {"width": 16.0, "wall_r": false}),
		p(50, 36.8, -864, {"width": 18.0, "wall_r": false}),
		p(46, 36.0, -888, {"width": 20.0, "wall_r": false}),
		# 6) Ice geyser field: wide, gentle downhill, playful launches.
		p(40, 33.4, -938, {"width": 20.0}),
		p(34, 31.0, -986, {"width": 20.0}),
		p(34, 29.2, -1014, {"width": 20.0}),
		# 7) Corkscrew finale: 270-degree descending spiral, r=45, drops ~34m.
		p(35, 28.1, -1030, {"width": 18.0, "surface": ICE}),
		p(48.2, 22.4, -1061.8, {"width": 17.0, "surface": ICE}),
		p(80, 16.7, -1075, {"width": 17.0, "surface": ICE}),
		p(111.8, 11.0, -1061.8, {"width": 17.0, "surface": ICE}),
		p(125, 5.3, -1030, {"width": 17.0, "surface": ICE}),
		p(111.8, -0.4, -998.2, {"width": 17.0, "surface": ICE}),
		p(80, -6.1, -985, {"width": 18.0, "surface": ICE}),
		# 8) Finish straight (passes ~37m under the geyser field).
		p(46, -7.1, -990, {"width": 18.0}),
		p(8, -7.7, -994, {"width": 18.0}),
		p(-34, -8, -997, {"width": 18.0}),
		p(-72, -8, -999, {"width": 18.0}),
	]
	setup_main(pts)

	# 5) Narrow ridge shortcut: width 7, NO walls, skips the switchback
	# descent along an exposed spine right of the safe route (~110m saved).
	var branch_pts: Array = [
		p(38, 57.4, -630, {"width": 9.0, "surface": RICE, "wall_l": false, "wall_r": false}),
		p(46, 55.2, -664, {"width": 7.0, "surface": RICE, "wall_l": false, "wall_r": false}),
		p(52, 52.6, -700, {"width": 7.0, "surface": RICE, "wall_l": false, "wall_r": false}),
		p(56, 49.8, -736, {"width": 7.0, "surface": RICE, "wall_l": false, "wall_r": false}),
		p(52, 46.8, -772, {"width": 7.0, "surface": RICE, "wall_l": false, "wall_r": false}),
		p(56, 43.6, -806, {"width": 7.0, "surface": RICE, "wall_l": false, "wall_r": false}),
		p(58, 40.4, -838, {"width": 8.0, "surface": RICE, "wall_l": false, "wall_r": false}),
		p(56, 37.6, -858, {"width": 9.0, "surface": RICE, "wall_l": false, "wall_r": false}),
		p(48, 36.4, -880, {"width": 9.0, "surface": RICE, "wall_l": false, "wall_r": false}),
	]
	var shortcut := add_branch(branch_pts, 0.7, "ridge_shortcut")

	finalize()
	_main_cum = _cum_lengths(main_guide)
	_short_cum = _cum_lengths(shortcut)
	# Convert the branch's entry/exit (index-space from add_branch) to true
	# arc offsets: the get_guide override below works entirely in arc space.
	var branch_info: Dictionary = branches[0]
	branch_info["entry"] = _main_cum[clampi(int(float(branch_info["entry"]) / PathGuide.SAMPLE_SPACING), 0, _main_cum.size() - 1)]
	branch_info["exit"] = _main_cum[clampi(int(float(branch_info["exit"]) / PathGuide.SAMPLE_SPACING), 0, _main_cum.size() - 1)]

	# --- Geometry-derived offsets (true arc space) --------------------------
	var ridge_arc := _arc_near(Vector3(60, 67, -340))
	var ridge_mid_arc := _arc_near(Vector3(55, 67, -386))
	var ridge_late_arc := _arc_near(Vector3(61, 66.6, -430))
	var ridge_end_arc := _arc_near(Vector3(56, 66.2, -466))
	var cavern_arc := _arc_near(Vector3(48, 64.6, -502))
	var cavern_end_arc := _arc_near(Vector3(46, 58.6, -616))
	var merge_arc := _arc_near(Vector3(46, 36.0, -888))
	var geyser_arc := _arc_near(Vector3(40, 33.4, -938))
	var spiral_arc := _arc_near(Vector3(35, 28.1, -1030))
	var spiral_mid_arc := _arc_near(Vector3(80, 16.7, -1075))
	var spiral_late_arc := _arc_near(Vector3(125, 5.3, -1030))
	var spiral_end_arc := _arc_near(Vector3(80, -6.1, -985))

	# --- Windy ridge: three alternating crosswind zones --------------------
	# Wind moves racers positionally (it bypasses velocity), so each zone is
	# flanked by thick ice berms: the wind rattles you, the berms keep the
	# ridge survivable, and the danger hints make the AI pre-compensate.
	var wind_specs: Array = [
		{"arc": ridge_arc + 18.0, "dir": 1.0, "strength": 4.0},
		{"arc": (ridge_mid_arc + ridge_late_arc) * 0.5, "dir": -1.0, "strength": 4.0},
		{"arc": ridge_end_arc - 34.0, "dir": 1.0, "strength": 4.0},
	]
	for spec: Dictionary in wind_specs:
		var arc := float(spec["arc"])
		var xform := main_guide.transform_at(arc)
		var wind := HazardWindZone.new()
		wind.configure(xform.basis.x * float(spec["dir"]), float(spec["strength"]), Vector3(14.0, 8.0, 34.0))
		wind.transform = Transform3D(xform.basis, xform.origin + xform.basis.y * 3.0)
		add_child(wind)
		_add_wind_wisps(xform, float(spec["dir"]))
		# Danger side = side the wind pushes you toward; AI biases away.
		var kind := "danger_right" if float(spec["dir"]) > 0.0 else "danger_left"
		add_hint(arc - 35.0, kind, arc + 26.0)
	# One continuous berm channel walls the whole traverse, and a lateral
	# clamp (see _physics_process) makes the ridge fall-proof under wind.
	_add_ridge_berms(ridge_arc - 20.0, cavern_arc + 6.0)
	_ridge_clamp_start = ridge_arc - 16.0
	_ridge_clamp_end = cavern_arc + 2.0

	# --- Icicle cavern: 9 icicles, weaving safe line -----------------------
	var icicle_laterals: Array = [-4.0, 3.0, -2.0, 4.0, -3.0, 2.0, -4.0, 3.0, -2.0]
	for i: int in icicle_laterals.size():
		var offset := cavern_arc + 8.0 + float(i) * 12.0
		if offset > cavern_end_arc - 4.0:
			break
		var icicle := HazardIcicle.new()
		icicle.position = main_guide.point_at(offset, float(icicle_laterals[i]), 5.5)
		add_child(icicle)
	# First half hangs left-heavy, second half right-heavy: weave the bots.
	var cavern_mid_arc := (cavern_arc + cavern_end_arc) * 0.5
	add_hint(cavern_arc - 25.0, "danger_left", cavern_mid_arc)
	add_hint(cavern_mid_arc, "danger_right", cavern_end_arc)

	# --- Geyser field: 6 staggered geysers on the wide downhill ------------
	# Kept well upstream of the corkscrew so launches land on the wide
	# downhill, never past the spiral's entry curve.
	var geyser_laterals: Array = [-5.0, 4.0, -1.0, 5.0, -4.0, 1.0]
	var geyser_phases: Array = [0.0, 0.9, 1.7, 2.3, 0.5, 1.3]
	for i: int in 6:
		var offset := merge_arc + 12.0 + float(i) * 17.0
		var geyser := HazardGeyser.new()
		geyser.phase_offset = float(geyser_phases[i])
		geyser.position = main_guide.point_at(offset, float(geyser_laterals[i]), 0.0)
		add_child(geyser)

	# --- Slide hints + boost pads for the descent finale -------------------
	add_hint(geyser_arc - 25.0, "slide", spiral_end_arc)
	add_hint(spiral_arc + 5.0, "slide", spiral_end_arc)   # re-acquire after respawn
	add_hint(spiral_mid_arc, "slide", spiral_end_arc)
	add_hint(spiral_late_arc, "slide", spiral_end_arc)
	TrackBuilder.add_boost_pad(self, main_guide, spiral_arc + 45.0, -2.5)
	TrackBuilder.add_boost_pad(self, main_guide, spiral_arc + 125.0, 2.5)

	# Shortcut: slide its steep tail. Branch hint offsets are main-line
	# equivalents: lerp(entry, exit) by branch arc fraction (see get_guide).
	var b_entry := float(branch_info["entry"])
	var b_exit := float(branch_info["exit"])
	add_hint(b_entry + (150.0 / shortcut.length) * (b_exit - b_entry), "slide", b_exit + 30.0, 0)

	# --- Pickups (arc offsets: placement space) ----------------------------
	add_item_row(120.0)
	add_item_row(ridge_arc + 10.0)
	add_item_row(_arc_near(Vector3(-6, 54.4, -670)))
	add_item_row(merge_arc + 6.0)
	add_item_row(_arc_near(Vector3(34, 29.2, -1014)))

	add_fish_line(55.0, 8, 5.0, 0.0)
	add_fish_line(_arc_near(Vector3(48, 43, -108)), 8, 5.0, -3.0)
	add_fish_line(_arc_near(Vector3(12, 54, -188)) - 15.0, 10, 5.0, 0.0)
	add_fish_line(_arc_near(Vector3(-28, 62.6, -264)), 8, 5.0, 3.0)
	add_fish_line(ridge_mid_arc, 8, 5.5, 0.0)
	add_fish_line(_arc_near(Vector3(42, 62.6, -540)), 10, 4.5, 0.0)
	add_fish_line(_arc_near(Vector3(-62, 45.0, -774)), 10, 5.0, -4.0)
	add_fish_line(30.0, 10, 6.0, 0.0, 0.0, shortcut)  # reward the ridge
	add_fish_line(_arc_near(Vector3(40, 33.4, -938)), 10, 5.0, 5.0)
	add_fish_line(spiral_arc + 35.0, 12, 6.0, 0.0)
	add_fish_line(_arc_near(Vector3(80, -6.1, -985)) + 12.0, 8, 5.0, 0.0)

	_decorate()
	_build_aurora()
	_build_stars()
	# Deep twilight: near-black zenith falling to a violet horizon band, a
	# small cold moon disc, dark-blue ambient tinting every snow surface, thin
	# distance haze (dense fog would eat the aurora/stars) plus ground mist
	# pooling in the finish bowl below y=2.
	build_environment({
		"sky_top": Color(0.03, 0.05, 0.14),
		"sky_horizon": Color(0.4, 0.24, 0.5),
		"ground_color": Color(0.05, 0.07, 0.16),
		"sun_angle_deg": -18.0,
		"sun_energy": 0.55,
		"sun_color": Color(0.66, 0.76, 1.0),
		"sun_angle_max": 2.5,
		"sun_curve": 0.05,
		"sky_energy": 0.9,
		"exposure": 1.12,
		"fog_color": Color(0.09, 0.12, 0.26),
		"fog_density": 0.0015,
		"fog_height": 2.0,
		"fog_height_density": 0.05,
		"glow_threshold": 1.05,
		"shadow_distance": 120.0,
		"ambient_energy": 1.35,
		"snow": true,
		"distant_bergs": true,
		"berg_color": Color(0.34, 0.42, 0.66),
		"berg_count": 12,
		"berg_distance": 800.0,
		"berg_y": -31.0,
	})
	add_ground_plane(-32.0, Color(0.09, 0.12, 0.2), 4000.0,
		VisualLibrary.snow_material(Color(0.52, 0.58, 0.85), 0.85))


## True arc-length offset, the space point_at/transform_at expect.
func _arc_near(point: Vector3) -> float:
	var idx := int(main_guide.nearest(point, -1)["index"])
	return _main_cum[clampi(idx, 0, _main_cum.size() - 1)]


static func _cum_lengths(guide: PathGuide) -> PackedFloat32Array:
	var cum := PackedFloat32Array()
	cum.resize(guide.points.size())
	var total := 0.0
	for i: int in range(1, guide.points.size()):
		total += guide.points[i - 1].distance_to(guide.points[i])
		cum[i] = total
	return cum


## Override: the base implementation converts sample indices to offsets with
## a uniform 2.0m spacing, but Godot 4.7 bakes samples 1.0-2.0m apart, so its
## targets overshoot by ~50% and clamp to the course end — fatal on hairpins
## and the corkscrew. Walk the real baked samples instead.
func ai_target(racer: Racer, lookahead: float, lateral: float = 0.0) -> Vector3:
	var cache: Dictionary = racer.guide_cache
	var path := int(cache.get("path", -1))
	if path >= 0 and path < branches.size():
		var branch: Dictionary = branches[path]
		var guide: PathGuide = branch["guide"]
		var idx := int(cache.get("branch_idx_%d" % path, 0))
		var target_idx := _walk_index(guide, idx, lookahead)
		if target_idx < guide.points.size() - 2:
			return _sample_point(guide, target_idx, lateral)
		# Near branch end: aim back onto the main line beyond the merge.
		return main_guide.point_at(float(branch["exit"]) + 12.0, lateral)
	var main_idx := int(cache.get("main_idx", 0))
	return _sample_point(main_guide, _walk_index(main_guide, main_idx, lookahead), lateral)


## Override: the base version feeds index-space offsets into yaw_at() (an
## arc-length API) and reports index-space progress. Because a racer's facing
## is anchored to the guide yaw +/- max steer, the inflated yaw points at
## geometry far ahead and racers cannot hold tight curves at all. This
## version computes yaw from the local baked tangent and reports true
## arc-length progress (hints, hazards, and branch entry/exit on this course
## are all stored in arc space to match).
func get_guide(racer: Racer) -> Dictionary:
	if main_guide == null:
		return {"yaw": 0.0, "progress": 0.0}
	var cache: Dictionary = racer.guide_cache
	var current_path := int(cache.get("path", -1))
	var pos := racer.global_position

	var main_hint := int(cache.get("main_idx", -1))
	var main_res := main_guide.nearest(pos, main_hint)
	var main_idx := int(main_res["index"])
	var main_arc := _main_cum[clampi(main_idx, 0, _main_cum.size() - 1)]
	var best_path := -1
	var best_res := main_res
	var best_dist := float(main_res["distance"])
	if current_path == -1:
		best_dist -= 2.0  # hysteresis: stick with current path

	for branch: Dictionary in branches:
		var entry := float(branch["entry"])
		var exit_offset := float(branch["exit"])
		if main_arc < entry - 40.0 or main_arc > exit_offset + 40.0:
			continue
		var branch_id := int(branch["id"])
		var guide: PathGuide = branch["guide"]
		var hint := int(cache.get("branch_idx_%d" % branch_id, -1))
		var res := guide.nearest(pos, hint)
		cache["branch_idx_%d" % branch_id] = int(res["index"])
		var dist := float(res["distance"])
		if current_path == branch_id:
			dist -= 2.0
		if dist < best_dist:
			best_dist = dist
			best_path = branch_id
			best_res = res

	cache["main_idx"] = main_idx
	cache["path"] = best_path
	racer.guide_cache = cache

	var result: Dictionary
	if best_path == -1:
		result = {"yaw": _yaw_at_index(main_guide, main_idx), "progress": main_arc}
	else:
		var branch: Dictionary = branches[best_path]
		var guide: PathGuide = branch["guide"]
		var branch_idx := int(best_res["index"])
		var branch_arc := _short_cum[clampi(branch_idx, 0, _short_cum.size() - 1)]
		var frac := branch_arc / maxf(guide.length, 0.001)
		var mapped := lerpf(float(branch["entry"]), float(branch["exit"]), frac)
		result = {"yaw": _yaw_at_index(guide, branch_idx), "progress": mapped}
	_advance_checkpoints(racer, float(result["progress"]))
	return result


static func _yaw_at_index(guide: PathGuide, idx: int) -> float:
	var pts := guide.points
	var tangent := pts[mini(idx + 2, pts.size() - 1)] - pts[maxi(idx - 2, 0)]
	if tangent.length_squared() < 0.0001:
		return 0.0
	return atan2(-tangent.x, -tangent.z)


static func _walk_index(guide: PathGuide, start_idx: int, lookahead: float) -> int:
	var pts := guide.points
	var i := clampi(start_idx, 0, pts.size() - 1)
	var remaining := lookahead
	while i < pts.size() - 1 and remaining > 0.0:
		remaining -= pts[i].distance_to(pts[i + 1])
		i += 1
	return i


static func _sample_point(guide: PathGuide, idx: int, lateral: float) -> Vector3:
	var pts := guide.points
	var tangent := pts[mini(idx + 1, pts.size() - 1)] - pts[maxi(idx - 1, 0)]
	if tangent.length_squared() < 0.0001:
		tangent = Vector3.FORWARD
	var right := tangent.normalized().cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	return pts[idx] + right.normalized() * lateral


## --- Decorations ------------------------------------------------------------

func _decorate() -> void:
	if GameConfig.is_headless():
		return

	# Course-side flags in aurora colors, alternating sides.
	var offset := 60.0
	var side := 1.0
	while offset < main_guide.length - 60.0:
		var xform := main_guide.transform_at(offset)
		var lateral := (10.5 + rng.randf_range(0.0, 3.0)) * side
		TrackBuilder.add_flag(self, xform.origin + xform.basis.x * lateral,
			Color(0.3, 0.95, 0.6) if side > 0 else Color(0.7, 0.45, 1.0))
		side = -side
		offset += 120.0

	# Warm research-station lamps dotted along the whole route. Emissive
	# meshes only — the sparse real OmniLight3Ds go to key landmarks below.
	var light_offset := 90.0
	var light_side := -1.0
	while light_offset < main_guide.length - 40.0:
		var xform := main_guide.transform_at(light_offset)
		_add_station_light(xform.origin + xform.basis.x * ((10.5 + rng.randf_range(0.0, 2.0)) * light_side))
		light_side = -light_side
		light_offset += 155.0
	# Start plateau: one lamp casting a real warm pool over the grid.
	var start_xform := main_guide.transform_at(14.0)
	_add_station_light(start_xform.origin + start_xform.basis.x * 10.0, true)
	# Dense pole rows framing the finish straight; the nearest row casts
	# real light so the finish reads warm against the twilight.
	for i: int in 3:
		var xform := main_guide.transform_at(finish_offset - 15.0 - float(i) * 25.0)
		for s: float in [-1.0, 1.0]:
			_add_station_light(xform.origin + xform.basis.x * (10.5 * s), i == 0)

	# Two research huts with glowing windows (each brings one real lamp).
	var hut_a := main_guide.transform_at(_arc_near(Vector3(60, 67, -340)))
	_add_research_hut(hut_a.origin + hut_a.basis.x * 14.0, hut_a.origin)
	var hut_b := main_guide.transform_at(_arc_near(Vector3(40, 33.4, -938)))
	_add_research_hut(hut_b.origin + hut_b.basis.x * -15.0, hut_b.origin)

	# Windy ridge: softly glowing crystal fins flanking the traverse in
	# alternating aurora green / violet.
	var ridge_start := _arc_near(Vector3(60, 67, -340))
	var ridge_end := _arc_near(Vector3(56, 66.2, -466))
	var crystal_offset := ridge_start
	var tint_flip := false
	while crystal_offset < ridge_end:
		var xform := main_guide.transform_at(crystal_offset)
		for s: float in [-1.0, 1.0]:
			var tint := Color(0.45, 1.0, 0.7) if tint_flip else Color(0.75, 0.55, 1.0)
			_add_glow_crystal(xform.origin + xform.basis.x * (8.5 * s) + Vector3.DOWN * 0.8,
				rng.randf_range(2.0, 4.5), tint)
			tint_flip = not tint_flip
		crystal_offset += 26.0

	# Icicle cavern: crystalline ice arches + glow shards lining the walls.
	var cavern_start := _arc_near(Vector3(48, 64.6, -502))
	var cavern_end := _arc_near(Vector3(46, 58.6, -616))
	var arch_mat := VisualLibrary.ice_material(Color(0.48, 0.62, 0.95), 0.5)
	var cave_offset := cavern_start
	while cave_offset < cavern_end:
		var xform := main_guide.transform_at(cave_offset)
		var arch := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 7.5
		torus.outer_radius = 10.0
		arch.mesh = torus
		arch.material_override = arch_mat
		arch.transform = Transform3D(xform.basis.rotated(xform.basis.x, deg_to_rad(90)), xform.origin + Vector3.UP * 1.0)
		add_child(arch)
		for s: float in [-1.0, 1.0]:
			_add_glow_crystal(xform.origin + xform.basis.x * (8.0 * s) + Vector3.DOWN * 0.6,
				rng.randf_range(2.2, 4.8), Color(0.55, 0.8, 1.0))
		cave_offset += 20.0

	# Spectator penguins near start and finish.
	for i: int in 10:
		var near_start := main_guide.transform_at(rng.randf_range(10.0, 85.0))
		var lateral := (11.5 + rng.randf_range(0.0, 4.0)) * (1.0 if i % 2 == 0 else -1.0)
		TrackBuilder.add_spectator(self, near_start.origin + near_start.basis.x * lateral, near_start.origin, rng)
	for i: int in 8:
		var near_finish := main_guide.transform_at(finish_offset - rng.randf_range(5.0, 70.0))
		var lateral := (11.5 + rng.randf_range(0.0, 4.0)) * (1.0 if i % 2 == 0 else -1.0)
		TrackBuilder.add_spectator(self, near_finish.origin + near_finish.basis.x * lateral, near_finish.origin, rng)

	# Distant twilight peaks: jagged low-poly berg silhouettes ringing the
	# course. Baked vertex colors give dark faceted walls + paler snow caps.
	var peak_mat := VisualLibrary.rock_material(Color(0.3, 0.36, 0.6))
	for i: int in 16:
		var angle := TAU * float(i) / 16.0 + rng.randf_range(-0.15, 0.15)
		var dist := rng.randf_range(380.0, 620.0)
		var peak := MeshInstance3D.new()
		peak.mesh = VisualLibrary.berg_mesh(rng.randi())
		peak.material_override = peak_mat
		var width := rng.randf_range(90.0, 170.0)
		peak.scale = Vector3(width * rng.randf_range(0.9, 1.4), rng.randf_range(70.0, 130.0), width)
		peak.position = Vector3(20.0 + sin(angle) * dist, -30.0, -520.0 + cos(angle) * dist)
		peak.rotation.y = rng.randf() * TAU
		peak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(peak)

	# Snowdrift mounds fill the course flanks so the slopes never read empty.
	var drift_mesh := VisualLibrary.snow_drift_mesh()
	var drift_mat := VisualLibrary.rock_material(Color(0.62, 0.68, 0.92))
	for i: int in 30:
		var drift_offset := rng.randf_range(30.0, main_guide.length - 50.0)
		var drift_xform := main_guide.transform_at(drift_offset)
		var drift_lateral := rng.randf_range(12.0, 28.0) * (1.0 if rng.randf() > 0.5 else -1.0)
		var drift := MeshInstance3D.new()
		drift.mesh = drift_mesh
		drift.material_override = drift_mat
		var drift_scale := rng.randf_range(1.6, 4.2)
		drift.scale = Vector3(drift_scale * rng.randf_range(0.9, 1.5), drift_scale * rng.randf_range(0.5, 0.9), drift_scale)
		drift.position = drift_xform.origin + drift_xform.basis.x * drift_lateral + Vector3.DOWN * 0.8
		drift.rotation.y = rng.randf() * TAU
		drift.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(drift)

	# Rocks and glow crystals scattered along the route.
	for i: int in 26:
		var offset2 := rng.randf_range(40.0, main_guide.length - 60.0)
		var xform2 := main_guide.transform_at(offset2)
		var lateral2 := rng.randf_range(13.0, 26.0) * (1.0 if rng.randf() > 0.5 else -1.0)
		if rng.randf() > 0.55:
			TrackBuilder.add_rock(self, xform2.origin + xform2.basis.x * lateral2 + Vector3.DOWN * 1.0, rng.randf_range(0.7, 1.8), rng)
		else:
			_add_glow_crystal(xform2.origin + xform2.basis.x * lateral2 + Vector3.DOWN * 1.0,
				rng.randf_range(2.0, 5.5), Color(0.55, 0.8, 1.0) if rng.randf() > 0.5 else Color(0.7, 0.5, 1.0))

	# Landmark crystal monoliths: one on the outside of each hairpin apex
	# (all three apexes bulge away from x=0 and run -Z, so the outward side
	# is sign(apex.x) along basis.x) + a beacon rising through the middle of
	# the corkscrew finale.
	for apex: Vector3 in [Vector3(127, 47.6, -146), Vector3(-87, 59.2, -230), Vector3(-74, 46.6, -752)]:
		var apex_xform := main_guide.transform_at(_arc_near(apex))
		var out_side := 1.0 if apex.x > 0.0 else -1.0
		_add_glow_crystal(apex_xform.origin + apex_xform.basis.x * (13.0 * out_side) + Vector3.DOWN * 2.0,
			rng.randf_range(7.0, 10.0), Color(0.45, 1.0, 0.7))
	_add_glow_crystal(Vector3(80.0, -18.0, -1030.0), 24.0, Color(0.5, 1.0, 0.75))


## Thick wind-carved ice berms lining both edges of the whole ridge
## traverse as one continuous extruded strip per side. The positional push
## of HazardWindZone tunnels through the thin default track walls, and any
## segment joints or outward tapers create wedge pockets or exit ramps —
## so this is a single smooth channel: a collector funnel at the entry, a
## low inward taper at the cavern end, thick everywhere.
func _add_ridge_berms(start_arc: float, end_arc: float) -> void:
	var berm_mat := StandardMaterial3D.new()
	berm_mat.albedo_color = Color(0.3, 0.42, 0.62)
	berm_mat.roughness = 0.25
	berm_mat.rim_enabled = true
	berm_mat.rim = 0.4
	berm_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var step := 3.0
	var length := end_arc - start_arc
	var count := int(length / step)
	# Station profile: lateral of berm center-of-mass and protrusion height.
	# Entry funnel collects racers inward; exit taper sinks the berm while
	# staying over the cavern floor (half-width 6.5).
	var lats: Array[float] = []
	var heights: Array[float] = []
	for i: int in count + 1:
		var t := float(i) * step
		var lat := 6.6
		var h := 2.0
		if t < 12.0:
			lat = lerpf(8.4, 6.6, t / 12.0)
		var t_end := length - t
		if t_end < 9.0:
			lat = lerpf(7.1, 6.6, t_end / 9.0)
			h = lerpf(0.4, 2.0, t_end / 9.0)
		lats.append(lat)
		heights.append(h)

	for s: float in [-1.0, 1.0]:
		# Solid collision: heavily overlapping oriented boxes (trimesh strips
		# tunnel under HazardWindZone's positional push; solid boxes do not).
		for i: int in count:
			var a := main_guide.point_at(start_arc + float(i) * step, lats[i] * s, 0.0)
			var b := main_guide.point_at(start_arc + float(i + 1) * step, lats[i + 1] * s, 0.0)
			var h := (heights[i] + heights[i + 1]) * 0.5
			var dir := b - a
			var body := StaticBody3D.new()
			body.collision_layer = GameConfig.LAYER_WORLD
			body.collision_mask = 0
			body.set_meta("surface", SurfacesDB.Surface.ICE_ROUGH)
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(1.6, h + 0.6, dir.length() + 1.6)
			shape.shape = box
			body.add_child(shape)
			var mid := (a + b) * 0.5 + Vector3.UP * (h * 0.5 - 0.3)
			body.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), mid)
			add_child(body)

		# Visual: one continuous strip matching the collision profile.
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var prev_in_b := Vector3.ZERO
		var prev_in_t := Vector3.ZERO
		var prev_out_t := Vector3.ZERO
		for i: int in count + 1:
			var arc := start_arc + float(i) * step
			var xform := main_guide.transform_at(arc)
			var right := xform.basis.x * s
			var up := xform.basis.y
			var in_b := xform.origin + right * (lats[i] - 0.85) - up * 0.6
			var in_t := xform.origin + right * (lats[i] - 0.7) + up * heights[i]
			var out_t := xform.origin + right * (lats[i] + 0.85) + up * (heights[i] * 0.55)
			if i > 0:
				_berm_quad(st, prev_in_b, prev_in_t, in_t, in_b)
				_berm_quad(st, prev_in_t, prev_out_t, out_t, in_t)
			prev_in_b = in_b
			prev_in_t = in_t
			prev_out_t = out_t
		st.generate_normals()
		var visual := MeshInstance3D.new()
		visual.mesh = st.commit()
		visual.material_override = berm_mat
		add_child(visual)


static func _berm_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
	st.add_vertex(a); st.add_vertex(d); st.add_vertex(c)


## Warm station lamp: post + emissive globe (blooms past the glow threshold).
## with_light additionally drops one of the few real OmniLight3Ds — capped at
## MAX_OMNI_LIGHTS and skipped on low particle quality (mobile budget).
func _add_station_light(pos: Vector3, with_light: bool = false) -> void:
	var post := MeshInstance3D.new()
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.09
	post_mesh.bottom_radius = 0.13
	post_mesh.height = 3.4
	post.mesh = post_mesh
	post.material_override = TrackBuilder.prop_material(Color(0.25, 0.28, 0.36))
	post.position = pos + Vector3.UP * 1.7
	add_child(post)
	var lamp := MeshInstance3D.new()
	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.32
	lamp_mesh.height = 0.64
	lamp_mesh.radial_segments = 8
	lamp_mesh.rings = 5
	lamp.mesh = lamp_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.7, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.62, 0.18)
	mat.emission_energy_multiplier = 2.6
	lamp.material_override = mat
	lamp.position = pos + Vector3.UP * 3.55
	add_child(lamp)
	if with_light:
		_try_add_omni(pos + Vector3.UP * 3.4)


func _try_add_omni(pos: Vector3) -> void:
	if _omni_lights >= MAX_OMNI_LIGHTS or GameConfig.is_headless():
		return
	if String(SettingsManager.get_setting("display", "particle_quality")) == "low":
		return
	var omni := OmniLight3D.new()
	omni.light_color = Color(1.0, 0.62, 0.25)
	omni.light_energy = 1.8
	omni.omni_range = 16.0
	omni.omni_attenuation = 1.4
	omni.shadow_enabled = false
	omni.position = pos
	add_child(omni)
	_omni_lights += 1


func _add_research_hut(pos: Vector3, look_target: Vector3) -> void:
	var hut := Node3D.new()
	hut.position = pos
	var flat := Vector3(look_target.x, pos.y, look_target.z)
	if flat.distance_squared_to(pos) > 0.01:
		hut.look_at_from_position(pos, flat, Vector3.UP)
	add_child(hut)
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(4.4, 2.8, 3.4)
	body.mesh = body_mesh
	body.material_override = TrackBuilder.prop_material(Color(0.75, 0.32, 0.2))
	body.position = Vector3(0, 1.4, 0)
	hut.add_child(body)
	var roof := MeshInstance3D.new()
	var roof_mesh := PrismMesh.new()
	roof_mesh.size = Vector3(4.8, 1.2, 3.8)
	roof.mesh = roof_mesh
	roof.material_override = TrackBuilder.prop_material(Color(0.9, 0.93, 0.98))
	roof.position = Vector3(0, 3.4, 0)
	hut.add_child(roof)
	var window_mat := StandardMaterial3D.new()
	window_mat.albedo_color = Color(1.0, 0.75, 0.35)
	window_mat.emission_enabled = true
	window_mat.emission = Color(1.0, 0.65, 0.2)
	window_mat.emission_energy_multiplier = 1.8
	for wx: float in [-1.1, 1.1]:
		var window := MeshInstance3D.new()
		var window_mesh := BoxMesh.new()
		window_mesh.size = Vector3(0.9, 0.9, 0.06)
		window.mesh = window_mesh
		window.material_override = window_mat
		window.position = Vector3(wx, 1.5, -1.72)
		hut.add_child(window)
	_add_station_light(pos + Vector3(2.8, 0, 1.5), true)


## --- Aurora sky, stars, wind wisps, glow crystals ---------------------------

## Serpentine curtain meshes wearing the shared animated aurora shader.
## The shader expects UV.x along the ribbon and UV.y = 0 at the top edge;
## each ribbon duplicates the cached material to vary intensity, band scale,
## curtain frequency, alpha, and scroll speed.
func _build_aurora() -> void:
	if GameConfig.is_headless():
		set_process(false)
		return
	var center := Vector3(20.0, 0.0, -520.0)
	var configs: Array[Dictionary] = [
		{"radius": 350.0, "y": 168.0, "h": 60.0, "a0": -0.5, "a1": 1.6, "wobble": 26.0,
			"intensity": 2.0, "bands": 3.2, "freq": 24.0, "alpha": 0.55, "scroll": 0.06},
		{"radius": 470.0, "y": 196.0, "h": 74.0, "a0": 2.3, "a1": 4.5, "wobble": 34.0,
			"intensity": 1.8, "bands": 2.4, "freq": 30.0, "alpha": 0.5, "scroll": 0.045},
		{"radius": 580.0, "y": 228.0, "h": 86.0, "a0": 0.8, "a1": 3.2, "wobble": 40.0,
			"intensity": 1.7, "bands": 2.8, "freq": 18.0, "alpha": 0.45, "scroll": 0.08},
		{"radius": 690.0, "y": 258.0, "h": 96.0, "a0": -1.3, "a1": 0.9, "wobble": 30.0,
			"intensity": 1.5, "bands": 3.6, "freq": 26.0, "alpha": 0.4, "scroll": 0.035},
	]
	for cfg: Dictionary in configs:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var segments := 30
		var radius := float(cfg["radius"])
		var prev_bottom := Vector3.ZERO
		var prev_top := Vector3.ZERO
		var prev_t := 0.0
		for i: int in segments + 1:
			var t := float(i) / float(segments)
			var angle := lerpf(float(cfg["a0"]), float(cfg["a1"]), t)
			var r := radius + sin(t * PI * 2.0 + radius) * float(cfg["wobble"])
			var wave := sin(t * PI * 3.0 + radius) * 12.0
			var bottom := center + Vector3(cos(angle) * r, float(cfg["y"]) + wave, sin(angle) * r)
			var top := bottom + Vector3.UP * (float(cfg["h"]) + sin(t * PI * 5.0 + radius) * 12.0)
			if i > 0:
				st.set_uv(Vector2(prev_t, 1.0)); st.add_vertex(prev_bottom)
				st.set_uv(Vector2(prev_t, 0.0)); st.add_vertex(prev_top)
				st.set_uv(Vector2(t, 0.0)); st.add_vertex(top)
				st.set_uv(Vector2(prev_t, 1.0)); st.add_vertex(prev_bottom)
				st.set_uv(Vector2(t, 0.0)); st.add_vertex(top)
				st.set_uv(Vector2(t, 1.0)); st.add_vertex(bottom)
			prev_bottom = bottom
			prev_top = top
			prev_t = t
		var ribbon := MeshInstance3D.new()
		ribbon.mesh = st.commit()
		var mat := VisualLibrary.aurora_material().duplicate() as ShaderMaterial
		mat.set_shader_parameter("intensity", float(cfg["intensity"]))
		mat.set_shader_parameter("band_scale", float(cfg["bands"]))
		mat.set_shader_parameter("curtain_frequency", float(cfg["freq"]))
		mat.set_shader_parameter("max_alpha", float(cfg["alpha"]))
		mat.set_shader_parameter("scroll_speed", float(cfg["scroll"]))
		ribbon.material_override = mat
		ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ribbon)
		_aurora_ribbons.append(ribbon)


## Star dome: one MultiMesh of soft additive billboards (same recipe as the
## title screen sky), fog-immune, brighter toward the dark zenith.
func _build_stars() -> void:
	if GameConfig.is_headless():
		return
	var center := Vector3(20.0, 20.0, -520.0)
	var count := 320
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var star_material := StandardMaterial3D.new()
	star_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	star_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	star_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	star_material.billboard_keep_scale = true
	star_material.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.9)
	star_material.vertex_color_use_as_albedo = true
	star_material.disable_receive_shadows = true
	star_material.disable_fog = true
	quad.material = star_material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = count
	for i: int in count:
		var azimuth := rng.randf() * TAU
		var altitude := rng.randf_range(0.1, 1.5)
		var dir := Vector3(cos(azimuth) * cos(altitude), sin(altitude), sin(azimuth) * cos(altitude))
		var s := rng.randf_range(2.4, 7.0)
		multimesh.set_instance_transform(i,
			Transform3D(Basis.from_scale(Vector3(s, s, s)), center + dir * 1150.0))
		var height_fade := clampf((altitude - 0.05) / 1.2, 0.0, 1.0)
		var alpha := rng.randf_range(0.35, 0.95) * (0.3 + 0.7 * height_fade)
		multimesh.set_instance_color(i, Color(0.85 + rng.randf() * 0.15, 0.9 + rng.randf() * 0.1, 1.0, alpha))
	var stars := MultiMeshInstance3D.new()
	stars.multimesh = multimesh
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stars)


## Blowing-snow wisps streaming across a crosswind zone: soft stretched
## billboards emitted upwind of the track, carried across it by the same
## direction the HazardWindZone pushes. Skipped headless / on low quality.
func _add_wind_wisps(xform: Transform3D, dir: float) -> void:
	if GameConfig.is_headless():
		return
	var quality := String(SettingsManager.get_setting("display", "particle_quality"))
	if quality == "low":
		return
	var wisps := GPUParticles3D.new()
	wisps.amount = 26 if quality == "high" else 14
	wisps.lifetime = 2.0
	wisps.preprocess = 2.0
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(2.0, 2.5, 16.0)
	mat.direction = Vector3(dir, 0.06, 0.0)
	mat.spread = 7.0
	mat.initial_velocity_min = 9.0
	mat.initial_velocity_max = 14.0
	mat.gravity = Vector3(0.0, -1.2, 0.0)
	mat.scale_min = 0.6
	mat.scale_max = 1.4
	mat.color = Color(0.82, 0.9, 1.0, 0.32)
	wisps.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(1.5, 0.4)
	var draw_mat := StandardMaterial3D.new()
	draw_mat.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.6)
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.disable_receive_shadows = true
	quad.material = draw_mat
	wisps.draw_pass_1 = quad
	wisps.visibility_aabb = AABB(Vector3(-34.0, -12.0, -22.0), Vector3(68.0, 24.0, 44.0))
	wisps.transform = Transform3D(xform.basis, xform.origin - xform.basis.x * (dir * 11.0) + xform.basis.y * 2.2)
	add_child(wisps)


## Faceted crystal cluster (shared VisualLibrary mesh) with a subtle emissive
## charge so it reads at twilight without joining the OmniLight3D budget.
func _add_glow_crystal(pos: Vector3, height: float, tint: Color) -> void:
	var crystal := MeshInstance3D.new()
	crystal.mesh = VisualLibrary.ice_crystal_mesh()
	crystal.material_override = _crystal_material(tint)
	crystal.scale = Vector3(height * 0.8, height, height * 0.8)
	crystal.rotation.y = rng.randf() * TAU
	crystal.position = pos
	crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(crystal)


func _crystal_material(tint: Color) -> StandardMaterial3D:
	var key := tint.to_html(false)
	if _crystal_mats.has(key):
		return _crystal_mats[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.2
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 0.55
	_crystal_mats[key] = mat
	return mat


var _ridge_clamp_start := 0.0
var _ridge_clamp_end := -1.0


## Ridge guard: HazardWindZone moves racers positionally, and sustained push
## accumulates penetration into ANY barrier (thin wall or solid berm) faster
## than depenetration recovers, until racers pop through the far side and
## fall off the ridge. Counter it in kind: clamp lateral offset to the berm
## line while on the ridge traverse. The berms visually sell the constraint.
func _physics_process(_delta: float) -> void:
	if _ridge_clamp_end <= _ridge_clamp_start:
		return
	for node: Node in get_tree().get_nodes_in_group(GameConfig.GROUP_RACERS):
		var r := node as Racer
		if r == null or r.state == Racer.State.FINISHED:
			continue
		var p := r.global_position
		if p.z > -290.0 or p.z < -530.0 or p.y < 55.0:
			continue
		var hint := int(r.guide_cache.get("main_idx", -1))
		var res := main_guide.nearest(p, hint)
		var idx := clampi(int(res["index"]), 0, _main_cum.size() - 1)
		var arc := _main_cum[idx]
		if arc < _ridge_clamp_start or arc > _ridge_clamp_end:
			continue
		var xf := main_guide.transform_at(arc)
		var lat := (p - xf.origin).dot(xf.basis.x)
		if absf(lat) > 5.2:
			r.global_position = p - xf.basis.x * (lat - clampf(lat, -5.2, 5.2))


func _process(delta: float) -> void:
	if _aurora_ribbons.is_empty():
		return
	_aurora_time += delta
	for i: int in _aurora_ribbons.size():
		var ribbon := _aurora_ribbons[i]
		var phase := float(i) * 1.9
		ribbon.position.y = sin(_aurora_time * 0.22 + phase) * 7.0
		ribbon.scale.y = 1.0 + 0.1 * sin(_aurora_time * 0.15 + phase * 1.7)
