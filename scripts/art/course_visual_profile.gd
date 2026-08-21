class_name CourseVisualProfile
extends Resource
## Renderer-safe look data for one course or runner biome.

const SCHEMA_VERSION: int = 1
const TIERS: PackedStringArray = ["high", "medium", "low"]
const DEFAULT_QUALITY_TIERS: Dictionary = {
	"high": {
		"dressing_density": 1.0,
		"lod_threshold": 1.0,
		"shadow_distance": 90.0,
		"vfx_scale": 1.0,
		"far_chunks": 7,
	},
	"medium": {
		"dressing_density": 0.65,
		"lod_threshold": 2.0,
		"shadow_distance": 55.0,
		"vfx_scale": 0.60,
		"far_chunks": 5,
	},
	"low": {
		"dressing_density": 0.35,
		"lod_threshold": 4.0,
		"shadow_distance": 24.0,
		"vfx_scale": 0.35,
		"far_chunks": 4,
	},
}

@export_category("Identity")
@export var schema_version: int = SCHEMA_VERSION
@export var profile_id: String = ""
@export var display_name: String = ""
@export var biome_id: String = ""
@export_multiline var art_direction: String = ""
@export var approved_for_runtime: bool = false

@export_category("Sky and atmosphere")
@export var sky_top: Color = Color(0.05, 0.35, 0.82)
@export var sky_horizon: Color = Color(0.40, 0.78, 0.96)
@export var ground_horizon: Color = Color(0.28, 0.60, 0.82)
@export var ground_bottom: Color = Color(0.08, 0.32, 0.58)
@export var fog_color: Color = Color(0.40, 0.76, 0.95)
@export_range(0.0, 0.02, 0.0001) var fog_density: float = 0.0016

@export_category("Lighting")
@export var sun_color: Color = Color(1.0, 0.94, 0.76)
@export_range(0.0, 4.0, 0.01) var sun_energy: float = 1.55
@export_range(0.0, 2.0, 0.01) var ambient_energy: float = 0.38
@export var shaft_color: Color = Color(1.0, 0.97, 0.86)

@export_category("Palette")
@export var deck_dark: Color = Color(0.04, 0.18, 0.36)
@export var deck_mid: Color = Color(0.20, 0.52, 0.76)
@export var snow_bright: Color = Color(0.92, 0.99, 1.0)
@export var decorative_accent: Color = Color(1.0, 0.62, 0.14)
@export var collect_color: Color = Color(1.0, 0.82, 0.28)
@export var powerup_color: Color = Color(0.86, 0.42, 1.0)
@export var hazard_color: Color = Color(1.0, 0.30, 0.08)
@export var duck_color: Color = Color(0.16, 0.95, 1.0)
@export var go_color: Color = Color(0.22, 1.0, 0.36)

@export_category("Quality tiers")
@export var quality_tiers: Dictionary = DEFAULT_QUALITY_TIERS.duplicate(true)


func environment_values() -> Dictionary:
	return {
		"sky_top": sky_top,
		"sky_horizon": sky_horizon,
		"ground_horizon": ground_horizon,
		"ground_bottom": ground_bottom,
		"sun": sun_color,
		"sun_energy": sun_energy,
		"fog": fog_color,
		"fog_density": fog_density,
		"ambient": ambient_energy,
		"shaft": shaft_color,
	}


func quality_settings(tier: String) -> Dictionary:
	var selected: Variant = quality_tiers.get(tier, quality_tiers.get("medium", {}))
	return (selected as Dictionary).duplicate(true) if selected is Dictionary else {}


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if schema_version != SCHEMA_VERSION:
		errors.append("schema_version must be %d" % SCHEMA_VERSION)
	if not _valid_id(profile_id):
		errors.append("profile_id must be lower_snake_case")
	if not _valid_id(biome_id):
		errors.append("biome_id must be lower_snake_case")
	if display_name.strip_edges().is_empty():
		errors.append("display_name is required")
	if fog_density < 0.0 or fog_density > 0.02:
		errors.append("fog_density must be between 0 and 0.02")
	if sun_energy < 0.0 or ambient_energy < 0.0:
		errors.append("lighting energy cannot be negative")
	for tier: String in TIERS:
		if not quality_tiers.has(tier) or not quality_tiers[tier] is Dictionary:
			errors.append("quality_tiers missing '%s'" % tier)
			continue
		var values: Dictionary = quality_tiers[tier]
		for key: String in ["dressing_density", "lod_threshold", "shadow_distance", "vfx_scale", "far_chunks"]:
			if not values.has(key):
				errors.append("quality tier '%s' missing %s" % [tier, key])
		var density := float(values.get("dressing_density", -1.0))
		var vfx := float(values.get("vfx_scale", -1.0))
		if density < 0.0 or density > 1.0:
			errors.append("quality tier '%s' dressing_density outside 0..1" % tier)
		if vfx < 0.0 or vfx > 1.0:
			errors.append("quality tier '%s' vfx_scale outside 0..1" % tier)
		if float(values.get("lod_threshold", 0.0)) <= 0.0:
			errors.append("quality tier '%s' lod_threshold must be positive" % tier)
		if float(values.get("shadow_distance", -1.0)) < 0.0:
			errors.append("quality tier '%s' shadow_distance cannot be negative" % tier)
		if int(values.get("far_chunks", 0)) < 1 or int(values.get("far_chunks", 0)) > 7:
			errors.append("quality tier '%s' far_chunks must be 1..7" % tier)
	return errors


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
