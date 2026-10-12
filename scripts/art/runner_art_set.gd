class_name RunnerArtSet
extends Resource
## Logical runner roles mapped to ArtCatalog IDs.
##
## Gameplay may keep procedural fallback while production_ready is false.

const SCHEMA_VERSION: int = 1
const REQUIRED_BIOMES: PackedStringArray = ["day", "dusk", "cave", "night"]
const REQUIRED_OBSTACLES: PackedStringArray = ["block", "bar", "low", "ramp", "seal"]
const REQUIRED_PICKUPS: PackedStringArray = ["fish", "powerup"]

@export_category("Identity")
@export var schema_version: int = SCHEMA_VERSION
@export var set_id: String = ""
@export var display_name: String = ""
@export_multiline var notes: String = ""
@export var production_ready: bool = false
@export var allow_procedural_fallback: bool = true

@export_category("Profiles")
@export var character_look: CharacterLook
@export var course_profiles: Array[CourseVisualProfile] = []

@export_category("Catalog mappings")
@export var deck_scene_ids: Dictionary = {}
@export var obstacle_scene_ids: Dictionary = {}
@export var pickup_scene_ids: Dictionary = {}
@export var dressing_scene_ids: Dictionary = {}
@export var landmark_scene_ids: Dictionary = {}

@export_category("Preload")
@export var common_preload_ids: PackedStringArray = PackedStringArray()
@export var biome_preload_ids: Dictionary = {}


func profile_for_biome(biome_id: String) -> CourseVisualProfile:
	for profile: CourseVisualProfile in course_profiles:
		if profile != null and profile.biome_id == biome_id:
			return profile
	return null


func obstacle_asset_id(kind: String) -> String:
	return String(obstacle_scene_ids.get(kind, ""))


func pickup_asset_id(kind: String) -> String:
	return String(pickup_scene_ids.get(kind, ""))


func collect_preload_ids(biome_id: String) -> PackedStringArray:
	var ids := PackedStringArray()
	for asset_id: String in common_preload_ids:
		_append_unique(ids, asset_id)
	if character_look != null:
		for asset_id: String in character_look.required_asset_ids():
			_append_unique(ids, asset_id)
	_append_unique(ids, String(deck_scene_ids.get(biome_id, "")))
	for mapping: Dictionary in [obstacle_scene_ids, pickup_scene_ids]:
		for asset_id: Variant in mapping.values():
			_append_unique(ids, String(asset_id))
	for mapping: Dictionary in [dressing_scene_ids, landmark_scene_ids, biome_preload_ids]:
		var values: Variant = mapping.get(biome_id, [])
		if values is Array or values is PackedStringArray:
			for asset_id: Variant in values:
				_append_unique(ids, String(asset_id))
	ids.sort()
	return ids


func readiness_gaps() -> PackedStringArray:
	var gaps := PackedStringArray()
	if character_look == null:
		gaps.append("character_look")
	elif not character_look.production_ready:
		gaps.append("character_look:not_ready")
	for biome_id: String in REQUIRED_BIOMES:
		if String(deck_scene_ids.get(biome_id, "")).is_empty():
			gaps.append("deck:%s" % biome_id)
		if profile_for_biome(biome_id) == null:
			gaps.append("profile:%s" % biome_id)
	for kind: String in REQUIRED_OBSTACLES:
		if String(obstacle_scene_ids.get(kind, "")).is_empty():
			gaps.append("obstacle:%s" % kind)
	for kind: String in REQUIRED_PICKUPS:
		if String(pickup_scene_ids.get(kind, "")).is_empty():
			gaps.append("pickup:%s" % kind)
	return gaps


func validation_errors(catalog: ArtCatalog = null) -> PackedStringArray:
	var errors := PackedStringArray()
	if schema_version != SCHEMA_VERSION:
		errors.append("schema_version must be %d" % SCHEMA_VERSION)
	if not _valid_id(set_id):
		errors.append("set_id must be lower_snake_case")
	if display_name.strip_edges().is_empty():
		errors.append("display_name is required")
	if character_look != null:
		for error: String in character_look.validation_errors():
			errors.append("character_look: %s" % error)
	var seen_biomes: Dictionary = {}
	for profile: CourseVisualProfile in course_profiles:
		if profile == null:
			errors.append("course_profiles contains null")
			continue
		if seen_biomes.has(profile.biome_id):
			errors.append("duplicate course profile biome: %s" % profile.biome_id)
		seen_biomes[profile.biome_id] = true
		for error: String in profile.validation_errors():
			errors.append("profile '%s': %s" % [profile.profile_id, error])
	if production_ready:
		if allow_procedural_fallback:
			errors.append("production_ready art set cannot allow procedural fallback")
		for gap: String in readiness_gaps():
			errors.append("production_ready missing %s" % gap)
	if catalog != null:
		for biome_id: String in REQUIRED_BIOMES:
			for asset_id: String in collect_preload_ids(biome_id):
				if not catalog.has_asset(asset_id):
					errors.append("catalog missing asset ID: %s" % asset_id)
	return _deduplicate(errors)


static func _append_unique(values: PackedStringArray, value: String) -> void:
	if not value.is_empty() and value not in values:
		values.append(value)


static func _deduplicate(values: PackedStringArray) -> PackedStringArray:
	var result := PackedStringArray()
	for value: String in values:
		if value not in result:
			result.append(value)
	return result


static func _valid_id(value: String) -> bool:
	if value.is_empty():
		return false
	for index: int in value.length():
		var code := value.unicode_at(index)
		var allowed := code >= 97 and code <= 122
		allowed = allowed or (index > 0 and code >= 48 and code <= 57)
		allowed = allowed or (index > 0 and code == 95)
		if not allowed:
			return false
	return true
