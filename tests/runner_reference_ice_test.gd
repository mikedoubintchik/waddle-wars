extends Node
const Ice = preload("res://scripts/runner/runner_reference_ice.gd")
var checks := 0
var failures := 0

func _ready() -> void:
	var block := Ice.block_mesh()
	var ridge := Ice.ridge_mesh()
	_check(block == Ice.block_mesh() and ridge == Ice.ridge_mesh(), "obstacle caches stable")
	for item: Array in [[block, Vector3(2.3, 2.0, 1.5)], [ridge, Vector3(1.0, 0.8, 1.15)]]:
		var mesh := item[0] as ArrayMesh
		var size: Vector3 = item[1]
		_check(mesh.get_aabb().size.is_equal_approx(size), "exact collision dimensions")
		_check(is_zero_approx(mesh.get_aabb().position.y), "ground pivot")
		_check(mesh.get_surface_count() == 1 and mesh.surface_get_array_len(0) <= 700,
			"one surface within existing obstacle vertex budget")
		_mesh_integrity(mesh)
		_rounded_snow_boulder(mesh, size)
	var source_scene := load("res://assets/art/runner/day/runner_day_iceberg_cluster_v1.tscn") as PackedScene
	var source_node := source_scene.instantiate()
	var source := RunnerTrack._first_scene_mesh(source_node)
	var sea := Ice.sea_mesh(source)
	_check(sea == Ice.sea_mesh(source), "sea derivative cached across chunks and retries")
	_check(sea.get_faces().size() == source.get_faces().size(), "sea triangle count unchanged")
	_check(sea.get_surface_count() == 1, "sea remains single draw surface")
	_check(sea.get_aabb().size.x > source.get_aabb().size.x and sea.get_aabb().size.y < source.get_aabb().size.y,
		"reference sea silhouette broader and lower than old rounded mass")
	_check(absf(sea.get_aabb().position.y) < 0.02, "sea waterline unchanged")
	_mesh_integrity(sea)
	source_node.free()
	var material := Ice.material()
	_check(material == Ice.material(), "single shared ice material")
	_check(material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED, "opaque without blending or depth textures")
	_check(material.albedo_texture == null and material.vertex_color_use_as_albedo, "ice no longer samples steel atlas")
	_check(RunnerTrack._block_mesh() == block, "BLOCK cache resolves only to reference ice")
	for biome: int in RunnerTrack.BIOME_COUNT:
		for index: int in 6:
			var track := RunnerTrack.new()
			add_child(track)
			track._headless = false
			track._runner_art_set = load(RunnerGame.RUNNER_ART_SET_PATH)
			var chunk := RunnerTrack.RunnerChunk.new()
			chunk.index = index
			chunk.biome = biome
			track.add_child(chunk)
			_check(track._add_obstacle(chunk, RunnerTrack.Kind.BLOCK, 0, 1, -20.0), "live BLOCK placement accepted")
			var area := chunk.get_child(0) as Area3D
			var visual := area.get_child(1) as MeshInstance3D
			var collider := (area.get_child(0) as CollisionShape3D).shape as BoxShape3D
			_check(collider.size == Vector3(2.3, 2.0, 1.5), "BLOCK collider untouched in every biome")
			_check(bool(visual.get_meta("reference_ice_block", false))
				and visual.mesh == block and visual.material_override == material,
				"every BLOCK uses ice geometry/material, never a wooden crate")
			_check(visual.rotation == Vector3.ZERO, "ice follows collision axes")
			_check(track._add_obstacle(chunk, RunnerTrack.Kind.BLOCK, 1, 1, -20.0)
				and not track._add_obstacle(chunk, RunnerTrack.Kind.BLOCK, 2, 1, -20.0),
				"ice replacement preserves mandatory free lane")
			track.free()
	_test_generated_patterns(block, material)
	_test_powerup_pickups()
	await get_tree().process_frame
	print("[runner_reference_ice] %d/%d passed; sea triangles=%d; obstacle triangles=%d" %
		[checks - failures, checks, sea.get_faces().size() / 3, block.get_faces().size() / 3])
	get_tree().quit(1 if failures else 0)

