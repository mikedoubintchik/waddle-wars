class_name CourseIceberg
extends CourseBase
## ICEBERG BAY: open ocean at sunset. Berg-hopping, sliding platform gaps,
## two swim channels, rolling wave ramps, a tilting-slab causeway, sliding
## seals, and a risky narrow berg-chain shortcut. Ocean plane far below.

const SNOW := SurfacesDB.Surface.PACKED_SNOW
const ICE := SurfacesDB.Surface.ICE_SMOOTH
const RICE := SurfacesDB.Surface.ICE_ROUGH

const OCEAN_Y: float = -2.0

var _bobbers: Array[Dictionary] = []  # {node, base_y, phase, amp, speed}
var _bob_time: float = 0.0
## Prefix arclength per baked guide point. PathGuide.nearest() reports offsets
## as index * SAMPLE_SPACING, but Curve3D bakes points DENSER than the bake
## interval (measured avg ~1.4m for this course), so index-space offsets outrun
## true arclength by ~45%. transform_at()/point_at() consume true arclength, so
## anything placed from a nearest() offset lands far ahead of its landmark.
## This table converts: index space (racer progress, hints) <-> arclength
## (geometry placement). See _arc_near()/_offset_near().
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
	# space from PathGuide.nearest). The base class steps in arclength, which
	# racers' inflated index-space progress passes ~45% early — a faller would
	# then respawn at a checkpoint transform hundreds of meters AHEAD of where
	# it actually fell (verified in race_sim: racers skipped the whole swim
	# channel). Offsets below are index space; transforms are true geometry.
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
	add_child(TrackBuilder.build_water(water1_pts, "SwimChannel"))
	var water2_pts: Array = [
		p(2, 4.0, -1412, {"width": 15.0}),
		p(2, 4.0, -1435),
		p(2, 4.0, -1470),
	]
	add_child(TrackBuilder.build_water(water2_pts, "SwimFinale"))

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
	build_environment({
		"sky_top": Color(0.18, 0.16, 0.38),
		"sky_horizon": Color(0.98, 0.62, 0.4),
		"ground_color": Color(0.16, 0.3, 0.44),
		"sun_angle_deg": -15.0,
		"sun_yaw_deg": 40.0,
		"sun_color": Color(1.0, 0.8, 0.6),
		"sun_energy": 1.1,
		"fog_color": Color(0.97, 0.68, 0.52),
		"fog_density": 0.004,
		"snow": false,
	})
	# The ocean IS the ground plane: ~6m below the lowest water surface, well
	# above kill_y so fallers visibly splash toward it before respawning.
	add_ground_plane(OCEAN_Y, Color(0.1, 0.3, 0.45))


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
	# Course-side flags alternating warm sunset colors.
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

	# Buoys bobbing on the open water beside the course.
	for i: int in 8:
		var o2 := 90.0 + float(i) * (main_guide.length - 200.0) / 8.0
		var xf2 := main_guide.transform_at(o2)
		var lat2 := rng.randf_range(26.0, 42.0) * (1.0 if i % 2 == 0 else -1.0)
		_add_buoy(Vector3(xf2.origin.x + xf2.basis.x.x * lat2, OCEAN_Y + 0.6, xf2.origin.z + xf2.basis.x.z * lat2))

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

	# Drifting berg chunks scattered across the whole bay.
	var chunk_mat := TrackBuilder.prop_material(Color(0.92, 0.96, 1.0), 0.85)
	for i: int in 26:
		var o5 := rng.randf_range(0.0, main_guide.length)
		var xf5 := main_guide.transform_at(o5)
		var lat5 := rng.randf_range(55.0, 320.0) * (1.0 if rng.randf() > 0.5 else -1.0)
		var chunk := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(rng.randf_range(5.0, 16.0), rng.randf_range(1.2, 3.0), rng.randf_range(4.0, 12.0))
		chunk.mesh = box
		chunk.material_override = chunk_mat
		chunk.position = xf5.origin + xf5.basis.x * lat5
		chunk.position.y = OCEAN_Y + box.size.y * 0.25
		chunk.rotation.y = rng.randf() * TAU
		chunk.rotation.z = rng.randf_range(-0.06, 0.06)
		add_child(chunk)


func _add_buoy(pos: Vector3) -> void:
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
	ring.material_override = TrackBuilder.prop_material(Color(0.85, 0.2, 0.18))
	ring.position.y = 0.55
	buoy.add_child(ring)
	var light := MeshInstance3D.new()
	var light_mesh := SphereMesh.new()
	light_mesh.radius = 0.22
	light_mesh.height = 0.44
	light.mesh = light_mesh
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(1.0, 0.6, 0.2)
	lm.emission_enabled = true
	lm.emission = Color(1.0, 0.5, 0.15)
	lm.emission_energy_multiplier = 1.4
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
	boat.position = Vector3(pos.x, OCEAN_Y - 0.4, pos.z)
	boat.rotation.y = yaw
	add_child(boat)
	_bobbers.append({"node": boat, "base_y": boat.position.y, "phase": rng.randf() * TAU, "amp": 0.2, "speed": 0.35})
