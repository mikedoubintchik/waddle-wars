class_name CourseTutorial
extends CourseBase
## WADDLE SCHOOL: a short guided course teaching steering, jumping, sliding,
## surfaces, shoving, items, checkpoints, and finishing — all through real
## gameplay with signposted practice zones. Dressed as a friendly schoolyard:
## warm bright light, festive banner arches in each lesson's accent color,
## soft drift banks and ice-crystal scatter beside the line.

const SNOW := SurfacesDB.Surface.PACKED_SNOW
const DEEP := SurfacesDB.Surface.DEEP_SNOW
const ICE := SurfacesDB.Surface.ICE_SMOOTH


func _init() -> void:
	course_id = "tutorial"


static func p(x: float, y: float, z: float, extra: Dictionary = {}) -> Dictionary:
	var d := {"pos": Vector3(x, y, z)}
	d.merge(extra)
	return d


func build_course() -> void:
	var pts: Array = [
		p(0, 20, 30, {"width": 18.0}),
		p(0, 20, -30, {"width": 18.0}),        # steering slalom zone
		p(-12, 19, -90, {"width": 18.0}),
		p(10, 18, -150, {"width": 18.0}),
		p(0, 17, -210, {"width": 16.0}),       # jump zone (bar hops)
		p(0, 16, -280, {"width": 14.0}),       # slide tunnel zone
		p(0, 15, -340, {"width": 14.0, "surface": ICE}),   # ice showcase
		p(0, 14.5, -400, {"width": 14.0, "surface": DEEP}),  # deep snow showcase
		p(0, 13, -450, {"width": 18.0}),       # shove practice
		p(0, 11, -520, {"width": 18.0}),       # item practice
		p(0, 8, -600, {"width": 18.0, "surface": ICE}),  # final slide
		p(0, 6, -660, {"width": 18.0}),
		p(0, 6, -700, {"width": 18.0}),
	]
	setup_main(pts)
	finalize()

	# Slalom gates (poles planted on the deck rather than resting exactly on it).
	for gate: Array in [[80.0, -4.0], [110.0, 4.0], [140.0, -4.0]]:
		var xform := main_guide.transform_at(float(gate[0]))
		TrackBuilder.add_flag(self, seat_dressing(xform, float(gate[1]) - 2.5, 3.0), Color(0.3, 0.8, 0.4))
		TrackBuilder.add_flag(self, seat_dressing(xform, float(gate[1]) + 2.5, 3.0), Color(0.3, 0.8, 0.4))

	# Jump bars: low walls to hop over (thin, forgiving).
	var jump_offset := _offset_near(Vector3(0, 17, -210))
	for i: int in 2:
		var bar := StaticBody3D.new()
		bar.collision_layer = GameConfig.LAYER_WORLD
		bar.collision_mask = 0
		var mesh := BoxMesh.new()
		mesh.size = Vector3(14.0, 0.5, 0.5)
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = TrackBuilder.prop_material(Color(0.85, 0.4, 0.3))
		bar.add_child(instance)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = mesh.size
		shape.shape = box
		bar.add_child(shape)
		var xform := main_guide.transform_at(jump_offset + float(i) * 26.0)
		bar.transform = Transform3D(xform.basis, xform.origin + Vector3.UP * 0.3)
		add_child(bar)
		add_hint(jump_offset + float(i) * 26.0 - 12.0, "jump")

	# Slide tunnel.
	var tunnel_offset := _offset_near(Vector3(0, 16, -280))
	TrackBuilder.add_overhead_bar(self, main_guide, tunnel_offset)
	TrackBuilder.add_overhead_bar(self, main_guide, tunnel_offset + 18.0)
	add_hint(tunnel_offset - 35.0, "slide", tunnel_offset + 30.0)

	# Item box row for the item lesson.
	add_item_row(_offset_near(Vector3(0, 11, -520)) - 20.0)
	add_fish_line(60.0, 6, 5.0, 0.0)
	add_fish_line(_offset_near(Vector3(0, 15, -340)), 8, 5.0, 0.0)
	add_fish_line(_offset_near(Vector3(0, 8, -600)), 8, 5.0, 0.0)
	add_hint(_offset_near(Vector3(0, 8, -600)) - 10.0, "slide", _offset_near(Vector3(0, 6, -660)))

	# Ice sheet below the schoolyard ridge. Laid down before the dressing runs
	# so every far-field prop can seat itself on it (see CourseBase.ground_plane_y).
	add_ground_plane(-10.0, Color(0.9, 0.94, 0.99), 4000.0,
		VisualLibrary.snow_material(Color(0.9, 0.94, 0.99), 0.4))

	# Friendly scenery.
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 7
	for i: int in 8:
		var offset := rng2.randf_range(20.0, main_guide.length - 40.0)
		var xform := main_guide.transform_at(offset)
		var side := 1.0 if i % 2 == 0 else -1.0
		var lateral := (track_edge_lateral(main_guide, offset, side, 10.0) + 1.4) * side
		TrackBuilder.add_spectator(self, seat_dressing(xform, lateral, 1.6, GROUND_SHOULDER, 0.05),
			xform.origin, rng2)
	_decorate()
	# Warm, friendly schoolyard grade: brighter and gentler than the race
	# courses — pastel morning sky, a soft golden sun, low contrast, light
	# haze, cream clouds and a ring of pale bergs so the horizon isn't empty.
	build_environment({
		"sky_top": Color(0.3, 0.62, 0.94),
		"sky_horizon": Color(0.9, 0.95, 1.0),
		"ground_color": Color(0.62, 0.75, 0.9),
		"sun_angle_deg": -50.0,
		"sun_yaw_deg": -30.0,
		"sun_energy": 1.5,
		"sun_color": Color(1.0, 0.95, 0.84),
		"sky_energy": 1.05,
		"ambient_energy": 1.0,
		"exposure": 1.0,
		"contrast": 1.02,
		"saturation": 1.05,
		"fog_color": Color(0.88, 0.94, 1.0),
		"fog_density": 0.0016,
		"glow_threshold": 1.2,
		"shadow_distance": 120.0,
		"snow": false,
		"clouds": true,
		"cloud_color": Color(1.0, 0.98, 0.92, 0.8),
		"distant_bergs": true,
		"berg_color": Color(0.82, 0.9, 0.98),
		"berg_count": 8,
		"berg_distance": 700.0,
	})


