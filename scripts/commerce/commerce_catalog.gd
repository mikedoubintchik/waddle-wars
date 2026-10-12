class_name CommerceCatalog
extends RefCounted
## Cosmetic non-consumables only. Native prices come from the platform store;
## web prices come from the server. This packaged catalog is not a grant source.

const PATH: String = "res://data/commerce/catalog.json"
static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if parsed is Dictionary:
			_data = parsed
	return _data.duplicate(true)


static func products() -> Array:
	return data().get("products", [])


static func product(id: String) -> Dictionary:
	for item: Dictionary in products():
		if String(item.get("id", "")) == id:
			return item
	return {}


static func from_store_id(id: String, provider: String) -> Dictionary:
	for item: Dictionary in products():
		if String(item.get("%s_product_id" % provider, "")) == id:
			return item
	return {}


static func cosmetic_ids(product_ids: Array) -> Array[String]:
	var ids: Array[String] = []
	for value: Variant in product_ids:
		if not value is String:
			continue
		for cosmetic: String in product(String(value)).get("cosmetics", []):
			if not ids.has(cosmetic):
				ids.append(cosmetic)
	ids.sort()
	return ids


static func disclosure() -> String:
	return String(data().get("disclosure", ""))
