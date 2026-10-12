extends Node
const Walls = preload("res://scripts/runner/runner_reference_walls.gd")
var checks := 0
var failures := 0

func _ready() -> void:
	var catalog := ArtCatalog.new()
	_check(catalog.reload_manifest() == OK, "real release catalog loads")
	var art := load(RunnerGame.RUNNER_ART_SET_PATH) as RunnerArtSet
	var authored := RunnerTrack.new()
	add_child(authored)
	authored.configure_art(art, catalog)
	authored.setup_golden_slice(20260818, 1)
	var material := Walls.material()
	_check(material == Walls.material() and material.albedo_texture == null,
		"one shared cached material, no new texture")
	_check(material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,
		"opaque wall needs no depth/screen sampling or transparency")
	for id: String in RunnerTrack.DAY_DECK_ASSETS:
		var source := authored._authored_day_meshes[id] as Mesh
		var source_arrays := source.surface_get_arrays(0)
		var mesh := authored._authored_day_mesh(id)
		_check(mesh == Walls.deck_mesh(source) and mesh != source, id + " derivative cached independently")
		_check(source.surface_get_arrays(0) == source_arrays, id + " imported source unchanged")
		_check(mesh.get_surface_count() == 1, id + " keeps one surface/draw family")
		_check(mesh.get_faces().size() <= source.get_faces().size(), id + " does not increase triangle budget")
		_check(mesh.get_aabb().is_equal_approx(source.get_aabb()), id + " original overall envelope preserved")
		_check(_protected_faces(mesh, false) == _protected_faces(source, false), id + " playable deck geometry untouched")
		_check(_protected_faces(mesh, true) == _protected_faces(source, true), id + " original snow/cap geometry retained")
		_check(ShaderWarmup.has_external_probe(mesh, material, [], RunnerTrack.SHADER_WARMUP_SCOPE),
			id + " exact derived mesh/material registered for warmup")
		_check(_panel_colours(mesh), id + " blue frame and recessed dark insert present")
		print("[runner_reference_walls] %s triangles %d -> %d" % [id,
			source.get_faces().size() / 3, mesh.get_faces().size() / 3])
	var family_count := 0
	var module_count := 0
	var drawn := true
	for node: Node in authored.find_children("AuthoredDeckKerb*", "MultiMeshInstance3D", true, false):
		var instance := node as MultiMeshInstance3D
		family_count += 1
		module_count += instance.multimesh.instance_count
		drawn = drawn and instance.material_override == material \
			and bool(instance.multimesh.mesh.get_meta("runner_reference_walls", false))
		for transform: Transform3D in instance.get_meta("authored_source_transforms", []):
			drawn = drawn and transform.basis.get_scale().is_equal_approx(Vector3.ONE) \
				and is_equal_approx(transform.origin.y, RunnerTrack.AUTHORED_DAY_DECK_Y)
	_check(drawn and family_count == 30 and module_count == 60,
		"real generated DAY draws three unchanged cassette families and exact placements")
	var signature := _gameplay_signature(authored)
	var fallback := RunnerTrack.new()
	add_child(fallback)
	fallback.setup_golden_slice(20260818, 1)
	_check(_gameplay_signature(fallback) == signature, "authored/fallback hazards, fish and powerups identical")
	var verge := RunnerTrack._verge_mesh()
	_check(verge.get_surface_count() == 4 and verge.get_faces().size() / 3 <= 1200,
		"fallback retains four surfaces with bounded panel geometry")
	for biome: int in RunnerTrack.BIOME_COUNT:
		var chunk := RunnerTrack.RunnerChunk.new()
		chunk.biome = biome
		fallback._build_deck(chunk, RunnerTrack.Pattern.OPEN)
		var wall := chunk.get_node("Verge") as MeshInstance3D
		_check(wall.mesh == verge and wall.get_active_material(0) == material,
			"fallback biome %d uses cached blue panel mesh/material" % biome)
		_check(chunk.find_children("*", "CollisionObject3D", true, false).is_empty(),
			"wall presentation adds no collider in biome %d" % biome)
		chunk.free()
	var count := Walls._decks.size()
	var probes := ShaderWarmup.external_probe_count(RunnerTrack.SHADER_WARMUP_SCOPE)
	for retry: int in 3:
		authored.setup_golden_slice(20260818, 1)
		_check(Walls._decks.size() == count and count == 3, "retry keeps exactly three derived cached decks")
		_check(_gameplay_signature(authored) == signature, "retry seeded collision/pickup signature preserved")
		_check(ShaderWarmup.external_probe_count(RunnerTrack.SHADER_WARMUP_SCOPE) == probes,
			"retry warmup registrations remain bounded")
		await get_tree().process_frame
	authored.free()
	fallback.free()
	await get_tree().process_frame
	print("[runner_reference_walls] %d/%d passed" % [checks - failures, checks])
	get_tree().quit(1 if failures else 0)

func _protected_faces(mesh: Mesh, snow: bool) -> PackedStringArray:
	var result := PackedStringArray()
	var faces := mesh.get_faces()
	for i: int in range(0, faces.size(), 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		var protected := minf(a.y, minf(b.y, c.y)) >= 1.445 if snow else \
			maxf(absf(a.x), maxf(absf(b.x), absf(c.x))) <= 5.29
		if protected:
			result.append("%s|%s|%s" % [a, b, c])
	result.sort()
	return result

func _panel_colours(mesh: Mesh) -> bool:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var blue := 0
	var dark := 0
	for i: int in vertices.size():
		var v := vertices[i]
		var c := colours[i].linear_to_srgb()
		if is_equal_approx(absf(v.x), 5.40) and v.y > 0.90 and v.y < 1.44:
			if c.b > c.r * 1.8 and c.b > 0.5: blue += 1
		if is_equal_approx(absf(v.x), 5.505) and v.y > 0.30 and v.y < 0.90:
			if c.b > c.r and c.b < 0.4: dark += 1
	return blue > 0 and dark > 0

func _gameplay_signature(root: Node) -> PackedStringArray:
	var result := PackedStringArray()
	for node: Node in root.find_children("*", "Area3D", true, false):
		var area := node as Area3D
		var family := ""
		for group: StringName in [RunnerConfig.GROUP_HAZARD, RunnerConfig.GROUP_PICKUP, RunnerConfig.GROUP_POWERUP]:
			if area.is_in_group(group): family = String(group)
		if not family.is_empty():
			result.append("%s|%s|%s|%s|%s" % [family, area.get_meta("kind", ""),
				area.get_meta("powerup", ""), area.global_position, area.get_child(0).shape])
	result.sort()
	return result

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[runner_reference_walls] " + label)