func _offset_near(point: Vector3) -> float:
	return float(main_guide.nearest(point, -1)["offset"])


## --- Decoration -------------------------------------------------------------
## Pure visual dressing, skipped headless (nothing gameplay reads these nodes).
## Everything is shadowless and batched through MultiMeshInstance3D with shared
## cached materials, so the whole pass costs a handful of draw calls; instance
## counts scale with the particle_quality setting.

func _decorate() -> void:
	if GameConfig.is_headless():
		return
	var quality := String(SettingsManager.get_setting("display", "particle_quality"))
	var density := 1.0
	if quality == "medium":
		density = 0.75
	elif quality == "low":
		density = 0.5
	_decorate_stations()
	_decorate_drifts(density)
	_decorate_crystals(density)
	_decorate_boulders(density)


func _add_multimesh(mesh: Mesh, transforms: Array[Transform3D], material: Material, name_hint: String, colors: PackedColorArray = PackedColorArray()) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors.size() > 0
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i: int in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		if i < colors.size():
			mm.set_instance_color(i, colors[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = name_hint
	instance.multimesh = mm
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


## Lesson stations: [offset along the main line, half-span clearing the
## authored track width, festive accent color]. Offsets derive from the same
## anchors the lessons use, so the dressing tracks the gates if the layout
## ever moves. Purely visual — no collision, nothing gameplay reads these.
## Accent colors are shared with TutorialManager's confetti palette.
func _station_list() -> Array:
	return [
		[60.0, 10.0, Color(0.36, 0.8, 0.45)],                                       # steering gates
		[_offset_near(Vector3(0, 17, -210)) - 20.0, 9.3, Color(0.9, 0.45, 0.32)],   # penguin hop
		[_offset_near(Vector3(0, 16, -280)) - 28.0, 8.2, Color(0.42, 0.72, 0.98)],  # belly slide
		[_offset_near(Vector3(0, 15, -340)) - 15.0, 8.2, Color(0.34, 0.83, 0.78)],  # know your snow
		[_offset_near(Vector3(0, 13, -450)) - 18.0, 9.8, Color(0.95, 0.63, 0.27)],  # flipper shove
		[_offset_near(Vector3(0, 11, -520)) - 32.0, 10.0, Color(0.96, 0.77, 0.26)], # power-ups
		[_offset_near(Vector3(0, 8, -600)) - 16.0, 10.0, Color(0.72, 0.52, 0.95)],  # home slide
	]


## Festive banner arch over the track at every lesson station: two wooden
## poles (buried through the skirt so they never float), a pale crossbar with
## gold finials, and a row of hanging pennants alternating the station accent
## with white. Pennants use per-instance MultiMesh colors, so all seven arches
## cost four draw calls total. The crossbar sits ~5m up — far above any jump.
## The span is measured off the real deck edge rather than the authored
## half-span, and the whole arch rides the surface height under its feet, so a
## station never plants its poles in mid-air past a narrowing track.
func _decorate_stations() -> void:
	var pole_transforms: Array[Transform3D] = []
	var bar_transforms: Array[Transform3D] = []
	var finial_transforms: Array[Transform3D] = []
	var pennant_transforms: Array[Transform3D] = []
	var pennant_colors := PackedColorArray()
	for station: Array in _station_list():
		var offset := float(station[0])
		var half := float(station[1])
		var accent: Color = station[2]
		var xform := main_guide.transform_at(offset)
		# Foot span: outside the racing floor on the wider of the two sides so
		# the arch stays symmetric. Falls back to the authored half-span.
		var span := maxf(track_edge_lateral(main_guide, offset, -1.0, half),
			track_edge_lateral(main_guide, offset, 1.0, half)) + 1.0
		# Sink/lift the whole arch onto the surface its feet stand on.
		var lift := dressing_ground(xform, span) - xform.origin.y - 0.15
		var base := xform.origin + xform.basis.y * lift
		for side: float in [-1.0, 1.0]:
			var foot := base + xform.basis.x * (span * side)
			pole_transforms.append(Transform3D(xform.basis, foot + xform.basis.y * 2.0))
			finial_transforms.append(Transform3D(xform.basis, foot + xform.basis.y * 5.6))
		bar_transforms.append(Transform3D(
			xform.basis * Basis.from_scale(Vector3(span * 2.0 + 0.6, 1.0, 1.0)),
			base + xform.basis.y * 5.05))
		var count := maxi(int((half * 2.0 - 1.0) / 0.75), 5)
		for k: int in count:
			var t := (float(k) + 0.5) / float(count) - 0.5
			var lateral := t * (span * 2.0 - 0.6)
			var sway := rng.randf_range(-0.12, 0.12)
			var pennant_basis := xform.basis * Basis(Vector3(0, 0, 1), PI) \
				* Basis(Vector3(0, 1, 0), sway) \
				* Basis.from_scale(Vector3(rng.randf_range(0.9, 1.1), rng.randf_range(0.9, 1.1), 1.0))
			pennant_transforms.append(Transform3D(pennant_basis,
				base + xform.basis.x * lateral + xform.basis.y * 4.62))
			pennant_colors.append(accent if k % 2 == 0 else Color(0.97, 0.98, 1.0))
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.08
	pole_mesh.bottom_radius = 0.11
	pole_mesh.height = 7.0
	pole_mesh.radial_segments = 8
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(1.0, 0.22, 0.22)
	var finial_mesh := SphereMesh.new()
	finial_mesh.radius = 0.14
	finial_mesh.height = 0.28
	finial_mesh.radial_segments = 10
	finial_mesh.rings = 5
	var pennant_mesh := PrismMesh.new()
	pennant_mesh.size = Vector3(0.55, 0.62, 0.05)
	_add_multimesh(pole_mesh, pole_transforms,
		TrackBuilder.prop_material(Color(0.5, 0.35, 0.2)), "StationPoles")
	_add_multimesh(bar_mesh, bar_transforms,
		TrackBuilder.prop_material(Color(0.94, 0.96, 1.0), 0.85), "StationBars")
	_add_multimesh(finial_mesh, finial_transforms,
		TrackBuilder.prop_material(Color(0.85, 0.72, 0.35), 0.4), "StationFinials")
	_add_multimesh(pennant_mesh, pennant_transforms,
		VisualLibrary.rock_material(Color(1.0, 1.0, 1.0)), "StationPennants", pennant_colors)


## Soft drift banks hugging both track edges (plus occasional larger banks
## further out for depth): the schoolyard reads as groomed snow, not a bare
## ribbon in the void. Laterals are measured off the real deck edge and every
## mound is seated on the surface under it — the old constants sat on the deck
## where the track is 18m wide and floated 4m past it where it narrows to 14.
## One multimesh.
func _decorate_drifts(density: float) -> void:
	var transforms: Array[Transform3D] = []
	var step := 16.0 / density
	var offset := 20.0
	var side := 1.0
	while offset < main_guide.length - 20.0:
		var xform := main_guide.transform_at(offset)
		var edge := track_edge_lateral(main_guide, offset, side, 9.0)
		var lateral := (edge + rng.randf_range(0.6, 3.2)) * side
		var r := rng.randf_range(1.5, 3.2)
		var drift_basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(
			r * rng.randf_range(1.3, 2.0), r * rng.randf_range(0.5, 0.75), r * rng.randf_range(0.75, 1.0)))
		# Low mounds hide their own footprint, so they get a generous shoulder.
		transforms.append(Transform3D(drift_basis,
			seat_dressing(xform, lateral, drift_basis.get_scale().y, 5.0, 0.14)))
		if rng.randf() > 0.65:
			var far_r := rng.randf_range(2.2, 4.2)
			var far_basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(
				far_r * rng.randf_range(1.2, 1.8), far_r * 0.55, far_r * rng.randf_range(0.7, 0.9)))
			var far_lateral := lateral + rng.randf_range(1.4, 4.4) * side
			transforms.append(Transform3D(far_basis,
				seat_dressing(xform, far_lateral, far_basis.get_scale().y, 6.0, 0.15)))
		side = -side
		offset += step
	_add_multimesh(VisualLibrary.snow_drift_mesh(), transforms,
		VisualLibrary.rock_material(Color(1.0, 1.0, 1.0)), "SnowDrifts")


