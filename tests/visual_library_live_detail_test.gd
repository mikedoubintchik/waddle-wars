extends Node
## Resource/identity contracts only. No claim of browser/GPU performance.
## run_tests.sh provides an isolated project and user:// directory.

var _passes: int = 0
var _failures: int = 0


func _ready() -> void:
	var saved_materials := VisualLibrary._materials.duplicate()
	var saved_auto_materials := VisualLibrary._auto_detail_materials.duplicate()
	var saved_detail := VisualLibrary._detail_level_cache
	var saved_settings := SettingsManager.settings.duplicate(true)
	var saved_override := SettingsManager._governor_override
	VisualLibrary._materials.clear()
	VisualLibrary._auto_detail_materials.clear()
	_test_factory_and_variant_contracts()
	_test_actual_settings_dispatch()
	_check("settings and governor preference unchanged",
			SettingsManager.settings == saved_settings
			and SettingsManager._governor_override == saved_override)
	VisualLibrary._materials = saved_materials
	VisualLibrary._auto_detail_materials = saved_auto_materials
	VisualLibrary._detail_level_cache = saved_detail
	print("[visual_library_live_detail] DONE: %d passed, %d failed" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool) -> void:
	if ok:
		_passes += 1
		print("[visual_library_live_detail] PASS %s" % label)
	else:
		_failures += 1
		print("[visual_library_live_detail] FAIL %s" % label)


func _families(detail: float) -> Array[ShaderMaterial]:
	return [
		VisualLibrary.snow_material(Color(0.72, 0.83, 0.94), 0.31, detail, 0.24),
		VisualLibrary.ice_material(Color(0.26, 0.57, 0.78), 0.62, detail),
		VisualLibrary.water_material(Color(0.06, 0.23, 0.34),
				Color(0.21, 0.63, 0.74), 0.25, 0.13, detail),
		VisualLibrary.aurora_material(detail),
	]


func _select_fixture_detail(detail: float) -> void:
	# Headless deliberately resolves production quality to zero. Inject only
	# the derived value here, then exercise the real in-place update operation.
	VisualLibrary._detail_level_cache = detail
	VisualLibrary._refresh_auto_detail_materials(detail)


func _uniforms_except_detail(material: ShaderMaterial) -> Dictionary:
	var result: Dictionary = {}
	for uniform: Dictionary in material.shader.get_shader_uniform_list():
		var uniform_name := StringName(uniform.get("name", ""))
		if uniform_name != &"detail_level":
			result[uniform_name] = material.get_shader_parameter(uniform_name)
	return result


