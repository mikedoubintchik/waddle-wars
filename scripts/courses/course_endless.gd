class_name CourseEndless
extends CourseBase
## ENDLESS EXPEDITION: a long course assembled from reusable segment
## templates with a deterministic seed. Difficulty ramps with distance; a
## blizzard storm front chases the racers (see EndlessManager).

const SNOW := SurfacesDB.Surface.PACKED_SNOW
const DEEP := SurfacesDB.Surface.DEEP_SNOW
const ICE := SurfacesDB.Surface.ICE_SMOOTH
const RICE := SurfacesDB.Surface.ICE_ROUGH

## 0 = randomize per run; tests set a fixed value for determinism.
static var run_seed: int = 0

const SEGMENT_COUNT: int = 26

var _cursor: Vector3 = Vector3(0, 110, 30)
var _heading: float = 0.0  # yaw; 0 = -Z
var _pts: Array = []
var _post_build: Array[Callable] = []

## Rolling-terrain state: a slow sine swell (~±4.5m over ~570m wavelength)
## layered onto every segment's height so the expedition undulates instead of
## descending on a ruler. Driven purely by accumulated distance — fully
## deterministic per seed, and no extra rng draws (segment rolls stay
## byte-identical for a given run_seed).
const ROLL_AMPLITUDE: float = 4.5
const ROLL_FREQUENCY: float = 0.011  # rad per meter of course distance
var _roll_distance: float = 0.0
var _roll_prev: float = 0.0


func _init() -> void:
	course_id = "endless"


static func p2(pos: Vector3, extra: Dictionary = {}) -> Dictionary:
	var d := {"pos": pos}
	d.merge(extra)
	return d


func _advance(forward: float, lateral: float, drop: float, extra: Dictionary = {}) -> void:
	# Bounded wander keeps the course from self-intersecting.
	var turn := atan2(lateral, forward)
	_heading = clampf(_heading + turn, deg_to_rad(-38.0), deg_to_rad(38.0))
	var dist := Vector2(forward, lateral).length()
	_cursor += Vector3(-sin(_heading), 0.0, -cos(_heading)) * dist
	_cursor.y -= drop
	# Mild rolling swell on top of the segment's own drop. Applied as the
	# delta of an absolute sine so the roll never accumulates: worst-case
	# extra grade is ~ROLL_AMPLITUDE*ROLL_FREQUENCY (~2.8 degrees) on top of
	# the steepest segment (downhill, ~6.7 degrees) — well under the AI cap.
	_roll_distance += dist
	var roll := sin(_roll_distance * ROLL_FREQUENCY) * ROLL_AMPLITUDE
	_cursor.y += roll - _roll_prev
	_roll_prev = roll
	_pts.append(p2(_cursor, extra))


func build_course() -> void:
	var seed_value := run_seed if run_seed != 0 else int(Time.get_unix_time_from_system())
	rng.seed = seed_value

	_pts.append(p2(_cursor, {"width": 20.0}))
	_advance(60, 0, 1, {"width": 20.0})

	var segments: Array[String] = ["straight", "scurve", "downhill"]
	var pool_easy: Array[String] = ["straight", "scurve", "downhill", "boost_runway", "slalom"]
	var pool_mid: Array[String] = ["scurve", "downhill", "slalom", "tunnel", "climb", "geyser_field", "boost_runway"]
	var pool_hard: Array[String] = ["downhill", "tunnel", "snowball_alley", "icicle_run", "seal_crossing", "geyser_field", "slalom", "climb"]
	while segments.size() < SEGMENT_COUNT:
		var tier := segments.size() / 6
		var pool := pool_easy if tier == 0 else (pool_mid if tier == 1 else pool_hard)
		segments.append(pool[rng.randi_range(0, pool.size() - 1)])

	for i: int in segments.size():
		_build_segment(segments[i], 1.0 + float(i) * 0.05)
	_advance(120, 0, 2, {"width": 20.0})

	setup_main(_pts)
	finalize()
	for hook: Callable in _post_build:
		hook.call()

	# Fish and items sprinkled along the whole run.
	var offset := 100.0
	while offset < main_guide.length - 100.0:
		if rng.randf() < 0.65:
			add_fish_line(offset, rng.randi_range(5, 9), 5.0, rng.randf_range(-4.0, 4.0))
		if fmod(offset, 400.0) < 160.0:
			add_item_row(offset + 60.0)
		elif fmod(offset, 400.0) > 240.0:
			add_snowball_row(offset + 30.0)  # no rng draws: seed determinism kept
		offset += 170.0

	_decorate()
	build_environment({
		"sky_top": Color(0.2, 0.5, 0.86),
		"sky_horizon": Color(0.82, 0.92, 1.0),
		"ground_color": Color(0.85, 0.92, 0.98),
		"sun_angle_deg": -44.0,
		"sun_energy": 1.25,
		"fog_color": Color(0.82, 0.9, 1.0),
		"fog_density": 0.0018,
		"snow": true,
	})
	var lowest := INF
	for point: Vector3 in main_guide.points:
		lowest = minf(lowest, point.y)
	add_ground_plane(lowest - 18.0, Color(0.88, 0.93, 0.98))


