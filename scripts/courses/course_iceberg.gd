class_name CourseIceberg
extends CourseBase
## ICEBERG BAY: open ocean at sunrise. Berg-hopping, sliding platform gaps,
## two swim channels, rolling wave ramps, a tilting-slab causeway, sliding
## seals, and a risky narrow berg-chain shortcut. Animated ocean far below.

const SNOW := SurfacesDB.Surface.PACKED_SNOW
const ICE := SurfacesDB.Surface.ICE_SMOOTH
const RICE := SurfacesDB.Surface.ICE_ROUGH

const OCEAN_Y: float = -2.0

## Ocean palette. The water shader lerps deep -> shallow with fresnel toward
## the horizon plus a noise ripple from above. Screenshot review: the old
## indigo -> peach pair read as flat matte purple beside the track, so the
## water is now teal deep -> aqua shallow (cool, clearly WATER); the warm
## sunrise lives in the sky, sun and fog — not in the water albedo. Channels
## sit a step lighter than open ocean so the swim route reads.
const OCEAN_DEEP: Color = Color(0.03, 0.22, 0.28)
const OCEAN_SHALLOW: Color = Color(0.38, 0.8, 0.78)
const CHANNEL_DEEP: Color = Color(0.05, 0.28, 0.34)
const CHANNEL_SHALLOW: Color = Color(0.5, 0.84, 0.8)

## Track tints cooled toward white-blue: under the warm sunrise light the
## default snow/ice tints tone-mapped to low-contrast lilac-pink against the
## water. Cool albedo balances the warm sun so racers and fish pop.
## Screenshot review round 2: 0.82/0.9 still tone-mapped lilac under the low
## warm sun, so the snow floor is nudged brighter/whiter (blue bias kept
## subtle so the sunrise mood survives).
const TRACK_SNOW_TINT: Color = Color(0.92, 0.96, 1.0)
const TRACK_ICE_TINT: Color = Color(0.4, 0.72, 1.0)
const TRACK_RICE_TINT: Color = Color(0.66, 0.82, 0.97)
## Azure ice for the big horizon bergs — must read as ICE, not rock, even
## under the warm sun.
const HORIZON_BERG_TINT: Color = Color(0.62, 0.8, 0.96)
## Yaw of the sunrise sun (must match the build_environment sun_yaw_deg).
## Horizontal direction TO the sun is (sin, 0, cos) of this yaw; the glint
## corridor, hero-berg backlight placement and warm rim tints all key off it.
const SUN_YAW_DEG: float = 40.0
## Elevation of the sunrise sun above the horizon (magnitude of the
## build_environment sun_angle_deg). _sun_dir_3d() combines it with the yaw
## into the full toward-sun vector the water shader's glint uniform expects.
const SUN_PITCH_DEG: float = 13.0
## Warm rim color for sun-facing ice edges (hero bergs) and the glint band.
const SUN_WARM_RIM: Color = Color(1.0, 0.8, 0.56)
## Track floor runs whose lowest vertex sits under this height skim the sea
## (swim approaches, wave ramps, seal flat, finale): their ice gets a wet
## meltwater sheen (lower roughness). The high berg-hop arc and the shortcut
## stay dry frosted ice.
const WET_SHEEN_Y: float = 7.0
## Airtime of one breaching-whale leap (see _update_breach).
const BREACH_DURATION: float = 3.4

var _bobbers: Array[Dictionary] = []  # {node, base_y, phase, amp, speed}
var _bob_time: float = 0.0
var _buoy_lamps: Array[Dictionary] = []  # {mat, phase, period, lit} blinking tops
var _spinners: Array[Dictionary] = []  # {node, speed} slow yaw (seabird flocks)
var _drift_foam: MeshInstance3D = null  # near-track foam patches, drift in _process
var _drift_origin: Vector3 = Vector3.ZERO
var _wet_band_mat: StandardMaterial3D = null  # shared glossy spray-wet band
var _hero_centers: Array[Vector3] = []  # sculpted hero-berg spots (seabird anchors)
var _water_lines: Array[Array] = []  # swim channel point arrays, kept for edge foam
var _foam_st: SurfaceTool = null  # batches every foam quad into one mesh/draw call
var _drift_layers: Array[Dictionary] = []  # {node, dir, amp, speed, phase} pack-ice parallax
var _breach_whale: Node3D = null  # live breaching whale (never built under reduced motion)
var _breach_splash: MeshInstance3D = null
var _breach_anchor: Vector3 = Vector3.ZERO
var _breach_wait: float = 0.0
var _breach_t: float = -1.0  # <0 = submerged, waiting out the long timer
## Prefix arclength per guide sample point. PathGuide.nearest() reports offsets
## as index * SAMPLE_SPACING while transform_at()/point_at() consume true
## arclength. With the current PathGuide (uniform resampling in _init) the two
## spaces coincide and this table is the identity; it is kept because an
## earlier PathGuide used Godot's adaptively-tessellated baked points directly
## (avg ~1.4m spacing -> nearest() offsets outran arclength by ~45%, teleporting
## respawns forward and displacing every offset-placed prop). The table keeps
## hint space (racer progress) and placement space (geometry) correct under
## BOTH behaviors. See _arc_near()/_offset_near().
var _arc: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	course_id = "iceberg"


static func p(x: float, y: float, z: float, extra: Dictionary = {}) -> Dictionary:
	var d := {"pos": Vector3(x, y, z)}
	d.merge(extra)
	return d


