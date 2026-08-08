class_name CourseAurora
extends CourseBase
## AURORA ASCENT: twilight mountain under the southern lights. Switchback
## climb, windy ridge traverse, icicle cavern, a narrow no-wall ridge
## shortcut, an ice geyser field, and a huge 270-degree corkscrew descent
## to a research-station finish. Deep star-strewn twilight sky with a big
## haloed moon that carries the scene key light (snow shading, ice speculars,
## and shadows all match the disc), animated aurora curtains arcing low across
## the forward view (shared VisualLibrary shader) that converge into a crown
## over the finish and reflect faintly off the smooth-ice corkscrew,
## dark-blue ambient snow, a warm light-pollution stain on the horizon over
## the research-camp side, a zenith-dense star field with power-law brightness
## plus a few large scintillating twinklers, pulsing glow crystals along the
## route, warm research lamps (sparse real lights), a dome-tent research
## outpost and cable-car line seen from the climb, dramatic frost-banded cliff
## dropoffs with exposure-driven blowing-snow streamers along the windy ridge,
## and distant lit-from-within crystal spires ringing the valley floor.

const SNOW := SurfacesDB.Surface.PACKED_SNOW
const ICE := SurfacesDB.Surface.ICE_SMOOTH
const RICE := SurfacesDB.Surface.ICE_ROUGH

## Hard cap on real OmniLight3Ds (mobile renderer: keep the cluster light
## count tiny). Everything else glows via emissive materials only.
const MAX_OMNI_LIGHTS: int = 5

## Unit direction from the course toward the moon disc. The environment key
## light ("sun") is aimed along -MOON_DIR in build_course, so snow shading,
## the moonlit specular smears on ice, shadow direction, and the procedural
## sky halo all agree with the visible moon billboard.
const MOON_DIR := Vector3(-0.34032, 0.40038, -0.85081)

var _aurora_ribbons: Array[Node3D] = []
var _aurora_time: float = 0.0
var _omni_lights: int = 0
var _crystal_mats: Dictionary = {}