func _build_segment(kind: String, intensity: float) -> void:
	match kind:
		"straight":
			# Front half packed snow, back half a smooth-ice patch: recurring
			# slide rewards on straights. rng draw order/count unchanged so
			# segment rolls stay byte-identical for a given run_seed. A point's
			# dict governs the span it STARTS (build_ribbon span [i, i+1) uses
			# points[i]), so ICE rides the mid point, not the end point.
			var fwd := rng.randf_range(90, 130)
			var lat := rng.randf_range(-15, 15)
			var drop := rng.randf_range(2, 5)
			_advance(fwd * 0.55, lat, drop * 0.55, {"width": 18.0, "surface": ICE})
			_advance(fwd * 0.45, 0, drop * 0.45, {"width": 18.0})
			var ice_start: Vector3 = _pts[_pts.size() - 2]["pos"]
			_post_build.append(func() -> void:
				var o := float(main_guide.nearest(ice_start, -1)["offset"])
				add_hint(o - 5.0, "slide", o + fwd * 0.45))
		"scurve":
			var side := 1.0 if rng.randf() > 0.5 else -1.0
			_advance(70, 35 * side, 3, {"width": 16.0})
			_advance(70, -35 * side, 3, {"width": 16.0})
			# Acceleration pad rewarding a clean S: placed mid-way down the
			# second sweep (its straightest stretch, pointing down-track)
			# rather than at the exit point, where the smoothed bend into the
			# next segment is still underway and boosted AI overshot into the
			# walls. Placement math only — zero rng draws, so segment rolls
			# stay byte-identical for a given run_seed.
			var exit_pos := _cursor
			_post_build.append(func() -> void:
				var o := float(main_guide.nearest(exit_pos, -1)["offset"])
				TrackBuilder.add_boost_pad(self, main_guide, o - 35.0))
		"downhill":
			_advance(60, rng.randf_range(-10, 10), 4, {"width": 18.0, "surface": ICE})
			var start := _cursor
			_advance(120, rng.randf_range(-20, 20), 14, {"width": 18.0, "surface": ICE})
			_post_build.append(func() -> void:
				var o := float(main_guide.nearest(start, -1)["offset"])
				add_hint(o - 20.0, "slide", o + 160.0)
				# Pad at the drop-in launches the slide.
				TrackBuilder.add_boost_pad(self, main_guide, o + 6.0))
		"climb":
			# Acceleration pad at the uphill start helps carry speed into the
			# deep-snow grind.
			var base := _cursor
			_advance(90, rng.randf_range(-10, 10), -5, {"width": 14.0, "surface": DEEP})
			_advance(50, 0, 1, {"width": 16.0})
			_post_build.append(func() -> void:
				var o := float(main_guide.nearest(base, -1)["offset"])
				TrackBuilder.add_boost_pad(self, main_guide, o + 8.0))
		"slalom":
			var side := 1.0 if rng.randf() > 0.5 else -1.0
			for i: int in 3:
				_advance(45, 24 * side, 2, {"width": 12.0, "surface": RICE})
				side = -side
			var pos := _cursor
			_post_build.append(func() -> void:
				var xform := main_guide.transform_at(float(main_guide.nearest(pos, -1)["offset"]))
				for s: float in [-1.0, 1.0]:
					TrackBuilder.add_ice_crystal(self, xform.origin + xform.basis.x * (8.0 * s), rng.randf_range(2.5, 5.0)))
		"tunnel":
			_advance(50, 0, 2, {"width": 11.0, "surface": ICE})
			var start := _cursor
			_advance(60, 0, 2, {"width": 11.0, "surface": ICE})
			_post_build.append(func() -> void:
				var o := float(main_guide.nearest(start, -1)["offset"])
				TrackBuilder.add_overhead_bar(self, main_guide, o + 8.0)
				TrackBuilder.add_overhead_bar(self, main_guide, o + 34.0)
				add_hint(o - 35.0, "slide", o + 55.0))
		"geyser_field":
			var start := _cursor
			_advance(130, rng.randf_range(-12, 12), 5, {"width": 20.0})
			_post_build.append(func() -> void:
				var o := float(main_guide.nearest(start, -1)["offset"])
				for i: int in 4:
					var geyser := HazardGeyser.new()
					geyser.phase_offset = rng.randf() * 3.0
					geyser.position = main_guide.point_at(o + 20.0 + float(i) * 26.0, rng.randf_range(-6.0, 6.0), 0.0)
					add_child(geyser))
		"snowball_alley":
			var start := _cursor
			_advance(160, rng.randf_range(-14, 14), 8, {"width": 20.0})
			var end := _cursor
			_post_build.append(func() -> void:
				var o1 := float(main_guide.nearest(start, -1)["offset"])
				var o2 := float(main_guide.nearest(end, -1)["offset"])
				var ball := HazardSnowball.new()
				ball.configure(main_guide, o1, o2, rng.randf_range(-4.0, 4.0), 13.0 * intensity)
				add_child(ball)
				add_hint(o1 - 30.0, "danger_left" if rng.randf() > 0.5 else "danger_right", o2))
		"icicle_run":
			var start := _cursor
			_advance(110, rng.randf_range(-10, 10), 4, {"width": 14.0, "surface": RICE})
			_post_build.append(func() -> void:
				var o := float(main_guide.nearest(start, -1)["offset"])
				for i: int in 5:
					var icicle := HazardIcicle.new()
					icicle.position = main_guide.point_at(o + 12.0 + float(i) * 20.0, rng.randf_range(-5.0, 5.0), 7.0)
					add_child(icicle))
		"seal_crossing":
			var start := _cursor
			_advance(90, 0, 3, {"width": 20.0, "surface": ICE})
			_post_build.append(func() -> void:
				var o := float(main_guide.nearest(start, -1)["offset"])
				for i: int in 2:
					var seal := HazardSeal.new()
					seal.configure(main_guide, o + 25.0 + float(i) * 30.0, 7.0, 3.5 + intensity)
					add_child(seal))
		"boost_runway":
			var start := _cursor
			_advance(110, rng.randf_range(-8, 8), 6, {"width": 16.0, "surface": ICE})
			_post_build.append(func() -> void:
				var o := float(main_guide.nearest(start, -1)["offset"])
				TrackBuilder.add_boost_pad(self, main_guide, o + 25.0, -3.0)
				TrackBuilder.add_boost_pad(self, main_guide, o + 55.0, 3.0)
				add_fish_line(o + 20.0, 8, 5.0, 0.0, 1.5))