func build_course() -> void:
	var pts: Array = [
		# 1. Start berg: long straight for the grid, dipping off the plateau.
		# The dip span is a smooth-ice patch: an early slide reward on a
		# straight descent, well before the berg arc asks for steering.
		p(0, 12, 35, {"width": 18.0}),
		p(0, 12, -30, {"width": 18.0, "surface": ICE}),
		p(2, 10.5, -100, {"width": 20.0}),
		# 2. Berg-hop: wide right-swinging arc of connected bergs riding a
		# gentle ocean swell — each berg crests +2-3m then dips, so the arc
		# rolls like the sea it floats on. Widths breathe 22 -> 14 -> 20 -> 12.
		# wall_l stays ON at -240/-540: the branch corridor is well clear of the
		# main edge by those spots, and the wall catches racers whose guide yaw
		# (sampled far ahead by PathGuide's index-space offsets) cuts the arc.
		p(14, 13, -170, {"width": 22.0, "wall_l": false}),
		p(34, 9.5, -240, {"width": 16.0}),
		p(52, 12.5, -310, {"width": 16.0}),
		p(56, 9, -380, {"width": 20.0}),
		# Width 16 (was 13): the 20->13 pinch mid-arc dumped outer-line AI off
		# the right edge into water (sim DNF loop). Crest softened 11.5->10.5.
		p(44, 10.5, -440, {"width": 16.0}),
		p(24, 8, -490, {"width": 18.0, "wall_l": false}),
		p(6, 10, -540, {"width": 18.0}),
		p(0, 8.8, -590, {"width": 16.0}),
		# 3. Moving-platform crossing: floorless span bridged by sliding slabs.
		# The swell rise at -590 doubles as the launch hump into the jump.
		p(0, 8.4, -620, {"width": 14.0}),
		p(0, 8, -640, {"width": 12.0, "gap": true}),
		p(0, 8, -672, {"width": 14.0}),
		# 4. Approach and the big swim channel (80m of open water): one last
		# wave rise at -770, then down to the ice edge at water level.
		p(-6, 7.5, -720, {"width": 16.0}),
		# Iced downhill straight into the swim channel: slide in at speed
		# (full-width water below the edge — no steering precision needed).
		p(-10, 7.8, -770, {"width": 16.0, "surface": ICE}),
		p(-10, 6.3, -810, {"width": 14.0}),
		p(-8, 6.0, -848, {"width": 14.0, "gap": true}),  # ice edge, 1m over water
		p(-4, 5.0, -878, {"width": 14.0, "gap": true}),  # guide at water surface
		p(0, 5.0, -900, {"width": 14.0, "gap": true}),
		p(2, 5.0, -925, {"width": 14.0, "gap": true}),
		p(3, 4.2, -932, {"width": 18.0, "surface": ICE, "wall_l": false, "wall_r": false}),  # submerged exit ramp
		p(4, 6.2, -965, {"width": 18.0, "surface": ICE}),
		# 5. Wave ramps: three rolling hills on smooth ice, amplified so each
		# crest launches (+3m rise, short 11-12 degree back faces).
		p(2, 6.2, -1000, {"width": 16.0, "surface": ICE}),
		p(0, 9.2, -1028, {"width": 16.0, "surface": ICE}),
		p(-2, 6.2, -1042, {"width": 16.0, "surface": ICE}),
		p(-4, 9.2, -1070, {"width": 16.0, "surface": ICE}),
		p(-6, 6.2, -1084, {"width": 16.0, "surface": ICE}),
		p(-8, 9.2, -1112, {"width": 16.0, "surface": ICE}),
		p(-8, 6.2, -1126, {"width": 16.0, "surface": RICE}),
		# 6. Tilting-slab causeway: floorless span bridged by rocking slabs,
		# with a small wave rise before the jump edge.
		p(-8, 6.6, -1160, {"width": 14.0}),
		p(-8, 6.0, -1185, {"width": 12.0, "gap": true}),
		p(-8, 6.0, -1220, {"width": 14.0}),
		# 7. Seal flat: wide smooth ice with sliding seals, settling swell.
		p(-6, 6.0, -1250, {"width": 20.0, "surface": ICE}),
		p(-2, 5.7, -1290, {"width": 20.0, "surface": ICE}),
		p(0, 5.5, -1330, {"width": 20.0, "surface": ICE}),
		p(2, 5.4, -1360, {"width": 20.0, "surface": ICE}),
		# 8. Finale: a last swell hump into the short second swim, then the
		# finish straight.
		p(2, 5.8, -1390, {"width": 16.0}),
		p(2, 5.0, -1410, {"width": 13.0, "wall_l": false, "wall_r": false, "gap": true}),
		p(2, 4.0, -1424, {"width": 13.0, "gap": true}),
		p(2, 4.0, -1442, {"width": 13.0, "gap": true}),
		p(2, 3.2, -1456, {"width": 18.0, "surface": ICE, "wall_l": false, "wall_r": false}),  # submerged exit ramp
		p(2, 5.0, -1490, {"width": 18.0, "surface": ICE}),
		p(0, 5.4, -1530, {"width": 18.0}),
		p(0, 5.0, -1660, {"width": 18.0}),
	]
	setup_main(pts)
	_build_arc_table()
	# Long runout past the banner so finished racers stop before the berg edge.
	finish_offset = main_guide.length - 80.0

	# Risky berg-chain shortcut: cuts the wide berg-hop arc on the inside.
	# Narrow smooth ice, no walls — fall off and you swim with the fishes.
	var branch_pts: Array = [
		p(16, 12.0, -190, {"width": 10.0, "surface": ICE, "wall_l": false, "wall_r": false}),
		p(10, 10.2, -250, {"width": 7.0, "surface": ICE, "wall_l": false, "wall_r": false}),
		p(6, 11.2, -320, {"width": 7.0, "surface": ICE, "wall_l": false, "wall_r": false}),
		p(8, 9.4, -390, {"width": 7.0, "surface": ICE, "wall_l": false, "wall_r": false}),
		p(12, 10.4, -450, {"width": 8.0, "surface": ICE, "wall_l": false, "wall_r": false}),
		p(18, 8.6, -505, {"width": 10.0, "surface": ICE, "wall_l": false, "wall_r": false}),
	]
	var shortcut := add_branch(branch_pts, 0.6, "berg_chain")

	finalize()

	# Rebuild checkpoints in the SAME offset space racer progress uses (index
	# space from PathGuide.nearest). Identical to the base behavior while
	# PathGuide samples uniformly, but immune to the earlier non-uniform
	# sampling, under which racers' inflated index-space progress crossed
	# arclength-placed checkpoints ~45% early and a faller respawned hundreds
	# of meters AHEAD of where it fell (verified in race_sim: racers skipped
	# the whole swim channel). Offsets are index space; transforms geometry.
	checkpoint_offsets.clear()
	checkpoint_transforms.clear()
	var finish_idx_offset := _index_offset_of_arc(finish_offset)
	var cp_offset := 40.0
	while cp_offset < finish_idx_offset - 60.0:
		var cp_xform := main_guide.transform_at(_arc_of_index_offset(cp_offset))
		checkpoint_offsets.append(cp_offset)
		checkpoint_transforms.append(Transform3D(cp_xform.basis, cp_xform.origin + Vector3.UP * 0.5))
		cp_offset += CHECKPOINT_INTERVAL

	# --- Swim channels (water is additional geometry under the gap spans) ---
	var water1_pts: Array = [
		p(-8, 5.0, -842, {"width": 15.0}),
		p(-4, 5.0, -878),
		p(0, 5.0, -900),
		p(2, 5.0, -925),
		p(3, 5.0, -946),
	]
	var water1 := TrackBuilder.build_water(water1_pts, "SwimChannel")
	add_child(water1)
	_upgrade_water_surface(water1)
	_water_lines.append(water1_pts)
	var water2_pts: Array = [
		p(2, 4.0, -1412, {"width": 15.0}),
		p(2, 4.0, -1435),
		p(2, 4.0, -1470),
	]
	var water2 := TrackBuilder.build_water(water2_pts, "SwimFinale")
	add_child(water2)
	_upgrade_water_surface(water2)
	_water_lines.append(water2_pts)

	# --- Moving platform crossing (section 3) -------------------------------
	add_hint(_offset_near(Vector3(0, 8, -640)) - 2.0, "jump")
	var plat_periods: Array[float] = [4.2, 5.2, 6.0]
	var plat_phases: Array[float] = [0.0, 2.1, 4.2]
	for i: int in 3:
		var plat := HazardPlatform.new()
		# First slab is static so the crossing is always survivable regardless
		# of arrival timing; the moving pair behind it stays the skill element.
		var sweep := 0.0 if i == 0 else 2.2
		plat.configure(Vector3(13.0, 0.8, 11.5), Vector3.RIGHT, sweep, plat_periods[i], 0.0, plat_phases[i],
			{"heave": 0.22, "heave_freq": 0.6, "yaw_deg": 5.0, "yaw_freq": 0.4, "variance": 0.1, "seed": 70 + i})
		plat.position = Vector3(0.0, 7.6, -643.0 - 10.0 * float(i))
		add_child(plat)
	# 70m upstream so the boost expires well before the platform jump — at
	# -16m it launched full-speed racers onto a bad platform phase, and a
	# respawned racer re-hit the pad on the same cycle (resonant stuck loop).
	TrackBuilder.add_boost_pad(self, main_guide, _arc_near(Vector3(0, 8, -640)) - 70.0)

	# --- Tilting-slab causeway (section 6) ----------------------------------
	add_hint(_offset_near(Vector3(-8, 6, -1185)) - 2.0, "jump")
	var slab_phases: Array[float] = [0.0, 0.4, 0.8, 1.2]
	for i: int in 4:
		var slab := HazardPlatform.new()
		slab.configure(Vector3(11.0, 0.8, 9.5), Vector3.RIGHT, 0.0, 4.0, 13.0, slab_phases[i],
			{"heave": 0.22, "heave_freq": 0.55, "yaw_deg": 5.0, "yaw_freq": 0.45, "variance": 0.1, "seed": 80 + i})
		slab.position = Vector3(-8.0, 5.6, -1188.0 - 9.0 * float(i))
		add_child(slab)

	# --- Sliding seals (section 7) ------------------------------------------
	var seal_data: Array = [
		{"pos": Vector3(-4, 5.9, -1270), "sweep": 8.0, "speed": 3.6, "hint": "danger_left"},
		{"pos": Vector3(-1.5, 5.7, -1296), "sweep": 9.0, "speed": 4.4, "hint": "danger_right"},
		{"pos": Vector3(0, 5.5, -1322), "sweep": 7.0, "speed": 5.0, "hint": "danger_left"},
	]
	for data: Dictionary in seal_data:
		var seal := HazardSeal.new()
		# configure() consumes arclength (point_at); hints consume index space.
		seal.configure(main_guide, _arc_near(data["pos"]), float(data["sweep"]), float(data["speed"]))
		add_child(seal)
		var seal_hint_offset := _offset_near(data["pos"])
		add_hint(seal_hint_offset - 35.0, String(data["hint"]), seal_hint_offset + 8.0)

	# --- Wave ramp crest hops + slide fun -----------------------------------
	for crest: Vector3 in [Vector3(0, 9.2, -1028), Vector3(-4, 9.2, -1070), Vector3(-8, 9.2, -1112)]:
		add_hint(_offset_near(crest) - 2.0, "jump")

	# Keep AI biased to the inside-right through the berg arc: the left edge
	# borders the shortcut void and the far-ahead guide yaw tempts a left cut.
	add_hint(_offset_near(Vector3(34, 9.5, -240)) - 20.0, "danger_left",
		_offset_near(Vector3(52, 12.5, -310)) + 10.0)
	add_hint(_offset_near(Vector3(56, 9, -380)), "danger_left",
		_offset_near(Vector3(24, 8, -490)))

	# Shortcut is flat smooth ice: sliding it hard is the whole point. Branch
	# hints are matched against MAPPED main-line progress, so use entry..exit.
	var branch_entry := float(branches[0]["entry"])
	var branch_exit := float(branches[0]["exit"])
	add_hint(branch_entry + 10.0, "slide", branch_exit - 10.0, 0)

	# Boost pads after both swim exits to relaunch momentum.
	TrackBuilder.add_boost_pad(self, main_guide, _arc_near(Vector3(4, 6.2, -965)) + 6.0)
	TrackBuilder.add_boost_pad(self, main_guide, _arc_near(Vector3(2, 5.0, -1490)) + 6.0)

	# More acceleration pads. Playtest: pads on corner exits and narrow
	# no-wall spans boosted AI straight off edges into the water (DNF loop),
	# so every pad below sits on a straight pointing down-track, centered,
	# and >=60m upstream of the platform crossing, the causeway, the swim
	# edges, and the berg-arc pinch points:
	# - start-dip exit straight (boost expires well before the arc's
	#   open-left span at -170),
	# - the centered mid-straight BEFORE the berg-arc apex at -380 (was the
	#   corner exit at lateral +3.0, which held boosted AI on the outer-right
	#   line into the -440 pinch — the exact edge the old sim DNF loop used),
	# - the berg-chain survivor reward, moved OFF the narrow no-wall shortcut
	#   onto the walled main straight just past its merge (94m before the
	#   platform-crossing jump edge),
	# - the seal-flat straight just past the last seal (was the swell hump
	#   only ~48m before the finale swim edge; now 68m clear).
	TrackBuilder.add_boost_pad(self, main_guide, _arc_near(Vector3(2, 10.5, -100)) + 4.0)
	TrackBuilder.add_boost_pad(self, main_guide, _arc_near(Vector3(56, 9, -380)) - 40.0)
	TrackBuilder.add_boost_pad(self, main_guide, _arc_near(Vector3(6, 10, -540)) + 6.0)
	TrackBuilder.add_boost_pad(self, main_guide, _arc_near(Vector3(0, 5.5, -1330)) + 12.0)
	# Slide hints for the new smooth-ice patches (hint offsets are index
	# space): the start dip and the downhill run into the big swim channel.
	add_hint(_offset_near(Vector3(0, 12, -30)) + 4.0, "slide", _offset_near(Vector3(2, 10.5, -100)))
	add_hint(_offset_near(Vector3(-10, 7.8, -770)) - 5.0, "slide", _offset_near(Vector3(-10, 6.3, -810)))

	# --- Pickups (placement APIs consume arclength offsets) -----------------
	add_item_row(115.0)
	add_item_row(_arc_near(Vector3(0, 8.6, -600)))
	add_item_row(_arc_near(Vector3(2, 6.2, -1000)) + 6.0)
	add_item_row(_arc_near(Vector3(-6, 6.0, -1250)))
	add_item_row(_arc_near(Vector3(0, 5.4, -1530)))
	add_snowball_row(150.0)
	add_snowball_row(_arc_near(Vector3(0, 8.6, -600)) - 25.0)
	add_snowball_row(_arc_near(Vector3(-6, 6.0, -1250)) - 30.0)

	add_fish_line(70.0, 8, 5.0, 0.0)
	add_fish_line(_arc_near(Vector3(14, 13, -170)), 8, 5.0, -3.0)
	add_fish_line(25.0, 10, 6.0, 0.0, 0.0, shortcut)  # shortcut reward
	add_fish_line(_arc_near(Vector3(52, 12.5, -310)), 8, 5.0, 3.0)
	add_fish_line(_arc_near(Vector3(0, 8, -655)), 6, 5.0, 0.0)  # across the platforms
	add_fish_line(_arc_near(Vector3(0, 5, -900)) - 25.0, 10, 6.0, 0.0)  # in the swim channel
	add_fish_line(_arc_near(Vector3(0, 9.2, -1028)) - 12.0, 8, 4.0, 0.0, 1.5)  # crest arc
	add_fish_line(_arc_near(Vector3(0, 5.5, -1330)) - 30.0, 10, 5.5, -4.0)
	add_fish_line(_arc_near(Vector3(2, 4.0, -1435)) - 10.0, 6, 5.0, 0.0)  # finale swim
	add_fish_line(_arc_near(Vector3(0, 5.2, -1560)) - 20.0, 8, 5.0, 0.0)

	_decorate()
	# Sunrise over open water: big low sun disc, peach-to-indigo gradient,
	# warm sea haze hugging the water, pink cloud puffs, azure berg clusters
	# on the horizon. NOTE: base distant_bergs is deliberately OFF — its ring
	# is centered on the course centroid, and on this ~1700m ribbon the ring's
	# along-axis points landed right beside the track as giant flat purple
	# pyramids (screenshot defect). _add_horizon_bergs() replaces it with
	# guide-relative clusters guaranteed far off the racing line.
	build_environment({
		"sky_top": Color(0.12, 0.2, 0.48),
		"sky_horizon": Color(1.0, 0.6, 0.42),
		# Ground hemisphere feeds sky ambient: deep sea teal, not the old
		# purple, which tinted the whole track lilac from below.
		"ground_color": Color(0.12, 0.24, 0.34),
		"sun_angle_deg": -13.0,
		"sun_yaw_deg": SUN_YAW_DEG,
		"sun_color": Color(1.0, 0.82, 0.62),
		"sun_energy": 1.12,
		"sun_angle_max": 30.0,
		"sun_curve": 0.14,
		"sky_energy": 1.0,
		"exposure": 0.93,
		"fog_color": Color(0.98, 0.68, 0.5),
		"fog_density": 0.0018,
		"fog_height": 1.5,
		"fog_height_density": 0.035,
		"glow_threshold": 1.4,
		"snow": false,
		"clouds": true,
		"cloud_color": Color(1.0, 0.76, 0.62, 0.7),
	})
	_add_horizon_bergs()
	# The ocean IS the ground plane, in two layers: a far 4000m sheet with a
	# long slow swell for the horizon, and a course-aligned finely subdivided
	# sheet so vertex waves + their sun glints actually resolve near the track
	# (the 48x48 far grid has ~83m cells — any readable wavelength aliases to
	# flat there, which is why the ocean looked matte). Far sheet sits 1.6m
	# lower so the two displaced surfaces never intersect. Flat color fallback
	# keeps headless sims cheap.
	if GameConfig.is_headless():
		add_ground_plane(OCEAN_Y, Color(0.1, 0.3, 0.45))
	else:
		# The far sheet gets the true sunrise sun vector so its specular glint
		# lane runs INTO the low sun, agreeing with the sun disc, the batched
		# glint-quad corridor and the near detail sheet (cache-safe duplicate;
		# the shared material's default sun points elsewhere).
		var far_mat := VisualLibrary.water_material(
			OCEAN_DEEP, OCEAN_SHALLOW, 1.0, 0.014).duplicate() as ShaderMaterial
		far_mat.set_shader_parameter("sun_direction", _sun_dir_3d())
		far_mat.set_shader_parameter("sun_glint_strength", 1.25)
		add_ground_plane(OCEAN_Y - 1.6, Color(0.1, 0.3, 0.45), 4000.0, far_mat, true)
		_add_ocean_detail()


## Index-space offset (comparable to racer progress and hint offsets).
func _offset_near(point: Vector3) -> float:
	return float(main_guide.nearest(point, -1)["offset"])


