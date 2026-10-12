extends Node
## Required release gate, intentionally red until all 480 reviewed files exist.
const LIBRARY = preload("res://scripts/ui/wardrobe_outfit_library.gd")

func _ready() -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(LIBRARY.MANIFEST_PATH))
	var failures: Array[String] = []
	var checked := 0
	if not manifest is Dictionary or not manifest.get("entries") is Dictionary:
		push_error("[wardrobe-catalog] Invalid outfit manifest")
		get_tree().quit(1)
		return
	var entries: Dictionary = manifest["entries"]
	var hats: Array[String] = [""]
	var goggles: Array[String] = [""]
	var scarves: Array[String] = [""]
	hats.append_array(CosmeticsDB.items_in_category("hat"))
	goggles.append_array(CosmeticsDB.items_in_category("goggles"))
	scarves.append_array(CosmeticsDB.items_in_category("scarf"))
	var expected: Dictionary = {}
	for body: String in CosmeticsDB.items_in_category("body"):
		for hat: String in hats:
			for eyewear: String in goggles:
				for scarf: String in scarves:
					var look := {"body": body, "hat": hat, "goggles": eyewear, "scarf": scarf}
					var key := LIBRARY.outfit_key(look)
					expected[key] = true
					var entry: Variant = entries.get(key)
					if not entry is Dictionary:
						failures.append("missing:" + key)
						continue
					var path := String(entry.get("runtime", ""))
					var correct := path == LIBRARY.ASSET_PREFIX + key + ".webp" and ResourceLoader.exists(path)
					for slot: String in look:
						correct = correct and String(entry.get(slot, "")) == ("none" if String(look[slot]).is_empty() else String(look[slot]))
					correct = correct and String(entry.get("runtime_sha256", "")).length() == 64 and FileAccess.get_sha256(path) == String(entry.get("runtime_sha256", ""))
					if correct:
						# Decode every admitted import without retaining the 480-image library.
						var texture := ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
						correct = texture != null and texture.get_width() == 512 and texture.get_height() > 0
						if correct:
							var decoded := texture.get_image()
							correct = decoded != null and not decoded.is_invisible() \
								and decoded.detect_alpha() != Image.ALPHA_NONE and decoded.has_mipmaps()
							decoded = null
						texture = null
					if correct: checked += 1
					else: failures.append("invalid:" + key)
	for key: String in entries:
		if not expected.has(key): failures.append("unknown:" + key)
	if expected.size() != LIBRARY.EXPECTED_OUTFITS or int(manifest.get("expected", 0)) != LIBRARY.EXPECTED_OUTFITS:
		failures.append("catalog dimension mismatch")
	print("[wardrobe-catalog] %d/%d complete, hash-verified and loaded transparent mipmapped outfits; %d failures" % [checked, LIBRARY.EXPECTED_OUTFITS, failures.size()])
	if not failures.is_empty():
		print("[wardrobe-catalog] ", ", ".join(failures.slice(0, 8)))
	get_tree().quit(0 if failures.is_empty() else 1)