## Glacier-family dressing density: route flags/rocks, wind-blown snowbank
## drifts and calved ice boulders lining the whole expedition (MultiMesh, one
## draw call each), spectators bookending start and finish, and two layered
## silhouette rings of craggy peaks following the wandering corridor instead
## of the old bare cone ring. Runs after every gameplay rng draw, so seeded
## segment layouts stay byte-identical. Skipped headless (visual only).
func _decorate() -> void:
	if GameConfig.is_headless():
		return
	var quality := String(SettingsManager.get_setting("display", "particle_quality"))
	var density := 1.0
	if quality == "medium":
		density = 0.75
	elif quality == "low":
		density = 0.5

	var offset := 80.0
	var side := 1.0
	while offset < main_guide.length - 80.0:
		var xform := main_guide.transform_at(offset)
		var lateral := (12.0 + rng.randf_range(0.0, 4.0)) * side
		if rng.randf() > 0.5:
			TrackBuilder.add_flag(self, xform.origin + xform.basis.x * lateral, Color(0.9, 0.3, 0.3) if side > 0 else Color(0.25, 0.5, 0.9))
		else:
			TrackBuilder.add_rock(self, xform.origin + xform.basis.x * (lateral + 4.0) + Vector3.DOWN, rng.randf_range(0.8, 1.6), rng)
		side = -side
		offset += 90.0

	_decorate_mountains()
	_decorate_horizon_bands()
	_decorate_snowbanks(density)
	_decorate_boulders(density)

	# Expedition send-off and welcome crowds.
	for i: int in maxi(int(10.0 * density), 4):
		var near_start := main_guide.transform_at(rng.randf_range(10.0, 80.0))
		var lat := (11.5 + rng.randf_range(0.0, 5.0)) * (1.0 if i % 2 == 0 else -1.0)
		TrackBuilder.add_spectator(self, near_start.origin + near_start.basis.x * lat, near_start.origin, rng)
	for i: int in maxi(int(7.0 * density), 3):
		var near_finish := main_guide.transform_at(finish_offset - rng.randf_range(5.0, 60.0))
		var lat := (11.5 + rng.randf_range(0.0, 5.0)) * (1.0 if i % 2 == 0 else -1.0)
		TrackBuilder.add_spectator(self, near_finish.origin + near_finish.basis.x * lat, near_finish.origin, rng)