## Hero twinkler stars animated in _process (scale + alpha scintillation).
var _twinklers: Array[MeshInstance3D] = []
var _twinkler_mats: Array[StandardMaterial3D] = []
var _twinkler_base: PackedFloat32Array = PackedFloat32Array()
var _twinkler_phase: PackedFloat32Array = PackedFloat32Array()
var _twinkler_speed: PackedFloat32Array = PackedFloat32Array()

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
		# 1) Start ridge plateau. The middle span is a smooth-ice patch: an
		# early flat slide reward on the dead-straight opening.
		p(0, 40, 35, {"width": 18.0}),
		p(0, 40, -25, {"width": 18.0, "surface": ICE}),
		p(0, 40, -62, {"width": 18.0}),
		# 2) Zigzag switchback climb (+40m over ~560m, three gentle hairpins).
		p(16, 41.5, -94, {"width": 16.0}),
		p(48, 44.5, -108, {"width": 16.0}),
		p(84, 47.6, -114, {"width": 16.0}),
		p(112, 49.4, -122, {"width": 16.0}),
		p(127, 51.5, -146, {"width": 16.0}),  # hairpin 1 apex
		p(112, 53.6, -170, {"width": 16.0}),
		p(64, 57.3, -180, {"width": 16.0}),
		p(12, 61.2, -188, {"width": 16.0}),
		p(-38, 64.8, -196, {"width": 16.0}),
		p(-70, 67.0, -206, {"width": 16.0}),
		p(-87, 69.1, -230, {"width": 16.0}),  # hairpin 2 apex
		p(-70, 71.2, -254, {"width": 16.0}),
		p(-28, 74.2, -264, {"width": 16.0}),
		p(14, 77.3, -272, {"width": 16.0}),
		p(42, 78.8, -282, {"width": 16.0}),   # hairpin 3 (turn back to -Z)
		p(58, 80.0, -306, {"width": 15.0}),
		# 3) Windy ridge traverse: narrow, low walls ON, crosswinds, and a
		# rolling undulation (+/-1-2m) so the spine reads wind-carved.
		p(60, 80.6, -340, {"width": 12.0}),
		p(55, 78.8, -386, {"width": 12.0}),
		p(61, 81.0, -430, {"width": 12.0}),
		p(56, 79.2, -466, {"width": 12.0}),
		# 4) Icicle cavern: rough ice, gentle downhill.
		p(48, 76.8, -502, {"width": 13.0, "surface": RICE}),
		p(42, 74.0, -540, {"width": 13.0, "surface": RICE}),
		p(50, 71.2, -578, {"width": 13.0, "surface": RICE}),
		p(46, 68.4, -616, {"width": 13.0, "surface": RICE, "wall_r": false}),
		# 5) Safe switchback descent (shortcut branch cuts this loop).
		p(28, 66.8, -648, {"width": 16.0, "wall_r": false}),
		p(-6, 64.4, -670, {"width": 16.0, "wall_r": false}),
		p(-38, 61.8, -690, {"width": 16.0}),
		p(-58, 59.8, -708, {"width": 15.0}),
		p(-70, 58.2, -728, {"width": 15.0}),
		p(-74, 56.6, -752, {"width": 15.0}),  # descent hairpin apex
		p(-62, 55.0, -774, {"width": 15.0}),
		p(-34, 53.0, -792, {"width": 15.0}),
		# Descent tail: smooth-ice patch on the near-straight run-out (ends
		# ~60m before the geyser field, so steering room is back first).
		p(4, 50.8, -808, {"width": 16.0, "surface": ICE}),
		p(30, 49.0, -822, {"width": 16.0, "surface": ICE}),
		p(44, 47.8, -840, {"width": 16.0, "wall_r": false}),
		p(50, 46.8, -864, {"width": 18.0, "wall_r": false}),
		p(46, 46.0, -888, {"width": 20.0, "wall_r": false}),
		# 6) Ice geyser field: wide downhill, playful launches.
		p(40, 42.0, -938, {"width": 20.0}),
		p(34, 38.4, -986, {"width": 20.0}),
		# Corkscrew approach iced so the finale slide starts past the geysers.
		p(34, 36.2, -1014, {"width": 20.0, "surface": ICE}),
		# 7) Corkscrew finale: 270-degree descending spiral, r=45, drops ~42m
		# at a sustained ~11.5 degrees — most of the climb's gained height.
		p(35, 35.0, -1030, {"width": 18.0, "surface": ICE}),
		p(48.2, 28.0, -1061.8, {"width": 17.0, "surface": ICE}),
		p(80, 21.0, -1075, {"width": 17.0, "surface": ICE}),
		p(111.8, 14.0, -1061.8, {"width": 17.0, "surface": ICE}),
		p(125, 7.0, -1030, {"width": 17.0, "surface": ICE}),
		p(111.8, 0.0, -998.2, {"width": 17.0, "surface": ICE}),
		p(80, -7.0, -985, {"width": 18.0, "surface": ICE}),
		# 8) Finish straight (passes ~45m under the geyser field).
		p(46, -8.0, -990, {"width": 18.0}),
		p(8, -8.6, -994, {"width": 18.0}),
		p(-34, -9, -997, {"width": 18.0}),
		p(-72, -9, -999, {"width": 18.0}),
	]
	setup_main(pts)

	# 5) Narrow ridge shortcut: width 7, NO walls, skips the switchback
	# descent along an exposed spine right of the safe route (~110m saved).
	var branch_pts: Array = [
		p(38, 67.4, -630, {"width": 9.0, "surface": RICE, "wall_l": false, "wall_r": false}),
		p(46, 65.2, -664, {"width": 7.0, "surface": RICE, "wall_l": false, "wall_r": false}),
		p(52, 62.6, -700, {"width": 7.0, "surface": RICE, "wall_l": false, "wall_r": false}),
		p(56, 59.8, -736, {"width": 7.0, "surface": RICE, "wall_l": false, "wall_r": false}),
		p(52, 56.8, -772, {"width": 7.0, "surface": RICE, "wall_l": false, "wall_r": false}),
		p(56, 53.6, -806, {"width": 7.0, "surface": RICE, "wall_l": false, "wall_r": false}),
		p(58, 50.4, -838, {"width": 8.0, "surface": RICE, "wall_l": false, "wall_r": false}),
		p(56, 47.6, -858, {"width": 9.0, "surface": RICE, "wall_l": false, "wall_r": false}),
		p(48, 46.4, -880, {"width": 9.0, "surface": RICE, "wall_l": false, "wall_r": false}),
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
	var ridge_arc := _arc_near(Vector3(60, 80.6, -340))
	var ridge_mid_arc := _arc_near(Vector3(55, 78.8, -386))
	var ridge_late_arc := _arc_near(Vector3(61, 81.0, -430))
	var ridge_end_arc := _arc_near(Vector3(56, 79.2, -466))
	var cavern_arc := _arc_near(Vector3(48, 76.8, -502))
	var cavern_end_arc := _arc_near(Vector3(46, 68.4, -616))
	var merge_arc := _arc_near(Vector3(46, 46.0, -888))
	var geyser_arc := _arc_near(Vector3(40, 42.0, -938))
	var spiral_arc := _arc_near(Vector3(35, 35.0, -1030))
	var spiral_mid_arc := _arc_near(Vector3(80, 21.0, -1075))
	var spiral_late_arc := _arc_near(Vector3(125, 7.0, -1030))
	var spiral_end_arc := _arc_near(Vector3(80, -7.0, -985))

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

	# More acceleration pads, each on a straight AFTER its corner fully
	# completes (playtest: pads directly on hairpin exits boosted AI while
	# still steering — they overshot into walls/edges and fell): the gentle
	# uphill grind before the hairpin-1 climb (extra speed is safe into a
	# grade), the mid-straight after hairpin 1, the straight between
	# hairpins 2 and 3 (~70m before hairpin 3 begins), and the run-out
	# straight after the descent hairpin (boost expires before the descent-
	# tail ice and the wall-less merge span at -840). The ridge-shortcut
	# survivor reward moved OFF the narrow no-wall spine onto the wide main
	# line just past its merge, where rejoining racers have realigned. All
	# clear of the wind zones, icicle cavern, and the geyser lanes.
	TrackBuilder.add_boost_pad(self, main_guide, _arc_near(Vector3(48, 44.5, -108)) + 6.0)
	TrackBuilder.add_boost_pad(self, main_guide, _arc_near(Vector3(64, 57.3, -180)) + 4.0)
	TrackBuilder.add_boost_pad(self, main_guide, _arc_near(Vector3(-28, 74.2, -264)) + 4.0)
	TrackBuilder.add_boost_pad(self, main_guide, _arc_near(Vector3(-34, 53.0, -792)) + 4.0)
	TrackBuilder.add_boost_pad(self, main_guide, merge_arc + 10.0)
	# Slide hint for the new descent-tail ice patch (start plateau ice is
	# left unhinted — racers are still building speed off the grid; the
	# corkscrew-approach ice sits inside the geyser->spiral slide hint).
	add_hint(_arc_near(Vector3(4, 50.8, -808)) - 8.0, "slide", _arc_near(Vector3(44, 47.8, -840)))

	# Shortcut: slide its steep tail. Branch hint offsets are main-line
	# equivalents: lerp(entry, exit) by branch arc fraction (see get_guide).
	var b_entry := float(branch_info["entry"])
	var b_exit := float(branch_info["exit"])
	add_hint(b_entry + (150.0 / shortcut.length) * (b_exit - b_entry), "slide", b_exit + 30.0, 0)

	# --- Pickups (arc offsets: placement space) ----------------------------
	add_item_row(120.0)
	add_item_row(ridge_arc + 10.0)
	add_item_row(_arc_near(Vector3(-6, 64.4, -670)))
	add_item_row(merge_arc + 6.0)
	add_item_row(_arc_near(Vector3(34, 36.2, -1014)))
	add_snowball_row(160.0)
	add_snowball_row(ridge_arc + 45.0)
	add_snowball_row(_arc_near(Vector3(34, 36.2, -1014)) + 30.0)

	add_fish_line(55.0, 8, 5.0, 0.0)
	add_fish_line(_arc_near(Vector3(48, 44.5, -108)), 8, 5.0, -3.0)
	add_fish_line(_arc_near(Vector3(12, 61.2, -188)) - 15.0, 10, 5.0, 0.0)
	add_fish_line(_arc_near(Vector3(-28, 74.2, -264)), 8, 5.0, 3.0)
	add_fish_line(ridge_mid_arc, 8, 5.5, 0.0)
	add_fish_line(_arc_near(Vector3(42, 74.0, -540)), 10, 4.5, 0.0)
	add_fish_line(_arc_near(Vector3(-62, 55.0, -774)), 10, 5.0, -4.0)
	add_fish_line(30.0, 10, 6.0, 0.0, 0.0, shortcut)  # reward the ridge
	add_fish_line(_arc_near(Vector3(40, 42.0, -938)), 10, 5.0, 5.0)
	add_fish_line(spiral_arc + 35.0, 12, 6.0, 0.0)
	add_fish_line(_arc_near(Vector3(80, -7.0, -985)) + 12.0, 8, 5.0, 0.0)

	# Twilight snowfield first: the peak rings, crystal spires, rock mesas and
	# berg ring all seat themselves on it, so it must exist before the dressing
	# runs. Darker, richer twilight snowfield: deep blue-violet albedo with
	# sparkle raised so the plain reads as star-frosted night snow instead of a
	# pale grey wash lifting the whole lower frame.
	add_ground_plane(-32.0, Color(0.06, 0.08, 0.16), 4000.0,
		VisualLibrary.snow_material(Color(0.36, 0.42, 0.74), 0.95))

	_decorate()
	_build_aurora()
	_build_stars()
	_build_moon()
	_build_horizon_glow()
	_add_aurora_reflections(spiral_arc + 2.0, spiral_end_arc - 2.0)
	_add_moon_glints(spiral_arc + 8.0, spiral_end_arc)
	# Deep twilight: near-black zenith falling to a muted violet horizon band,
	# dark-blue ambient tinting every snow surface, thin distance haze (dense
	# fog would eat the aurora/stars) plus ground mist pooling in the finish
	# bowl below y=2. The directional key light is aimed along -MOON_DIR so
	# the moon visibly lights the snow: cool shading, ice speculars, and
	# shadow direction all match the disc, and the small procedural-sky "sun"
	# halo lands directly behind the moon billboard as its atmospheric glow.
	build_environment({
		"sky_top": Color(0.02, 0.04, 0.12),
		"sky_horizon": Color(0.3, 0.21, 0.43),
		"ground_color": Color(0.05, 0.07, 0.16),
		"sun_angle_deg": rad_to_deg(asin(-MOON_DIR.y)),
		"sun_yaw_deg": rad_to_deg(atan2(MOON_DIR.x, MOON_DIR.z)),
		"sun_energy": 0.85,  # moonlight lifted so racers read against night snow
		"sun_color": Color(0.7, 0.78, 1.0),
		"sun_angle_max": 5.0,
		"sun_curve": 0.12,
		"sky_energy": 0.9,
		"exposure": 1.02,
		"fog_color": Color(0.09, 0.12, 0.26),
		"fog_density": 0.0015,
		"fog_height": 2.0,
		"fog_height_density": 0.05,
		"glow": true,
		"glow_threshold": 1.05,
		"shadow_distance": 120.0,
		"ambient_energy": 1.6,
		"snow": true,
		"distant_bergs": true,
		"berg_color": Color(0.34, 0.42, 0.66),
		"berg_count": 12,
		"berg_distance": 800.0,
	})


## --- Peak rings ---------------------------------------------------------------
## Both silhouette rings are centred here and sized by how far the COURSE
## reaches in each direction, rather than by a fixed radius.
##
## A fixed radius was the bug the player reported as "the mountains overlap the
## course". Aurora is a switchback climb 1065 m long and 320 m wide, so its own
## reach from this centre runs from about 190 m out to the sides to 560 m fore
## and aft -- and the near ring was authored at 380-620 m, a radius SMALLER
## than the course in the directions where the course is longest. Four of the
## sixteen peaks were consequently planted straight through the deck: one over
## the start line, one over the geyser downhill, one over the corkscrew and one
## over the finish straight, each reaching 8.4-9.9 m inboard of a 9-10 m half
## width, which is to say across the whole racing line. Measured with
## tests/overlap_probe.tscn; re-run it after touching anything here.
const PEAK_CENTRE: Vector3 = Vector3(20.0, 0.0, -520.0)
## Half-extent of berg_mesh in its own unit space, so a peak's world footprint
## is this times its scale. Measured from the probe's reported AABBs.
const PEAK_UNIT_HALF: float = 1.45
## Clear air demanded between a peak's footprint and the widest deck edge.
const PEAK_MARGIN: float = 45.0
## Bearing window searched for the course's reach. Wide enough that a peak
## cannot slip past the shoulder of a leg just outside its own bearing.
const PEAK_ARC_WINDOW: float = 0.45


var _peak_reach: PackedFloat32Array = PackedFloat32Array()


## Distance from PEAK_CENTRE at which a peak of `scale` may stand on `angle`
## without touching the course, never closer than `minimum`.
func _peak_ring_distance(angle: float, scale: Vector3, minimum: float) -> float:
	var footprint := maxf(scale.x, scale.z) * PEAK_UNIT_HALF
	return maxf(minimum, _course_reach(angle) + footprint + PEAK_MARGIN)


## Furthest the racing line gets from PEAK_CENTRE within PEAK_ARC_WINDOW of
## `angle`, including the widest half-width there. Built once from every guide
## and bucketed by bearing.
func _course_reach(angle: float) -> float:
	if _peak_reach.is_empty():
		_build_peak_reach()
	var buckets := _peak_reach.size()
	var span := int(ceil(PEAK_ARC_WINDOW / (TAU / float(buckets))))
	var centre_bucket := int(floor(fposmod(angle, TAU) / (TAU / float(buckets))))
	var reach := 0.0
	for i: int in range(centre_bucket - span, centre_bucket + span + 1):
		reach = maxf(reach, _peak_reach[posmod(i, buckets)])
	return reach


func _build_peak_reach() -> void:
	_peak_reach.resize(72)
	_peak_reach.fill(0.0)
	var guides: Array[PathGuide] = [main_guide]
	for branch: Dictionary in branches:
		var g: PathGuide = branch.get("guide")
		if g != null:
			guides.append(g)
	for guide: PathGuide in guides:
		var step := 4.0
		var offset := 0.0
		while offset <= guide.length:
			var origin := guide.transform_at(offset).origin
			# Half-width is not tracked per sample here, so the widest span on
			# the course is added to every sample -- cheap, and erring outward
			# is the whole point.
			var to := Vector2(origin.x - PEAK_CENTRE.x, origin.z - PEAK_CENTRE.z)
			var bucket := int(floor(fposmod(atan2(to.x, to.y), TAU) / (TAU / 72.0)))
			_peak_reach[bucket] = maxf(_peak_reach[bucket], to.length() + 10.0)
			offset += step


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
	var hut_a := main_guide.transform_at(_arc_near(Vector3(60, 80.6, -340)))
	_add_research_hut(hut_a.origin + hut_a.basis.x * 14.0, hut_a.origin)
	var hut_b := main_guide.transform_at(_arc_near(Vector3(40, 42.0, -938)))
	_add_research_hut(hut_b.origin + hut_b.basis.x * -15.0, hut_b.origin)

	# Research outpost on a mesa below hairpin 2: warm-lit dome tents and
	# antenna masts the racers look down on through the whole zigzag climb.
	_add_research_station(Vector3(-150.0, 44.0, -252.0), Vector3(-87.0, 69.1, -230.0))
	# Cable-car line strung between two rock spurs east of the climb — its
	# sagging silhouette and lit gondolas cross the sky above the switchbacks.
	_add_cable_car_line(Vector3(168.0, 74.0, -152.0), Vector3(96.0, 98.0, -348.0))

	# Windy ridge: softly glowing crystal fins flanking the traverse in
	# alternating aurora green / violet.
	var ridge_start := _arc_near(Vector3(60, 80.6, -340))
	var ridge_end := _arc_near(Vector3(56, 79.2, -466))
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

	# Dramatic cliff dropoffs falling away from both ridge edges, plus
	# wind-torn snow streamers blowing off the lips into the valley below.
	var cliff_end := _arc_near(Vector3(48, 76.8, -502)) + 8.0
	_add_ridge_cliffs(ridge_start - 14.0, cliff_end)
	var streamer_arc := ridge_start + 8.0
	var streamer_side := 1.0
	while streamer_arc < ridge_end:
		# Wind exposure: local crests along the undulating spine shed far more
		# spindrift than the sheltered saddles between them. Compare the deck
		# height against the ridge line ~20m either side and scale the streamer
		# density / speed / opacity by the result.
		var deck_y := main_guide.transform_at(streamer_arc).origin.y
		var flank_y := (main_guide.transform_at(streamer_arc - 20.0).origin.y
			+ main_guide.transform_at(streamer_arc + 20.0).origin.y) * 0.5
		var exposure := clampf(0.55 + (deck_y - flank_y) * 0.45, 0.25, 1.0)
		_add_edge_streamer(main_guide.transform_at(streamer_arc), streamer_side, exposure)
		streamer_side = -streamer_side
		streamer_arc += 34.0

	# Icicle cavern: crystalline ice arches + glow shards lining the walls.
	var cavern_start := _arc_near(Vector3(48, 76.8, -502))
	var cavern_end := _arc_near(Vector3(46, 68.4, -616))
	# The arches used the track's ice shader, which is authored for a deck seen
	# from above under a sun. Wrapped around a ten-metre torus on a night
	# course it had almost nothing to work with and the arches rendered as flat
	# black holes punched through the sky -- the most conspicuously broken
	# thing in the cavern. They now carry their own glacial material with
	# enough self-emission to read as lit ice, matching the glow crystals
	# already lining these walls.
	var arch_mat := StandardMaterial3D.new()
	arch_mat.albedo_color = Color(0.42, 0.62, 0.88, 0.93)
	arch_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	arch_mat.roughness = 0.18
	arch_mat.metallic = 0.0
	arch_mat.emission_enabled = true
	arch_mat.emission = Color(0.36, 0.66, 0.95)
	arch_mat.emission_energy_multiplier = 0.55
	arch_mat.rim_enabled = true
	arch_mat.rim = 0.85
	arch_mat.rim_tint = 0.4
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
		var peak := MeshInstance3D.new()
		peak.mesh = VisualLibrary.berg_mesh(rng.randi())
		peak.material_override = peak_mat
		var width := rng.randf_range(90.0, 170.0)
		peak.scale = Vector3(width * rng.randf_range(0.9, 1.4), rng.randf_range(70.0, 130.0), width)
		var dist := _peak_ring_distance(angle, peak.scale, 380.0)
		peak.position = Vector3(PEAK_CENTRE.x + sin(angle) * dist, -30.0,
			PEAK_CENTRE.z + cos(angle) * dist)
		peak.rotation.y = rng.randf() * TAU
		peak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(peak)
	# Second, farther silhouette ring: taller, darker massifs sunk toward the
	# horizon glow. Two depth layers give the ridge-behind-ridge recession of
	# real twilight ranges instead of one flat paper cutout ring.
	var far_peak_mat := VisualLibrary.rock_material(Color(0.17, 0.21, 0.4))
	for i: int in 11:
		var angle := TAU * float(i) / 11.0 + rng.randf_range(-0.2, 0.2)
		var peak := MeshInstance3D.new()
		peak.mesh = VisualLibrary.berg_mesh(rng.randi())
		peak.material_override = far_peak_mat
		var width := rng.randf_range(140.0, 240.0)
		peak.scale = Vector3(width * rng.randf_range(0.9, 1.4), rng.randf_range(110.0, 190.0), width)
		var dist := _peak_ring_distance(angle, peak.scale, 700.0)
		peak.position = Vector3(PEAK_CENTRE.x + sin(angle) * dist, -32.0,
			PEAK_CENTRE.z + cos(angle) * dist)
		peak.rotation.y = rng.randf() * TAU
		peak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(peak)

	# Snowdrift mounds fill the course flanks so the slopes never read empty.
	# Each candidate is checked against every racing line, not just the one it
	# was measured from: the ridge shortcut runs parallel to the main descent,
	# close enough that a 28 m lateral off the main guide can land on it.
	var drift_mesh := VisualLibrary.snow_drift_mesh()
	var drift_mat := VisualLibrary.rock_material(Color(0.62, 0.68, 0.92))
	for i: int in 30:
		var drift_scale := rng.randf_range(1.6, 4.2)
		var drift_wide := drift_scale * rng.randf_range(0.9, 1.5)
		var drift_pos := Vector3.ZERO
		var drift_ok := false
		for _attempt: int in 6:
			var drift_offset := rng.randf_range(30.0, main_guide.length - 50.0)
			var drift_xform := main_guide.transform_at(drift_offset)
			var drift_lateral := rng.randf_range(12.0, 28.0) * (1.0 if rng.randf() > 0.5 else -1.0)
			drift_pos = drift_xform.origin + drift_xform.basis.x * drift_lateral + Vector3.DOWN * 0.8
			if clear_of_track(drift_pos, maxf(drift_wide, drift_scale)):
				drift_ok = true
				break
		if not drift_ok:
			continue
		var drift := MeshInstance3D.new()
		drift.mesh = drift_mesh
		drift.material_override = drift_mat
		drift.scale = Vector3(drift_wide, drift_scale * rng.randf_range(0.5, 0.9), drift_scale)
		drift.position = drift_pos
		drift.rotation.y = rng.randf() * TAU
		drift.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(drift)

	# Rocks and glow crystals scattered along the route, out on the flanks past
	# the track walls. Laterals stay where they were on purpose: everything
	# between the deck edge and the wall is in the wall's own shadow, and
	# dressing moved in there disappears behind it.
	for i: int in 26:
		var offset2 := rng.randf_range(40.0, main_guide.length - 60.0)
		var xform2 := main_guide.transform_at(offset2)
		var lateral2 := rng.randf_range(13.0, 26.0) * (1.0 if rng.randf() > 0.5 else -1.0)
		var flank_pos := xform2.origin + xform2.basis.x * lateral2 + Vector3.DOWN * 1.0
		if rng.randf() > 0.55:
			var rock_s := rng.randf_range(0.7, 1.8)
			TrackBuilder.add_rock(self, flank_pos, rock_s, rng)
			_add_flank_contact_patch(flank_pos, rock_s * 0.8)
		else:
			var glow_h := rng.randf_range(2.0, 5.5)
			_add_glow_crystal(flank_pos, glow_h,
				Color(0.55, 0.8, 1.0) if rng.randf() > 0.5 else Color(0.7, 0.5, 1.0))
			_add_flank_contact_patch(flank_pos, glow_h * 0.26)

	# Dense filler crystal field: small static shards in aurora green/violet
	# catching the sky light along the whole route (the pulsing hero crystals
	# above stay individual; this field is pure density at two draw calls).
	_add_crystal_field()

	# Distant lit-from-within crystal spires ringing the valley floor below
	# the mountain — mid-distance landmarks between the track and the peak
	# silhouettes, so the world reads inhabited by the same crystal light the
	# trackside shards carry.
	_add_crystal_spires()

	# Landmark crystal monoliths: one on the outside of each hairpin apex
	# (all three apexes bulge away from x=0 and run -Z, so the outward side
	# is sign(apex.x) along basis.x) + a beacon rising through the middle of
	# the corkscrew finale.
	for apex: Vector3 in [Vector3(127, 51.5, -146), Vector3(-87, 69.1, -230), Vector3(-74, 56.6, -752)]:
		var apex_xform := main_guide.transform_at(_arc_near(apex))
		var out_side := 1.0 if apex.x > 0.0 else -1.0
		_add_glow_crystal(apex_xform.origin + apex_xform.basis.x * (13.0 * out_side) + Vector3.DOWN * 2.0,
			rng.randf_range(7.0, 10.0), Color(0.45, 1.0, 0.7))
	_add_glow_crystal(Vector3(80.0, -18.0, -1030.0), 30.0, Color(0.5, 1.0, 0.75))

	# Baked contact shadows, flushed last so every pass above has had its chance
	# to register one. Moonlight this weak casts almost no readable shadow of
	# its own, so without a patch at the foot even a correctly bedded rock
	# floats free of the snow it is standing in.
	_add_multimesh(VisualLibrary.contact_patch_mesh(), _contact_patches,
		_contact_material(), "ContactShadows", 240.0)


## --- Contact shadows ---------------------------------------------------------
## gl_compatibility has no SSAO, so the occlusion that plants a prop on the
## ground has to be geometry: one soft alpha quad per prop, all of them through
## a single MultiMesh (one draw call for the whole mountain).

var _contact_patches: Array[Transform3D] = []


## Polar night: no sun, a low moon and the curtain itself, over snow that reads
## deep blue-violet. Shade here is nearly black with the sky's violet still in
## it — glacier's daylight blue-grey would be LIGHTER than this ground and
## would paint pale discs instead of shadows. Low alpha to match: at this
## exposure a small darkening is already plenty.
func _contact_material() -> StandardMaterial3D:
	var mat := VisualLibrary.contact_shadow_material().duplicate() as StandardMaterial3D
	mat.albedo_color = Color(0.05, 0.06, 0.17, 0.40)
	return mat


## BUILD TIME ONLY. Registers a contact shadow at the foot of a flank prop.
## `radius` is the prop's footprint; the patch is drawn a shade wider, because a
## real ambient-occlusion contact reaches slightly past the silhouette.
##
## Anchored to the prop's OWN base rather than to a probed ground height, which
## is the one course where that is the right call. The flanks here are cliffs,
## mesas and berms — all visual-only meshes with no collision — so a downward
## probe sees nothing but the base plane 100m below, and the height the dressing
## was authored against (a metre under the deck plane) is the best statement
## anyone can make about where these props meet the mountain. The failure mode
## is bounded too: if a prop does hang free, its patch hangs with it and reads
## as the prop's own dark foot instead of as a decal stranded on the ground.
func _add_flank_contact_patch(pos: Vector3, radius: float) -> void:
	_contact_patches.append(Transform3D(
		Basis.from_scale(Vector3(radius * 2.4, 1.0, radius * 2.4)),
		pos + Vector3.UP * 0.05))


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


## --- Ridge cliffs, outpost, cable car ---------------------------------------

static func _ctri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		col_a: Color, col_b: Color, col_c: Color) -> void:
	st.set_color(col_a)
	st.add_vertex(a)
	st.set_color(col_b)
	st.add_vertex(b)
	st.set_color(col_c)
	st.add_vertex(c)