## Exercise the real incremental action builder, not a hand-placed showcase.
## Visuals must not change seeded hazards, fish, row admission or the RNG cursor.
func _test_generated_patterns(block: ArrayMesh, material: Material) -> void:
	for biome: int in RunnerTrack.BIOME_COUNT:
		for pattern: int in [RunnerTrack.Pattern.LANE_WEAVE,
			RunnerTrack.Pattern.MIXED_GAUNTLET, RunnerTrack.Pattern.PINCH]:
			for seed_value: int in [419, 909177]:
				var signatures: Array[PackedStringArray] = []
				var rng_states: Array[int] = []
				for rendered: bool in [false, true]:
					var track := RunnerTrack.new()
					add_child(track)
					track._clear()
					track._headless = not rendered
					var chunk := RunnerTrack.RunnerChunk.new()
					chunk.biome = biome
					chunk.index = 20 + biome
					chunk.difficulty = 0.8
					track.add_child(chunk)
					var rng := RandomNumberGenerator.new()
					rng.seed = seed_value
					track._run_pattern(pattern, chunk, rng, 0.8)
					var signature := PackedStringArray()
					var ice_count := 0
					var only_ice := true
					for child: Node in chunk.get_children():
						if child is not Area3D:
							continue
						var area := child as Area3D
						signature.append("%s|%d|%d|%s" % [area.get_meta("kind", "fish"),
							area.get_meta("lane", -1), area.get_meta("span", 1), area.position])
						if rendered and area.get_meta("kind", "") == "block":
							ice_count += 1
							var visual := area.get_child(1) as MeshInstance3D
							only_ice = only_ice and (visual.mesh == block
								and visual.material_override == material)
					if rendered:
						# MIXED may legitimately roll only jump/slide rows. Weave and
						# pinch guarantee full-height obstacles in this difficulty range.
						_check(only_ice and (ice_count > 0 or pattern == RunnerTrack.Pattern.MIXED_GAUNTLET),
							"generated biome %d pattern %d seed %d has ice-only blocks" % [biome, pattern, seed_value])
						var safe_rows := true
						for blocked: int in chunk.rows.values():
							safe_rows = safe_rows and blocked < RunnerConfig.LANE_COUNT
						_check(safe_rows, "generated ice patterns retain a free lane in every row")
					signatures.append(signature)
					rng_states.append(rng.state)
					track.free()
				_check(signatures[0] == signatures[1] and rng_states[0] == rng_states[1],
					"ice presentation preserves seeded hazard/fish layout and RNG cursor")

func _test_powerup_pickups() -> void:
	var track := RunnerTrack.new()
	add_child(track)
	track._headless = false
	var chunk := RunnerTrack.RunnerChunk.new()
	track.add_child(chunk)
	for id: StringName in RunnerConfig.POWERUP_IDS:
		track._add_powerup(chunk, 1, -20.0, id)
		var pickup := chunk.get_child(chunk.get_child_count() - 1) as RunnerTrack.RunnerPowerup
		_check(pickup.is_in_group(RunnerConfig.GROUP_POWERUP)
			and not pickup.is_in_group(RunnerConfig.GROUP_HAZARD), "powerup remains a collectible, never an ice hazard")
		var visual := pickup.body.get_child(0) as MeshInstance3D
		_check(visual.mesh == RunnerTrack._crate_mesh(id)
			and visual.mesh != Ice.block_mesh(), "powerup keeps its distinct icon solid")
		_check(pickup.collect() == id and pickup.collect() == &"", "powerup awards original id exactly once")
	track.free()

func _rounded_snow_boulder(mesh: ArrayMesh, size: Vector3) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var foot_x := Vector2(INF, -INF)
	var crown_x := Vector2(INF, -INF)
	var snow := 0
	for i: int in vertices.size():
		var vertex := vertices[i]
		if vertex.y <= 0.001:
			foot_x.x = minf(foot_x.x, vertex.x)
			foot_x.y = maxf(foot_x.y, vertex.x)
		if vertex.y >= size.y * 0.90:
			crown_x.x = minf(crown_x.x, vertex.x)
			crown_x.y = maxf(crown_x.y, vertex.x)
		var colour := colours[i].linear_to_srgb()
		if colour.r > 0.8 and colour.g > 0.9: snow += 1
	_check(foot_x.y - foot_x.x < size.x * 0.60, "rounded boulder narrows at grounded foot")
	_check(crown_x.y - crown_x.x < size.x * 0.40, "small irregular crown replaces broad flat roof")
	_check(float(snow) / vertices.size() >= 0.60, "snow-dominant body includes shoulder and middle faces")
	_check(vertices.size() == 240, "rounded silhouette retains80triangle budget")

func _mesh_integrity(mesh: ArrayMesh) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var valid := true
	var blue := 0
	var snow := 0
	for i: int in vertices.size():
		valid = valid and vertices[i].is_finite() and normals[i].is_normalized()
		var c := colours[i].linear_to_srgb()
		if c.b > 0.75 and c.r < 0.65: blue += 1
		if c.r > 0.8 and c.g > 0.9: snow += 1
	_check(valid, "finite geometry and valid outward face normals")
	_check(blue > vertices.size() / 5 and snow > vertices.size() / 8, "distinct saturated blue fractures and white snow planes")

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[runner_reference_ice] " + message)