## Two silhouette rings anchored along the wandering guide (never a fixed
## world ring — the seeded course can drift anywhere): a near ring of craggy
## faceted peaks and a far, paler hazed ring behind it. Rejection sampling
## keeps every peak clear of the racing line; shadows off (backdrop only).
func _decorate_mountains() -> void:
	var near_mat := VisualLibrary.rock_material(Color(1.0, 1.0, 1.0))
	var far_mat := TrackBuilder.prop_material(Color(0.84, 0.9, 0.98), 0.9)
	for _i: int in 12:
		_place_peak(near_mat, 260.0, 470.0, 90.0, 170.0, 120.0, 240.0)
	for _i: int in 10:
		_place_peak(far_mat, 560.0, 900.0, 150.0, 260.0, 200.0, 380.0)


func _place_peak(mat: Material, lat_min: float, lat_max: float, w_min: float, w_max: float,
		h_min: float, h_max: float) -> void:
	for _attempt: int in 8:
		var anchor := main_guide.transform_at(rng.randf_range(0.0, main_guide.length))
		var side := 1.0 if rng.randf() > 0.5 else -1.0
		var width := rng.randf_range(w_min, w_max)
		var pos := anchor.origin + anchor.basis.x * (rng.randf_range(lat_min, lat_max) * side)
		# The wandering corridor can loop back near any world point: demand
		# clearance from the WHOLE guide, not just the anchor span.
		if float(main_guide.nearest(pos, -1)["distance"]) < width * 1.5 + 40.0:
			continue
		var peak := MeshInstance3D.new()
		peak.mesh = VisualLibrary.berg_mesh(rng.randi())
		peak.material_override = mat
		peak.scale = Vector3(width * rng.randf_range(0.9, 1.4), rng.randf_range(h_min, h_max), width)
		var lowest := INF
		for point: Vector3 in main_guide.points:
			lowest = minf(lowest, point.y)
		peak.position = Vector3(pos.x, lowest - 18.0, pos.z)
		peak.rotation.y = rng.randf() * TAU
		peak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(peak)
		return