## Dramatic cliff dropoffs flanking the windy ridge traverse: dark faceted
## rock faces falling ~46m from both edges into the valley haze, with a pale
## snow-dusted lip where they meet the berms and jittered crags below.
## Visual only — the berms and the lateral clamp own the gameplay boundary.
func _add_ridge_cliffs(start_arc: float, end_arc: float) -> void:
	var mat := VisualLibrary.rock_material(Color(0.36, 0.39, 0.55))
	var step := 7.0
	var count := maxi(int((end_arc - start_arc) / step), 2)
	# Rings: lateral reach + drop below the deck (lip -> ledge -> crag -> base).
	# The lip ring is unjittered and tucks under the berm's outer face so the
	# berm and cliff read as one continuous edge with no gap strip.
	var ring_lat: Array[float] = [8.2, 11.8, 15.5, 21.0, 28.5]
	var ring_drop: Array[float] = [-0.3, 2.8, 13.0, 28.0, 46.0]
	var ring_col: Array[Color] = [
		Color(0.85, 0.9, 1.05),   # snow-dusted lip
		Color(0.6, 0.63, 0.78),
		Color(0.42, 0.44, 0.58),
		Color(0.3, 0.31, 0.42),
		Color(0.2, 0.21, 0.3),    # fades into the valley darkness
	]
	var rings := ring_lat.size()
	for s: float in [-1.0, 1.0]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		# Precompute jittered stations so adjacent quads share edges exactly.
		var stations: Array = []
		for i: int in count + 1:
			var xform := main_guide.transform_at(start_arc + float(i) * step)
			var right := xform.basis.x * s
			var pts: Array[Vector3] = []
			for r_i: int in rings:
				var jl := 0.0 if r_i == 0 else rng.randf_range(-1.6, 1.6) * (0.4 + 0.3 * float(r_i))
				var jd := 0.0 if r_i == 0 else rng.randf_range(-1.8, 1.8)
				pts.append(xform.origin + right * (ring_lat[r_i] + jl)
					+ Vector3.DOWN * (ring_drop[r_i] + jd))
			stations.append(pts)
		for i: int in count:
			var a: Array[Vector3] = stations[i]
			var b: Array[Vector3] = stations[i + 1]
			for r_i: int in rings - 1:
				var shade := rng.randf_range(0.8, 1.15)
				# Frost-banded strata: pale ice seams striping the rock face at
				# roughly constant depth, with the phase drifting along the wall
				# (station index) so bands dip and rise like real sediment lines
				# picked out by wind-packed frost.
				var frost := Color(0.78, 0.86, 1.02)
				var f_top := pow(0.5 + 0.5 * sin(ring_drop[r_i] * 0.5 + float(i) * 0.55), 3.0) * 0.4
				var f_bot := pow(0.5 + 0.5 * sin(ring_drop[r_i + 1] * 0.5 + float(i) * 0.55), 3.0) * 0.4
				var ct := ring_col[r_i].lerp(frost, f_top) * shade
				var cb := ring_col[r_i + 1].lerp(frost, f_bot) * shade
				ct.a = 1.0
				cb.a = 1.0
				if s > 0.0:
					_ctri(st, a[r_i], b[r_i], b[r_i + 1], ct, ct, cb)
					_ctri(st, a[r_i], b[r_i + 1], a[r_i + 1], ct, cb, cb)
				else:
					_ctri(st, a[r_i], b[r_i + 1], b[r_i], ct, cb, ct)
					_ctri(st, a[r_i], a[r_i + 1], b[r_i + 1], ct, cb, cb)
		st.generate_normals()
		var cliff := MeshInstance3D.new()
		cliff.mesh = st.commit()
		cliff.material_override = mat
		cliff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cliff)