## True arclength offset (consumable by transform_at/point_at placement APIs).
func _arc_near(point: Vector3) -> float:
	return _arc_of_index_offset(float(main_guide.nearest(point, -1)["offset"]))


func _build_arc_table() -> void:
	var pts := main_guide.points
	_arc.resize(pts.size())
	var total := 0.0
	_arc[0] = 0.0
	for i: int in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
		_arc[i] = total


func _arc_of_index_offset(index_offset: float) -> float:
	var i := clampi(int(index_offset / PathGuide.SAMPLE_SPACING), 0, _arc.size() - 1)
	return _arc[i]


func _index_offset_of_arc(arc_offset: float) -> float:
	for i: int in _arc.size():
		if _arc[i] >= arc_offset:
			return float(i) * PathGuide.SAMPLE_SPACING
	return float(_arc.size() - 1) * PathGuide.SAMPLE_SPACING


func _process(delta: float) -> void:
	if _bobbers.is_empty() and _spinners.is_empty() and _buoy_lamps.is_empty() \
			and _drift_foam == null and _drift_layers.is_empty() and _breach_whale == null:
		return
	_bob_time += delta
	for b: Dictionary in _bobbers:
		var node := b["node"] as Node3D
		node.position.y = float(b["base_y"]) + sin(_bob_time * float(b["speed"]) + float(b["phase"])) * float(b["amp"])
	# Spinners with a "wobble" key breathe their rate sinusoidally (seabird
	# glide variation); plain spinners (radar sweeps) turn at constant speed.
	for s: Dictionary in _spinners:
		var rate := float(s["speed"])
		var wobble := float(s.get("wobble", 0.0))
		if wobble > 0.0:
			rate *= 1.0 + sin(_bob_time * float(s.get("wobble_freq", 0.3))
				+ float(s.get("wobble_phase", 0.0))) * wobble
		(s["node"] as Node3D).rotation.y += rate * delta
	# Buoy lamps blink like real navigation lights: hard on/off on a per-buoy
	# period. Material writes only on state flips (cheap; 8 mats, ~1 flip/s).
	for l: Dictionary in _buoy_lamps:
		var lit := fmod(_bob_time + float(l["phase"]), float(l["period"])) < 0.5
		if lit != bool(l["lit"]):
			l["lit"] = lit
			(l["mat"] as StandardMaterial3D).emission_energy_multiplier = 3.4 if lit else 0.3
	# The whole near-track foam-patch sheet drifts slowly relative to the swell
	# so surface water reads as moving even between wave crests.
	if _drift_foam != null:
		_drift_foam.position = _drift_origin + Vector3(
			sin(_bob_time * 0.045) * 3.5, 0.0, cos(_bob_time * 0.06) * 2.5)
	# Pack-ice parallax: each layer's root slides on its own slow sine — the
	# near band faster and farther than the far band — so the plates visibly
	# shear against each other and the bergs. Two node writes per frame.
	for layer: Dictionary in _drift_layers:
		var node := layer["node"] as Node3D
		var sway := sin(_bob_time * float(layer["speed"]) + float(layer["phase"]))
		node.position = (layer["dir"] as Vector3) * (sway * float(layer["amp"])) \
			+ Vector3.UP * (sin(_bob_time * 0.5 + float(layer["phase"])) * 0.06)
	if _breach_whale != null:
		_update_breach(delta)


## --- Scenery ----------------------------------------------------------------

func _decorate() -> void:
	var headless := GameConfig.is_headless()
	if not headless:
		_cool_track_materials()
		_foam_st = SurfaceTool.new()
		_foam_st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Course-side flags alternating warm sunrise colors.
	var offset := 60.0
	var side := 1.0
	while offset < main_guide.length - 60.0:
		var xform := main_guide.transform_at(offset)
		var lateral := (11.0 + rng.randf_range(0.0, 3.0)) * side
		TrackBuilder.add_flag(self, xform.origin + xform.basis.x * lateral,
			Color(0.95, 0.5, 0.2) if side > 0 else Color(0.96, 0.94, 0.9))
		side = -side
		offset += 120.0

	# Spectator penguins on the start and finish bergs.
	for i: int in 10:
		var near_start := main_guide.transform_at(rng.randf_range(8.0, 85.0))
		var lateral2 := (11.0 + rng.randf_range(0.0, 4.0)) * (1.0 if i % 2 == 0 else -1.0)
		TrackBuilder.add_spectator(self, near_start.origin + near_start.basis.x * lateral2, near_start.origin, rng)
	for i: int in 8:
		var near_finish := main_guide.transform_at(finish_offset - rng.randf_range(5.0, 65.0))
		var lateral3 := (11.0 + rng.randf_range(0.0, 4.0)) * (1.0 if i % 2 == 0 else -1.0)
		TrackBuilder.add_spectator(self, near_finish.origin + near_finish.basis.x * lateral3, near_finish.origin, rng)

	# Berg texture: rocks and crystals just off the racing surface.
	for i: int in 16:
		var o := rng.randf_range(120.0, main_guide.length - 80.0)
		var xf := main_guide.transform_at(o)
		var lat := rng.randf_range(12.0, 24.0) * (1.0 if rng.randf() > 0.5 else -1.0)
		if rng.randf() > 0.45:
			TrackBuilder.add_rock(self, xf.origin + xf.basis.x * lat + Vector3.DOWN * 1.0, rng.randf_range(0.8, 2.0), rng)
		else:
			TrackBuilder.add_ice_crystal(self, xf.origin + xf.basis.x * lat + Vector3.DOWN * 0.8, rng.randf_range(2.0, 5.5))

	# Crystals flanking both floorless crossings as a visual warning.
	for edge_z: float in [-640.0, -672.0, -1185.0, -1220.0]:
		var probe := Vector3(0.0 if edge_z > -1000.0 else -8.0, 8.0 if edge_z > -1000.0 else 6.0, edge_z)
		var exf := main_guide.transform_at(_arc_near(probe))
		for s: float in [-1.0, 1.0]:
			TrackBuilder.add_ice_crystal(self, exf.origin + exf.basis.x * (8.5 * s) + Vector3.DOWN * 0.5,
				rng.randf_range(2.5, 4.5), Color(1.0, 0.75, 0.45))

	# Navigation buoys bobbing on the open water beside the course: red to
	# port, green to starboard, emissive tops that catch the bloom pass.
	for i: int in 8:
		var o2 := 90.0 + float(i) * (main_guide.length - 200.0) / 8.0
		var xf2 := main_guide.transform_at(o2)
		var lat2 := rng.randf_range(26.0, 42.0) * (1.0 if i % 2 == 0 else -1.0)
		var bpos := Vector3(xf2.origin.x + xf2.basis.x.x * lat2, OCEAN_Y + 0.6, xf2.origin.z + xf2.basis.x.z * lat2)
		_add_buoy(bpos, i % 2 == 0)
		if not headless:
			for k: int in 3:
				var bang := TAU * float(k) / 3.0 + rng.randf()
				_foam_quad(Vector3(bpos.x + cos(bang) * 1.3, OCEAN_Y + 0.68, bpos.z + sin(bang) * 1.3),
					rng.randf_range(1.0, 1.6))

	# Distant whale silhouettes, slowly rising and sinking.
	for i: int in 3:
		var o3 := [420.0, 900.0, 1350.0][i] as float
		var xf3 := main_guide.transform_at(minf(o3, main_guide.length - 40.0))
		var lat3 := rng.randf_range(150.0, 240.0) * (1.0 if i % 2 == 0 else -1.0)
		_add_whale(xf3.origin + xf3.basis.x * lat3, rng.randf() * TAU)

	# Snow-covered research boats anchored mid-distance in the bay — near
	# enough that the bow/bridge/mast silhouette and warm windows resolve.
	for i: int in 2:
		var o4 := [600.0, 1450.0][i] as float
		var xf4 := main_guide.transform_at(minf(o4, main_guide.length - 40.0))
		var lat4 := rng.randf_range(150.0, 210.0) * (-1.0 if i % 2 == 0 else 1.0)
		_add_boat(xf4.origin + xf4.basis.x * lat4, rng.randf() * TAU)

	# Drifting bergs scattered across the whole bay: faceted low-poly
	# silhouettes riding the swell, each with a foam collar at the waterline.
	# 8 distinct seeded meshes reused across instances (cached in VisualLibrary).
	# Realism pass: every berg lists a few degrees off vertical (real bergs
	# never float upright), bergs on the sun side of the course swap to a
	# warm-rim ice variant so their edges catch the sunrise backlight, and
	# near-track bergs gain a wave-cut waterline erosion notch plus a
	# meltwater blue-ice vein band. The vein is a thin, yaw-offset, squashed
	# copy of the SAME seeded silhouette: the facet mismatch lets deep-blue
	# strata poke through as irregular horizontal streaks. (Baking veins as
	# vertex-color bands was considered, but the ice shader ignores COLOR —
	# the band-copy trick gets the look from cached meshes at zero bake cost.)
	var berg_mat := VisualLibrary.ice_material(Color(0.82, 0.91, 1.0), 0.55)
	var berg_warm_mat: ShaderMaterial = null if headless \
		else _warm_rim_ice(Color(0.82, 0.91, 1.0), 0.55, 0.5, 2.4)
	var drift_notch_mat := VisualLibrary.rock_material(Color(0.16, 0.3, 0.4))
	var vein_mat := VisualLibrary.ice_material(Color(0.36, 0.66, 0.92), 0.95)
	var sun_side_h := _sun_dir_h()
	for i: int in 24:
		var o5 := rng.randf_range(0.0, main_guide.length)
		var xf5 := main_guide.transform_at(o5)
		var lat5 := rng.randf_range(55.0, 320.0) * (1.0 if rng.randf() > 0.5 else -1.0)
		var bpos5 := xf5.origin + xf5.basis.x * lat5
		var berg := MeshInstance3D.new()
		var berg_seed := rng.randi_range(0, 7)
		berg.mesh = VisualLibrary.berg_mesh(berg_seed)
		var sun_facing := sun_side_h.dot(xf5.basis.x * signf(lat5)) > 0.0
		berg.material_override = berg_warm_mat if (sun_facing and berg_warm_mat != null) else berg_mat
		# Decorative silhouette off the racing line: under the -13 deg sun its
		# cast shadow stretches into a huge foreground blob, so shadows are off.
		berg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var s := rng.randf_range(4.0, 11.0)
		var bsx := s * rng.randf_range(0.9, 1.4)
		var bsy := s * rng.randf_range(0.45, 0.8)
		berg.scale = Vector3(bsx, bsy, s)
		var brot := Vector3(rng.randf_range(-0.07, 0.07), rng.randf() * TAU, rng.randf_range(-0.07, 0.07))
		berg.position = Vector3(bpos5.x, OCEAN_Y - s * 0.08, bpos5.z)
		berg.rotation = brot
		add_child(berg)
		if i % 3 == 0:
			_bobbers.append({"node": berg, "base_y": berg.position.y, "phase": rng.randf() * TAU, "amp": 0.12, "speed": 0.5})
		if not headless and absf(lat5) < 170.0:
			# Near-track detail only (where it resolves at race distance).
			_add_waterline_notch(Vector3(bpos5.x, 0.0, bpos5.z), berg_seed, brot,
				bsx, s, drift_notch_mat, clampf(s * 0.09, 0.4, 1.1))
			var vein := MeshInstance3D.new()
			vein.mesh = VisualLibrary.berg_mesh(berg_seed)
			vein.material_override = vein_mat
			vein.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			vein.scale = Vector3(bsx * 0.86, clampf(s * 0.045, 0.2, 0.5), s * 0.86)
			vein.position = Vector3(bpos5.x,
				OCEAN_Y - s * 0.08 + bsy * rng.randf_range(0.55, 0.85), bpos5.z)
			vein.rotation = brot + Vector3(0.0, 1.1, 0.0)
			add_child(vein)
		if not headless:
			for k: int in 5:
				var ang := TAU * (float(k) + rng.randf() * 0.7) / 5.0
				# Berg base radius in world = mesh base (0.7-1.25) * x-scale
				# (0.9-1.4)s; keep the collar at/just outside that so blobs
				# poke out from under every silhouette instead of hiding inside.
				# Foam rides at OCEAN_Y + 0.68, above the 0.55 swell crests.
				var ring_r := s * rng.randf_range(1.1, 1.45)
				_foam_quad(Vector3(bpos5.x + cos(ang) * ring_r, OCEAN_Y + 0.68, bpos5.z + sin(ang) * ring_r),
					rng.randf_range(0.25, 0.5) * s)

	# Snow drifts flanking the racing line: soft sculpted texture on the
	# otherwise bare berg tops (visual only, outside the racing surface).
	var drift_mat := VisualLibrary.rock_material(Color(0.98, 0.97, 1.0))
	for i: int in 12:
		var o6 := rng.randf_range(10.0, main_guide.length - 90.0)
		var xf6 := main_guide.transform_at(o6)
		var lat6 := rng.randf_range(12.5, 20.0) * (1.0 if rng.randf() > 0.5 else -1.0)
		var drift := MeshInstance3D.new()
		drift.mesh = VisualLibrary.snow_drift_mesh()
		drift.material_override = drift_mat
		var ds := rng.randf_range(1.6, 3.6)
		drift.scale = Vector3(ds, ds * rng.randf_range(0.5, 0.8), ds * rng.randf_range(0.8, 1.3))
		drift.position = xf6.origin + xf6.basis.x * lat6 + Vector3.DOWN * 0.35
		drift.rotation.y = rng.randf() * TAU
		add_child(drift)

	# Cinematic set dressing: sculpted hero bergs with waterline notches, a
	# breaching-whale arc pair, circling seabird flocks, drifting near-track
	# foam patches, a brash-ice raft along the track edges, and the sun-glint
	# corridor. Visual-only, batched or few-node, all skipped headless. Hero
	# bergs first: seabirds anchor to them and their churn collars batch into
	# the shared foam surface.
	if not headless:
		_add_hero_bergs()
		_add_breach_arcs()
		_add_breaching_whale()
		_add_seabirds()
		_add_drift_foam()
		_add_brash_ice()
		_add_floes()
		_add_pack_ice()
		_add_sun_glint()

	# Foam bands hugging the swim channel edges, then one batched commit for
	# every foam quad placed above (single mesh, single draw call).
	if not headless:
		for line: Array in _water_lines:
			_channel_foam(line)
		_commit_foam()


