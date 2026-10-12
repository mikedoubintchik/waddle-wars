extends Node
## Registry/queue contracts only, not a claim of rasterization or hitch removal.

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	_check(ShaderWarmup.use_extended_warmup(1),
			"all web clients prepare absent-at-start effects")
	_check(not ShaderWarmup.use_extended_warmup(0),
			"native warmup policy unchanged")
	var saved_probes := ShaderWarmup._external_probes.duplicate()
	var saved_keys := ShaderWarmup._external_probe_keys.duplicate()
	var saved_scoped_probes := ShaderWarmup._scoped_external_probes.duplicate(true)
	var saved_scoped_keys := ShaderWarmup._scoped_external_probe_keys.duplicate(true)
	var saved_overflows := ShaderWarmup._external_probe_overflows.duplicate(true)
	ShaderWarmup._external_probes.clear()
	ShaderWarmup._external_probe_keys.clear()
	ShaderWarmup._scoped_external_probes.clear()
	ShaderWarmup._scoped_external_probe_keys.clear()
	ShaderWarmup._external_probe_overflows.clear()
	_test_budget_isolation_and_inventory()
	ShaderWarmup._external_probes.assign(saved_probes)
	ShaderWarmup._external_probe_keys = saved_keys
	ShaderWarmup._scoped_external_probes = saved_scoped_probes
	ShaderWarmup._scoped_external_probe_keys = saved_scoped_keys
	ShaderWarmup._external_probe_overflows = saved_overflows
	print("[shader_warmup_scope] %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(ok: bool, label: String, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("[shader_warmup_scope] FAIL %s %s" % [label, detail])


func _test_budget_isolation_and_inventory() -> void:
	var legacy_mesh := BoxMesh.new()
	var runner_mesh := SphereMesh.new()
	var materials: Array[Material] = []
	for index: int in ShaderWarmup.MAX_EXTERNAL_PROBES:
		var material := StandardMaterial3D.new()
		material.resource_name = "ScopedFixture%d" % index
		materials.append(material)
		ShaderWarmup.register_external_probe(legacy_mesh, material)
	var legacy_keys := ShaderWarmup._external_probe_keys.duplicate()
	for material: Material in materials:
		ShaderWarmup.register_external_probe(runner_mesh, material, [],
				RunnerTrack.SHADER_WARMUP_SCOPE)
	_check(ShaderWarmup.external_probe_count() == 32 \
			and ShaderWarmup.external_probe_count(RunnerTrack.SHADER_WARMUP_SCOPE) == 32,
			"each registry owns unchanged 32-pair budget")
	_check(ShaderWarmup._external_probe_keys == legacy_keys,
			"runner registration does not clear or consume default registry")
	_check(bool(ShaderWarmup.external_scope_status(RunnerTrack.SHADER_WARMUP_SCOPE)["registry_complete"]),
			"full registry without omitted pairs remains complete")
	var world := Node3D.new()
	var live := MeshInstance3D.new()
	live.mesh = PlaneMesh.new()
	live.material_override = StandardMaterial3D.new()
	world.add_child(live)
	var particles := GPUParticles3D.new()
	particles.process_material = ParticleProcessMaterial.new()
	world.add_child(particles)
	var cached_material := VisualLibrary.rock_material(Color(0.17, 0.29, 0.41), 0.63)
	var cached_mesh := VisualLibrary.snow_drift_mesh()
	var warmup := ShaderWarmup.new()
	warmup._world = world
	warmup._extended = true
	warmup._external_scope = RunnerTrack.SHADER_WARMUP_SCOPE
	warmup._build_queue()
	var summary := warmup.inventory_summary()
	_check(int(summary["by_type"]["external"]) == 32 \
			and summary["scope"] == "global" \
			and summary["external_registry"]["scope"] == "runner",
			"scoped external prefix keeps legacy resource inventory", str(summary))
	for material: Material in materials:
		_check(_has_pair(warmup, runner_mesh, material),
				"runner exact pair survives full prior-mode registry")
	_check(not _has_pair(warmup, legacy_mesh, materials[0]),
			"runner queue does not spend late slots on prior-mode pairs")
	_check(warmup._queue_keys.has("mesh:%d" % live.mesh.get_instance_id()) \
			and warmup._queue_keys.has("material:%d" % live.material_override.get_instance_id()),
			"live resources remain collected")
	_check(warmup._queue_keys.has("mesh:%d" % cached_mesh.get_instance_id()) \
			and warmup._queue_keys.has("material:%d" % cached_material.get_instance_id()),
			"shared cached resources remain collected")
	var synthetic_complete := true
	for material: Material in ShaderWarmup.probe_materials():
		synthetic_complete = synthetic_complete and warmup._queue_keys.has(
				"material:%d" % material.get_instance_id())
	_check(synthetic_complete and warmup._queue_keys.has(
			"particle:%d" % particles.process_material.get_instance_id()),
			"web feature and particle collection remain intact")
	var first_keys := _queue_keys(warmup)
	for material: Material in materials:
		ShaderWarmup.register_external_probe(runner_mesh, material, [],
				RunnerTrack.SHADER_WARMUP_SCOPE)
	warmup._build_queue()
	_check(_queue_keys(warmup) == first_keys \
			and ShaderWarmup.external_scope_status(RunnerTrack.SHADER_WARMUP_SCOPE)["dropped"] == 0,
			"retry deduplicates before cap without false overflow")
	warmup._external_scope = &""
	warmup._build_queue()
	var default_complete := true
	for material: Material in materials:
		default_complete = default_complete and _has_pair(warmup, legacy_mesh, material)
	_check(default_complete and not _has_pair(warmup, runner_mesh, materials[0]),
			"other mode selects original default registry after runner retry")
	var overflow_material := StandardMaterial3D.new()
	ShaderWarmup.register_external_probe(runner_mesh, overflow_material, [],
			RunnerTrack.SHADER_WARMUP_SCOPE)
	ShaderWarmup.register_external_probe(runner_mesh, overflow_material, [],
			RunnerTrack.SHADER_WARMUP_SCOPE)
	var status := ShaderWarmup.external_scope_status(RunnerTrack.SHADER_WARMUP_SCOPE)
	_check(status["registered"] == 32 and status["dropped"] == 1 \
			and not bool(status["registry_complete"]),
			"unique overflow diagnosed once without false coverage", str(status))
	_check(not ShaderWarmup.has_external_probe(runner_mesh, overflow_material, [],
			RunnerTrack.SHADER_WARMUP_SCOPE) and ShaderWarmup._external_probe_keys == legacy_keys,
			"overflow neither registers omitted pair nor damages other scope")
	warmup._external_scope = &"runner_typo"
	warmup._build_queue()
	status = warmup.inventory_summary()["external_registry"]
	_check(not bool(status["known"]) and not bool(status["registry_complete"]) \
			and int(warmup.inventory_summary()["by_type"]["external"]) == 0,
			"unknown scope emits explicit incomplete diagnostic", str(status))
	_check(warmup._queue_keys.has("material:%d" % cached_material.get_instance_id()),
			"unknown external scope never narrows unrelated cached inventory")
	warmup.free()
	world.free()


func _has_pair(warmup: ShaderWarmup, mesh: Mesh, material: Material) -> bool:
	return warmup._queue_keys.has("external:%d:%d" % [mesh.get_instance_id(),
			material.get_instance_id()])


func _queue_keys(warmup: ShaderWarmup) -> PackedStringArray:
	var keys := PackedStringArray()
	for row: Dictionary in warmup._queue:
		keys.append(String(row["key"]))
	return keys