## Friendly-scale ice crystal clusters scattered along both sides — garden
## ornaments, not the monoliths of the race courses. One multimesh; cached
## rock_material is shared, so duplicate before tweaking gloss.
func _decorate_crystals(density: float) -> void:
	var transforms: Array[Transform3D] = []
	var count := int(16.0 * density)
	for _i: int in count:
		var offset := rng.randf_range(30.0, main_guide.length - 50.0)
		var xform := main_guide.transform_at(offset)
		var margin := rng.randf_range(1.0, 4.0)
		var side := 1.0 if rng.randf() > 0.5 else -1.0
		var lateral := (track_edge_lateral(main_guide, offset, side, 9.0) + margin) * side
		var height := rng.randf_range(1.4, 3.6)
		var aspect := rng.randf_range(0.55, 0.85)
		var crystal_basis := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(
			height * aspect, height * rng.randf_range(0.85, 1.1), height * aspect))
		transforms.append(Transform3D(crystal_basis,
			seat_dressing(xform, lateral, crystal_basis.get_scale().y, GROUND_SHOULDER, 0.12)))
	var crystal_mat := VisualLibrary.rock_material(Color(0.7, 0.87, 1.0)).duplicate() as StandardMaterial3D
	crystal_mat.roughness = 0.12
	crystal_mat.metallic = 0.05
	_add_multimesh(VisualLibrary.ice_crystal_mesh(), transforms, crystal_mat, "IceCrystals")


