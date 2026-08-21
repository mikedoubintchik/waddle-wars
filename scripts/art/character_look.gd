class_name CharacterLook
extends Resource
## Data-only character presentation contract.
##
## Resource stores catalog IDs instead of loading scenes directly. This keeps
## menus and runner art sets cheap until ArtCatalog explicitly preloads them.

const SCHEMA_VERSION: int = 1
const MAX_DEFORM_BONES: int = 36
const MAX_SKIN_INFLUENCES: int = 4
const MAX_SURFACES: int = 2
const MIN_LOD0_TRIANGLES: int = 18_000
const MAX_LOD0_TRIANGLES: int = 25_000

enum RenderRole {
	HERO,
	RACER,
	GHOST,
	CROWD,
}

const REQUIRED_ANIMATIONS: PackedStringArray = [
	"countdown_idle",
	"fidget",
	"run",
	"lean_left",
	"lean_right",
	"jump_takeoff",
	"jump_air",
	"jump_land",
	"slide_enter",
	"slide_loop",
	"slide_exit",
	"ramp_launch",
	"ramp_flip",
	"ramp_land",
	"swim",
	"shove",
	"hit_left",
	"hit_right",
	"stumble",
	"recover",
	"wipeout",
	"defeat",
	"celebration",
]

const REQUIRED_SOCKETS: PackedStringArray = [
	"head_socket",
	"face_socket",
	"neck_socket",
	"trail_socket",
]

@export_category("Identity")
@export var schema_version: int = SCHEMA_VERSION
@export var look_id: String = ""
@export var display_name: String = ""
@export var species_id: String = "emperor"
@export_enum("Hero", "Racer", "Ghost", "Crowd") var render_role: int = RenderRole.HERO
@export_multiline var notes: String = ""
@export var production_ready: bool = false

@export_category("Catalog assets")
@export var body_scene_id: String = ""
@export var animation_library_id: String = ""
@export var material_set_id: String = ""
@export var accessory_scene_ids: Dictionary = {}

@export_category("Equipped cosmetics")
@export var hat_id: String = ""
@export var scarf_id: String = ""
@export var goggles_id: String = ""
@export var trail_id: String = ""

@export_category("Presentation")
@export var body_color: Color = Color(0.13, 0.16, 0.22)
@export var belly_color: Color = Color(0.95, 0.94, 0.90)
@export var identity_color: Color = Color(0.36, 0.78, 1.0)
## Compatibility looks with no legacy accent preserve PenguinVisual's
## species-authored identity rim instead of forcing the generic default.
@export var inherit_species_identity_color: bool = false
@export var visual_offset: Vector3 = Vector3.ZERO
@export var visual_rotation_degrees: Vector3 = Vector3.ZERO
@export var visual_scale: Vector3 = Vector3.ONE

@export_category("Rig contract")
@export var animation_names: Dictionary = {
	"countdown_idle": "countdown_idle",
	"fidget": "fidget",
	"run": "run",
	"lean_left": "lean_left",
	"lean_right": "lean_right",
	"jump_takeoff": "jump_takeoff",
	"jump_air": "jump_air",
	"jump_land": "jump_land",
	"slide_enter": "slide_enter",
	"slide_loop": "slide_loop",
	"slide_exit": "slide_exit",
	"ramp_launch": "ramp_launch",
	"ramp_flip": "ramp_flip",
	"ramp_land": "ramp_land",
	"swim": "swim",
	"shove": "shove",
	"hit_left": "hit_left",
	"hit_right": "hit_right",
	"stumble": "stumble",
	"recover": "recover",
	"wipeout": "wipeout",
	"defeat": "defeat",
	"celebration": "celebration",
}
@export var socket_names: PackedStringArray = REQUIRED_SOCKETS.duplicate()
@export_range(1, MAX_DEFORM_BONES, 1) var deform_bones: int = 32
@export_range(1, MAX_SKIN_INFLUENCES, 1) var skin_influences: int = 4
@export_range(1, MAX_SURFACES, 1) var surface_count: int = 2
@export_range(1, MAX_LOD0_TRIANGLES, 1) var lod0_triangles: int = 25_000