## Wind-torn snow streamer blowing off a cliff lip: stretched-quad particles
## launched outward over the dropoff, sinking as they fade into the valley.
## exposure (0.25-1.0) scales density, launch speed, and opacity so crests
## stream hard while sheltered saddles only dribble. Skipped headless / on
## low particle quality.
func _add_edge_streamer(xform: Transform3D, side: float, exposure: float = 1.0) -> void:
	if GameConfig.is_headless():
		return
	var quality := String(SettingsManager.get_setting("display", "particle_quality"))
	if quality == "low":
		return
	var streamer := GPUParticles3D.new()
	var base_amount := 16 if quality == "high" else 9
	streamer.amount = maxi(4, int(roundf(float(base_amount) * exposure)))
	streamer.lifetime = 2.6
	streamer.preprocess = 2.6
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(1.2, 0.8, 7.0)
	mat.direction = Vector3(side, 0.18, 0.0)
	mat.spread = 9.0
	mat.initial_velocity_min = lerpf(4.0, 7.5, exposure)
	mat.initial_velocity_max = lerpf(7.5, 12.5, exposure)
	mat.gravity = Vector3(0.0, -3.2, 0.0)
	mat.scale_min = 0.7
	mat.scale_max = 1.8
	mat.color = Color(0.85, 0.92, 1.0, 0.16 + 0.14 * exposure)
	streamer.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(2.6, 0.5)
	var draw_mat := StandardMaterial3D.new()
	draw_mat.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.6)
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.disable_receive_shadows = true
	quad.material = draw_mat
	streamer.draw_pass_1 = quad
	streamer.visibility_aabb = AABB(Vector3(-42.0, -32.0, -22.0), Vector3(84.0, 42.0, 44.0))
	streamer.transform = Transform3D(xform.basis,
		xform.origin + xform.basis.x * (side * 9.0) + xform.basis.y * 1.4)
	add_child(streamer)