## Re-tint every track floor run toward white-blue (visual only; surface
## physics metadata is untouched). Under the warm sunrise light the default
## VisualLibrary track tints tone-mapped to lilac-pink and sank into the
## water (screenshot defect). Floor runs are identified structurally: each is
## a MeshInstance3D immediately followed by its StaticBody3D carrying the
## "surface" meta — walls and skirts have no such body, so they are skipped.
## Sunset-grazing sun turns the snow shader's sastrugi/micro-bump normal
## relief into hard violet self-shadow dimples across the whole ribbon
## (screenshot defect). Same snow shader, but nearly flat normals here.
static var _flat_snow_mat: ShaderMaterial = null


static func _flat_lit_snow() -> ShaderMaterial:
	if _flat_snow_mat == null:
		_flat_snow_mat = VisualLibrary.snow_material(TRACK_SNOW_TINT, 0.55).duplicate() as ShaderMaterial
		_flat_snow_mat.set_shader_parameter("sastrugi_strength", 0.12)
		_flat_snow_mat.set_shader_parameter("normal_strength", 0.1)
		_flat_snow_mat.set_shader_parameter("detail_strength", 0.22)
		_flat_snow_mat.set_shader_parameter("cavity_strength", 0.0)
		_flat_snow_mat.set_shader_parameter("micro_bump_strength", 0.0)
	return _flat_snow_mat


func _cool_track_materials() -> void:
	# Wet-sheen variants (cache-safe duplicates): any ice run whose lowest
	# vertex sits under WET_SHEEN_Y skims the sea — swim approaches, wave
	# ramps, seal flat, finale — so its surface tightens to a glassier,
	# meltwater-slicked film (lower roughness, brighter specular). Visual
	# only; SurfacesDB friction metadata is untouched. The high berg-hop arc
	# and the shortcut stay dry frosted ice.
	var wet_ice := VisualLibrary.ice_material(TRACK_ICE_TINT, 0.85).duplicate() as ShaderMaterial
	wet_ice.set_shader_parameter("roughness_base", 0.03)
	wet_ice.set_shader_parameter("roughness_variation", 0.08)
	wet_ice.set_shader_parameter("specular_amount", 0.78)
	var wet_rice := VisualLibrary.ice_material(TRACK_RICE_TINT, 0.5).duplicate() as ShaderMaterial
	wet_rice.set_shader_parameter("roughness_base", 0.12)
	wet_rice.set_shader_parameter("roughness_variation", 0.14)
	wet_rice.set_shader_parameter("specular_amount", 0.7)
	for track_name: String in ["MainTrack", "Branch_berg_chain"]:
		var track := get_node_or_null(track_name)
		if track == null:
			continue
		var children := track.get_children()
		for i: int in children.size() - 1:
			var floor_mesh := children[i] as MeshInstance3D
			var body := children[i + 1] as StaticBody3D
			if floor_mesh == null or body == null or not body.has_meta("surface"):
				continue
			var surface := int(body.get_meta("surface"))
			var wet := floor_mesh.mesh.get_aabb().position.y + floor_mesh.position.y < WET_SHEEN_Y
			if surface == SNOW:
				floor_mesh.material_override = _flat_lit_snow()
			elif surface == ICE:
				floor_mesh.material_override = wet_ice if wet \
					else VisualLibrary.ice_material(TRACK_ICE_TINT, 0.85)
			elif surface == RICE:
				floor_mesh.material_override = wet_rice if wet \
					else VisualLibrary.ice_material(TRACK_RICE_TINT, 0.5)


## Horizon berg clusters, placed relative to the main guide (never the course
## centroid) so every cluster is guaranteed 420m+ off the racing line, plus
## end caps past the start and finish so the skyline wraps. Faceted
## VisualLibrary.berg_mesh silhouettes in azure ice_material: cool blue albedo
## + fresnel rim keeps them reading as ICE under the warm sunrise sun.
func _add_horizon_bergs() -> void:
	if GameConfig.is_headless():
		return
	var berg_mat := VisualLibrary.ice_material(HORIZON_BERG_TINT, 0.45)
	# Clusters between the course and the sun read backlit: their silhouette
	# edges pick up the warm sunrise rim instead of the neutral pale one.
	var warm_mat := _warm_rim_ice(HORIZON_BERG_TINT, 0.45, 0.45, 2.4)
	var sun_h := _sun_dir_h()
	var low_detail := String(SettingsManager.get_setting("display", "particle_quality")) == "low"
	var clusters: Array[Dictionary] = []
	var cluster_count := 6
	for i: int in cluster_count:
		var xf := main_guide.transform_at(main_guide.length * (float(i) + 0.5) / float(cluster_count))
		for side: float in [-1.0, 1.0]:
			clusters.append({"pos": xf.origin + xf.basis.x * (rng.randf_range(420.0, 640.0) * side),
				"warm": sun_h.dot(xf.basis.x * side) > 0.0})
	var start_dir := (main_guide.position_at(minf(40.0, main_guide.length))
		- main_guide.position_at(0.0)).normalized()
	clusters.append({"pos": main_guide.position_at(0.0) - start_dir * rng.randf_range(480.0, 620.0),
		"warm": sun_h.dot(-start_dir) > 0.0})
	var end_dir := (main_guide.position_at(main_guide.length)
		- main_guide.position_at(maxf(main_guide.length - 40.0, 0.0))).normalized()
	clusters.append({"pos": main_guide.position_at(main_guide.length) + end_dir * rng.randf_range(480.0, 620.0),
		"warm": sun_h.dot(end_dir) > 0.0})
	for cluster: Dictionary in clusters:
		var center := cluster["pos"] as Vector3
		var berg_count := rng.randi_range(1, 2) if low_detail else rng.randi_range(2, 3)
		for k: int in berg_count:
			var berg := MeshInstance3D.new()
			# Eight shapes across two dozen instances read as one berg stamped
			# repeatedly along the horizon. Sixteen is still few enough to batch
			# but enough that neighbours stop rhyming.
			berg.mesh = VisualLibrary.berg_mesh(rng.randi_range(0, 15))
			berg.material_override = warm_mat if bool(cluster["warm"]) else berg_mat
			# Horizon skyline only — never let these giants cast into the scene.
			berg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var s := rng.randf_range(26.0, 54.0)
			berg.scale = Vector3(s * rng.randf_range(0.9, 1.5), s * rng.randf_range(0.5, 0.85), s)
			berg.position = Vector3(center.x + rng.randf_range(-80.0, 80.0),
				OCEAN_Y - s * 0.06, center.z + rng.randf_range(-80.0, 80.0))
			berg.rotation.y = rng.randf() * TAU
			add_child(berg)
	# Ultra-far mega-berg layer: a second, deeper skyline ring at 900-1250m.
	# The sunrise fog (density 0.0018) dissolves these into pale warm ghosts,
	# giving the horizon two recession layers instead of one cutout ring.
	var far_mat := VisualLibrary.ice_material(Color(0.56, 0.7, 0.88), 0.25)
	var far_count := 5 if low_detail else 8
	for i: int in far_count:
		var xf := main_guide.transform_at(main_guide.length * (float(i) + 0.5) / float(far_count))
		var side := 1.0 if i % 2 == 0 else -1.0
		var mega := MeshInstance3D.new()
		mega.mesh = VisualLibrary.berg_mesh(rng.randi_range(16, 27))
		mega.material_override = far_mat
		mega.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ms := rng.randf_range(60.0, 105.0)
		mega.scale = Vector3(ms * rng.randf_range(1.0, 1.6), ms * rng.randf_range(0.45, 0.7), ms)
		var mpos := xf.origin + xf.basis.x * (rng.randf_range(900.0, 1250.0) * side)
		mega.position = Vector3(mpos.x, OCEAN_Y - ms * 0.05, mpos.z)
		mega.rotation.y = rng.randf() * TAU
		add_child(mega)


## Course-aligned high-density swell sheet at the true ocean height. Covers
## the whole course corridor (plus the 320m lateral prop band: drifting
## bergs, boats, whales, buoy foam) with ~12m cells so the water shader's
## vertex swell and analytic normals resolve into visible rolling waves and
## low-sun glints instead of the matte flat the 83m far-grid cells produced.
func _add_ocean_detail() -> void:
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for point: Vector3 in main_guide.points:
		min_x = minf(min_x, point.x)
		max_x = maxf(max_x, point.x)
		min_z = minf(min_z, point.z)
		max_z = maxf(max_z, point.z)
	var pad := 360.0
	var width := (max_x - min_x) + pad * 2.0
	var depth := (max_z - min_z) + pad * 2.0
	var low_detail := String(SettingsManager.get_setting("display", "particle_quality")) == "low"
	var cell := 18.0 if low_detail else 12.0
	var plane := PlaneMesh.new()
	plane.size = Vector2(width, depth)
	plane.subdivide_width = int(width / cell)
	plane.subdivide_depth = int(depth / cell)
	var sheet := MeshInstance3D.new()
	sheet.name = "OceanDetail"
	sheet.mesh = plane
	# wave_height 0.55 keeps crests under the foam blobs at OCEAN_Y + 0.68;
	# wave_scale 0.08 -> ~46m primary wavelength, ~4 samples per wave at 12m.
	# Duplicated (cache-safe) so this sheet alone gets extra crest whitecaps
	# and a slightly slower swell: rolling waves stay READABLE at race height
	# without touching the shared channel/far-sheet water materials.
	var ocean_mat := VisualLibrary.water_material(OCEAN_DEEP, OCEAN_SHALLOW, 0.55, 0.08).duplicate() as ShaderMaterial
	ocean_mat.set_shader_parameter("crest_foam", 0.38)
	ocean_mat.set_shader_parameter("wave_speed", 0.9)
	# Align the shader's mirror-glint with the ACTUAL sunrise sun (the shared
	# default points at a generic overhead sun): every wave face now sparkles
	# along the same corridor as the sun disc and glint quads. Slightly
	# stronger + tighter than default — low-sun glitter on open water.
	ocean_mat.set_shader_parameter("sun_direction", _sun_dir_3d())
	ocean_mat.set_shader_parameter("sun_glint_strength", 1.45)
	ocean_mat.set_shader_parameter("sun_glint_power", 220.0)
	sheet.material_override = ocean_mat
	sheet.position = Vector3((min_x + max_x) * 0.5, OCEAN_Y, (min_z + max_z) * 0.5)
	sheet.extra_cull_margin = 4.0  # flat PlaneMesh AABB + vertex displacement
	add_child(sheet)


