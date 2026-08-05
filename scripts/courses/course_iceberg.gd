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
const TRACK_SNOW_TINT: Color = Color(0.82, 0.9, 1.0)
const TRACK_ICE_TINT: Color = Color(0.4, 0.72, 1.0)
const TRACK_RICE_TINT: Color = Color(0.5, 0.74, 0.96)
## Azure ice for the big horizon bergs — must read as ICE, not rock, even
## under the warm sun.
const HORIZON_BERG_TINT: Color = Color(0.62, 0.8, 0.96)

var _bobbers: Array[Dictionary] = []  # {node, base_y, phase, amp, speed}
var _bob_time: float = 0.0
var _water_lines: Array[Array] = []  # swim channel point arrays, kept for edge foam
var _foam_st: SurfaceTool = null  # batches every foam quad into one mesh/draw call
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
		# 1. Start berg: long flat straight for the grid and spectators.
		p(0, 12, 35, {"width": 18.0}),
		p(0, 12, -30, {"width": 18.0}),
		p(2, 11.5, -100, {"width": 20.0}),
		# 2. Berg-hop: wide right-swinging arc of connected bergs, widths
		# breathing 22 -> 14 -> 20 -> 12 so each berg reads distinct.
		# wall_l stays ON at -240/-540: the branch corridor is well clear of the
		# main edge by those spots, and the wall catches racers whose guide yaw
		# (sampled far ahead by PathGuide's index-space offsets) cuts the arc.
		p(14, 11, -170, {"width": 22.0, "wall_l": false}),
		p(34, 10.5, -240, {"width": 16.0}),
		p(52, 10, -310, {"width": 16.0}),
		p(56, 9.5, -380, {"width": 20.0}),
		p(44, 9, -440, {"width": 13.0}),
		p(24, 8.5, -490, {"width": 18.0, "wall_l": false}),
		p(6, 8, -540, {"width": 18.0}),
		p(0, 8, -590, {"width": 16.0}),
		# 3. Moving-platform crossing: floorless span bridged by sliding slabs.
		p(0, 8, -620, {"width": 14.0}),
		p(0, 8, -640, {"width": 12.0, "gap": true}),
		p(0, 8, -672, {"width": 14.0}),
		# 4. Approach and the big swim channel (80m of open water).
		p(-6, 7.5, -720, {"width": 16.0}),
		p(-10, 7, -770, {"width": 16.0}),
		p(-10, 6.3, -810, {"width": 14.0}),
		p(-8, 6.0, -848, {"width": 14.0, "gap": true}),  # ice edge, 1m over water
		p(-4, 5.0, -878, {"width": 14.0, "gap": true}),  # guide at water surface
		p(0, 5.0, -900, {"width": 14.0, "gap": true}),
		p(2, 5.0, -925, {"width": 14.0, "gap": true}),
		p(3, 4.2, -932, {"width": 18.0, "surface": ICE, "wall_l": false, "wall_r": false}),  # submerged exit ramp
		p(4, 6.2, -965, {"width": 18.0, "surface": ICE}),
		# 5. Wave ramps: three rolling hills on smooth ice.
		p(2, 6.5, -1000, {"width": 16.0, "surface": ICE}),
		p(0, 8.6, -1028, {"width": 16.0, "surface": ICE}),
		p(-2, 6.4, -1042, {"width": 16.0, "surface": ICE}),
		p(-4, 8.6, -1070, {"width": 16.0, "surface": ICE}),
		p(-6, 6.4, -1084, {"width": 16.0, "surface": ICE}),
		p(-8, 8.6, -1112, {"width": 16.0, "surface": ICE}),
		p(-8, 6.2, -1126, {"width": 16.0, "surface": RICE}),
		# 6. Tilting-slab causeway: floorless span bridged by rocking slabs.
		p(-8, 6.0, -1160, {"width": 14.0}),
		p(-8, 6.0, -1185, {"width": 12.0, "gap": true}),
		p(-8, 6.0, -1220, {"width": 14.0}),
		# 7. Seal flat: wide smooth ice with sliding seals.
		p(-6, 5.8, -1250, {"width": 20.0, "surface": ICE}),
		p(-2, 5.6, -1290, {"width": 20.0, "surface": ICE}),
		p(0, 5.5, -1330, {"width": 20.0, "surface": ICE}),
		p(2, 5.4, -1360, {"width": 20.0, "surface": ICE}),
		# 8. Finale: short second swim, then the finish straight.
		p(2, 5.2, -1390, {"width": 16.0}),
		p(2, 5.0, -1410, {"width": 13.0, "wall_l": false, "wall_r": false, "gap": true}),
		p(2, 4.0, -1424, {"width": 13.0, "gap": true}),
		p(2, 4.0, -1442, {"width": 13.0, "gap": true}),
		p(2, 3.2, -1456, {"width": 18.0, "surface": ICE, "wall_l": false, "wall_r": false}),  # submerged exit ramp
		p(2, 5.0, -1490, {"width": 18.0, "surface": ICE}),
		p(0, 5.0, -1530, {"width": 18.0}),
		p(0, 5.0, -1660, {"width": 18.0}),
	]
	setup_main(pts)
	_build_arc_table()
	# Long runout past the banner so finished racers stop before the berg edge.
	finish_offset = main_guide.length - 80.0

	# Risky berg-chain shortcut: cuts the wide berg-hop arc on the inside.
	# Narrow smooth ice, no walls — fall off and you swim with the fishes.
	var branch_pts: Array = [
		p(16, 10.45, -190, {"width": 10.0, "surface": ICE, "wall_l": false, "wall_r": false}),
		p(10, 10.0, -250, {"width": 7.0, "surface": ICE, "wall_l": false, "wall_r": false}),
		p(6, 9.5, -320, {"width": 7.0, "surface": ICE, "wall_l": false, "wall_r": false}),
		p(8, 9.2, -390, {"width": 7.0, "surface": ICE, "wall_l": false, "wall_r": false}),
		p(12, 8.9, -450, {"width": 8.0, "surface": ICE, "wall_l": false, "wall_r": false}),
		p(18, 8.85, -505, {"width": 10.0, "surface": ICE, "wall_l": false, "wall_r": false}),
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
		plat.configure(Vector3(12.0, 0.8, 10.5), Vector3.RIGHT, 3.0, plat_periods[i], 0.0, plat_phases[i])
		plat.position = Vector3(0.0, 7.6, -643.0 - 10.0 * float(i))
		add_child(plat)
	TrackBuilder.add_boost_pad(self, main_guide, _arc_near(Vector3(0, 8, -640)) - 16.0)

	# --- Tilting-slab causeway (section 6) ----------------------------------
	add_hint(_offset_near(Vector3(-8, 6, -1185)) - 2.0, "jump")
	var slab_phases: Array[float] = [0.0, 0.4, 0.8, 1.2]
	for i: int in 4:
		var slab := HazardPlatform.new()
		slab.configure(Vector3(11.0, 0.8, 9.5), Vector3.RIGHT, 0.0, 4.0, 9.0, slab_phases[i])
		slab.position = Vector3(-8.0, 5.6, -1188.0 - 9.0 * float(i))
		add_child(slab)

	# --- Sliding seals (section 7) ------------------------------------------
	var seal_data: Array = [
		{"pos": Vector3(-4, 5.7, -1270), "sweep": 8.0, "speed": 3.6, "hint": "danger_left"},
		{"pos": Vector3(-1.5, 5.6, -1296), "sweep": 9.0, "speed": 4.4, "hint": "danger_right"},
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
	for crest: Vector3 in [Vector3(0, 8.6, -1028), Vector3(-4, 8.6, -1070), Vector3(-8, 8.6, -1112)]:
		add_hint(_offset_near(crest) - 2.0, "jump")

	# Keep AI biased to the inside-right through the berg arc: the left edge
	# borders the shortcut void and the far-ahead guide yaw tempts a left cut.
	add_hint(_offset_near(Vector3(34, 10.5, -240)) - 20.0, "danger_left",
		_offset_near(Vector3(52, 10, -310)) + 10.0)
	add_hint(_offset_near(Vector3(56, 9.5, -380)), "danger_left",
		_offset_near(Vector3(24, 8.5, -490)))

	# Shortcut is flat smooth ice: sliding it hard is the whole point. Branch
	# hints are matched against MAPPED main-line progress, so use entry..exit.
	var branch_entry := float(branches[0]["entry"])
	var branch_exit := float(branches[0]["exit"])
	add_hint(branch_entry + 10.0, "slide", branch_exit - 10.0, 0)

	# Boost pads after both swim exits to relaunch momentum.
	TrackBuilder.add_boost_pad(self, main_guide, _arc_near(Vector3(4, 6.2, -965)) + 6.0)
	TrackBuilder.add_boost_pad(self, main_guide, _arc_near(Vector3(2, 5.0, -1490)) + 6.0)

	# --- Pickups (placement APIs consume arclength offsets) -----------------
	add_item_row(115.0)
	add_item_row(_arc_near(Vector3(0, 8, -600)))
	add_item_row(_arc_near(Vector3(2, 6.5, -1000)) + 6.0)
	add_item_row(_arc_near(Vector3(-6, 5.8, -1250)))
	add_item_row(_arc_near(Vector3(0, 5.0, -1530)))

	add_fish_line(70.0, 8, 5.0, 0.0)
	add_fish_line(_arc_near(Vector3(14, 11, -170)), 8, 5.0, -3.0)
	add_fish_line(25.0, 10, 6.0, 0.0, 0.0, shortcut)  # shortcut reward
	add_fish_line(_arc_near(Vector3(52, 10, -310)), 8, 5.0, 3.0)
	add_fish_line(_arc_near(Vector3(0, 8, -655)), 6, 5.0, 0.0)  # across the platforms
	add_fish_line(_arc_near(Vector3(0, 5, -900)) - 25.0, 10, 6.0, 0.0)  # in the swim channel
	add_fish_line(_arc_near(Vector3(0, 8.6, -1028)) - 12.0, 8, 4.0, 0.0, 1.5)  # crest arc
	add_fish_line(_arc_near(Vector3(0, 5.5, -1330)) - 30.0, 10, 5.5, -4.0)
	add_fish_line(_arc_near(Vector3(2, 4.0, -1435)) - 10.0, 6, 5.0, 0.0)  # finale swim
	add_fish_line(_arc_near(Vector3(0, 5, -1560)) - 20.0, 8, 5.0, 0.0)

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
		"sun_yaw_deg": 40.0,
		"sun_color": Color(1.0, 0.76, 0.52),
		"sun_energy": 1.25,
		"sun_angle_max": 30.0,
		"sun_curve": 0.14,
		"sky_energy": 1.1,
		"exposure": 1.08,
		"fog_color": Color(0.98, 0.68, 0.5),
		"fog_density": 0.0018,
		"fog_height": 1.5,
		"fog_height_density": 0.035,
		"glow_threshold": 1.1,
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
		add_ground_plane(OCEAN_Y - 1.6, Color(0.1, 0.3, 0.45), 4000.0,
			VisualLibrary.water_material(OCEAN_DEEP, OCEAN_SHALLOW, 1.0, 0.014), true)
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
	if _bobbers.is_empty():
		return
	_bob_time += delta
	for b: Dictionary in _bobbers:
		var node := b["node"] as Node3D
		node.position.y = float(b["base_y"]) + sin(_bob_time * float(b["speed"]) + float(b["phase"])) * float(b["amp"])


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
				_foam_quad(Vector3(bpos.x + cos(bang) * 1.3, OCEAN_Y + 0.5, bpos.z + sin(bang) * 1.3),
					rng.randf_range(1.0, 1.6))

	# Distant whale silhouettes, slowly rising and sinking.
	for i: int in 3:
		var o3 := [420.0, 900.0, 1350.0][i] as float
		var xf3 := main_guide.transform_at(minf(o3, main_guide.length - 40.0))
		var lat3 := rng.randf_range(150.0, 240.0) * (1.0 if i % 2 == 0 else -1.0)
		_add_whale(xf3.origin + xf3.basis.x * lat3, rng.randf() * TAU)

	# Snow-covered research boats far off in the bay.
	for i: int in 2:
		var o4 := [600.0, 1450.0][i] as float
		var xf4 := main_guide.transform_at(minf(o4, main_guide.length - 40.0))
		var lat4 := rng.randf_range(200.0, 260.0) * (-1.0 if i % 2 == 0 else 1.0)
		_add_boat(xf4.origin + xf4.basis.x * lat4, rng.randf() * TAU)

	# Drifting bergs scattered across the whole bay: faceted low-poly
	# silhouettes riding the swell, each with a foam collar at the waterline.
	# 8 distinct seeded meshes reused across instances (cached in VisualLibrary).
	var berg_mat := VisualLibrary.ice_material(Color(0.82, 0.91, 1.0), 0.55)
	for i: int in 24:
		var o5 := rng.randf_range(0.0, main_guide.length)
		var xf5 := main_guide.transform_at(o5)
		var lat5 := rng.randf_range(55.0, 320.0) * (1.0 if rng.randf() > 0.5 else -1.0)
		var bpos5 := xf5.origin + xf5.basis.x * lat5
		var berg := MeshInstance3D.new()
		berg.mesh = VisualLibrary.berg_mesh(rng.randi_range(0, 7))
		berg.material_override = berg_mat
		var s := rng.randf_range(4.0, 11.0)
		berg.scale = Vector3(s * rng.randf_range(0.9, 1.4), s * rng.randf_range(0.45, 0.8), s)
		berg.position = Vector3(bpos5.x, OCEAN_Y - s * 0.08, bpos5.z)
		berg.rotation.y = rng.randf() * TAU
		add_child(berg)
		if i % 3 == 0:
			_bobbers.append({"node": berg, "base_y": berg.position.y, "phase": rng.randf() * TAU, "amp": 0.12, "speed": 0.5})
		if not headless:
			for k: int in 5:
				var ang := TAU * (float(k) + rng.randf() * 0.7) / 5.0
				# Berg base radius in world = mesh base (0.7-1.25) * x-scale
				# (0.9-1.4)s; keep the collar at/just outside that so blobs
				# poke out from under every silhouette instead of hiding inside.
				var ring_r := s * rng.randf_range(1.1, 1.45)
				_foam_quad(Vector3(bpos5.x + cos(ang) * ring_r, OCEAN_Y + 0.5, bpos5.z + sin(ang) * ring_r),
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
func _cool_track_materials() -> void:
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
			if surface == SNOW:
				floor_mesh.material_override = VisualLibrary.snow_material(TRACK_SNOW_TINT, 0.55)
			elif surface == ICE:
				floor_mesh.material_override = VisualLibrary.ice_material(TRACK_ICE_TINT, 0.85)
			elif surface == RICE:
				floor_mesh.material_override = VisualLibrary.ice_material(TRACK_RICE_TINT, 0.3)


## Horizon berg clusters, placed relative to the main guide (never the course
## centroid) so every cluster is guaranteed 420m+ off the racing line, plus
## end caps past the start and finish so the skyline wraps. Faceted
## VisualLibrary.berg_mesh silhouettes in azure ice_material: cool blue albedo
## + fresnel rim keeps them reading as ICE under the warm sunrise sun.
func _add_horizon_bergs() -> void:
	if GameConfig.is_headless():
		return
	var berg_mat := VisualLibrary.ice_material(HORIZON_BERG_TINT, 0.45)
	var low_detail := String(SettingsManager.get_setting("display", "particle_quality")) == "low"
	var clusters: Array[Vector3] = []
	var cluster_count := 6
	for i: int in cluster_count:
		var xf := main_guide.transform_at(main_guide.length * (float(i) + 0.5) / float(cluster_count))
		for side: float in [-1.0, 1.0]:
			clusters.append(xf.origin + xf.basis.x * (rng.randf_range(420.0, 640.0) * side))
	var start_dir := (main_guide.position_at(minf(40.0, main_guide.length))
		- main_guide.position_at(0.0)).normalized()
	clusters.append(main_guide.position_at(0.0) - start_dir * rng.randf_range(480.0, 620.0))
	var end_dir := (main_guide.position_at(main_guide.length)
		- main_guide.position_at(maxf(main_guide.length - 40.0, 0.0))).normalized()
	clusters.append(main_guide.position_at(main_guide.length) + end_dir * rng.randf_range(480.0, 620.0))
	for center: Vector3 in clusters:
		var berg_count := rng.randi_range(1, 2) if low_detail else rng.randi_range(2, 3)
		for k: int in berg_count:
			var berg := MeshInstance3D.new()
			berg.mesh = VisualLibrary.berg_mesh(rng.randi_range(0, 7))
			berg.material_override = berg_mat
			var s := rng.randf_range(26.0, 54.0)
			berg.scale = Vector3(s * rng.randf_range(0.9, 1.5), s * rng.randf_range(0.5, 0.85), s)
			berg.position = Vector3(center.x + rng.randf_range(-80.0, 80.0),
				OCEAN_Y - s * 0.06, center.z + rng.randf_range(-80.0, 80.0))
			berg.rotation.y = rng.randf() * TAU
			add_child(berg)


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
	# wave_height 0.45 keeps crests under the foam blobs at OCEAN_Y + 0.5;
	# wave_scale 0.08 -> ~46m primary wavelength, ~4 samples per wave at 12m.
	sheet.material_override = VisualLibrary.water_material(OCEAN_DEEP, OCEAN_SHALLOW, 0.45, 0.08)
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


func _add_boat(pos: Vector3, yaw: float) -> void:
	var boat := Node3D.new()
	var hull := MeshInstance3D.new()
	var hull_mesh := BoxMesh.new()
	hull_mesh.size = Vector3(16.0, 2.6, 5.5)
	hull.mesh = hull_mesh
	hull.material_override = TrackBuilder.prop_material(Color(0.9, 0.9, 0.92))
	hull.position.y = 1.1
	boat.add_child(hull)
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
	var antenna := MeshInstance3D.new()
	var ant_mesh := CylinderMesh.new()
	ant_mesh.top_radius = 0.05
	ant_mesh.bottom_radius = 0.08
	ant_mesh.height = 4.0
	antenna.mesh = ant_mesh
	antenna.material_override = TrackBuilder.prop_material(Color(0.4, 0.42, 0.46))
	antenna.position = Vector3(-3.5, 7.2, 0.0)
	boat.add_child(antenna)
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
	boat.position = Vector3(pos.x, OCEAN_Y - 0.4, pos.z)
	boat.rotation.y = yaw
	add_child(boat)
	_bobbers.append({"node": boat, "base_y": boat.position.y, "phase": rng.randf() * TAU, "amp": 0.2, "speed": 0.35})


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
			(child as MeshInstance3D).material_override = VisualLibrary.water_material(
				CHANNEL_DEEP, CHANNEL_SHALLOW, 0.18, 0.35)
			return


## Append one flat foam blob (soft radial quad) to the batched foam surface.
## World-space, random spin, laid flat; call only between the SurfaceTool
## begin in _decorate and _commit_foam.
func _foam_quad(pos: Vector3, size: float) -> void:
	if _foam_st == null:
		return
	var ang := rng.randf() * TAU
	var half := size * 0.5
	var ax := Vector3(cos(ang), 0.0, sin(ang)) * half
	var az := Vector3(-sin(ang), 0.0, cos(ang)) * half
	var a := pos - ax - az
	var b := pos + ax - az
	var c := pos + ax + az
	var d := pos - ax + az
	_foam_st.set_uv(Vector2(0.0, 0.0))
	_foam_st.add_vertex(a)
	_foam_st.set_uv(Vector2(1.0, 0.0))
	_foam_st.add_vertex(b)
	_foam_st.set_uv(Vector2(1.0, 1.0))
	_foam_st.add_vertex(c)
	_foam_st.set_uv(Vector2(0.0, 0.0))
	_foam_st.add_vertex(a)
	_foam_st.set_uv(Vector2(1.0, 1.0))
	_foam_st.add_vertex(c)
	_foam_st.set_uv(Vector2(0.0, 1.0))
	_foam_st.add_vertex(d)


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