## Per-biome horizon bands: the 26-segment expedition crosses three difficulty
## tiers, so each third of the run gets its own horizon character — bright
## sunlit foothills over the easy opening, a paler hazed high range mid-run,
## and dark storm-shadowed massifs plus lit ice spires over the hard final
## third (the deepening skyline foreshadows the blizzard chasing the run).
## One shared seeded silhouette + one cached material per band (a MultiMesh
## draw call each); rejection sampling keeps everything far off the wandering
## corridor; counts scale with display/quality_preset (low ~40% of high).
func _decorate_horizon_bands() -> void:
	var quality := String(SettingsManager.get_setting("display", "quality_preset"))
	var q := 1.0
	if quality == "medium":
		q = 0.7
	elif quality == "low":
		q = 0.4
	var lowest := INF
	for point: Vector3 in main_guide.points:
		lowest = minf(lowest, point.y)
	var third := main_guide.length / 3.0
	var bands: Array[Dictionary] = [
		{"span": Vector2(0.0, third), "mesh_seed": 31, "count": 10,
			"tint": Color(0.92, 0.95, 1.0), "lat": Vector2(420.0, 640.0),
			"w": Vector2(70.0, 150.0), "h": Vector2(90.0, 200.0)},
		{"span": Vector2(third, third * 2.0), "mesh_seed": 32, "count": 9,
			"tint": Color(0.66, 0.76, 0.92), "lat": Vector2(560.0, 820.0),
			"w": Vector2(110.0, 210.0), "h": Vector2(160.0, 300.0)},
		{"span": Vector2(third * 2.0, main_guide.length), "mesh_seed": 33, "count": 8,
			"tint": Color(0.44, 0.52, 0.68), "lat": Vector2(640.0, 940.0),
			"w": Vector2(150.0, 260.0), "h": Vector2(220.0, 380.0)},
	]
	for b_i: int in bands.size():
		var band: Dictionary = bands[b_i]
		var span: Vector2 = band["span"]
		var lat: Vector2 = band["lat"]
		var w_range: Vector2 = band["w"]
		var h_range: Vector2 = band["h"]
		var tint: Color = band["tint"]
		var transforms: Array[Transform3D] = []
		for _i: int in maxi(int(float(band["count"]) * q), 3):
			for _attempt: int in 8:
				var anchor := main_guide.transform_at(rng.randf_range(span.x, span.y))
				var side := 1.0 if rng.randf() > 0.5 else -1.0
				var width := rng.randf_range(w_range.x, w_range.y)
				var pos := anchor.origin + anchor.basis.x * (rng.randf_range(lat.x, lat.y) * side)
				if float(main_guide.nearest(pos, -1)["distance"]) < width * 1.7 + 60.0:
					continue
				var peak_basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(
					Vector3(width * rng.randf_range(0.9, 1.4), rng.randf_range(h_range.x, h_range.y), width))
				transforms.append(Transform3D(peak_basis, Vector3(pos.x, lowest - 20.0, pos.z)))
				break
		_add_multimesh(VisualLibrary.berg_mesh(int(band["mesh_seed"])), transforms,
			VisualLibrary.rock_material(tint), "HorizonBand_%d" % b_i, 2400.0)
	# Final-third biome accent: pale ice spires glinting between the dark
	# massifs — a colder, stranger horizon as the difficulty (and the storm)
	# closes in. Shared crystal mesh, one cached glossy material.
	var spire_transforms: Array[Transform3D] = []
	for _i: int in maxi(int(8.0 * q), 3):
		for _attempt: int in 8:
			var anchor := main_guide.transform_at(rng.randf_range(third * 2.0, main_guide.length - 10.0))
			var side := 1.0 if rng.randf() > 0.5 else -1.0
			var pos := anchor.origin + anchor.basis.x * (rng.randf_range(240.0, 420.0) * side)
			if float(main_guide.nearest(pos, -1)["distance"]) < 120.0:
				continue
			var h := rng.randf_range(24.0, 46.0)
			var spire_basis := Basis(Vector3.UP, rng.randf() * TAU) \
				* Basis.from_scale(Vector3(h * 0.5, h, h * 0.5))
			spire_transforms.append(Transform3D(spire_basis, Vector3(pos.x, lowest - 16.0, pos.z)))
			break
	_add_multimesh(VisualLibrary.ice_crystal_mesh(), spire_transforms,
		VisualLibrary.rock_material(Color(0.6, 0.76, 0.94), 0.35), "HorizonSpires", 1600.0)