## Navigation buoy: red ring/lamp to port, green to starboard. Lamp emission
## sits above the glow HDR threshold (1.1) so tops bloom against the sunrise.
func _add_buoy(pos: Vector3, port: bool) -> void:
	var buoy := Node3D.new()
	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.7
	body_mesh.height = 2.6
	body.mesh = body_mesh
	body.material_override = TrackBuilder.prop_material(Color(0.95, 0.95, 0.93))
	body.position.y = 0.9
	buoy.add_child(body)
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.55
	ring_mesh.outer_radius = 1.0
	ring.mesh = ring_mesh
	ring.material_override = TrackBuilder.prop_material(
		Color(0.85, 0.2, 0.18) if port else Color(0.12, 0.6, 0.32))
	ring.position.y = 0.55
	buoy.add_child(ring)
	var light := MeshInstance3D.new()
	var light_mesh := SphereMesh.new()
	light_mesh.radius = 0.22
	light_mesh.height = 0.44
	light.mesh = light_mesh
	var glow_col := Color(1.0, 0.32, 0.16) if port else Color(0.3, 1.0, 0.5)
	var lm := StandardMaterial3D.new()
	lm.albedo_color = glow_col
	lm.emission_enabled = true
	lm.emission = glow_col
	lm.emission_energy_multiplier = 2.6
	light.material_override = lm
	light.position.y = 2.35
	buoy.add_child(light)
	buoy.position = pos
	add_child(buoy)
	_bobbers.append({"node": buoy, "base_y": pos.y, "phase": rng.randf() * TAU, "amp": 0.3, "speed": 0.9})
	# Blinking navigation lamp (real buoys flash): per-buoy period/phase so the
	# bay twinkles asynchronously. lm is created per buoy, never shared, so the
	# _process blink writes cannot leak into other materials. Headless sims
	# skip registration (no renderer to blink for).
	if not GameConfig.is_headless():
		_buoy_lamps.append({"mat": lm, "phase": rng.randf() * 3.0,
			"period": rng.randf_range(1.7, 2.6), "lit": true})


func _add_whale(pos: Vector3, yaw: float) -> void:
	var whale := Node3D.new()
	var dark := TrackBuilder.prop_material(Color(0.2, 0.22, 0.27), 0.9)
	var back := MeshInstance3D.new()
	var back_mesh := SphereMesh.new()
	back_mesh.radius = 6.0
	back_mesh.height = 7.0
	back.mesh = back_mesh
	back.material_override = dark
	back.scale = Vector3(1.5, 0.55, 0.8)
	whale.add_child(back)
	var tail := MeshInstance3D.new()
	var tail_mesh := PrismMesh.new()
	tail_mesh.size = Vector3(5.0, 3.0, 0.7)
	tail.mesh = tail_mesh
	tail.material_override = dark
	tail.position = Vector3(11.0, 2.2, 0.0)
	tail.rotation.z = deg_to_rad(18.0)
	whale.add_child(tail)
	var fin := MeshInstance3D.new()
	var fin_mesh := PrismMesh.new()
	fin_mesh.size = Vector3(2.4, 2.0, 0.5)
	fin.mesh = fin_mesh
	fin.material_override = dark
	fin.position = Vector3(-3.0, 2.6, 0.0)
	fin.rotation.z = deg_to_rad(-14.0)
	whale.add_child(fin)
	whale.position = Vector3(pos.x, OCEAN_Y - 1.6, pos.z)
	whale.rotation.y = yaw
	add_child(whale)
	_bobbers.append({"node": whale, "base_y": whale.position.y, "phase": rng.randf() * TAU, "amp": 0.5, "speed": 0.25})


## Research vessel anchored in the bay: wedge bow, two-tier superstructure,
## mast with crossbar, funnel, deck gear — a detailed inhabited silhouette
## rather than the old plain box, with warm window light and a masthead lamp.
func _add_boat(pos: Vector3, yaw: float) -> void:
	var boat := Node3D.new()
	var hull := MeshInstance3D.new()
	var hull_mesh := BoxMesh.new()
	hull_mesh.size = Vector3(16.0, 2.6, 5.5)
	hull.mesh = hull_mesh
	hull.material_override = TrackBuilder.prop_material(Color(0.9, 0.9, 0.92))
	hull.position.y = 1.1
	boat.add_child(hull)
	# Wedge bow: PrismMesh rotated so the apex points along +X past the hull
	# end (Rz(-90): local +Y apex -> world +X). Same 2.6m cross-section as the
	# hull so the join is seamless.
	var bow := MeshInstance3D.new()
	var bow_mesh := PrismMesh.new()
	bow_mesh.size = Vector3(2.6, 4.5, 5.5)
	bow.mesh = bow_mesh
	bow.material_override = TrackBuilder.prop_material(Color(0.9, 0.9, 0.92))
	bow.position = Vector3(10.2, 1.1, 0.0)
	bow.rotation.z = -PI / 2.0
	boat.add_child(bow)
	var stripe := MeshInstance3D.new()
	var stripe_mesh := BoxMesh.new()
	stripe_mesh.size = Vector3(16.2, 0.5, 5.7)
	stripe.mesh = stripe_mesh
	stripe.material_override = TrackBuilder.prop_material(Color(0.8, 0.2, 0.18))
	stripe.position.y = 0.4
	boat.add_child(stripe)
	var deck_snow := MeshInstance3D.new()
	var snow_mesh := BoxMesh.new()
	snow_mesh.size = Vector3(15.6, 0.3, 5.1)
	deck_snow.mesh = snow_mesh
	deck_snow.material_override = TrackBuilder.prop_material(Color(0.97, 0.98, 1.0))
	deck_snow.position.y = 2.55
	boat.add_child(deck_snow)
	var cabin := MeshInstance3D.new()
	var cabin_mesh := BoxMesh.new()
	cabin_mesh.size = Vector3(4.5, 2.6, 3.6)
	cabin.mesh = cabin_mesh
	cabin.material_override = TrackBuilder.prop_material(Color(0.85, 0.87, 0.9))
	cabin.position = Vector3(-3.5, 3.9, 0.0)
	boat.add_child(cabin)
	# Bridge tier above the main cabin: stepped superstructure silhouette.
	var bridge := MeshInstance3D.new()
	var bridge_mesh := BoxMesh.new()
	bridge_mesh.size = Vector3(3.0, 1.6, 2.8)
	bridge.mesh = bridge_mesh
	bridge.material_override = TrackBuilder.prop_material(Color(0.88, 0.9, 0.93))
	bridge.position = Vector3(-3.0, 6.0, 0.0)
	boat.add_child(bridge)
	# Funnel aft of the cabin with a dark cap band.
	var funnel := MeshInstance3D.new()
	var funnel_mesh := CylinderMesh.new()
	funnel_mesh.top_radius = 0.5
	funnel_mesh.bottom_radius = 0.65
	funnel_mesh.height = 2.4
	funnel.mesh = funnel_mesh
	funnel.material_override = TrackBuilder.prop_material(Color(0.82, 0.55, 0.2))
	funnel.position = Vector3(-6.4, 4.8, 0.0)
	boat.add_child(funnel)
	var funnel_cap := MeshInstance3D.new()
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.52
	cap_mesh.bottom_radius = 0.52
	cap_mesh.height = 0.4
	funnel_cap.mesh = cap_mesh
	funnel_cap.material_override = TrackBuilder.prop_material(Color(0.2, 0.22, 0.26))
	funnel_cap.position = Vector3(-6.4, 6.1, 0.0)
	boat.add_child(funnel_cap)
	# Deck gear: crates/winch housing forward — breaks up the deck line.
	for gear: Vector3 in [Vector3(2.5, 3.05, 1.2), Vector3(4.4, 2.95, -1.1)]:
		var crate := MeshInstance3D.new()
		var crate_mesh := BoxMesh.new()
		crate_mesh.size = Vector3(1.5, 1.0, 1.3)
		crate.mesh = crate_mesh
		crate.material_override = TrackBuilder.prop_material(Color(0.75, 0.6, 0.4))
		crate.position = gear
		boat.add_child(crate)
	var antenna := MeshInstance3D.new()
	var ant_mesh := CylinderMesh.new()
	ant_mesh.top_radius = 0.05
	ant_mesh.bottom_radius = 0.08
	ant_mesh.height = 4.0
	antenna.mesh = ant_mesh
	antenna.material_override = TrackBuilder.prop_material(Color(0.4, 0.42, 0.46))
	antenna.position = Vector3(-3.5, 7.2, 0.0)
	boat.add_child(antenna)
	# Crossbar yard on the mast: instantly reads "ship" in silhouette.
	var yard := MeshInstance3D.new()
	var yard_mesh := CylinderMesh.new()
	yard_mesh.top_radius = 0.04
	yard_mesh.bottom_radius = 0.04
	yard_mesh.height = 2.6
	yard.mesh = yard_mesh
	yard.material_override = TrackBuilder.prop_material(Color(0.4, 0.42, 0.46))
	yard.position = Vector3(-3.5, 8.3, 0.0)
	yard.rotation.x = PI / 2.0
	boat.add_child(yard)
	# Warm lit-window band around the cabin + masthead lamp: distant boats read
	# as inhabited silhouettes against the sunrise (both catch the glow pass).
	var window_mat := StandardMaterial3D.new()
	window_mat.albedo_color = Color(1.0, 0.85, 0.55)
	window_mat.emission_enabled = true
	window_mat.emission = Color(1.0, 0.78, 0.42)
	window_mat.emission_energy_multiplier = 1.9
	var windows := MeshInstance3D.new()
	var win_mesh := BoxMesh.new()
	win_mesh.size = Vector3(4.62, 0.7, 3.68)
	windows.mesh = win_mesh
	windows.material_override = window_mat
	windows.position = Vector3(-3.5, 4.15, 0.0)
	boat.add_child(windows)
	var mast_light := MeshInstance3D.new()
	var ml_mesh := SphereMesh.new()
	ml_mesh.radius = 0.18
	ml_mesh.height = 0.36
	mast_light.mesh = ml_mesh
	var ml_mat := StandardMaterial3D.new()
	ml_mat.albedo_color = Color(1.0, 0.95, 0.8)
	ml_mat.emission_enabled = true
	ml_mat.emission = Color(1.0, 0.9, 0.6)
	ml_mat.emission_energy_multiplier = 2.4
	mast_light.material_override = ml_mat
	mast_light.position = Vector3(-3.5, 9.3, 0.0)
	boat.add_child(mast_light)
	# Rigging: forward stay masthead -> bow, aft stay masthead -> stern deck,
	# and a shroud from each yard tip down to the gunwale. Thin dark cylinders
	# — the taut line-work every real working vessel carries; at mid-distance
	# they cross-hatch the sunrise sky and kill the toy-model bareness.
	var rig_mat := TrackBuilder.prop_material(Color(0.16, 0.17, 0.2))
	_add_rig_line(boat, Vector3(-3.5, 9.1, 0.0), Vector3(12.0, 2.9, 0.0), rig_mat)
	_add_rig_line(boat, Vector3(-3.5, 9.1, 0.0), Vector3(-7.7, 3.0, 0.0), rig_mat)
	for zside: float in [-1.0, 1.0]:
		_add_rig_line(boat, Vector3(-3.5, 8.3, 1.3 * zside), Vector3(-3.5, 2.8, 2.45 * zside), rig_mat)
	# Radar mast on the bridge roof: tapered post plus an open-array bar that
	# sweeps in _process — the one slow-moving detail that sells "working ship".
	var radar_post := MeshInstance3D.new()
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.06
	post_mesh.bottom_radius = 0.09
	post_mesh.height = 1.0
	post_mesh.radial_segments = 6
	post_mesh.rings = 0
	radar_post.mesh = post_mesh
	radar_post.material_override = TrackBuilder.prop_material(Color(0.4, 0.42, 0.46))
	radar_post.position = Vector3(-1.9, 7.3, 0.0)
	boat.add_child(radar_post)
	var radar_pivot := Node3D.new()
	radar_pivot.position = Vector3(-1.9, 7.9, 0.0)
	boat.add_child(radar_pivot)
	var radar_bar := MeshInstance3D.new()
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(1.5, 0.14, 0.22)
	radar_bar.mesh = bar_mesh
	radar_bar.material_override = TrackBuilder.prop_material(Color(0.85, 0.87, 0.9))
	radar_pivot.add_child(radar_bar)
	if not GameConfig.is_headless():
		_spinners.append({"node": radar_pivot, "speed": 2.2})
	boat.position = Vector3(pos.x, OCEAN_Y - 0.4, pos.z)
	boat.rotation.y = yaw
	add_child(boat)
	_bobbers.append({"node": boat, "base_y": boat.position.y, "phase": rng.randf() * TAU, "amp": 0.2, "speed": 0.35})


