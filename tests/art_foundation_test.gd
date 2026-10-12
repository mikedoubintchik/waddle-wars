extends Node
## Headless contract test for authored-art foundation.
##
##   godot --headless --path . res://tests/art_foundation_test.tscn

const PROFILE_PATHS: PackedStringArray = [
	"res://data/art/course_profiles/runner_day.tres",
	"res://data/art/course_profiles/runner_dusk.tres",
	"res://data/art/course_profiles/runner_cave.tres",
	"res://data/art/course_profiles/runner_night.tres",
]
const RUNNER_DAY_PREVIEW_FRAGMENT: String = \
		"res://data/art/fragments/runner_day_kit_v1.json"
const RUNNER_DAY_SCENE_IDS: PackedStringArray = [
	"runner_day_barrier_v1",
	"runner_day_cargo_stack_v1",
	"runner_day_deck_kerb_b_v1",
	"runner_day_deck_kerb_c_v1",
	"runner_day_deck_kerb_v1",
	"runner_day_gantry_v1",
	"runner_day_iceberg_cluster_v1",
	"runner_day_icebreaker_landmark_v1",
	"runner_day_radar_landmark_v1",
	"runner_day_ramp_v1",
	"runner_day_research_hub_landmark_v1",
	"runner_day_research_lab_v1",
	"runner_day_signal_pylon_v1",
	"runner_day_snowcat_v1",
	"runner_day_tunnel_shell_v1",
]
const RUNNER_DAY_RELEASE_SCENE_IDS: PackedStringArray = [
	"runner_day_deck_kerb_b_v1", "runner_day_deck_kerb_c_v1", "runner_day_deck_kerb_v1",
	"runner_day_iceberg_cluster_v1", "runner_day_research_lab_v1", "runner_day_signal_pylon_v1",
]

var _passes: int = 0
var _failures: int = 0


