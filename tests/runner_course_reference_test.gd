extends Node
## Reference-art changes must preserve obstacle envelopes and cached resources.
var _checks := 0
var _failures := 0

func _ready() -> void:
	var block := RunnerTrack._block_mesh()
	var ice := RunnerTrack._low_mesh()
	_check(block == RunnerTrack._block_mesh(), "full-height ice boulders share one mesh")
	_check(ice == RunnerTrack._low_mesh(), "ice obstacles share one mesh")
	for entry: Array in [[block, Vector3(RunnerTrack.BLOCK_WIDTH, RunnerTrack.BLOCK_HEIGHT,
		RunnerTrack.BLOCK_DEPTH)], [ice, Vector3(1.0, RunnerTrack.LOW_HEIGHT, RunnerTrack.LOW_DEPTH)]]:
		var mesh := entry[0] as ArrayMesh
		var size: Vector3 = entry[1]
		var bounds := mesh.get_aabb()
		_check(mesh.get_surface_count() == 1, "one material surface per obstacle")
		_check(mesh.surface_get_array_len(0) <= 700, "reference geometry remains bounded")
		_check(absf(bounds.position.y) < 0.001, "visual rests on actual deck")
		_check(absf(bounds.end.y - size.y) < 0.001, "visual crown matches collision height")
		_check(absf(bounds.size.x - size.x) < 0.001, "visual width matches collision width")
		_check(absf(bounds.size.z - size.z) < 0.06, "visible depth stays within 6cm of collision")
	var track := RunnerTrack.new()
	add_child(track)
	track._clear()
	track._headless = false
	for kind: int in [RunnerTrack.Kind.BLOCK, RunnerTrack.Kind.LOW]:
		var chunk := RunnerTrack.RunnerChunk.new()
		chunk.biome = RunnerTrack.Biome.DAY
		track.add_child(chunk)
		_check(track._add_obstacle(chunk, kind, 0, 1, -20.0), "normal generator adds reference obstacle")
		var area := chunk.get_child(0) as Area3D
		var collider := area.get_child(0) as CollisionShape3D
		var visual := area.get_child(1) as MeshInstance3D
		_check(visual.mesh == (block if kind == RunnerTrack.Kind.BLOCK else ice),
			"live obstacle actually consumes reference mesh")
		_check(is_equal_approx((collider.shape as BoxShape3D).size.y,
			(RunnerTrack.BLOCK_HEIGHT if kind == RunnerTrack.Kind.BLOCK else RunnerTrack.LOW_HEIGHT)),
			"gameplay collider height unchanged")
		_check(area.is_in_group(RunnerConfig.GROUP_HAZARD), "hazard stays in collision group")
		chunk.free()
	track._register_shader_warmup_probes()
	_check(ShaderWarmup.has_external_probe(block, RunnerTrack.ReferenceIce.material(), [],
		RunnerTrack.SHADER_WARMUP_SCOPE), "ice BLOCK mesh/material is warmed before gameplay")
	track.free()
	var runner := RunnerGame.new()
	runner._runner_art_set = load(RunnerGame.RUNNER_ART_SET_PATH)
	var current := runner._runner_environment(RunnerTrack.Biome.DAY)
	var fallback := RunnerTrack.biome_environment(RunnerTrack.Biome.DAY)
	_check(current["sky_top"] == fallback["sky_top"] and current["sky_horizon"] == fallback["sky_horizon"],
		"authored and fallback day atmosphere match reference palette")
	runner.free()
	print("[runner_course_reference] %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures else 0)

func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error("[runner_course_reference] " + label)
