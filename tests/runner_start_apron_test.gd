extends Node
## The opening runway must meet the first playable ice surface exactly. A
## small height step draws a full-width line beside the idle penguin's feet.

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	var art_set := load("res://data/art/runner_art_set_foundation.tres") as RunnerArtSet
	var catalog := ArtCatalog.new()
	catalog.manifest_path = "res://tests/fixtures/art/runner_day_kit_catalog.json"
	_check("catalog_ready", catalog.reload_manifest() == OK)
	for authored: bool in [true, false]:
		var label := "authored" if authored else "procedural"
		var track := RunnerTrack.new()
		add_child(track)
		if authored:
			track.configure_art(art_set, catalog)
			track._prime_authored_day_cache()
		var chunk := RunnerTrack.RunnerChunk.new()
		chunk.index = 0
		chunk.biome = RunnerTrack.Biome.DAY
		track.add_child(chunk)
		track._chunks.append(chunk)
		track._build_deck(chunk, RunnerTrack.Pattern.OPEN)
		track._build_start_apron()
		var deck := chunk.get_node_or_null("GlacialIceSkin" if authored else "Deck") \
				as MeshInstance3D
		var apron := track.get_node_or_null("StartApron/StartIce") as MeshInstance3D
		_check(label + "_surfaces_exist", deck != null and apron != null)
		if deck != null and apron != null:
			var deck_bounds := deck.transform * deck.mesh.get_aabb()
			var apron_bounds := apron.transform * apron.mesh.get_aabb()
			_check(label + "_coplanar", is_equal_approx(
					deck_bounds.position.y, apron_bounds.position.y))
			_check(label + "_touch_at_start", is_zero_approx(deck_bounds.end.z)
					and is_zero_approx(apron_bounds.position.z))
			_check(label + "_same_width", is_equal_approx(
					deck_bounds.size.x, apron_bounds.size.x))
			_check(label + "_same_material", deck.material_override == apron.material_override)
			_check(label + "_no_collision_change", track.floor_y_at(0.0) == 0.0
					and track.get_node("StartApron").find_children(
							"*", "CollisionObject3D", true, false).is_empty())
		track.free()
	print("[runner_start_apron] %d/%d passed" % [_checks - _failures, _checks])
	get_tree().quit(0 if _failures == 0 else 1)


func _check(label: String, passed: bool) -> void:
	_checks += 1
	if not passed:
		_failures += 1
	print("  %s %s" % ["PASS" if passed else "FAIL", label])