## One taut rigging line: a thin dark cylinder stretched between two boat-local
## points. Quaternion(arc_from, arc_to) aligns the cylinder's Y axis with the
## run — both endpoints stay slanted well away from straight down, so the
## shortest-arc constructor never degenerates.
func _add_rig_line(parent: Node3D, from: Vector3, to: Vector3, mat: Material) -> void:
	var line := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.035
	mesh.bottom_radius = 0.035
	mesh.height = from.distance_to(to)
	mesh.radial_segments = 5
	mesh.rings = 0
	line.mesh = mesh
	line.material_override = mat
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	line.position = (from + to) * 0.5
	line.quaternion = Quaternion(Vector3.UP, (to - from).normalized())
	parent.add_child(line)


## --- Cinematic set dressing --------------------------------------------------

## Horizontal unit vector pointing AT the sunrise sun (matches the
## DirectionalLight built from sun_yaw_deg: for yaw Y rotation, the light
## shines along (-sin, *, -cos), so toward-sun is (sin, 0, cos)).
static func _sun_dir_h() -> Vector3:
	return Vector3(sin(deg_to_rad(SUN_YAW_DEG)), 0.0, cos(deg_to_rad(SUN_YAW_DEG)))


## Full unit vector pointing AT the sunrise sun, elevation included — exactly
## what the water shader's sun_direction uniform reflects for its glint lane.
## Matches the DirectionalLight (rot X = -SUN_PITCH_DEG, rot Y = SUN_YAW_DEG):
## toward-sun = (sin yaw * cos pitch, sin pitch, cos yaw * cos pitch).
static func _sun_dir_3d() -> Vector3:
	var pitch := deg_to_rad(SUN_PITCH_DEG)
	return _sun_dir_h() * cos(pitch) + Vector3.UP * sin(pitch)


## Ice with a WARM fresnel rim: a cache-safe duplicate of the shared ice
## material with rim tint pushed toward the sun color; the ice shader's
## built-in rim emission then carries a slight sunrise glow on every
## silhouette edge — backlit ice without a second light. Used by the hero
## bergs and by every sun-facing drifting/horizon berg.
func _warm_rim_ice(tint: Color, clarity: float, strength: float, power: float = 2.2) -> ShaderMaterial:
	var mat := VisualLibrary.ice_material(tint, clarity).duplicate() as ShaderMaterial
	mat.set_shader_parameter("rim_tint", SUN_WARM_RIM)
	mat.set_shader_parameter("rim_strength", strength)
	mat.set_shader_parameter("rim_power", power)
	return mat


## Three MASSIVE sculpted hero bergs (30-60m class) mid-distance off the
## racing line: seeded faceted silhouettes scaled way up in warm-rim azure
## ice, each with a dark wave-cut waterline notch band, a darker water halo,
## and a churn foam collar. The middle one is a natural double-pillar arch.
## Two sit on the sun side so their rims read backlit; one balances far side.
## Lateral clearance: max base radius = 1.25 * (1.1 * s) ~ 1.4s, well inside
## every dist below, so no hero ice ever crowds the racing surface.
func _add_hero_bergs() -> void:
	var warm := _warm_rim_ice(HORIZON_BERG_TINT, 0.5, 0.62, 2.2)
	# Notch band multiplies the berg's baked per-face vertex colors into a
	# dark teal: the shadowed, wave-worn undercut right at the waterline.
	var notch_mat := VisualLibrary.rock_material(Color(0.16, 0.3, 0.4))
	var halo_mat := StandardMaterial3D.new()
	halo_mat.albedo_color = Color(0.01, 0.09, 0.13, 0.42)
	halo_mat.albedo_texture = VisualLibrary.soft_radial_texture(64, 0.9)
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	halo_mat.render_priority = 1
	var sun_h := _sun_dir_h()
	var specs: Array[Dictionary] = [
		{"f": 0.24, "side": 1.0, "s": 46.0, "dist": 220.0, "arch": false},
		{"f": 0.52, "side": 1.0, "s": 38.0, "dist": 205.0, "arch": true},
		{"f": 0.8, "side": -1.0, "s": 54.0, "dist": 300.0, "arch": false},
	]
	for spec: Dictionary in specs:
		var xf := main_guide.transform_at(main_guide.length * float(spec["f"]))
		var center := Vector3(xf.origin.x, 0.0, xf.origin.z) \
			+ sun_h * (float(spec["dist"]) * float(spec["side"]))
		_hero_centers.append(center)
		var s := float(spec["s"])
		if bool(spec["arch"]):
			_hero_arch(center, s, warm, notch_mat)
		else:
			_hero_berg(center, s, rng.randi_range(0, 7), warm, notch_mat)
		_add_water_halo(center, s * 2.6, halo_mat)
		for k: int in 8:
			var a := TAU * (float(k) + rng.randf() * 0.6) / 8.0
			var r := s * rng.randf_range(1.05, 1.35)
			_foam_quad(Vector3(center.x + cos(a) * r, OCEAN_Y + 0.68, center.z + sin(a) * r),
				rng.randf_range(0.14, 0.24) * s)


func _hero_berg(center: Vector3, s: float, mesh_seed: int, mat: ShaderMaterial,
		notch_mat: StandardMaterial3D) -> void:
	var yaw := rng.randf() * TAU
	var sx := s * rng.randf_range(0.85, 1.1)
	var sy := s * rng.randf_range(0.55, 0.8)
	var sz := s * rng.randf_range(0.85, 1.1)
	var berg := MeshInstance3D.new()
	berg.mesh = VisualLibrary.berg_mesh(mesh_seed)
	berg.material_override = mat
	# Hero-scale silhouette: its low-sun shadow would reach the track as a
	# giant blob. Decorative only, so it casts no shadow.
	berg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	berg.scale = Vector3(sx, sy, sz)
	berg.position = Vector3(center.x, OCEAN_Y - sy * 0.04, center.z)
	berg.rotation.y = yaw
	add_child(berg)
	_add_waterline_notch(center, mesh_seed, Vector3(0.0, yaw, 0.0), sx, sz, notch_mat)


## Dark waterline band: the SAME seeded silhouette, xz-inflated 5% and
## y-squashed to a thin skin whose widest base ring sits just below the
## waterline. A berg barely tapers this close to its base, so the inflated
## copy stays proud of the ice only in a thin band at the water — reading as
## the wave-cut erosion notch every real berg carries. rot is the full
## rotation of the berg it hugs (tilted drifting bergs pass their list so the
## band stays flush); band_h scales the skin to the berg class (1.5m suits
## the 30-60m heroes, drifting bergs pass ~a tenth of their size).
func _add_waterline_notch(center: Vector3, mesh_seed: int, rot: Vector3, sx: float, sz: float,
		notch_mat: StandardMaterial3D, band_h: float = 1.5) -> void:
	var notch := MeshInstance3D.new()
	notch.mesh = VisualLibrary.berg_mesh(mesh_seed)
	notch.material_override = notch_mat
	notch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	notch.scale = Vector3(sx * 1.05, band_h, sz * 1.05)
	notch.position = Vector3(center.x, OCEAN_Y - 0.4, center.z)
	notch.rotation = rot
	add_child(notch)
	# Spray-wet sheen band riding just ABOVE the waterline: swell and spray
	# keep the first meter of ice above the sea dark and glassy on every real
	# berg. Same seeded silhouette, slightly less inflated than the notch so
	# the dark undercut still reads below it, glossy so the low sun streaks it.
	var wet := MeshInstance3D.new()
	wet.mesh = VisualLibrary.berg_mesh(mesh_seed)
	wet.material_override = _wet_band_material()
	wet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wet.scale = Vector3(sx * 1.035, band_h * 0.8, sz * 1.035)
	wet.position = Vector3(center.x, OCEAN_Y - 0.4 + band_h * 0.72, center.z)
	wet.rotation = rot
	add_child(wet)


## Shared glossy wet-band material: darkened teal-blue ice with a tight
## specular so the sunrise drags a highlight along every waterline.
func _wet_band_material() -> StandardMaterial3D:
	if _wet_band_mat == null:
		_wet_band_mat = StandardMaterial3D.new()
		_wet_band_mat.albedo_color = Color(0.3, 0.5, 0.6)
		_wet_band_mat.roughness = 0.06
		_wet_band_mat.metallic = 0.15
		_wet_band_mat.rim_enabled = true
		_wet_band_mat.rim = 0.4
		_wet_band_mat.rim_tint = 0.2
	return _wet_band_mat


## Natural ice arch: two inward-leaning pillar bergs bridged by a lying-berg
## lintel. Same seeded mesh family so the facet language matches; at
## mid-distance the trio silhouettes into one wave-carved arch.
func _hero_arch(center: Vector3, s: float, mat: ShaderMaterial,
		notch_mat: StandardMaterial3D) -> void:
	var yaw := rng.randf() * TAU
	# rotation.y = yaw maps local +X to this world direction.
	var axis := Vector3(cos(yaw), 0.0, -sin(yaw))
	var perp := Vector3(-axis.z, 0.0, axis.x)  # horizontal lean axis
	var gap := s * 0.85
	var lean := 0.16
	var pillar_seeds: Array[int] = [2, 5]
	for i: int in 2:
		var side := -1.0 if i == 0 else 1.0
		var pcx := center + axis * (gap * side)
		var sx := s * rng.randf_range(0.5, 0.6)
		var sy := s * rng.randf_range(0.75, 0.85)
		var sz := s * rng.randf_range(0.5, 0.6)
		var pillar := MeshInstance3D.new()
		pillar.mesh = VisualLibrary.berg_mesh(pillar_seeds[i])
		pillar.material_override = mat
		pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pillar.scale = Vector3(sx, sy, sz)
		pillar.position = Vector3(pcx.x, OCEAN_Y - 1.0, pcx.z)
		pillar.rotation.y = yaw + side * 0.4
		# Lean the tops toward each other: rotating about perp by +angle moves
		# local UP toward -axis (UP -> UP*cos - axis*sin), so lean*side points
		# both tops at the arch center.
		pillar.rotate(perp, lean * side)
		add_child(pillar)
		_add_waterline_notch(pcx, pillar_seeds[i], Vector3(0.0, yaw + side * 0.4, 0.0), sx, sz, notch_mat)
	var lintel := MeshInstance3D.new()
	lintel.mesh = VisualLibrary.berg_mesh(7)
	lintel.material_override = mat
	lintel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lintel.scale = Vector3(s * 1.15, s * 0.28, s * 0.42)
	lintel.position = Vector3(center.x, OCEAN_Y + s * 0.92, center.z)
	lintel.rotation.y = yaw
	add_child(lintel)


## Soft dark halo on the water around a hero berg: sells the mass shadow and
## deepens the waterline band from race distance. Sits between the swell
## crests (0.55) and the drifting foam layer (0.66).
func _add_water_halo(center: Vector3, radius: float, mat: StandardMaterial3D) -> void:
	var halo := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(radius * 2.0, radius * 2.0)
	halo.mesh = plane
	halo.material_override = mat
	# Transparent overlay: the shadow pass ignores alpha, so without this the
	# whole halo quad shadows the water as one giant hard-edged blob.
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.position = Vector3(center.x, OCEAN_Y + 0.62, center.z)
	add_child(halo)