func animation_name(logical_name: String) -> StringName:
	return StringName(String(animation_names.get(logical_name, logical_name)))


func cosmetic_ids() -> Dictionary:
	return {
		"hat": hat_id,
		"scarf": scarf_id,
		"goggles": goggles_id,
		"trail": trail_id,
	}


func to_legacy_config() -> Dictionary:
	var config := {
		"species": species_id,
		"body_color": body_color,
		"belly_color": belly_color,
		"hat": hat_id,
		"scarf": scarf_id,
		"goggles": goggles_id,
		"trail": trail_id,
	}
	if not inherit_species_identity_color:
		config["accent_color"] = identity_color
	return config


func required_asset_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for asset_id: String in [body_scene_id, animation_library_id, material_set_id]:
		_append_unique(ids, asset_id)
	var keys: Array = accessory_scene_ids.keys()
	keys.sort()
	for key: Variant in keys:
		_append_unique(ids, String(accessory_scene_ids[key]))
	ids.sort()
	return ids


func readiness_gaps() -> PackedStringArray:
	var gaps := PackedStringArray()
	if body_scene_id.is_empty():
		gaps.append("body_scene_id")
	if animation_library_id.is_empty():
		gaps.append("animation_library_id")
	for logical_name: String in REQUIRED_ANIMATIONS:
		if String(animation_names.get(logical_name, "")).is_empty():
			gaps.append("animation:%s" % logical_name)
	for socket_name: String in REQUIRED_SOCKETS:
		if socket_name not in socket_names:
			gaps.append("socket:%s" % socket_name)
	return gaps


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if schema_version != SCHEMA_VERSION:
		errors.append("schema_version must be %d" % SCHEMA_VERSION)
	if not _valid_id(look_id):
		errors.append("look_id must be lower_snake_case")
	if display_name.strip_edges().is_empty():
		errors.append("display_name is required")
	if not _valid_id(species_id):
		errors.append("species_id must be lower_snake_case")
	if render_role < RenderRole.HERO or render_role > RenderRole.CROWD:
		errors.append("render_role is invalid")
	if visual_scale.x <= 0.0 or visual_scale.y <= 0.0 or visual_scale.z <= 0.0:
		errors.append("visual_scale components must be positive")
	if deform_bones > MAX_DEFORM_BONES:
		errors.append("deform_bones exceeds %d" % MAX_DEFORM_BONES)
	if skin_influences > MAX_SKIN_INFLUENCES:
		errors.append("skin_influences exceeds %d" % MAX_SKIN_INFLUENCES)
	if surface_count > MAX_SURFACES:
		errors.append("surface_count exceeds %d" % MAX_SURFACES)
	if lod0_triangles > MAX_LOD0_TRIANGLES:
		errors.append("lod0_triangles exceeds %d" % MAX_LOD0_TRIANGLES)
	if production_ready and lod0_triangles < MIN_LOD0_TRIANGLES:
		errors.append("production lod0_triangles below %d" % MIN_LOD0_TRIANGLES)
	if production_ready and inherit_species_identity_color:
		errors.append("production identity_color must be explicit")
	for key: Variant in accessory_scene_ids.keys():
		if not _valid_id(String(key)):
			errors.append("accessory key '%s' must be lower_snake_case" % String(key))
		if not _valid_id(String(accessory_scene_ids[key])):
			errors.append("accessory '%s' has invalid catalog ID" % String(key))
	if production_ready:
		for gap: String in readiness_gaps():
			errors.append("production_ready missing %s" % gap)
	return errors