## Craggy rock mesa rising from the valley floor to a snow-capped top —
## grounds off-track set pieces (outpost plateau, cable-car pylons) so
## nothing floats over the void. Per-face shade jitter via vertex colors.
func _add_rock_mesa(top_center: Vector3, top_radius: float, base_radius: float) -> void:
	var sides := 9
	var fracs: Array[float] = [0.0, 0.45, 0.8, 1.0]
	var base_y := -34.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring_pts: Array = []
	for f: float in fracs:
		var y := lerpf(base_y, top_center.y, f)
		var r := lerpf(base_radius, top_radius, pow(f, 0.7))
		var pts: Array[Vector3] = []
		for i: int in sides:
			var angle := TAU * float(i) / float(sides)
			var jr := r * (1.0 if is_equal_approx(f, 1.0) else rng.randf_range(0.86, 1.14))
			pts.append(Vector3(top_center.x + cos(angle) * jr, y, top_center.z + sin(angle) * jr))
		ring_pts.append(pts)
	var wall_base := Color(0.5, 0.53, 0.68)
	for ring: int in fracs.size() - 1:
		var low: Array[Vector3] = ring_pts[ring]
		var high: Array[Vector3] = ring_pts[ring + 1]
		var snow_mix := 0.55 if ring == fracs.size() - 2 else 0.0
		for i: int in sides:
			var j := (i + 1) % sides
			var shade := rng.randf_range(0.75, 1.1)
			var col := Color(wall_base.r * shade, wall_base.g * shade, wall_base.b * shade)
			# Frost strata: horizontal pale seams by face height, phase wobbling
			# per side so the bands read as weathered layers, not painted rings.
			var band_y := (low[i].y + high[i].y) * 0.5
			var f_band := pow(0.5 + 0.5 * sin(band_y * 0.5 + float(i) * 0.8), 3.0) * 0.35
			col = col.lerp(Color(0.78, 0.86, 1.02), f_band)
			var col_hi := col.lerp(Color(0.95, 0.97, 1.0), snow_mix)
			_ctri(st, low[i], low[j], high[j], col, col, col_hi)
			_ctri(st, low[i], high[j], high[i], col, col_hi, col_hi)
	var top_ring: Array[Vector3] = ring_pts[fracs.size() - 1]
	var cap_col := Color(0.97, 0.99, 1.05)
	var apex := top_center + Vector3.UP * 0.6
	for i: int in sides:
		var j := (i + 1) % sides
		_ctri(st, top_ring[i], top_ring[j], apex, cap_col, cap_col, cap_col)
	st.generate_normals()
	var mesa := MeshInstance3D.new()
	mesa.mesh = st.commit()
	mesa.material_override = VisualLibrary.rock_material(Color(0.5, 0.54, 0.75))
	mesa.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesa)


## Research-station outpost: a huddle of warm-lit dome tents, supply crates,
## and antenna masts on a snow-capped mesa below the switchbacks — pure
## storytelling scenery the racers overlook through the whole zigzag climb.
## Emissive only: the real OmniLight3D budget is spent on the route itself.
func _add_research_station(pos: Vector3, look_target: Vector3) -> void:
	_add_rock_mesa(Vector3(pos.x, pos.y - 0.6, pos.z), 24.0, 40.0)
	var station := Node3D.new()
	station.position = pos
	var flat := Vector3(look_target.x, pos.y, look_target.z)
	if flat.distance_squared_to(pos) > 0.01:
		station.look_at_from_position(pos, flat, Vector3.UP)
	add_child(station)
	# Snow knoll blends the camp into the mesa cap.
	var knoll := MeshInstance3D.new()
	knoll.mesh = VisualLibrary.snow_drift_mesh()
	knoll.material_override = VisualLibrary.rock_material(Color(0.6, 0.66, 0.92))
	knoll.scale = Vector3(30.0, 7.0, 30.0)
	knoll.position = Vector3(0, -5.2, 0)
	station.add_child(knoll)
	var dome_mat := StandardMaterial3D.new()
	dome_mat.albedo_color = Color(0.66, 0.26, 0.16)
	dome_mat.roughness = 0.85
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(1.0, 0.75, 0.35)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(1.0, 0.62, 0.2)
	glow_mat.emission_energy_multiplier = 2.2
	var dome_specs: Array[Dictionary] = [
		{"pos": Vector3(0, 0, 0), "r": 3.2},
		{"pos": Vector3(-5.8, 0, 2.4), "r": 2.4},
		{"pos": Vector3(4.9, 0, 3.0), "r": 2.6},
		{"pos": Vector3(-2.2, 0, -5.2), "r": 2.0},
	]
	for spec: Dictionary in dome_specs:
		var r := float(spec["r"])
		var dome := MeshInstance3D.new()
		var dome_mesh := SphereMesh.new()
		dome_mesh.is_hemisphere = true
		dome_mesh.radius = r
		dome_mesh.height = r
		dome_mesh.radial_segments = 24
		dome_mesh.rings = 12
		dome.mesh = dome_mesh
		dome.material_override = dome_mat
		dome.position = (spec["pos"] as Vector3) + Vector3.DOWN * 0.35
		station.add_child(dome)
		# Warm doorway glow facing the course.
		var door := MeshInstance3D.new()
		var door_mesh := BoxMesh.new()
		door_mesh.size = Vector3(0.8, 1.05, 0.1)
		door.mesh = door_mesh
		door.material_override = glow_mat
		door.position = (spec["pos"] as Vector3) + Vector3(0.0, 0.35, -r * 0.94)
		station.add_child(door)
	# Antenna masts with red beacon tips: classic polar-station silhouette.
	var mast_mat := TrackBuilder.prop_material(Color(0.16, 0.17, 0.24))
	var beacon_mat := StandardMaterial3D.new()
	beacon_mat.albedo_color = Color(1.0, 0.3, 0.22)
	beacon_mat.emission_enabled = true
	beacon_mat.emission = Color(1.0, 0.22, 0.14)
	beacon_mat.emission_energy_multiplier = 2.4
	for mast_spec: Dictionary in [
		{"pos": Vector3(7.6, 0, -3.4), "h": 11.0},
		{"pos": Vector3(-8.2, 0, -3.0), "h": 8.0},
	]:
		var h := float(mast_spec["h"])
		var mast_base := mast_spec["pos"] as Vector3
		var mast := MeshInstance3D.new()
		var mast_mesh := CylinderMesh.new()
		mast_mesh.top_radius = 0.06
		mast_mesh.bottom_radius = 0.14
		mast_mesh.height = h
		mast.mesh = mast_mesh
		mast.material_override = mast_mat
		mast.position = mast_base + Vector3.UP * (h * 0.5)
		station.add_child(mast)
		var arm := MeshInstance3D.new()
		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(2.2, 0.1, 0.1)
		arm.mesh = arm_mesh
		arm.material_override = mast_mat
		arm.position = mast_base + Vector3.UP * (h * 0.78)
		station.add_child(arm)
		var beacon := MeshInstance3D.new()
		var beacon_mesh := SphereMesh.new()
		beacon_mesh.radius = 0.22
		beacon_mesh.height = 0.44
		beacon_mesh.radial_segments = 8
		beacon_mesh.rings = 5
		beacon.mesh = beacon_mesh
		beacon.material_override = beacon_mat
		beacon.position = mast_base + Vector3.UP * (h + 0.2)
		station.add_child(beacon)
	# Supply crates huddled between the tents.
	var crate_mat := TrackBuilder.prop_material(Color(0.3, 0.33, 0.44))
	for crate_spec: Dictionary in [
		{"pos": Vector3(2.2, 0.5, -2.6), "s": 1.1},
		{"pos": Vector3(3.1, 0.4, -1.5), "s": 0.9},
		{"pos": Vector3(-3.4, 0.55, -2.2), "s": 1.2},
	]:
		var crate := MeshInstance3D.new()
		var crate_mesh := BoxMesh.new()
		var cs := float(crate_spec["s"])
		crate_mesh.size = Vector3(cs, cs, cs)
		crate.mesh = crate_mesh
		crate.material_override = crate_mat
		crate.position = crate_spec["pos"] as Vector3
		crate.rotation.y = rng.randf_range(0.0, TAU)
		station.add_child(crate)