## A few calved ice boulders beside the line wearing the smooth-ice track
## shader (its frost border is UV2-gated to track floors, so plain meshes get
## the clean glassy treatment). Shared cached material, one multimesh.
func _decorate_boulders(density: float) -> void:
	var transforms: Array[Transform3D] = []
	var count := maxi(int(9.0 * density), 4)
	for _i: int in count:
		var offset := rng.randf_range(50.0, main_guide.length - 60.0)
		var xform := main_guide.transform_at(offset)
		var side := 1.0 if rng.randf() > 0.5 else -1.0
		var lateral := (track_edge_lateral(main_guide, offset, side, 9.0) + rng.randf_range(1.0, 5.0)) * side
		# Extra bed depth on top of the standard embed: calved blocks settle.
		var sink := rng.randf_range(0.2, 0.6)
		var s := rng.randf_range(1.0, 2.2)
		var boulder_basis := Basis.from_euler(Vector3(
			rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))) \
			* Basis.from_scale(Vector3(
				s * rng.randf_range(0.85, 1.25), s * rng.randf_range(0.5, 0.8), s * rng.randf_range(0.85, 1.25)))
		transforms.append(Transform3D(boulder_basis,
			seat_dressing(xform, lateral, boulder_basis.get_scale().y, 4.5, 0.1) + Vector3.DOWN * sink))
	_add_multimesh(VisualLibrary.berg_mesh(23), transforms,
		TrackBuilder.surface_material(SurfacesDB.Surface.ICE_SMOOTH), "IceBoulders")


## Entry point used by race.gd for Mode.TUTORIAL.
func run_tutorial(race_root: Node3D, powerups: PowerupSystem) -> void:
	var manager := TutorialManager.new()
	race_root.add_child(manager)
	manager.setup_tutorial(self, powerups)