## Wind-blown snowbank drifts hugging both track flanks along the whole run —
## the glacier course's density pattern, one MultiMesh draw call.
func _decorate_snowbanks(density: float) -> void:
	var transforms: Array[Transform3D] = []
	var step := 15.0 / density
	var offset := 30.0
	var side := 1.0
	while offset < main_guide.length - 30.0:
		var xform := main_guide.transform_at(offset)
		var lateral := (13.0 + rng.randf_range(0.0, 5.5)) * side
		var r := rng.randf_range(1.5, 3.4)
		var bank_basis := Basis(Vector3.UP, rng.randf() * TAU) \
			* Basis.from_scale(Vector3(
				r * rng.randf_range(1.4, 2.2), r * rng.randf_range(0.5, 0.8), r * rng.randf_range(0.7, 1.0)))
		transforms.append(Transform3D(bank_basis, xform.origin + xform.basis.x * lateral + Vector3.DOWN * 0.4))
		side = -side
		offset += step
	_add_multimesh(VisualLibrary.snow_drift_mesh(), transforms,
		VisualLibrary.rock_material(Color(1.0, 1.0, 1.0)), "Snowbanks")


## Calved ice boulders in the smooth-ice track shader (crack veins + sun
## streak; its frost border is gated off non-track meshes), tumbled just off
## both edges. One MultiMesh draw call.
func _decorate_boulders(density: float) -> void:
	var transforms: Array[Transform3D] = []
	for _i: int in int(18.0 * density):
		var offset := rng.randf_range(60.0, main_guide.length - 70.0)
		var xform := main_guide.transform_at(offset)
		var lateral := rng.randf_range(12.0, 20.0) * (1.0 if rng.randf() > 0.5 else -1.0)
		var s := rng.randf_range(0.9, 2.3)
		var boulder_basis := Basis.from_euler(Vector3(
			rng.randf_range(-0.35, 0.35), rng.randf() * TAU, rng.randf_range(-0.35, 0.35))) \
			* Basis.from_scale(Vector3(
				s * rng.randf_range(0.85, 1.3), s * rng.randf_range(0.5, 0.85), s * rng.randf_range(0.85, 1.3)))
		transforms.append(Transform3D(boulder_basis,
			xform.origin + xform.basis.x * lateral + Vector3.DOWN * rng.randf_range(0.4, 0.9)))
	_add_multimesh(VisualLibrary.berg_mesh(11), transforms,
		TrackBuilder.surface_material(SurfacesDB.Surface.ICE_SMOOTH), "IceBoulders")


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


## Entry point used by race.gd for Mode.ENDLESS.
func run_endless(race_root: Node3D, powerups: PowerupSystem) -> void:
	var manager := EndlessManager.new()
	race_root.add_child(manager)
	manager.setup(self, powerups, false)
	var camera_rig := ChaseCamera.new()
	race_root.add_child(camera_rig)
	camera_rig.attach_to(manager.player)
	if not GameConfig.is_headless():
		camera_rig.camera.make_current()
	var hud := RaceHUD.new()
	race_root.add_child(hud)
	hud.setup(manager, manager.player)
	manager.hud = hud
	race_root.add_child(PauseMenu.new())
	if SettingsManager.touch_controls_enabled():
		var touch := TouchControls.new()
		race_root.add_child(touch)
		# Player.setup is deferred by RaceManager, so controller is still null
		# here; defer the wire-up so it runs after the controller exists
		# (same pattern as race.gd).
		_setup_touch_deferred.call_deferred(touch, manager)
	AudioManager.play_music("music_race")


## Runs after RaceManager's deferred player.setup, so the controller exists.
func _setup_touch_deferred(touch: TouchControls, manager: EndlessManager) -> void:
	touch.setup(manager.player.controller as PlayerController)