## Cable-car line strung between two rock spurs east of the climb: pylon
## masts with red aviation beacons on mesas, a sagging segmented cable, and
## two gondola cabins with warm-lit windows. Silhouette storytelling only —
## far off-track, no collision.
func _add_cable_car_line(a: Vector3, b: Vector3) -> void:
	var dark := TrackBuilder.prop_material(Color(0.12, 0.13, 0.19))
	var beacon_mat := StandardMaterial3D.new()
	beacon_mat.albedo_color = Color(1.0, 0.3, 0.22)
	beacon_mat.emission_enabled = true
	beacon_mat.emission = Color(1.0, 0.22, 0.14)
	beacon_mat.emission_energy_multiplier = 2.4
	for endpoint: Vector3 in [a, b]:
		var foot_y := endpoint.y - 24.0
		_add_rock_mesa(Vector3(endpoint.x, foot_y + 1.0, endpoint.z), 5.0, 15.0)
		var mast := MeshInstance3D.new()
		var mast_mesh := CylinderMesh.new()
		mast_mesh.top_radius = 0.4
		mast_mesh.bottom_radius = 0.65
		mast_mesh.height = 26.0
		mast.mesh = mast_mesh
		mast.material_override = dark
		mast.position = Vector3(endpoint.x, foot_y + 13.0, endpoint.z)
		add_child(mast)
		var arm := MeshInstance3D.new()
		var arm_mesh := BoxMesh.new()
		arm_mesh.size = Vector3(3.4, 0.5, 0.5)
		arm.mesh = arm_mesh
		arm.material_override = dark
		arm.position = endpoint
		add_child(arm)
		var beacon := MeshInstance3D.new()
		var beacon_mesh := SphereMesh.new()
		beacon_mesh.radius = 0.3
		beacon_mesh.height = 0.6
		beacon_mesh.radial_segments = 8
		beacon_mesh.rings = 5
		beacon.mesh = beacon_mesh
		beacon.material_override = beacon_mat
		beacon.position = endpoint + Vector3.UP * 1.9
		add_child(beacon)
	# Sagging cable: chain of thin cylinders along a catenary-ish curve.
	var segments := 18
	var sag := 9.0
	var prev := a
	for i: int in range(1, segments + 1):
		var t := float(i) / float(segments)
		var pt := a.lerp(b, t) + Vector3.DOWN * (sag * 4.0 * t * (1.0 - t))
		var seg_dir := pt - prev
		var seg := MeshInstance3D.new()
		var seg_mesh := CylinderMesh.new()
		seg_mesh.top_radius = 0.22
		seg_mesh.bottom_radius = 0.22
		seg_mesh.height = seg_dir.length() + 0.3
		seg_mesh.radial_segments = 6
		seg_mesh.rings = 0
		seg.mesh = seg_mesh
		seg.material_override = dark
		var seg_basis := Basis.looking_at(seg_dir.normalized(), Vector3.UP)
		seg.transform = Transform3D(
			seg_basis * Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0)),
			(prev + pt) * 0.5)
		add_child(seg)
		prev = pt
	# Gondola cabins hanging from the line, windows warm against the twilight.
	var window_mat := StandardMaterial3D.new()
	window_mat.albedo_color = Color(1.0, 0.75, 0.35)
	window_mat.emission_enabled = true
	window_mat.emission = Color(1.0, 0.62, 0.2)
	window_mat.emission_energy_multiplier = 2.0
	for t: float in [0.35, 0.7]:
		var hang := a.lerp(b, t) + Vector3.DOWN * (sag * 4.0 * t * (1.0 - t))
		var arm2 := MeshInstance3D.new()
		var arm2_mesh := CylinderMesh.new()
		arm2_mesh.top_radius = 0.08
		arm2_mesh.bottom_radius = 0.08
		arm2_mesh.height = 1.6
		arm2.mesh = arm2_mesh
		arm2.material_override = dark
		arm2.position = hang + Vector3.DOWN * 0.8
		add_child(arm2)
		var cabin := MeshInstance3D.new()
		var cabin_mesh := BoxMesh.new()
		cabin_mesh.size = Vector3(1.5, 1.7, 2.3)
		cabin.mesh = cabin_mesh
		cabin.material_override = dark
		cabin.position = hang + Vector3.DOWN * 2.4
		add_child(cabin)
		var strip := MeshInstance3D.new()
		var strip_mesh := BoxMesh.new()
		strip_mesh.size = Vector3(1.56, 0.5, 1.7)
		strip.mesh = strip_mesh
		strip.material_override = window_mat
		strip.position = hang + Vector3.DOWN * 2.15
		add_child(strip)


## --- Aurora sky, stars, wind wisps, glow crystals ---------------------------

## Serpentine curtain meshes wearing the shared animated aurora shader.
## The shader expects UV.x along the ribbon and UV.y = 0 at the top edge;
## each ribbon picks a cached shader_variant of the shared material to vary
## intensity, band scale, curtain frequency, alpha, and scroll speed.
func _build_aurora() -> void:
	if GameConfig.is_headless():
		set_process(false)
		return
	var center := Vector3(20.0, 0.0, -520.0)
	# The course runs toward -Z, so the forward sky cone is angles with
	# sin(a) < 0 around the dome center. The first two ribbons are the heroes:
	# low, huge, and bright, arcing right across the racer's forward view; the
	# shader's core band times these intensities pushes their curtain hearts
	# well past the glow HDR threshold (1.05) so they bloom against twilight
	# (fog can't gray them: the shader runs fog_disabled).
	# The last two wrap high behind/beside for all-around coverage.
	var configs: Array[Dictionary] = [
		{"radius": 340.0, "y": 126.0, "h": 106.0, "a0": -2.7, "a1": -0.45, "wobble": 30.0,
			"intensity": 3.4, "bands": 2.6, "freq": 22.0, "alpha": 0.7, "scroll": 0.07},
		{"radius": 480.0, "y": 158.0, "h": 118.0, "a0": -2.35, "a1": -0.8, "wobble": 38.0,
			"intensity": 2.9, "bands": 3.0, "freq": 27.0, "alpha": 0.62, "scroll": 0.05},
		{"radius": 560.0, "y": 216.0, "h": 90.0, "a0": 0.7, "a1": 2.9, "wobble": 40.0,
			"intensity": 2.0, "bands": 2.8, "freq": 18.0, "alpha": 0.48, "scroll": 0.08},
		{"radius": 660.0, "y": 246.0, "h": 100.0, "a0": -1.2, "a1": 1.1, "wobble": 30.0,
			"intensity": 1.8, "bands": 3.6, "freq": 26.0, "alpha": 0.42, "scroll": 0.035},
		# Second fainter band: an ultra-dim, very high veil hanging behind the
		# hero curtains in the forward sky — the pale secondary arc real
		# displays carry above the main one. Slowest scroll of the set and the
		# lowest alpha: it drifts, it never flashes.
		{"radius": 620.0, "y": 298.0, "h": 132.0, "a0": -2.95, "a1": -0.25, "wobble": 46.0,
			"intensity": 1.15, "bands": 3.4, "freq": 19.0, "alpha": 0.3, "scroll": 0.022},
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
		# shader_variant: identical parameter sets resolve to ONE cached shared
		# material across course reloads (each duplicate() minted a fresh WebGL
		# program state on first sight — a hitch on single-threaded wasm).
		ribbon.material_override = VisualLibrary.shader_variant(VisualLibrary.aurora_material(), {
			"intensity": float(cfg["intensity"]),
			"band_scale": float(cfg["bands"]),
			"curtain_frequency": float(cfg["freq"]),
			"max_alpha": float(cfg["alpha"]),
			"scroll_speed": float(cfg["scroll"]),
		})
		ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ribbon)
		_aurora_ribbons.append(ribbon)
	_build_aurora_crown()


## Finale: six aurora streamers spiraling in to a crown directly over the
## research-station finish, so the whole sky pulls together as racers spill
## out of the corkscrew and cross the line. Brightest at the crown so the
## convergence blooms through the glow threshold.
func _build_aurora_crown() -> void:
	var crown := Vector3(-52.0, 0.0, -997.0)
	var streamers := 6
	for k: int in streamers:
		var base_angle := TAU * float(k) / float(streamers) + 0.35
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var segments := 14
		var prev_bottom := Vector3.ZERO
		var prev_top := Vector3.ZERO
		var prev_t := 0.0
		for i: int in segments + 1:
			var t := float(i) / float(segments)
			var angle := base_angle + t * 0.85
			var r := lerpf(20.0, 310.0, t * t * 0.4 + t * 0.6)
			var y := lerpf(112.0, 208.0, t) + sin(t * 9.0 + float(k) * 1.7) * 5.0
			var h := lerpf(26.0, 74.0, t)
			var bottom := crown + Vector3(cos(angle) * r, y, sin(angle) * r)
			var top := bottom + Vector3.UP * h
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
		var streamer := MeshInstance3D.new()
		streamer.mesh = st.commit()
		# All six streamers share ONE cached variant (shader_variant), where the
		# old per-streamer duplicate() minted six identical materials per load.
		streamer.material_override = VisualLibrary.shader_variant(VisualLibrary.aurora_material(), {
			"intensity": 3.2,
			"band_scale": 2.2,
			"curtain_frequency": 16.0,
			"max_alpha": 0.66,
			"scroll_speed": 0.09,
		})
		streamer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(streamer)
		_aurora_ribbons.append(streamer)


## Star dome: one MultiMesh of soft additive billboards (same recipe as the
## title screen sky), fog-immune, brighter AND denser toward the dark zenith
## (real dark-sky gradient: horizon extinction eats the faint crowd first).
## Count scales with display/quality_preset (low ~40% of high).
func _build_stars() -> void:
	if GameConfig.is_headless():
		return
	var center := Vector3(20.0, 20.0, -520.0)
	var quality := String(SettingsManager.get_setting("display", "quality_preset"))
	var count := 1150
	if quality == "medium":
		count = 800
	elif quality == "low":
		count = 460
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
	# Milky-Way band: the last ~third of the field is drawn toward a fixed
	# great circle through the dome (dir flattened against the band plane), a
	# dense dust of small dim stars — the way a real dark-sky night carries a
	# visible galactic lane, not a uniform scatter.
	var band_normal := Vector3(0.62, 0.3, 0.72).normalized()
	var band_from := count * 2 / 3
	for i: int in count:
		var azimuth := rng.randf() * TAU
		# Zenith-weighted altitude: pow-biased sampling packs the dome densely
		# overhead and thins smoothly toward the horizon band.
		var altitude := lerpf(0.08, 1.5, pow(rng.randf(), 0.58))
		var dir := Vector3(cos(azimuth) * cos(altitude), sin(altitude), sin(azimuth) * cos(altitude))
		var in_band := i >= band_from
		if in_band:
			dir = (dir - band_normal * dir.dot(band_normal) * rng.randf_range(0.82, 0.97)).normalized()
			if dir.y < 0.08:
				dir = (dir + Vector3.UP * (0.08 - dir.y) * 2.0).normalized()
		# Power-law magnitude: a dim crowd with a sparse bright minority, the
		# way a real star field reads (uniform sizes look like printed dots).
		var mag := pow(rng.randf(), 2.4)
		if in_band:
			mag *= 0.45  # band stars: dense but individually faint dust
		var s := 2.0 + mag * 6.5
		multimesh.set_instance_transform(i,
			Transform3D(Basis.from_scale(Vector3(s, s, s)), center + dir * 1150.0))
		var height_fade := clampf((dir.y * 1.2 - 0.05) / 1.1, 0.0, 1.0)
		var alpha := (0.22 + 0.72 * mag) * (0.3 + 0.7 * height_fade)
		# ~1 in 6 stars carries a warm K-class tint; the rest stay blue-white.
		var col := Color(0.85 + rng.randf() * 0.15, 0.9 + rng.randf() * 0.1, 1.0)
		if rng.randf() < 0.16:
			col = Color(1.0, 0.87, 0.72)
		multimesh.set_instance_color(i, Color(col.r, col.g, col.b, alpha))
	var stars := MultiMeshInstance3D.new()
	stars.multimesh = multimesh
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stars)
	_build_twinklers(center)