func _test_factory_and_variant_contracts() -> void:
	_select_fixture_detail(1.0)
	var automatic := _families(-1.0)
	var fixed := _families(1.0)
	var repeat := _families(-7.0)
	var fixed_half := _families(0.5)
	var fixed_zero := _families(0.0)
	var base_params: Array[Dictionary] = []
	for index: int in automatic.size():
		base_params.append(_uniforms_except_detail(automatic[index]))
		_check("family %d automatic and matching fixed level are separate" % index,
				automatic[index] != fixed[index])
		_check("family %d every negative request shares auto identity" % index,
				automatic[index] == repeat[index])
		_check("family %d fixed levels have separate cache entries" % index,
				fixed[index] != fixed_half[index] and fixed[index] != fixed_zero[index])
		_check("family %d initial auto level is high" % index,
				automatic[index].get_shader_parameter("detail_level") == 1.0)
		_check("family %d automatic shader identity matches fixed shader" % index,
				automatic[index].shader == fixed[index].shader)

	var ice := automatic[1]
	var changes := {"rim_strength": 0.10, "crack_strength": 0.48,
			"rim_tint": Color(0.25, 0.62, 0.81)}
	var variant := VisualLibrary.shader_variant(ice, changes)
	var nested := VisualLibrary.shader_variant(variant, {"streak_strength": 0.12})
	var fixed_variant := VisualLibrary.shader_variant(fixed[1], changes)
	var pinned := VisualLibrary.shader_variant(ice, {"detail_level": 0.73,
			"rim_strength": 0.17})
	var pinned_named := VisualLibrary.shader_variant(ice, {&"detail_level": 0.27})
	var pinned_nested := VisualLibrary.shader_variant(pinned, {"glint_strength": 0.20})
	var raw_duplicate := ice.duplicate() as ShaderMaterial
	var duplicate_variant := VisualLibrary.shader_variant(raw_duplicate, changes)
	var variants: Array[ShaderMaterial] = [variant, nested]
	var variant_params: Array[Dictionary] = [
		_uniforms_except_detail(variant), _uniforms_except_detail(nested),
	]
	_check("automatic variant is registered",
			VisualLibrary._auto_detail_materials.has(variant.get_instance_id()))
	_check("nested automatic variant is registered",
			VisualLibrary._auto_detail_materials.has(nested.get_instance_id()))
	_check("fixed and explicitly overridden variants are not registered",
			not VisualLibrary._auto_detail_materials.has(fixed_variant.get_instance_id())
			and not VisualLibrary._auto_detail_materials.has(pinned.get_instance_id())
			and not VisualLibrary._auto_detail_materials.has(pinned_named.get_instance_id())
			and not VisualLibrary._auto_detail_materials.has(pinned_nested.get_instance_id()))
	_check("raw duplicate and its variants remain caller-owned",
			not VisualLibrary._auto_detail_materials.has(raw_duplicate.get_instance_id())
			and not VisualLibrary._auto_detail_materials.has(duplicate_variant.get_instance_id()))
	_check("variant parameter-order independent identity",
			VisualLibrary.shader_variant(ice, {"rim_tint": Color(0.25, 0.62, 0.81),
					"crack_strength": 0.48, "rim_strength": 0.10}) == variant)
	_check("variants preserve shader resources",
			variant.shader == ice.shader and nested.shader == ice.shader)
	_check("overrides applied without altering base",
			variant.get_shader_parameter("rim_strength") == 0.10
			and ice.get_shader_parameter("rim_strength") != 0.10)

	var resident := MeshInstance3D.new()
	resident.material_override = nested
	var cache_count := VisualLibrary._materials.size()
	var auto_count := VisualLibrary._auto_detail_materials.size()
	for cycle: int in 3:
		for level: float in [0.5, 0.0, 1.0]:
			_select_fixture_detail(level)
			var reused := _families(-1.0)
			var explicit_reused := _families(1.0)
			var label := "cycle %d level %.1f" % [cycle, level]
			for index: int in automatic.size():
				_check("%s family %d keeps identity and updates uniform" % [label, index],
						reused[index] == automatic[index]
						and reused[index].get_shader_parameter("detail_level") == level)
				_check("%s family %d preserves other parameters" % [label, index],
						_uniforms_except_detail(reused[index]) == base_params[index])
				_check("%s family %d preserves fixed detail and identity" % [label, index],
						explicit_reused[index] == fixed[index]
						and fixed[index].get_shader_parameter("detail_level") == 1.0
						and fixed_half[index].get_shader_parameter("detail_level") == 0.5
						and fixed_zero[index].get_shader_parameter("detail_level") == 0.0)
			for index: int in variants.size():
				_check("%s inherited variant %d updates only detail" % [label, index],
						variants[index].get_shader_parameter("detail_level") == level
						and _uniforms_except_detail(variants[index]) == variant_params[index])
			_check("%s pinned and caller-owned copies untouched" % label,
					pinned.get_shader_parameter("detail_level") == 0.73
					and pinned_named.get_shader_parameter("detail_level") == 0.27
					and pinned_nested.get_shader_parameter("detail_level") == 0.73
					and fixed_variant.get_shader_parameter("detail_level") == 1.0
					and raw_duplicate.get_shader_parameter("detail_level") == 1.0
					and duplicate_variant.get_shader_parameter("detail_level") == 1.0)
			_check("%s resident and variant factory retain original identity" % label,
					resident.material_override == nested
					and VisualLibrary.shader_variant(ice, changes) == variant
					and VisualLibrary.shader_variant(variant, {"streak_strength": 0.12}) == nested)
			_check("%s creates no new cached resources or registry entries" % label,
					VisualLibrary._materials.size() == cache_count
					and VisualLibrary._auto_detail_materials.size() == auto_count)
	resident.free()

	_select_fixture_detail(0.0)
	var created_low := VisualLibrary.shader_variant(ice, {"glint_strength": 0.39})
	_check("new variant created after degradation inherits current low",
			created_low.get_shader_parameter("detail_level") == 0.0)
	_select_fixture_detail(1.0)
	_check("new low-era variant recovers in place",
			created_low.get_shader_parameter("detail_level") == 1.0
			and VisualLibrary.shader_variant(ice, {"glint_strength": 0.39}) == created_low)
	var fine_fixed_a := VisualLibrary.aurora_material(0.33330)
	var fine_fixed_b := VisualLibrary.aurora_material(0.33331)
	_check("explicit close detail values do not alias rounded cache keys",
			fine_fixed_a != fine_fixed_b
			and fine_fixed_a.get_shader_parameter("detail_level") == 0.33330
			and fine_fixed_b.get_shader_parameter("detail_level") == 0.33331)


func _test_actual_settings_dispatch() -> void:
	_select_fixture_detail(1.0)
	var automatic := _families(-1.0)
	var fixed := _families(0.73)
	var inherited := VisualLibrary.shader_variant(automatic[1], {"depth_strength": 0.13})
	var count := VisualLibrary._materials.size()
	# The real settings path must dispatch to the live update. In this isolated
	# headless process the selected detail is zero, irrespective of saved tier.
	SettingsManager._apply_display("quality_preset", "low")
	_check("actual settings dispatch resolves headless detail zero",
			VisualLibrary._detail_level_cache == 0.0)
	for index: int in automatic.size():
		_check("actual settings dispatch updates resident family %d" % index,
				automatic[index].get_shader_parameter("detail_level") == 0.0)
		_check("actual settings dispatch leaves explicit family %d untouched" % index,
				fixed[index].get_shader_parameter("detail_level") == 0.73)
	_check("actual settings dispatch updates inherited variant",
			inherited.get_shader_parameter("detail_level") == 0.0)
	_check("actual settings dispatch adds no material resources",
			VisualLibrary._materials.size() == count)