## Builds a compatibility look from SaveManager's `equipped` dictionary.
## Passing the whole save dictionary is also accepted for low-risk callers.
static func from_equipped(equipped_or_save: Dictionary,
		role: int = RenderRole.HERO) -> CharacterLook:
	var equipped: Dictionary = equipped_or_save
	var nested: Variant = equipped_or_save.get("equipped", null)
	if nested is Dictionary:
		equipped = nested
	var body_id := String(equipped.get("body", "body_classic"))
	var body_info: Dictionary = CosmeticsDB.get_item(body_id)
	if body_info.is_empty():
		body_info = CosmeticsDB.get_item("body_classic")
	var config := body_info.duplicate(true)
	config["hat"] = String(equipped.get("hat", ""))
	config["scarf"] = String(equipped.get("scarf", ""))
	config["goggles"] = String(equipped.get("goggles", ""))
	config["trail"] = String(equipped.get("trail", ""))
	config["display_name"] = String(body_info.get("name", body_id))
	return from_legacy_config(config, role)


## Accepts dictionaries currently sent to PenguinVisual.setup(), including AI
## personality rows whose single `hat` field may contain any cosmetic category.
static func from_legacy_config(config: Dictionary,
		role: int = RenderRole.RACER) -> CharacterLook:
	var result := CharacterLook.new()
	result.render_role = clampi(role, RenderRole.HERO, RenderRole.CROWD)
	result.species_id = _resolve_species(config)
	result.look_id = "legacy_%s_%s" % [_role_name(result.render_role), result.species_id]
	result.display_name = String(config.get("display_name", config.get("name", result.species_id.capitalize())))
	var body_value: Variant = config.get("body_color", result.body_color)
	if body_value is Color:
		result.body_color = body_value
	var belly_value: Variant = config.get("belly_color", result.belly_color)
	if belly_value is Color:
		result.belly_color = belly_value
	var accent_value: Variant = config.get("accent_color", null)
	if accent_value is Color:
		result.identity_color = accent_value
	else:
		result.inherit_species_identity_color = true
	result.hat_id = String(config.get("hat", ""))
	result.scarf_id = String(config.get("scarf", ""))
	result.goggles_id = String(config.get("goggles", ""))
	result.trail_id = String(config.get("trail", ""))
	result._normalize_cosmetic_categories()
	result.notes = "Compatibility CharacterLook derived from legacy presentation config; authored catalog assets not assigned."
	result.production_ready = false
	return result


func _normalize_cosmetic_categories() -> void:
	# Rival configs historically route every accessory through `hat`. Preserve
	# the ID while moving it to its actual semantic socket.
	if hat_id.is_empty():
		return
	var info: Dictionary = CosmeticsDB.get_item(hat_id)
	match String(info.get("category", "hat")):
		"scarf":
			if scarf_id.is_empty():
				scarf_id = hat_id
			hat_id = ""
		"goggles":
			if goggles_id.is_empty():
				goggles_id = hat_id
			hat_id = ""
		"trail":
			if trail_id.is_empty():
				trail_id = hat_id
			hat_id = ""


static func _resolve_species(config: Dictionary) -> String:
	var explicit := String(config.get("species", ""))
	if _valid_id(explicit):
		return explicit
	var body_value: Variant = config.get("body_color", null)
	if body_value is Color:
		var wanted := (body_value as Color).to_html(false)
		for cosmetic_id: String in CosmeticsDB.ITEMS.keys():
			var item: Dictionary = CosmeticsDB.ITEMS[cosmetic_id]
			if String(item.get("category", "")) != "body":
				continue
			var candidate: Variant = item.get("body_color", null)
			if candidate is Color and (candidate as Color).to_html(false) == wanted:
				return String(item.get("species", "emperor"))
	return "emperor"


static func _role_name(role: int) -> String:
	match role:
		RenderRole.RACER:
			return "racer"
		RenderRole.GHOST:
			return "ghost"
		RenderRole.CROWD:
			return "crowd"
		_:
			return "hero"


static func _append_unique(values: PackedStringArray, value: String) -> void:
	if not value.is_empty() and value not in values:
		values.append(value)


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