## A handful of hero stars, larger than the MultiMesh field, that visibly
## scintillate (scale + alpha breathe in _process). Real skies only twinkle
## noticeably on the brightest few stars — animating the whole dome would
## read as shimmer noise, so exactly these eight get motion.
func _build_twinklers(center: Vector3) -> void:
	for i: int in 8:
		var azimuth := rng.randf() * TAU
		var altitude := rng.randf_range(0.25, 1.4)
		var dir := Vector3(cos(azimuth) * cos(altitude), sin(altitude), sin(azimuth) * cos(altitude))
		var quad := QuadMesh.new()
		quad.size = Vector2(1.0, 1.0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.billboard_keep_scale = true
		mat.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.95)
		mat.albedo_color = Color(1.0, 0.88, 0.74, 0.85) if i % 3 == 0 else Color(0.92, 0.95, 1.0, 0.85)
		mat.disable_receive_shadows = true
		mat.disable_fog = true
		quad.material = mat
		var star := MeshInstance3D.new()
		star.mesh = quad
		var base := rng.randf_range(9.0, 14.0)
		star.scale = Vector3.ONE * base
		star.position = center + dir * 1140.0
		star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(star)
		_twinklers.append(star)
		_twinkler_mats.append(mat)
		_twinkler_base.append(base)
		_twinkler_phase.append(rng.randf() * TAU)
		_twinkler_speed.append(rng.randf_range(1.6, 3.2))


## Big soft moon low in the forward-left sky: a crisp bright disc plus two
## nested halo billboards. Sits beyond the aurora shell, fog-immune, and
## deliberately just under the glow threshold so it stays serene, with the
## additive halos carrying the atmospheric bloom feel. Placed along MOON_DIR:
## the environment key light in build_course points along -MOON_DIR, so the
## snow shading and specular response visibly come FROM this disc.
func _build_moon() -> void:
	if GameConfig.is_headless():
		return
	var center := Vector3(20.0, 20.0, -520.0)
	var pos := center + MOON_DIR * 1080.0
	# Crisp-edged disc texture: full-bright core, quick soft falloff at the rim.
	var moon_gradient := Gradient.new()
	moon_gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	moon_gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	moon_gradient.add_point(0.72, Color(1.0, 1.0, 1.0, 1.0))
	moon_gradient.add_point(0.86, Color(1.0, 1.0, 1.0, 0.45))
	var moon_tex := GradientTexture2D.new()
	moon_tex.gradient = moon_gradient
	moon_tex.fill = GradientTexture2D.FILL_RADIAL
	moon_tex.fill_from = Vector2(0.5, 0.5)
	moon_tex.fill_to = Vector2(0.5, 0.0)
	moon_tex.width = 64
	moon_tex.height = 64
	# Halos first (pushed slightly farther away so the disc sorts on top).
	var halo_specs: Array[Dictionary] = [
		{"size": 360.0, "color": Color(0.5, 0.6, 1.0, 0.1), "back": 14.0},
		{"size": 190.0, "color": Color(0.62, 0.72, 1.0, 0.24), "back": 7.0},
	]
	var away := (pos - center).normalized()
	for spec: Dictionary in halo_specs:
		var halo := MeshInstance3D.new()
		var halo_mesh := QuadMesh.new()
		var hs := float(spec["size"])
		halo_mesh.size = Vector2(hs, hs)
		var halo_mat := StandardMaterial3D.new()
		halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		halo_mat.albedo_texture = VisualLibrary.soft_radial_texture(64, 0.85)
		halo_mat.albedo_color = spec["color"] as Color
		halo_mat.disable_receive_shadows = true
		halo_mat.disable_fog = true
		halo_mesh.material = halo_mat
		halo.mesh = halo_mesh
		halo.position = pos + away * float(spec["back"])
		halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(halo)
	var disc := MeshInstance3D.new()
	var disc_mesh := QuadMesh.new()
	disc_mesh.size = Vector2(86.0, 86.0)
	var disc_mat := StandardMaterial3D.new()
	disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	disc_mat.albedo_texture = moon_tex
	disc_mat.albedo_color = Color(0.94, 0.96, 1.0)
	disc_mat.disable_receive_shadows = true
	disc_mat.disable_fog = true
	disc_mesh.material = disc_mat
	disc.mesh = disc_mesh
	disc.position = pos
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)


## Horizon realism: a warm light-pollution dome low over the research-camp
## side of the sky (the finish station and the mesa outpost both sit west /
## down-course), plus a fainter secondary blush. Real dark-sky horizons are
## never a uniform gradient — any inhabited direction carries a sodium-amber
## stain — and the warm-vs-cool split also anchors which way "camp" is.
func _build_horizon_glow() -> void:
	if GameConfig.is_headless():
		return
	var center := Vector3(20.0, 0.0, -520.0)
	var specs: Array[Dictionary] = [
		{"dir": Vector3(-0.55, 0.0, -0.83), "size": Vector2(680.0, 230.0),
			"color": Color(1.0, 0.6, 0.3, 0.085), "y": -4.0},
		{"dir": Vector3(-0.95, 0.0, -0.3), "size": Vector2(430.0, 150.0),
			"color": Color(1.0, 0.55, 0.28, 0.06), "y": -12.0},
	]
	for spec: Dictionary in specs:
		var glow := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = spec["size"] as Vector2
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.albedo_texture = VisualLibrary.soft_radial_texture(64, 0.8)
		mat.albedo_color = spec["color"] as Color
		mat.disable_receive_shadows = true
		mat.disable_fog = true
		quad.material = mat
		glow.mesh = quad
		var pos := center + (spec["dir"] as Vector3).normalized() * 1120.0
		pos.y = float(spec["y"])
		glow.position = pos
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(glow)


## Faint aurora reflection hovering just over the smooth-ice corkscrew: the
## same animated curtain shader, ground-projected as a dim strip that follows
## the banked deck (built from transform_at stations, so it hugs the spiral).
## Reads as sky light caught in polished ice without any reflection probe.
## Additive + depth_draw_never + max_alpha 0.16: it can neither occlude the
## track nor wash out the racing line.
func _add_aurora_reflections(start_arc: float, end_arc: float) -> void:
	if GameConfig.is_headless():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 8.0
	var count := maxi(int((end_arc - start_arc) / step), 2)
	var half_w := 5.5
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_t := 0.0
	for i: int in count + 1:
		var xform := main_guide.transform_at(start_arc + float(i) * step)
		var l := xform.origin - xform.basis.x * half_w + xform.basis.y * 0.06
		var r := xform.origin + xform.basis.x * half_w + xform.basis.y * 0.06
		var t := float(i) / float(count)
		if i > 0:
			# UV.x runs along the strip, UV.y across it: the shader's edge fades
			# then soften both track-side borders and both ends.
			st.set_uv(Vector2(prev_t, 0.0)); st.add_vertex(prev_l)
			st.set_uv(Vector2(t, 0.0)); st.add_vertex(l)
			st.set_uv(Vector2(t, 1.0)); st.add_vertex(r)
			st.set_uv(Vector2(prev_t, 0.0)); st.add_vertex(prev_l)
			st.set_uv(Vector2(t, 1.0)); st.add_vertex(r)
			st.set_uv(Vector2(prev_t, 1.0)); st.add_vertex(prev_r)
		prev_l = l
		prev_r = r
		prev_t = t
	var sheet := MeshInstance3D.new()
	sheet.mesh = st.commit()
	sheet.material_override = VisualLibrary.shader_variant(VisualLibrary.aurora_material(), {
		"intensity": 0.55,
		"band_scale": 2.2,
		"curtain_frequency": 13.0,
		"max_alpha": 0.16,
		"scroll_speed": 0.06,
		"core_boost": 0.2,
	})
	sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sheet)


## Moonlit specular streaks on the smooth-ice corkscrew: stretched additive
## smears aligned with the moon azimuth, laid in the local deck plane so they
## follow the banking. Static stand-ins for the anisotropic glint band a low
## moon paints across wind-polished ice — always pointing at the disc that
## also drives the key light.
func _add_moon_glints(start_arc: float, end_arc: float) -> void:
	if GameConfig.is_headless():
		return
	var band_yaw := atan2(MOON_DIR.x, MOON_DIR.z)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.7)
	mat.albedo_color = Color(0.72, 0.82, 1.0, 0.15)
	mat.disable_receive_shadows = true
	var arc := start_arc
	while arc < end_arc - 4.0:
		var xform := main_guide.transform_at(arc)
		var deck_yaw := atan2(xform.basis.z.x, xform.basis.z.z)
		var glint := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(rng.randf_range(2.0, 3.4), rng.randf_range(9.0, 15.0))
		glint.mesh = plane
		glint.material_override = mat
		glint.transform = Transform3D(
			xform.basis.rotated(xform.basis.y.normalized(), band_yaw - deck_yaw),
			xform.origin + xform.basis.x * rng.randf_range(-5.0, 5.0) + xform.basis.y * 0.07)
		glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(glint)
		arc += rng.randf_range(15.0, 24.0)


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