func _ready() -> void:
	_test_catalog()
	_test_catalog_invalid_reload()
	_test_preview_overlay()
	_test_normal_runner_preview_resolution()
	await _test_catalog_lazy_preload()
	_test_catalog_headless_preload()
	_test_character_look()
	_test_profiles()
	_test_runner_set()
	print("[art-foundation] DONE: %d passed, %d failed" % [_passes, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _check(check_name: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passes += 1
		print("[art-foundation] PASS %s" % check_name)
	else:
		_failures += 1
		var suffix := ": %s" % detail if not detail.is_empty() else ""
		print("[art-foundation] FAIL %s%s" % [check_name, suffix])


func _test_catalog() -> void:
	var catalog := load("res://data/art/art_catalog.tres") as ArtCatalog
	_check("catalog_loads", catalog != null)
	if catalog == null:
		return
	var error := catalog.reload_manifest()
	_check("catalog_manifest_valid", error == OK,
		"error=%d details=%s" % [error, str(catalog.manifest_errors())])
	var frontend_ids := catalog.asset_ids("frontend")
	_check("catalog_frontend_sources_registered", frontend_ids == PackedStringArray([
		"frontend_loader_penguin",
		"frontend_title_landscape",
		"frontend_title_portrait",
		"frontend_wordmark_v2",
		"frontend_wordmark_v3",
		"frontend_wordmark_v4",
		"wardrobe_category_icons_v3",
	]), "ids=%s" % str(frontend_ids))
	_check("catalog_frontend_paths_resolve",
		catalog.asset_path("frontend_loader_penguin") ==
			"res://assets/art/ui/loader_penguin_expedition_v1.png"
		and catalog.asset_path("frontend_title_landscape") ==
			"res://assets/art/ui/title_expedition_landscape_v1.png"
		and catalog.asset_path("frontend_title_portrait") ==
			"res://assets/art/ui/title_expedition_portrait_v1.png"
		and catalog.asset_path("wardrobe_category_icons_v3") ==
			"res://assets/art/ui/menu/wardrobe_category_icons_v3.png")
	var budgets := catalog.budgets()
	_check("catalog_character_budget", int(budgets.get("character_lod0_triangles_max", 0)) == 25_000)
	_check("catalog_draw_budget", int(budgets.get("draw_calls_high_peak_max", 0)) == 300)
	_check("catalog_primitive_budget", int(budgets.get("visible_primitives_low_max", 0)) == 50_000)
	var missing_error := catalog.begin_preload(PackedStringArray(["not_registered"]))
	var status := catalog.preload_status()
	_check("catalog_unknown_id_fails", missing_error == ERR_DOES_NOT_EXIST,
		"error=%d" % missing_error)
	_check("catalog_unknown_id_completes", bool(status.get("complete", false))
		and int(status.get("failed", 0)) == 1, str(status))


func _test_catalog_invalid_reload() -> void:
	var catalog := ArtCatalog.new()
	catalog.manifest_path = "res://tests/fixtures/art/catalog.json"
	catalog.strict_paths = false
	_check("catalog_invalid_setup_valid", catalog.reload_manifest() == OK,
		str(catalog.manifest_errors()))
	_check("catalog_invalid_setup_indexed",
		catalog.has_asset("runner_day_profile_fixture"))
	catalog.manifest_path = "res://tests/fixtures/art/catalog_invalid.json"
	var error := catalog.reload_manifest()
	_check("catalog_invalid_reload_fails", error == ERR_INVALID_DATA,
		"error=%d details=%s" % [error, str(catalog.manifest_errors())])
	_check("catalog_invalid_reload_clears_manifest", catalog.manifest().is_empty(),
		str(catalog.manifest()))
	_check("catalog_invalid_reload_clears_entries", catalog.asset_ids().is_empty()
		and not catalog.has_asset("must_not_escape")
		and catalog.asset_entry("must_not_escape").is_empty()
		and catalog.asset_path("must_not_escape").is_empty())
	_check("catalog_invalid_reload_stays_failed",
		catalog.begin_preload(PackedStringArray(["must_not_escape"])) == ERR_INVALID_DATA,
		str(catalog.manifest_errors()))
	catalog.manifest_path = "res://tests/fixtures/art/catalog.json"
	_check("catalog_invalid_reload_recovers", catalog.reload_manifest() == OK
		and catalog.has_asset("runner_day_profile_fixture"),
		str(catalog.manifest_errors()))


func _test_preview_overlay() -> void:
	_check("preview_policy_debug", ArtCatalog.preview_overlay_allowed(true, false))
	_check("preview_policy_editor", ArtCatalog.preview_overlay_allowed(false, true))
	_check("preview_policy_release_denied",
		not ArtCatalog.preview_overlay_allowed(false, false))
	var catalog := ArtCatalog.new()
	_check("preview_central_manifest_valid", catalog.reload_manifest() == OK,
		str(catalog.manifest_errors()))
	var central_ids := catalog.asset_ids()
	var error := catalog.apply_preview_fragment(RUNNER_DAY_PREVIEW_FRAGMENT)
	_check("preview_fragment_applies", error == OK,
		"error=%d details=%s" % [error, str(catalog.manifest_errors())])
	var preview_ids := catalog.preview_asset_ids()
	# Six scenes and the shared surface dependencies now belong to the release
	# catalog. Nine remaining review scenes + shell shader/material stay private.
	var expected_preview_count := (RUNNER_DAY_SCENE_IDS.size() - RUNNER_DAY_RELEASE_SCENE_IDS.size()) * 2 + 2
	_check("preview_fragment_count", preview_ids.size() == expected_preview_count,
		"ids=%d expected=%d" % [preview_ids.size(), expected_preview_count])
	_check("preview_fragment_scenes_resolve",
		_all_ids_registered(catalog, RUNNER_DAY_SCENE_IDS), str(preview_ids))
	var all_not_ready := true
	for asset_id: String in preview_ids:
		if catalog.asset_entry(asset_id).get("production_ready", true) != false:
			all_not_ready = false
	_check("preview_fragment_honest_not_ready", all_not_ready)
	var manifest_after_apply := catalog.manifest()
	var ids_after_apply := catalog.asset_ids()
	error = catalog.apply_preview_fragment(RUNNER_DAY_PREVIEW_FRAGMENT)
	_check("preview_fragment_idempotent", error == OK
		and catalog.preview_asset_ids() == preview_ids
		and catalog.asset_ids() == ids_after_apply
		and catalog.manifest() == manifest_after_apply,
		"error=%d ids=%s" % [error, str(catalog.asset_ids())])

	var bad_fragments: Dictionary = {
		"conflict": "res://tests/fixtures/art/preview_fragment_conflict.json",
		"path_traversal": "res://tests/fixtures/art/preview_fragment_traversal.json",
		"production_ready": "res://tests/fixtures/art/preview_fragment_ready.json",
		"shape": "res://tests/fixtures/art/preview_fragment_shape_invalid.json",
	}
	for failure_name: String in bad_fragments:
		error = catalog.apply_preview_fragment(String(bad_fragments[failure_name]))
		_check("preview_rejects_%s" % failure_name, error != OK, "error=%d" % error)
		_check("preview_rollback_%s" % failure_name,
			catalog.preview_asset_ids() == preview_ids
			and catalog.asset_ids() == ids_after_apply
			and catalog.manifest() == manifest_after_apply,
			"ids=%s" % str(catalog.asset_ids()))
	catalog.reload_manifest()
	_check("preview_reload_clears_overlay", not catalog.preview_overlay_active()
		and catalog.preview_asset_ids().is_empty()
		and catalog.asset_ids() == central_ids, str(catalog.asset_ids()))


func _test_normal_runner_preview_resolution() -> void:
	var art_set := load("res://data/art/runner_art_set_foundation.tres") as RunnerArtSet
	var catalog := ArtCatalog.new()
	var game := RunnerGame.new()
	_check("runner_preview_central_manifest_valid", catalog.reload_manifest() == OK,
		str(catalog.manifest_errors()))
	var preview_error := game._apply_runner_day_preview(catalog)
	_check("runner_game_applies_real_preview", preview_error == OK
		and catalog.preview_overlay_active(),
		"error=%d details=%s" % [preview_error, str(catalog.manifest_errors())])
	_check("runner_preview_art_set_resolves", art_set != null
		and art_set.validation_errors(catalog).is_empty(),
		str(art_set.validation_errors(catalog)) if art_set != null else "null")
	game._runner_art_set = art_set
	game._art_catalog = catalog
	var track := RunnerTrack.new()
	game.add_child(track)
	track.setup(20260818, 1.0, 1)
	var status := track.authored_day_kit_status()
	_check("normal_runner_uses_scoped_mapping_even_with_preview_catalog",
		not bool(status.get("active", false))
		and int(status.get("loaded", 0)) == RUNNER_DAY_RELEASE_SCENE_IDS.size()
		and status.get("asset_ids", PackedStringArray()) == RUNNER_DAY_RELEASE_SCENE_IDS,
		str(status))
	game.free()


func _all_ids_registered(catalog: ArtCatalog, ids: PackedStringArray) -> bool:
	for asset_id: String in ids:
		if not catalog.has_asset(asset_id):
			return false
	return true


func _test_catalog_lazy_preload() -> void:
	var catalog := ArtCatalog.new()
	catalog.manifest_path = "res://tests/fixtures/art/catalog.json"
	catalog.strict_paths = false
	var error := catalog.reload_manifest()
	_check("catalog_fixture_valid", error == OK, str(catalog.manifest_errors()))
	if error != OK:
		return
	error = catalog.begin_preload(PackedStringArray(["runner_day_profile_fixture"]))
	_check("catalog_lazy_request", error == OK, "error=%d" % error)
	for attempt: int in 120:
		var status := catalog.poll_preload()
		if bool(status.get("complete", false)):
			break
		await get_tree().process_frame
	var final_status := catalog.preload_status()
	var resource := catalog.loaded_resource("runner_day_profile_fixture")
	_check("catalog_lazy_complete", bool(final_status.get("complete", false))
		and int(final_status.get("failed", 0)) == 0, str(final_status))
	_check("catalog_lazy_typed_resource", resource is CourseVisualProfile,
		str(resource))


func _test_catalog_headless_preload() -> void:
	if not GameConfig.is_headless():
		return
	var catalog := ArtCatalog.new()
	catalog.manifest_path = "res://tests/fixtures/art/catalog_headless_preload.json"
	# The missing-path entry is intentional: this exercises the preload error
	# API rather than rejecting the entire fixture during manifest indexing.
	catalog.strict_paths = false
	_check("catalog_headless_fixture_valid", catalog.reload_manifest() == OK,
			str(catalog.manifest_errors()))
	var ids := PackedStringArray(["headless_scene_fixture", "headless_material_fixture"])
	var error := catalog.begin_preload(ids)
	var immediate_status := catalog.preload_status()
	var scene := catalog.loaded_resource(ids[0])
	var material := catalog.loaded_resource(ids[1])
	# Check before yielding or polling. The old threaded path always leaves a
	# pending request, even when a cached dependency finishes on its worker.
	_check("catalog_headless_resources_ready_without_polling",
			error == OK and scene is PackedScene and material is ShaderMaterial,
			str(immediate_status))
	_check("catalog_headless_submits_no_pending_thread_jobs",
			catalog._pending.is_empty() and int(immediate_status.get("pending", -1)) == 0)
	_check("catalog_headless_immediate_progress_complete",
			bool(immediate_status.get("complete", false))
			and int(immediate_status.get("total", -1)) == 2
			and int(immediate_status.get("loaded", -1)) == 2
			and int(immediate_status.get("failed", -1)) == 0
			and is_equal_approx(float(immediate_status.get("progress", -1.0)), 1.0),
			str(immediate_status))
	_check("catalog_headless_poll_is_idempotent", catalog.poll_preload() == immediate_status)
	error = catalog.begin_preload(ids)
	_check("catalog_headless_reuses_loaded_resources",
			error == OK and catalog.loaded_resource(ids[0]) == scene
			and catalog.loaded_resource(ids[1]) == material
			and catalog.preload_status() == immediate_status)
	error = catalog.begin_preload(PackedStringArray([
			"headless_missing_fixture", "headless_unknown_fixture",
	]))
	var failed_status := catalog.poll_preload()
	var failures: Dictionary = failed_status.get("failures", {})
	_check("catalog_headless_missing_path_preserves_first_error",
			error == ERR_FILE_NOT_FOUND, "error=%d" % error)
	_check("catalog_headless_failure_details_preserved",
			String(failures.get("headless_missing_fixture", "")).begins_with("resource not found:")
			and failures.get("headless_unknown_fixture") == "unknown asset ID", str(failures))
	_check("catalog_headless_failed_batch_finishes_without_jobs",
			catalog._pending.is_empty() and bool(failed_status.get("complete", false))
			and int(failed_status.get("total", -1)) == 4
			and int(failed_status.get("loaded", -1)) == 2
			and int(failed_status.get("failed", -1)) == 2
			and is_equal_approx(float(failed_status.get("progress", -1.0)), 1.0),
			str(failed_status))


func _test_character_look() -> void:
	var contract := load("res://data/art/character_look_contract.tres") as CharacterLook
	_check("character_contract_loads", contract != null)
	if contract == null:
		return
	_check("character_contract_valid", contract.validation_errors().is_empty(),
		str(contract.validation_errors()))
	_check("character_contract_not_ready", not contract.production_ready
		and "body_scene_id" in contract.readiness_gaps())
	var equipped := {
		"body": "body_rockhopper",
		"hat": "hat_crown",
		"scarf": "scarf_red",
		"goggles": "goggles_ski",
		"trail": "trail_aurora",
	}
	var hero := CharacterLook.from_equipped(equipped, CharacterLook.RenderRole.HERO)
	_check("character_from_equipped_species", hero.species_id == "rockhopper", hero.species_id)
	_check("character_from_equipped_cosmetics", hero.hat_id == "hat_crown"
		and hero.scarf_id == "scarf_red" and hero.goggles_id == "goggles_ski"
		and hero.trail_id == "trail_aurora", str(hero.cosmetic_ids()))
	_check("character_from_equipped_role", hero.render_role == CharacterLook.RenderRole.HERO)
	var rival := CharacterLook.from_legacy_config(
		PersonalitiesDB.get_item("marina"), CharacterLook.RenderRole.RACER)
	_check("character_legacy_species", rival.species_id == "king", rival.species_id)
	_check("character_legacy_category_normalized", rival.hat_id.is_empty()
		and rival.scarf_id == "scarf_bowtie", str(rival.cosmetic_ids()))
	_check("character_legacy_round_trip", String(rival.to_legacy_config().get("species")) == "king")
	var explicit_config := rival.to_legacy_config()
	_check("character_legacy_explicit_identity_preserved",
		explicit_config.get("accent_color") == PersonalitiesDB.get_item("marina").get("accent_color"),
		str(explicit_config.get("accent_color")))
	var inherited := CharacterLook.from_legacy_config(
		CosmeticsDB.get_item("body_rockhopper"), CharacterLook.RenderRole.HERO)
	var inherited_config := inherited.to_legacy_config()
	_check("character_legacy_species_identity_inherited",
		inherited.inherit_species_identity_color
		and not inherited_config.has("accent_color")
		and String(inherited_config.get("species", "")) == "rockhopper",
		str(inherited_config))


func _test_profiles() -> void:
	var seen: Dictionary = {}
	for path: String in PROFILE_PATHS:
		var profile := load(path) as CourseVisualProfile
		_check("profile_load_%s" % path.get_file().get_basename(), profile != null)
		if profile == null:
			continue
		_check("profile_valid_%s" % profile.biome_id, profile.validation_errors().is_empty(),
			str(profile.validation_errors()))
		seen[profile.biome_id] = true
		var high := profile.quality_settings("high")
		var medium := profile.quality_settings("medium")
		var low := profile.quality_settings("low")
		_check("profile_tiers_%s" % profile.biome_id,
			float(high.get("lod_threshold", 0.0)) == 1.0
			and float(medium.get("lod_threshold", 0.0)) == 2.0
			and float(low.get("lod_threshold", 0.0)) == 4.0)
		var environment := profile.environment_values()
		_check("profile_environment_%s" % profile.biome_id,
			environment.has("ground_horizon") and environment.has("fog_density")
			and environment.has("shaft"))
	_check("profiles_cover_runner_biomes", seen.size() == 4
		and seen.has("day") and seen.has("dusk") and seen.has("cave") and seen.has("night"),
		str(seen.keys()))


func _test_runner_set() -> void:
	var art_set := load("res://data/art/runner_art_set_foundation.tres") as RunnerArtSet
	var catalog := load("res://data/art/art_catalog.tres") as ArtCatalog
	_check("runner_set_loads", art_set != null)
	if art_set == null:
		return
	if catalog != null:
		catalog.reload_manifest()
		catalog.apply_preview_fragment(RUNNER_DAY_PREVIEW_FRAGMENT)
	_check("runner_set_valid_foundation", art_set.validation_errors(catalog).is_empty(),
		str(art_set.validation_errors(catalog)))
	_check("runner_set_fallback_explicit", not art_set.production_ready
		and art_set.allow_procedural_fallback)
	_check("runner_set_profiles_mapped", art_set.course_profiles.size() == 4
		and art_set.profile_for_biome("day") != null
		and art_set.profile_for_biome("night") != null)
	_check("runner_set_reports_gaps", not art_set.readiness_gaps().is_empty())
	var day_preload := art_set.collect_preload_ids("day")
	var required_day_ids := PackedStringArray([
		"runner_day_deck_kerb_b_v1",
		"runner_day_deck_kerb_c_v1",
		"runner_day_deck_kerb_v1",
		"runner_day_iceberg_cluster_v1",
		"runner_day_research_lab_v1",
		"runner_day_signal_pylon_v1",
		"runner_day_surface_material_v1",
	])
	_check("runner_set_day_preload_complete", day_preload == required_day_ids,
		str(day_preload))