## Breaching-whale story beats: dark torus arcs standing vertically in the
## water far off toward the sun — most of the ring submerged so only a smooth
## back-arc breaches — plus a dorsal fin and splash foam where the body meets
## the sea. StandardMaterial rim lighting catches the sunrise backlight along
## the arc edge, so they read as backlit giants, not black blobs.
func _add_breach_arcs() -> void:
	var sun_h := _sun_dir_h()
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.13, 0.15, 0.2)
	body_mat.roughness = 0.55
	body_mat.rim_enabled = true
	body_mat.rim = 0.7
	body_mat.rim_tint = 0.25
	var specs: Array[Dictionary] = [
		{"f": 0.36, "dist": 340.0, "r": 9.0},
		{"f": 0.66, "dist": 420.0, "r": 11.0},
	]
	for spec: Dictionary in specs:
		var xf := main_guide.transform_at(main_guide.length * float(spec["f"]))
		var center := Vector3(xf.origin.x, 0.0, xf.origin.z) + sun_h * float(spec["dist"])
		var r := float(spec["r"])
		var depth := r * 0.42
		var yaw := atan2(sun_h.x, sun_h.z) + PI / 2.0 + rng.randf_range(-0.5, 0.5)
		var whale := Node3D.new()
		whale.position = Vector3(center.x, OCEAN_Y - depth, center.z)
		whale.rotation.y = yaw
		add_child(whale)
		var arc := MeshInstance3D.new()
		arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var torus := TorusMesh.new()
		torus.inner_radius = r - 1.7
		torus.outer_radius = r
		torus.rings = 40
		torus.ring_segments = 10
		arc.mesh = torus
		arc.material_override = body_mat
		# Scale local Y (donut axis) BEFORE the x-rotation stands the ring up:
		# thins the body laterally without shearing.
		arc.scale = Vector3(1.0, 0.55, 1.0)
		arc.rotation.x = PI / 2.0
		whale.add_child(arc)
		var fin := MeshInstance3D.new()
		var fin_mesh := PrismMesh.new()
		fin_mesh.size = Vector3(2.0, 1.8, 0.4)
		fin.mesh = fin_mesh
		fin.material_override = body_mat
		fin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fin.position = Vector3(rng.randf_range(-1.2, 1.2), r - 0.2, 0.0)
		fin.rotation.z = deg_to_rad(-12.0)
		whale.add_child(fin)
		# Splash foam where the arc pierces the surface (chord of the ring's
		# midline circle at waterline depth), batched into the shared foam mesh.
		var rm := r - 0.85
		var chord := sqrt(maxf(rm * rm - depth * depth, 1.0))
		var dirx := Vector3(cos(yaw), 0.0, -sin(yaw))
		for side: float in [-1.0, 1.0]:
			var splash := Vector3(center.x, 0.0, center.z) + dirx * (chord * side)
			for k: int in 3:
				_foam_quad(Vector3(splash.x + rng.randf_range(-2.0, 2.0), OCEAN_Y + 0.68,
					splash.z + rng.randf_range(-2.0, 2.0)), rng.randf_range(2.0, 3.5))


## Live breaching whale: far off toward the sunrise, a low-poly humpback
## launches nose-first out of the swell on a long timer, arcs through open
## air and falls back — pure _process pose math on one Node3D, no
## allocations, no physics. UITheme.reduced_motion() disables the whole
## performer (a leaping peripheral silhouette is exactly the motion that
## setting exists to remove); the static breach-arc story beats remain.
func _add_breaching_whale() -> void:
	if UITheme.reduced_motion():
		return
	var xf := main_guide.transform_at(main_guide.length * 0.12)
	var anchor := Vector3(xf.origin.x, 0.0, xf.origin.z) + _sun_dir_h() * 330.0
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.14, 0.16, 0.21)
	body_mat.roughness = 0.5
	body_mat.rim_enabled = true
	body_mat.rim = 0.65
	body_mat.rim_tint = 0.25
	var pale_mat := TrackBuilder.prop_material(Color(0.72, 0.76, 0.8))
	var whale := Node3D.new()
	whale.name = "BreachWhale"
	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 2.6
	body_mesh.height = 15.0
	body_mesh.radial_segments = 10
	body_mesh.rings = 6
	body.mesh = body_mesh
	body.material_override = body_mat
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.rotation.z = -PI / 2.0  # capsule Y axis -> nose along +X
	whale.add_child(body)
	# Pale throat pleats: humpbacks flash a light belly mid-breach.
	var throat := MeshInstance3D.new()
	var throat_mesh := CapsuleMesh.new()
	throat_mesh.radius = 2.1
	throat_mesh.height = 11.0
	throat_mesh.radial_segments = 8
	throat_mesh.rings = 4
	throat.mesh = throat_mesh
	throat.material_override = pale_mat
	throat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	throat.rotation.z = -PI / 2.0
	throat.position = Vector3(1.0, -0.9, 0.0)
	whale.add_child(throat)
	var fluke := MeshInstance3D.new()
	var fluke_mesh := PrismMesh.new()
	fluke_mesh.size = Vector3(6.0, 2.6, 0.5)
	fluke.mesh = fluke_mesh
	fluke.material_override = body_mat
	fluke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fluke.position = Vector3(-8.6, 0.6, 0.0)
	fluke.rotation.z = deg_to_rad(24.0)
	whale.add_child(fluke)
	for zside: float in [-1.0, 1.0]:
		var fin := MeshInstance3D.new()
		var fin_mesh := PrismMesh.new()
		fin_mesh.size = Vector3(4.6, 1.4, 0.4)
		fin.mesh = fin_mesh
		fin.material_override = pale_mat
		fin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fin.position = Vector3(1.6, -1.4, 2.4 * zside)
		fin.rotation.x = deg_to_rad(50.0 * zside)
		whale.add_child(fin)
	whale.position = Vector3(anchor.x, OCEAN_Y - 30.0, anchor.z)
	whale.rotation.y = rng.randf() * TAU
	add_child(whale)
	_breach_whale = whale
	_breach_anchor = anchor
	_breach_wait = rng.randf_range(9.0, 16.0)
	# Splash disc at the anchor: scaled up in _update_breach whenever the body
	# straddles the waterline, invisible (near-zero scale) the rest of the time.
	_breach_splash = MeshInstance3D.new()
	var splash_mesh := PlaneMesh.new()
	splash_mesh.size = Vector2(1.0, 1.0)
	_breach_splash.mesh = splash_mesh
	var splash_mat := StandardMaterial3D.new()
	splash_mat.albedo_color = Color(1.0, 0.97, 0.92, 0.55)
	splash_mat.albedo_texture = VisualLibrary.soft_radial_texture(64, 0.85)
	splash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	splash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	splash_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	splash_mat.render_priority = 2
	_breach_splash.material_override = splash_mat
	_breach_splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_breach_splash.position = Vector3(anchor.x, OCEAN_Y + 0.7, anchor.z)
	_breach_splash.scale = Vector3(0.05, 1.0, 0.05)
	add_child(_breach_splash)


## Drives the breaching whale: long submerged waits (26-44s) punctuated by a
## ~3.4s parabolic leap — nose-led rise, pitch-over through the apex,
## back-first re-entry. The splash disc flares only while the body crosses
## the waterline.
func _update_breach(delta: float) -> void:
	if _breach_t < 0.0:
		_breach_wait -= delta
		if _breach_wait <= 0.0:
			_breach_t = 0.0
			_breach_whale.rotation.y = rng.randf() * TAU
		return
	_breach_t += delta
	var t := _breach_t / BREACH_DURATION
	if t >= 1.0:
		_breach_t = -1.0
		_breach_wait = rng.randf_range(26.0, 44.0)
		_breach_whale.position.y = OCEAN_Y - 30.0
		_breach_splash.scale = Vector3(0.05, 1.0, 0.05)
		return
	# Body center rises from 9m under the surface to ~7m over it and back.
	var height := -9.0 + 4.0 * 16.0 * t * (1.0 - t)
	_breach_whale.position = Vector3(_breach_anchor.x, OCEAN_Y + height, _breach_anchor.z)
	_breach_whale.rotation.z = lerpf(1.15, -1.4, t)
	var wet := clampf(1.0 - absf(height) / 5.0, 0.0, 1.0)
	var spread := 0.05 + wet * 13.0
	_breach_splash.scale = Vector3(spread, 1.0, spread)