## Faceted crystal cluster (shared VisualLibrary mesh) wearing the shared
## sparkle shader: a slow, restrained emissive pulse plus fresnel rim so
## track-side crystals shimmer magically at twilight without joining the
## OmniLight3D budget.
func _add_glow_crystal(pos: Vector3, height: float, tint: Color) -> void:
	var crystal := MeshInstance3D.new()
	crystal.mesh = VisualLibrary.ice_crystal_mesh()
	# Deterministic phase variant from position: neighbouring crystals
	# de-synchronize instead of pulsing in lockstep across the course.
	var variant := int(absf(pos.x * 13.0 + pos.z * 7.0)) % 2
	crystal.material_override = _crystal_material(tint, variant)
	crystal.scale = Vector3(height * 0.8, height, height * 0.8)
	crystal.rotation.y = rng.randf() * TAU
	crystal.position = pos
	crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(crystal)


## Cached per (tint, variant): duplicated sparkle materials with the pickup
## pulse slowed and softened. Peak emission grazes the glow threshold, so
## only the brightest instant of the pulse blooms — magical but restrained.
func _crystal_material(tint: Color, variant: int = 0) -> ShaderMaterial:
	var key := "%s_%d" % [tint.to_html(false), variant]
	if _crystal_mats.has(key):
		return _crystal_mats[key]
	var mat := VisualLibrary.sparkle_material(tint, tint.lightened(0.4)).duplicate() as ShaderMaterial
	mat.set_shader_parameter("pulse_speed", 0.9 if variant == 0 else 1.3)
	mat.set_shader_parameter("pulse_min", 0.22)
	mat.set_shader_parameter("pulse_max", 0.72)
	mat.set_shader_parameter("rim_power", 2.6)
	mat.set_shader_parameter("roughness_value", 0.18)
	_crystal_mats[key] = mat
	return mat


## Two MultiMeshes (aurora-green and violet) of small tilted ice shards
## flanking the whole route: a faint emissive tint well under the glow
## threshold plus a rim term reads as the curtain light caught in trackside
## ice. ~48 instances for two draw calls; shadows off.
func _add_crystal_field() -> void:
	var green_transforms: Array[Transform3D] = []
	var violet_transforms: Array[Transform3D] = []
	var quality := String(SettingsManager.get_setting("display", "particle_quality"))
	var per_step := 1.0 if quality == "high" else 0.7
	var offset := 50.0
	while offset < main_guide.length - 60.0:
		for side: float in [-1.0, 1.0]:
			if rng.randf() > per_step * 0.8:
				continue
			var shard_offset := offset + rng.randf_range(-8.0, 8.0)
			var xform := main_guide.transform_at(shard_offset)
			var lateral := rng.randf_range(11.5, 24.0) * side
			var h := rng.randf_range(1.1, 2.8)
			var tilt_dir := rng.randf() * TAU
			var shard_basis := Basis(Vector3(cos(tilt_dir), 0.0, sin(tilt_dir)), rng.randf_range(-0.2, 0.2)) \
				* Basis(Vector3.UP, rng.randf() * TAU) \
				* Basis.from_scale(Vector3(h * rng.randf_range(0.5, 0.8), h, h * rng.randf_range(0.5, 0.8)))
			var pos := xform.origin + xform.basis.x * lateral + Vector3.DOWN * 0.6
			# Same branch trap as the drifts: this lateral is measured off the
			# main line, and near the shortcut the far side of it is deck.
			if not clear_of_track(pos, h * 0.4):
				continue
			_add_flank_contact_patch(pos, h * 0.24)
			if rng.randf() > 0.5:
				green_transforms.append(Transform3D(shard_basis, pos))
			else:
				violet_transforms.append(Transform3D(shard_basis, pos))
		offset += 34.0
	_add_multimesh(VisualLibrary.ice_crystal_mesh(), green_transforms,
		_field_crystal_material(Color(0.24, 0.72, 0.46)), "CrystalFieldGreen")
	_add_multimesh(VisualLibrary.ice_crystal_mesh(), violet_transforms,
		_field_crystal_material(Color(0.5, 0.36, 0.78)), "CrystalFieldViolet")


## Distant crystal spires: tall shard clusters scattered across the valley
## floor 260-430m out, glowing steadily from within (cached emissive
## materials at 0.85 energy — well under the 1.05 bloom threshold, so no
## flashing, just lit ice). Shared crystal mesh, two MultiMesh draw calls
## (green + violet); rejection sampling keeps every spire 90m+ off the
## racing line; counts scale with display/quality_preset (low ~40% of high).
func _add_crystal_spires() -> void:
	var quality := String(SettingsManager.get_setting("display", "quality_preset"))
	var count := 9
	if quality == "medium":
		count = 6
	elif quality == "low":
		count = 4
	var center := Vector3(20.0, 0.0, -520.0)
	var green_transforms: Array[Transform3D] = []
	var violet_transforms: Array[Transform3D] = []
	for i: int in count:
		var angle := TAU * float(i) / float(count) + rng.randf_range(-0.3, 0.3)
		for _attempt: int in 6:
			var dist := rng.randf_range(260.0, 430.0)
			var pos := center + Vector3(sin(angle) * dist, 0.0, cos(angle) * dist)
			if float(main_guide.nearest(pos, -1)["distance"]) < 90.0:
				angle += 0.35
				continue
			var h := rng.randf_range(26.0, 52.0)
			var spire_basis := Basis(Vector3.UP, rng.randf() * TAU) \
				* Basis.from_scale(Vector3(h * rng.randf_range(0.4, 0.55), h, h * rng.randf_range(0.4, 0.55)))
			var xform := Transform3D(spire_basis, Vector3(pos.x, -31.0, pos.z))
			if i % 2 == 0:
				green_transforms.append(xform)
			else:
				violet_transforms.append(xform)
			break
	_add_multimesh(VisualLibrary.ice_crystal_mesh(), green_transforms,
		VisualLibrary.emissive_material(Color(0.1, 0.24, 0.2), Color(0.3, 0.95, 0.6), 0.85, 0.3),
		"CrystalSpiresGreen", 1500.0)
	_add_multimesh(VisualLibrary.ice_crystal_mesh(), violet_transforms,
		VisualLibrary.emissive_material(Color(0.2, 0.15, 0.32), Color(0.66, 0.45, 1.0), 0.85, 0.3),
		"CrystalSpiresViolet", 1500.0)


## Static crystal-field material: dark glassy shard with a faint colored
## emissive lift (never blooms) and a rim so silhouettes catch the sky.
func _field_crystal_material(glow: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.3, 0.44)
	mat.roughness = 0.14
	mat.metallic = 0.08
	mat.emission_enabled = true
	mat.emission = glow
	mat.emission_energy_multiplier = 0.42
	mat.rim_enabled = true
	mat.rim = 0.55
	mat.rim_tint = 0.3
	return mat


## range_base > 0 opts the dressing into VisualLibrary.apply_dressing_range
## distance culling. Visibility range keys off the NODE origin, so the node is
## re-anchored at the transforms' centroid (instance transforms made relative):
## the fade then measures from the feature itself, not world zero.
func _add_multimesh(mesh: Mesh, transforms: Array[Transform3D], material: Material, name_hint: String, range_base: float = 0.0) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	var instance := MultiMeshInstance3D.new()
	instance.name = name_hint
	instance.multimesh = mm
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if range_base > 0.0:
		var centroid := Vector3.ZERO
		for t: Transform3D in transforms:
			centroid += t.origin
		centroid /= float(transforms.size())
		instance.position = centroid
		for i: int in transforms.size():
			mm.set_instance_transform(i, Transform3D(transforms[i].basis, transforms[i].origin - centroid))
		VisualLibrary.apply_dressing_range(instance, range_base)
	else:
		for i: int in transforms.size():
			mm.set_instance_transform(i, transforms[i])
	add_child(instance)


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
		if p.z > -290.0 or p.z < -530.0 or p.y < 70.0:
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
	if _aurora_ribbons.is_empty() and _twinklers.is_empty():
		return
	_aurora_time += delta
	for i: int in _aurora_ribbons.size():
		var ribbon := _aurora_ribbons[i]
		var phase := float(i) * 1.9
		ribbon.position.y = sin(_aurora_time * 0.22 + phase) * 7.0
		ribbon.scale.y = 1.0 + 0.1 * sin(_aurora_time * 0.15 + phase * 1.7)
	# Hero-star scintillation: two incommensurate sine taps per star give the
	# irregular flicker of real atmospheric twinkle (a single sine reads as a
	# metronome). Scale + alpha only — no allocation, two uniform updates each.
	for i: int in _twinklers.size():
		var a := _aurora_time * _twinkler_speed[i] + _twinkler_phase[i]
		var tw := 0.5 + 0.35 * sin(a) + 0.15 * sin(a * 2.63 + 1.7)
		_twinklers[i].scale = Vector3.ONE * (_twinkler_base[i] * (0.75 + 0.3 * tw))
		_twinkler_mats[i].albedo_color.a = 0.4 + 0.55 * clampf(tw, 0.0, 1.0)