## Drifting pack-ice field beyond the brash band, in two depth layers that
## slow-drift on opposing diagonals — near plates slide visibly against the
## far band and the anchored bergs, so the whole bay parallaxes like loose
## pack riding a current. One shared plate mesh + ONE cached ice material
## across both layers (same cache entry the pancake floes use); plate counts
## scale with display/quality_preset (low ~40% of high). Each layer is a
## single MultiMesh whose root drifts in _process. Reduced motion keeps the
## field but pins it static.
func _add_pack_ice() -> void:
	var quality := String(SettingsManager.get_setting("display", "quality_preset"))
	var keep := 1.0
	if quality == "medium":
		keep = 0.7
	elif quality == "low":
		keep = 0.4
	var plate_mesh := CylinderMesh.new()
	plate_mesh.top_radius = 1.0
	plate_mesh.bottom_radius = 1.14
	plate_mesh.height = 0.34
	plate_mesh.radial_segments = 7
	plate_mesh.rings = 0
	var mat := VisualLibrary.ice_material(Color(0.9, 0.95, 1.0), 0.3)
	var layers: Array[Dictionary] = [
		{"name": "PackIceNear", "lat": Vector2(120.0, 200.0), "s": Vector2(2.4, 5.5),
			"step": 44.0, "dir": Vector3(0.8, 0.0, 0.6), "amp": 7.0, "speed": 0.05},
		{"name": "PackIceFar", "lat": Vector2(210.0, 360.0), "s": Vector2(4.0, 9.0),
			"step": 62.0, "dir": Vector3(-0.5, 0.0, 0.86), "amp": 3.0, "speed": 0.03},
	]
	for layer: Dictionary in layers:
		var xforms: Array[Transform3D] = []
		var lat_range: Vector2 = layer["lat"]
		var s_range: Vector2 = layer["s"]
		var o := 30.0
		while o < main_guide.length - 30.0:
			var xf := main_guide.transform_at(o)
			for side: float in [-1.0, 1.0]:
				if rng.randf() > keep * 0.85:
					continue
				var lat := rng.randf_range(lat_range.x, lat_range.y) * side
				var pos := xf.origin + xf.basis.x * lat + xf.basis.z * rng.randf_range(-18.0, 18.0)
				var b := Basis.from_euler(Vector3(rng.randf_range(-0.04, 0.04),
					rng.randf() * TAU, rng.randf_range(-0.04, 0.04))) \
					* Basis.from_scale(Vector3(rng.randf_range(s_range.x, s_range.y), 1.0,
						rng.randf_range(s_range.x, s_range.y)))
				xforms.append(Transform3D(b, Vector3(pos.x, OCEAN_Y + 0.28, pos.z)))
			o += float(layer["step"])
		if xforms.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = plate_mesh
		mm.instance_count = xforms.size()
		for i: int in xforms.size():
			mm.set_instance_transform(i, xforms[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = String(layer["name"])
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		if not UITheme.reduced_motion():
			_drift_layers.append({"node": mmi, "dir": (layer["dir"] as Vector3).normalized(),
				"amp": float(layer["amp"]), "speed": float(layer["speed"]),
				"phase": rng.randf() * TAU})


## Seabird flocks circling high over the first and last hero bergs: thin dark
## billboard quads on slow-spinning pivots — distant gulls riding thermals.
## One shared mesh + material across every bird; pivots yaw in _process.
func _add_seabirds() -> void:
	if _hero_centers.is_empty():
		return
	var bird_mesh := QuadMesh.new()
	bird_mesh.size = Vector2(1.7, 0.4)
	var bird_mat := StandardMaterial3D.new()
	bird_mat.albedo_color = Color(0.2, 0.22, 0.28)
	bird_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bird_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var anchors: Array[Vector3] = [_hero_centers[0], _hero_centers[_hero_centers.size() - 1]]
	for a_i: int in anchors.size():
		var anchor := anchors[a_i]
		var pivot := Node3D.new()
		pivot.position = Vector3(anchor.x, OCEAN_Y + rng.randf_range(46.0, 62.0), anchor.z)
		add_child(pivot)
		for b: int in 5:
			var bird := MeshInstance3D.new()
			bird.mesh = bird_mesh
			bird.material_override = bird_mat
			bird.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var ang := TAU * float(b) / 5.0 + rng.randf() * 0.8
			var rad := rng.randf_range(7.0, 15.0)
			bird.position = Vector3(cos(ang) * rad, rng.randf_range(-3.0, 3.0), sin(ang) * rad)
			# Per-bird wingspan variance: the flock reads as individuals, not
			# five stamped copies.
			bird.scale = Vector3.ONE * rng.randf_range(0.75, 1.25)
			pivot.add_child(bird)
		# Glide variation: circling rate breathes (gulls bank into the wind and
		# ease out of it, never metronome circles) and the whole flock rides a
		# slow vertical thermal bob.
		_spinners.append({"node": pivot, "speed": 0.22 if a_i % 2 == 0 else -0.17,
			"wobble": 0.4, "wobble_freq": rng.randf_range(0.22, 0.4),
			"wobble_phase": rng.randf() * TAU})
		_bobbers.append({"node": pivot, "base_y": pivot.position.y, "phase": rng.randf() * TAU,
			"amp": rng.randf_range(1.0, 1.8), "speed": 0.16})


## Brash ice: the small broken chunks that collect along berg edges in every
## real polar bay. One MultiMesh of a seeded berg silhouette squashed to floe
## scale, scattered just off both track edges at the waterline (lateral
## 15-34m — the ocean sits 5-15m below the racing surface, so chunks hug the
## berg skirts and swim-channel flanks, never the track). Single draw call;
## the whole raft rides the swell via one _bobbers node write per frame.
func _add_brash_ice() -> void:
	var low_detail := String(SettingsManager.get_setting("display", "particle_quality")) == "low"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = VisualLibrary.berg_mesh(3)
	var xforms: Array[Transform3D] = []
	var step := 58.0 if low_detail else 34.0
	var o := 30.0
	while o < main_guide.length - 30.0:
		var xf := main_guide.transform_at(o)
		for side: float in [-1.0, 1.0]:
			for k: int in rng.randi_range(1, 3):
				if rng.randf() < 0.3:
					continue
				var lat := rng.randf_range(15.0, 34.0) * side
				var pos := xf.origin + xf.basis.x * lat \
					+ xf.basis.z * rng.randf_range(-12.0, 12.0)
				var b := Basis.from_euler(Vector3(rng.randf_range(-0.12, 0.12),
					rng.randf() * TAU, rng.randf_range(-0.12, 0.12))) \
					* Basis.from_scale(Vector3(rng.randf_range(0.5, 1.6),
						rng.randf_range(0.22, 0.45), rng.randf_range(0.5, 1.6)))
				xforms.append(Transform3D(b, Vector3(pos.x, OCEAN_Y + 0.25, pos.z)))
		o += step
	if xforms.is_empty():
		return
	mm.instance_count = xforms.size()
	for i: int in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "BrashIce"
	mmi.multimesh = mm
	mmi.material_override = VisualLibrary.ice_material(Color(0.85, 0.93, 1.0), 0.4)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_bobbers.append({"node": mmi, "base_y": 0.0, "phase": rng.randf() * TAU,
		"amp": 0.09, "speed": 0.55})


## Drifting pancake floes: flat angular ice plates scattered across the open
## water beyond the brash band (lateral 34-120m), the loose mid-distance pack
## every real berg bay carries. Squashed 7-sided cylinders in pale ice, tiny
## tilts so edges catch the low sun. One MultiMesh riding the swell via a
## single _bobbers write per frame; shadows off.
func _add_floes() -> void:
	var low_detail := String(SettingsManager.get_setting("display", "particle_quality")) == "low"
	var floe_mesh := CylinderMesh.new()
	floe_mesh.top_radius = 1.0
	floe_mesh.bottom_radius = 1.12
	floe_mesh.height = 0.32
	floe_mesh.radial_segments = 7
	floe_mesh.rings = 0
	var xforms: Array[Transform3D] = []
	var step := 64.0 if low_detail else 40.0
	var o := 40.0
	while o < main_guide.length - 40.0:
		var xf := main_guide.transform_at(o)
		for side: float in [-1.0, 1.0]:
			for _k: int in rng.randi_range(1, 2):
				if rng.randf() < 0.35:
					continue
				var lat := rng.randf_range(34.0, 120.0) * side
				var pos := xf.origin + xf.basis.x * lat + xf.basis.z * rng.randf_range(-16.0, 16.0)
				var b := Basis.from_euler(Vector3(rng.randf_range(-0.05, 0.05),
					rng.randf() * TAU, rng.randf_range(-0.05, 0.05))) \
					* Basis.from_scale(Vector3(rng.randf_range(1.4, 4.2), 1.0, rng.randf_range(1.4, 4.2)))
				xforms.append(Transform3D(b, Vector3(pos.x, OCEAN_Y + 0.3, pos.z)))
		o += step
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = floe_mesh
	mm.instance_count = xforms.size()
	for i: int in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "PancakeFloes"
	mmi.multimesh = mm
	mmi.material_override = VisualLibrary.ice_material(Color(0.9, 0.95, 1.0), 0.3)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_bobbers.append({"node": mmi, "base_y": 0.0, "phase": rng.randf() * TAU,
		"amp": 0.07, "speed": 0.45})


## Sparse foam patches on the near-track water: small clustered quads batched
## into ONE mesh whose root node slow-drifts in _process, so the surface
## visibly moves at race height even between swell crests.
func _add_drift_foam() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var o := 40.0
	while o < main_guide.length - 40.0:
		var xf := main_guide.transform_at(o)
		for side: float in [-1.0, 1.0]:
			if rng.randf() < 0.35:
				continue
			var lat := rng.randf_range(26.0, 110.0) * side
			var base := xf.origin + xf.basis.x * lat
			var cpos := Vector3(base.x, OCEAN_Y + 0.66, base.z)
			for k: int in rng.randi_range(2, 3):
				_flat_quad(st, cpos + Vector3(rng.randf_range(-3.0, 3.0), 0.0, rng.randf_range(-3.0, 3.0)),
					rng.randf_range(1.6, 3.4))
		o += 58.0
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	_drift_foam = MeshInstance3D.new()
	_drift_foam.name = "DriftFoam"
	_drift_foam.mesh = mesh
	# Alpha blobs read as opaque quads in the shadow pass — no casting.
	_drift_foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.97, 0.92, 0.38)
	mat.albedo_texture = VisualLibrary.soft_radial_texture(64, 0.8)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 2
	_drift_foam.material_override = mat
	add_child(_drift_foam)
	_drift_origin = _drift_foam.position


## Sun-glint corridor + whitecap band: a lane of warm sparkle quads marching
## across the water toward the sun from anchor points along the course, quads
## growing with distance, plus sparse white caps in the same lane. Emission
## energy 2.4 clears the 1.1 glow threshold so the lane blooms like low-sun
## glitter on open water. One batched mesh, one draw call.
func _add_sun_glint() -> void:
	var sun_h := _sun_dir_h()
	var perp := Vector3(-sun_h.z, 0.0, sun_h.x)
	var low_detail := String(SettingsManager.get_setting("display", "particle_quality")) == "low"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var anchor_step := 460.0 if low_detail else 300.0
	var o := 130.0
	while o < main_guide.length - 60.0:
		var base := main_guide.position_at(o)
		var d := 46.0
		while d < 330.0:
			if rng.randf() > 0.3:
				var pos := Vector3(base.x, OCEAN_Y + 0.72, base.z) + sun_h * d \
					+ perp * rng.randf_range(-16.0, 16.0)
				_flat_quad(st, pos, lerpf(0.55, 2.1, d / 330.0) * rng.randf_range(0.7, 1.3))
				if rng.randf() < 0.28:
					_foam_quad(pos + perp * rng.randf_range(4.0, 10.0) + Vector3(0.0, -0.04, 0.0),
						rng.randf_range(1.2, 2.4))
			d += rng.randf_range(11.0, 20.0)
		o += anchor_step
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	var glints := MeshInstance3D.new()
	glints.name = "SunGlints"
	glints.mesh = mesh
	# Alpha sparkle quads must not shadow the water they decorate.
	glints.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.6, 0.75)
	mat.albedo_texture = VisualLibrary.soft_radial_texture(32, 0.95)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.38)
	mat.emission_energy_multiplier = 2.4
	mat.render_priority = 2
	glints.material_override = mat
	add_child(glints)


## --- Water + foam upgrades --------------------------------------------------

## Swap the flat StandardMaterial water ribbon from TrackBuilder.build_water
## for the animated VisualLibrary water shader. The first MeshInstance3D child
## is the surface ribbon (areas precede it, the darker floor mesh follows).
## wave_height 0.18 (the shader's channel default) is visibly alive without
## drifting far from the gameplay swim height.
func _upgrade_water_surface(water_root: Node3D) -> void:
	if GameConfig.is_headless():
		return
	for child: Node in water_root.get_children():
		if child is MeshInstance3D:
			# Duplicate (cache-safe) so the swim channels share the same real
			# sun vector as the open ocean: glints at swim height line up with
			# the sunrise instead of the shader's generic default sun.
			var chan_mat := VisualLibrary.water_material(
				CHANNEL_DEEP, CHANNEL_SHALLOW, 0.18, 0.35).duplicate() as ShaderMaterial
			chan_mat.set_shader_parameter("sun_direction", _sun_dir_3d())
			(child as MeshInstance3D).material_override = chan_mat
			return


## Append one flat blob (soft radial quad) to ANY SurfaceTool batch.
## World-space, random spin, laid flat on XZ.
func _flat_quad(st: SurfaceTool, pos: Vector3, size: float) -> void:
	var ang := rng.randf() * TAU
	var half := size * 0.5
	var ax := Vector3(cos(ang), 0.0, sin(ang)) * half
	var az := Vector3(-sin(ang), 0.0, cos(ang)) * half
	var a := pos - ax - az
	var b := pos + ax - az
	var c := pos + ax + az
	var d := pos - ax + az
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(a)
	st.set_uv(Vector2(1.0, 0.0))
	st.add_vertex(b)
	st.set_uv(Vector2(1.0, 1.0))
	st.add_vertex(c)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(a)
	st.set_uv(Vector2(1.0, 1.0))
	st.add_vertex(c)
	st.set_uv(Vector2(0.0, 1.0))
	st.add_vertex(d)


## Append one flat foam blob to the batched foam surface. Call only between
## the SurfaceTool begin in _decorate and _commit_foam.
func _foam_quad(pos: Vector3, size: float) -> void:
	if _foam_st == null:
		return
	_flat_quad(_foam_st, pos, size)


## Foam blobs along both lateral edges of a swim channel point line, so the
## water route reads as churning where it meets the ice.
func _channel_foam(line: Array) -> void:
	var width := float((line[0] as Dictionary).get("width", 15.0))
	for i: int in line.size() - 1:
		var a: Vector3 = (line[i] as Dictionary)["pos"]
		var b: Vector3 = (line[i + 1] as Dictionary)["pos"]
		var seg := b - a
		var seg_len := seg.length()
		if seg_len < 1.0:
			continue
		var lat := Vector3(seg.z, 0.0, -seg.x).normalized()
		var steps := maxi(int(seg_len / 5.0), 1)
		for s: int in steps:
			var t := (float(s) + 0.5) / float(steps)
			var center := a.lerp(b, t)
			for side: float in [-1.0, 1.0]:
				var pos := center + lat * ((width * 0.5 - 1.0) * side)
				pos.y += 0.22
				_foam_quad(pos, rng.randf_range(1.8, 3.2))


## Commit every batched foam quad as ONE unshaded transparent mesh drawn after
## the water (render_priority) so blobs never sink under the swell.
func _commit_foam() -> void:
	if _foam_st == null:
		return
	var foam := MeshInstance3D.new()
	foam.name = "FoamBlobs"
	foam.mesh = _foam_st.commit()
	# Alpha blobs read as opaque quads in the shadow pass — no casting.
	foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.96, 0.9, 0.5)
	mat.albedo_texture = VisualLibrary.soft_radial_texture(64, 0.85)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 2
	foam.material_override = mat
	add_child(foam)
	_foam_st = null
